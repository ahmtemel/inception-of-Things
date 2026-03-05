# Part 3 — K3d + Argo CD (GitOps)

This README is a **defense-ready, detailed guide** for Part 3 of Inception of Things.
It explains:

- what is built,
- which programs are used and why,
- how each file works,
- exact run and verification steps,
- common problems and fast recovery,
- what to say during evaluation.

---

## 1) Goal of Part 3

Create a local Kubernetes cluster with **K3d** (K3s inside Docker), install **Argo CD**, and deploy an application from a **GitHub repository** using **GitOps**.

Expected behavior:

1. Argo CD watches your Git repo (`manifests/` path).
2. It deploys `wil-playground` into namespace `dev`.
3. If you change image `v1 -> v2` and push commit, Argo CD syncs and applies the change.
4. If cluster state drifts from Git, Argo CD self-heals it.

---

## 2) Programs Used and Why

### Docker
- Container runtime.
- Required by K3d because K3d runs K3s nodes as Docker containers.

### K3d
- Creates a lightweight Kubernetes cluster quickly.
- Instead of full VM-based K8s, it runs K3s inside Docker.
- In this part, cluster name is `iot-p3`.

### K3s
- Lightweight Kubernetes distribution.
- K3d uses K3s under the hood.

### kubectl
- Kubernetes CLI client.
- Used to apply manifests, check pods/services/namespaces, get logs, port-forward.

### Argo CD
- GitOps CD controller for Kubernetes.
- Watches Git repo and keeps cluster state aligned with manifests.

### Git + GitHub
- Git stores desired state as YAML.
- GitHub repo is the source Argo CD watches.

### wil42/playground image
- Test application for demonstration (`v1` and `v2`).
- Helpful to prove GitOps by changing tag and observing rollout.

---

## 3) High-Level Architecture

```
GitHub repo (manifests/deployment.yaml)
        │
        │ watched by Argo CD
        ▼
K3d cluster: iot-p3
  ├─ namespace argocd
  │   ├─ argocd-server
  │   ├─ argocd-repo-server
  │   └─ argocd-application-controller
  └─ namespace dev
      └─ wil-playground deployment + service

Host ports
  - 8888 -> app service (via k3d loadbalancer mapping)
  - 8080 -> Argo CD UI (via kubectl port-forward)
```

---

## 4) Repository Structure (Part 3)

```
p3/
├── README.md
├── scripts/
│   └── setup.sh
└── confs/
    ├── application.yaml
    └── deployment.yaml
```

### `scripts/setup.sh`
Automates all provisioning steps:
1. Checks prerequisites (`docker`, `kubectl`, `k3d`).
2. Recreates K3d cluster `iot-p3`.
3. Fixes kubeconfig location for the invoking user.
4. Creates `argocd` and `dev` namespaces.
5. Installs Argo CD from official manifest.
6. Applies `confs/application.yaml`.
7. Waits for app pod in `dev`.
8. Prints Argo CD login details + test hints.

### `confs/application.yaml`
Argo CD `Application` resource.
- Defines **source** Git repo/path/branch.
- Defines **destination** cluster/namespace.
- Enables automated sync + self-heal + prune.

### `confs/deployment.yaml`
Application workload manifest intended to live in GitHub repo under `manifests/`.
Contains:
- `Deployment` (`wil42/playground:v1`),
- `Service` on port `8888`.

---

## 5) Deep Explanation of `application.yaml`

Current behavior:

- `repoURL: https://github.com/ahmtemel/ahmtemel-iot-p3.git`
  - Argo CD clones this repo.
- `targetRevision: HEAD`
  - Tracks latest commit of default branch.
- `path: manifests`
  - Only files under `manifests/` are considered desired state.
- `destination.namespace: dev`
  - Deploys app resources into `dev` namespace.
- `syncPolicy.automated`
  - `selfHeal: true` => if someone changes/deletes managed resources manually, Argo CD reverts to Git state.
  - `prune: true` => if a resource is removed from Git, Argo CD removes it from cluster too.

Important: auto-sync does not mean instant webhook unless configured/exposed; polling may take some time.

---

## 6) Prerequisites Installation

## Fedora (recommended for your environment)

```bash
# Docker
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

Check:

```bash
docker --version
kubectl version --client
k3d version
```

---

## 7) GitHub Repo Preparation (Required)

Argo CD watches your repo, so this must exist and be public:

- Repo: `ahmtemel-iot-p3`
- Path: `manifests/`
- File: `manifests/deployment.yaml`

Example push flow:

```bash
mkdir -p ~/ahmtemel-iot-p3/manifests
cp p3/confs/deployment.yaml ~/ahmtemel-iot-p3/manifests/deployment.yaml

