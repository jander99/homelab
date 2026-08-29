# recyclarr (media)

**Audit date:** 2026-08-29

CronJob (not a Deployment — the only batch-workload app in this audit series besides the migration-only Jobs elsewhere), syncing TRaSH-Guides quality profiles/custom formats into sonarr + radarr nightly.

## Findings

### 🟢 Well-configured, no action needed

- `securityContext` on the Job's pod template is fully hardened out of the box: `runAsNonRoot`, explicit non-root UID/GID `1000`, `fsGroup: 1000` — better default posture than most of the raw-Deployment apps in this series (tdarr, radarr, qbittorrent, sabnzbd all lack this).
- No implicit-`default`-ServiceAccount gap to flag: recyclarr genuinely needs no Kubernetes API access and there's nothing here suggesting one was granted — worth a quick explicit `automountServiceAccountToken: false` for parity with the pattern already flagged elsewhere, but lower priority since there's no dedicated non-default ServiceAccount to begin with (same root cause as the other findings, smallest blast radius of the set).
- `concurrencyPolicy: Forbid` + `successfulJobsHistoryLimit: 3`/`failedJobsHistoryLimit: 1` — sensible CronJob hygiene, prevents overlapping syncs and caps history growth.
- `recyclarr-secrets.sops.yaml` genuinely SOPS-encrypted (age-key-based, in-file instructions for re-encrypting after rotation) — Sonarr/Radarr API keys aren't leaked in plaintext.
- Config injects secrets via `!env_var` indirection (`envFrom: secretRef`) rather than templating keys directly into the ConfigMap — API keys never touch the non-secret `recyclarr-config` ConfigMap.
- `quality_profiles` reference well-known TRaSH-Guides `trash_id`s with human-readable inline comments explaining the ladder — legible, maintainable config, not opaque IDs.
- Resource requests/limits set (`100m/128Mi` → `500m/512Mi`) — reasonable for a short-lived nightly sync.
- Live: last 3 scheduled runs (`2026-08-26`, `2026-08-27`, `2026-08-28`, all ~06:30 UTC daily) all show `Complete`, 12-14s runtime each — the automation is genuinely working, not just configured.

### 🟡 Worth knowing, not actionable

- No forward-auth/ingress at all — correctly so, this is a batch job with no HTTP surface, nothing to expose.
- Not covered by any `kopiur` SnapshotPolicy — correctly so, its only state is the `recyclarr-config` ConfigMap (declarative, in git) and the ephemeral Job pod itself; nothing here needs backup.

### Kine/leader-election pattern (issue #355) check

Not applicable — recyclarr is a short-lived batch Job, not a controller, and doesn't leader-elect.
