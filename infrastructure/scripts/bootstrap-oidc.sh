#!/usr/bin/env bash
# bootstrap-oidc.sh
# Run this ONCE from a machine with az CLI + gh CLI logged in.
# It creates the Azure App Registration, federated credentials, and
# pushes the three secrets into your GitHub repo.
#
# Usage:
#   chmod +x bootstrap-oidc.sh
#   GITHUB_ORG=sufideen GITHUB_REPO=azcloudtrain01 ./bootstrap-oidc.sh

set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:-sufideen}"
GITHUB_REPO="${GITHUB_REPO:-azcloudtrain01}"
APP_NAME="sp-${GITHUB_REPO}-cicd"

echo "==> Logging in to Azure (browser will open)"
az login --output none

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "    Subscription : $SUBSCRIPTION_ID"
echo "    Tenant       : $TENANT_ID"

# ── 1. Create App Registration ────────────────────────────────────────────
echo "==> Creating App Registration: $APP_NAME"
CLIENT_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId -o tsv)
echo "    Client ID    : $CLIENT_ID"

# Create the service principal
az ad sp create --id "$CLIENT_ID" --output none

# ── 2. Assign Contributor at subscription scope ───────────────────────────
echo "==> Assigning Contributor role"
az role assignment create \
  --assignee "$CLIENT_ID" \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --output none

# ── 3. Add federated credentials (one per environment + main branch) ─────────
OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)

for ENV in dev test prod; do
  echo "==> Federated credential for environment: $ENV"
  az ad app federated-credential create \
    --id "$OBJECT_ID" \
    --parameters "{
      \"name\": \"github-${GITHUB_REPO}-${ENV}\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENV}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" --output none
done

# Also add one for the master branch (used by the validate job)
echo "==> Federated credential for branch: master"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-${GITHUB_REPO}-master\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/master\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none

# Also add one for pull requests
echo "==> Federated credential for pull_request events"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-${GITHUB_REPO}-pr\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none

# ── 4. Push secrets to GitHub ─────────────────────────────────────────────────
echo "==> Writing GitHub repository secrets (requires gh CLI)"
gh secret set AZURE_CLIENT_ID       --body "$CLIENT_ID"       --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_TENANT_ID       --body "$TENANT_ID"       --repo "${GITHUB_ORG}/${GITHUB_REPO}"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID" --repo "${GITHUB_ORG}/${GITHUB_REPO}"

echo ""
echo "==> Done! Values for reference:"
echo "    AZURE_CLIENT_ID       = $CLIENT_ID"
echo "    AZURE_TENANT_ID       = $TENANT_ID"
echo "    AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo ""
echo "Next: create GitHub Environments (dev / test / prod) in the repo settings,"
echo "      then merge the feature branch to main to trigger the pipeline."
