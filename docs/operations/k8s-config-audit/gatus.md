# gatus (gatus)

**Chart version:** 1.5.0 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Uptime/health-check dashboard, 17 endpoint checks across auth/dashboards/media groups.

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `1.5.0` — confirmed current upstream latest, zero drift, no open Renovate PR needed.
- Image tag deliberately pinned ahead of chart appVersion (`v5.36.0` vs chart's `v5.34.0`) with a clear documented rationale (OIDC support), consistent with this repo's stated "chart version != image tag, pin explicitly" convention.
- Container: `runAsNonRoot`, non-root UID/GID 65534, `readOnlyRootFilesystem: true`; pod-level `fsGroup: 65534`. Liveness + readiness probes both present (`/health`, port 8080).
- Resources match declared config exactly on the live Deployment (`10m`/`64Mi` request, `128Mi` limit).
- `automountServiceAccountToken: false` correctly set even though it uses the `default` ServiceAccount — same free hardening tdarr's audit found missing; gatus already has it right.
- `gatus-oidc-secret.sops.yaml` is genuinely SOPS-encrypted, not a plaintext leak.
- OIDC auth is Gatus-native (`security.oidc` in `config.yaml`), not a Traefik forwardAuth middleware — correctly noted in comments as why no middleware annotation is needed on the Ingress.
- Endpoint list (17 checks) is current and specific — includes accurate, hard-won gotchas already worked out in comments (e.g., authentik's health endpoint returns HTML not JSON so only `[STATUS]==200` is checked; tdarr's real API port is 8266 not 8265). Two real historical bugs are documented and confirmed fixed: PR #243 (wrong `envFrom` field name silently dropped OIDC env vars, causing boot panics) and the chart's dual-ConfigMap-reference quirk — live pod confirms both are correctly resolved (0 restarts, 10 days uptime).
- Live pod image matches declared tag exactly (`twinproduction/gatus:v5.36.0`).

### Kine/leader-election pattern (issue #355) check

Not applicable. Single replica, no leader-election flags, 0 restarts over 10 days.

### 🔴 Clear actionable gaps

None found.
