#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# teardown.sh — Local teardown script (mirrors the GitHub Actions workflow)
#
# Usage:
#   ./infrastructure/scripts/teardown.sh --environment dev
#   ./infrastructure/scripts/teardown.sh --environment all
#
# Prerequisites:
#   az login (or az login --use-device-code)
#   az account set --subscription <your-subscription-id>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

NAME_PREFIX="contoso"
ENVIRONMENT=""

usage() {
  echo "Usage: $0 --environment <dev|test|prod|all>"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --environment) ENVIRONMENT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$ENVIRONMENT" ]] && usage

delete_env() {
  local env="$1"
  local rgs=(
    "rg-${NAME_PREFIX}-hub-${env}"
    "rg-${NAME_PREFIX}-spoke-${env}"
    "rg-${NAME_PREFIX}-storage-${env}"
  )

  echo ""
  echo "═══════════════════════════════════════"
  echo "  Tearing down: ${env}"
  echo "═══════════════════════════════════════"

  for rg in "${rgs[@]}"; do
    if az group exists --name "$rg" | grep -q true; then
      echo "  🗑  Deleting $rg ..."
      az group delete --name "$rg" --yes --no-wait
    else
      echo "  ✓  Already absent: $rg"
    fi
  done

  echo "  ⏳ Deletions submitted (async — Azure completes in ~5 min)"
}

# Safety prompt for prod
if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "all" ]]; then
  echo ""
  echo "⚠️  WARNING: You are about to delete the PRODUCTION environment."
  read -rp "   Type 'delete-prod' to confirm: " CONFIRM
  if [[ "$CONFIRM" != "delete-prod" ]]; then
    echo "❌ Confirmation failed. Aborting."
    exit 1
  fi
fi

case "$ENVIRONMENT" in
  dev)  delete_env dev ;;
  test) delete_env test ;;
  prod) delete_env prod ;;
  all)
    delete_env dev
    delete_env test
    delete_env prod
    ;;
  *) usage ;;
esac

echo ""
echo "✅ Teardown complete."
echo "   To redeploy: gh workflow run 'Deploy Hub-Spoke Infrastructure' --field environment=<env>"
