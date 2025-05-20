# k3s-lxc

## 1. Установка LXD

Проще всего из [snap](https://snapcraft.io/lxd)

```bash
    snap install lxd
```
При установке настраивается сетевой мост lxdbr0 с NAT 

```bash
    lxc network list | grep lxdbr0
```

и его маршрутизация на хост машине

```bash
    ip route | grep lxdbr0
```

Если нет, то можно вручную

```bash
    lxc network create lxdbr0 \
      ipv4.address=10.0.0.1/24 \
      ipv4.nat=true \
      ipv6.address=none

    lxc profile device add default eth0 nic name=eth0 network=lxdbr0

    sudo ip route add 10.0.0.0/24 dev lxdbr0
```

Если нужен доступ к lxc контейнерам с хост машины, то нужно прописать

```bash
    lxc network set lxdbr0 ipv4.routing=true
```

# 2. Профиль lxd

```bash
lxc profile create kubernates

# Заполняем профиль конфигурацией
lxc profile set kubernates \
limits.cpu "2" \
limits.memory "2GB" \
raw.lxc "lxc.apparmor.profile = unconfined
lxc.cgroup2.devices.allow = a
lxc.mount.entry = /lib/modules /lib/modules none bind,ro 0 0
lxc.mount.entry = /usr/lib/modules /usr/lib/modules none bind,ro 0 0
lxc.mount.auto = proc:rw sys:rw" \
security.nesting "true" \
security.privileged "true"

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
    INSTALL_K3S_EXEC='agent --kubelet-arg=--anonymous-auth=true --kubelet-arg=--client-ca-file=\"\"' sh -"
```
