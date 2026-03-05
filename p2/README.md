# Part 2 — K3s + 3 Web Applications + Ingress (Traefik)

This README explains Part 2 in depth: architecture, tools, every manifest, request flow, test strategy, and what to say in defense.

---

## 1) Objective of Part 2

Build a Kubernetes environment on **one VM** where:

- `app-one` serves **Hello from app1** (1 replica)
- `app-two` serves **Hello from app2** (3 replicas)
- `app-three` serves **Hello from app3** (1 replica, default backend)

Routing is done by **Ingress (Traefik)** using the HTTP Host header:

- `Host: app1.com` → `app-one`
- `Host: app2.com` → `app-two`
- no Host match → `app-three`

---

## 2) Programs/Components Used and Why

### VirtualBox
Runs the VM itself (CPU, RAM, networking virtualization).

### Vagrant
Automates VM creation and provisioning.
- Reads `Vagrantfile`
- Boots VM with fixed private IP
- Executes shell provisioning script automatically
- Mounts project folder as `/vagrant` inside VM

### Debian Bookworm (`debian/bookworm64`)
Base OS image of VM.

### K3s
Lightweight Kubernetes distribution.
- In Part 2, it runs as **server mode** on single node.
- Includes components needed for Deployments, Services, Ingress.

### Traefik (Ingress Controller)
Default Ingress Controller in K3s.
- Watches Ingress resources
- Receives HTTP traffic
- Routes to target Kubernetes Services

### nginx (`nginx:stable-alpine`)
Used by all 3 apps as the web server.
- Multi-arch compatible (works on many CPU architectures)
- Stable and lightweight

### busybox initContainer
Creates app-specific HTML at pod startup (including pod hostname).

---

## 3) Architecture

```
Host machine
└── VM: aliS (192.168.56.110)
    ├── K3s Server (single-node cluster)
    ├── app-one Deployment (1 pod) + Service
    ├── app-two Deployment (3 pods) + Service
    ├── app-three Deployment (1 pod) + Service
    └── Ingress (Traefik rules)
```

External request path:

1. Request arrives to VM IP `192.168.56.110`
2. Traefik receives it
3. Traefik checks `Host` header
4. Routes to matching Service
5. Service load-balances to one of its pods

---

## 4) File Structure and Responsibilities

```
p2/
├── Vagrantfile
├── scripts/
│   └── server_setup.sh
└── confs/
    ├── app-one.yaml
    ├── app-two.yaml
    ├── app-three.yaml
    └── ingress.yaml
```

### `Vagrantfile`
- Defines one VM: `aliS`
- Fixed IP: `192.168.56.110`
- Resources: `1 CPU`, `1024 MB RAM`
- Runs `scripts/server_setup.sh`

### `scripts/server_setup.sh`
Provisioning steps:
1. install `curl`
2. install K3s server (`--node-ip=192.168.56.110`, kubeconfig mode 644)
3. wait until K3s reports node as Ready
4. apply all Kubernetes manifests (`app-one`, `app-two`, `app-three`, `ingress`)

### `confs/app-*.yaml`
Each file contains:
- one `Deployment`
- one `Service` (`ClusterIP`)

### `confs/ingress.yaml`
Ingress rules with `ingressClassName: traefik`.

---

## 5) Kubernetes Concepts in This Part

### Pod
Smallest runnable unit. Each pod runs one nginx container.

### Deployment
Ensures desired number of pods is always running.
- app-one: `replicas: 1`
- app-two: `replicas: 3`
- app-three: `replicas: 1`

### Service (`ClusterIP`)
Stable internal endpoint for pods selected by labels.
- Decouples traffic from ephemeral pod IPs
- Handles internal load balancing

### Ingress
Layer-7 HTTP routing resource.
- Uses host/path rules
- Forwards traffic to Services

### Ingress Controller (Traefik)
Actual process that enforces Ingress rules.

### initContainer + emptyDir
- `initContainer` writes `index.html` before nginx starts
- `emptyDir` shares generated file with nginx container
- Pod hostname is written into HTML to visualize pod identity/load balancing

---

## 6) Detailed Manifest Behavior

## `app-one.yaml`
- Deployment name: `app-one`
- Label: `app: app-one`
- Replicas: `1`
- Container image: `nginx:stable-alpine`
- initContainer writes: `Hello from app1.` and pod hostname
- Service name: `app-one` on port 80

## `app-two.yaml`
- Same pattern as app-one
- Replicas: `3` (important for load-balancing demo)
- initContainer writes: `Hello from app2.`
- Service name: `app-two`

