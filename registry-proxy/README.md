# Кеширующий прокси для docker registry

## 1. Создание контейнера

```bash
    sudo lxc launch ubuntu:22.04 docker-registry --profile default --profile kubernates
    
    sudo lxc exec docker-registry -- sh -c "apt update && apt install -y docker.io"
    
```

## 2. Установка и настройка прокси

```bash
    sudo lxc exec docker-registry -- sh -c 'cat <<EOF | sudo tee /config.yml > /dev/null
version: 0.1

proxy:
  remoteurl: https://registry-1.docker.io
  maxduration: 0  # бесконечное кэширование

storage:
  filesystem:
    rootdirectory: /var/lib/registry

http:
  addr: :5000
EOF'

    sudo lxc exec docker-registry -- sh -c "docker run -d --restart=always --name docker-registry \
      -v /opt/registry-data:/var/lib/registry \
      -v $(pwd)/config.yml:/etc/docker/registry/config.yml \
      -p 5000:5000 \
      registry:2"

```

## 3. Настройка k3s для получения образов с использованием прокси

```bash
    sudo lxc exec k3s-master -- sh -c "sudo mkdir -p /etc/rancher/k3s && echo 'mirrors:\n  \"docker.io\":\n    endpoint:\n      - \"http://`lxc list docker-registry --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:5000\"\nconfigs:\n  \"`lxc list docker-registry --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:5000\":\n    tls:\n      insecure_skip_verify: true' | sudo tee /etc/rancher/k3s/registries.yaml"
    sudo lxc exec k3s-worker1 -- sh -c "sudo mkdir -p /etc/rancher/k3s && echo 'mirrors:\n  \"docker.io\":\n    endpoint:\n      - \"http://`lxc list docker-registry --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:5000\"\nconfigs:\n  \"`lxc list docker-registry --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:5000\":\n    tls:\n      insecure_skip_verify: true' | sudo tee /etc/rancher/k3s/registries.yaml"
    ...
```

## 4. Прокси для нескольких репозиториев

docker registry умеет проксировать только один репозиторий, 
если нужно проксировать несколько,
то потребуется поднять фасадный прокси (с возможностью L7 балансировки) для маршрутизации запросов в разные прокси репозитории.

Пример конфига для двух репозиториев [caddy](reg_proxy.Caddyfile)

Контейнер с caddy
```shell
docker run -d --name caddy-proxy --restart=always \
    -v $(pwd)/reg_proxy.Caddyfile:/etc/caddy/Caddyfile:ro \
    --net=host \
    caddy:2
```

Для его работу нужно поднять 2 прокси репозитория для контейнеров на портах 5001 и 5002 