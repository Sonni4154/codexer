import requests

def run(prompt: str, context: dict):
    """
    Sends user prompt and context to n8n webhook and returns workflow output
    """
    n8n_url = "http://n8n:5678/webhook/webui-trigger"  # internal Docker network
    payload = {"prompt": prompt, "context": context}

    try:
        response = requests.post(n8n_url, json=payload, timeout=15)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        return {"error": str(e)}
