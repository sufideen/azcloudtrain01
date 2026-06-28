#!/usr/bin/env bash
# bootstrap-oidc.sh
# Run this ONCE from a machine with az CLI + gh CLI logged in.
# It creates the Azure App Registration, federated credentials, and
# pushes the three secrets into your GitHub repo.
#
# Usage:
#   chmod +x bootstrap-oidc.sh
#   GITHUB_ORG=sufideen GITHUB_REPO=azcloudtrain01 NAME_PREFIX=contoso ./bootstrap-oidc.sh

set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:-sufideen}"
GITHUB_REPO="${GITHUB_REPO:-azcloudtrain01}"
NAME_PREFIX="${NAME_PREFIX:-contoso}"
APP_NAME="sp-${GITHUB_REPO}-cicd"

echo "==> Logging in to Azure (browser will open)"
az login --output none

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "    Subscription : $SUBSCRIPTION_ID"
echo "    Tenant       : $TENANT_ID"

# ── 1. Create App Registration (single-tenant) ────────────────────────────────
echo "==> Creating App Registration: $APP_NAME (single-tenant)"
CLIENT_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)
echo "    Client ID    : $CLIENT_ID"

# Create the service principal
az ad sp create --id "$CLIENT_ID" --output none

OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)

# ── 2. Assign Contributor scoped to per-environment resource groups only ──────
# Avoids granting subscription-wide Contributor which is overly broad.
# Resource groups are created by the pipeline on first deploy; role assignments
# are idempotent so re-running this script is safe.
for ENV in dev test prod; do
  for TIER in hub spoke storage; do
    RG_NAME="rg-${NAME_PREFIX}-${TIER}-${ENV}"
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
    echo "==> Assigning Contributor → $RG_NAME"
    # Resource groups may not exist yet on first run; create them so the
    # role assignment can target them before the first pipeline deployment.
    az group create --name "$RG_NAME" --location uksouth --output none 2>/dev/null || true
    az role assignment create \
      --assignee "$CLIENT_ID" \
      --role Contributor \
      --scope "$SCOPE" \
      --output none
  done
done

# Subscription-level read is still needed for what-if and sub-scoped deployments.
echo "==> Assigning Reader at subscription scope (for what-if)"
az role assignment create \
  --assignee "$CLIENT_ID" \
  --role Reader \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --output none

# Allow the SP to create/manage role assignments within those RGs (needed for
# Key Vault RBAC and managed identity assignments).
for ENV in dev test prod; do
  for TIER in hub spoke storage; do
    RG_NAME="rg-${NAME_PREFIX}-${TIER}-${ENV}"
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"
    az role assignment create \
      --assignee "$CLIENT_ID" \
      --role "User Access Administrator" \
      --scope "$SCOPE" \
      --condition "@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidEquals {b24988ac-6180-42a0-ab88-20f7382dd24c}" \
      --condition-version "2.0" \
      --output none 2>/dev/null || true
  done
done

# ── 3. Add federated credentials (one per environment + branch + PR) ──────────
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

echo "==> Federated credential for branch: master"
az ad app federated-credential create \
  --id "$OBJECT_ID" \
  --parameters "{
    \"name\": \"github-${GITHUB_REPO}-master\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/master\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none

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
echo "Next steps:"
echo "  1. In GitHub → Settings → Environments, add required reviewers for test and prod."
echo "  2. Set Deployment branch policy to 'master' only on each environment."
echo "  3. Run teardown-role-assignments.sh when the subscription is idle to remove all access."
