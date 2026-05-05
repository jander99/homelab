# cert-manager DNS-01 Cloudflare Setup

This guide details the process of setting up cert-manager with DNS-01 challenges using Cloudflare. This configuration enables the automation of TLS certificates for internal and external services.

## Section 1: Prerequisites

Before proceeding, ensure you have the following tools installed and accounts configured:

- **kubectl**: For cluster interaction.
- **flux CLI**: For GitOps reconciliation and status checks.
- **sops**: For encrypting sensitive information like API tokens.
- **kustomize**: For managing Kubernetes manifests.
- **Cloudflare Account**: With a target domain already added.

## Section 2: Bootstrap check — sops-age Secret

Flux requires access to the age private key to decrypt SOPS-encrypted files. Verify that the `sops-age` Secret exists in the `flux-system` namespace. This must be present before Flux attempts to reconcile `infra-configs`.

If the secret is missing, create it using the following command:

```bash
kubectl create secret generic sops-age \
  --namespace flux-system \
  --from-file=age.agekey=$HOME/.kube/k3s-homelab-age.agekey
```

**Note:** The age private key is expected at `~/.kube/k3s-homelab-age.agekey`, and the public key is defined in the repository root's `.sops.yaml`.

## Section 3: Cloudflare NS delegation

cert-manager uses DNS-01 challenges, which require Let's Encrypt to validate domain ownership from the internet.

1. Add your domain to the Cloudflare dashboard.
2. Update your domain registrar's nameservers to use the specific NS records provided by Cloudflare.
3. Verify propagation using `dig`:

```bash
dig NS <your-domain> @8.8.8.8
```

**Note:** The domain must be delegated to public Cloudflare nameservers for the DNS-01 challenge to succeed. Internal DNS (like Pi-hole) is not sufficient for Let's Encrypt validation.

## Section 4: Cloudflare API token creation

Create a scoped API token in the Cloudflare dashboard. Avoid using the Global API Key for better security.

Required permissions:
- **Zone** -> **DNS** -> **Edit**
- **Zone** -> **Zone** -> **Read**

Scope the token to the specific zone (domain) you are using.

## Section 5: SOPS encrypt the secret

Follow these steps to securely store your Cloudflare API token in the repository:

1. Copy the example file:
   ```bash
   cp k3s/infrastructure/configs/cert-manager/cloudflare-token.sops.yaml.example k3s/infrastructure/configs/cert-manager/cloudflare-token.sops.yaml
   ```
2. Edit `k3s/infrastructure/configs/cert-manager/cloudflare-token.sops.yaml` and replace `<YOUR_CLOUDFLARE_API_TOKEN>` with your real token.
3. Encrypt the file in-place:
   ```bash
   sops -e -i k3s/infrastructure/configs/cert-manager/cloudflare-token.sops.yaml
   ```
4. Commit only the encrypted file:
   ```bash
   git add k3s/infrastructure/configs/cert-manager/cloudflare-token.sops.yaml
   git commit -m "feat(configs): add encrypted cloudflare token"
   ```

**CRITICAL:** Never commit the unencrypted file to version control.

## Section 6: Email placeholder

ACME registration requires an email address for important expiry notices and account recovery.

Replace `<your-email@example.com>` with a real email address in the following files before the first reconciliation:
- `k3s/infrastructure/configs/cert-manager/clusterissuer-staging.yaml`
- `k3s/infrastructure/configs/cert-manager/clusterissuer-prod.yaml`

## Section 7: Staging test

It is recommended to test the pipeline using the Let's Encrypt staging environment to avoid hitting rate limits.

Create a test Certificate in the `default` namespace:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - test.<your-domain>
```

Verify the status of the certificate:
```bash
kubectl describe certificate test-cert -n default
```

Expected output should include `Status: True, Reason: Ready`. Note that staging certificates are not trusted by browsers but confirm that the DNS-01 challenge pipeline is functional.

## Section 8: Prod promotion

Once the staging test is successful, promote your applications to use production certificates.

Update your `Certificate` manifests to reference the `letsencrypt-prod` issuer instead of `letsencrypt-staging`. Note that there is no automatic promotion; each application must explicitly choose the desired issuer. Delete the staging test certificate when it is no longer needed.

## Section 9: Flux reconciliation

Trigger a manual reconciliation to apply the changes immediately:

```bash
flux reconcile kustomization infra-configs --with-source
```

Check the status of the reconciliation and the ClusterIssuers:

```bash
flux get kustomizations
kubectl get clusterissuer letsencrypt-staging letsencrypt-prod
```

## Section 10: Prune warning

The `infra-configs` Kustomization has `prune: true` enabled. If the cert-manager files in `k3s/infrastructure/configs/cert-manager/` are removed from the repository, Flux will delete the ClusterIssuers and the `cloudflare-api-token` Secret from the cluster. It will **not** delete the `cert-manager` namespace (managed by the `platform` Kustomization) or any issued `Certificate` objects (which live in the apps layer). Always plan removals carefully — removing the ClusterIssuers while active certificates still exist will prevent cert-manager from renewing them.
