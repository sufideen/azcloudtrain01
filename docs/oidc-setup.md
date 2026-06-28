# OIDC Setup — Passwordless Azure Authentication for GitHub Actions

This guide sets up **OpenID Connect (OIDC)** between GitHub Actions and Azure so your pipeline can deploy to Azure without storing any secrets or passwords.

---

## What Is OIDC and Why Use It?

Traditional pipelines store an Azure client secret in GitHub. That secret can be leaked, expire, or be forgotten. OIDC replaces the secret entirely:

```
GitHub Actions runner            Azure Active Directory
        │                                │
        │── "I am run on               ──►│
        │   sufideen/azcloudtrain01       │── Checks: repo name ✓ branch ✓
        │   branch: master"              │
        │                                │
        │◄── Access token (60 min) ──────│
        │                                │
        │── Deploy to Azure ────────────►│
```

No secrets stored. No rotation schedule. Every run is independently auditable.

> Microsoft reference: [Configure OIDC in Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)

---

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- GitHub CLI installed and authenticated (`gh auth login`)
- Contributor access on your Azure subscription
- Admin access on the GitHub repository

---

## Step 1 — Run the Bootstrap Script (Automated)

The repository includes a script that does everything automatically:

```bash
chmod +x infrastructure/scripts/bootstrap-oidc.sh

./infrastructure/scripts/bootstrap-oidc.sh \
  --subscription-id <your-subscription-id> \
  --github-repo sufideen/azcloudtrain01
```

This script:
1. Creates an Azure App Registration (service principal)
2. Assigns Contributor role at subscription scope
3. Adds federated credentials for each environment (`dev`, `test`, `prod`) and branch (`master`)
4. Pushes `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` as GitHub secrets

Skip to [Step 4 — Verify](#step-4--verify) if the script succeeds.

---

## Step 2 — Manual Setup (If You Prefer Full Control)

### 2a — Create an App Registration

```bash
az ad app create --display-name "azcloudtrain01-github-oidc"
```

Note the `appId` from the output — you will need it below.

### 2b — Create a Service Principal

```bash
az ad sp create --id <appId-from-above>
```

### 2c — Assign Contributor Role at Subscription Scope

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
  --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID
```

> Microsoft reference: [Assign Azure roles using Azure CLI](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli)

### 2d — Add Federated Credentials

Run once per environment. The `subject` must exactly match what GitHub sends — any mismatch causes `AADSTS700213`.

**For the master branch (dev auto-deploy):**
```bash
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-master",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:sufideen/azcloudtrain01:ref:refs/heads/master",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**For the dev environment:**
```bash
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-env-dev",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:sufideen/azcloudtrain01:environment:dev",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Repeat for `test` and `prod`** — change `"name"` and `"subject"` for each.

> Microsoft reference: [Configuring OpenID Connect in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)

---

## Step 3 — Add GitHub Secrets

```bash
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CLIENT_ID=<appId-from-above>

gh secret set AZURE_CLIENT_ID       --body "$CLIENT_ID"       --repo sufideen/azcloudtrain01
gh secret set AZURE_TENANT_ID       --body "$TENANT_ID"       --repo sufideen/azcloudtrain01
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo sufideen/azcloudtrain01
```

> GitHub reference: [Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)

---

## Step 4 — Create GitHub Environments

GitHub environments allow you to add approval gates before deploying to test or prod.

```bash
# The GitHub CLI does not create environments directly — use the GitHub UI:
# Repository → Settings → Environments → New environment
# Create: dev, test, prod
# Add required reviewers on test and prod
```

Or via the GitHub REST API:
```bash
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/sufideen/azcloudtrain01/environments/dev

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/sufideen/azcloudtrain01/environments/test

gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/sufideen/azcloudtrain01/environments/prod
```

> GitHub reference: [Creating and using environments](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment)

---

## Step 4 — Verify

Run a test pipeline to confirm OIDC is working:

```bash
gh workflow run "Deploy Hub-Spoke Infrastructure" \
  --repo sufideen/azcloudtrain01 \
  --ref master \
  --field environment=dev
```

Watch the run:
```bash
gh run watch --repo sufideen/azcloudtrain01
```

A successful login step in the pipeline logs looks like:

```
Run azure/login@v2
Federated token obtained successfully
Login successful
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `AADSTS700213 — No matching federated identity record found` | Subject string mismatch | Check the `subject` field character by character — it must exactly match `repo:org/repo:ref:refs/heads/master` or `repo:org/repo:environment:dev` |
| `AuthorizationFailed` during deployment | Contributor role not assigned | Run the `az role assignment create` command above |
| `Bad credentials` on GitHub secrets | Wrong `appId` used | Re-check with `az ad app list --display-name azcloudtrain01-github-oidc` |
| Pipeline skips with no error | Environment not created in GitHub | Go to Settings → Environments and create `dev`, `test`, `prod` |

---

*Next: [Rebuild the dev environment](rebuild-dev.md)*
