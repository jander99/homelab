# headlamp (headlamp)

**Chart version:** 0.45.0 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Kubernetes dashboard UI, OIDC-authenticated via Authentik.

## Findings

### 🔴 Clear actionable gap — real and fixable, unlike portainer's equivalent finding

No `securityContext.capabilities.drop` or `readOnlyRootFilesystem` set, even though the chart genuinely supports both as documented opt-ins (confirmed via `helm show values headlamp/headlamp --version 0.45.0` — the chart even auto-provisions a writable `/tmp` emptyDir when `readOnlyRootFilesystem: true` is set, so there's no friction to adopting it). Unlike portainer's chart (which exposes no securityContext knob at all), most of the hardening is already in place via the chart's own defaults — confirmed live: `runAsNonRoot: true`, `runAsUser: 100`, `runAsGroup: 101`, `privileged: false` — only capability-dropping and read-only-root are missing, and both are cheap, low-risk additions.

### 🟡 Worth flagging explicitly — two independent paths to cluster-admin

1. `headlamp-admin` ClusterRoleBinding grants the headlamp pod's own ServiceAccount `cluster-admin` — same category as portainer, inherent to what a full-featured K8s dashboard needs to display/manage arbitrary cluster resources.
2. `headlamp-oidc-admins` ClusterRoleBinding separately grants `cluster-admin` to any human user whose authentik OIDC group membership includes `homelab-admins` (via `headlamp-oidc-rbac.yaml`). Reasonable and likely intentional for a personal homelab admin dashboard, but worth being explicit: logging into headlamp with an admin-group account is equivalent to holding a cluster-admin kubeconfig.

### 🟢 Well-configured, no action needed

- Chart pinned at `0.45.0` — confirmed current upstream latest, zero drift, no open Renovate PR needed.
- Image tag `v0.45.0` matches chart version exactly, not `:latest`.
- Resources set (`10m`/`128Mi` request, `256Mi` limit), matches this repo's established convention.
- Both liveness and readiness probes present.
- `headlamp-oidc-secret.sops.yaml` genuinely SOPS-encrypted, not a plaintext leak.
- `oidc.externalSecret.hasScopes: true` is a well-documented workaround for a real, easy-to-miss chart gotcha: the chart silently omits the `-oidc-scopes` arg unless this flag is set, which would otherwise cause the binary to fall back to a default scope list missing `offline_access` — breaking refresh tokens and forcing re-auth every 24h. Correctly caught and documented.
- PVC correctly migrated to `longhorn` with the documented Restore CR pairing.
- Two init containers run `runAsUser: 0` — justified: they `chown` the shared plugins volume to the main container's non-root UID/GID before handoff; the main container itself stays non-root.
- 0 restarts over 2d3h — stable.

### Kine/leader-election pattern (issue #355) check

Not applicable. Dashboard UI, single replica, no leader-election flags, 0 restarts.
