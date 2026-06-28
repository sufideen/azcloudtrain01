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
CAPTURE_DIR="teardown-assets/$(date -u +%Y%m%dT%H%M%SZ)"

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

# ── Asset capture (runs BEFORE any deletion) ──────────────────────────────────
capture_env() {
  local env="$1"
  local out="${CAPTURE_DIR}/${env}"
  mkdir -p "$out"

  echo ""
  echo "═══════════════════════════════════════"
  echo "  Capturing assets: ${env}"
  echo "═══════════════════════════════════════"

  local rgs=(
    "rg-${NAME_PREFIX}-hub-${env}"
    "rg-${NAME_PREFIX}-spoke-${env}"
    "rg-${NAME_PREFIX}-storage-${env}"
  )

  # 1. Resource list — every resource in every RG
  for rg in "${rgs[@]}"; do
    if az group exists --name "$rg" | grep -q true; then
      echo "  📋 Resource list: $rg"
      az resource list --resource-group "$rg" \
        --query "[].{name:name,type:type,location:location,sku:sku.name}" \
        -o table > "${out}/${rg}-resources.txt" 2>/dev/null || true
    fi
  done

  # 2. ARM export — full deployed state as JSON for each RG
  for rg in "${rgs[@]}"; do
    if az group exists --name "$rg" | grep -q true; then
      echo "  📦 ARM export: $rg"
      az group export --name "$rg" --include-parameter-default-value \
        -o json > "${out}/${rg}-arm-export.json" 2>/dev/null || \
        echo "    ⚠️  ARM export skipped (unsupported resource type in $rg)"
    fi
  done

  # 3. Network topology snapshot
  local hub_rg="rg-${NAME_PREFIX}-hub-${env}"
  if az group exists --name "$hub_rg" | grep -q true; then
    echo "  🌐 Network topology: ${env}"
    az network watcher show-topology \
      --resource-group "$hub_rg" \
      -o json > "${out}/network-topology.json" 2>/dev/null || true
  fi

  # 4. App Gateway config
  local appgw_name="agw-${NAME_PREFIX}-${env}"
  if az network application-gateway show \
       --name "$appgw_name" --resource-group "$hub_rg" &>/dev/null; then
    echo "  🔒 App Gateway config: ${appgw_name}"
    az network application-gateway show \
      --name "$appgw_name" --resource-group "$hub_rg" \
      -o json > "${out}/app-gateway.json" 2>/dev/null || true
  fi

  # 5. Cost summary (last 30 days)
  echo "  💰 Cost summary: ${env}"
  local start_date end_date
  end_date=$(date -u +%Y-%m-%d)
  start_date=$(date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || \
               date -u -v-30d +%Y-%m-%d)   # macOS fallback
  for rg in "${rgs[@]}"; do
    if az group exists --name "$rg" | grep -q true; then
      az consumption usage list \
        --start-date "$start_date" --end-date "$end_date" \
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg" \
        --query "[].{date:usageStart,resource:instanceName,cost:pretaxCost,currency:currency}" \
        -o table > "${out}/${rg}-cost.txt" 2>/dev/null || \
        echo "    ⚠️  Cost data unavailable (requires billing reader role)"
    fi
  done

  echo "  ✅ Assets captured → ${out}/"
}

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
  dev)
    capture_env dev
    delete_env dev
    ;;
  test)
    capture_env test
    delete_env test
    ;;
  prod)
    capture_env prod
    delete_env prod
    ;;
  all)
    capture_env dev
    capture_env test
    capture_env prod
    delete_env dev
    delete_env test
    delete_env prod
    ;;
  *) usage ;;
esac

echo ""
echo "✅ Teardown complete."
echo "   Assets saved to: ${CAPTURE_DIR}/"
echo "   To redeploy: gh workflow run 'Deploy Hub-Spoke Infrastructure' --field environment=<env>"
