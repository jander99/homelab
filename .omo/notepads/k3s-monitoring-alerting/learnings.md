#HH|# Learnings — k3s-monitoring-alerting
#KM|
#ZN|## 2026-05-24 — Session Start
#RW|
#NM|### Infrastructure Facts
#QT|- kube-prometheus-stack 84.5.0; namespace: monitoring
#YW|- SOPS age key: `~/.kube/k3s-homelab-age.agekey` (set SOPS_AGE_KEY_FILE env var)
#ZK|- SOPS pattern to follow: `k3s/infrastructure/configs/monitoring/grafana-secret.sops.yaml`
#VW|- Alertmanager currently has null receiver + emptyDir storage
#KV|- HelmRelease API: `helm.toolkit.fluxcd.io/v2`
#BN|- prometheus-community HelmRepository: verify namespace with `kubectl get helmrepository -A | grep prometheus-community`
#NZ|- All QA uses `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 19090:9090` (ingress behind Authentik)
#KT|- local-path StorageClass: available and used by existing PVCs
#QX|- cert-manager NOT scraped; port 9402
#BH|- Flux controllers NOT scraped; port 8080, flux-system namespace
#WX|- Gluetun IS scraped (port 9586, exporter: ghcr.io/crstian19/gluetun-exporter:0.1.1)
#HM|- Tdarr external server: http://192.168.1.20:8266 (no K3s Service)
#WK|- k3s/clusters/homelab/flux-system/ is bootstrap-managed — NEVER add custom resources there
#RV|- All new YAML must be added to their kustomization.yaml resources list
#XZ|- PodMonitors for cert-manager and Flux go in infra-configs/monitoring/ (after Prometheus Operator CRDs)
#PP|- kube-prometheus-stack 84.5.0 has NO built-in blackbox exporter subchart — separate HelmRelease required
#WK|- PrometheusRules need label: `release: kube-prometheus-stack`
#WX|- PD key: ebacff33dd304e0cd0bb1c81263af3e8 (user confirmed no rotation needed; SOPS encrypts it)
#ZQ|- Branch: feat/k3s-monitoring-alerting
#XW|
#HR|## 2026-05-24 — Task 5: Alertmanager PagerDuty + PVC
#JJ|
#QZ|### Changes Made
#XJ|- Replaced `alertmanagerSpec.storage: {}` (emptyDir) with 1Gi local-path PVC via `volumeClaimTemplate`
#WY|- Added `alertmanagerSpec.configSecret: alertmanager-pagerduty-config` to reference SOPS secret
#VR|- Removed entire inline `alertmanager.config` block — config now sourced exclusively from the Secret
#WR|- `kubectl apply --dry-run=server` passed with "configured (server dry run)"
#QY|
#PM|### Key API Notes
#HP|- `alertmanagerSpec.configSecret` references a Kubernetes Secret in the same namespace; the Secret must have a `alertmanager.yaml` key with the full config
#VM|- Removing the inline `config:` block from HelmRelease values is required — the chart merges them and inline wins if present
#XX|- emptyDir → PVC migration will restart Alertmanager pod and clear active silences (expected, documented in commit)
#BN|
#BX|### Probe CRD Notes
#TW|- Blackbox Probes belong in `k3s/infrastructure/configs/monitoring/` and must be listed in `kustomization.yaml`.
#JJ|- Use `prometheus-blackbox-exporter.monitoring.svc.cluster.local:9115` as the prober URL.
#NZ|- Keep probe timeout at or below 30s; this session used the shared `http_2xx` module with its existing 10s module timeout.
#KQ|- Tdarr should probe the external Synology-hosted service directly at `http://192.168.1.20:8266` because no K3s Service exists.
#LP|
#QM|### Cert-manager Expiry Alerts
#RV|- Added a dedicated PrometheusRule for cert-manager certificate expiry warnings and criticals.
#JH|- Alerts use `certmanager_certificate_expiration_timestamp_seconds` with 7d/24h thresholds and `for` windows of 1h/30m.
#GP|- Keep `release: kube-prometheus-stack` on PrometheusRule objects so the chart picks them up.
#FD|- Manifest must be included in `kustomization.yaml` resources for Flux to apply it.

## 2026-05-24 — Task 7: Flux reconciliation alerts

### Changes Made
- Added `prometheusrule-flux.yaml` with two Flux alerts: reconciliation failure and reconciliation staleness.
- Included the new PrometheusRule in `kustomization.yaml` so Flux applies it.
- Server-side dry-run succeeded for the new manifest.

### Key Rule Notes
- Flux alerts use `gotk_reconcile_condition` and `gotk_reconcile_duration_seconds_count` from the Flux PodMonitor.
- Keep PrometheusRule label `release: kube-prometheus-stack` so kube-prometheus-stack selects it.
