#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Update and install curl
apt-get update && apt-get install -y curl

# 2. Install K3s Server
# --write-kubeconfig-mode 644 allows you to use kubectl without sudo
# --node-ip specifies which network interface K3s should use
curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip=192.168.56.110 \
        --bind-address=192.168.56.110 \
        --flannel-iface=eth1 \
    --write-kubeconfig-mode=644

# 3. Share the token via the /vagrant folder (synced by Vagrant)
# The worker needs this token to join the cluster
until [ -s /var/lib/rancher/k3s/server/node-token ]; do
    sleep 1
done

cp /var/lib/rancher/k3s/server/node-token /vagrant/.node-token.tmp
mv /vagrant/.node-token.tmp /vagrant/node-token