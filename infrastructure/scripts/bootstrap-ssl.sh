#!/usr/bin/env bash
# bootstrap-ssl.sh
# Generates a SELF-SIGNED certificate (demo/dev use only) and imports it into Key Vault.
# Prints the versionless secret URI to use as keyVaultCertSecretUri in the .bicepparam file.
#
# Usage:
#   ./bootstrap-ssl.sh --environment dev --keyvault-name <kv-name> [--domain <cn>]
#
# Requires: az CLI (logged in, with "Key Vault Certificates Officer" on the vault), openssl.

set -euo pipefail

ENVIRONMENT="dev"
KV_NAME=""
DOMAIN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment)   ENVIRONMENT="$2"; shift 2 ;;
    --keyvault-name) KV_NAME="$2"; shift 2 ;;
    --domain)        DOMAIN="$2"; shift 2 ;;
    -h|--help)       sed -n 2,10p "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$KV_NAME" ]] && { echo "ERROR: --keyvault-name is required" >&2; exit 1; }
DOMAIN="${DOMAIN:-contoso-${ENVIRONMENT}.example.com}"
CERT_NAME="appgw-ssl-${ENVIRONMENT}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Generating self-signed certificate for ${DOMAIN}"
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
  -subj "/CN=${DOMAIN}" -addext "subjectAltName=DNS:${DOMAIN}" 2>/dev/null
cat "$WORKDIR/key.pem" "$WORKDIR/cert.pem" > "$WORKDIR/combined.pem"

echo "==> Importing into Key Vault ${KV_NAME} as ${CERT_NAME}"
az keyvault certificate import \
  --vault-name "$KV_NAME" --name "$CERT_NAME" \
  --file "$WORKDIR/combined.pem" --output none

SECRET_URI="https://${KV_NAME}.vault.azure.net/secrets/${CERT_NAME}"
echo
echo "Done. Add this to infrastructure/parameters/${ENVIRONMENT}.bicepparam:"
echo "  param keyVaultCertSecretUri = '${SECRET_URI}'"
