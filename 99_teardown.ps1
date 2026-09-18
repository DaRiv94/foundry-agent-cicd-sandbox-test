# 99_teardown.ps1 - remove everything this project added to your sandbox, and nothing else:
#   the three agents, the chat-model deployment, the pipeline identity and its role grant.
# Your resource group, Foundry account, project and other work stay. The GitHub repo and its
# Environments are left alone (they cost nothing).
#
# Sandbox edition: never deletes the resource group (you are not allowed to, and it holds your
# whole sandbox).
# Usage:  .\scripts\99_teardown.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root ".env") | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}
foreach ($k in @("AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "FOUNDRY_ACCOUNT", "FOUNDRY_PROJECT")) {
    if (-not (Get-Item "Env:$k" -ErrorAction SilentlyContinue).Value -or (Get-Item "Env:$k").Value -like "*<*") {
        throw "Nothing to tear down: $k is not set in .env (0_prepare never ran)."
    }
}
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
$sub = $env:AZURE_SUBSCRIPTION_ID
$rg = $env:AZURE_RESOURCE_GROUP
$alias = if ($rg -match '^rg-ais-[a-z0-9]+-(.+)-sandbox$') { $Matches[1] } else { "student" }
$identityName = "id-ais-ncus-$alias-cicd"

Write-Host "This will delete, inside $rg :"
Write-Host "  - agents $($env:AGENT_NAME)-dev, -test, -prod (all versions)"
Write-Host "  - model deployment chat-model on $($env:FOUNDRY_ACCOUNT)"
Write-Host "  - managed identity $identityName and its Foundry User grant on the group"
Write-Host "It does NOT delete the resource group, the Foundry account or the project."
if ((Read-Host "Type DELETE to continue") -ne "DELETE") { Write-Host "Aborted."; exit 0 }

# 1. agents
$python = if (Test-Path (Join-Path $root ".venv\Scripts\python.exe")) { Join-Path $root ".venv\Scripts\python.exe" } else { "python" }
& $python (Join-Path $PSScriptRoot "98_delete_agents.py")

# 2. the model deployment. In the sandbox the Foundry account carries a CanNotDelete lock that
#    also blocks deleting its model deployments, so this step is best-effort: the deployment
#    stays, costs nothing while idle, and the sandbox admin removes it at teardown.
$dep = az cognitiveservices account deployment show --name $env:FOUNDRY_ACCOUNT --resource-group $rg --deployment-name chat-model --query name -o tsv 2>$null
if ($dep) {
    $out = az cognitiveservices account deployment delete --name $env:FOUNDRY_ACCOUNT --resource-group $rg --deployment-name chat-model 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Host "chat-model deployment deleted" }
    elseif ($out -match 'ScopeLocked') { Write-Host "[SKIP] chat-model stays: the Foundry account is locked, so deployments cannot be deleted by you. It costs nothing while idle; Frankie removes it." }
    else { Write-Host "[WARN] chat-model could not be deleted: $out" }
} else { Write-Host "chat-model deployment already gone" }

# 3. the pipeline identity: its role grant on the group first (a grant at group scope is yours
#    to delete), then the identity itself (its federated credentials go with it).
$principalId = az identity show --resource-group $rg --name $identityName --query principalId -o tsv 2>$null
if ($principalId) {
    az role assignment delete --assignee-object-id $principalId --scope "/subscriptions/$sub/resourceGroups/$rg" --only-show-errors 2>$null
    az identity delete --resource-group $rg --name $identityName
    Write-Host "$identityName and its role grant deleted"
} else { Write-Host "$identityName already gone" }

Write-Host "Teardown complete. Your resource group, Foundry account and project are untouched."
Write-Host "Your GitHub repo, its Environments and variables stay; delete the repo yourself if you want it gone."
