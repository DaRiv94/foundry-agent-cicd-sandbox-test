#!/usr/bin/env bash
# 1_deploy_infra.sh - deploy infra/main.bicep into your sandbox resource group. It adds the
# chat-model deployment to your existing Foundry account. Idempotent: rerunning changes nothing
# that already matches.
#
# Sandbox edition: run this once, by you. The pipeline never runs it, because the pipeline
# identity holds Foundry User, which cannot create model deployments.
# Usage:  ./scripts/1_deploy_infra.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"; [[ -z "$line" || "$line" == \#* ]] && continue; export "${line%%=*}=${line#*=}"
done < "$ROOT/.env"
for k in AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP FOUNDRY_ACCOUNT FOUNDRY_PROJECT; do
  [[ -n "${!k:-}" && "${!k}" != *"<"* ]] || { echo "Run ./scripts/0_prepare.sh first: $k is not set in .env."; exit 1; }
done
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
rg="$AZURE_RESOURCE_GROUP"

echo "Deploying infra/main.bicep into $rg (chat-model on $FOUNDRY_ACCOUNT) ..."
az deployment group create --resource-group "$rg" --name "infra-$(date +%Y%m%d%H%M%S)" \
  --template-file "$ROOT/infra/main.bicep" --parameters foundryAccountName="$FOUNDRY_ACCOUNT" \
  --query "properties.outputs.deploymentName.value" -o tsv | sed "s/^/Model deployment : /"
echo "Project endpoint : https://${FOUNDRY_ACCOUNT}.services.ai.azure.com/api/projects/${FOUNDRY_PROJECT}"
echo "Next: python scripts/2_deploy_agent.py --env dev"
