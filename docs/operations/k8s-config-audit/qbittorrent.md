# qbittorrent (qbittorrent)

**Audit date:** 2026-08-29

Torrent client, raw Deployment (no Helm chart), routed through a `gluetun` VPN sidecar (NordVPN/OpenVPN) with two metrics-exporter sidecars (`qbt-exporter`, `gluetun-exporter`) — 4 containers total.

## Findings

### 🔴 Clear actionable gap

Same issue as tdarr/radarr/etc.: `serviceAccountName` unset (implicit `default`, confirmed live) with no `automountServiceAccountToken: false` on any of the 4 containers. None of `gluetun`, `qbittorrent`, `qbt-exporter`, or `gluetun-exporter` ever calls the Kubernetes API. Same free, no-downside fix. (8th app with this pattern in this audit series.)

### 🟢 Well-configured, no action needed

- Live restart counts: `gluetun` 1, everything else 0 — stable. (`gluetun`'s single restart is not a leader-election crash — this app doesn't leader-elect; not investigated further as a one-off on a VPN sidecar is low-signal.)
- VPN credentials (`nordvpn-credentials.sops.yaml`, `qbittorrent-apikey.sops.yaml`) genuinely SOPS-encrypted, both with `.example` onboarding templates.
- `gluetun` scopes its elevated access correctly: only `NET_ADMIN` capability added (needed to manage the VPN tunnel/iptables), not full `privileged: true` — tighter than the CSI driver precedent elsewhere in this audit.
- `FIREWALL_OUTBOUND_SUBNETS` is explicitly scoped to the cluster's pod/service CIDRs + LAN (`10.42.0.0/16,10.43.0.0/16,192.168.1.0/24`) rather than left wide open — a real, deliberate containment choice on top of the VPN tunnel itself.
- An init container (`seed-config`) idempotently seeds `qBittorrent.conf` and enforces `WebUI\LocalHostAuth=false` on every start — a well-reasoned config-drift guard (without it, qBittorrent would allow unauthenticated access from what it considers "localhost," which inside a shared network namespace with gluetun means any pod on the tunnel).
- Storage is coherent: `qbittorrent-config`/`gluetun-config` on `longhorn`, `qbittorrent-media` correctly bound to the already-audited `smb-media` StorageClass via a static PV with `nodeStageSecretRef` pointing at the same `smbcreds` secret confirmed SOPS-encrypted in `csi-driver-smb.md`.
- Resource requests/limits set on all 4 containers, reasonable for each role (qbittorrent itself gets the most headroom: 20m/2Gi request → 2000m/3Gi limit).
- Liveness + readiness probes present on all 4 containers.
- Ingress: cert-manager `letsencrypt-prod` + `websecure`-only entrypoint, TLS configured.
- `kopiur` backup coverage confirmed in `kopiur-policies.md`: both `qbittorrent-config` and `qbittorrent-gluetun` have healthy, recently-succeeded scheduled snapshots.

### 🟡 Worth knowing, not qbittorrent-specific

- No Traefik forward-auth middleware on this Ingress — same repo-wide pattern already noted in `radarr.md` (every *arr/media app relies on its own built-in auth instead of SSO-in-front). Here it's slightly more load-bearing than most, since the `seed-config` init container's whole purpose is keeping qBittorrent's own auth enabled — worth the owner double-checking the WebUI password isn't still a default.
- Two separate `ServiceMonitor`s (`qbittorrent-exporter`, `qbittorrent-gluetun`) both select on the same pod — intentional (metrics endpoints on different ports/paths), not a duplicate/gap.

### Kine/leader-election pattern (issue #355) check

Not applicable — qbittorrent is an application, not a controller, and none of its 4 containers leader-elect.
