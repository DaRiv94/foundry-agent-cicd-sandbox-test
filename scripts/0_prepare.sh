#!/usr/bin/env bash
# 0_prepare.sh - find the Foundry account and project in your sandbox resource group and
# check the one role the evaluation gate needs. Creates nothing except a missing role grant.
#
# Sandbox edition: your resource group, Foundry account and project already exist and you
# are not allowed to create new ones, so this script discovers them and writes their names
# into .env for every later script to use.
# Usage:  ./scripts/0_prepare.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
[[ -f "$ENV_FILE" ]] || { echo "Copy .env.example to .env first."; exit 1; }
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"; [[ -z "$line" || "$line" == \#* ]] && continue; export "${line%%=*}=${line#*=}"
done < "$ENV_FILE"
for k in AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP; do
  [[ -n "${!k:-}" && "${!k}" != *"<"* ]] || { echo "Edit .env first: $k is still a placeholder."; exit 1; }
done
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
rg="$AZURE_RESOURCE_GROUP"

# 1. the resource group must already exist (a sandbox student cannot create one)
az group show --name "$rg" --query "properties.provisioningState" -o tsv > /dev/null 2>&1 \
  || { echo "Resource group $rg was not found. Use your own sandbox group, rg-ais-ncus-<alias>-sandbox."; exit 1; }
echo "Resource group  : $rg"

# 2. discover the one Foundry account and its one project
read -r account_name account_id < <(az cognitiveservices account list --resource-group "$rg" \
  --query "[?kind=='AIServices'] | [0].[name, id]" -o tsv | tr '\t' ' ')
[[ -n "${account_name:-}" ]] || { echo "No Microsoft Foundry account found in $rg. Make a post."; exit 1; }
read -r project_full project_principal < <(MSYS_NO_PATHCONV=1 az rest --method get \
  --url "https://management.azure.com${account_id}/projects?api-version=2025-12-01" \
  --query "value[0].[name, identity.principalId]" -o tsv | tr '\t' ' ')
[[ -n "${project_full:-}" ]] || { echo "No Foundry project found in $account_name. Make a post."; exit 1; }
project_name="${project_full##*/}"
endpoint="https://${account_name}.services.ai.azure.com/api/projects/${project_name}"
echo "Foundry account : $account_name"
echo "Foundry project : $project_name"
echo "Project endpoint: $endpoint"

# 3. write the names back into .env (replace the line if present, append if not)
for pair in "FOUNDRY_ACCOUNT=$account_name" "FOUNDRY_PROJECT=$project_name"; do
  key="${pair%%=*}"
  if grep -q "^$key=" "$ENV_FILE"; then
    sed -i.bak "s|^$key=.*|$pair|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    printf '\n%s\n' "$pair" >> "$ENV_FILE"
  fi
done
echo "Wrote FOUNDRY_ACCOUNT and FOUNDRY_PROJECT into .env"

# 4. the evaluation gate runs inside Foundry as the PROJECT's identity, which needs Foundry User
#    on the account. Most sandboxes already have this from Week 2; grant it only if missing.
foundry_user="53ca6127-db72-4b80-b1b0-d745d6d5456d"
existing="$(MSYS_NO_PATHCONV=1 az role assignment list --assignee-object-id "$project_principal" --scope "$account_id" \
  --role "$foundry_user" --query "length(@)" -o tsv --only-show-errors)"
if [[ "${existing:-0}" -gt 0 ]]; then
  echo "Project identity already holds Foundry User on the account."
else
  MSYS_NO_PATHCONV=1 az role assignment create --assignee-object-id "$project_principal" --assignee-principal-type ServicePrincipal \
    --role "$foundry_user" --scope "$account_id" --query id -o tsv --only-show-errors > /dev/null
  echo "Granted Foundry User to the project identity on the account (allow a few minutes to propagate)."
fi

# 5. you: nothing to grant. Your sandbox account already holds Foundry Owner on this Foundry
#    account, which covers creating agents and running evaluations from this machine.
echo "You already hold Foundry Owner on $account_name; no self-grant needed."
echo "Next: ./scripts/1_deploy_infra.sh"
