# Restoring a PVC from a Kopiur backup

Reference runbook synthesized from two real restores: the csi-hostpath→longhorn
migration (11 PVCs across 8 apps, 2026-08-20/22) and the sabnzbd data-loss
incident recovery (2026-08-21/22, `restore-config.yaml`). Both used the same
mechanism — a kopiur `Restore` CR — for different reasons: the migration
wanted the *latest* snapshot onto a new storage class, the incident wanted a
*specific pre-incident* snapshot after the latest ones turned out to be
useless. This doc covers both paths.

Companion doc: [`onboard-namespace-to-kopiur.md`](onboard-namespace-to-kopiur.md)
for getting a namespace *into* backup coverage in the first place.

## TL;DR

1. Decide which snapshot you want: **latest** (`source.fromPolicy`) or a
   **specific point in time** (`source.snapshotRef`). Use snapshotRef whenever
   there's any chance the latest snapshot(s) are backups *of the bad state* —
   see Phase 1.
2. Pre-flight: confirm the SnapshotPolicy has exactly one `sources:` entry
   (see Gotcha 1 — this bug has bitten this cluster before), and set
   `policy.onMissingSnapshot: Fail` so a missing/empty snapshot fails loudly
   instead of silently creating an empty PVC.
3. Scale the target Deployment/StatefulSet to 0 and suspend the HelmRelease
   if the PVC is chart-managed.
4. Delete the existing PVC if its name would conflict with the Restore's
   `target.pvc.name`.
5. `kubectl apply -f restore.yaml`.
6. Watch `kubectl get restore -n <ns>` until `phase: Completed`.
7. Scale back up. Verify at the **application** level, not just PVC-bound —
   the sabnzbd incident had a PVC that looked perfectly healthy while empty.
8. Resume the HelmRelease. Leave the Restore CR in the tree as a record, or
   delete it — it's a no-op once completed either way.

## Phase 1 — Choose the source: `fromPolicy` vs `snapshotRef`

**`fromPolicy`** pulls the latest successful snapshot from a named
`SnapshotPolicy`, optionally offset backward (`offset: N` = N snapshots ago).
This is what every csi-hostpath→longhorn migration restore used — the source
PVC was healthy right up to the migration, so "latest" was always the right
answer.

```yaml
source:
  fromPolicy:
    name: <policy-name>     # matches the SnapshotPolicy's metadata.name
    offset: 0                # 0 = latest, 1 = one snapshot before that, ...
```

**`snapshotRef`** pins to one specific `Snapshot` CR by name — the resource
type kopiur creates for every completed snapshot, whether scheduled or
manually discovered. Use this for disaster recovery, where "latest" may
already be the disaster:

```yaml
source:
  snapshotRef:
    name: <snapshot-cr-name>
    namespace: <ns>
```

This is what sabnzbd's recovery used. `fromPolicy` would have quietly
restored the *empty post-incident config*, because the SnapshotPolicy had
kept running on its normal schedule after the wipe and had no idea anything
was wrong — the schedule doesn't know good state from bad. Find the right
snapshot first:

```bash
kubectl get snapshot -n <ns>                              # list all
kubectl get snapshot -n <ns> -o wide                       # + timestamps
kubectl get snapshot -n <ns> <name> -o jsonpath='{.status}'
```

Cross-reference the timestamp against when you know the data was still good
(deploy logs, incident timeline, `kubectl get events`). Prefer a snapshot
from *before* the bad event with margin, not the one immediately preceding
it — timestamps on Discovered Snapshot CRs can lag the actual backup content.

## Phase 2 — Pre-flight checks

Do these **before** touching the running app:

1. **Multi-source check.** `kubectl get snapshotpolicy -n <ns> <name> -o yaml`
   and confirm `spec.sources` has exactly one entry. A `SnapshotPolicy` with
   multiple sources silently captures only the first and drops the rest —
   see Gotcha 1. If
   you're restoring from a policy with more than one source, the snapshot
   you're about to trust may not contain what you think it does.
