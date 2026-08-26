# Studio Wally Server

This is the backend the Studio Wally plugin talks to. The plugin makes a request with the packages to install,
installs them with wally, builds them into an rbxm with rojo, and returns that as the response.

I run an instance of this at https://studio-wally.fewkz.com that you're free to
use, and it's what the plugin points at by default.

## Running it

Requires Python 3.7 or newer, with `wally` and `rojo` on PATH.
[wally-package-types](https://github.com/JohnnyMorganz/wally-package-types) is
optional, but without it the packages won't export their types.

```sh
python server.py 8080
```

You can then update your manifest's `server` field to `"http://localhost:8080"`
and the plugin will communicate with the server locally.
