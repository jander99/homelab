# coredns (kube-system)

**Audit date:** 2026-08-28

k3s's built-in CoreDNS, extended via a `coredns-custom` ConfigMap (k3s's officially supported customization mechanism) — not a separate Helm-managed deployment.

## Findings

### 🟢 Well-configured, no action needed

- `coredns-custom` ConfigMap uses k3s's officially documented extension mechanism (`import /etc/coredns/custom/*.server`, confirmed live in the built-in Corefile — matches k3s's documented CoreDNS custom-configuration-imports pattern exactly). Not a hack or workaround.
- Live ConfigMap matches git byte-for-byte.
- The `homelab.properties:53` forward zone is a genuinely load-bearing, well-integrated piece of the DNS chain, not standalone config: every Ingress across every application in this repo uses a `*.homelab.properties` hostname (confirmed via grep — radarr, sonarr, prowlarr, sabnzbd, qbittorrent, tdarr, gatus, headlamp, portainer, authentik, monitoring probes all reference this suffix). This zone is what lets in-cluster pods resolve those hostnames at all, by forwarding to the two pihole instances (`192.168.1.2` external, `192.168.1.201` in-cluster LoadBalancer — both addresses independently confirmed correct against the already-audited external-dns and pihole components) which hold the actual records populated by external-dns.
- Forward target order (external pihole first, in-cluster pihole second) is CoreDNS's standard primary/fallback semantics — reasonable redundancy, not a misconfiguration.

### 🟡 Worth knowing, not actionable

1 restart in 21 days, `exitCode=255`/`reason=Unknown` at `2026-08-08T01:20:33Z` — matches the exact same timestamp already found on node-feature-discovery's master+gc pods earlier in this audit series (same node/containerd-level event, third independent confirmation of that fingerprint). Not the kine lease-timeout pattern (issue #355) — CoreDNS doesn't leader-elect, single replica, no lease RBAC.

### 🔴 Clear actionable gaps

None found.
