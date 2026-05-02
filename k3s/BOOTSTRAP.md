# K3s Bootstrap Guide

This guide covers bootstrapping a single-node K3s cluster using Ansible, then optionally scaling to a multi-node HA setup.

> **Current state**: Single-node K3s server on the testbed (`192.168.1.128`) with SQLite datastore. HA cluster, Longhorn, and Flux CD are future work — see [Part 2](#part-2-scaling-to-ha-future-state) for the upgrade path.

---

## Part 1: Single-Node K3s Bootstrap

### Overview

The Ansible playbooks automate the entire K3s server installation:

1. **`provision-nodes.yml`** — OS hardening, packages, UFW firewall, kernel modules, sysctl
2. **`bootstrap-k3s.yml`** — K3s server install, configuration, kubeconfig fetch, token persistence

Run them in order on a single testbed node. The result is a working single-node K3s cluster using SQLite (the default and recommended datastore for single-node deployments).

### Prerequisites

#### Hardware

- **One Ubuntu Server node** with a static IP address (default: `192.168.1.128`)
  - Minimum 2 GB RAM (4 GB recommended)
  - Minimum 20 GB disk
  - 1 CPU core (2+ recommended)

#### Software

- **Fresh Ubuntu Server** installation, fully updated
- **`k3s` user account** with passwordless sudo (created by Ansible)
- **Direct console/SSH access** to the node for initial setup

#### Control Machine

Your workstation (where you run Ansible) needs:

```bash
# Install Ansible and required collections
pip install ansible
ansible-galaxy collection install -r k3s/bootstrap/ansible/requirements.yml

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
ansible --version
kubectl version --client
```

### Step 1: Configure the Testbed Node

Before Ansible can reach the node, set up SSH access manually on the testbed:

```bash
# On the testbed node (192.168.1.128):
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh

# Create the k3s user with passwordless sudo
sudo useradd -m -s /bin/bash k3s
echo "k3s:changeme" | sudo chpasswd  # Change this immediately
sudo bash -c 'echo "k3s ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/k3s'

# Copy your SSH public key
mkdir -p ~k3s/.ssh && chmod 700 ~k3s/.ssh
# From your control machine:
ssh-copy-id k3s@192.168.1.128
```

> **Note:** The `common` Ansible role also configures passwordless sudo for the `k3s` user. If you prefer to let Ansible handle this entirely, you only need initial SSH access to run `provision-nodes.yml`.

### Step 2: Verify Inventory

The inventory at `k3s/bootstrap/ansible/inventory/hosts.yml` defines the testbed node:

```yaml
all:
  children:
    k3s_servers:
      hosts:
        testbed:
          ansible_host: 192.168.1.128
```

Verify connectivity:

```bash
cd k3s/bootstrap/ansible
ansible all -i inventory/hosts.yml -m ping
```

### Step 3: Review Group Variables

Key settings in `inventory/group_vars/all.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `k3s_version` | `v1.35.4+k3s1` | K3s release to install |
| `timezone` | `America/New_York` | Node timezone |
| `k3s_firewall_rules` | SSH, API, kubelet, Flannel | UFW ports to open |
| `k3s_kernel_modules` | `br_netfilter`, `overlay` | Required kernel modules |
| `k3s_sysctl_params` | bridge-nf, ip-forward, swappiness | Required sysctl settings |

Role-specific defaults are in `roles/k3s-server/defaults/main.yml` — override them in `group_vars/all.yml` or via `-e` flags.

### Step 4: Install Required Ansible Collections

```bash
cd k3s/bootstrap/ansible
ansible-galaxy collection install -r requirements.yml
```

### Step 5: Run Provision Nodes Playbook

This hardens the OS, installs packages, configures UFW, and sets up kernel parameters:

```bash
cd k3s/bootstrap/ansible
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml
```

If the playbook reboots the node (due to kernel updates), wait for SSH to come back and re-run:

```bash
# Wait for the node to come back up
ssh k3s@192.168.1.128 "uptime"
# Re-run if the playbook was interrupted by a reboot
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml
```

### Step 6: Bootstrap K3s Server

This installs K3s, writes the config, fetches the kubeconfig, and persists the join token:

```bash
cd k3s/bootstrap/ansible
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml
```

#### What this playbook does

1. Validates that `k3s_version` is defined
2. Creates `/etc/rancher/k3s/` and writes `config.yaml` with:
   - `write-kubeconfig-mode: "0600"` — root-only kubeconfig on the node
   - `secrets-encryption: true` — encrypts Kubernetes Secrets at rest
   - `flannel-backend: vxlan` — default CNI backend
3. Downloads and installs the K3s binary (`INSTALL_K3S_SKIP_START=true`)
4. Enables and starts the `k3s` systemd service
5. Waits for the API server (port 6443) and node Ready state
6. Reads the node token from `/var/lib/rancher/k3s/server/node-token`
7. Persists the token locally at `~/.kube/k3s-testbed-token` (mode `0600`)
8. Fetches `/etc/rancher/k3s/k3s.yaml` to `~/.kube/k3s-testbed.yaml`
9. Secures the local kubeconfig (mode `0600`)
10. Replaces `127.0.0.1` with the node's actual IP in the kubeconfig

> **Important:** `secrets-encryption: true` is a one-way door. Enable it before deploying any workloads. If you toggle it after workloads exist, existing Secrets will not be re-encrypted until you manually rotate the encryption key.

### Step 7: Verify the Cluster

```bash
# Use the fetched kubeconfig
export KUBECONFIG=~/.kube/k3s-testbed.yaml

# Check node status
kubectl get nodes
# Expected: one node in Ready state

# Check system pods
kubectl get pods -A

# Verify Secrets encryption
kubectl get secrets -A -o yaml | grep -c 'encrypted'
```

You should see:
- One `Ready` node (the testbed)
- System pods running: `local-path-provisioner`, `coredns`, `metrics-server`, `kube-proxy`
- No Longhorn or Flux pods (those are future work)

### Step 8: Use the Cluster

```bash
export KUBECONFIG=~/.kube/k3s-testbed.yaml

# Deploy a test workload
kubectl create deployment nginx --image=nginx:alpine --replicas=1
kubectl expose deployment nginx --port=80 --target-port=80
kubectl get pods,svc

# Clean up
kubectl delete deployment,svc nginx
```

### Security Notes

- **Kubeconfig on the node** is mode `0600` (root-only). On your control machine it is also `0600`.
- **Node join token** is persisted at `~/.kube/k3s-testbed-token` (mode `0600`). You will need this token if you later add nodes for HA.
- **Secrets at rest** are encrypted. Keep the encryption key safe — it lives at `/var/lib/rancher/k3s/server/encryption-config.json` on the node.
- **UFW firewall** is configured with only the required ports open (SSH, API server, kubelet, Flannel).

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|------|
| `ansible all -m ping` fails | SSH not reachable or wrong key | Verify `~/.ssh/k3s_cluster` key, check IP in `hosts.yml` |
| K3s install fails at download | `get.k3s.io` unreachable or wrong version string | Verify `k3s_version` in `group_vars/all.yml` matches a real K3s release |
| Node stuck in `NotReady` | Flannel or kubelet not started | `sudo journalctl -u k3s -n 100` on the node |
| `kubectl` cannot connect | Wrong IP in kubeconfig | Check `server:` line in `~/.kube/k3s-testbed.yaml` |
| Re-run playbook restarts K3s | Config file changed | Normal — Ansible detects config drift and restarts the service |

### Running the Full Entrypoint

The `site.yml` playbook runs all phases in sequence:

```bash
cd k3s/bootstrap/ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

> **Note:** `site.yml` currently runs Phase 1 (provision) and Phase 2 (K3s bootstrap). Phase 3 (Flux) is not yet implemented and will fail with a clear message.

---

## Part 2: Scaling to HA (Future State)

> **Warning:** This section describes a future upgrade path. None of this is implemented yet. The single-node cluster uses SQLite as its datastore, which does not support in-place migration to embedded etcd. Moving from single-node SQLite to multi-node HA **requires a fresh cluster install** — there is no upgrade path that preserves state.

### Prerequisites Before Scaling

Before adding nodes, you must:

1. **Back up the SQLite datastore** from `/var/lib/rancher/k3s/server/db/state.db` on the testbed.
2. **Save the node join token** — it is stored at `~/.kube/k3s-testbed-token` on your control machine.
3. **Ensure all workloads have GitOps-managed definitions** so they can be re-applied after a fresh install.

### Step 1: Provision Additional Nodes

Add nodes to `inventory/hosts.yml`:

```yaml
all:
  children:
    k3s_servers:
      hosts:
        testbed:
          ansible_host: 192.168.1.128
        # Uncomment and re-IP after provisioning:
        # k3s-node-1:
        #   ansible_host: 192.168.1.40
        # k3s-node-2:
        #   ansible_host: 192.168.1.41
        # k3s-node-3:
        #   ansible_host: 192.168.1.42
```

Run `provision-nodes.yml` on the new nodes to harden them.

### Step 2: Restore etcd Ports in UFW

Add these back to `inventory/group_vars/all.yml`:

```yaml
k3s_firewall_rules:
  # ... existing rules ...
  - { port: 2379, proto: tcp, comment: "etcd client requests" }   # HA only
  - { port: 2380, proto: tcp, comment: "etcd peer communication" } # HA only
```

### Step 3: Initialize the First HA Node

On the first server, set `k3s_init_cluster: true` in `group_vars/all.yml` or via the command line:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml \
  -e "k3s_init_cluster=true"
```

This reconfigures K3s to use embedded etcd instead of SQLite and starts the HA cluster.

> **Destructive operation:** Enabling `cluster-init: true` on an existing SQLite node will not migrate data. Back up workloads and re-apply them after the cluster is re-initialized.

### Step 4: Join Additional Nodes

On each additional server:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml \
  -e "k3s_server_url=https://192.168.1.128:6443" \
  -e "k3s_token=<saved-join-token>"
```

### Step 5: Verify HA Cluster

```bash
kubectl get nodes
# Expected: 3 (or more) nodes in Ready state

kubectl get pods -n kube-system -l component=etcd
# Expected: etcd pods on each server
```

### Future Phases

These are not yet implemented and are listed here for planning purposes only:

| Phase | Component | Status |
|-------|-----------|--------|
| Flux CD | GitOps automation | Stub only (`bootstrap-flux.yml`) |
| Longhorn | Distributed block storage | Not started |
| Nginx Ingress | HTTP load balancer | Not started (Traefik is the default K3s ingress) |
| Cert Manager | TLS certificate automation | Not started |
| SOPS + age | Secret encryption in Git | Not started |
| CDK8s | TypeScript-defined manifests | Not started |
| Velero | Backup/restore | Not started |

Refer to `k3s/k3s.md` for the full target architecture.