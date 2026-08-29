# pihole (pihole)

**Namespace:** pihole
**Chart version:** 2.38.0 (mojo2600-pihole/pihole) — current upstream latest, zero chart drift
**Audit date:** 2026-08-28

In-cluster Pi-hole v6 DNS server, exposed via MetalLB LoadBalancer (DNS, 192.168.1.201) and Traefik Ingress (web UI). A separate `external-dns-k3s` HelmRelease (already covered in the `external-dns` audit) pushes records into this instance.

## Findings

### 🔴 Actionable finding

- **`image.tag: "2026.05.0"` is pinned 2 releases behind current upstream** (`2026.07.2` is what chart `2.38.0`'s own `appVersion` points to; `2026.06.0` and `2026.07.2` have both shipped since). No open Renovate PR covers this. The chart's own version is tracked fine (Flux/Renovate's `flux` manager watches `chart.spec.version`), but this specific field is a manual `image.tag` override nested inside `values:`, and `renovate.json`'s generic `kubernetes` manager doesn't appear to be picking it up — no annotation comment, no matching open PR despite genuine drift. Worth either adding a `# renovate: datasource=docker depName=pihole/pihole` comment annotation so Renovate starts tracking this field, or bumping it by hand now.

### 🟢 Well-configured, no action needed

- Chart pinned at `2.38.0` — confirmed current upstream latest (`helm search repo --versions`), zero chart drift.
- Both SOPS secrets (`pihole-admin-password.sops.yaml`, `pihole-k3s-password.sops.yaml`) are genuinely encrypted (`ENC[AES256_GCM,...]`), not plaintext leaks.
- **Probe-timing fix (PR #256) genuinely applied** — unlike dcgm-exporter's equivalent fix, which silently no-op'd. Pihole didn't use the `postRenderers` mechanism at all; probes are set directly via the chart's native `values.probes.*` field, confirmed matching on both the rendered chart output and the live pod (`initialDelaySeconds: 30` on both liveness/readiness, live and rendered). No risk of the dcgm-exporter-style silent-mismatch bug here since there's no patch-target-name to get wrong.
- Resource requests/limits set on both containers (pihole + pihole-exporter sidecar), matching live cluster exactly.
- `migration/restore.yaml` is legitimate, well-documented leftover from a completed csi-hostpath→longhorn storage migration — deliberately excluded from `kustomization.yaml` with a clear comment explaining why (avoids Flux refighting the completed migration). Not dead config in a bad way; it's a runbook artifact, correctly not wired into ongoing reconciliation.
- 0 restarts over 6 days on the live pod — no stability issues.
- DNS-impact tradeoff of the storage migration is explicitly documented (1-3 min SERVFAIL window), and podDnsConfig correctly routes the pod's own DNS resolution around itself to avoid a chicken-and-egg bootstrap problem.

### 🟡 Worth knowing, structurally hard to fix (upstream chart limitation)

- Neither the `pihole` container nor the `pihole-exporter` sidecar gets any `securityContext` hardening beyond a hardcoded `privileged: false` on the main container — no `runAsNonRoot`, no capability drops, no seccomp profile, no override knob exposed anywhere in the chart's values.yaml for either container. Confirmed via `helm show values` — this isn't a values override we're missing, the chart simply doesn't template a configurable securityContext at all. Root is actually required here (per the migration doc's own note: "pihole container runs as root (uid=0) so it can read logrotate", plus binding port 53), but even the achievable partial hardening (dropped capabilities, seccomp) isn't exposed as an option.

### Kine/leader-election pattern (issue #355) check

Not applicable. Pi-hole is a DNS server, not a Kubernetes controller — no leader-election flags anywhere in the rendered manifests, and 0 restarts over 6 days rules out any instability of any kind, let alone this specific pattern.
