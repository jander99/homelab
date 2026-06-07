# PROJECT KNOWLEDGE BASE

**Updated:** 2026-06-07 · **Branch:** master

## OVERVIEW

Single repo, two production stacks:

- **Docker** — 9 services on a Synology NAS (macvlan networking): media automation, monitoring, networking, utilities. Operational; not migrating.
- **K3s** — single-node testbed (192.168.1.128, SQLite datastore), managed by **Flux CD v2** rooted at `k3s/clusters/homelab/`. Target is 3-node HA on Dell Optiplexes (.40/.41/.42) with embedded etcd; hardware acquired, not yet provisioned.

Flux-managed layers (wider than the previous AGENTS.md suggested):

```
platform  →  infra-controllers  →  infra-configs  →  apps
(namespaces)  (CRD-bearing HelmReleases)  (configs that need those CRDs)  (workloads)
```

- **platform/namespaces/**: cert-manager, headlamp, monitoring, pihole, telemetry
- **infra-controllers/**: cert-manager, metallb, opentelemetry-collector, tempo, dcgm-exporter, external-dns, csi-driver-smb, node-feature-discovery, nvidia-device-plugin
- **infra-configs/**: cert-manager ClusterIssuers, metallb IPAddressPool/L2Advertisement, kube-prometheus-stack (`configs/monitoring/`), Grafana datasources
- **apps/**: headlamp, pihole, portainer, prowlarr, qbittorrent, radarr, recyclarr, sabnzbd, sense-exporter, sonarr, tdarr, unpoller, monitoring

Subdirectory deep-dives: `docker/AGENTS.md`, `docker/media/AGENTS.md`, `docker/prometheus/AGENTS.md`, `k3s/AGENTS.md`, `k3s/infrastructure/AGENTS.md`, `k3s/bootstrap/ansible/AGENTS.md`, `applications/cdk8s/AGENTS.md`. This file is the entry point only.

## DIRECTORY OWNERSHIP

| Path | What lives there | Pointer |
|------|-----------------|---------|
| `docker/<svc>/<svc>-compose.yml` | Compose for one Docker service (one file per service) | `docker/AGENTS.md` |
| `docker/prometheus/etc/{prometheus,alerts}.yml` | Prometheus scrape targets + alerts | `docker/prometheus/AGENTS.md` |
| `docker/scripts/network-setup.sh` | Creates the macvlan network (bridge is created by compose) | — |
| `k3s/bootstrap/ansible/` | Single-node K3s server role; `provision-nodes` + `bootstrap-k3s` | `k3s/bootstrap/ansible/AGENTS.md` |
| `k3s/clusters/homelab/` | Flux Kustomization root (5 Kustomizations + flux-system/) | `k3s/AGENTS.md` |
| `k3s/platform/namespaces/` | All namespaces (do not put namespaces in `configs/`) | — |
| `k3s/infrastructure/controllers/<name>/` | One chart per dir: `helmrelease.yaml` + `helmrepository.yaml` + `kustomization.yaml` | `k3s/infrastructure/AGENTS.md` |
| `k3s/infrastructure/configs/` | ClusterIssuers, IPAddressPools, kube-prometheus-stack, Grafana datasources | same |
| `k3s/applications/<name>/` | Per-app workload manifests (consumed by Flux `apps` Kustomization) | — |
| `applications/cdk8s/` | CDK8s TypeScript stub (HelloChart only). Nx workspace initialized, `synth` target configured. `dist/` is gitignored; promotion to `k3s/applications/` is not yet designed. | `applications/cdk8s/AGENTS.md` |
| `.sops.yaml` | SOPS age rules — `k3s/.*\.sops\.yaml$` is encrypted under the homelab age key | `k3s/AGENTS.md` for the key fingerprint |
| `docs/media-stack-integration-guide.md` | Long-form media-stack reference (12.9K) | — |

## CI / VALIDATION

`flux-validate.yaml` runs on every PR touching `k3s/**`, `applications/cdk8s/**`, or workflow files. Pipeline:

1. `yamllint -c .yamllint.yaml` on `k3s/applications/`, `k3s/infrastructure/`, `k3s/platform/`, `k3s/clusters/homelab/`, `.github/workflows/` (NOT on `docker/**` — pre-existing trailing-space issues are tracked separately)
2. `flux-local test --path k3s/clusters/homelab` (pytest fixtures; expected no-op today)
3. `flux-local diff ks --path k3s/clusters/homelab --branch-orig origin/master` (post-comments on PR)
4. `kubeconformist` and `cdk8s synth` steps are present but disabled (`if: false` placeholders)

`.pre-commit-config.yaml` mirrors the yamllint rules at commit time so the same indentation / duplicate-key / trailing-space checks fire before push.

**.yamllint.yaml** disables `line-length`, `document-start`, `truthy`, `octal-values` (K8s/Helm YAML frequently trips them by design). Indentation (2 spaces, consistent) and `key-duplicates` are the headline rules. `*.sops.yaml` is excluded everywhere (base64 padding, intentional trailing whitespace).

## CONVENTIONS

**Docker** (`docker/AGENTS.md` for the full list):
- Compose files named `<service>-compose.yml`, never `docker-compose.yml`. Exception: `docker/sense-exporter/sense-exporter.yml`.
- External networks only; both `homelab_physical_network` (macvlan) and `homelab_bridge_network` (bridge) are referenced as `external:`. Run `docker/scripts/network-setup.sh` once on a fresh host.
- LinuxServer.io containers: `PUID=1027`, `PGID=100`, `TZ=America/New_York`. Persistent data on `/volume1/data/<service>` and `/volume1/config/<service>`.
- Secrets via `${VAR}` referencing `.env` (gitignored by `**/*.env`).

**K3s** (`k3s/AGENTS.md` for the full list):
- Flux layering is load-bearing: `infra-configs` `dependsOn: [infra-controllers]`. Do not add a new chart that introduces CRDs without also adding the configs Kustomization entry in the right order.
- Namespaces go in `k3s/platform/namespaces/`, never in `k3s/infrastructure/configs/`.
- SOPS-encrypted secrets end in `.sops.yaml`. Encrypt with `sops` CLI; the age private key is at `~/.kube/k3s-homelab-age.agekey` (also deployed as `flux-system/sops-age` Secret in-cluster).

## ANTI-PATTERNS (THIS PROJECT)

- Do not name a compose file `docker-compose.yml` — breaks the convention other tooling (Renovate, scripts) assumes.
- Do not hand-edit `docker/prometheus/snmp_exporter/snmp.yml` — auto-generated; banner says so.
- Do not "fix" the typo `WATHCTOWER_REVIVE_STOPPED` in the watchtower compose — leaving it as-is is intentional.
- Do not enable `kubeEtcd` / `kubeScheduler` / `kubeControllerManager` / `kubeProxy` scrapers in kube-prometheus-stack — K3s binds them to 127.0.0.1 and uses SQLite; they always fail to scrape.
- Do not treat `k3s/k3s.md` as current state — it describes the target, not reality. `k3s/AGENTS.md` and sub-AGENTS.md files are the verified-now sources.
- Do not add real workloads to `applications/cdk8s/src/main.ts` until the `dist/` → `k3s/applications/` promotion workflow is designed and documented.
- Do not force-push to a merged branch. Once a PR is merged, the next fix goes on a **new** branch off current master with a new PR. Editing the merged PR's body is pointless.
- Do not skip the existing branch / worktree / PR workflow (see `.claude/AGENTS.md` and the user-supplied system instructions at session start).

## VERIFICATION GOTCHAS (hard-earned)

The repo's CI validates **structure**, not **semantics**. Recent failure mode:

- `yamllint` and `flux-local diff` will pass on a syntactically valid Helm release that the running chart binary refuses to start. The OTel collector bring-up in #190-#196 took seven PRs because the actual config-schema validation lives inside the running `otelcol-k8s` binary at startup, and there was no CI step that exercised it. The chart preset, the k8s_cluster receiver's `distribution` default, the kubeletstats receiver's `node:` requirement, the `k8snode` (not `k8s_api`) detector name — all rejected by the binary, none of them caught by yamllint or kustomize build.

Rules of thumb for any chart that ships its own config schema (OTel, Prometheus, Grafana dashboards, etc.):

1. **Read the source at the exact git tag the chart uses**, not the README on `main`. README-on-main described a future detector rename that didn't exist in `v0.151.0` (the binary actually running).
2. **Chart version ≠ image tag.** OTel chart `v0.155.0` ships `appVersion: 0.151.0`; pulling `:0.155.0` fails. Pin the image tag explicitly when the chart version and appVersion diverge.
3. **Use the chart's presets as the default, not the fallback.** OTel's `presets.clusterMetrics` / `hostMetrics` / `kubeletMetrics` / `resourceDetection` exist precisely because hand-rolling the same config (ClusterRole, host mounts, leader election) is where bugs creep in. Extend the preset; don't duplicate it.
4. **The right validation step that is missing today:** render the chart with `helm template`, then run the resulting ConfigMap through the real binary's `validate` command (`otelcol-k8s validate --config=...`). Add this as a CI step before adding another chart with custom config.

## COMMANDS

```bash
# Docker stack (one-time + per service)
./docker/scripts/network-setup.sh
cd docker/<service>/ && docker-compose -f <service>-compose.yml up -d

