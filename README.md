# n8n-AI Stack

Containerized agent-orchestration stack with n8n, Ollama, Open WebUI, Qdrant, PostgreSQL, Redis, and helper indexing services.

## Quick start

1. Copy env template and set secure values:
   ```bash
   cp .env.example .env
   ```
2. Ensure required Docker networks exist:
   ```bash
   docker network create backend_network || true
   docker network create database_network || true
   docker network create ai_network || true
   ```
3. Start services:
   ```bash
   docker compose up -d --build
   ```

## Service URLs

- n8n: http://localhost:5678
- Open WebUI: http://localhost:8080
- pgAdmin: http://localhost:8888
- Qdrant: http://localhost:6333

## Deployment notes

- `cloudflared` now reads `CLOUDFLARED_TOKEN` from `.env` (no hardcoded tunnel token).
- `n8n_sync` performs real upsert sync from `n8n_workflows/*.json` into the n8n API.
- Parser/indexer/chunker services now respect `CODE_PATHS` (and `WATCH_PATHS`) and connect to the configured Ollama host.
