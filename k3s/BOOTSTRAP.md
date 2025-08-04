# K3s Cluster Bootstrap Guide

This guide covers bootstrapping a fresh K3s cluster from clean Ubuntu Server installations with minimal manual intervention. This guide is designed for Kubernetes beginners and provides detailed explanations of each step.

## What is K3s?

K3s is a lightweight Kubernetes distribution designed for production workloads in resource-constrained environments. It packages all Kubernetes components into a single binary and removes many optional features to reduce memory and storage footprint.

**Key K3s Features:**
- Single binary installation (~100MB)
- Built-in container runtime (containerd)
- Embedded etcd for HA clusters
- Automatic TLS certificate management
- Built-in local storage provider
- Simplified networking with Flannel CNI

## Prerequisites

### Hardware Requirements
- **3 Ubuntu Server nodes** with static IP addresses (192.168.1.40-42)
  - Minimum 2GB RAM per node (4GB recommended)
  - Minimum 20GB disk space per node
  - 1 CPU core per node (2+ recommended)

### Software Requirements
- **Fresh Ubuntu Server installations** (latest version, fully updated)
- **k3s user account** with same password on all nodes
- **Direct terminal access** to each node (monitor/keyboard or IPMI/iLO)

### Control Machine Setup
Your control machine (where you run commands) needs:

```bash
# Install Ansible (Ubuntu/Debian)
sudo apt update
sudo apt install -y ansible sshpass

# Install kubectl for cluster management
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Flux CLI for GitOps
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify installations
ansible --version
kubectl version --client
flux version --client
```

## Phase 1: Manual Node Preparation

These steps must be performed manually on each node via direct terminal access.

### Step 1: Enable SSH Service

**Why SSH?** SSH (Secure Shell) allows secure remote access to your nodes. Ansible uses SSH to automate tasks across multiple machines.

Perform these steps **on each node** (192.168.1.40, 192.168.1.41, 192.168.1.42):

```bash
# Update package list and install SSH server
sudo apt update
sudo apt install -y openssh-server

# Enable SSH to start automatically on boot
sudo systemctl enable ssh

# Start SSH service immediately
sudo systemctl start ssh

# Verify SSH is running (should show "active (running)")
sudo systemctl status ssh
```

**Expected Output:**
```
● ssh.service - OpenBSD Secure Shell server
   Loaded: loaded (/lib/systemd/system/ssh.service; enabled; vendor preset: enabled)
   Active: active (running) since [timestamp]
   Process: [PID] ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: [PID] (sshd)
```

```bash
# Configure firewall to allow SSH (if UFW is enabled)
sudo ufw status
# If firewall is active, allow SSH:
sudo ufw allow ssh

# Optional: Check which port SSH is running on (default: 22)
sudo ss -tlnp | grep :22
```

### Step 2: Configure SSH for k3s User

**Why these permissions?** SSH requires strict file permissions for security. The `.ssh` directory must be readable only by the owner (700), and `authorized_keys` must not be writable by others (600).

Perform these steps **on each node**:

```bash
# Switch to the k3s user account
su - k3s
# You'll be prompted for the k3s user password

# Verify you're now the k3s user
whoami
# Should output: k3s

# Create SSH directory with proper permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create authorized_keys file (will store public keys later)
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Verify permissions are correct
ls -la ~/.ssh/
```

**Expected Output:**
```
drwx------ 2 k3s k3s 4096 [date] .
drwxr-xr-x 3 k3s k3s 4096 [date] ..
-rw------- 1 k3s k3s    0 [date] authorized_keys
```

```bash
# Exit back to the original user
exit
```

### Step 3: Test SSH Connectivity

**Important:** This step verifies that SSH is working before we set up key-based authentication.

From your **control machine**, test SSH access to each node:

