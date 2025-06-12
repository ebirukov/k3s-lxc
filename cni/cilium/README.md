# Установка cilium

## Подготовка k3s

Для установки cilium в k3 нужно установить мастер ноды с отключенным cni по умолчанию (flannel).
При установки добавить в INSTALL_K3S_EXEC опции --flannel-backend=none --disable-network-policy)

Пример установки из [скрипта](./../../script/add-master.sh)
```bash
INSTALL_K3S_EXEC="--disable traefik --disable servicelb --flannel-backend=none --disable-network-policy" MASTER_NODE_NAME=k3s-master ./add-master.sh
```

## Установка cilium CLI (рекомендуемый способ)

Примеры установки из [скрипта](install-cli.sh)

```shell
# фиксированная версия под linux на x86
DISTR_URL=https://github.com/cilium/cilium-cli/releases/download/v0.18.3/ ./install-cli.sh
# или
CILIUM_CLI_VERSION=v0.18.3 ./install-cli.sh
# последняя версия под arm
GOARCH=arm64 ./install-cli.sh
```

Для запуска нужно иметь настроенный kubectl. Проверка работы после установки

```shell
    cilium status
    # если установить и запускать изнутри lxc и не настроен kubectl то можно --kubeconfig
    cilium status --kubeconfig /etc/rancher/k3s/k3s.yaml
```

## Установки Cilium

```shell

cilium install \
  --version 1.17.4 \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR=$(lxc network show lxdbr0 | grep '^  ipv4.address:' | awk '{print $2}')  \
  --set kubeProxyReplacement=false \
  --set bpf.hostLegacyRouting=false
```