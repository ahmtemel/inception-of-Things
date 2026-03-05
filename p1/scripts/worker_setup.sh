#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Update and install curl
apt-get update && apt-get install -y curl

# 2. Wait for the server token to appear in the shared folder
while [ ! -s /vagrant/node-token ]; do
  sleep 2
done

# 3. Wait for K3s API on the server to be reachable
until curl -sk --max-time 2 https://192.168.56.110:6443/ >/dev/null 2>&1; do
  sleep 2
done

# 4. Join the cluster as an Agent
# K3S_URL points to the server IP
# K3S_TOKEN is the secret token we just fetched
TOKEN=$(cat /vagrant/node-token)
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=$TOKEN sh -s - agent \
    --node-ip=192.168.56.111 \
    --flannel-iface=eth1