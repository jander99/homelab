# Metrics stack: local-path -> longhorn-nvme-local

Moves Prometheus, Loki and Tempo from `local-path` (SATA root disk, no snapshots) to
`longhorn-nvme-local` (NVMe, strict-local, backed up by kopiur). Same two-stage rsync pattern as the
alertmanager and Grafana moves. Do one service at a time, Tempo first (pilot), then Loki, then Prometheus.

Measured usage before the move: Prometheus 13G/20Gi, Loki 304M/20Gi, Tempo 1.1M/5Gi.
New sizes: 20Gi, 5Gi, 2Gi (must match the HelmRelease values in this PR).

**Do not merge the PR until all three cutovers are done.** Loki/Tempo StatefulSet volume templates are
immutable, so the new values must only reach Helm after the StatefulSets and PVCs already match.

## Variables

| | Prometheus | Loki | Tempo |
|---|---|---|---|
| ns | monitoring | telemetry | telemetry |
| HelmRelease | kube-prometheus-stack | loki | tempo |
| PVC | `prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0` | `storage-loki-0` | `storage-tempo-0` |
| Workload | `Prometheus/kube-prometheus-stack-prometheus` (operator) | `sts/loki` | `sts/tempo` |
| Manifests | `applications/monitoring/migration/prometheus-nvme-stage{1,2}.yaml` | `infrastructure/controllers/loki/migration/` | `infrastructure/controllers/tempo/migration/` |

## Procedure (per service; `$NS`, `$HR`, `$PVC`, `$SVC` from the table)

```bash
export KUBECONFIG=~/.kube/k3s-testbed.yaml

# 1. Quiesce. Suspend the HelmRelease first or Helm recreates the old PVC/replicas.
flux suspend hr $HR -n $NS
kubectl -n $NS scale sts/$SVC --replicas=0            # Loki, Tempo
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus \
  --type merge -p '{"spec":{"replicas":0}}'            # Prometheus only
kubectl -n $NS wait --for=delete pod/${SVC}-0 --timeout=300s   # Prometheus: prometheus-kube-prometheus-stack-prometheus-0

# 2. Keep the original data: local-path deletes the directory when the PVC goes, unless the PV is Retain.
PV=$(kubectl -n $NS get pvc $PVC -o jsonpath='{.spec.volumeName}')
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# 3. Stage 1: old PVC -> intermediate PVC (longhorn-nvme-local).
kubectl apply -f <stage1 manifest>
kubectl -n $NS wait --for=condition=complete job/${SVC}-nvme-copy-stage1 --timeout=1h
kubectl -n $NS logs job/${SVC}-nvme-copy-stage1 | tail -8      # file and byte counts must match

# 4. Remove the old PVC and the StatefulSet (keeps volumeClaimTemplate immutability out of the way).
kubectl -n $NS delete pvc $PVC
kubectl -n $NS delete sts $SVC --cascade=orphan     # Prometheus: delete the sts; the operator recreates it at replicas 0

# 5. Stage 2: intermediate -> PVC with the original name, now on longhorn-nvme-local.
kubectl apply -f <stage2 manifest>
kubectl -n $NS wait --for=condition=complete job/${SVC}-nvme-copy-stage2 --timeout=1h
kubectl -n $NS logs job/${SVC}-nvme-copy-stage2 | tail -8
kubectl -n $NS delete pvc ${SVC}-intermediate
```

## After all three are cut over

1. Merge the PR. Policies and schedules apply; the HelmRelease values now match the live PVCs.
2. Resume and verify, per service: `flux resume hr $HR -n $NS`. Prometheus: the HelmRelease resets the CR to
   1 replica. Confirm the pod starts and the PVC is `longhorn-nvme-local`.
3. Check the data survived: Prometheus range query reaching back past the migration time, a Loki
   `{namespace=~".+"}` query over the last 24h, a Tempo search in Grafana.
4. Confirm each kopiur `Snapshot` completes (`kubectl get kopiasnap -A`).
5. After about a week, drop the retained originals: `kubectl delete pv <old PV>`, then remove the left-over
   `/var/lib/rancher/k3s/storage/pvc-*` directories on the node (Retain keeps them).

## Rollback (before step 5 above)

The old data is still on the node. Re-create a `local-path` PVC bound to the retained PV (clear its
`claimRef`), revert the HelmRelease values, and resume.
