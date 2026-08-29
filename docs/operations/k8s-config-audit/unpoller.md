# unpoller (unpoller)

**Audit date:** 2026-08-29

UniFi controller metrics exporter (Prometheus), single container, no ingress/UI — the best-hardened raw-Deployment app found in this entire audit series.

## Findings

### 🟢 Well-configured, no action needed — no 🔴 gap to report

- **The only app in this audit series that already does everything right on the ServiceAccount front**: explicit dedicated `ServiceAccount/unpoller` with `automountServiceAccountToken: false` set at the ServiceAccount level (belt-and-suspenders — the field isn't even needed twice, but it's there). This is the exact fix every other raw-Deployment app in this series (tdarr, radarr, qbittorrent, sabnzbd, +5 more) is missing — worth pointing at this file as the reference pattern when those get fixed.
- Full container `securityContext`: `runAsNonRoot`, explicit UID/GID `65532`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, all capabilities dropped — matches the infra-controller hardening bar (alloy, cert-manager, etc.), not the lighter app-tier bar seen elsewhere.
- `startupProbe` (30×10s = 5 min budget) + `readinessProbe` + `livenessProbe`, all correctly scoped `tcpSocket` checks against the metrics port — sensible for a workload with no HTTP health endpoint of its own.
- Credentials (`unpoller-secret.sops.yaml` — UniFi controller username/password) genuinely SOPS-encrypted.
- `UP_UNIFI_DEFAULT_VERIFY_SSL: "false"` is a real, explainable local exception, not carelessness — UniFi controllers commonly serve a self-signed cert on the LAN and this is a single hardcoded internal target (`https://192.168.1.1`), not a general TLS-verification bypass.
- Resource requests/limits set (`25m/64Mi` → `500m/256Mi`), appropriately light for a metrics poller.
- Live: 0 restarts — stable.
- `ServiceMonitor` present and correctly labeled to match the Deployment's `app.kubernetes.io/name: unpoller` selector.

### 🟡 Worth knowing, not actionable

- No ingress — correctly so, this exposes only a metrics endpoint for in-cluster Prometheus scraping, nothing meant for browser access.
- Not covered by any `kopiur` SnapshotPolicy — correctly so, this app is entirely stateless (no PVC in the manifest at all), nothing to back up.

### Kine/leader-election pattern (issue #355) check

Not applicable — unpoller is a stateless metrics exporter, not a controller, and doesn't leader-elect.
