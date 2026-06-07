# INFRASTRUCTURE DIRECTORY

**Generated:** 2026-05-06

## OVERVIEW

Flux-managed infrastructure layer split into two reconciliation stages:
- **controllers/**: HelmRelease + HelmRepository manifests that install cluster controllers and their CRDs.
- **configs/**: Supporting resources (ClusterIssuers, IPAddressPools, SOPS-encrypted secrets) that depend on those CRDs existing first.

## STRUCTURE

```
infrastructure/
├── controllers/
│   ├── cert-manager/           # helmrelease.yaml, helmrepository.yaml, kustomization.yaml
│   ├── metallb/                # helmrelease.yaml, helmrepository.yaml, kustomization.yaml
│   ├── opentelemetry-collector/# helmrelease.yaml, helmrepository.yaml, kustomization.yaml
│   └── tempo/                  # helmrelease.yaml, helmrepository.yaml, kustomization.yaml
└── configs/
    ├── cert-manager/   # cloudflare-token.sops.yaml, clusterissuer-{prod,staging}.yaml, kustomization.yaml
    ├── metallb/        # ipaddresspool.yaml, l2advertisement.yaml, kustomization.yaml
    └── monitoring/     # helmrelease.yaml, helmrepository.yaml, grafana-secret.sops.yaml, kustomization.yaml

## RECONCILIATION ORDER

Flux Kustomization `infra-configs` has `dependsOn: [infra-controllers]`. This guarantees HelmReleases (and their CRDs) install before ClusterIssuers or IPAddressPools are applied. Do not bypass this ordering.

## WHAT'S DEPLOYED

### cert-manager
- **Chart**: `jetstack/cert-manager` `>=1.14.0 <2.0.0` | namespace: `cert-manager`
- **CRDs**: `crds.enabled: true`, policy: `CreateReplace` on install and upgrade
- **Issuers**: `letsencrypt-prod` and `letsencrypt-staging` ClusterIssuers (Cloudflare DNS-01 challenge)
- **Secret**: `cloudflare-token.sops.yaml` — SOPS age-encrypted Cloudflare API token; Flux decrypts via `flux-system/sops-age` Secret in cluster

### metallb
- **Chart**: `metallb` from metallb Helm repository | namespace: `metallb-system`
- **IPAddressPool**: defined in `configs/metallb/ipaddresspool.yaml`
- **L2Advertisement**: defined in `configs/metallb/l2advertisement.yaml`

### kube-prometheus-stack
- **Chart**: `prometheus-community/kube-prometheus-stack` `>=84.0.0 <85.0.0` (deployed: 84.5.0) | namespace: `monitoring`
- **Components**: Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter
- **Ingresses**: grafana.homelab.properties, prometheus.homelab.properties, alertmanager.homelab.properties (all TLS via letsencrypt-prod)
- **Storage**: Prometheus 20Gi PVC (local-path), Grafana 5Gi PVC (local-path), Alertmanager emptyDir
- **Secret**: `grafana-secret.sops.yaml` — SOPS age-encrypted Grafana admin credentials (`admin-user` / `admin-password` keys)
- **K3s scrapers disabled**: kubeEtcd, kubeScheduler, kubeControllerManager, kubeProxy (K3s uses SQLite; control plane binds to 127.0.0.1)
- **PodMonitor discovery**: `podMonitorSelectorNilUsesHelmValues: false` + `serviceMonitorSelectorNilUsesHelmValues: false`

### opentelemetry-collector
- **Chart**: `open-telemetry/opentelemetry-collector` v0.155.0 (contrib "kube" image, appVersion 0.151.0) | namespace: `telemetry`
- **Mode**: `daemonset` — one pod per node (single on the testbed, scales to N on HA cluster)
- **Presets enabled**: `clusterMetrics`, `hostMetrics`, `kubeletMetrics`, `resourceDetection` — the chart generates correct receiver/ClusterRole/host-mount config for these, including `k8s_leader_elector` for the daemonset k8s_cluster receiver. The chart also auto-adds the `resourcedetection/env` processor to the traces pipeline when the resourceDetection preset is enabled.
- **Custom receivers layered on top**: `otlp` (grpc :4317, http :4318) for app-side opt-ins; `k8s_cluster.node_conditions_to_report` / `allocatable_types_to_report` extensions; `kubeletstats.node: "${env:K8S_NODE_NAME}"` (required by Validate() when node-utilization metrics are enabled; the preset doesn't set it) and `kubeletstats.metrics` enabling the four node-utilization gauges
- **Exporters**: `otlp` → `tempo.telemetry.svc.cluster.local:4317`; `debug` (stdout) for metrics/logs
- **Processors**: `memory_limiter`, `batch` (custom); `resourcedetection/env` (chart preset, auto-added to traces pipeline; detectors: `env`, `k8snode` — `k8snode` is the only registered K8s detector in v0.151.0; the `k8s_api` rename is a future-version change)
- **Extensions**: `health_check` (chart default) — no k8s_observer/receiver_creator; we don't do annotation-based discovery
- **Host mounts**: provided by the `hostMetrics` preset (hostfs → /, propagated HostToContainer)

### tempo
- **Chart**: `grafana-community/tempo` v2.2.0 (single-binary / monolithic) | namespace: `telemetry`
- **Storage**: `local` backend, 5Gi PVC on `local-path`, WAL at `/var/tempo/wal`
- **Receivers**: `otlp` (grpc :4317, http :4318) — defaults, no override needed
- **Retention**: 168h (7 days)
- **No ingress** — Grafana dials `http://tempo.telemetry.svc.cluster.local:3200` in-cluster
- **Datasource**: `grafanadatasource-tempo.yaml` in `configs/monitoring/` (sidecar-discovered via `grafana_datasource: "1"` label); uid `tempo`, serviceMap back-linked to `prometheus`

### Headlamp (reference — lives in `k3s/applications/headlamp/`)
- Uses `cert-manager.io/cluster-issuer: letsencrypt-prod` in Traefik ingress
- URL: `headlamp.homelab.properties`

### Pihole (reference — lives in `k3s/applications/pihole/`)
- PodMonitor enabled via `monitoring.sidecar.enabled: true` (ekofr/pihole-exporter:v1.0.0 on port 9617)
- URL: `pihole.homelab.properties`
## WHERE TO LOOK

| Task | File |
|------|------|
| Add a new controller chart | `controllers/<name>/helmrelease.yaml` + `helmrepository.yaml` + `kustomization.yaml` |
| Add a Grafana datasource | `configs/monitoring/grafanadatasource-<name>.yaml` (must have `grafana_datasource: "1"` label) |
| Add a ClusterIssuer | `configs/cert-manager/` |
| Change IP address pool | `configs/metallb/ipaddresspool.yaml` |
| Edit Cloudflare token secret | `configs/cert-manager/cloudflare-token.sops.yaml` via `sops` CLI |
| Edit Grafana admin secret | `configs/monitoring/grafana-secret.sops.yaml` via `sops` CLI |
| Modify monitoring stack values | `configs/monitoring/helmrelease.yaml` |
## ANTI-PATTERNS

- **Do not hand-edit `*.sops.yaml` files** — SOPS-encrypted; edit only with `sops <file>` using the age key at `~/.kube/k3s-homelab-age.agekey`.
- **Do not add configs/ resources that need CRDs from controllers/** without ensuring `infra-configs` dependsOn remains correct.
- **Do not duplicate ClusterIssuers** — `letsencrypt-prod` and `letsencrypt-staging` already exist; reference by name in ingress annotations.
- **Do not add a new controller without a matching entry** in the `infra-controllers` Kustomization's `resources:` list at `k3s/clusters/homelab/infra-controllers.yaml`.
- **Do not place namespaces inside `configs/`** — namespaces belong in `k3s/platform/namespaces/` (see monitoring namespace as the established pattern).
- **Do not enable kubeEtcd/kubeScheduler/kubeControllerManager/kubeProxy scrapers** — K3s binds these to 127.0.0.1 and uses SQLite; they will always fail to scrape.

## NOTES

- `cloudflare-token.sops.yaml.example` is an unencrypted reference template — safe to read/edit.
- The age key fingerprint is in `.sops.yaml` at the repo root. The private key is **not** in git; it lives at `~/.kube/k3s-homelab-age.agekey` on the Ansible controller and as `flux-system/sops-age` Secret in the cluster.
- cert-manager's `HelmRelease` uses `helm.toolkit.fluxcd.io/v2` API (Flux v2.3.0 compatible).