cd ~/ahmtemel-iot-p3
git init
git add .
git commit -m "initial v1"
git branch -M main
git remote add origin https://github.com/ahmtemel/ahmtemel-iot-p3.git
git push -u origin main
```

---

## 8) Run Part 3

From project root:

```bash
cd p3
sudo ./scripts/setup.sh
```

Why `sudo` is used in this project flow:
- avoids permission issues on fresh systems.

After setup, ensure your user kubeconfig is up to date:

```bash
unset KUBECONFIG
mkdir -p ~/.kube
sudo k3d kubeconfig get iot-p3 > ~/.kube/config
kubectl get nodes
```

If this works, cluster access is healthy.

---

## 9) Verification Checklist

```bash
kubectl get ns
kubectl get pods -n argocd
kubectl get pods -n dev
curl http://localhost:8888/
```

Expected:
- `argocd` and `dev` namespaces exist,
- Argo CD pods are running,
- `wil-playground` pod running in `dev`,
- `curl` returns JSON containing message `v1`.

---

## 10) Argo CD UI Access

Get admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Open UI via port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open browser:
- `https://localhost:8080`
- user: `admin`
- password: output from command above.

---

## 11) GitOps Demonstration (v1 -> v2)

In watched Git repo:

```bash
cd ~/ahmtemel-iot-p3
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "upgrade to v2"
git push
```

Then verify:

```bash
curl http://localhost:8888/
```

Expected message changes from `v1` to `v2` after Argo CD sync.

In UI, app should go back to `Synced` + `Healthy`.

---

## 12) Self-Heal Demonstration

Delete managed pod manually:

```bash
kubectl -n dev delete pod -l app=wil-playground
```

Argo CD should recreate it automatically.

This proves `selfHeal: true`.

---

## 13) Defense Talking Points (What to Say)

Use this story:

1. “I created a local Kubernetes cluster with K3d because it is fast and lightweight.”
2. “I installed Argo CD in `argocd` namespace and defined one Application manifest.”
3. “Argo CD watches my public GitHub repo path `manifests/` as source of truth.”
4. “The app is deployed into `dev` namespace and exposed on port `8888`.”
5. “With automated sync/prune/self-heal enabled, cluster state is continuously reconciled to Git state.”
6. “I demonstrate GitOps by pushing `v1 -> v2` and showing automatic rollout.”
7. “I demonstrate self-heal by deleting a pod and showing Argo CD restores it.”

Short one-line summary for evaluator:

> “Part 3 implements GitOps: Git is the desired state, Argo CD continuously enforces that state in Kubernetes.”

---

## 14) Common Problems and Fast Fixes

## A) `kubectl` points to wrong server/port
Symptom: connection refused to stale port.

Fix:

```bash
unset KUBECONFIG
sudo k3d kubeconfig get iot-p3 > ~/.kube/config
kubectl get nodes
```

## B) Argo CD not syncing app
Check app status:

```bash
kubectl get application -n argocd
kubectl describe application wil-playground -n argocd
```

Typical causes:
- repo private/inaccessible,
- wrong `repoURL`,
- wrong `path` (must match `manifests`),
- YAML invalid in repo.

## C) `dev` pod never appears
Inspect Argo CD pods first:

```bash
kubectl get pods -n argocd
kubectl logs -n argocd deployment/argocd-repo-server --tail=100
```

Then inspect application status/errors:

```bash
kubectl describe application wil-playground -n argocd
```

## D) UI unreachable
- Ensure port-forward terminal is still running.
- Retry:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## E) App logs are empty
Some containers do not emit request logs continuously; this is normal if health and response are correct.

---

## 15) Minimal Evaluation Script (Quick Run)

```bash
# setup
cd p3
sudo ./scripts/setup.sh
unset KUBECONFIG
sudo k3d kubeconfig get iot-p3 > ~/.kube/config

# prove cluster + app
kubectl get nodes
kubectl get pods -n argocd
kubectl get pods -n dev
curl http://localhost:8888/

# prove GitOps update
cd ~/ahmtemel-iot-p3
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add . && git commit -m "v2" && git push
sleep 60
curl http://localhost:8888/
```

---

## 16) Final Success Criteria

You can consider Part 3 complete when:

- K3d cluster is healthy,
- Argo CD pods are running,
- `wil-playground` is deployed from Git,
- v1->v2 commit updates app automatically,
- self-heal behavior is demonstrated.
