
import requests

def generate_n8n_workflow(prompt: str):
    """
    Generates n8n workflow JSON from a natural language description using Ollama
    """
    # 1. Call Ollama
    ollama_resp = requests.post(
        "http://ollama:11434/ollama-api-endpoint",
        json={"prompt": f"Generate n8n workflow JSON for: {prompt}"},
    ).json()

    workflow_json = ollama_resp.get("output")

    # 2. Post to n8n API to create workflow
    n8n_api_url = "http://n8n:5678/rest/workflows"
    headers = {"Authorization": "Bearer YOUR_N8N_API_KEY"}
    r = requests.post(n8n_api_url, json=workflow_json, headers=headers)
    return r.json()
