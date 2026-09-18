"""98_delete_agents.py - delete the three agents (every version) this project created.

Sandbox edition: the resource group, Foundry account and project are yours to keep, so
teardown removes only what this project added. 99_teardown runs this first, then removes the
model deployment and the pipeline identity. Safe to run more than once.

Usage:  python scripts/98_delete_agents.py
"""
import os
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")
endpoint = f"https://{os.environ['FOUNDRY_ACCOUNT']}.services.ai.azure.com/api/projects/{os.environ['FOUNDRY_PROJECT']}"
project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())


def delete_agent(agent_name: str) -> str:
    """Delete every version of one agent, tolerating an agent that is already gone."""
    agents = project.agents
    try:
        versions = [v.version for v in agents.list_versions(agent_name=agent_name)]
    except Exception:
        return "not found"
    for version in versions:
        try:
            agents.delete_version(agent_name=agent_name, agent_version=version)
        except Exception:
            pass
    try:
        agents.delete(agent_name=agent_name)
    except Exception:
        pass
    return f"{len(versions)} version(s) removed"


for env_name in ("dev", "test", "prod"):
    name = f"{os.environ['AGENT_NAME']}-{env_name}"
    print(f"{name}: {delete_agent(name)}")
print("Done")
