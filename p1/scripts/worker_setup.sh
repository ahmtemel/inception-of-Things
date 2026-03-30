#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y curl

# Server token'ın gelmesini bekle
while [ ! -s /vagrant/node-token ]; do
  sleep 2
done

# Server API'nin hazır olmasını bekle
until curl -sk --max-time 2 https://192.168.56.110:6443/ >/dev/null 2>&1; do
  sleep 2
done

TOKEN=$(cat /vagrant/node-token)
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=$TOKEN sh -s - agent \
    --node-ip=192.168.56.111 \
    --flannel-iface=eth1