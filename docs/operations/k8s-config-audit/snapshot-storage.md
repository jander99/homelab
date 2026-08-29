# snapshot-storage (VolumeSnapshotClasses, no dedicated namespace)

**Audit date:** 2026-08-28

VolumeSnapshotClasses for the two snapshot-capable CSI drivers in this cluster (longhorn, csi-hostpath) — consumed by kopiur SnapshotPolicies (already audited) and the cluster-wide `snapshot-controller` (already audited).

## Findings

### 🟢 Well-configured, no action needed

- Both classes deliberately avoid `snapshot.storage.kubernetes.io/is-default-class` — kopiur SnapshotPolicies pick by name (`spec.volumeSnapshotClassName`), and the comments explain marking either default would cause ambiguity if a third class is ever added. Consistent, documented policy across both files.
- `longhorn-snapclass` correctly uses `type: snap` (in-cluster, copy-on-write, node-local) rather than `type: bak` (push to a configured Longhorn backup target) — the comment correctly explains kopiur's own mover Pods already handle moving data off-cluster, so a second, redundant off-cluster push via Longhorn's own backup mechanism would be wasted work.
- Live cluster matches git exactly: `csi-hostpath-snapclass` and `longhorn-snapclass` are the only two VolumeSnapshotClasses present, both `deletionPolicy: Delete`, both bound to the correct driver.
- The `longhorn`/`longhorn-static` StorageClasses visible on the live cluster (not declared anywhere in this repo) are chart-managed — Longhorn's own Helm chart creates them regardless of `persistence.defaultClass: false` (already confirmed in the longhorn audit); not missing config, just not something this repo needs to declare since the chart owns it.

### 🔴 Clear actionable gaps

None found.
