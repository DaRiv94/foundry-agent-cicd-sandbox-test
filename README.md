# Prompt agent CI/CD in your sandbox, single resource group

This project promotes a Microsoft Foundry prompt agent from dev to test to prod inside the ONE Foundry project you already have in your Azure AI Agent Accelerator sandbox. The agent is a Frankies Bakery customer service agent: one model deployment plus `agent/instructions.md`, no tools.

The three environments are three agents in the same project, told apart by a name suffix. Every promotion creates a new immutable version of the agent for that environment from the same instructions file. Prod is pinned to the version that passed the gate.

```
rg-ais-ncus-<alias>-sandbox                  your resource group (exists, you cannot create one)
  msf-ais-ncus-<alias>-sandbox-<xxxx>        your Foundry account (exists, keyless, Entra only)
    chat-model                               gpt-5.4-nano deployment this project adds, same name in every environment
    prj-ais-ncus-<alias>-sandbox             your Foundry project (exists)
      bakery-support-dev                     versions 1, 2, 3 ...   endpoint serves the latest version
      bakery-support-test                    versions 1, 2, 3 ...   the evaluation gate runs here
      bakery-support-prod                    versions 1, 2, 3 ...   endpoint PINNED to the promoted version
  id-ais-ncus-<alias>-cicd                   managed identity the pipeline signs in as (Foundry User on this group)
```

Zero secrets. GitHub Actions signs in to Azure with OpenID Connect as the managed identity. The Foundry account has local auth disabled, so there is no key to leak.

## How this differs from the lesson video

The video builds one Foundry account per environment and gives the pipeline Foundry Owner. Your sandbox allows one Foundry account and you cannot grant Foundry Owner, so this edition changes four things and nothing else:

| In the video | In your sandbox | Why |
|---|---|---|
| Three Foundry accounts and projects, one per environment | One account, one project, three agents named `-dev`, `-test`, `-prod` | The sandbox allows one account and one project per student |
| The pipeline deploys the Bicep on every run | You deploy the Bicep once by hand. It adds only the `chat-model` deployment | The pipeline identity holds Foundry User, which cannot create model deployments |
| Pipeline identity holds Foundry Owner | Pipeline identity holds Foundry User | Foundry Owner is not a role you can grant. Every step the pipeline runs is a data-plane call, and Foundry User covers all of them |
| Evaluation judged by a model | Evaluation is a substring check per row, no judge model | Simpler, free, and the gate still blocks prod |

Everything else is the video: GitHub Environments, the federated credential, immutable versions, the gate in test, the required reviewer on prod, the pin, and rollback by re-pin.

## How promotion works

| Stage | Trigger | What runs | Gate |
|---|---|---|---|
| dev | push to any branch except `main` | create a new agent version, smoke test | none |
| test | push to `main` (job 2 of the Release run) | new version, smoke test, evaluation gate | 6-row evaluation, 80 percent must pass |
| prod | push to `main` (job 3 of the Release run) | wait for the reviewer, new version, pin the endpoint, smoke test the pin | a person approves |

The Release run moves the same commit through dev, test, and prod. The prod job waits because the `prod` GitHub Environment has a required reviewer. The evaluation gate blocks prod because the prod job declares `needs: test`.

## What you need

Your sandbox

- Your sandbox resource group with its Foundry account and project. Nothing else. Script 0 finds them.
- Quota: 10K tokens per minute of `gpt-5.4-nano`. Your sandbox has it.

