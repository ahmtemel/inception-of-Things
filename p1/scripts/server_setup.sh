#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Update and install curl
apt-get update && apt-get install -y curl

# 2. Install K3s Server
# Not: libvirt altında eth1 arayüzü K3s trafiği için kullanılacak
curl -sfL https://get.k3s.io | sh -s - server \
    --node-ip=192.168.56.110 \
    --bind-address=192.168.56.110 \
    --advertise-address=192.168.56.110 \
    --flannel-iface=eth1 \
    --write-kubeconfig-mode=644

# 3. Token paylaşımı
# K3s'in token üretmesini bekle
until [ -s /var/lib/rancher/k3s/server/node-token ]; do
    sleep 2
done

# Vagrant klasörü üzerinden token'ı worker'a ilet
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token