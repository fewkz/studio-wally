#!/bin/sh
echo "" >> wally.toml
for arg in "$@"; do echo "$arg" >> wally.toml; done
cat wally.toml
wally install
mkdir Packages ServerPackages
rojo serve --address 0.0.0.0