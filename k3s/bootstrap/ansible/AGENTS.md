# ANSIBLE DIRECTORY

## OVERVIEW
Ansible workspace for provisioning OS nodes and installing a single-node K3s server. Two playbooks are runnable; `bootstrap-flux.yml` is a stub.

## STRUCTURE
```
ansible/
├── ansible.cfg                        # Remote user: k3s; SSH key: ~/.ssh/k3s_cluster
├── inventory/
│   ├── hosts.yml                      # Target nodes (add cluster nodes here)
│   └── group_vars/all.yml             # Shared vars: packages, UFW rules, kernel modules, k3s_version
├── playbooks/
│   ├── provision-nodes.yml            # ✓ Runnable — common + k3s-prereqs roles
│   ├── bootstrap-k3s.yml              # ✓ Runnable — k3s-server role (single-node install)
│   ├── bootstrap-flux.yml             # ✗ Stub — not yet runnable
│   └── site.yml                       # Full entrypoint: runs all phases sequentially
└── roles/
    ├── common/                        # apt upgrade, packages, timezone, UFW, passwordless sudo
    ├── k3s-prereqs/                   # swap disable, kernel modules (br_netfilter, overlay), sysctl
    ├── k3s-server/                    # K3s install, config, kubeconfig fetch, token persistence
    └── flux-bootstrap/                # Stub role (empty)
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Add/remove cluster nodes | `inventory/hosts.yml` | Testbed: 192.168.1.128; target cluster: .40/.41/.42 |
| Change k3s version | `inventory/group_vars/all.yml` | `k3s_version: v1.35.4+k3s1` |
| Flux repo settings | `inventory/group_vars/all.yml` | `flux_owner: jander99`, `flux_repo: homelab`, `flux_branch: master` |
| K3s server config | `roles/k3s-server/` | Writes `/etc/rancher/k3s/config.yaml` on remote |
| Add OS packages/UFW rules | `inventory/group_vars/all.yml` | Common role reads from here |

## CONVENTIONS
- **Variable loading**: `group_vars/` is at `inventory/group_vars/all.yml` — pass `-i inventory/hosts.yml` to every `ansible-playbook` call or variable loading breaks.
- **Remote user**: `k3s` with passwordless sudo; SSH key at `~/.ssh/k3s_cluster`.
- **Python**: remote interpreter explicitly set to `/usr/bin/python3`.
- **kubeconfig**: fetched to `~/.kube/k3s-<hostname>.yaml`; token to `~/.kube/k3s-<hostname>-token`.

## ANTI-PATTERNS
- **Do not run playbooks without verifying target nodes are reachable** — `bootstrap-flux.yml` is a stub and will fail.
- **`secrets-encryption: true` in k3s-server config is a one-way door** — enabling it on a running cluster requires full reinstall to disable.
- **Do not add roles to `bootstrap-flux.yml`** until the Flux bootstrap Ansible integration is designed.
- **Do not change `flannel-backend`** from `vxlan` without understanding the network impact on existing cluster state.

## COMMANDS
```bash
# From this directory:
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml

# Verify connectivity first:
ansible all -i inventory/hosts.yml -m ping
```

## NOTES
- **K3s config written**: `flannel-backend: vxlan`, `secrets-encryption: true`, `write-kubeconfig-mode: 0644`.
- `common` role asserts that required vars (packages list, UFW rules) are non-empty before proceeding.
- `k3s-prereqs` loads `br_netfilter` and `overlay` kernel modules + sets net.bridge sysctl.
- Testbed node (i7-4770k, 192.168.1.128) must be re-IP'd to 192.168.1.4x before joining the HA cluster.
