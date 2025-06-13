#!/bin/bash

# usage: DISTR_URL=http://192.168.2.60/k3s MASTER_NODE_NAME=k3s-master ./add-master.sh
# INSTALL_K3S_EXEC="--disable traefik --disable servicelb --flannel-backend=none --disable-network-policy --disable-kube-proxy" MASTER_NODE_NAME=k3s-master ./add-master.sh

set -euo pipefail

DISTR_URL=${DISTR_URL:-""}
INSTALL_SCRIPT_URL=${INSTALL_SCRIPT_URL:-}
INSTALL_K3S_EXEC=${INSTALL_K3S_EXEC:-"--disable traefik --disable servicelb"}
PRIMARY_MASTER_NODE_NAME=${PRIMARY_MASTER_NODE_NAME:-""} # не забыить про --cluster-init

# Включаем трассировку, если произошла ошибка
trap 'echo -e "\n❌ Ошибка на строке $LINENO: $BASH_COMMAND" >&2; set -x' ERR

MASTER_NODE_NAME=${MASTER_NODE_NAME:-$(petname --words 2)}
NODE_NAME=${MASTER_NODE_NAME}
INSTALL_K3S_VERSION=${K3S_VERSION:-v1.32.4+k3s1}

if [[ -n "$DISTR_URL" ]]; then
   INSTALL_SCRIPT_URL=$DISTR_URL/get.k3s.io
   echo "SET INSTALL_SCRIPT_URL="$INSTALL_SCRIPT_URL
fi

if [[ -z "$INSTALL_SCRIPT_URL" ]]; then
    INSTALL_SCRIPT_URL=https://get.k3s.io
    echo "SET DEFAULT INSTALL_SCRIPT_URL"
fi

sudo lxc launch ubuntu:22.04 "$NODE_NAME" --profile default --profile kubernates

while ! sudo lxc exec "$NODE_NAME" -- bash -c "getent hosts $NODE_NAME" > /dev/null 2>&1; do
    echo "Хост $NODE_NAME пока не доступен, ждем..."
    sleep 2
done

if [[ -n "$PRIMARY_MASTER_NODE_NAME" ]]; then
    K3S_TOKEN=$(sudo lxc exec "$PRIMARY_MASTER_NODE_NAME" -- sh -c 'cat /var/lib/rancher/k3s/server/node-token')
    MASTER_IP=$(sudo lxc list "$PRIMARY_MASTER_NODE_NAME" --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address')
    K3S_URL=https://$MASTER_IP:6443
    INSTALL_K3S_EXEC="server --server $K3S_URL --token $K3S_TOKEN $INSTALL_K3S_EXEC "
    echo "устанавливает дополнительная мастер узел ""$K3S_URL""($INSTALL_K3S_EXEC)"
fi

echo "Установка master node k3s из $DISTR_URL версии ""$INSTALL_K3S_VERSION"

echo sudo lxc exec -t "$NODE_NAME" -- bash -c "curl -sfL $INSTALL_SCRIPT_URL | \
    INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION \
    GITHUB_URL=$DISTR_URL \
    INSTALL_K3S_EXEC='$INSTALL_K3S_EXEC' sh -"

sudo lxc exec -t "$NODE_NAME" -- bash -c "curl -sfL $INSTALL_SCRIPT_URL | \
    INSTALL_K3S_VERSION=$INSTALL_K3S_VERSION \
    GITHUB_URL=$DISTR_URL \
    INSTALL_K3S_EXEC='$INSTALL_K3S_EXEC' sh -"

REGISTRY_IP=$(sudo lxc list docker-registry --project default --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address')
REGISTRY_PORT="5000"
REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"

echo "Настраиваем кеширующий репозиторий образов по адресу http://${REGISTRY_IP}:${REGISTRY_PORT}"

sudo lxc exec "$NODE_NAME" -- bash -c '
  mkdir -p /etc/rancher/k3s
  tee /etc/rancher/k3s/registries.yaml
' <<EOF
mirrors:
  "*":
    endpoint:
      - "http://$REGISTRY_IP:$REGISTRY_PORT"
configs:
  "$REGISTRY_IP:$REGISTRY_PORT":
    tls:
      insecure_skip_verify: true
EOF
