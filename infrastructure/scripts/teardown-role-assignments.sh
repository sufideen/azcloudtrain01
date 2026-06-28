#!/usr/bin/env bash
# teardown-role-assignments.sh
# Removes all role assignments for the CI/CD service principal when the
# subscription is idle (e.g. after a demo or when not actively deploying).
# Re-run bootstrap-oidc.sh to restore access before the next deployment.
#
# Usage:
#   GITHUB_ORG=sufideen GITHUB_REPO=azcloudtrain01 NAME_PREFIX=contoso ./teardown-role-assignments.sh

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-azcloudtrain01}"
NAME_PREFIX="${NAME_PREFIX:-contoso}"
APP_NAME="sp-${GITHUB_REPO}-cicd"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
CLIENT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)

if [[ -z "$CLIENT_ID" ]]; then
  echo "ERROR: App Registration '$APP_NAME' not found. Nothing to remove."
  exit 1
fi

echo "==> Removing role assignments for $APP_NAME ($CLIENT_ID)"

# Remove subscription-level Reader
az role assignment delete \
  --assignee "$CLIENT_ID" \
  --role Reader \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --output none 2>/dev/null && echo "    Removed: Reader @ subscription" || echo "    Skipped: Reader @ subscription (not found)"

# Remove per-RG Contributor and User Access Administrator
for ENV in dev test prod; do
  for TIER in hub spoke storage; do
    RG_NAME="rg-${NAME_PREFIX}-${TIER}-${ENV}"
    SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG_NAME}"

    az role assignment delete \
      --assignee "$CLIENT_ID" \
      --role Contributor \
      --scope "$SCOPE" \
      --output none 2>/dev/null && echo "    Removed: Contributor @ $RG_NAME" || true

    az role assignment delete \
      --assignee "$CLIENT_ID" \
      --role "User Access Administrator" \
      --scope "$SCOPE" \
      --output none 2>/dev/null && echo "    Removed: User Access Administrator @ $RG_NAME" || true
  done
done

echo ""
echo "==> All role assignments removed. The App Registration and federated"
echo "    credentials are still in place — run bootstrap-oidc.sh to restore"
echo "    access before the next deployment."
