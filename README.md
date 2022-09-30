# Studio Wally

Studio Wally is a plugin for Roblox Studio that lets you install and update [Wally](https://github.com/UpliftGames/wally) packages all from in studio.

This plugin is intended to be used by projects that aren't managed by Rojo, such as prototypes or legacy games.

This plugin relies on the experimental [Rojo headless API](https://github.com/rojo-rbx/rojo/pull/639) to connect to a server for syncing the packages in.
The headless API is currently not available in the main branch of Rojo, and must be installed from a fork,
which is available on the [Roblox Library](https://www.roblox.com/library/11092943149/Rojo-Boatly).

## How to get

You can get the latest version of the plugin from [Roblox Library](https://www.roblox.com/library/11121595926/Studio-Wally),
or download a build of the plugin from [GitHub Releases](https://github.com/fewkz/studio-wally/releases)

You will also need the [Rojo Boatly](https://www.roblox.com/library/11092943149/Rojo-Boatly) plugin installed in order for it to work.

## How to use

The plugin adds two buttons to the plugin toolbar, the "Edit Packages" button will open the studio wally manifest,
which stores the configuration for studio wally and what packages to install.

The "Install Packages" button will send a request to the server to download the packages, which will use Rojo to sync the packages in.

Make sure to check the output if something unexpected happened, as it gives errors when something goes wrong. Feel free to open an issue if you run into any problems.