```bash
# Test SSH connection to master node
ssh k3s@192.168.1.40
# Enter the k3s user password when prompted
# You should see the Ubuntu welcome message and shell prompt
# Type 'exit' to disconnect

# Test SSH connection to worker node 1
ssh k3s@192.168.1.41
# Enter password, verify connection, then exit

# Test SSH connection to worker node 2
ssh k3s@192.168.1.42
# Enter password, verify connection, then exit
```

**Troubleshooting SSH Issues:**
- **Connection refused:** Check if SSH service is running: `sudo systemctl status ssh`
- **Permission denied:** Verify k3s user password is correct
- **Network unreachable:** Verify IP addresses and network connectivity: `ping 192.168.1.40`
- **Firewall blocking:** Check UFW status: `sudo ufw status`

## Phase 2: SSH Key Setup and Distribution

### Step 4: Generate SSH Key Pair

**Why SSH Keys?** SSH keys provide secure, password-less authentication. The private key stays on your control machine, while public keys are distributed to the nodes.

On your **control machine**:

```bash
# Generate ED25519 SSH key pair (more secure than RSA)
ssh-keygen -t ed25519 -f ~/.ssh/k3s_cluster -N ""
```

**Command Explanation:**
- `-t ed25519`: Use ED25519 algorithm (modern, secure)
- `-f ~/.ssh/k3s_cluster`: Save key as 'k3s_cluster' in SSH directory
- `-N ""`: No passphrase (empty string)

**Expected Output:**
```
Generating public/private ed25519 key pair.
Your identification has been saved in /home/[user]/.ssh/k3s_cluster
Your public key has been saved in /home/[user]/.ssh/k3s_cluster.pub
The key fingerprint is:
SHA256:[fingerprint] [user]@[hostname]
```

```bash
# Start SSH agent to manage keys
eval "$(ssh-agent -s)"
# Should output: Agent pid [number]

# Add private key to SSH agent
ssh-add ~/.ssh/k3s_cluster
# Should output: Identity added: ~/.ssh/k3s_cluster

# Verify key was added
ssh-add -l
# Should show your key fingerprint
```

### Step 5: Distribute SSH Keys

**What happens here?** The `ssh-copy-id` command copies your public key to each node's `~/.ssh/authorized_keys` file, enabling password-less SSH access.

From your **control machine**:

```bash
# Copy public key to master node
ssh-copy-id -i ~/.ssh/k3s_cluster.pub k3s@192.168.1.40
# Enter k3s password when prompted
```

**Expected Output:**
```
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/[user]/.ssh/k3s_cluster.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now, it is to install the new key(s)
k3s@192.168.1.40's password:

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'k3s@192.168.1.40'"
and check to make sure that only the key(s) you wanted were added.
```

```bash
# Copy public key to worker node 1
ssh-copy-id -i ~/.ssh/k3s_cluster.pub k3s@192.168.1.41
# Enter k3s password when prompted

# Copy public key to worker node 2
ssh-copy-id -i ~/.ssh/k3s_cluster.pub k3s@192.168.1.42
# Enter k3s password when prompted

# Test password-less SSH access
ssh -i ~/.ssh/k3s_cluster k3s@192.168.1.40 'hostname'
# Should output the hostname without prompting for password
ssh -i ~/.ssh/k3s_cluster k3s@192.168.1.41 'hostname'
ssh -i ~/.ssh/k3s_cluster k3s@192.168.1.42 'hostname'
```

### Step 6: Configure SSH Client

**Why SSH Config?** This creates friendly hostnames and sets default connection parameters, making it easier to connect to nodes.

Edit your SSH config file:

```bash
# Create or edit SSH config file
nano ~/.ssh/config
```

Add this configuration:

```
# K3s Cluster Nodes
Host k3s-master
    HostName 192.168.1.40
    User k3s
    IdentityFile ~/.ssh/k3s_cluster
    StrictHostKeyChecking no

Host k3s-worker1
    HostName 192.168.1.41
    User k3s
    IdentityFile ~/.ssh/k3s_cluster
    StrictHostKeyChecking no

Host k3s-worker2
    HostName 192.168.1.42
    User k3s
    IdentityFile ~/.ssh/k3s_cluster
    StrictHostKeyChecking no

# Wildcard for all k3s nodes
Host k3s-*
    UserKnownHostsFile /dev/null
    LogLevel ERROR
```