## `app-three.yaml`
- Same pattern
- Replicas: `1`
- initContainer writes: `Hello from app3.`
- Used as default route in Ingress

## `ingress.yaml`
Rules:
- host `app1.com` → service `app-one:80`
- host `app2.com` → service `app-two:80`
- no host match (default rule) → service `app-three:80`

`pathType: Prefix` with `/` means all paths match.

---

## 7) End-to-End Execution Flow

When `vagrant up` is run:

1. VM starts (`aliS`)
2. `server_setup.sh` installs K3s
3. Script waits for cluster readiness
4. Deployments create pods
5. Services expose stable cluster endpoints
6. Ingress becomes active in Traefik
7. Requests route by host header to correct app

---

## 8) How to Run (From Scratch)

```bash
cd p2
vagrant destroy -f
vagrant up
```

SSH into VM:

```bash
vagrant ssh aliS
```

Cluster checks:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc
kubectl get ingress
```

---

## 9) Functional Tests You Should Perform

Inside VM:

```bash
curl -H "Host:app1.com" 192.168.56.110
curl -H "Host:app2.com" 192.168.56.110
curl 192.168.56.110
```

Expected results:
- first call contains `Hello from app1.`
- second call contains `Hello from app2.`
- third call contains `Hello from app3.`

### Show app-two load balancing
Run multiple requests:

```bash
for i in {1..10}; do curl -s -H "Host:app2.com" 192.168.56.110 | grep Pod; done
```

Pod name should vary among app-two replicas.

---

## 10) Browser Testing from Host

Add to host `/etc/hosts`:

```bash
sudo sh -c 'echo "192.168.56.110 app1.com" >> /etc/hosts'
sudo sh -c 'echo "192.168.56.110 app2.com" >> /etc/hosts'
```

Then open:
- `http://app1.com`
- `http://app2.com`
- `http://192.168.56.110`

---

## 11) Defense Script (What to Explain)

A clean explanation order:

1. **Purpose**: one-node K3s cluster with 3 apps and host-based routing.
2. **Infrastructure**: Vagrant creates one Debian VM with static private IP.
3. **Cluster bootstrap**: provisioning installs K3s and waits for readiness.
4. **Workloads**: three Deployments + Services, app-two has 3 replicas.
5. **Traffic**: Ingress + Traefik route by Host header.
6. **Default behavior**: unmatched host goes to app-three.
7. **Proof**: `curl` tests + replica load balancing on app-two.

You can summarize this in one line:

> “Part 2 demonstrates Kubernetes service exposure and host-based HTTP routing through Traefik Ingress on a single-node K3s cluster.”

---

## 12) Common Issues and Fixes

### Ingress returns 404
- Check ingress exists:
  ```bash
  kubectl get ingress
  ```
- Check Traefik pods:
  ```bash
  kubectl get pods -n kube-system | grep -i traefik
  ```

### Services exist but app not reachable
- Verify pods are Running:
  ```bash
  kubectl get pods
  ```
- Check pod logs:
  ```bash
  kubectl logs deploy/app-one
  kubectl logs deploy/app-two
  kubectl logs deploy/app-three
  ```

### Wrong app response
- Confirm `Host` header in curl command.
- Confirm ingress rules in `confs/ingress.yaml`.

### VM provisioning hangs/fails
- Rebuild cleanly:
  ```bash
  vagrant destroy -f
  vagrant up
  ```

---

## 13) Quick Validation Checklist

- [ ] `kubectl get nodes` shows `aliS` Ready
- [ ] `kubectl get pods` shows 5 app pods total (1+3+1)
- [ ] `kubectl get svc` shows `app-one`, `app-two`, `app-three`
- [ ] `kubectl get ingress` shows `app-ingress`
- [ ] `curl -H "Host:app1.com" 192.168.56.110` → app1 message
- [ ] `curl -H "Host:app2.com" 192.168.56.110` → app2 message
- [ ] `curl 192.168.56.110` → app3 message
- [ ] repeated app2 calls show different pod hostnames

---

## 14) Why This Part Matters

Part 2 proves you understand:
- Kubernetes workload primitives (`Deployment`, `Service`)
- traffic entrypoint (`Ingress`)
- practical HTTP routing by domain
- replica-based scaling and load balancing behavior
- infrastructure automation with Vagrant provisioning

This is the bridge between basic cluster setup (Part 1) and GitOps automation (Part 3).
