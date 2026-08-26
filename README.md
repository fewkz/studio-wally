# Studio Wally

Studio Wally is a plugin for Roblox Studio that lets you install and update [Wally](https://github.com/UpliftGames/wally) packages all from in studio.

## How to get

You can get the latest version of the plugin from [Roblox Library](https://www.roblox.com/library/11121595926/Studio-Wally),
or download a build of the plugin from [GitHub Releases](https://github.com/fewkz/studio-wally/releases)

## How to use

The plugin adds two buttons to the plugin toolbar, the "Edit Packages" button will open the studio wally manifest,
which stores the configuration for studio wally and what packages to install.

The "Install Packages" button will send a request to the server to download the packages and the plugin will add them to your game.

The manifest supports a `packages` field and a `serverPackages` field, which will go into ReplicatedStorage and ServerStorage respectively.

The server used is specified in the studio wally manifest through the `server` field. You can either use `"https://studio-wally.fewkz.com"`
or run the server in this repository yourself.

Studio Wally has wally lockfile support, which pins previously installed package versions in case a new version is published.
You can create a StringValue with the name "StudioWallyLock" inside of ServerStorage, which the plugin will read to
forward to the server when installing packages with wally. After installation, the updated lockfile will be written.

Wally treats the version specified in the manifest as a minimum. Wally will download any package with the same major
version that is higher than the version specified. Therefore downloading `package@1.0.0` may download `package@1.2.0`.
If you want to pin a specific version, you should do `package@=1.0.0`, or use the lockfile feature to keep the version you were using between installs.

### Sample Manifest

Here is a sample studio wally manifest which downloads `roblox/roact@1.4.4` into `ReplicatedStorage.Packages.Roact` and `evaera/promise@4.0.0` into `ServerStorage.Packages.Promise`

```lua
return {
	server = "https://studio-wally.fewkz.com",
	packages = {
		Roact = "roblox/roact@1.4.4",
	},
	serverPackages = {
		Promise = "evaera/promise@4.0.0",
	}
}
```

Make sure to check the output if something unexpected happened, as it gives errors when something goes wrong. Feel free to open an issue if you run into any problems.