**Configuration Explanation:**
- `HostName`: Actual IP address of the node
- `User`: Username to connect as (k3s)
- `IdentityFile`: Private key to use for authentication
- `StrictHostKeyChecking no`: Don't prompt about host key verification
- `UserKnownHostsFile /dev/null`: Don't save host keys
- `LogLevel ERROR`: Reduce SSH output verbosity

```bash
# Set proper permissions on SSH config
chmod 600 ~/.ssh/config

# Test friendly hostnames
ssh k3s-master 'hostname'
ssh k3s-worker1 'hostname'
ssh k3s-worker2 'hostname'
```

## Phase 3: Ansible Configuration

### Step 7: Setup Ansible Inventory

**What is Ansible Inventory?** An inventory file tells Ansible which hosts to manage and how to connect to them. It groups hosts by role (masters, workers) and sets connection parameters.

Create the directory structure:

```bash
# Create Ansible directory structure
mkdir -p k3s/bootstrap/ansible/inventory
mkdir -p k3s/bootstrap/ansible/playbooks
mkdir -p k3s/bootstrap/ansible/group_vars
mkdir -p k3s/bootstrap/ansible/host_vars
```

Create the inventory file:

```bash
# Create inventory file
nano k3s/bootstrap/ansible/inventory/hosts
```

Add this content:

```ini
# K3s Cluster Inventory
# Groups hosts by role and defines connection parameters

[k3s_cluster:children]
masters
workers

[masters]
k3s-master ansible_host=192.168.1.40

[workers]
k3s-worker1 ansible_host=192.168.1.41
k3s-worker2 ansible_host=192.168.1.42

# Global variables for all K3s cluster nodes
[k3s_cluster:vars]
ansible_user=k3s
ansible_ssh_private_key_file=~/.ssh/k3s_cluster
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3

# Master node specific variables
[masters:vars]
node_role=master
k3s_server=true

# Worker node specific variables
[workers:vars]
node_role=worker
k3s_server=false
```

**Inventory Explanation:**
- `[k3s_cluster:children]`: Creates a parent group containing masters and workers
- `ansible_host`: Actual IP address to connect to
- `ansible_user`: Username for SSH connections
- `ansible_ssh_private_key_file`: Path to SSH private key
- `ansible_python_interpreter`: Python path (required for Ubuntu)
- `k3s_server`: Determines if node runs K3s server or agent

### Step 8: Test Ansible Connectivity

**What does this test?** The ping module verifies Ansible can connect to all nodes via SSH and execute Python commands.

```bash
# Navigate to Ansible directory
cd k3s/bootstrap/ansible/

# Test connectivity to all nodes
ansible all -i inventory/hosts -m ping
```

**Expected Output:**
```
k3s-master | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
k3s-worker1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
k3s-worker2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

```bash
# Test individual groups
ansible masters -i inventory/hosts -m ping
ansible workers -i inventory/hosts -m ping

