# sense-exporter (sense-exporter)

**Audit date:** 2026-08-28

Raw Deployment (no Helm chart). Exports Sense home-energy-monitor metrics via a NordVPN-tunneled sidecar (gluetun) — same VPN-sidecar pattern as qbittorrent.

## Findings

### 🔴 Clear actionable gap

Deployment uses the implicit `default` ServiceAccount with no `automountServiceAccountToken: false` — same unnecessary-token-mount pattern already found on `tdarr`. Neither container calls the Kubernetes API. Free, no-downside fix.

### 🟢 Well-configured, no action needed

- Both image tags pinned to explicit versions and confirmed current against upstream releases: `sense_energy_prometheus_exporter:1.0.0` and `gluetun:v3.41.3` — zero drift.
- Both SOPS secrets (`sense-secret.sops.yaml`, `nordvpn-credentials.sops.yaml`) are genuinely encrypted, not plaintext leaks.
- **NordVPN mystery solved, not cruft**: gluetun runs as a sidecar tunneling *all* outbound traffic (including the exporter's polling of `api.sense.com`) through NordVPN via a shared pod network namespace — well-documented in the manifest's own comments, matches the identical pattern already used by `qbittorrent`. The `nordvpn-credentials.sops.yaml` header explicitly explains it's a namespace-scoped copy of the same NordVPN service credentials used elsewhere (Secrets don't cross namespaces), not an accidental duplicate.
- `NET_ADMIN` capability (gluetun only) and the `/dev/net/tun` hostPath CharDevice mount are both justified — required for VPN tunnel creation, same category as other host-device-access components in this audit.
- Resource requests/limits set on both containers with sensible values.
- Liveness/readiness probes present on gluetun; sense-exporter has no probe, but it's a private-network-only metrics endpoint with no user-facing traffic depending on fast failure detection — low-impact, not flagged as actionable.
- `strategy: Recreate` is correctly justified — the hostPath CharDevice can't be shared between old/new pods during a rolling update.
- gluetun's 27 restarts all show `exitCode=0`/`reason=Completed` — clean, non-crash restarts (likely gluetun's own periodic reconnect behavior). sense-exporter's 1 restart is the same `exitCode=255`/`reason=Unknown` node-level fingerprint already confirmed elsewhere in this series (2026-08-08T01:20:33Z).

### Kine/leader-election pattern (issue #355) check

Not applicable. Application, not a controller — no leader-election flags, no lease RBAC.
