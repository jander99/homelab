# longhorn (longhorn-system)

**Chart version:** 1.12.1 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Primary storage backend for this cluster's persistent workloads.

## Findings

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355) — worst instance found so far, and currently ongoing (not historical)

12 pods are affected: `csi-attacher`, `csi-provisioner`, `csi-resizer`, `csi-snapshotter` each run 3 replicas, and every single pod across all 4×3=12 shows substantial restart counts (28–39 restarts each over 11 days). Confirmed via `--previous` logs on all four sidecar types — identical `context deadline exceeded` on lease PUT → "Stopped leading" → exit pattern. This is **actively ongoing right now**, not a historical event: one pod restarted 4 minutes before this check ran (`01:17:18Z` on 2026-08-29), and crash timestamps are scattered throughout the day (19:48, 19:53, 22:19:59, 23:18 — all 2026-08-28), roughly 3-4 restarts/day per pod. One of these (`csi-attacher-...fb7jv`, crashed `22:19:59.891Z`) lines up within the same ~22:20 UTC window as the flux-system and kopiur-system cascade already reported to issue #355 — a 4th independent controller confirming that event, across a 3rd namespace.

### 🔴 Real, low-risk mitigation lever for issue #355 — not currently applied

This cluster is single-node, so Longhorn's default of 3 replicas for each CSI sidecar (`attacherReplicaCount`, `provisionerReplicaCount`, `resizerReplicaCount`, `snapshotterReplicaCount` — all confirmed present in `helm show values longhorn/longhorn --version 1.12.1`, all left unset in our `helmrelease.yaml`, all defaulting to `~` → chart default `3`) provides **zero HA benefit** — all 3 replicas of each sidecar necessarily run on the same single node, so if the node goes down all 3 go down together regardless of replica count. But each replica independently competes for the *same* leader-election lease, so running 3 instead of 1 **triples the lease-write pressure this component contributes** to the exact contention issue tracked in #355, for no functional gain. Setting all four `*ReplicaCount` values to `1` would cut this component's contribution to the cluster-wide lease churn by two-thirds with no downside on this topology — worth raising back to 3 only when this becomes a genuine multi-node cluster. This doesn't fix #355 (the kine ceiling itself is unrelated to any one component), but it's a real, cheap, immediately-available mitigation that reduces exposure while the eventual etcd migration is pending. Filed as the first concrete mitigation candidate in issue #355 — not applied yet per this audit pass being read-only.

### 🟢 Well-configured, no action needed

- Chart pinned at `1.12.1` — confirmed current upstream latest (`helm search repo --versions`), zero drift, no Renovate PR needed.
- `persistence.defaultClassReplicaCount: 1` is already correctly set for this single-node topology, with a clear comment explaining why and when to raise it — the *volume* replica count was already handled correctly; it's specifically the *CSI sidecar pod* replica counts (a separate, easy-to-miss setting) that weren't.
- `persistence.defaultClass: false` deliberately keeps local-path as the implicit cluster default, consistent with the same policy already documented for csi-hostpath-sc — apps opt in explicitly, not silently defaulted onto Longhorn.
- Core data-plane components (`longhorn-manager`, `longhorn-csi-plugin`, `engine-image`, `instance-manager`, `longhorn-driver-deployer`, `longhorn-ui`) all show **0 restarts** over 11 days — only the CSI sidecars (which leader-elect) are affected, consistent with the pattern seen everywhere else in this audit: leader-electing components are the ones hitting the kine ceiling, non-electing ones stay rock stable.

### 🟡 Worth knowing, not independently investigated further

Did not do a full resource-limits/securityContext/RBAC pass on every one of the ~19 pods in this namespace given the volume of pods and the more urgent finding above — worth a dedicated follow-up if a full pass is wanted, out of scope for this pass's time budget.