# K3s cluster bootstrap (run on Ansible controller)
cd k3s/bootstrap/ansible/
ansible-playbook -i inventory/hosts.yml playbooks/provision-nodes.yml
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-k3s.yml
ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-flux.yml

# CDK8s synth
yarn nx run cdk8s:synth

# Lint + validate (matches CI)
yamllint -c .yamllint.yaml k3s/applications k3s/infrastructure k3s/platform k3s/clusters/homelab .github/workflows
flux-local test --path k3s/clusters/homelab --skip-invalid-kustomization-paths
flux-local diff ks --path k3s/clusters/homelab --skip-invalid-kustomization-paths --branch-orig origin/master

# SOPS
sops k3s/infrastructure/configs/<file>.sops.yaml     # edit
sops -e -i k3s/infrastructure/configs/<file>.sops.yaml  # encrypt in place

# Cluster inspection (testbed)
KUBECONFIG=~/.kube/k3s-testbed.yaml kubectl get hr,pods -A
```

## NOTES

- **Testbed kubeconfig**: `~/.kube/k3s-testbed.yaml` (fetched by `bootstrap-k3s.yml`). The K3s API is reachable from the LAN.
- **Grafana**: https://grafana.homelab.properties — credentials in BitWarden; SOPS secret at `k3s/infrastructure/configs/monitoring/grafana-secret.sops.yaml`.
- **Watchtower metrics** require `Bearer` token auth at `/v1/metrics` (every other exporter uses plain `/metrics`). Sense and Netgear CM1000 exporters use `/` as the metrics path. Pi-hole DNS chain: pihole → `cloudflared:172.20.1.1:5053` (DoH to 1.1.1.1).
- **`.worktrees/`, `.sisyphus/`, `.omo/`, `.claude/`, `.agents/`** are local tooling state (gitignored) and not authoritative. Don't read project structure from there.
- **Worktrees** go in `../homelab-<branch-suffix>` (siblings of the main repo, per the user-supplied session-start instructions). Use `git worktree list` to audit before starting new work.
