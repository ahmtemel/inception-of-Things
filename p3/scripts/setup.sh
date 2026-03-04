#!/bin/bash
# =============================================
# Part 3: K3d + Argo CD Kurulum Scripti
# Bu script savunma sırasında çalıştırılacaktır.
# Gerekli tüm araçları kurar ve yapılandırır.
# =============================================

set -e

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}  Part 3: K3d + Argo CD Kurulum Başlıyor     ${NC}"
echo -e "${YELLOW}=============================================${NC}"

# ---- ADIM 1: Docker Kurulumu ----
echo -e "\n${GREEN}>>> [1/7] Docker kuruluyor...${NC}"
if ! command -v docker &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release > /dev/null 2>&1
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
    sudo usermod -aG docker $USER
    echo -e "  ${GREEN}✓ Docker kuruldu${NC}"
else
    echo -e "  ${GREEN}✓ Docker zaten kurulu${NC}"
fi
sudo systemctl start docker
sudo systemctl enable docker

# ---- ADIM 2: kubectl Kurulumu ----
echo -e "\n${GREEN}>>> [2/7] kubectl kuruluyor...${NC}"
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo -e "  ${GREEN}✓ kubectl kuruldu${NC}"
else
    echo -e "  ${GREEN}✓ kubectl zaten kurulu${NC}"
fi

# ---- ADIM 3: K3d Kurulumu ----
echo -e "\n${GREEN}>>> [3/7] K3d kuruluyor...${NC}"
if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    echo -e "  ${GREEN}✓ K3d kuruldu${NC}"
else
    echo -e "  ${GREEN}✓ K3d zaten kurulu${NC}"
fi

# ---- ADIM 4: K3d Cluster Oluştur ----
echo -e "\n${GREEN}>>> [4/7] K3d cluster oluşturuluyor...${NC}"
if k3d cluster list 2>/dev/null | grep -q "iot-p3"; then
    echo -e "  ${YELLOW}! Cluster zaten var, silip yeniden oluşturuluyor...${NC}"
    k3d cluster delete iot-p3
fi
k3d cluster create iot-p3 --port "8888:8888@loadbalancer"
echo -e "  ${GREEN}✓ K3d cluster oluşturuldu${NC}"

# ---- ADIM 5: Namespace'leri Oluştur ----
echo -e "\n${GREEN}>>> [5/7] Namespace'ler oluşturuluyor...${NC}"
kubectl create namespace argocd 2>/dev/null || true
kubectl create namespace dev 2>/dev/null || true
echo -e "  ${GREEN}✓ argocd ve dev namespace'leri oluşturuldu${NC}"

# ---- ADIM 6: Argo CD Kurulumu ----
echo -e "\n${GREEN}>>> [6/7] Argo CD kuruluyor...${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null
echo "  Argo CD pod'ları başlatılıyor, bekleniyor..."
kubectl wait --for=condition=ready pod --all -n argocd --timeout=180s 2>/dev/null || true
echo -e "  ${GREEN}✓ Argo CD kuruldu${NC}"

# ---- ADIM 7: Argo CD Application Oluştur ----
echo -e "\n${GREEN}>>> [7/7] Argo CD Application oluşturuluyor...${NC}"
kubectl apply -f /home/vagrant/confs/application.yaml 2>/dev/null || \
kubectl apply -f application.yaml 2>/dev/null || \
echo -e "  ${YELLOW}! application.yaml bulunamadı, manuel uygulayın${NC}"

# Pod'ların hazır olmasını bekle
sleep 10
kubectl wait --for=condition=ready pod --all -n dev --timeout=120s 2>/dev/null || true

# ---- SONUÇ ----
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}       KURULUM TAMAMLANDI!                   ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# Admin şifresini göster
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
echo -e "Argo CD Admin Şifresi: ${YELLOW}${ARGO_PASS}${NC}"
echo ""
echo "Argo CD Arayüzü:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "  Tarayıcı: https://localhost:8080"
echo "  Kullanıcı: admin"
echo ""

kubectl get ns
echo ""
kubectl get pods -n dev
echo ""
echo "Test: curl http://localhost:8888/"
