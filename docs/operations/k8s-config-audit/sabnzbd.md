# sabnzbd (sabnzbd)

**Audit date:** 2026-08-29

Usenet client, raw Deployment (no Helm chart), routed through a `gluetun` VPN sidecar (NordVPN/WireGuard this time, vs. qbittorrent's OpenVPN) with an `exportarr` metrics sidecar and a `gluetun-exporter` — 4 containers total. This is the app with the documented 2026-08-21 config data-loss incident ([[sabnzbd-config-data-loss-2026-08-21]]) — already confirmed fully resolved in `kopiur.md`; this pass checks the live Deployment/PVC config directly rather than re-litigating the incident.

## Findings

### 🔴 Clear actionable gap

Same issue as every other raw-Deployment app in this series: `serviceAccountName` unset (implicit `default`, confirmed live) with no `automountServiceAccountToken: false` on any of the 4 containers. None of `gluetun`, `sabnzbd`, `exportarr`, or `gluetun-exporter` ever calls the Kubernetes API. Same free, no-downside fix. (9th app with this pattern in this audit series.)

### 🟢 Well-configured, no action needed

- Live restart counts: all 4 containers at 0 — completely stable, no residual instability from the 2026-08-21 incident.
- `sabnzbd-config` PVC is genuinely on `longhorn` (in-file comment: `# was: csi-hostpath-sc`) — matches `kopiur.md`'s confirmation that the incident's recovery Restore CR shows `Completed`. Sized at `20Gi` (bumped from `5Gi`, with an in-file pointer to the recovery plan doc explaining why: restored snapshot data included misplaced `Downloads/complete`) — a deliberate, documented sizing decision, not drift.
- Credentials (`nordvpn-credentials.sops.yaml`, `sabnzbd-apikey.sops.yaml`) genuinely SOPS-encrypted.
- `gluetun` here uses WireGuard (vs. qbittorrent's OpenVPN) with the same scoped `NET_ADMIN`-only capability and the same deliberately-narrow `FIREWALL_OUTBOUND_SUBNETS`.
- Storage is coherent: `sabnzbd-downloads` correctly on `local-path` (transient in-progress downloads, not worth backing up — sensibly excluded from the `kopiur` PVC set), `sabnzbd-media` on the already-audited `smb-media` StorageClass via the same `smbcreds`-secret pattern as qbittorrent/radarr.
- Resource requests/limits set on all 4 containers (`sabnzbd` itself: 450m/2200Mi request → 3000m/4Gi limit — reasonable for an unpacking-heavy Usenet workload).
- Liveness + readiness probes present on all 4 containers.
- Ingress: cert-manager `letsencrypt-prod` + `websecure`-only entrypoint, TLS configured.
- `kopiur` backup coverage confirmed in `kopiur-policies.md`: both `sabnzbd-config` and `sabnzbd-gluetun` have healthy, recently-succeeded scheduled snapshots — the exact mechanism that made the 2026-08-21 recovery possible in the first place is still working correctly today.

### 🟡 Worth knowing — a real, still-open operational footgun, already self-documented in-file

The Deployment carries an unusually detailed in-file comment describing a real recurring issue: sabnzbd's `sabnzbd.ini` auto-populates `host_whitelist` with the pod's hostname on first startup, and every subsequent pod restart (new hostname, e.g. `sabnzbd-b545495fb-hq959`) makes that stale, causing gatus to see a 503 through gluetun's proxy when checking the ingress hostname. The documented fix is a **manual, imperative `kubectl exec` + `sed` command that must be re-run after every fresh pod start** — this is a real gap (no automated remediation, no init-container guard analogous to qbittorrent's `seed-config` pattern) but the previous author already identified and documented it clearly, including that the fix is captured by the next `kopiur` snapshot. Flagging as still-open rather than re-discovering: an init container that unconditionally sets `host_whitelist` to a wildcard/hostname-agnostic value (mirroring qbittorrent's `seed-config` approach) would close this permanently instead of relying on someone remembering the runbook next time the pod restarts.

- Same repo-wide "no forward-auth middleware, relies on the app's own auth" pattern as every other *arr/media app — not sabnzbd-specific.

### Kine/leader-election pattern (issue #355) check

Not applicable — sabnzbd is an application, not a controller, and none of its 4 containers leader-elect.
