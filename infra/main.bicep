// Sandbox edition. The Foundry account and project already exist in your sandbox and you are
// not allowed to create new ones, so this template references the account and adds ONE thing:
// the chat-model deployment that all three agents (dev, test, prod) use.
//
// You deploy this once, by hand (scripts/1_deploy_infra). The pipeline never runs it: the
// pipeline identity holds Foundry User, which has no right to create model deployments.
targetScope = 'resourceGroup'

@description('Name of the existing Foundry account in this resource group (written into .env by 0_prepare).')
param foundryAccountName string

// gpt-5.4-nano is on the sandbox allow-list and cheap. Capacity is in units of 1K tokens per
// minute; the sandbox caps any one deployment at 50.
param chatModelName string = 'gpt-5.4-nano'
param chatModelVersion string = '2026-03-17'
@minValue(1)
@maxValue(50)
param chatCapacity int = 10

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {
  name: foundryAccountName
}

// The deployment is always called chat-model so the agent definition never changes.
resource chatModel 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: account
  name: 'chat-model'
  sku: { name: 'GlobalStandard', capacity: chatCapacity }
  properties: {
    model: { format: 'OpenAI', name: chatModelName, version: chatModelVersion }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

output accountName string = account.name
output deploymentName string = chatModel.name
