# K3s Ansible Bootstrap

Ansible playbooks for provisioning nodes, installing the single-node K3s server, and bootstrapping Flux CD against the GitOps manifests in this repository.

## Prerequisites

### 1. Install Ansible Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Create the k3s User on Each Node

On the target node (via console or existing SSH access), create the user Ansible will connect as:

```bash
sudo useradd -m -s /bin/bash k3s
sudo usermod -aG sudo k3s
sudo passwd k3s
```

### 3. Generate an SSH Key Pair

On your **local machine**, generate a dedicated key for this cluster:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/k3s_cluster -C "k3s-ansible"
```

This creates two files:
- `~/.ssh/k3s_cluster` — private key (never share this)
- `~/.ssh/k3s_cluster.pub` — public key (goes on the nodes)

### 4. Copy the Public Key to Each Node

Use `ssh-copy-id` to push the public key using the k3s user's password:

```bash
ssh-copy-id -i ~/.ssh/k3s_cluster.pub k3s@192.168.1.128
```

You'll be prompted for the k3s user's password once. After this, Ansible can connect without a password.

Verify it works:

```bash
ssh -i ~/.ssh/k3s_cluster k3s@192.168.1.128
```

Repeat for each node listed in `inventory/hosts.yml`.

---

## Running the Playbooks

### Provision nodes (OS hardening + K3s prerequisites)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml -v
```

This applies the `common` and `k3s-prereqs` roles, which:
- Runs `apt` dist-upgrade and installs required packages
- Sets timezone, configures UFW firewall rules
- Disables swap permanently
- Loads `br_netfilter` and `overlay` kernel modules
- Applies sysctl settings for Kubernetes networking

### Install K3s server

```bash
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml -v
```

Installs K3s v1.35.4+k3s1 on all `k3s_servers` hosts. On success, kubeconfig is fetched to
`~/.kube/k3s-<hostname>.yaml` and the node join token is saved to `~/.kube/k3s-<hostname>-token`.

```bash
KUBECONFIG=~/.kube/k3s-testbed.yaml kubectl get nodes
```

### Bootstrap Flux CD

`bootstrap-flux.yml` runs on the Ansible controller using the kubeconfig fetched by `bootstrap-k3s.yml`. It installs the pinned Flux and age CLIs if needed, creates the `flux-system/sops-age` Secret before reconciliation, and runs `flux bootstrap github` against the repository settings in `inventory/group_vars/all.yml`.

Before running it:

- Verify `flux_github_owner`, `flux_github_repo`, and `flux_git_branch` in `inventory/group_vars/all.yml`.
- Export a GitHub token with repository write access.
- Back up the generated age private key at `~/.kube/k3s-homelab-age.agekey` after first run.

```bash
export GITHUB_TOKEN=ghp_xxxx
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-flux.yml -v
```

### Full bootstrap

```bash
export GITHUB_TOKEN=ghp_xxxx
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v
```

`site.yml` runs provisioning, K3s installation, and Flux bootstrap in order. Flux will reconcile `k3s/clusters/homelab/` from the configured Git branch.

---

## Inventory

Edit `inventory/hosts.yml` to add or change target nodes. The testbed node (192.168.1.128) is configured by default. Production cluster nodes (192.168.1.40-42) are commented out until they are provisioned.
