# Monitoring Operations Runbook

## Grafana Git Sync — Configuration & Recovery

### Overview

Grafana v13 Git Sync is configured to sync dashboards from `jander99/homelab-dashboards`
(branch: `main`, path: `dashboards/`). It polls every 60s — no webhook is configured
because Grafana is MetalLB-internal only (not externally reachable by GitHub).

The PAT used is stored in Grafana's database and survives pod restarts. A SOPS-encrypted
backup is kept at `k3s/infrastructure/configs/monitoring/grafana-gitsync-pat.sops.yaml`
(K8s secret `grafana-gitsync-pat` in namespace `monitoring`).

---

### PAT Details

| Field | Value |
|---|---|
| Scope | `jander99/homelab-dashboards` only |
| Permissions | Contents R/W, Pull requests R/W, Webhooks R/W, Metadata R |
| Expiry | ~1 year from creation — check BitWarden |
| BitWarden entry | `homelab-dashboards grafana-gitsync PAT` |

---

### Initial Configuration (UI — preferred)

1. Open <https://grafana.homelab.properties>
2. Navigate: **Administration → General → Provisioning → Git Sync** tab
3. Add repository:
   - **Provider:** GitHub
   - **Repository URL:** `https://github.com/jander99/homelab-dashboards`
   - **Branch:** `main`
   - **Path:** `dashboards/`
   - **PAT:** _(decrypt secret below and paste the token value)_
4. Save. Grafana will begin syncing within 60 seconds.

---

### Recovery — Grafana DB Wiped

If Grafana's database is wiped, the Git Sync configuration is lost. To recover:

**Step 1 — Retrieve the PAT:**

```bash
SOPS_AGE_KEY_FILE=~/.kube/k3s-homelab-age.agekey \
  sops --decrypt k3s/infrastructure/configs/monitoring/grafana-gitsync-pat.sops.yaml \
  | grep token
```

**Step 2 — Re-configure via the UI** (see "Initial Configuration" above) using the
decrypted token.

#### Alternative: API (headless)

First obtain a Grafana service account token, then:

```bash
curl -X POST "https://grafana.homelab.properties/apis/provisioning.grafana.app/v0alpha1/namespaces/default/repositories" \
  -H "Authorization: Bearer <grafana-service-account-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "provisioning.grafana.app/v0alpha1",
    "kind": "Repository",
    "metadata": {"name": "homelab-dashboards"},
    "spec": {
      "title": "Homelab Dashboards",
      "type": "github",
      "github": {
        "url": "https://github.com/jander99/homelab-dashboards",
        "branch": "main",
        "path": "dashboards/"
      },
      "sync": {"enabled": true, "intervalSeconds": 60, "target": "folder"},
      "workflows": ["write", "branch"]
    },
    "secure": {"token": {"create": "<PAT-from-SOPS>"}}
  }'
```

---

### PAT Rotation

1. Generate a new fine-grained PAT at <https://github.com/settings/tokens?type=fine-grained>
   with the same permissions as listed in [PAT Details](#pat-details) above.
2. Update the BitWarden entry `homelab-dashboards grafana-gitsync PAT` with the new value and expiry.
3. Update the SOPS-encrypted secret:
   ```bash
   # Opens $EDITOR with decrypted YAML; saves encrypted in-place on exit
   SOPS_AGE_KEY_FILE=~/.kube/k3s-homelab-age.agekey \
     sops k3s/infrastructure/configs/monitoring/grafana-gitsync-pat.sops.yaml
   ```
4. Commit, push, and open a PR with the updated SOPS file.
5. Re-configure Git Sync in the Grafana UI (or via API) using the new PAT. The old
   configuration will stop working once the old PAT expires.

---

### Verifying Sync Status

In the Grafana UI: **Administration → General → Provisioning → Git Sync**

Check the last sync timestamp and any error banners. Dashboards in `dashboards/` of
`jander99/homelab-dashboards` (branch `main`) should appear within 60 seconds of a commit.
