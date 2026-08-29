# csi-driver-smb (kube-system)

**Namespace:** kube-system
**Chart version:** 1.20.3 — current upstream latest, zero drift
**Audit date:** 2026-08-28

Kubernetes CSI driver providing SMB/CIFS-backed persistent volumes from a Synology NAS, used by `radarr`, `sonarr`, `qbittorrent`, `sabnzbd`, `tdarr` for shared media storage.

## Findings

### 🟢 Well-configured, no action needed

- Chart is already on the latest available version (`1.20.3` — confirmed via `helm search repo --versions`, no drift).
- All sidecar/driver images are pinned to explicit versions (no `:latest`) and match what's actually running live.
- Non-privileged sidecars (`liveness-probe`, `node-driver-registrar`, `csi-provisioner`, `csi-resizer`) all have `readOnlyRootFilesystem` and dropped capabilities where the chart sets them.
- `livenessProbe` present on the main driver container (HTTP healthz via the liveness-probe sidecar).
- RBAC is properly least-privilege — scoped to PV/PVC/StorageClass/CSINode/Node reads and a `get`-only (no `list`/`watch`) grant on Secrets, needed because the StorageClass references a named credential secret. No CRD watches, no cluster-wide secret enumeration. Notably tighter than `alloy`'s RBAC.
- Credentials are SOPS-encrypted (`smb-credentials.sops.yaml`), with a clean non-secret `.example` template for onboarding — matches the "never hardcode credentials" requirement correctly.
- StorageClass is actively in use — 16 PVCs bound across 8 namespaces, not dead config.

### 🔴 Actionable finding (caught live, not a static config gap)

- **The controller pod has 155 restarts on `csi-provisioner` and 71 on `csi-resizer` over 16 days** (the `smb` driver container itself and `liveness-probe` sidecar: 0 restarts — rock solid). Root cause confirmed via crash logs: both sidecars lose their leader-election lease with `Put ".../leases/..." context deadline exceeded`, then intentionally `os.Exit(1)` per client-go leaderelection's standard "stop leading → exit" behavior. This is the same symptom as cert-manager's crash-restarts (see `cert-manager.md`) and the already-documented `k3s-kine-scalability-ceiling` issue — single-node k3s + kine/SQLite datastore chokes when many controllers hit `coordination.k8s.io` leases concurrently. Not a csi-driver-smb misconfiguration. No user-visible impact so far (PVCs stayed bound throughout), but it's real, ongoing operational noise. The chart doesn't expose leader-election timeout tuning (`leader-election-lease-duration`/`renew-deadline`/`retry-period`) via `values.yaml`, so mitigating this at the csi-driver-smb level specifically isn't straightforward — this is a symptom of the cluster-wide kine issue and should be tracked/fixed there, not per-component.

### 🟡 Worth knowing, structurally hard to fix (upstream/architectural)

- `smb` driver container runs `privileged: true` on both the node DaemonSet and controller Deployment — required and justified: CSI node plugins need host mount-namespace access to bind-mount CIFS shares into pod volume paths (`mountPropagation: Bidirectional` against `/var/lib/kubelet`). Same pattern used by essentially every CSI node driver upstream (matches the `system-upgrade-controller` Job-privilege precedent from the earlier upgrade-controller audit). Controller Deployment also runs `hostNetwork: true` — this is the chart's own template default, not something set in our values override.
- StorageClass mount options (`dir_mode=0777, file_mode=0777, noperm`) are maximally permissive at the filesystem layer — plausible/likely intentional given multiple app pods with different UIDs need shared read-write access to the same media library, but worth explicitly confirming that's still the intent rather than an inherited default nobody revisited.