Local machine (all from the program's tools list)

- Git
- Python 3.12
- PowerShell 7 or Bash. Every script has both.
- Azure CLI 2.76 or later with Bicep (`az bicep install`).
- GitHub CLI. Windows: `winget install GitHub.cli`. macOS: `brew install gh`. Then `gh auth login` and pick GitHub.com, HTTPS, and browser sign-in. It asks for the `repo` and `workflow` scopes by default.

GitHub

- A free personal GitHub account. Required reviewers on Environments are free on public repos, so the repo you create below is public. It contains nothing but a fictional bakery.

## Step 1: create your own repo from the template

This project is published as a GitHub template. A template gives you your own copy of the files in a repo you own, which is what the pipeline needs.

In the browser: open https://github.com/DaRiv94/foundry-agent-cicd-sandbox, click **Use this template**, then **Create a new repository**. Name it `foundry-agent-cicd-sandbox`, keep it **Public**, click **Create repository**. Then clone it.

Or from the terminal, one command does both:

```powershell
gh repo create foundry-agent-cicd-sandbox --public --template DaRiv94/foundry-agent-cicd-sandbox --clone
cd foundry-agent-cicd-sandbox
```

Your repo name is `<your GitHub user>/foundry-agent-cicd-sandbox`. You need it in the next step.

## Step 2: set up

Windows (PowerShell)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
az login --tenant "270d839f-5b11-4ff1-899a-ab7d2894386b" --scope "https://management.core.windows.net//.default" --claims-challenge "eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19"
```

Mac / Linux (Bash)

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
az login --tenant "270d839f-5b11-4ff1-899a-ab7d2894386b" --scope "https://management.core.windows.net//.default" --claims-challenge "eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19"
```

The `az login` line is the same sandbox sign-in from your tools list. Open `.env` and replace the two placeholders: your resource group (`rg-ais-ncus-<alias>-sandbox`) and your GitHub repo as `owner/name`. Leave the subscription id alone; every student is in that subscription. Every script refuses to run while a placeholder is still there.

## Step 3: run it locally first

Do the whole promotion by hand once. It is the same sequence the pipeline runs, so when the pipeline runs later you already know every step.

Windows (PowerShell)

```powershell
.\scripts\0_prepare.ps1
.\scripts\1_deploy_infra.ps1

# dev
python scripts\2_deploy_agent.py --env dev
python scripts\3_smoke_test.py --env dev

# test: the gate runs here
python scripts\2_deploy_agent.py --env test
python scripts\3_smoke_test.py --env test
python scripts\4_evaluate.py --env test --agent-version 1

# prod: pin, then prove the pin
python scripts\2_deploy_agent.py --env prod
python scripts\5_pin_version.py --env prod --agent-version 1
python scripts\3_smoke_test.py --env prod
```

Mac / Linux (Bash)

```bash
./scripts/0_prepare.sh
./scripts/1_deploy_infra.sh

# dev
python scripts/2_deploy_agent.py --env dev
python scripts/3_smoke_test.py --env dev

# test: the gate runs here
python scripts/2_deploy_agent.py --env test
python scripts/3_smoke_test.py --env test
python scripts/4_evaluate.py --env test --agent-version 1

# prod: pin, then prove the pin
python scripts/2_deploy_agent.py --env prod
python scripts/5_pin_version.py --env prod --agent-version 1
python scripts/3_smoke_test.py --env prod
```

What you see

- `0_prepare` prints your Foundry account, project and endpoint, writes the two names into `.env`, and checks that your project's identity holds Foundry User on the account (the evaluation gate needs it; most sandboxes have it from Week 2).
- `1_deploy_infra` adds the `chat-model` deployment to your account. Two to three minutes the first time, seconds after that.
- `2_deploy_agent` prints `bakery-support-dev version 1 created`. Run it again and you get version 2. Versions are never edited.
- `4_evaluate` polls for about two minutes, prints one line per question, then `Pass rate 6/6 = 100% (minimum 80%)` and `GATE PASSED`. It also prints a link to the report in the Foundry portal.
- `5_pin_version` prints which version the prod endpoint now serves.

Where to look in the Foundry portal: open your project, then Agents. You see three new agents. Open one and look at its versions and the `git_sha` and `env` metadata on each. On the prod agent, the endpoint settings show the pinned version instead of "always use latest".

## Step 4: wire up GitHub

Push nothing yet; your repo already holds the files from the template. Run the bootstrap script. It needs the `az login` from step 2 and `gh auth login`.

Windows (PowerShell)

```powershell
.\scripts\0b_pipeline_identity.ps1
```

Mac / Linux (Bash)

```bash
./scripts/0b_pipeline_identity.sh
```

It creates one managed identity in your resource group with three federated credentials, one per GitHub Environment. Each credential trusts only jobs that run inside that Environment, so the `prod` job is the only job that gets a token after a reviewer approves. The identity gets Foundry User on your resource group and nothing else. It also creates the three GitHub Environments (prod with you as the required reviewer) and the variables the workflows read.

Wait about ten minutes for the role assignment to propagate, then go to step 5. If the first run fails at the login step with "No subscriptions found", it was too early. Rerun it.

Federated credential subjects: GitHub issues an immutable subject for repos created after July 2026, `repo:OWNER@OWNER-ID/REPO@REPO-ID:environment:NAME`. The script reads both ids with `gh api` and builds that subject. If the first login fails with `AADSTS70021`, the error shows the subject GitHub sent. Compare it with `az identity federated-credential list`.

## Step 5: the promotion loop

This is the loop a developer runs every day.

1. Create a branch and edit `agent/instructions.md`. For example, change Saturday closing time from 8:30 PM to 5 PM.
2. Push the branch. The Dev workflow creates a new version of `bakery-support-dev` and smoke tests it. Open the run in the Actions tab and read the answer in the smoke test step.
3. Open a pull request and merge it.
4. The Release workflow starts on `main`: the dev job runs again on the merge commit, then the test job creates a test version and runs the evaluation gate, then the prod job waits.
5. Approve the prod job in the Actions tab (Review deployments, tick prod, Approve and deploy). It creates the prod version, pins the endpoint to it, and smoke tests the pinned endpoint. The smoke test output shows the new closing time.

Nothing reaches prod without a passing gate on the exact commit and a human approval.

## Step 6: break the gate

See the gate do its job once.

1. On a branch, delete rule 3 from `agent/instructions.md` (the "I will connect you with a team member" sentence) and change the Sunday hours to "9 AM to 2 PM Sunday".
2. Merge it. The test job's evaluation step fails two of six rows, prints `Pass rate 4/6 = 67%`, exits 1, and the prod job never starts. Prod keeps serving the pinned version.
3. Restore both edits and merge. The gate passes and prod gets the fixed version.

The gate tolerates one miss on purpose, so a single wrong row passes at 83 percent. Six rows is small. With a real evaluation set you raise the row count and the threshold together.

## Rollback

Prod serves one pinned version. To go back, pin the previous one.

```powershell
python scripts\5_pin_version.py --env prod --agent-version 1
```

A pin cannot be removed, only re-pointed. There is no way back to "always use latest" once an endpoint is pinned, which is fine: prod should never serve "whatever was created last".

## Cost

Agents and the model deployment cost nothing while idle. You pay for tokens when a smoke test or evaluation runs, and six evaluation rows on gpt-5.4-nano cost a fraction of a cent. The managed identity is free.

## Teardown

Windows (PowerShell)

```powershell
.\scripts\99_teardown.ps1
```

Mac / Linux (Bash)

```bash
./scripts/99_teardown.sh
```

The script lists what it will remove, asks you to type DELETE, then deletes the three agents and the pipeline identity with its role grant. It tries to delete the `chat-model` deployment too, but your Foundry account carries a lock that blocks that for you, so the deployment stays. It costs nothing while idle, and Frankie removes it when your sandbox is torn down. Your resource group, Foundry account and project stay. Never delete the resource group; it holds your whole sandbox. The GitHub repo and its Environments stay and cost nothing.

## Troubleshooting

- `AuthorizationFailed` in script 0 or 1: you are signed in as the wrong account, or `AZURE_RESOURCE_GROUP` is not your group. Rerun the `az login` line from step 2 and check `.env`.
- `RequestDisallowedByPolicy` in script 1: the sandbox denied the deployment. Keep the defaults in `infra/main.bicep` (gpt-5.4-nano, GlobalStandard, capacity 10).
- The pipeline fails at azure/login with "No subscriptions found": the role assignment has not propagated. Wait ten minutes and rerun the job.
- The pipeline fails at azure/login with `AADSTS70021`: the federated credential subject does not match. See step 4.
- `4_evaluate` reports `GATE FAILED: evaluation run failed`: the project identity may not hold Foundry User on the account yet. Script 0 grants it if missing; allow a few minutes and rerun.
- Two runs at once wait for each other. That is the concurrency group in `deploy-stage.yml`, on purpose.

## When to use this topology

Use one project for all three environments when one small team owns the agent and cheap, fast setup matters more than isolation. Everything shares one account, one quota, and one set of role assignments. A mistake in dev cannot break prod's agent versions, but it can spend prod's quota, and anyone with access to the project sees all three agents.

Do not use it when different teams need different access to dev and prod, when compliance needs separate audit trails per environment, or when prod needs its own capacity. The lesson video shows the same agent with one Foundry account per environment, which is where you go before the agent has real users.

## Adding capabilities

See `adding-capabilities.md` for what changes when you add web search, file search, RAG with Azure AI Search, an MCP server, or code execution. All of those tools work in the sandbox.
