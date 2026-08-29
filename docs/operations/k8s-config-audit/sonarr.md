# sonarr (media)

**Audit date:** 2026-08-28

TV show manager, raw Deployment (no Helm chart), with an `exportarr` metrics sidecar.

## Findings

### 🔴 Clear actionable gap

Same unnecessary-token-mount issue found on `tdarr`: `serviceAccountName` unset (implicit `default`) with no `automountServiceAccountToken: false`. Confirmed live. Neither the `sonarr` nor `exportarr` container ever calls the Kubernetes API. Free, no-downside fix. (6th app with this pattern in this audit series.)

### 🟢 Well-configured, no action needed

- Both images pinned to explicit versions, confirmed current: `lscr.io/linuxserver/sonarr:4.0.19` matches the latest published LinuxServer tag family; `ghcr.io/onedr0p/exportarr:v2.3.0` matches GitHub's latest release tag exactly. No open Renovate PR for either — consistent with no drift.
- Resource requests/limits set on both containers with sensible headroom (sonarr: 20m/800Mi request, 1000m/1Gi limit; exportarr: 50m/64Mi request, 200m/256Mi limit).
- Both containers have liveness and readiness probes, correctly hitting real health endpoints (`/ping` for sonarr, `/healthz` for exportarr).
- `sonarr-apikey.sops.yaml` is genuinely SOPS-encrypted, with clear in-file instructions for rotating it.
- Ingress uses cert-manager (`letsencrypt-prod`) + Traefik `websecure` entrypoint only — no plaintext HTTP path.
- Storage is coherent: `sonarr-config` on `longhorn` (2Gi), `sonarr-media` on `smb-media` via a static PV referencing the SMB CSI credentials by secret ref, matching the pattern already confirmed correct in the `csi-driver-smb`/`smb-storage` audits.
- `exportarr`'s API key is sourced from the same SOPS secret via `secretKeyRef`, not duplicated or hardcoded.
- Live pod: **0 restarts over 6d2h** — the scheduled VolumeSnapshot processed against sonarr's PVC at 22:18:00 UTC on 2026-08-28 (found during the `snapshot-controller` audit, right before the confirmed kine cascade) had zero impact on the sonarr pod itself.

### Kine/leader-election pattern (issue #355) check

Not applicable and not present. Sonarr is an application, not a Kubernetes controller — no leader-election flags, and 0 restarts confirms no instability of any kind.

### 🟡 Worth knowing

No NetworkPolicy (repo-wide pattern, not sonarr-specific).
