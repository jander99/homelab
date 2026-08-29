# csi-hostpath (kube-system)

**Namespace:** kube-system
**Chart version:** v1.17.1 (alvistack/csi-hostpathplugin) — current upstream latest, zero drift
**Audit date:** 2026-08-29

CSI driver providing the `csi-hostpath-sc` StorageClass, originally added to support snapshot-capable PVCs for headlamp + gatus before Longhorn existed in this cluster (see `[[local-path-pvcs-need-csi-hostpath-for-snapshots]]` memory note).

## Findings

### 🔴 Clear actionable gap — the StorageClass is now completely orphaned

`csi-hostpath-sc` has **zero live PVCs** cluster-wide (checked every PVC's `storageClassName` directly). The only two consumers it was ever added for have already migrated off:

- `k3s/applications/headlamp/helmrelease.yaml:112` — `storageClassName: longhorn`, with a comment confirming "Migrated from csi-hostpath-sc to longhorn"
- `k3s/applications/gatus/helmrelease.yaml:64` — same pattern, "Migrated from csi-hostpath-sc to longhorn in #307"

Every other repo reference to `csi-hostpath-sc` (headlamp, gatus, and ~15 other apps' `migration/` directories) is a historical migration manifest, already-applied and inert — not a live consumer. This matches the kopiur audit's finding that all 17 `csi-hostpath→longhorn` migration Restore CRs show `Completed` — the migration this driver existed to support is fully finished.

The `csi-hostpathplugin-0` StatefulSet (8 containers: hostpath, csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter, node-driver-registrar, liveness-probe, csi-external-health-monitor-controller) is still running and still leader-electing for no operational benefit. Recommend removing the whole `k3s/infrastructure/controllers/csi-hostpath/` directory (and the matching `VolumeSnapshotClass`/`StorageClass` config if any remains in `infra-configs/snapshot-storage/`) now that nothing binds to it — this both removes dead config and reduces one more contributor to the cluster-wide kine lease contention below.

### 🔴 Confirmed instance of the kine/leader-election pattern (issue #355)

`csi-external-health-monitor-controller` has **79 restarts over 7d3h** — every other sidecar in the same pod (csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter, hostpath, liveness-probe) shows **0 restarts**, consistent with this being specifically the one leader-electing component. `--previous` logs show the exact same signature as every other confirmed instance: lease renewal for `external-health-monitor-leader-hostpath-csi-k8s-io` failed with `context deadline exceeded` at **2026-08-28T22:20:00.717Z** — inside the confirmed 22:19:59.891Z–22:20:37Z cascade window (now 6 controllers across kube-system, flux-system, kopiur-system, longhorn-system confirmed in that exact window). Adding as a new data point on issue #355.

### 🟡 Worth knowing, structurally hard to fix

- `reclaimPolicy: Delete` on `csi-hostpath-sc` (vs. `Retain` on `smb-media`) — moot given the StorageClass has no live PVCs, but worth noting for whoever removes this: no data-retention step is needed since nothing is bound.
- `volumeBindingMode: Immediate` — chart default, not a local override.

## Recommendation

Given the orphaned-controller finding is a clean, low-risk removal (zero live consumers, confirmed migration complete), this is a better candidate for an actual cleanup PR than most audit findings — unlike the kine leader-election pattern (architectural, tracked in #355) or most 🟡 items (informational only).
