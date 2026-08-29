# metallb (metallb-system)

**Chart version:** 0.16.1 — current upstream latest, zero drift
**Audit date:** 2026-08-28

LoadBalancer IP allocation (L2 mode) for a bare-metal cluster. Config split across `k3s/infrastructure/controllers/metallb/` (the chart) and `k3s/infrastructure/configs/metallb/` (IPAddressPool + L2Advertisement).

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `0.16.1` — confirmed current upstream latest (`helm search repo --versions`), zero drift, no Renovate PR needed.
- **Controller and speaker are scoped very differently, correctly reflecting their actual roles** — one of the better privilege-separation examples in this audit series: `metallb-controller` (IP allocation via the API) runs with `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, no elevated network capabilities at all. `metallb-speaker` (does ARP/L2 announcements) needs `hostNetwork: true` and adds exactly `NET_RAW` — not a blanket `privileged: true` and not `NET_ADMIN`, just the one capability actually required for L2 announcement, with everything else still dropped.
- RBAC on both ClusterRoles is properly scoped: `services`/`endpoints`/`nodes`/`namespaces` get/list/watch plus MetalLB's own CRDs — no secrets, no configmaps, no broad cluster access.
- IPAddressPool (`192.168.1.200-192.168.1.220`, L2 mode only) doesn't overlap the pod CIDR (`10.42.0.0/24`) or service CIDR (`10.43.0.0/16`, inferred from live ClusterIPs) — checked live: 2 addresses currently allocated (`traefik` → `.200`, `pihole-dns` → `.201`), both real, not dead config. Could not verify against the LAN's DHCP reservation range from this shell (no router access) — worth the owner double-checking that assumption still holds, but no evidence of an actual conflict.
- Resource requests/limits set explicitly on both `controller` and `speaker`, matching the repo's established memory-only-limit convention.

### 🟡 Worth knowing, actually fixable (not upstream-forced) — low priority

The chart's `frrk8s.enabled: true` default means a full frr-k8s BGP backend (5-container DaemonSet: `controller`, `frr`, `reloader`, `frr-metrics`, `frr-status`, plus a `statuscleaner` Deployment) is running on this cluster, but the only config present is an `L2Advertisement` — no `BGPAdvertisement`/`BGPPeer` CRs exist anywhere in the repo. This isn't a local misconfiguration (we don't set `frrk8s` at all in `helmrelease.yaml` — it's purely the current chart's default BGP backend, replacing the now-deprecated standalone `frr.enabled` mode), but it is running extra idle attack surface and resource footprint for a capability (BGP) this deployment doesn't use. An explicit `frrk8s: {enabled: false}` override would remove it cleanly if BGP is never planned; harmless to leave as-is if BGP might be adopted later (e.g. moving beyond L2 mode).

### Kine/leader-election pattern (issue #355) check

Not applicable / not present. All 4 pods show low, old restart counts unrelated to the 2026-08-28 cascade: `metallb-controller` 1 restart ~21d ago, `frr-k8s-statuscleaner` 1 restart ~21d ago, `speaker` 1 restart ~21d ago, `frr-k8s` DaemonSet 7 restarts ~6d19h ago (≈2026-08-22, not the 08-28 22:20 UTC window). None of these timestamps land in or near the confirmed cascade window, and none of MetalLB's rendered manifests show leader-election flags.

### 🔴 Clear actionable gaps

None found.
