# k3s-lxc - использования кластера lxc в качестве кластера для k3s

### Преимущества 

- минимальный оверхед от виртуализации, производительность близка к работе на хосте
- [простота создания новой ноды кластер](#4-установка-воркернод)
- минимальное потребление ресурсов, можно поднять кластер из нескольких нод на ноуте
```
NAME          CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
k3s-master    22m          1%       1176Mi          61%         
k3s-worker1   9m           0%       902Mi           47%         
k3s-worker2   7m           0%       751Mi           39% 
```

### Недостатки

- работает только на Linux
- годится только для простого тестового кластера homelab и тестовых сред.

## 1. Установка LXD

Проще всего из [snap](https://snapcraft.io/lxd)

```bash
    snap install lxd
```
При установке в lxd версии 6 настраивается сетевой мост lxdbr0 с NAT 

```bash
    lxc network list | grep lxdbr0
```

и его маршрутизация на хост машине

```bash
    ip route | grep lxdbr0
```

В версиях lxd младше 6, то потребуется вручную

```bash
    lxc network create lxdbr0 \
      ipv4.address=10.0.0.1/24 \
      ipv4.nat=true \
      ipv6.address=none

    lxc profile device add default eth0 nic name=eth0 network=lxdbr0

  # Маршруты для lxdbr0
    sudo ip route add 10.0.0.0/24 dev lxdbr0
    # Разрешаем весь трафик через lxdbr0
    sudo iptables -A FORWARD -i lxdbr0 -j ACCEPT
    sudo iptables -A FORWARD -o lxdbr0 -j ACCEPT
    
    # Включаем NAT для выхода в интернет
    sudo iptables -t nat -A POSTROUTING -s 10.170.100.0/24 ! -d 10.170.100.0/24 -j MASQUERADE
```

Если нужен доступ к lxc контейнерам с хост машины, то нужно прописать

```bash
    lxc network set lxdbr0 ipv4.routing=true
```


# 2. Профиль lxd

```bash
lxc profile create kubernates

# Заполняем профиль конфигурацией
lxc profile set kubernates raw.lxc "lxc.apparmor.profile = unconfined
lxc.cgroup2.devices.allow = a
lxc.mount.entry = /lib/modules /lib/modules none bind,ro 0 0
lxc.mount.entry = /usr/lib/modules /usr/lib/modules none bind,ro 0 0
lxc.mount.auto = proc:rw sys:rw"
lxc profile set kubernates security.nesting "true"
lxc profile set kubernates security.privileged "true"
lxc profile set kubernates limits.cpu "2"
lxc profile set kubernates limits.memory "2GB"

# Настроим устройства для профиля
lxc profile device add kubernates kmsg unix-char path=/dev/kmsg mode=0666
lxc profile device add kubernates kvm unix-char path=/dev/kvm mode=0666
lxc profile device add kubernates tun unix-char path=/dev/net/tun mode=0666
```

# 3. Установка мастерноды

```bash
    sudo lxc launch ubuntu:22.04 k3s-master --profile default --profile kubernates
    
    sudo lxc exec k3s-master -- bash -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--disable traefik --disable servicelb' sh -"
```

Если при попытке запуски контейнеров
```
Error: Failed instance creation: Failed creating instance record: Failed initialising instance: Invalid devices: Failed detecting root disk device: No root device could be found
```
то под контейнеры, нужно настроить сторадж

```bash
    sudo lxc storage create pool dir source=/lxd-storage
    sudo lxc profile device add default root disk path=/ pool=pool
```

Для доступа к контейнеру через kubectl может потребоваться проброс портов
Можно сделать например через отдельный профиль

```bash
    sudo lxc profile create kubectl-proxy
    sudo lxc profile device add kubectl-proxy kubectl-port proxy bind=host listen=tcp:0.0.0.0:6443 connect=tcp:127.0.0.1:6443
    sudo lxc profile apply k3s-master kubectl-proxy kubernates default
```

# 4. Установка воркернод

```bash
    sudo lxc launch ubuntu:22.04 k3s-worker1 --profile default --profile kubernates
    
    sudo lxc exec k3s-worker1 -- bash -c "curl -sfL https://get.k3s.io | \
    K3S_URL=https://`lxc list k3s-master --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:6443 \
    K3S_TOKEN=`lxc exec k3s-master -- sh -c 'cat /var/lib/rancher/k3s/server/node-token'` \
    INSTALL_K3S_EXEC='agent --kubelet-arg=--anonymous-auth=true --kubelet-arg=--client-ca-file=\"\"' sh -"
  
    sudo lxc launch ubuntu:22.04 k3s-worker2 --profile default --profile kubernates
    
    sudo lxc exec k3s-worker2 -- bash -c "curl -sfL https://get.k3s.io | \
    K3S_URL=https://`lxc list k3s-master --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`:6443 \
    K3S_TOKEN=`lxc exec k3s-master -- sh -c 'cat /var/lib/rancher/k3s/server/node-token'` \
    INSTALL_K3S_EXEC='agent' sh -"
```

## 5. Настройка конфига для kubeconfig kubectl на хосте

```shell
# Копируем конфиг k3s на хост
lxc file pull k3s-master/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Меняем localhost на адрес контейнера
sed -i "s/127.0.0.1/`lxc list k3s-master --format json | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address'`/g" ~/.kube/config

# Проверяем доступ
kubectl get nodes
```

## 6. (Опционально) Кеширующий прокси для docker registry

Чтобы каждый lxc контейнер кластера заново не ходил в инет за образами, 
можно настроить [кеширующий прокси](registry-proxy/README.md)

## 7. (Опционально) Развертывание HA-IP 

Встроенный в k3s servicelb для доступа с хост машины может не работать в lxc контейнерах.
Для создания высокодоступных адресов к приложениям в кластере с хост машины можно развернуть [MetalLB](metalb/README.md) в режиме L2
