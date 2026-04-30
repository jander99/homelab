# K3s Ansible Bootstrap

Ansible playbooks for provisioning K3s cluster nodes. Only `provision-nodes.yml` is runnable today — K3s install and Flux CD are stubs pending future work.

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

### Full bootstrap (not yet runnable)

```bash
# Phase 2 and 3 are stubs — these will fail with a clear message.
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -v
```

K3s install (`bootstrap-k3s.yml`) and Flux CD (`bootstrap-flux.yml`) require `roles/k3s-server/` which is not yet implemented.

---

## Inventory

Edit `inventory/hosts.yml` to add or change target nodes. The testbed node (192.168.1.128) is configured by default. Production cluster nodes (192.168.1.40-42) are commented out until they are provisioned.
