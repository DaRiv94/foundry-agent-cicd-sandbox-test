"""3_smoke_test.py - ask the agent's endpoint one question and fail only on an empty answer.

This calls the agent endpoint, the same URL applications call, so it honours the pin.
In prod it runs after 5_pin_version.py to prove customers get the promoted version.

Usage:  python scripts/3_smoke_test.py --env dev
"""
import argparse
import os
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")
parser = argparse.ArgumentParser()
parser.add_argument("--env", required=True, choices=["dev", "test", "prod"])
args = parser.parse_args()

# Sandbox edition: the account and project already exist; 0_prepare wrote their names into .env
# (the pipeline reads the same two names from GitHub repository variables).
endpoint = f"https://{os.environ['FOUNDRY_ACCOUNT']}.services.ai.azure.com/api/projects/{os.environ['FOUNDRY_PROJECT']}"
agent = f"{os.environ['AGENT_NAME']}-{args.env}"
project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential(), allow_preview=True)

question = "What time do you open on Saturday?"
openai = project.get_openai_client(agent_name=agent)  # bound to the agent endpoint
answer = (openai.responses.create(input=question).output_text or "").strip()
print(f"Agent: {agent}\nQ: {question}\nA: {answer}")
if not answer:
    sys.exit("SMOKE TEST FAILED: empty answer")
print("SMOKE TEST PASSED")
