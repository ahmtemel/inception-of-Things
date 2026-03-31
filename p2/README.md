# Part 2 — K3s + 3 Web Uygulaması + Ingress (Traefik)

Bu README Part 2'yi derinlemesiyle açıklar: mimari, araçlar, manifestler, request akışı, test stratejisi ve savunmada ne söyleneceği.

---

## 1) Part 2'nin Amacı

**Tek bir VM** üzerinde, 3 web uygulaması barındıran bir Kubernetes ortamı kurmak:

- `app-one` → **Hello from app1.** (1 replica)
- `app-two` → **Hello from app2.** (3 replica)
- `app-three` → **Hello from app3.** (1 replica, default backend)

Yönlendirme **Ingress (Traefik)** tarafından HTTP Host header'ına göre yapılır:

| Domain | Uygulama |
|--------|----------|
| `app1.com` | app-one |
| `app2.com` | app-two |
| `app3.com` | app-three |
| `denden.com` (veya eşleşmeyen herhangi bir host) | app-three (default) |

---

## 2) Kullanılan Programlar

### libvirt / KVM
- Sanal makineyi çalıştıran hypervisor.
- `vagrant-libvirt` plugin'i ile Vagrant tarafından yönetilir.
- `host-passthrough` CPU modu, nested virtualization, `virtio` NIC aktif.

### Vagrant
- VM oluşturma ve provisioning otomasyon aracı.
- `vagrant up` sonrası `trigger` ile host'un `/etc/hosts` dosyasını otomatik günceller.

### Debian Bookworm (`debian/bookworm64`)
- Hafif ve kararlı base OS image.

### K3s
- Part 2'de single-node **server mode** olarak çalışır.
- Deployment, Service, Ingress kaynaklarını destekler.

### Traefik (Ingress Controller)
- K3s'e varsayılan olarak dahil gelir.
- Ingress kaynaklarını izler ve HTTP trafiğini yönlendirir.

### nginx (`nginx:stable-alpine`)
- 3 uygulamanın web server'ı.
- Multi-arch uyumlu, hafif ve stabil.

### busybox initContainer
- Pod başlamadan önce uygulamaya özgü HTML oluşturur (pod hostname dahil).

---

## 3) Mimari

```
Host Machine
└── KVM (libvirt)
    └── VM: aliS (192.168.56.110)
        ├── K3s Server (single-node cluster)
        ├── app-one  Deployment (1 pod) + Service
        ├── app-two  Deployment (3 pod) + Service
        ├── app-three Deployment (1 pod) + Service
        └── Ingress (Traefik kuralları)
```

Request akışı:
1. `192.168.56.110`'a istek gelir
2. Traefik alır
3. `Host` header'ına bakar
4. Eşleşen Service'e yönlendirir
5. Service pod'lardan birine load balance eder

---

## 4) Dosya Yapısı

```
p2/
├── Vagrantfile
├── scripts/
│   ├── server_setup.sh       # VM içinde çalışır
│   └── update_hosts.sh       # Host Mac'te çalışır (trigger ile)
└── confs/
    ├── app-one.yaml
    ├── app-two.yaml
    ├── app-three.yaml
    └── ingress.yaml
```

### `Vagrantfile`
- Tek VM tanımlar: `aliS`, IP `192.168.56.110`, 1 CPU, 1024 MB RAM.
- libvirt provider: `host-passthrough`, `nested: true`, `virtio`, `scsi`.
- `vagrant up` sonrası `trigger` ile `scripts/update_hosts.sh` çalıştırır.

### `scripts/server_setup.sh`
VM içinde çalışır:
1. `curl` kurulur
2. K3s server kurulur (`--node-ip`, `--bind-address`, `--advertise-address`, `--flannel-iface=eth1`)
3. `vagrant` kullanıcısına `kubectl` PATH ve KUBECONFIG otomatik ayarlanır
4. Cluster node `Ready` olana kadar beklenir
5. Tüm Kubernetes manifestleri apply edilir

