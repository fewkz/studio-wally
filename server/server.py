import json
import shutil
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
PROJECT = ROOT / "default.project.json"
PLACE = ROOT / "place.project.json"
DEFAULT_PORT = 8080
REPOSITORY = "https://github.com/fewkz/studio-wally"
REGISTRY = "https://github.com/UpliftGames/wally-index"
PLUGIN_VERSION = 2
OUTDATED_PLUGIN_REPLY = (
    b'{"status":"Using an old version of the Studio Wally plugin,'
    b' please update to the latest version"}'
)


class BadManifest(Exception):
    pass


def buildManifest(packages, serverPackages) -> str:
    packages = packages or []
    serverPackages = serverPackages or []
    for field, given in (("packages", packages), ("serverPackages", serverPackages)):
        if not isinstance(given, list):
            raise BadManifest(f"{field} must be a list of packages")
        for package in given:
            # Each line of the package list is a single line string
            if not isinstance(package, str) or "\n" in package or "\r" in package:
                raise BadManifest(f"Invalid package {package!r} in {field}")
    return "\n".join(
        [
            "[package]",
            'name = "studio-wally/place"',
            'version = "0.1.0"',
            f'registry = "{REGISTRY}"',
            'realm = "shared"',
            "",
            # Where the plugin ends up putting each folder. Wally needs this to
            # link a server package to a shared one it depends on.
            "[place]",
            'shared-packages = "game.ReplicatedStorage.Packages"',
            'server-packages = "game.ServerStorage.Packages"',
            "",
            "[dependencies]",
            *packages,
            "",
            "[server-dependencies]",
            *serverPackages,
            "",
        ]
    )


def buildPackages(manifest: str):
    warnings = []
    with tempfile.TemporaryDirectory() as scratch:
        work = Path(scratch)
        (work / "wally.toml").write_text(manifest)
        shutil.copy(PROJECT, work / "default.project.json")
        shutil.copy(PLACE, work / "place.project.json")
        subprocess.run(
            ["wally", "install"], cwd=work, capture_output=True, text=True, check=True
        )
        # wally deletes these when there's nothing to install, but rojo needs them.
        (work / "Packages").mkdir(exist_ok=True)
        (work / "ServerPackages").mkdir(exist_ok=True)
        # Without this the link modules don't re-export the package's types.
        if shutil.which("wally-package-types"):
            subprocess.run(
                [
                    "rojo",
                    "sourcemap",
                    "place.project.json",
                    "--output",
                    "sourcemap.json",
                ],
                cwd=work,
                capture_output=True,
                text=True,
                check=True,
            )
            for folder in ("Packages", "ServerPackages"):
                try:
                    subprocess.run(
                        [
                            "wally-package-types",
                            "--sourcemap",
                            "sourcemap.json",
                            folder,
                        ],
                        cwd=work,
                        capture_output=True,
                        text=True,
                        check=True,
                    )
                except subprocess.CalledProcessError as err:
                    output = f"{err.stdout}{err.stderr}"
                    for chunk in output.split("error: Failed to create new link")[:-1]:
                        name = chunk.rsplit("_Index/", 1)[-1].split("/")[0]
                        warnings.append(name.replace("_", "/", 1))
                    print(
                        f"wally-package-types failed on {folder}:{chr(10)}{output}",
                        file=sys.stderr,
                    )
        else:
            print(
                "no wally-package-types, packages won't export types", file=sys.stderr
            )
        subprocess.run(
            ["rojo", "build", "default.project.json", "--output", "packages.rbxm"],
            cwd=work,
            capture_output=True,
            text=True,
            check=True,
        )
        return (work / "packages.rbxm").read_bytes(), warnings


class Handler(BaseHTTPRequestHandler):
    def respond(self, code: int, contentType: str, body: bytes, warning=None):
        self.send_response(code)
        self.send_header("Studio-Wally-Version", str(PLUGIN_VERSION))
        if warning:
            self.send_header("Studio-Wally-Warning", warning)
        self.send_header("Content-Type", contentType)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def logRequest(self):
        placeId = self.headers.get("Roblox-Id")
        self.log_message(
            "%s",
            f"Build requested by place {placeId}" if placeId else "Build requested",
        )
        for name, value in self.headers.items():
            self.log_message("%s", f"  {name}: {value}")

    def logBuild(self, posted, seconds: float):
        count = len(posted.get("packages") or []) + len(
            posted.get("serverPackages") or []
        )
        self.log_message("%s", f"Built {count} packages in {seconds:.1f}s")

    def do_GET(self):
        self.send_response(302)
        self.send_header("Location", REPOSITORY)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        self.logRequest()
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        try:
            posted = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.respond(400, "text/plain", b"Expected a JSON body")
            return
        if not isinstance(posted, dict) or posted.get("version") != PLUGIN_VERSION:
            self.log_message("%s", "Request came from an outdated plugin")
            self.respond(200, "application/json", OUTDATED_PLUGIN_REPLY)
            return
        try:
            manifest = buildManifest(
                posted.get("packages"), posted.get("serverPackages")
            )
        except BadManifest as err:
            self.respond(400, "text/plain", str(err).encode())
            return
        started = time.monotonic()
        try:
            packages, warnings = buildPackages(manifest)
        except subprocess.CalledProcessError as err:
            message = f"{err.cmd[0]} failed:\n{err.stdout}{err.stderr}"
            print(message, file=sys.stderr)
            self.respond(500, "text/plain", message.encode())
            return
        except OSError as err:
            print(err, file=sys.stderr)
            self.respond(500, "text/plain", str(err).encode())
            return
        self.logBuild(posted, time.monotonic() - started)
        warning = (
            f"Types could not be re-exported for {', '.join(warnings)}"
            if warnings
            else None
        )
        self.respond(200, "application/octet-stream", packages, warning)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"Listening on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
