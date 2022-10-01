# Studio Wally Server

This is the code for the backend of studio wally that handles requests to install packages and starts a rojo server for serving those packages. I run an up to date version of this server at https://studio-wally.fewkz.com that you're free to use.

## Setting up

### Prerequisites
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl/)
- [Docker Engine](https://docs.docker.com/engine/install/)
- [Skaffold](https://skaffold.dev/)
- A kubernetes cluster to deploy to

### Deploying

You can deploy the backend using Skaffold by doing `skaffold run`. Skaffold requires a image registry to upload the built images to. You can use GitHub for this by passing the `--default-repo ghcr.io/USERNAME/studio-wally` arg. You'll also need to [authenticate with the GitHub container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry).

You'll need to manually deploy a service that's exposed to the internet through kubectl, which can vary by cloud provider. The configuration I used is available at https://gist.github.com/fewkz/a894ce5fe521c86b9713a544697f1deb

## Wally Server

Wally server is a docker image that installs wally packages provided to it as arguments and serves a rojo project with the packages.
You can run the wally-server by doing
```sh
docker run -p 34872:34872 -it ghcr.io/fewkz/studio-wally/wally-server \
'promise = "evaera/promise@4.0.0"' 'testez = "roblox/testez@0.4.1"'
```
