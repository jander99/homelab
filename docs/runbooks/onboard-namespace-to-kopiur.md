# Onboarding a namespace to Kopiur backups

Reference runbook from the **prowlarr** migration on 2026-08-15/16.

## TL;DR

To add a new namespace to kopiur:

1. Ensure the app PVC is on **`csi-hostpath-sc`** (only this storage class has a
   snapshot class bound — `csi-hostpath-snapclass`). Migrate if not.
2. Provision a **`kopiur-repo`** PV + PVC pair in the new namespace (50 Gi RWX
   on `smb-media`, bound to the dedicated backup SMB sub-share
   `\\MemoryAlpha\backups\`).
3. Add a `SnapshotPolicy` + `SnapshotSchedule` pointing at the source PVC.
4. The mover's `securityContext.runAsUser/runAsGroup` must match the app's
   PUID/PGID, and `podSecurityContext.fsGroup` must match PGID.

## Phase 1 — Storage class migration (only if PVC isn't on csi-hostpath-sc)

The prowlarr PVC (`local-path`, 2 Gi) was migrated to `csi-hostpath-sc` with a
two-step rsync because K8s does not allow changing `storageClassName` on a
Bound PVC. The PVC **name was kept stable** to avoid touching deployment.yaml.

Observed downtime (prowlarr): **~100 seconds** (00:26:31 → 00:28:11). With
the deployment's existing `Recreate` strategy, the cutover is just a scale-0
and scale-1.

Steps (apply imperatively during the cutover window — Flux won't reconcile
until the feature branch merges to `master`):

1. Provision a companion PVC on the target storage class:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: <pvc>-hostpath        # companion; deleted after cutover
     namespace: <ns>
   spec:
     accessModes: [ReadWriteOnce]
     storageClassName: csi-hostpath-sc
     resources: { requests: { storage: <same> } }
   ```
2. One-shot copy pod mounts both PVCs, rsyncs with `-aHAX --delete`, chowns
   to `PUID:PGID`, exits. Confirms with `OK`.
3. Spot-check the copy: `kubectl run verify-copy --rm -it --image=alpine:3.20
   --overrides='{...}' ls -la /data`.
4. **Scale app to 0.** `kubectl -n <ns> scale deploy <app> --replicas=0`.
5. `kubectl delete pvc <pvc>` (the original, on `local-path`).
6. `kubectl apply` a fresh PVC with the same name on the new storage class.
7. Second one-shot copy pod rsyncs data from the companion into the freshly
   bound replacement.
8. Scale app back to 1. Verify the pod is `Ready`.
9. `kubectl delete pvc <pvc>-hostpath` and force-delete the second copy pod
   (csi-hostpath finalizers hang if a pod still references the PVC).
10. Update `pvc.yaml` storageClassName in the feature branch; commit + push.

Why two copy passes? We could have deleted and recreated in one step, but
keeping the original PVC alive as the source-of-truth during Phase 1 means we
can retry Phase 2 if anything goes wrong before touching the live PVC name.

## Phase 2 — Provision kopiur-repo storage

The kopiur mover Pod mounts a PVC named **`kopiur-repo`** in the **app's
namespace**. Without it, the Pod is `Unschedulable` and the snapshot wedges:

```
0/1 nodes are available: persistentvolumeclaim "kopiur-repo" not found
```

The first prowlarr snapshot at 00:48 wedged for exactly this reason — we
had provisioned the SnapshotPolicy + Schedule but forgotten the per-namespace
repo PVC. Snapshot at 01:48 succeeded once we created the PV/PVC pair.

Create `pv-<ns>.yaml` next to `pv-gatus.yaml` / `pv-headlamp.yaml` /
`pv-kopiur-system.yaml` in `k3s/infrastructure/configs/kopiur/`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kopiur-repo-<ns>             # namespace-suffixed PV name
spec:
  capacity: { storage: 50Gi }
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: smb-media
  mountOptions:
    - vers=3.0
    - dir_mode=0777
    - file_mode=0777
    - uid=<PUID>                     # match app's PUID
    - gid=<PGID>                     # match app's PGID
    - noperm
    - cache=strict
    - noserverino
  csi:
    driver: smb.csi.k8s.io
    readOnly: false
    volumeHandle: kopiur-repo-<ns>-vol
    volumeAttributes:
      source: //192.168.1.20/backups    # dedicated backup SMB sub-share
    nodeStageSecretRef:
      name: smbcreds
      namespace: kube-system
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopiur-repo                   # always "kopiur-repo" — what the
                                      # mover Pod's volume resolver looks for
  namespace: <ns>
spec:
  accessModes: [ReadWriteMany]
  storageClassName: smb-media
  volumeName: kopiur-repo-<ns>
  resources: { requests: { storage: 50Gi } }
```

Add it to `k3s/infrastructure/configs/kopiur/kustomization.yaml` and to the
same infra-configs Kustomization that owns the ClusterRepository (so the PV
binds before kopiur schedules any movers in the new namespace).

## Phase 3 — SnapshotPolicy + SnapshotSchedule

`k3s/infrastructure/configs/kopiur-policies/snapshotpolicy-<app>.yaml`:

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: SnapshotPolicy
metadata:
  name: <app>
  namespace: <ns>
spec:
  repository: { kind: ClusterRepository, name: nas }
  sources:
    - pvc: { name: <app>-config }
      sourcePathOverride: /config     # must match the container's mountPath
  copyMethod: Snapshot
  volumeSnapshotClassName: csi-hostpath-snapclass
  compression: { compressor: zstd }
  retention: { keepHourly: 24, keepDaily: 14, keepWeekly: 8, keepMonthly: 6 }
  verification:
    quick: { schedule: { cron: "H 3 * * *" } }   # Jenkins H = stable minute
  credentialProjection: { enabled: true }
  mover:
    securityContext:
      runAsUser: <PUID>
      runAsGroup: <PGID>
    podSecurityContext:
      fsGroup: <PGID>
      fsGroupChangePolicy: OnRootMismatch
    cache: { capacity: 1Gi, storageClassName: local-path, mode: Ephemeral }
```

`snapshotschedule-<app>.yaml` — note the `policyRef` (not `snapshotPolicyRef`)
and no `retention` field:

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: SnapshotSchedule
metadata:
  name: <app>-scheduled
  namespace: <ns>
spec:
  policyRef: { name: <app> }
  schedule:
    cron: "H * * * *"
    runOnCreate: false
```

Add both files to `k3s/infrastructure/configs/kopiur-policies/kustomization.yaml`.
The schedule's first run waits up to one hour (the `H * * * *` cron) — set
`runOnCreate: true` for an immediate smoke test, then revert to `false`.

## Validation signals

| Signal | Where |
|---|---|
| Snapshot CR reaches `Succeeded` | `kubectl get snapshot -n <ns>` |
| Policy `lastVerified` set | `kubectl get snapshotpolicy -n <ns> <app> -o yaml` |
| Kopia snapshot ID | `.status.snapshot.kopiaSnapshotID` |
| Schedule last/next time | `kubectl get snapshotschedule -n <ns>` |
| Mover Job logs (per-snapshot) | `kubectl -n <ns> get jobs` → logs of `<backup-name>` |
| End-to-end run time | ~1m48s for prowlarr (77.9 MiB source) |

For prowlarr the first successful snapshot was:
- `b0dbb6f16b8e1c2190adfebc8e762206`
- Fired at 01:48:01 UTC
- Mover created at 01:49:23
- Verified at 01:49:49
- Total elapsed: 1m48s

## Common gotchas

1. **SnapshotSchedule uses `policyRef`, not `snapshotPolicyRef`** — the first
   prowlarr apply errored with `unknown field "spec.retention"`, `unknown
   field "spec.snapshotPolicyRef"`. Reference:
   `k3s/infrastructure/configs/kopiur-policies/snapshotschedule-gatus.yaml`.
2. **csi-hostpath finalizer hangs on Terminating PVCs** that are still
   referenced by a pod. Force-delete any copy pod before retrying PVC delete:
   `kubectl delete pod <name> --force --grace-period=0`.
3. **Flux won't reconcile until the feature branch merges to `master`.** Apply
   imperatively during migration windows — the manifests in the worktree are
   the eventual source of truth, but they don't take effect until merge.
4. **`sourcePathOverride` must match the container's mountPath.** Prowlarr
   mounts its config at `/config` (LinuxServer convention). Headlamp uses
   `/data`. Get it from `kubectl describe pod` or the deployment's
   `volumeMounts`.
5. **The mover's `runAsUser`/`runAsGroup` must match the app's PUID/PGID, and
   `podSecurityContext.fsGroup` must match PGID.** Check the deployment's env
   vars (`PUID`, `PGID`) and the pod's `securityContext.fsGroup`.

## Per-namespace quick reference (post-prowlarr)

| NS | PUID | PGID | sourcePathOverride | Storage |
|---|---|---|---|---|
| gatus | 1000 | 1000 | /data | csi-hostpath-sc |
| headlamp | 100 | 101 | /data | csi-hostpath-sc |
| media (prowlarr) | 1027 | 100 | /config | csi-hostpath-sc |

To onboard: radarr-config, sonarr-config (same media namespace — need their
own kopiur-repo media PV/PVC, or share via a separate PV; media namespace
already has prowlarr's kopiur-repo so a second PV `kopiur-repo-media-2`
might collide on PV naming — use `kopiur-repo-radarr` + `kopiur-repo-sonarr`
as separate PVs sharing the SMB source).