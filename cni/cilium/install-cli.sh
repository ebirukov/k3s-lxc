#!/bin/bash

# usage: DISTR_URL=https://github.com/cilium/cilium-cli/releases/download/v0.18.3/ ./install-cli.sh

set -euo pipefail

CILIUM_CLI_VERSION=${CILIUM_CLI_VERSION:-$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)}

GOOS=${GOOS:-"linux"}
GOARCH=${GOARCH:-"amd64"}
DISTR_URL=${DISTR_URL:-"https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}"}

curl -L --remote-name-all "$DISTR_URL"/cilium-${GOOS}-${GOARCH}.tar.gz
sudo tar -C /usr/local/bin -xzvf cilium-${GOOS}-${GOARCH}.tar.gz
rm cilium-${GOOS}-${GOARCH}.tar.gz