2. **Confirm the mover identity.** Look up the app's UID/GID in the
   [reference table](#per-namespace-reference) below, or read them directly
   off the `SnapshotPolicy`'s `mover.securityContext`. The Restore's mover
   must match, or restored files land with the wrong ownership and the app
   won't start.
3. **Confirm privileged-mover status.** If the app runs as root (pihole,
   portainer, and — per the SnapshotPolicy comments — authentik, grafana,
   alertmanager, tdarr-server-data), the source namespace carries the
   `kopiur.home-operations.com/privileged-movers: "true"` annotation and the
   SnapshotPolicy sets `mover.privilegedMode: true` alongside
   `runAsUser: 0`. **This has not been verified end-to-end on an actual
   Restore** (only on SnapshotPolicy/backup — see the audit note in
   [`kopiur.md`](../operations/k8s-config-audit/kopiur.md)).
   Set the same `privilegedMode: true` + root securityContext on the
   Restore's `mover` block for these apps, and treat the first restore of
   any of them as a test of this assumption, not a known-good path.
4. **Credentials.** Every SnapshotPolicy in this cluster uses
   `ClusterRepository: nas`, whose credential Secret lives in
   `kopiur-system`, not the app's namespace. `credentialProjection.enabled:
   true` is required on the Restore or it stalls in `Pending` with
   `MissingCredentialsSecret`.

## Phase 3 — Prepare the target

```bash
# If chart-managed, stop Flux/Helm from fighting the PVC swap:
kubectl -n flux-system patch helmrelease <app> -p '{"spec":{"suspend":true}}' --type=merge

# Release the RWO lock on the current PVC:
kubectl -n <ns> scale deploy/<app> --replicas=0        # or statefulset
kubectl -n <ns> wait --for=delete pod -l app=<app> --timeout=60s

# If target.pvc.name reuses an existing PVC name, delete it first —
# Restore will hit a name conflict otherwise. The data is safe in the
# kopia repository regardless of what happens to this PVC.
kubectl -n <ns> delete pvc <pvc-name>
```

If a stale `VolumeSnapshot` on the old storage class still holds a
`pvc-as-source-protection` finalizer on the source PVC, clear that first (see
the gatus migration, PR #307, for the patch sequence) — otherwise the PVC
delete hangs in `Terminating`.

## Phase 4 — Apply the Restore CR

Generic template — adjust `source`, `target`, and `mover` per Phases 1–2:

```yaml
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: <app>-restore
  namespace: <ns>
spec:
  source:
    # pick ONE — see Phase 1
    fromPolicy:
      name: <policy-name>
      offset: 0
    # snapshotRef:
    #   name: <snapshot-cr-name>
    #   namespace: <ns>
  target:
    pvc:
      name: <pvc-name>
      storageClassName: longhorn
      accessModes: [ReadWriteOnce]
      capacity: <size>
  credentialProjection:
    enabled: true
  mover:
    # Preferred: inherit UID/GID from what the backup mover actually used,
    # recorded as a kopia tag on the snapshot itself — no manual chown risk.
    inheritSecurityContextFrom:
      snapshot: {}
    # If inheritSecurityContextFrom doesn't cover privileged mode (Phase 2,
    # check 3), set explicitly instead:
    # securityContext:
    #   runAsUser: 0
    #   runAsGroup: 0
    #   runAsNonRoot: false
    # privilegedMode: true
    cache:
      capacity: 1Gi
      storageClassName: local-path
      mode: Ephemeral
  failurePolicy:
    backoffLimit: 2
    activeDeadlineSeconds: 1800     # raise for large PVCs (sabnzbd used 3600 for ~12.5GiB)
  policy:
    onMissingSnapshot: Fail          # fail loudly rather than provision an empty PVC
```

Not in `kustomization.yaml` — this is operator-applied, once, imperatively.
Flux would otherwise re-run it on every reconcile.

```bash
kubectl apply -f restore.yaml
```

## Phase 5 — Validate

| Signal | Command |
|---|---|
| Restore phase | `kubectl get restore -n <ns> <name>` → `Completed` |
| Restore detail / failure reason | `kubectl get restore -n <ns> <name> -o yaml` → `.status` |
| Mover Job logs | `kubectl -n <ns> get jobs` → logs of the restore job |
| PVC bound | `kubectl get pvc -n <ns> <pvc-name>` → `Bound`, correct storage class |
| **Data actually present** | `kubectl run -n <ns> verify --rm -it --image=alpine:3.20 --overrides='...' -- ls -la /data` mounting the restored PVC directly, **before** scaling the app back up |

That last row is the one the sabnzbd incident skipped. The restored PVC was
`Bound` and looked completely normal in every `kubectl get` — the only way
anyone caught the empty-config problem was noticing the app behaving as a
fresh install ~90 minutes later. Don't trust `Bound`; look inside.

## Phase 6 — Resume and clean up

```bash
kubectl -n <ns> scale deploy/<app> --replicas=1
kubectl -n flux-system patch helmrelease <app> -p '{"spec":{"suspend":false}}' --type=merge
```

Check app-level health (not just `Ready` — actually exercise the feature the
restored data backs: DNS resolution for pihole, a login for authentik, the
job history for radarr/sonarr/prowlarr, torrents resuming for
qbittorrent/sabnzbd).

The Restore CR is harmless once `Completed` — reconciling it again is a
no-op. Delete it if you don't want it as a permanent record:

```bash
kubectl delete restore -n <ns> <name>
```

Keeping it (as the migration restores do, in `k3s/applications/<app>/migration/`)
documents what was restored, from where, and why — worth it for anything
beyond a routine drill.

## Common gotchas

1. **Multi-source `SnapshotPolicy` silently drops all but the first
   source.** Root cause of the sabnzbd incident. Fixed and re-verified across
   all 16 current policies (each declares exactly 1 source) — but check again
   before trusting a policy you haven't looked at recently.
2. **`fromPolicy` restores whatever the schedule most recently captured —
   including a backup of already-broken data.** If you're recovering from an
   incident, work out the last-known-good timestamp first and use
   `snapshotRef`, not `fromPolicy`.
3. **`credentialProjection.enabled: true` is required**, not optional, for
   every app in this cluster — the kopia repository credential lives in
   `kopiur-system`, never in the app's own namespace. Missing it stalls the
   Restore in `Pending` with `MissingCredentialsSecret`.
4. **UID/GID mismatch leaves restored files unreadable to the app.**
   `inheritSecurityContextFrom.snapshot: {}` is the safe default — it reads
   the UID/GID the backup mover actually used, recorded on the snapshot
   itself, rather than requiring you to hand-copy it.
5. **Restore's `target.pvc.name` colliding with an existing PVC fails the
   apply.** Delete the old PVC first — the data is safe in the kopia repo
   independent of what happens to the k8s PVC object.
6. **A stale `VolumeSnapshot` finalizer can block that PVC delete.** If
   `kubectl delete pvc` hangs in `Terminating`, check for orphaned
   `VolumeSnapshot`s referencing it as source and clear their finalizers.
7. **Restoring a chart-managed PVC while the HelmRelease is still active
   races Helm's own reconciliation.** Suspend the HelmRelease before
   scaling down; resume it only after the app is confirmed healthy on the
   restored PVC.
8. **`Bound` is not `correct`.** Always spot-check file contents on the
   restored PVC before scaling the app back up — see Phase 5.

## Per-namespace reference

All entries below have `spec.source.repository: {kind: ClusterRepository, name: nas}` and `credentialProjection.enabled: true`.

| App / policy | Namespace | Source PVC | Mount path | Mover UID:GID | Privileged mover |
|---|---|---|---|---|---|
| alertmanager | monitoring | `alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0` | `/alertmanager/alertmanager-db` | 1000:2000 | yes |
| authentik | authentik | `data-authentik-postgresql-0` | `/bitnami/postgresql/data` | 1001:1001 | yes |
| gatus | gatus | `gatus` | `/data` | 1000:1000 | no |
| grafana | monitoring | `kube-prometheus-stack-grafana` | `/var/lib/grafana` | 472:472 | yes |
| headlamp | headlamp | `headlamp` | `/data` | 100:101 | no |
| pihole | pihole | `pihole` | `/etc/pihole` | 0:0 | yes |
| portainer | portainer | `portainer` | `/data` | 0:0 | yes |
| prowlarr | media | `prowlarr-config` | `/config` | 1027:100 | no |
| qbittorrent-config | qbittorrent | `qbittorrent-config` | `/config` | 1027:100 | no |
| qbittorrent-gluetun | qbittorrent | `gluetun-config` | `/gluetun` | 1027:100 | no |
| radarr | media | `radarr-config` | `/config` | 1027:100 | no |
| sabnzbd-config | sabnzbd | `sabnzbd-config` | `/config` | 1027:100 | no |
| sabnzbd-gluetun | sabnzbd | `gluetun-config` | `/gluetun` | 1027:100 | no |
| sonarr | media | `sonarr-config` | `/config` | 1027:100 | no |
| tdarr-node-config | tdarr | `tdarr-node-config` | `/app/configs` | 1027:100 | no |
| tdarr-server-data | tdarr | `tdarr-server-data` | `/app/server` | 1027:100 | yes |

## Not covered here

**Prometheus, Loki, and Tempo hold weeks of history on `local-path`, which
has no snapshot class — none of it is kopiur-covered.** There is no restore
path for these; they're out of scope for this runbook because there's
nothing to restore *from*. Flagged separately as GAP in the three-node
readiness review.

**There is still no scheduled, unattended verification of this restore
path** — everything above has only ever been run by a human, under
supervision, during a migration or an incident. A monthly CronJob that
restores a canary snapshot into a scratch PVC and checks a sentinel file
(alerting via Alertmanager on failure) would catch the next version of the
multi-source bug before it reaches production data. Worth doing as a
follow-up; not built yet.
