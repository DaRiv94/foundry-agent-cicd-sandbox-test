#!/usr/bin/env bash
# 99_teardown.sh - remove everything this project added to your sandbox, and nothing else:
#   the three agents, the chat-model deployment, the pipeline identity and its role grant.
# Your resource group, Foundry account, project and other work stay. The GitHub repo and its
# Environments are left alone (they cost nothing).
#
# Sandbox edition: never deletes the resource group (you are not allowed to, and it holds your
# whole sandbox).
# Usage:  ./scripts/99_teardown.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"; [[ -z "$line" || "$line" == \#* ]] && continue; export "${line%%=*}=${line#*=}"
done < "$ROOT/.env"
for k in AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP FOUNDRY_ACCOUNT FOUNDRY_PROJECT; do
  [[ -n "${!k:-}" && "${!k}" != *"<"* ]] || { echo "Nothing to tear down: $k is not set in .env (0_prepare never ran)."; exit 1; }
done
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
sub="$AZURE_SUBSCRIPTION_ID"
rg="$AZURE_RESOURCE_GROUP"
if [[ "$rg" =~ ^rg-ais-[a-z0-9]+-(.+)-sandbox$ ]]; then alias="${BASH_REMATCH[1]}"; else alias="student"; fi
identity_name="id-ais-ncus-$alias-cicd"

echo "This will delete, inside $rg :"
echo "  - agents ${AGENT_NAME}-dev, -test, -prod (all versions)"
echo "  - model deployment chat-model on $FOUNDRY_ACCOUNT"
echo "  - managed identity $identity_name and its Foundry User grant on the group"
echo "It does NOT delete the resource group, the Foundry account or the project."
read -r -p "Type DELETE to continue: " answer
[[ "$answer" == "DELETE" ]] || { echo "Aborted."; exit 0; }

# 1. agents
if [[ -x "$ROOT/.venv/bin/python" ]]; then py="$ROOT/.venv/bin/python"; else py="python"; fi
"$py" "$ROOT/scripts/98_delete_agents.py"

# 2. the model deployment
if az cognitiveservices account deployment show --name "$FOUNDRY_ACCOUNT" --resource-group "$rg" --deployment-name chat-model --query name -o tsv > /dev/null 2>&1; then
  az cognitiveservices account deployment delete --name "$FOUNDRY_ACCOUNT" --resource-group "$rg" --deployment-name chat-model
  echo "chat-model deployment deleted"
else
  echo "chat-model deployment already gone"
fi

# 3. the pipeline identity: its role grant on the group first (a grant at group scope is yours
#    to delete), then the identity itself (its federated credentials go with it).
principal_id="$(az identity show --resource-group "$rg" --name "$identity_name" --query principalId -o tsv 2>/dev/null || true)"
if [[ -n "$principal_id" ]]; then
  MSYS_NO_PATHCONV=1 az role assignment delete --assignee-object-id "$principal_id" --scope "/subscriptions/$sub/resourceGroups/$rg" --only-show-errors 2>/dev/null || true
  az identity delete --resource-group "$rg" --name "$identity_name"
  echo "$identity_name and its role grant deleted"
else
  echo "$identity_name already gone"
fi

echo "Teardown complete. Your resource group, Foundry account and project are untouched."
echo "Your GitHub repo, its Environments and variables stay; delete the repo yourself if you want it gone."
