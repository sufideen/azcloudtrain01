# Rebuilding the Dev Environment

This guide explains how to deploy or rebuild the `dev` environment from scratch — whether the nightly teardown ran, or you want a clean slate.

---

## How the Dev Environment Works

The `dev` environment consists of three Azure resource groups:

```
rg-contoso-hub-dev       ← Hub VNet, App Gateway, Firewall, Bastion
rg-contoso-spoke-dev     ← Spoke VNet, NSGs
rg-contoso-storage-dev   ← Storage account
```

These are created automatically by `infrastructure/main.bicep` using the parameters in `infrastructure/parameters/dev.bicepparam`. If they were deleted by the teardown workflow or manually, re-running the deploy recreates them completely.

---

## Option A — Trigger via GitHub Actions (Recommended)

The cleanest approach — the pipeline handles authentication, validation, and deployment automatically.

```bash
gh workflow run "Deploy Hub-Spoke Infrastructure" \
  --repo sufideen/azcloudtrain01 \
  --ref master \
  --field environment=dev
```

Watch the run live:
```bash
gh run watch --repo sufideen/azcloudtrain01
```

Or open the Actions tab in GitHub:
```
https://github.com/sufideen/azcloudtrain01/actions
```

Deployment takes approximately 5 minutes.

---

## Option B — Deploy Directly from Local Machine (Azure CLI)

Use this if you want to deploy without going through GitHub Actions, or if you are debugging a template issue.

### 1 — Confirm you are logged in

```bash
az account show
```

If not logged in:
```bash
az login
az account set --subscription "<your-subscription-name-or-id>"
```

### 2 — Navigate to the repository root

```bash
cd azcloudtrain01
```

### 3 — Lint the templates first

```bash
az bicep lint --file infrastructure/main.bicep
```

Fix any warnings before proceeding.

### 4 — Run a what-if preview (safe — no changes made)

```bash
az deployment sub what-if \
  --location uksouth \
  --template-file infrastructure/main.bicep \
  --parameters infrastructure/parameters/dev.bicepparam \
  --name dev-whatif-$(date +%s)
```

Review the output. Green `+` means resources to create, yellow `~` means changes, red `-` means deletions.

> Microsoft reference: [What-if operation for Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if)

### 5 — Deploy

```bash
az deployment sub create \
  --location uksouth \
  --template-file infrastructure/main.bicep \
  --parameters infrastructure/parameters/dev.bicepparam \
  --name dev-deploy-$(date +%s)
```

The `$(date +%s)` suffix adds a Unix timestamp to the deployment name, preventing the `DeploymentActive` conflict that occurs when re-using a name while a previous run is still active.

> Microsoft reference: [Deploy Bicep files with Azure CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-cli)

---

## Verify the Deployment

After the deploy completes, confirm the resource groups exist:

```bash
az group list --query "[?contains(name, 'contoso') && contains(name, 'dev')].{Name:name, Location:location, State:properties.provisioningState}" -o table
```

Expected output:
```
Name                       Location    State
-------------------------  ----------  ---------
rg-contoso-hub-dev         uksouth     Succeeded
rg-contoso-spoke-dev       uksouth     Succeeded
rg-contoso-storage-dev     uksouth     Succeeded
```

Check the hub VNet:
```bash
az network vnet list --resource-group rg-contoso-hub-dev -o table
```

---

## Enable HTTPS (Optional — After Initial Deploy)

HTTPS is off by default. To activate it you need an SSL certificate in Key Vault.

```bash
# Generate a self-signed certificate and upload it to Key Vault
chmod +x infrastructure/scripts/bootstrap-ssl.sh

./infrastructure/scripts/bootstrap-ssl.sh \
  --environment dev \
  --keyvault-name <kv-name-from-deployment-output>
```

Then add the cert URI to `infrastructure/parameters/dev.bicepparam`:
```
param keyVaultCertSecretUri = 'https://<kv-name>.vault.azure.net/secrets/<cert-name>'
```

Re-run the deploy — HTTPS activates automatically and HTTP redirects to HTTPS with a 301.

> Microsoft reference: [App Gateway SSL termination with Key Vault](https://learn.microsoft.com/en-us/azure/application-gateway/key-vault-certs)

---

## Tear Down Dev When Done

To avoid unnecessary costs, tear down dev when you are not using it.

### Via GitHub Actions:
```bash
gh workflow run "Teardown Infrastructure" \
  --repo sufideen/azcloudtrain01 \
  --ref master \
  --field environment=dev
```

### Via Azure CLI:
```bash
az group delete --name rg-contoso-hub-dev     --yes --no-wait
az group delete --name rg-contoso-spoke-dev   --yes --no-wait
az group delete --name rg-contoso-storage-dev --yes --no-wait
```

> The nightly teardown workflow also runs automatically at **22:00 UTC Monday–Friday**.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `DeploymentActive` error | Another deployment with the same name is still running. Use `$(date +%s)` in the name or wait a few minutes. |
| `PolicyViolation` — location not allowed | Your Azure management group has a policy restricting regions. Ensure `--location` matches the allowed list. |
| `az login` prompts during deploy | Your token expired. Run `az login` and retry. |
| Resource group already exists with old resources | The deployment is idempotent — re-running updates resources to match the template. No need to delete first unless you want a clean state. |
| Firewall or Bastion stuck in `Updating` | These resources take 5–10 minutes. Wait and re-check with `az resource show`. |

---

*Back to [Setup Guide](setup-guide.md) · [OIDC Setup](oidc-setup.md)*
