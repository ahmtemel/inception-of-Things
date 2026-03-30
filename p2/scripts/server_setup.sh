#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Update and install curl
apt-get update && apt-get install -y curl

# 2. Install K3s Server
# --write-kubeconfig-mode 644 allows you to use kubectl without sudo
# --node-ip, --bind-address, --advertise-address: use the private network interface
# --flannel-iface: ensures flannel uses the correct interface (eth1)
curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip=192.168.56.110 \
    --bind-address=192.168.56.110 \
    --advertise-address=192.168.56.110 \
    --flannel-iface=eth1 \
    --write-kubeconfig-mode=644

# 3. vagrant kullanıcısı için kubectl PATH ve KUBECONFIG ayarla
echo 'export PATH=$PATH:/usr/local/bin' >> /home/vagrant/.bashrc
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/vagrant/.bashrc

# 4. Wait for K3s to be fully ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 2
done
echo "K3s is ready!"

# 5. Deploy the three web applications and ingress
kubectl apply -f /vagrant/confs/app-one.yaml
kubectl apply -f /vagrant/confs/app-two.yaml
kubectl apply -f /vagrant/confs/app-three.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo "All applications deployed successfully!"
