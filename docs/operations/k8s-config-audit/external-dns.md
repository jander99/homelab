# external-dns (external-dns)

**Namespace:** external-dns
**Chart version:** 1.21.1 — current upstream latest, zero drift
**Audit date:** 2026-08-28

ExternalDNS (`external-dns-docker` release) watching Ingress resources and pushing DNS records to an external Pi-hole instance (`192.168.1.2`) via a webhook provider. A second, separately-declared instance (`external-dns-k3s`, in `k3s/applications/pihole/`) targets an in-cluster Pi-hole — intentional dual-provider setup, out of scope for this audit pass, noted for context only.

## Findings

### 🟢 Well-configured, no action needed

- Chart pinned at `1.21.1` — confirmed current upstream latest (`helm search repo --versions`), zero drift, no Renovate PR needed.
- RBAC is exemplary least-privilege: the rendered ClusterRole grants exactly one rule — `get/watch/list` on `ingresses` — nothing else. Tightest RBAC of any component audited so far, because `sources: [ingress]` in our values means the chart only renders rules for that one source type.
- Both containers (`external-dns`, `webhook`) fully hardened: `runAsNonRoot`, non-root UID/GID (65532), `readOnlyRootFilesystem: true`, all capabilities dropped, no privilege escalation, pod-level seccomp `RuntimeDefault`.
- Both containers have liveness **and** readiness probes configured — better coverage than alloy or cert-manager.
- Resource requests/limits set on both containers, matching live cluster exactly.
- Pi-hole webhook password is genuinely SOPS-encrypted (age-based `ENC[AES256_GCM,...]`), not a plaintext leak.
- `policy: upsert-only` + `registry: noop` are deliberate, documented choices appropriate for a homelab with manually-managed Pi-hole entries (Pi-hole doesn't support TXT records, which is what `registry: noop` accounts for).
- Third-party webhook image (`ghcr.io/tarantini-io/external-dns-pihole-webhook:v1.0.0`) is pinned to an explicit tag, not `:latest`.

### 🟡 Worth knowing, not clearly actionable

- The webhook image is a third-party community project (`tarantini-io/external-dns-pihole-webhook`), not an official `kubernetes-sigs` artifact — inherent trust/maintenance-risk tradeoff of using Pi-hole as a DNS backend at all, not a config mistake.
- No NetworkPolicy (same repo-wide pattern noted for alloy — not repeated in full per-component).

### Kine/leader-election pattern (issue #355) check

Not applicable and not present. Restart counts are low (4/2 over 90 days) and confirmed via `--previous` logs to be caused by both containers dying simultaneously with `exitCode=255`/`Unknown` — a node/runtime-level event, not a lease-timeout crash. This deployment runs `replicas: 1` with `strategy: Recreate` and no leader-election flag in its rendered args, so it isn't architecturally exposed to the kine contention pattern at all. Useful negative data point for issue #355: not every controller in this cluster is at risk, only ones that actually leader-elect.

### 🔴 Clear actionable gaps

None found.