# Gather system information from all nodes
ansible all -i inventory/hosts -m setup -a "filter=ansible_distribution*"
```

**Troubleshooting Ansible Connection Issues:**
- **UNREACHABLE**: Check SSH connectivity manually: `ssh k3s-master`
- **Authentication failure**: Verify SSH keys: `ssh-add -l`
- **Python not found**: Install Python3: `ansible all -i inventory/hosts -m raw -a "sudo apt install python3 -y"`

## Phase 4: Automated Bootstrap with Ansible

### Step 9: Node Provisioning

**What does provisioning do?** Prepares Ubuntu nodes for K3s by installing dependencies, configuring system settings, and ensuring all prerequisites are met.

Before running the playbook, let's understand what will happen:

**System Updates:**
- Updates all packages to latest versions
- Installs essential tools (curl, wget, git, etc.)

**Kubernetes Prerequisites:**
- Disables swap (Kubernetes requirement)
- Loads required kernel modules (br_netfilter, overlay)
- Configures sysctl settings for networking
- Installs container runtime dependencies

**Security Configuration:**
- Configures UFW firewall rules for K3s ports
- Sets up log rotation for K3s logs

Run the node provisioning playbook:

```bash
ansible-playbook -i inventory/hosts playbooks/provision-nodes.yml -v
```

**Expected Duration:** 5-10 minutes depending on internet speed and system performance.

**Key Ports Opened:**
- `6443/tcp`: Kubernetes API server
- `10250/tcp`: Kubelet API
- `8472/udp`: Flannel VXLAN
- `51820/udp`: Flannel Wireguard (if enabled)

**Validation Commands:**
```bash
# Verify swap is disabled on all nodes
ansible all -i inventory/hosts -m shell -a "free -h | grep Swap"
# Should show 0B for swap

# Check kernel modules are loaded
ansible all -i inventory/hosts -m shell -a "lsmod | grep br_netfilter"

# Verify firewall rules
ansible all -i inventory/hosts -m shell -a "sudo ufw status numbered"
```

### Step 10: K3s Cluster Bootstrap

**What happens during K3s bootstrap?**

**Master Node Setup:**
1. Downloads and installs K3s binary
2. Starts K3s server with embedded etcd
3. Generates cluster token for worker nodes
4. Creates kubeconfig file for cluster access
5. Configures local storage and networking

**Worker Node Setup:**
1. Downloads and installs K3s binary
2. Connects to master using cluster token
3. Starts K3s agent process
4. Joins cluster and registers as available node

**Storage Configuration:**
1. Installs Longhorn distributed storage
2. Creates storage classes for persistent volumes
3. Configures 3-way replication for data safety

Run the K3s bootstrap playbook:

```bash
ansible-playbook -i inventory/hosts playbooks/bootstrap-k3s.yml -v
```

**Expected Duration:** 10-15 minutes (depends on internet speed for downloading images)

**What to watch for:**
- Master node: Should show "K3s server started successfully"
- Worker nodes: Should show "Joined cluster successfully"
- Storage: Longhorn pods should enter Running state

**Validation Commands:**
```bash
# Check K3s service status on all nodes
ansible all -i inventory/hosts -m shell -a "sudo systemctl status k3s || sudo systemctl status k3s-agent"

# Verify cluster token was generated
ansible masters -i inventory/hosts -m shell -a "sudo cat /var/lib/rancher/k3s/server/node-token"

# Check cluster nodes from master
ansible masters -i inventory/hosts -m shell -a "sudo k3s kubectl get nodes -o wide"
```

**Expected Node Output:**
```
NAME          STATUS   ROLES                  AGE   VERSION        INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k3s-master    Ready    control-plane,master   1m    v1.28.x+k3s1   192.168.1.40   <none>        Ubuntu 24.04.x LTS   6.8.0-xx-generic    containerd://1.7.x
k3s-worker1   Ready    <none>                 1m    v1.28.x+k3s1   192.168.1.41   <none>        Ubuntu 24.04.x LTS   6.8.0-xx-generic    containerd://1.7.x
k3s-worker2   Ready    <none>                 1m    v1.28.x+k3s1   192.168.1.42   <none>        Ubuntu 24.04.x LTS   6.8.0-xx-generic    containerd://1.7.x
```

### Step 11: Flux CD Bootstrap

**What is Flux CD?** Flux is a GitOps operator that automatically syncs your Kubernetes cluster with a Git repository. When you commit changes to your repo, Flux deploys them to the cluster.

**GitOps Benefits:**
- **Declarative**: Infrastructure defined as code
- **Versioned**: All changes tracked in Git
- **Automated**: No manual kubectl commands needed
- **Auditable**: Full change history and rollback capability

**Prerequisites for Flux:**
- GitHub repository (this homelab repository)
- GitHub Personal Access Token with repo permissions
- Flux CLI installed on control machine

**Setup GitHub Token:**
1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token with `repo` scope
3. Save token securely

```bash
# Export GitHub token (replace with your actual token)
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Verify token works
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user
```

Run the Flux bootstrap playbook:

```bash
ansible-playbook -i inventory/hosts playbooks/bootstrap-flux.yml -v -e github_token=$GITHUB_TOKEN
```

**Expected Duration:** 5-10 minutes

**What Flux Creates:**
- `flux-system` namespace
- Source controller (monitors Git repository)
- Kustomize controller (applies Kubernetes manifests)
- Helm controller (manages Helm charts)
- Notification controller (sends alerts)

**Validation Commands:**
```bash
# Check Flux components
ansible masters -i inventory/hosts -m shell -a "sudo k3s kubectl get pods -n flux-system"

