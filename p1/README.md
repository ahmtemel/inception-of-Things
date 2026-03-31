# Part 1 — K3s Cluster with Vagrant (Server + Worker)

Bu doküman Part 1'deki her şeyi açıklar: ne kuruldu, neden, nasıl çalışıyor ve nasıl test edilir.

---

## 1) Part 1'in Amacı

**2 sanal makine** kullanarak küçük bir Kubernetes kümesi oluşturmak:

- `aliS` → K3s **Server** (control plane) — `192.168.56.110`
- `aliSW` → K3s **Agent** (worker) — `192.168.56.111`

Her iki makine Vagrant + **libvirt/KVM** ile oluşturulur ve private network üzerinden haberleşir.

---

## 2) Kullanılan Programlar

### libvirt / KVM
- Sanal makineleri çalıştıran hypervisor (VirtualBox yerine KVM kullanılıyor).
- `vagrant-libvirt` plugin'i aracılığıyla Vagrant tarafından yönetilir.
- `host-passthrough` CPU modu ve nested virtualization aktif.

### Vagrant
- VM oluşturma ve provisioning otomasyon aracı.
- `Vagrantfile`'ı okur, makineleri başlatır, shell script'lerini çalıştırır.
- `/vagrant` synced folder ile host-guest arasında dosya paylaşır.

### Debian Bookworm (`debian/bookworm64`)
- Vagrant'ın kullandığı hafif ve kararlı base OS image'i.

### K3s
- Rancher'ın geliştirdiği hafif Kubernetes dağıtımı.
- Server mode: Kubernetes API / control plane çalıştırır.
- Agent mode: İş yüklerini çalıştırır, cluster'a join olur.

### curl
- K3s kurulum script'ini indirmek için kullanılır (`https://get.k3s.io`).
- Worker script'inde API hazırlığını kontrol etmek için kullanılır.

---

## 3) Mimari

```
Host Machine
└── KVM (libvirt)
    ├── VM1: aliS   (192.168.56.110)
    │   └── K3s Server (control plane)
    └── VM2: aliSW  (192.168.56.111)
        └── K3s Agent  (worker)
```

Ağ detayları:
- `eth0` = NAT (internet erişimi)
- `eth1` = private host-only network (VM'ler arası iletişim)

K3s overlay ağı (flannel) `eth1`'e sabitlenir.

---

## 4) Dosya Yapısı

```
p1/
├── Vagrantfile
├── node-token              # provisioning sırasında oluşturulur
└── scripts/
    ├── server_setup.sh
    └── worker_setup.sh
```

### `Vagrantfile`
- Her iki VM'i tanımlar: hostname, private IP, CPU/RAM, provisioning script.
- libvirt provider: `host-passthrough`, `nested: true`, `virtio` NIC, `scsi` disk.
- `libvirt__forward_mode: "none"` ile private network yönlendirmesi kapatılır.

### `scripts/server_setup.sh`
`aliS` üzerinde:
1. `curl` kurulur
2. K3s server kurulur (`--node-ip`, `--bind-address`, `--advertise-address`, `--flannel-iface=eth1`)
3. Node token hazır olana kadar beklenir
4. Token `/vagrant/node-token`'a kopyalanır

### `scripts/worker_setup.sh`
`aliSW` üzerinde:
1. `curl` kurulur
2. Token dosyası dolana kadar beklenir
3. K3s API erişilebilir olana kadar beklenir
4. K3s agent kurulup cluster'a katılır

### `node-token`
- K3s server'ın ürettiği gizli token.
- Worker'ın güvenli join işlemi için gerekli.
- Vagrant synced folder (`/vagrant`) üzerinden paylaşılır.

---

## 5) K3s Flag'leri ve Nedenleri

### Server flag'leri
| Flag | Neden |
|------|-------|
| `--node-ip=192.168.56.110` | Doğru node IP'sini cluster'a bildirir |
| `--bind-address=192.168.56.110` | API server private interface'i dinler |
| `--advertise-address=192.168.56.110` | Worker'lara doğru adres duyurulur |
| `--flannel-iface=eth1` | Flannel'ı NAT yerine private NIC'e zorlar |
| `--write-kubeconfig-mode=644` | VM içinde root'suz kubectl kullanımı sağlar |

### Worker flag'leri
| Flag | Neden |
|------|-------|
| `K3S_URL=https://192.168.56.110:6443` | Server API endpoint'i |
| `K3S_TOKEN=<token>` | Cluster'a katılmak için kimlik doğrulama |
| `--node-ip=192.168.56.111` | Worker'ın cluster node IP'si |
| `--flannel-iface=eth1` | Tutarlı inter-node overlay ağı |

---

## 6) Provisioning Akışı

1. `vagrant up` her iki VM'i başlatır.
2. `aliS` → `server_setup.sh` çalışır:
   - K3s server kurulur
   - `node-token` oluşturulur ve synced folder'a kopyalanır
3. `aliSW` → `worker_setup.sh` çalışır:
   - Token ve API hazırlığını bekler
   - K3s agent kurulup server'a join olur
4. Cluster iki-node `Ready` durumuna geçer.

---

## 7) Nasıl Çalıştırılır

```bash
cd p1
vagrant destroy -f
rm -f node-token
vagrant up
```

SSH:
```bash
vagrant ssh aliS
```

Cluster doğrulama:
```bash
kubectl get nodes -o wide
```

Beklenen çıktı: `aliS` (control-plane) ve `aliSW` (worker) her ikisi `Ready`.

---

## 8) Race Condition'lar ve Çözümleri

| Sorun | Çözüm |
|-------|-------|
| Token dosyası boş/eksik | `-s` (non-empty) kontrolü + atomic copy |
| Worker API hazır değilken başlar | `curl` ile API readiness loop |
| Flannel yanlış interface seçer | `--flannel-iface=eth1` ile zorla |
| Eski başarısız kurumdan kalıntı | `vagrant destroy -f && rm -f node-token` |

---

## 9) Sorun Giderme

### Worker sonsuza kadar bekliyor
```bash
ls -l /vagrant/node-token
curl -k https://192.168.56.110:6443/
```

### Worker service başarısız oluyor
```bash
sudo systemctl status k3s-agent --no-pager -l
sudo journalctl -u k3s-agent -n 200 --no-pager
```

### Server çalışıyor ama cluster kararsız
```bash
sudo systemctl status k3s --no-pager -l
kubectl get pods -A -o wide
```

### Tam temizlik
```bash
cd p1
vagrant destroy -f
rm -f node-token
vagrant up
```

---

## 10) Değerlendirme Kontrol Listesi

- [ ] `vagrant up` takılmadan tamamlanıyor
- [ ] `kubectl get nodes -o wide` 2 node gösteriyor
- [ ] Her iki node `Ready` durumunda
- [ ] `aliS` control-plane rolünde
- [ ] `aliSW` `192.168.56.111` ile join olmuş
- [ ] `k3s` ve `k3s-agent` servisleri active

---

## 11) Savunmada Açıklanacak Kavramlar

- **Control plane** ile **worker** arasındaki fark
- K3s'in tam Kubernetes yerine tercih edilme nedeni
- Statik private IP'lerin neden gerekli olduğu
- Token tabanlı join mekanizması
- Race condition'ların neden önemli olduğu
- `eth1`'in flannel için neden zorlandığı
- libvirt/KVM'in VirtualBox yerine kullanılma nedeni (nested virt desteği)
