# 🚀 Inception of Things (IoT)

> Kubernetes küme yönetimi projesi — K3s, K3d ve Argo CD kullanarak altyapı otomasyonu.

---

## 📋 İçindekiler

- [Genel Bakış](#-genel-bakış)
- [Gereksinimler](#-gereksinimler)
- [Part 1: K3s ve Vagrant](#-part-1-k3s-ve-vagrant)
- [Part 2: K3s ve Üç Web Uygulaması](#-part-2-k3s-ve-üç-web-uygulaması)
- [Part 3: K3d ve Argo CD](#-part-3-k3d-ve-argo-cd)
- [Sık Sorulan Sorular](#-sık-sorulan-sorular)
- [Kaynaklar](#-kaynaklar)

---

## 🌐 Genel Bakış

Bu proje üç bölümden oluşur:

| Part | Konu | Araçlar |
|------|-------|---------|
| **Part 1** | K3s Server + Worker kurulumu | Vagrant, VirtualBox, K3s |
| **Part 2** | 3 web uygulaması + Ingress | Vagrant, VirtualBox, K3s, Traefik |
| **Part 3** | CI/CD pipeline (GitOps) | K3d, Docker, Argo CD, GitHub |

### Temel Kavramlar

#### Kubernetes Nedir?
Kubernetes (K8s), container'ları (Docker gibi) yöneten bir orkestrasyon platformudur. Uygulamalarınızı otomatik olarak dağıtır, ölçeklendirir ve yönetir.

#### K3s Nedir?
K3s, Rancher tarafından geliştirilen **hafif bir Kubernetes dağıtımıdır**. Tam Kubernetes'in tüm özelliklerini taşır ama boyutu çok küçüktür (~50MB). IoT cihazları, edge computing ve geliştirme ortamları için idealdir.

#### K3d Nedir?
K3d, **K3s'i Docker container'ları içinde çalıştıran** bir araçtır. Vagrant/VM'e gerek kalmadan, Docker yeterlidir. Saniyeler içinde Kubernetes cluster'ı oluşturabilirsiniz.

#### Argo CD Nedir?
Argo CD, Kubernetes için bir **GitOps sürekli dağıtım (CD) aracıdır**. GitHub repo'nuzdaki YAML dosyalarını izler; değişiklik olduğunda otomatik olarak Kubernetes cluster'ınıza uygular.

#### Traefik Nedir?
Traefik (okunuşu: "trafik"), K3s'in varsayılan **Ingress Controller**'ıdır. Gelen HTTP isteklerini, Host header'ına bakarak doğru uygulamaya yönlendirir. Bir nevi "akıllı kapıcı" görevi görür.

---

## 📦 Gereksinimler

### Tüm Part'lar İçin
- **İşletim Sistemi:** Linux (Ubuntu 22.04 önerilir) veya macOS
- **VirtualBox:** 6.1+ (Part 1 ve Part 2 için)
- **Vagrant:** 2.3+ (Part 1 ve Part 2 için)

### Part 3 İçin Ek Gereksinimler
- **Docker:** 20.10+
- **K3d:** 5.0+
- **kubectl:** 1.25+
- **Git:** 2.30+
- **GitHub hesabı** (public repo gerekli)

### Kurulum (Ubuntu/Debian)

```bash
# VirtualBox
sudo apt-get update
sudo apt-get install -y virtualbox

# Vagrant
wget https://releases.hashicorp.com/vagrant/2.4.1/vagrant_2.4.1-1_amd64.deb
sudo dpkg -i vagrant_2.4.1-1_amd64.deb

# Docker (Part 3 için)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# K3d (Part 3 için)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

---

## 🖥️ Part 1: K3s ve Vagrant

### Amaç
İki sanal makine oluşturup, birini K3s **Server** (patron), diğerini K3s **Worker** (işçi) olarak yapılandırmak.

### Mimari

```
┌──────────────────────┐    ┌──────────────────────┐
│  ahmtemelS (Server)  │    │  ahmtemelSW (Worker)  │
│  192.168.56.110      │◄──►│  192.168.56.111       │
│  K3s Server Mode     │    │  K3s Agent Mode       │
│  1 CPU, 1GB RAM      │    │  1 CPU, 1GB RAM       │
│  ubuntu/jammy64      │    │  ubuntu/jammy64        │
└──────────────────────┘    └───────────────────────┘
```

### Dosya Yapısı

```
p1/
├── Vagrantfile          # 2 VM tanımı (Server + Worker)
└── node-token           # Otomatik oluşur (Server → Worker paylaşım token'ı)
```

### Vagrantfile Detaylı Açıklama

#### Server Makinesi (ahmtemelS)

```ruby
config.vm.define "ahmtemelS" do |server|
  server.vm.hostname = "ahmtemelS"                          # Makinenin ismi
  server.vm.network "private_network", ip: "192.168.56.110" # Sabit IP
```

- **`hostname`**: Makinenin ağ üzerindeki ismi. Proje kuralına göre `login + S` formatında.
- **`private_network`**: VirtualBox'ta "Host-Only" ağ oluşturur. Bu IP sadece host ve diğer VM'ler arasında geçerlidir.
- **`192.168.56.110`**: Proje tarafından belirlenen sabit IP adresi.

```ruby
  server.vm.provider "virtualbox" do |v|
    v.name = "ahmtemelS"  # VirtualBox'ta görünen isim
    v.memory = 1024       # 1 GB RAM
    v.cpus = 1            # 1 CPU çekirdeği
  end
```

- **`memory = 1024`**: K3s Server için minimum 512MB gerekir, 1GB güvenli bir değerdir.
- **`cpus = 1`**: K3s hafif olduğu için 1 CPU yeterlidir.

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip=192.168.56.110 \
  --bind-address=192.168.56.110 \
  --flannel-iface=eth1" sh -s -
```

- **`curl -sfL https://get.k3s.io`**: K3s kurulum scriptini indirir.
  - `-s`: Sessiz mod (progress bar göstermez)
  - `-f`: Hata durumunda HTTP kodunu döndürür
  - `-L`: Redirect'leri takip eder
- **`INSTALL_K3S_EXEC="server ..."`**: K3s'i server modunda çalıştırır.
- **`--write-kubeconfig-mode 644`**: kubeconfig dosyasını herkesin okuyabilmesi için izin verir.
- **`--node-ip=192.168.56.110`**: Kubernetes'e bu node'un IP adresini bildirir.
- **`--bind-address=192.168.56.110`**: API server'ın dinleyeceği IP.
- **`--flannel-iface=eth1`**: Flannel (ağ eklentisi) için VirtualBox'un private network arayüzünü kullanır. `eth0` NAT arayüzüdür, `eth1` bizim private network'ümüzdür.

```bash
sudo cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
```

- **node-token**: K3s Server kurulduğunda otomatik oluşan bir kimlik doğrulama token'ıdır. Worker'ın Server'a bağlanabilmesi için bu token gereklidir.
- **`/vagrant/`**: Vagrant'ın otomatik olarak host ile paylaştığı klasördür. Bu sayede token Worker VM'ine aktarılır.

#### Worker Makinesi (ahmtemelSW)

```bash
TOKEN=$(cat /vagrant/node-token)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server https://192.168.56.110:6443 \
  --token ${TOKEN} \
  --node-ip=192.168.56.111 \
  --flannel-iface=eth1" sh -s -
```

- **`agent`**: K3s'i worker (agent) modunda çalıştırır. Bu mod sadece iş yükü taşır, yönetim yapmaz.
- **`--server https://192.168.56.110:6443`**: Server'ın API adresine bağlanır. 6443, Kubernetes API server'ın standart portudur.
- **`--token ${TOKEN}`**: Daha önce Server'dan alınan kimlik doğrulama token'ı.

### Kullanım

```bash
cd p1/

# VM'leri başlat (ilk sefer ~5-10 dk sürer)
vagrant up

# Server'a bağlan
vagrant ssh ahmtemelS

# Cluster durumunu kontrol et (VM içinde)
kubectl get nodes -o wide

# Beklenen çıktı:
# NAME          STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
# ahmtemelS     Ready    control-plane,master   5m    v1.xx.x+k3s1   192.168.56.110
# ahmtemelSW    Ready    <none>                 3m    v1.xx.x+k3s1   192.168.56.111
```

### Doğrulama Kontrol Listesi

- [ ] `kubectl get nodes` komutu 2 node göstermeli
- [ ] Her iki node da `Ready` durumunda olmalı
- [ ] Server node'un rolü `control-plane,master` olmalı
- [ ] Worker node'un rolü `<none>` olmalı
- [ ] IP adresleri doğru olmalı (110 ve 111)

---

## 🌍 Part 2: K3s ve Üç Web Uygulaması

### Amaç
Tek bir VM üzerinde K3s Server kurarak, 3 farklı web uygulamasını deploy etmek. HOST header'a göre Ingress ile yönlendirme yapmak.

### Mimari

```
                    ┌─────────────────────────────────────────────┐
                    │           K3s Cluster (ahmtemelS)            │
                    │           192.168.56.110                     │
                    │                                              │
  Host:app1.com ──► │  ┌───────────┐                              │
                    │  │  app-one   │ ◄── 1 replica (nginx)       │
                    │  └───────────┘                              │
                    │        ▲                                     │
                    │        │                                     │
  Host:app2.com ──► │  ┌─────┴──────────┐                         │
                    │  │   Traefik       │  Ingress Controller    │
                    │  │  (Kapıcı)       │                        │
                    │  └─────┬──────────┘                         │
                    │        │                                     │
  (varsayılan)  ──► │  ┌─────┴─────┐   ┌───────────┐             │
                    │  │ app-three  │   │  app-two   │ ◄── 3 rep. │
                    │  │ (default)  │   │            │             │
                    │  └───────────┘   └───────────┘             │
                    └─────────────────────────────────────────────┘
                           ▲
                           │
                    ┌──────┴──────┐
                    │    Host     │
                    │  (Bilgisay.)│
                    └─────────────┘
```

### Dosya Yapısı

```
p2/
├── Vagrantfile              # Tek VM tanımı
└── confs/
    ├── app-one.yaml         # App1: Deployment + Service (1 replica)
    ├── app-two.yaml         # App2: Deployment + Service (3 replica)
    ├── app-three.yaml       # App3: Deployment + Service (1 replica)
    └── ingress.yaml         # Ingress: HOST bazlı yönlendirme
```

### Kubernetes Kavramları (Detaylı)

#### Pod
Pod, Kubernetes'teki en küçük çalıştırılabilir birimdir. Bir veya birden fazla container içerir. Bizim uygulamalarımızda her pod bir nginx container'ı çalıştırır.

#### Deployment
Deployment, pod'ların istenen sayıda çalışmasını garanti eder. Örneğin `replicas: 3` dersek, Kubernetes her zaman 3 pod çalıştırır. Biri ölürse otomatik olarak yenisini başlatır.

#### Service
Service, pod'lara sabit bir ağ adresi sağlar. Pod'lar gelip gider (IP'leri değişir), ama Service her zaman aynı adreste durur. `ClusterIP` tipi sadece cluster içinden erişilebilir.

#### Ingress
Ingress, cluster dışından gelen HTTP trafiğini cluster içindeki servislere yönlendirir. HOST header'a veya URL path'e göre yönlendirme yapar.

#### Ingress Controller (Traefik)
Ingress kurallarını gerçekten uygulayan yazılımdır. K3s varsayılan olarak Traefik kullanır. Traefik, gelen isteklerin HOST header'ına bakarak doğru servise yönlendirir.

### YAML Dosyaları Detaylı Açıklama

#### app-one.yaml

```yaml
apiVersion: apps/v1       # Kubernetes API versiyonu
kind: Deployment           # Kaynak tipi: Deployment
metadata:
  name: app-one            # Deployment'ın ismi
  labels:
    app: app-one           # Etiket (filtreleme için)
spec:
  replicas: 1              # Kaç pod çalışacak (app1 = 1 pod)
  selector:
    matchLabels:
      app: app-one         # Hangi pod'ları yöneteceğini belirler
  template:                # Pod şablonu
    metadata:
      labels:
        app: app-one       # Pod'un etiketi (selector ile eşleşmeli)
    spec:
      containers:
        - name: app-one
          image: nginx:stable-alpine    # ARM64 + x86 uyumlu nginx imajı
          ports:
            - containerPort: 80         # Container'ın dinlediği port
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html  # nginx'in HTML dosyalarını aradığı yer
      initContainers:                   # Ana container'dan ÖNCE çalışan container
        - name: init-html
          image: busybox:1.36           # Küçük utility container
          command: ["sh", "-c"]         # Shell komutu çalıştır
          args:
            - >-                        # Çok satırlı string (YAML folded)
              echo "<!DOCTYPE html>..." > /html/index.html
          volumeMounts:
            - name: html
              mountPath: /html
      volumes:
        - name: html
          emptyDir: {}                  # Geçici boş dizin (pod silinince kaybolur)
```

**initContainers neden var?**
- `initContainers` ana container başlamadan önce çalışır ve tamamlanır.
- Burada HTML dosyasını oluşturuyor. Pod ismi ve kernel bilgisini dinamik olarak HTML'e yazıyor.
- `emptyDir` volume'ü ile initContainer ve ana container aynı veriyi paylaşıyor.

**Neden `nginx:stable-alpine`?**
- `paulbouwer/hello-kubernetes` imajı sadece x86 (amd64) destekliyor.
- `nginx:stable-alpine` hem x86 hem ARM64 (Apple Silicon) destekliyor.
- Alpine tabanlı olduğu için çok hafif (~5MB).

#### app-two.yaml
App-one ile neredeyse aynı, farkları:
- **`replicas: 3`**: 3 pod çalışır (yük dengeleme gösterir)
- **Mesaj**: "Hello from app2."

#### app-three.yaml
App-one ile aynı yapıda:
- **`replicas: 1`**: 1 pod
- **Mesaj**: "Hello from app3."
- **Özel durum**: Ingress'te varsayılan (default) uygulama olarak tanımlı

#### ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
spec:
  ingressClassName: traefik          # Traefik Ingress Controller kullan
  rules:
    - host: app1.com                 # Host header = "app1.com" ise
      http:
        paths:
          - path: /                  # Tüm path'ler
            pathType: Prefix
            backend:
              service:
                name: app-one        # → app-one servisine yönlendir
                port:
                  number: 80
    - host: app2.com                 # Host header = "app2.com" ise
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-two        # → app-two servisine yönlendir
                port:
                  number: 80
    - http:                          # Host belirtilmemişse (varsayılan)
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-three      # → app-three servisine yönlendir
                port:
                  number: 80
```

**Ingress kuralları nasıl çalışır?**

| İstek | HOST Header | Yönlendirildiği Servis |
|-------|------------|----------------------|
| `curl -H "Host:app1.com" 192.168.56.110` | app1.com | app-one (1 pod) |
| `curl -H "Host:app2.com" 192.168.56.110` | app2.com | app-two (3 pod) |
| `curl 192.168.56.110` | (yok) | app-three (1 pod) |

**`pathType: Prefix` ne demek?**
- `Prefix`: URL path'in belirtilen prefix ile başlaması yeterli. `/` demek = tüm path'ler eşleşir.
- `Exact`: Tam eşleşme gerekir.

### Kullanım

```bash
cd p2/

# VM'i başlat (ilk sefer ~5-10 dk)
vagrant up

# VM'e bağlan
vagrant ssh ahmtemelS

# Cluster durumunu kontrol et
kubectl get all
kubectl get ingress

# Test (VM içinden)
curl -H "Host:app1.com" 192.168.56.110    # → Hello from app1.
curl -H "Host:app2.com" 192.168.56.110    # → Hello from app2.
curl 192.168.56.110                        # → Hello from app3.
```

### Host Makineden Tarayıcı ile Erişim

`/etc/hosts` dosyasına ekle:
```
192.168.56.110  app1.com
192.168.56.110  app2.com
```

```bash
# Linux/macOS
sudo sh -c 'echo "192.168.56.110  app1.com" >> /etc/hosts'
sudo sh -c 'echo "192.168.56.110  app2.com" >> /etc/hosts'
```

Tarayıcıda:
- `http://app1.com` → App1
- `http://app2.com` → App2
- `http://192.168.56.110` → App3

### Doğrulama Kontrol Listesi

- [ ] `kubectl get pods` → 5 pod (1 + 3 + 1) hepsi `Running`
- [ ] `kubectl get svc` → 3 servis (app-one, app-two, app-three)
- [ ] `kubectl get ingress` → app-ingress kuralları
- [ ] `curl -H "Host:app1.com" 192.168.56.110` → "Hello from app1."
- [ ] `curl -H "Host:app2.com" 192.168.56.110` → "Hello from app2."
- [ ] `curl 192.168.56.110` → "Hello from app3."
- [ ] app2'ye birden fazla istek atınca farklı pod isimleri dönmeli (3 replica)

---

## 🔄 Part 3: K3d ve Argo CD

### Amaç
K3d (K3s in Docker) kullanarak Kubernetes cluster oluşturmak, Argo CD ile GitHub repo'dan otomatik deploy (GitOps) kurmak.

### Mimari

```
  ┌─────────────┐         ┌──────────────────────────────────────┐
  │   GitHub     │  sync   │        K3D Cluster (Docker)          │
  │ (manifests)  │────────►│                                      │
  │              │         │  ┌────────────────────────────────┐  │
  │  deployment  │         │  │  namespace: argocd              │  │
  │  .yaml       │         │  │  ┌──────────────────────────┐  │  │
  │  (v1 → v2)   │         │  │  │      Argo CD             │  │  │
  │              │         │  │  │  (GitHub'ı izliyor)       │  │  │
  └──────┬───────┘         │  │  └────────────┬─────────────┘  │  │
         │ push            │  └───────────────┼────────────────┘  │
         │                 │                  │ otomatik deploy   │
         │                 │  ┌───────────────▼────────────────┐  │
         │                 │  │  namespace: dev                │  │
  ┌──────┴───────┐         │  │  ┌──────────────────────────┐  │  │
  │  Docker Hub  │─── pull ─│  │  │  wil-playground pod      │  │  │
  │  wil42/      │         │  │  │  (port 8888)              │  │  │
  │  playground  │         │  │  └──────────────────────────┘  │  │
  └──────────────┘         │  └────────────────────────────────┘  │
                           └───────────────────┬──────────────────┘
                                               │
                                        ┌──────┴──────┐
                                        │    Host     │
                                        │ localhost   │
                                        │   :8888     │
                                        └─────────────┘
```

### K3s vs K3d Farkı

| Özellik | K3s | K3d |
|---------|-----|-----|
| **Ne?** | Hafif Kubernetes dağıtımı | K3s'i Docker container içinde çalıştırır |
| **Kurulum** | Doğrudan OS'a kurulur | Docker container olarak çalışır |
| **VM gerekir mi?** | Evet (gerçek/sanal makine) | Hayır, Docker yeterli |
| **Kullanım alanı** | Üretim, IoT, edge | Geliştirme, test |
| **Hız** | Dakikalar | Saniyeler |

### GitOps Nedir?

GitOps, altyapı ve uygulama yapılandırmasını Git repo'sunda tutma yaklaşımıdır:

1. **Git = Tek Doğru Kaynak (Single Source of Truth)**: Tüm yapılandırma Git'te
2. **Otomatik Sync**: Git'teki değişiklik → otomatik olarak cluster'a uygulanır
3. **Deklaratif**: "Nasıl yapılacağını" değil, "ne istediğini" tanımlarsın

### Dosya Yapısı

```
p3/
├── scripts/
│   └── setup.sh             # Kurulum scripti (savunmada çalıştırılır)
└── confs/
    ├── application.yaml     # Argo CD Application tanımı
    └── deployment.yaml      # wil-playground Deployment + Service
```

### Dosyalar Detaylı Açıklama

#### scripts/setup.sh

Bu script savunma sırasında çalıştırılır. Sırasıyla:

1. **Docker kurulumu**: Container runtime (K3d'nin çalışması için şart)
2. **kubectl kurulumu**: Kubernetes komut satırı aracı
3. **K3d kurulumu**: K3s-in-Docker aracı
4. **K3d cluster oluşturma**: `k3d cluster create iot-p3 --port "8888:8888@loadbalancer"`
   - `--port "8888:8888@loadbalancer"`: Host'un 8888 portunu cluster'ın loadbalancer'ına bağlar
5. **Namespace oluşturma**: `argocd` (Argo CD için) ve `dev` (uygulama için)
6. **Argo CD kurulumu**: Resmi manifest dosyasını uygular
7. **Application oluşturma**: GitHub repo'yu Argo CD'ye tanıtır

#### confs/application.yaml

```yaml
apiVersion: argoproj.io/v1alpha1       # Argo CD'nin özel API'si
kind: Application                       # Argo CD Application kaynağı
metadata:
  name: wil-playground                  # Uygulamanın Argo CD'deki ismi
  namespace: argocd                     # Argo CD'nin çalıştığı namespace
spec:
  project: default                      # Argo CD projesi (default = varsayılan)
  source:
    repoURL: https://github.com/ahmtemel/ahmtemel-iot-p3.git  # GitHub repo adresi
    targetRevision: HEAD                # Git branch/tag (HEAD = en son commit)
    path: manifests                     # Repo içindeki YAML dosyalarının yolu
  destination:
    server: https://kubernetes.default.svc  # Hedef cluster (kendi cluster'ımız)
    namespace: dev                          # Hedef namespace
  syncPolicy:
    automated:                          # Otomatik senkronizasyon
      selfHeal: true                    # Cluster'da manuel değişiklik olursa geri al
      prune: true                       # Git'ten silinen kaynakları cluster'dan da sil
```

**Önemli alanlar:**
- **`repoURL`**: Argo CD'nin izleyeceği GitHub repo'su. **Public** olmalı (aksi halde authentication gerekir).
- **`targetRevision: HEAD`**: Her zaman en son commit'i kullanır.
- **`path: manifests`**: Repo'nun kökündeki `manifests/` klasöründeki YAML'ları uygular.
- **`selfHeal: true`**: Biri `kubectl delete pod ...` derse, Argo CD otomatik geri getirir.
- **`prune: true`**: Git'ten bir YAML silerseniz, Kubernetes'teki karşılığı da silinir.

#### confs/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev                     # dev namespace'inde çalışır
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wil-playground
  template:
    metadata:
      labels:
        app: wil-playground
    spec:
      containers:
        - name: wil-playground
          image: wil42/playground:v1   # Docker Hub'daki imaj, v1 etiketi
          ports:
            - containerPort: 8888      # Uygulamanın dinlediği port
---
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  type: LoadBalancer                   # Dışarıdan erişilebilir
  selector:
    app: wil-playground
  ports:
    - port: 8888                       # Servis portu
      targetPort: 8888                 # Container portu
```

**`wil42/playground` nedir?**
- Docker Hub'da bulunan hazır bir test uygulaması
- Port 8888'de çalışır
- İki versiyonu var:
  - **v1**: `{"status":"ok", "message": "v1"}` döner
  - **v2**: `{"status":"ok", "message": "v2"}` döner

### Kullanım (Adım Adım)

#### 1. Kurulum Scriptini Çalıştır

```bash
cd p3/
chmod +x scripts/setup.sh
./scripts/setup.sh
```

#### 2. Argo CD'ye Erişim

```bash
# Admin şifresini al
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward başlat
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Tarayıcıda: https://localhost:8080
# Kullanıcı: admin
# Şifre: yukarıda aldığın şifre
```

#### 3. Uygulamayı Test Et

```bash
# Pod'ları kontrol et
kubectl get pods -n dev

# Uygulamayı test et
curl http://localhost:8888/
# Beklenen: {"status":"ok", "message": "v1"}
```

#### 4. v2'ye Güncelleme (GitOps Demo)

GitHub repo'ndaki `manifests/deployment.yaml` dosyasında `v1`'i `v2` ile değiştir:

```bash
cd ~/ahmtemel-iot-p3
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add . && git commit -m "v2" && git push
```

Birkaç dakika bekle (Argo CD otomatik sync yapar), sonra:

```bash
curl http://localhost:8888/
# Beklenen: {"status":"ok", "message": "v2"}
```

### Doğrulama Kontrol Listesi

- [ ] `kubectl get ns` → `argocd` ve `dev` namespace'leri var
- [ ] `kubectl get pods -n argocd` → Tüm Argo CD pod'ları `Running`
- [ ] `kubectl get pods -n dev` → `wil-playground` pod'u `Running`
- [ ] `curl http://localhost:8888/` → v1 mesajı dönüyor
- [ ] GitHub'da v1→v2 değişikliği sonrası otomatik güncelleniyor
- [ ] Argo CD arayüzünde sync durumu "Synced" ve "Healthy"

---

## ❓ Sık Sorulan Sorular

### "exec format error" hatası alıyorum
Docker imajı mimarinizle uyumlu değil. ARM (Apple Silicon) kullanıyorsanız, x86-only imajlar çalışmaz. Çözüm: Multi-arch imaj kullanın (nginx:stable-alpine gibi).

### Traefik 404 döndürüyor
Traefik çalışıyor ama Ingress kurallarını uygulayamıyor olabilir. Çözümler:
1. `kubectl logs -n kube-system deployment/traefik` ile logları kontrol edin
2. `kubectl rollout restart deployment/traefik -n kube-system` ile yeniden başlatın
3. `sudo conntrack -F` ile bağlantı tablosunu temizleyin

### Argo CD "Repository not found" hatası veriyor
GitHub repo'nuzun **public** olduğundan emin olun. `application.yaml`'daki `repoURL`'i kontrol edin.

### Pod'lar "Pending" durumunda kalıyor
Cluster'da yeterli kaynak (CPU/RAM) olmayabilir. `kubectl describe pod <pod-ismi>` ile detayları kontrol edin.

---

## 📚 Kaynaklar

- [K3s Dokümantasyonu](https://docs.k3s.io/)
- [K3d Dokümantasyonu](https://k3d.io/)
- [Argo CD Dokümantasyonu](https://argo-cd.readthedocs.io/)
- [Kubernetes Resmi Dokümantasyonu](https://kubernetes.io/docs/)
- [Traefik Dokümantasyonu](https://doc.traefik.io/traefik/)
- [Vagrant Dokümantasyonu](https://developer.hashicorp.com/vagrant/docs)
- [wil42/playground Docker Hub](https://hub.docker.com/r/wil42/playground)

---

## 👤 Yazar

**ahmtemel** — Inception of Things (IoT) Projesi