# Check Flux sources (should show your Git repository)
ansible masters -i inventory/hosts -m shell -a "sudo k3s kubectl get gitrepositories -A"

# Check Flux kustomizations
ansible masters -i inventory/hosts -m shell -a "sudo k3s kubectl get kustomizations -A"
```

**Expected Flux Pods:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
source-controller-xxx                      1/1     Running   0          2m
kustomize-controller-xxx                   1/1     Running   0          2m
helm-controller-xxx                        1/1     Running   0          2m
notification-controller-xxx                1/1     Running   0          2m
```

## Phase 5: Verification

### Step 12: Cluster Health Check

**Why health checks?** These commands verify that all cluster components are working correctly and the cluster is ready for workloads.

**Setup kubectl Access:**

```bash
# Copy kubeconfig from master node to control machine
scp k3s-master:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config

# Update server IP in kubeconfig (K3s defaults to 127.0.0.1)
sed -i 's/127.0.0.1/192.168.1.40/g' ~/.kube/k3s-config

# Set KUBECONFIG environment variable
export KUBECONFIG=~/.kube/k3s-config

# Make this permanent by adding to ~/.bashrc
echo "export KUBECONFIG=~/.kube/k3s-config" >> ~/.bashrc
```

**Essential Health Checks:**

```bash
# 1. Verify all nodes are Ready
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME          STATUS   ROLES                  AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE           KERNEL-VERSION     CONTAINER-RUNTIME
k3s-master    Ready    control-plane,master   10m   v1.28.x   192.168.1.40   <none>        Ubuntu 24.04 LTS   6.8.0-xx-generic   containerd://1.7.x
k3s-worker1   Ready    <none>                 10m   v1.28.x   192.168.1.41   <none>        Ubuntu 24.04 LTS   6.8.0-xx-generic   containerd://1.7.x
k3s-worker2   Ready    <none>                 10m   v1.28.x   192.168.1.42   <none>        Ubuntu 24.04 LTS   6.8.0-xx-generic   containerd://1.7.x
```

```bash
# 2. Check all system pods are running
kubectl get pods -A
```

**Expected System Pods:**
- kube-system: coredns, local-path-provisioner, metrics-server, traefik
- longhorn-system: longhorn-manager, longhorn-driver, longhorn-ui
- flux-system: source-controller, kustomize-controller, helm-controller

```bash
# 3. Verify Longhorn storage system
kubectl get pods -n longhorn-system
kubectl get storageclass
```

**Expected Storage Classes:**
```
NAME                   PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
longhorn (default)     driver.longhorn.io   Delete          Immediate              true                   5m
local-path             rancher.io/local-path Delete          WaitForFirstConsumer   false                  10m
```

```bash
# 4. Check Flux CD status
flux get all -A
```

