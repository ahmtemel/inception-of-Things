#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# 1. Update and install curl
apt-get update && apt-get install -y curl

# 2. Install K3s Server
# --write-kubeconfig-mode 644 allows you to use kubectl without sudo
# --node-ip specifies which network interface K3s should use
curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip=192.168.56.110 \
    --write-kubeconfig-mode=644

# 3. Wait for K3s to be fully ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 2
done
echo "K3s is ready!"

# 4. Deploy the three web applications and ingress
kubectl apply -f /vagrant/confs/app-one.yaml
kubectl apply -f /vagrant/confs/app-two.yaml
kubectl apply -f /vagrant/confs/app-three.yaml
kubectl apply -f /vagrant/confs/ingress.yaml

echo "All applications deployed successfully!"
