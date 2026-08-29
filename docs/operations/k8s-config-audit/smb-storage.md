# smb-storage (StorageClass, no dedicated namespace)

**Audit date:** 2026-08-28

StorageClass for SMB/CIFS-backed volumes from a Synology NAS, provisioned by `csi-driver-smb` (already audited).

## Findings

### 🟢 Well-configured, no action needed

- Not the cluster default (`storageclass.kubernetes.io/is-default-class: "false"`, explicit comment explaining local-path remains default) — apps opt in explicitly, consistent with the same policy already documented for csi-hostpath-sc and longhorn.
- `reclaimPolicy: Retain` (unlike the other StorageClasses in this cluster, which are all `Delete`) — deliberate protection against accidental deletion of shared media data.
- Credentials referenced by name (`smbcreds`, `kube-system` namespace) match what was confirmed SOPS-encrypted in the csi-driver-smb audit — not re-verified here, already covered.
- `dir_mode=0777, file_mode=0777, noperm` mount options were flagged in the csi-driver-smb audit as "worth confirming intent" — seeing the StorageClass directly alongside its comments confirms this is a deliberate, documented choice (shared read-write access for multiple app pods with different UIDs against the same media library), not an unreviewed default.

### 🔴 Clear actionable gaps

None found.