**Expected Flux Resources:**
```
NAMESPACE     NAME          REVISION        SUSPENDED       READY   MESSAGE
flux-system   flux-system   main@sha1:xxx   False           True    Applied revision: main@sha1:xxx

NAMESPACE     NAME          REVISION        SUSPENDED       READY   MESSAGE  
flux-system   flux-system   main@sha1:xxx   False           True    Applied revision: main@sha1:xxx
```

```bash
# 5. Test cluster DNS resolution
kubectl run test-dns --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default
```

**Expected DNS Output:**
```
Server:    10.43.0.10
Address 1: 10.43.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.43.0.1 kubernetes.default.svc.cluster.local
```

### Step 13: Initial Application Deployment

**Testing GitOps Workflow:** This verifies that Flux can detect changes in your Git repository and deploy them to the cluster.

**Manual Flux Reconciliation:**

```bash
# Force Flux to check for new changes immediately
flux reconcile source git flux-system
```

**Expected Output:**
```
✓ applied revision main@sha1:xxxxxxxxxxxxx
```

```bash
# Check if any kustomizations need reconciliation
flux reconcile kustomization flux-system

# Monitor all pods across all namespaces
kubectl get pods -A -w
# Press Ctrl+C to stop watching
```

**Deploy a Test Application:**

Create a simple test deployment to verify the cluster is working:

```bash
# Create test namespace and deployment
kubectl create namespace test
kubectl create deployment nginx --image=nginx:alpine -n test
kubectl expose deployment nginx --port=80 --target-port=80 -n test

# Check deployment status
kubectl get pods -n test -w
# Wait for pod to show "Running" status

# Test internal connectivity
kubectl run test-client --image=busybox:1.28 --rm -it --restart=Never -n test -- wget -qO- nginx
# Should return HTML from nginx

# Clean up test resources
kubectl delete namespace test
```

**Verify Longhorn Storage:**

```bash
# Create a PVC to test storage
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
EOF

# Check PVC status (should show "Bound")
kubectl get pvc test-pvc

# Check Longhorn volume was created
kubectl get volumes -n longhorn-system

# Clean up test PVC
kubectl delete pvc test-pvc
```

**Access Cluster Services:**

```bash
# Get Traefik (ingress controller) service
kubectl get svc -n kube-system traefik

# Get Longhorn UI service (if enabled)
kubectl get svc -n longhorn-system longhorn-frontend

# Port forward to access Longhorn UI from control machine
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80 &
# Open browser to http://localhost:8080
# Kill port-forward: killall kubectl
```

## Troubleshooting

### Common Issues

1. **SSH Connection Refused**
   - Verify SSH service is running: `sudo systemctl status ssh`
   - Check firewall rules: `sudo ufw status`

2. **Ansible Connection Timeout**
   - Verify SSH key authentication: `ssh -i ~/.ssh/k3s_cluster k3s@<node-ip>`
   - Check inventory file syntax

3. **K3s Installation Failures**
   - Check node system requirements (RAM, disk space)
   - Verify network connectivity between nodes
   - Review K3s logs: `sudo journalctl -u k3s`

4. **Longhorn Storage Issues**
   - Ensure nodes have required dependencies: `iscsiadm`, `multipath-tools`
   - Check available disk space on each node

5. **Flux Bootstrap Failures**
   - Verify GitHub token permissions
   - Check repository access and branch existence
   - Review Flux controller logs: `kubectl logs -n flux-system -l app=source-controller`

## Next Steps

After successful bootstrap:
1. Configure monitoring stack (Prometheus, Grafana, Loki)
2. Set up ingress controller and certificates
3. Deploy applications using CDK8s or direct manifests
4. Configure backup strategies with Velero
5. Implement network policies and RBAC

## Required Ansible Playbooks

The following playbooks need to be created/updated in `k3s/bootstrap/ansible/playbooks/`:
- `provision-nodes.yml` - System preparation and dependencies
- `bootstrap-k3s.yml` - K3s cluster installation and configuration
- `bootstrap-flux.yml` - Flux CD setup and GitOps configuration