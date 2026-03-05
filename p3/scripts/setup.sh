#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WAIT]${NC} $1"; }

# ─────────────────────────────────────────────
# 1. Check prerequisites
# ─────────────────────────────────────────────
for cmd in docker kubectl k3d; do
  if ! command -v $cmd &>/dev/null; then
    echo "ERROR: '$cmd' is not installed. Please install it first."
    exit 1
  fi
done
info "All prerequisites found (docker, kubectl, k3d)"

# ─────────────────────────────────────────────
# 2. Create K3d cluster
# ─────────────────────────────────────────────
# Delete existing cluster if it exists
k3d cluster delete iot-p3 2>/dev/null || true

info "Creating K3d cluster 'iot-p3'..."
k3d cluster create iot-p3 --port "8888:8888@loadbalancer"

# Ensure kubeconfig is set correctly
export KUBECONFIG=$(k3d kubeconfig write iot-p3)
# Also write it to the default location so kubectl works after the script
mkdir -p /home/${SUDO_USER:-$USER}/.kube
k3d kubeconfig get iot-p3 > /home/${SUDO_USER:-$USER}/.kube/config
chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} /home/${SUDO_USER:-$USER}/.kube 2>/dev/null || true

# Wait for cluster to be ready
warn "Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
info "K3d cluster 'iot-p3' is ready!"

# ─────────────────────────────────────────────
# 3. Create namespaces
# ─────────────────────────────────────────────
info "Creating namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# ─────────────────────────────────────────────
# 4. Install Argo CD
# ─────────────────────────────────────────────
info "Installing Argo CD..."
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD pods to be ready
warn "Waiting for Argo CD pods to be ready (this may take a few minutes)..."
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
info "Argo CD is installed and running!"

# ─────────────────────────────────────────────
# 5. Deploy the Argo CD Application
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFS_DIR="$(dirname "$SCRIPT_DIR")/confs"

info "Applying Argo CD Application manifest..."
kubectl apply -f "$CONFS_DIR/application.yaml"

# ─────────────────────────────────────────────
# 6. Wait for the app to sync and deploy
# ─────────────────────────────────────────────
warn "Waiting for wil-playground pod to start in 'dev' namespace..."
for i in $(seq 1 60); do
  if kubectl get pods -n dev 2>/dev/null | grep -q "Running"; then
    break
  fi
  sleep 5
done

# ─────────────────────────────────────────────
# 7. Print status and access info
# ─────────────────────────────────────────────
echo ""
info "============================================"
info "  Setup Complete!"
info "============================================"
echo ""

# Get Argo CD admin password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

info "Argo CD Dashboard:"
echo "  URL:      https://localhost:8080"
echo "  User:     admin"
echo "  Password: $ARGOCD_PASS"
echo ""
info "To access Argo CD UI, run in a separate terminal:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo ""
info "Application status:"
kubectl get pods -n dev
echo ""
info "Test the app:"
echo "  curl http://localhost:8888/"
echo ""
