# monitoring (monitoring)

**Chart versions:** kube-prometheus-stack 88.5.3 (drift to 88.6.1 already covered by open Renovate PR #337); prometheus-blackbox-exporter 11.17.2 — current upstream latest, zero drift
**Audit date:** 2026-08-28

kube-prometheus-stack (Prometheus + Grafana + Alertmanager + operator + kube-state-metrics) plus a separate blackbox-exporter release. The biggest, most complex component in this audit series. Config lives entirely in `k3s/infrastructure/configs/monitoring/` — `k3s/applications/monitoring/` only contains a RUNBOOK.md and legitimate migration/ leftover artifacts.

## Findings

### 🟡 Worth knowing, actionable — inconsistent with the rest of this repo's secret-management pattern

`grafana-admin-secret` (referenced via `admin.existingSecret` in `helmrelease.yaml`) is a real, live secret on the cluster (114 days old) but is **not declared anywhere in git** — no `.sops.yaml` file, not in `kustomization.yaml`. Every other secret in this component (`grafana-secret`, `alertmanager-pagerduty-secret`, `grafana-oidc-secret`, `grafana-gitsync-pat`) is SOPS-encrypted and git-tracked, with `grafana-secret.sops.yaml.example` even following the documented onboarding pattern. This one was created out-of-band (`kubectl create secret` or similar), meaning it isn't reproducible if the cluster is rebuilt from git — a real gap in disaster-recovery completeness, though arguably could be a deliberate choice to keep the initial admin credential out of git entirely (a legitimate "bootstrap secret" pattern). Worth the owner confirming which it is and, if unintentional, either SOPS-encrypting it to match the rest of the repo or documenting the manual bootstrap step in the RUNBOOK.

### 🟢 Well-configured, no action needed

- `kube-prometheus-stack` chart pinned at `88.5.3`; drift to `88.6.1` already covered by open Renovate PR #337 — not a gap.
- `prometheus-blackbox-exporter` chart pinned at `11.17.2` — confirmed current upstream latest, zero drift.
- Prometheus and Grafana pods both have `runAsNonRoot`, `readOnlyRootFilesystem` (prometheus)/dropped capabilities + seccomp `RuntimeDefault` (both), matching the repo's established hardening convention.
- Resource requests/limits verified matching exactly between declared HelmRelease values and live containers across all 5 workload types — CPU limits deliberately unset with a documented rationale (throttling would hurt scrape reliability).
- Liveness/readiness probes present on both `prometheus` and `grafana` main containers; sidecars correctly have none, consistent with standard sidecar patterns seen elsewhere in this audit.
- All 4 SOPS secrets genuinely encrypted — not plaintext leaks.
- Grafana datasources correctly cross-reference already-audited services: Loki via `loki-gateway.telemetry.svc.cluster.local:80`, Tempo via `tempo.telemetry.svc.cluster.local:3200` (the HTTP query API port, distinct from the OTLP ingest port 4317 used by opentelemetry-collector) — both genuinely wired, not dangling references.
- Grafana OIDC config points at Authentik with a sensible role mapping (`homelab-admins` group → Grafana Admin, else Viewer).
- PVC migrations (Grafana, Alertmanager) from csi-hostpath-sc to Longhorn are well-documented in both the HelmRelease comments and a dedicated RUNBOOK.md, consistent with the pattern seen in other migrated components (pihole, portainer, sabnzbd).
- kube-prometheus-stack's k3s-specific tuning is sound: disables `kubeEtcd`/`kubeScheduler`/`kubeControllerManager`/`kubeProxy` scrapers (correctly noted as inapplicable to k3s's bundled-binary architecture), and drops duplicate `apiserver_*`/`scheduler_*` metrics surfaced redundantly via the kubelet endpoint — both with clear rationale comments.
- Operator RBAC (11 ClusterRole rules, including `*` verbs on `secrets`/`configmaps` cluster-wide and all Prometheus-Operator CRDs) is broad but justified — inherent to how prometheus-operator functions — same category as portainer's cluster-admin or longhorn's node access: not a local over-grant.

### Kine/leader-election pattern (issue #355) check

Not present, and not applicable to most of this component. All pods except `node-exporter` show **0 restarts** over 6+ days — none land in or near the 2026-08-28 ~22:20 UTC cascade window. `prometheus-operator`'s rendered container args carry no leader-election flags at all — confirmed empirically, an empty grep result — so despite being an "operator," it genuinely doesn't leader-elect on this single-replica deployment, ruling out the pattern architecturally, not just by absence of restarts. `node-exporter`'s single restart (`exitCode=255`/`reason=Unknown`, `2026-08-08T01:20:33Z`) matches the same node/containerd-level restart fingerprint already identified elsewhere in this audit.

### 🔴 Clear actionable gaps

None (the `grafana-admin-secret` item is filed as 🟡 since it may be an intentional security choice rather than an oversight).
