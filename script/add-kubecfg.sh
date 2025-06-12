#!/bin/bash

# deps: apt install yq && apt install jq
# usage: PROJECT_NAME=k3s-cilium MASTER_NODE_NAME=k3s-master KUBE_CONTEXT_NAME=k3s-cilium ./add-kubecfg.sh
set -euo pipefail

MASTER_NODE_NAME=${MASTER_NODE_NAME:-"k3s-master"}
PROJECT_NAME=${PROJECT_NAME:-"default"}
KUBE_CONTEXT_NAME=${KUBE_CONTEXT_NAME:-$MASTER_NODE_NAME}

# Включаем трассировку, если произошла ошибка
trap 'echo -e "\n❌ Ошибка на строке $LINENO: $BASH_COMMAND" >&2; set -x' ERR

lxc file pull "$MASTER_NODE_NAME"/etc/rancher/k3s/k3s.yaml ./k3s.yaml --project "$PROJECT_NAME"
# IP lxc контейнера MASTER_NODE_NAME
IP=${IP:-$(sudo lxc --project "$PROJECT_NAME" list "$MASTER_NODE_NAME" --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address')}

sed -i "s/127.0.0.1/${IP}/g" ./k3s.yaml

yq -i -y --arg name "$KUBE_CONTEXT_NAME" '
  .clusters[0].name = ($name + "-cluster") |
  .contexts[0].name = $name |
  .contexts[0].context.cluster = ($name + "-cluster") |
  .contexts[0].context.user = ($name + "-user") |
  .users[0].name = ($name + "-user")
' ./k3s.yaml

KUBECONFIG=~/.kube/config:./k3s.yaml kubectl config view --flatten > ./merged-kubeconfig

cp ~/.kube/config .
mv ./merged-kubeconfig ~/.kube/config

rm -f ./k3s.yaml

cat ~/.kube/config