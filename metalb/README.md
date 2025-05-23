# Развертывание балансировщика MetalLB

Для создания высокодоступного способа доступа к сервисам k3s в сети lxc контейнеров нужно использовать канальный уровень (L2) работы MetalLB

## 1. Установка и настройка MetalLB

```shell

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

```

Дождаться пока все поды поднимутся

```shell
  kubectl -n metallb-system wait --for=condition=ready pod --all --timeout=300s
```

Развернуть [манифест](config.yaml) для создания пула адресов доступных балансировщику

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.0.0.100-10.0.0.200  # Диапазон для LoadBalancer'ов
```
И анонсировать этот пул в сети (чтобы остальные ноды с агентами бузнали о доступном пуле адресов)
```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
```

```shell
  kubectl apply -f config.yaml
```

## Детали работы MetalLB в режиме L2

По сути MetalLB в этом режиме не является балансировщиком, а предоставляет высокодоступный IP адрес

Компонент Speaker (это агент балансировщика) запускается как DaemonSet (по одному на ноду).

Компонент Controller управляет логикой MetalLB.
Он следит за Kubernetes API, наблюдает за сервисами типа LoadBalancer, IP-пулами, и нодами

Когда создается Service типа LoadBalancer, Controller берет из пула адресов свободный ip
и назначает один из подов Speaker владельцем (управленцем) этого ip. 
Pod сообщает о владении остальным узлам кластера (точнее подам Speaker на этих узлах), рассылает AGRP запросы (типа этот ip находится на "устройстве" с данным mac адресом)

Управляющий адресом слушает ARP в сети запросы с помощью которых все "устройства" в сети для выясняют на какой ноде находится нужный IP.
```
+----------------+         ARP        +------------+        Pod
|   Пользователь | -----> Who has? -->|   MetalLB  |------> SVC/Pod
+----------------+   <--- It's me! ---+------------+
(10.0.0.101 -> MAC ноды)

```
При последующей отправке сетевых пакетов на этот ip запросы приходят на ноду (точнее на интерфейс с MAC адресом ноды) 
и далее kube-proxy (или другой CNI-плагин) решает как распределить трафик:

- iptables (или ipvs/ebpf) для DNAT/маршрутизации;

- перенаправляет входящие пакеты на соответствующий Service;

- раздаёт их по Endpoints (Pod'ам), по ClusterIP, NodePort, или напрямую (если настроен externalTrafficPolicy: Local или Cluster).

Если нода падает (Controller получает уведомление что нода NotReady), то Controller переназначает ip на другую ноду