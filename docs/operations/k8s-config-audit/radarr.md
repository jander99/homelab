# radarr (media)

**Audit date:** 2026-08-28

Movie manager, raw Deployment (no Helm chart), with an `exportarr` metrics sidecar.

## Findings

### 🔴 Clear actionable gap

Same issue as tdarr: `serviceAccountName` unset (implicit `default`) with no `automountServiceAccountToken: false` on either container. Neither `radarr` nor its `exportarr` metrics sidecar ever calls the Kubernetes API. Confirmed live. Same free, no-downside fix. (7th app with this pattern in this audit series.)

### 🟢 Well-configured, no action needed

- Image pinned to `6.3.0` (LinuxServer.io alias) — confirmed this matches the actual latest stable published tag (next available, `6.4.2`, is nightly-only) — zero drift.
- `radarr-apikey.sops.yaml` genuinely SOPS-encrypted, not a plaintext leak.
- Resource requests/limits set on both containers (radarr: 100m/900Mi request, 1000m/1Gi limit; exportarr sidecar: 50m/64Mi request, 200m/256Mi limit) — reasonable for this workload.
- Liveness + readiness probes present and correctly configured on both containers.
- Storage is coherent: `radarr-config` on `longhorn` (with an in-file comment noting the prior `csi-hostpath-sc` migration), `radarr-media` correctly bound to the already-audited `smb-media` StorageClass via a static PV, `nodeStageSecretRef` pointing at the same `smbcreds` secret already confirmed SOPS-encrypted in the csi-driver-smb audit.
- Ingress: cert-manager `letsencrypt-prod` + `websecure`-only entrypoint, TLS configured — no plaintext HTTP path.
- 0 restarts on both containers over 6d2h — completely stable. No kine/leader-election pattern (not applicable).

### 🟡 Worth knowing, not radarr-specific

No Traefik forward-auth middleware on this Ingress (unlike e.g. goldilocks, which reuses the authentik-forwardauth middleware) — checked across all of `k3s/applications/*/ingress.yaml`: no app in this repo uses one, so this isn't a radarr-specific gap, just this repo's consistent pattern of relying on each *arr app's own built-in authentication instead of SSO in front of it. Worth the owner confirming radarr's own auth is actually enabled if this is meant to be internet/LAN-exposed without a VPN.
