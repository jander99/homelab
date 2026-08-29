# prowlarr (media)

**Audit date:** 2026-08-28

Indexer manager, raw Deployment (no Helm chart), with an `exportarr` metrics sidecar.

## Findings

### 🔴 Clear actionable gap

Same unnecessary-token-mount issue found on `tdarr`: `serviceAccountName` is unset (implicit `default` SA) and `automountServiceAccountToken` isn't set anywhere (Deployment spec, pod spec, or the `default` SA itself all render empty → defaults to `true`). Neither `prowlarr` nor `exportarr` ever calls the Kubernetes API, so a live API token is mounted into the pod for no reason. Free fix: `automountServiceAccountToken: false` on the Deployment. (This is now the 5th app in this audit series with the same gap — tdarr, sense-exporter, prowlarr, sonarr, radarr — same low-risk, uniform, likely-batchable fix across all of them.)

### 🟢 Well-configured, no action needed

- Image pinned explicitly (`lscr.io/linuxserver/prowlarr:2.5.2`) — confirmed via Docker Hub that this is the current tag, zero drift, no open Renovate PR needed.
- `exportarr` sidecar (`ghcr.io/onedr0p/exportarr:v2.3.0`) is exactly the current GitHub release — zero drift.
- Both containers have full liveness + readiness probes, correctly scoped resource requests/limits, and the `exportarr` sidecar correctly reads the API key from the SOPS-encrypted `prowlarr-apikey` secret rather than a hardcoded value.
- Ingress uses cert-manager TLS (`letsencrypt-prod`) + `websecure`-only entrypoint — no plaintext HTTP path exposed. Service is `ClusterIP` — Ingress is the only route in.
- Storage already migrated to `longhorn`, consistent with the migration history established across this whole audit series.
- Live pod: 0 restarts across both containers over 8 days — completely stable, no kine/leader-election candidate.
- Checked whether `recyclarr` consumes Prowlarr's API — it doesn't; recyclarr only targets radarr/sonarr (quality-profile/custom-format sync). No cross-app inconsistency.

### 🟡 Worth knowing, plausibly justified but not confirmed

- Container-level `securityContext` is empty (only pod-level `fsGroup: 100` set) — no `runAsNonRoot`, no dropped capabilities, no `readOnlyRootFilesystem`. Same `PUID`/`PGID` LinuxServer.io pattern already seen on tdarr, where root startup is plausibly required to chown `/config` before dropping privileges internally — not independently verified against this specific image's entrypoint.
- No NetworkPolicy (repo-wide pattern, not prowlarr-specific).
