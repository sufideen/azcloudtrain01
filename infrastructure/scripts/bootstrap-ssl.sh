#!/usr/bin/env bash
# bootstrap-ssl.sh — One-time: generate a self-signed TLS cert and upload to Key Vault
#
# Run AFTER the first pipeline deploy (Key Vault must exist).
# Then re-deploy passing keyVaultCertSecretUri to activate the HTTPS listener.
#
# Usage:
#   ./infrastructure/scripts/bootstrap-ssl.sh \
#     --keyvault-name kv-contoso-dev-abc123 \
#     --cert-name     ssl-cert-dev \
#     --domain        contoso-dev.uksouth.cloudapp.azure.com
# ---------------------------------------------------------------------------
set -euo pipefail

KV_NAME=""
CERT_NAME="ssl-cert"
DOMAIN="localhost"

while [[ $# -gt 0 ]]; do
  case $1 in
    --keyvault-name) KV_NAME="$2";  shift 2 ;;
    --cert-name)     CERT_NAME="$2"; shift 2 ;;
    --domain)        DOMAIN="$2";   shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$KV_NAME" ]] && { echo "Error: --keyvault-name is required"; exit 1; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🔐 Generating self-signed certificate for: $DOMAIN"
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -keyout "$TMPDIR/key.pem" \
  -out    "$TMPDIR/cert.pem" \
  -subj   "/CN=${DOMAIN}/O=Contoso/C=GB" \
  -addext "subjectAltName=DNS:${DOMAIN},DNS:localhost"

openssl pkcs12 -export \
  -out     "$TMPDIR/cert.pfx" \
  -inkey   "$TMPDIR/key.pem" \
  -in      "$TMPDIR/cert.pem" \
  -passout pass:

echo "☁️  Uploading certificate to Key Vault: $KV_NAME / $CERT_NAME"
az keyvault certificate import \
  --vault-name "$KV_NAME" \
  --name       "$CERT_NAME" \
  --file       "$TMPDIR/cert.pfx" \
  --password   ""

# Strip the version from the URI — App Gateway will always use latest (enables auto-rotation)
SECRET_URI=$(az keyvault certificate show \
  --vault-name "$KV_NAME" \
  --name       "$CERT_NAME" \
  --query      "sid" \
  --output     tsv)
VERSIONLESS_URI="${SECRET_URI%/*}"

echo ""
echo "✅ Certificate uploaded successfully."
echo ""
echo "Add this parameter to your .bicepparam file, then re-run the deploy pipeline:"
echo ""
echo "  param keyVaultCertSecretUri = '${VERSIONLESS_URI}'"
echo ""
echo "The HTTPS listener on App Gateway will activate on the next deploy."
