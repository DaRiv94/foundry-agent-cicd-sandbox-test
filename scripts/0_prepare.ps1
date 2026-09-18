# 0_prepare.ps1 - find the Foundry account and project in your sandbox resource group and
# check the one role the evaluation gate needs. Creates nothing except a missing role grant.
#
# Sandbox edition: your resource group, Foundry account and project already exist and you
# are not allowed to create new ones, so this script discovers them and writes their names
# into .env for every later script to use.
# Usage:  .\scripts\0_prepare.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) { throw "Copy .env.example to .env first." }
Get-Content $envFile | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}
foreach ($k in @("AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP")) {
    if (-not (Get-Item "Env:$k").Value -or (Get-Item "Env:$k").Value -like "*<*") { throw "Edit .env first: $k is still a placeholder." }
}
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
$sub = $env:AZURE_SUBSCRIPTION_ID
$rg = $env:AZURE_RESOURCE_GROUP

# 1. the resource group must already exist (a sandbox student cannot create one)
$rgState = az group show --name $rg --query "properties.provisioningState" -o tsv 2>$null
if (-not $rgState) { throw "Resource group $rg was not found. Use your own sandbox group, rg-ais-ncus-<alias>-sandbox." }
Write-Host "Resource group  : $rg"

# 2. discover the one Foundry account and its one project
$accounts = az cognitiveservices account list --resource-group $rg --query "[?kind=='AIServices'].{name:name, id:id}" -o json | ConvertFrom-Json
if (-not $accounts -or @($accounts).Count -eq 0) { throw "No Microsoft Foundry account found in $rg. Make a post." }
$account = @($accounts)[0]
$projects = az rest --method get --url "https://management.azure.com$($account.id)/projects?api-version=2025-12-01" --query "value" -o json | ConvertFrom-Json
if (-not $projects -or @($projects).Count -eq 0) { throw "No Foundry project found in $($account.name). Make a post." }
$project = @($projects)[0]
$projectName = $project.name.Split('/')[-1]
$projectPrincipalId = $project.identity.principalId
$endpoint = "https://$($account.name).services.ai.azure.com/api/projects/$projectName"
Write-Host "Foundry account : $($account.name)"
Write-Host "Foundry project : $projectName"
Write-Host "Project endpoint: $endpoint"

# 3. write the names back into .env (replace the line if present, append if not)
$lines = Get-Content $envFile
foreach ($pair in @(@("FOUNDRY_ACCOUNT", $account.name), @("FOUNDRY_PROJECT", $projectName))) {
    $key, $value = $pair
    if ($lines -match "^$key=") { $lines = $lines | ForEach-Object { if ($_ -match "^$key=") { "$key=$value" } else { $_ } } }
    else { $lines += "$key=$value" }
}
Set-Content -Path $envFile -Value $lines -Encoding utf8
Write-Host "Wrote FOUNDRY_ACCOUNT and FOUNDRY_PROJECT into .env"

# 4. the evaluation gate runs inside Foundry as the PROJECT's identity, which needs Foundry User
#    on the account. Most sandboxes already have this from Week 2; grant it only if missing.
$foundryUserRoleId = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
$existing = az role assignment list --assignee-object-id $projectPrincipalId --scope $account.id --role $foundryUserRoleId --query "length(@)" -o tsv --only-show-errors
if ([int]$existing -gt 0) {
    Write-Host "Project identity already holds Foundry User on the account."
} else {
    az role assignment create --assignee-object-id $projectPrincipalId --assignee-principal-type ServicePrincipal `
        --role $foundryUserRoleId --scope $account.id --query id -o tsv --only-show-errors | Out-Null
    Write-Host "Granted Foundry User to the project identity on the account (allow a few minutes to propagate)."
}

# 5. you: nothing to grant. Your sandbox account already holds Foundry Owner on this Foundry
#    account, which covers creating agents and running evaluations from this machine.
Write-Host "You already hold Foundry Owner on $($account.name); no self-grant needed."
Write-Host "Next: .\scripts\1_deploy_infra.ps1"
