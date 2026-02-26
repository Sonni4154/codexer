#!/usr/bin/env python3
import json
import logging
import os
import time
from pathlib import Path
from typing import Dict, Optional

import requests

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("n8n-sync")


class N8nSync:
    def __init__(self):
        self.n8n_host = os.environ.get("N8N_HOST", "n8n")
        self.n8n_port = os.environ.get("N8N_PORT", "5678")
        self.api_key = os.environ.get("N8N_API_KEY", "").strip()
        self.workflows_path = Path(os.environ.get("WORKFLOWS_PATH", "/workflows"))
        self.sync_interval = int(os.environ.get("SYNC_INTERVAL", "300"))
        self.timeout = int(os.environ.get("N8N_TIMEOUT", "20"))
        self.base_url = f"http://{self.n8n_host}:{self.n8n_port}/api/v1"

    def _headers(self) -> Dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["X-N8N-API-KEY"] = self.api_key
        return headers

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        url = f"{self.base_url}{endpoint}"
        kwargs.setdefault("headers", self._headers())
        kwargs.setdefault("timeout", self.timeout)
        response = requests.request(method, url, **kwargs)
        response.raise_for_status()
        return response

    def _extract_workflow(self, payload: Dict) -> Optional[Dict]:
        if "name" in payload and "nodes" in payload:
            return payload
        if isinstance(payload.get("workflow"), dict):
            return payload["workflow"]
        logger.warning("Skipping invalid workflow payload: missing required keys")
        return None

    def _find_remote_workflow_by_name(self, name: str) -> Optional[Dict]:
        response = self._request("GET", "/workflows", params={"limit": 250})
        data = response.json().get("data", [])
        for workflow in data:
            if workflow.get("name") == name:
                return workflow
        return None

    def _upsert_workflow(self, workflow: Dict) -> str:
        existing = self._find_remote_workflow_by_name(workflow["name"])
        payload = {
            "name": workflow["name"],
            "nodes": workflow.get("nodes", []),
            "connections": workflow.get("connections", {}),
            "settings": workflow.get("settings", {}),
            "active": workflow.get("active", False),
            "tags": workflow.get("tags", []),
            "staticData": workflow.get("staticData", {}),
            "pinData": workflow.get("pinData", {}),
        }

        if existing and existing.get("id"):
            self._request("PATCH", f"/workflows/{existing['id']}", data=json.dumps(payload))
            return f"updated:{workflow['name']}"

        self._request("POST", "/workflows", data=json.dumps(payload))
        return f"created:{workflow['name']}"

    def sync_all(self):
        if not self.workflows_path.exists():
            logger.warning("Workflows path does not exist: %s", self.workflows_path)
            return

        synced = 0
        for workflow_file in sorted(self.workflows_path.glob("*.json")):
            try:
                payload = json.loads(workflow_file.read_text(encoding="utf-8"))
                workflow = self._extract_workflow(payload)
                if not workflow:
                    continue
                result = self._upsert_workflow(workflow)
                logger.info("%s from %s", result, workflow_file.name)
                synced += 1
            except requests.RequestException as exc:
                logger.error("Request failure syncing %s: %s", workflow_file.name, exc)
            except json.JSONDecodeError as exc:
                logger.error("Invalid JSON in %s: %s", workflow_file.name, exc)
            except Exception as exc:
                logger.error("Unexpected error syncing %s: %s", workflow_file.name, exc)

        logger.info("Sync pass complete: %d workflows processed", synced)



def main():
    sync = N8nSync()
    while True:
        sync.sync_all()
        time.sleep(sync.sync_interval)


if __name__ == "__main__":
    main()
