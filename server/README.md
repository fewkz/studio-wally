# Studio Wally Server

This is the code for the backend of studio wally that handles requests to install packages and starts a rojo server for serving those packages.

## Wally Server

Wally server is a docker image that installs wally packages provided to it as arguments and serves a rojo project with the packages.
You can run the wally-server by doing
```sh
docker run -p 34872:34872 -it ghcr.io/fewkz/studio-wally/wally-server \
'promise = "evaera/promise@4.0.0"' 'testez = "roblox/testez@0.4.1"'
```