### `scripts/update_hosts.sh`
Host Mac üzerinde çalışır (`vagrant up` trigger'ı ile):
- `app1.com`, `app2.com`, `app3.com`, `denden.com` → `192.168.56.110`
- `grep` ile kontrol eder, zaten varsa tekrar eklemez (şişirme yok)

### `confs/app-*.yaml`
Her dosya: bir `Deployment` + bir `ClusterIP Service`

### `confs/ingress.yaml`
Traefik Ingress kuralları:
- `app1.com` → `app-one:80`
- `app2.com` → `app-two:80`
- `app3.com` → `app-three:80` (explicit)
- eşleşmeyen host (örn. `denden.com`) → `app-three:80` (default)

---

## 5) Kubernetes Kavramları

| Kavram | Açıklama |
|--------|----------|
| **Pod** | Çalışan en küçük birim. Her pod bir nginx container içerir. |
| **Deployment** | İstenilen pod sayısının sürekli çalışmasını garantiler. |
| **Service (ClusterIP)** | Pod'lar için stabil internal endpoint. |
| **Ingress** | Layer-7 HTTP routing kaynağı. |
| **Ingress Controller** | Ingress kurallarını uygulayan process (Traefik). |
| **initContainer + emptyDir** | nginx başlamadan önce `index.html` yazar, `emptyDir` ile paylaşır. |

---

## 6) Nasıl Çalıştırılır

```bash
cd p2
vagrant destroy -f
vagrant up
```

`vagrant up` bittikten sonra Mac'te `/etc/hosts` otomatik güncellenir. Browser'dan direkt açılabilir.

SSH:
```bash
vagrant ssh aliS
```

SSH sonrası `kubectl` direkt çalışır (PATH ve KUBECONFIG otomatik ayarlıdır).

---

## 7) Test Adımları

### Cluster durumu (VM içinde)
```bash
kubectl get nodes          # aliS Ready
kubectl get pods -A        # 5 pod: 1+3+1
kubectl get svc            # app-one, app-two, app-three
kubectl get ingress        # app-ingress
```

### curl testi (VM içinde)
```bash
curl -H "Host: app1.com" 192.168.56.110    # Hello from app1.
curl -H "Host: app2.com" 192.168.56.110    # Hello from app2.
curl -H "Host: app3.com" 192.168.56.110    # Hello from app3.
curl -H "Host: denden.com" 192.168.56.110  # Hello from app3. (default)
curl 192.168.56.110                         # Hello from app3. (no host)
```

### app-two load balancing testi
```bash
for i in {1..10}; do curl -s -H "Host: app2.com" 192.168.56.110 | grep Pod; done
# Pod adı farklı replica'lar arasında değişmeli
```

### Browser testi (Mac'te)
`vagrant up` sonrası `/etc/hosts` otomatik güncellendiği için direkt açılır:
- `http://app1.com` → Hello from app1.
- `http://app2.com` → Hello from app2.
- `http://app3.com` → Hello from app3.
- `http://denden.com` → Hello from app3. (default backend)

---

## 8) Hızlı Doğrulama Kontrol Listesi

- [ ] `kubectl get nodes` → `aliS` Ready
- [ ] `kubectl get pods` → 5 pod toplam (1+3+1)
- [ ] `kubectl get svc` → `app-one`, `app-two`, `app-three`
- [ ] `kubectl get ingress` → `app-ingress`
- [ ] `curl -H "Host:app1.com" 192.168.56.110` → app1 mesajı
- [ ] `curl -H "Host:app2.com" 192.168.56.110` → app2 mesajı
- [ ] `curl 192.168.56.110` → app3 mesajı
- [ ] Tekrar app2 isteği farklı pod hostname gösteriyor

---

## 9) Sorun Giderme

### Ingress 404 döndürüyor
```bash
kubectl get ingress
kubectl get pods -n kube-system | grep -i traefik
```

### Servisler var ama uygulama erişilemiyor
```bash
kubectl get pods
kubectl logs deploy/app-one
```

### kubectl: command not found
```bash
export PATH=$PATH:/usr/local/bin
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```
(Kalıcı için: `~/.bashrc`'ye eklenir — `server_setup.sh` bunu otomatik yapar)

### VM provisioning takıldı/başarısız
```bash
vagrant destroy -f && vagrant up
```

---

## 10) Savunmada Açıklanacak Noktalar

1. **Amaç**: Tek node K3s cluster, 3 uygulama, host tabanlı HTTP yönlendirme.
2. **Altyapı**: Vagrant → Debian VM → statik private IP.
3. **Cluster bootstrap**: K3s kurulumu, node ready bekleme.
4. **Workload'lar**: 3 Deployment + Service, app-two'nun 3 replica'sı.
5. **Traffic**: Ingress + Traefik → Host header'a göre yönlendirme.
6. **Default davranış**: Eşleşmeyen host (örn. denden.com) → app-three.
7. **Kanıt**: curl testleri + app-two load balancing, browser testi.

> "Part 2, tek node K3s cluster üzerinde Traefik Ingress ile host tabanlı HTTP yönlendirmesini ve replica tabanlı load balancing'i gösterir."
