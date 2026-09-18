# 0b_pipeline_identity.ps1 - one-time setup for the GitHub Actions pipeline.
#   1. one user-assigned managed identity in your sandbox resource group (id-ais-ncus-<alias>-cicd)
#   2. three federated credentials, one per GitHub Environment (dev, test, prod). No secrets.
#   3. Foundry User on the resource group. That is all the pipeline needs: every step it runs
#      (new agent version, smoke test, evaluation, pin) is a data-plane call on your project.
#      Sandbox edition: Foundry Owner is not a role you can grant, and the pipeline does not need it.
#   4. the three GitHub Environments and their variables (prod gets a required reviewer)
# Requires: az login, gh auth login (repo + workflow scope), and your GitHub repo already pushed.
# Usage:  .\scripts\0b_pipeline_identity.ps1            (reviewer = the signed-in gh user)
#         .\scripts\0b_pipeline_identity.ps1 -Reviewer someone
param([string]$Reviewer = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root ".env") | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; Set-Item -Path "Env:$($k.Trim())" -Value $v.Trim()
}
foreach ($k in @("AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "GITHUB_REPO", "FOUNDRY_ACCOUNT", "FOUNDRY_PROJECT")) {
    if (-not (Get-Item "Env:$k" -ErrorAction SilentlyContinue).Value -or (Get-Item "Env:$k").Value -like "*<*") {
        throw "Edit .env (and run 0_prepare) first: $k is still a placeholder or empty."
    }
}
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
$sub = $env:AZURE_SUBSCRIPTION_ID
$tenant = az account show --query tenantId -o tsv
$rg = $env:AZURE_RESOURCE_GROUP; $repo = $env:GITHUB_REPO
# rg-ais-ncus-<alias>-sandbox -> id-ais-ncus-<alias>-cicd
$alias = if ($rg -match '^rg-ais-[a-z0-9]+-(.+)-sandbox$') { $Matches[1] } else { "student" }
$identityName = "id-ais-ncus-$alias-cicd"

# GitHub identifiers. Repos created after 2026-07-15 present the immutable OIDC subject
#   repo:OWNER@OWNER-ID/REPO@REPO-ID:environment:<name>
# so the federated credential must carry the numeric ids, not just the names.
$owner, $name = $repo -split '/', 2
$ownerId = gh api "users/$owner" --jq '.id'
$repoId = gh api "repos/$repo" --jq '.id'
if (-not $Reviewer) { $Reviewer = gh api user --jq '.login' }
$reviewerId = gh api "users/$Reviewer" --jq '.id'
Write-Host "Repo $repo (owner id $ownerId, repo id $repoId). Prod reviewer: $Reviewer"

# 1. the identity (one for all three environments; the Environment name is the unit of approval, not of infrastructure)
$identity = az identity create --resource-group $rg --name $identityName --location $env:AZURE_LOCATION `
    --query "{clientId:clientId, principalId:principalId}" -o json | ConvertFrom-Json
Write-Host "Identity $identityName  client id $($identity.clientId)"

# 3. Foundry User on the group: data plane on the account and project, nothing else.
#    --only-show-errors hides the harmless "cannot query Graph" warning a guest account gets.
$foundryUserRoleId = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
az role assignment create --assignee-object-id $identity.principalId --assignee-principal-type ServicePrincipal `
    --role $foundryUserRoleId --scope "/subscriptions/$sub/resourceGroups/$rg" --query id -o tsv --only-show-errors | Out-Null
Write-Host "Foundry User on $rg"

foreach ($e in @("dev", "test", "prod")) {
    # 2. federated credential: GitHub jobs running in Environment <e> may sign in as this identity
    $subject = "repo:$owner@$ownerId/$name@${repoId}:environment:$e"
    az identity federated-credential create --name "github-$e" --identity-name $identityName --resource-group $rg `
        --issuer "https://token.actions.githubusercontent.com" --subject $subject --audiences "api://AzureADTokenExchange" `
        --query name -o tsv | Out-Null
    Write-Host "$e : federated credential -> $subject"

    # 4. GitHub Environment + variables. prevent_self_review is only accepted together with reviewers;
    #    it is false so a one-person team can approve its own prod run.
    $body = @{ wait_timer = 0; deployment_branch_policy = $null }
    if ($e -eq "prod") { $body.reviewers = @(@{ type = "User"; id = [int]$reviewerId }); $body.prevent_self_review = $false }
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value ($body | ConvertTo-Json -Depth 4 -Compress) -Encoding ascii
    gh api --method PUT "repos/$repo/environments/$e" --input $tmp --jq '.name' | Out-Null
    Remove-Item $tmp
    gh variable set AZURE_CLIENT_ID --env $e --body $identity.clientId --repo $repo
    gh variable set AZURE_TENANT_ID --env $e --body $tenant --repo $repo
    gh variable set AZURE_SUBSCRIPTION_ID --env $e --body $sub --repo $repo
    Write-Host "$e : GitHub Environment with 3 variables$(if ($e -eq 'prod') { " and required reviewer $Reviewer" })"
}
gh variable set AZURE_RESOURCE_GROUP --body $rg --repo $repo
gh variable set FOUNDRY_ACCOUNT --body $env:FOUNDRY_ACCOUNT --repo $repo
gh variable set FOUNDRY_PROJECT --body $env:FOUNDRY_PROJECT --repo $repo
gh variable set AGENT_NAME --body $env:AGENT_NAME --repo $repo
Write-Host "Repository variables AZURE_RESOURCE_GROUP, FOUNDRY_ACCOUNT, FOUNDRY_PROJECT, AGENT_NAME set."
Write-Host "Done. Role assignments can take up to 10 minutes to propagate before the first workflow run succeeds."
