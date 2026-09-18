# 1_deploy_infra.ps1 - deploy infra/main.bicep into your sandbox resource group. It adds the
# chat-model deployment to your existing Foundry account. Idempotent: rerunning changes nothing
# that already matches.
#
# Sandbox edition: run this once, by you. The pipeline never runs it, because the pipeline
# identity holds Foundry User, which cannot create model deployments.
# Usage:  .\scripts\1_deploy_infra.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root ".env") | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}
foreach ($k in @("AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "FOUNDRY_ACCOUNT", "FOUNDRY_PROJECT")) {
    if (-not (Get-Item "Env:$k" -ErrorAction SilentlyContinue).Value -or (Get-Item "Env:$k").Value -like "*<*") {
        throw "Run .\scripts\0_prepare.ps1 first: $k is not set in .env."
    }
}
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
$rg = $env:AZURE_RESOURCE_GROUP
$stamp = Get-Date -Format "yyyyMMddHHmmss"

Write-Host "Deploying infra/main.bicep into $rg (chat-model on $($env:FOUNDRY_ACCOUNT)) ..."
$outputs = az deployment group create --resource-group $rg --name "infra-$stamp" `
    --template-file (Join-Path $root "infra\main.bicep") --parameters foundryAccountName=$env:FOUNDRY_ACCOUNT `
    --query "properties.outputs" -o json | ConvertFrom-Json
if (-not $outputs) { throw "Deployment failed." }
Write-Host "Model deployment : $($outputs.deploymentName.value) on $($outputs.accountName.value)"
Write-Host "Project endpoint : https://$($env:FOUNDRY_ACCOUNT).services.ai.azure.com/api/projects/$($env:FOUNDRY_PROJECT)"
Write-Host "Next: python scripts\2_deploy_agent.py --env dev"
