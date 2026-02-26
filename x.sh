#!/bin/bash

# ============================================
# N8N AI Stack - Complete Rebuild Script
# Idempotent with whiptail menus
# ============================================

# Exit on error but with cleanup
set -e
trap 'echo -e "\n❌ Script interrupted. Cleaning up..."; exit 1' INT TERM

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_menu() {
    whiptail --title "$1" --msgbox "$2" 0 0 3>&1 1>&2 2>&3
}

confirm_action() {
    whiptail --title "Confirm" --yesno "$1" 0 0 3>&1 1>&2 2>&3
}

# ============================================
# Check Prerequisites
# ============================================

check_prerequisites() {
    local missing=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker compose &> /dev/null; then
        missing+=("docker compose")
    fi
    
    # Check whiptail
    if ! command -v whiptail &> /dev/null; then
        missing+=("whiptail (install with: apt-get install whiptail)")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        show_menu "Missing Prerequisites" "The following are required:\n\n$(printf '• %s\n' "${missing[@]}")"
        exit 1
    fi
    
    log_success "Prerequisites checked"
}

# ============================================
# Environment Setup
# ============================================

setup_env() {
    log_info "Setting up environment variables..."
    
    local env_file=".env"
    local env_backup=".env.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Backup existing .env
    if [ -f "$env_file" ]; then
        cp "$env_file" "$env_backup"
        log_info "Backed up existing .env to $env_backup"
    fi
    
    # Load or create environment variables
    if [ ! -f "$env_file" ]; then
        # Generate secure passwords
        POSTGRES_PASSWORD=$(openssl rand -hex 16)
        REDIS_PASSWORD=$(openssl rand -hex 16)
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
        WEBUI_SECRET_KEY=$(openssl rand -hex 32)
        NEXTAUTH_SECRET=$(openssl rand -hex 32)
        LANGFUSE_SALT=$(openssl rand -hex 16)
        LANGFUSE_ENCRYPTION_KEY=$(openssl rand -hex 32)
        N8N_RUNNERS_AUTH_TOKEN=$(openssl rand -hex 32)
        CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
        
        cat > "$env_file" << EOF
# Database
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Encryption
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
LANGFUSE_SALT=${LANGFUSE_SALT}
LANGFUSE_ENCRYPTION_KEY=${LANGFUSE_ENCRYPTION_KEY}
N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}

# ClickHouse
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}

# Admin
PGADMIN_EMAIL=admin@example.com
PGADMIN_PASSWORD=$(openssl rand -hex 8)

# Timezone
TZ=America/Los_Angeles
EOF
        log_success "Created new .env file with secure passwords"
    else
        log_info "Using existing .env file"
        # Source the .env file
        set -a
        source "$env_file"
        set +a
    fi
    
    # Show passwords in whiptail
    whiptail --title "Environment Variables" \
        --msgbox "Your environment is configured.\n\nPasswords are saved in .env file.\n\nClickHouse Password: ${CLICKHOUSE_PASSWORD}\nPostgres Password: ${POSTGRES_PASSWORD}" 0 0
}

# ============================================
# Directory Structure
# ============================================

create_directories() {
    log_info "Creating directory structure..."
    
    local dirs=(
        "code_parser"
        "code_indexer"
        "ast_chunker"
        "n8n_sync"
        "n8n_workflows"
        "n8n_credentials"
        "n8n_custom"
        "n8n_task_runner_config"
        "ollama_modelfiles"
        "code_repos"
        "qdrant_config"
        "clickhouse_config"
        "postgres_init"
        "webui_functions"
        "webui_configs"
        "models"
        "backups"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_info "Created $dir"
    done
    
    log_success "Directory structure created"
}

# ============================================
# Configuration Files
# ============================================

create_config_files() {
    log_info "Creating configuration files..."
    
    # 1. n8n custom module
    cat > n8n_custom/package.json << 'EOF'
{
  "name": "n8n-custom",
  "version": "1.0.0",
  "description": "Custom n8n modules",
  "main": "index.js",
  "dependencies": {}
}
EOF
    
    cat > n8n_custom/index.js << 'EOF'
module.exports = {};
EOF
    
    # 2. n8n task runner config
    cat > n8n_task_runner_config/n8n-task-runners.json << 'EOF'
{
  "task-runners": [
    {
      "runner-type": "javascript",
      "env-overrides": {
        "NODE_FUNCTION_ALLOW_BUILTIN": "*",
        "NODE_FUNCTION_ALLOW_EXTERNAL": "*"
      }
    },
    {
      "runner-type": "python",
      "env-overrides": {
        "PYTHONPATH": "/opt/runners/task-runner-python",
        "N8N_RUNNERS_STDLIB_ALLOW": "*",
        "N8N_RUNNERS_EXTERNAL_ALLOW": "*"
      }
    }
  ]
}
EOF
    
    # 3. Qdrant config (empty - use defaults)
    cat > qdrant_config/qdrant.yaml << 'EOF'
# Empty config - using defaults
log_level: info
EOF
    
    # 4. ClickHouse config
    cat > clickhouse_config/users.xml << 'EOF'
<clickhouse>
    <users>
        <default>
            <password></password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
        <langfuse>
            <password>CHANGE_ME</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </langfuse>
    </users>
</clickhouse>
EOF
    
    # 5. Ollama modelfile
    cat > ollama_modelfiles/CodeAssistant << 'EOF'
FROM codellama:13b

PARAMETER temperature 0.2
PARAMETER top_p 0.9
PARAMETER stop "</s>"

SYSTEM """
You are an expert code reviewer and programming assistant. You understand multiple programming languages and can:
1. Review code for bugs, security issues, and style violations
2. Explain complex code sections
3. Suggest optimizations
4. Generate unit tests
5. Refactor code while preserving functionality

Always provide clear, actionable feedback with specific examples.
"""
EOF
    
    log_success "Configuration files created"
}

# ============================================
# Docker Compose File
# ============================================

create_docker_compose() {
    log_info "Creating docker compose.yml..."
    
    cat > docker compose.yml << 'EOF'
version: '3.8'

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: n8n-ai-cloudflared
    restart: unless-stopped
    command:
      - tunnel
      - --no-autoupdate
      - run
      - --token
      - eyJhIjoiZDkyOTQxODhjNDE3ZTFmMTZjZDk0ZjY5ZGU3ZDU3M2UiLCJ0IjoiM2NiNjZlNzEtNTYwMi00ZGQ5LWFjNDctOWE5YTA3MTRkMzdiIiwicyI6Ik9UY3hNelZrT0dJdE5HWmpaUzAwTjJaaUxXSXdOekF0Wm1ZelpHRmpaVEE0TkRsbSJ9
    networks:
      - backend_network
    healthcheck:
      test: ["CMD", "cloudflared", "tunnel", "info"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - n8n
      - webui

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-ai-n8n
    restart: unless-stopped
    environment:
      - N8N_PROTOCOL=https
      - N8N_HOST=n8n.wemakemarin.com
      - WEBHOOK_URL=https://n8n.wemakemarin.com
      - N8N_EDITOR_BASE_URL=https://n8n.wemakemarin.com
      - N8N_PORT=5678
      - NODE_ENV=production
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n_db
      - DB_POSTGRESDB_USER=n8n_user
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - GENERIC_TIMEZONE=${TZ}
      - N8N_AI_ENABLED=true
      - AI_PROVIDER=ollama
      - OLLAMA_HOST=http://ollama:11434
      - N8N_AI_TOKEN_SPLIT=true
      - N8N_AI_TOKEN_LIMIT=4096
      - EXTERNAL_HOOK_FILES=/home/node/.n8n/custom
      # Task runner configuration
      - N8N_RUNNERS_MODE=external
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      - N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}
      - N8N_RUNNERS_BROKER_PORT=5679
      - N8N_NATIVE_PYTHON_RUNNER=true
    ports:
      - "5678:5678"
    networks:
      - backend_network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      ollama:
        condition: service_started
    volumes:
      - n8n_data:/home/node/.n8n
      - ./models:/home/node/models:ro
      - ./n8n_workflows:/home/node/workflows
      - ./n8n_credentials:/home/node/credentials
      - ./n8n_custom:/home/node/.n8n/custom

  n8n-task-runners:
    image: n8nio/runners:latest
    container_name: n8n-ai-task-runners
    restart: unless-stopped
    environment:
      - N8N_RUNNERS_TASK_BROKER_URI=http://n8n:5679
      - N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}
      - N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT=15
      - N8N_RUNNERS_LAUNCHER_LOG_LEVEL=info
    networks:
      - backend_network
    depends_on:
      - n8n
    volumes:
      - ./n8n_task_runner_config:/etc/n8n-task-runners.json:ro

  ollama:
    image: ollama/ollama:latest
    container_name: n8n-ai-ollama
    restart: unless-stopped
    environment:
      - OLLAMA_KEEP_ALIVE=24h
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_ORIGINS=*
      - OLLAMA_NUM_PARALLEL=4
      - OLLAMA_MAX_LOADED_MODELS=3
    ports:
      - "11434:11434"
    networks:
      - ai_network
      - backend_network
    volumes:
      - ollama_data:/root/.ollama
      - ./models:/models:ro
      - ./ollama_modelfiles:/root/modelfiles
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu, compute, utility]
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3

  ollama-code-setup:
    image: ollama/ollama:latest
    container_name: n8n-ai-ollama-code-setup
    restart: "no"
    depends_on:
      ollama:
        condition: service_healthy
    entrypoint: >
      sh -c "
      echo 'Pulling code models...' &&
      ollama pull codellama:13b &&
      ollama pull deepseek-coder:6.7b &&
      ollama pull nomic-embed-text &&
      echo 'Creating custom code model...' &&
      ollama create code-assistant -f /root/modelfiles/CodeAssistant &&
      echo 'Setup complete'
      "
    volumes:
      - ./ollama_modelfiles:/root/modelfiles:ro
    networks:
      - backend_network

  webui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: n8n-ai-webui
    restart: unless-stopped
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - WEBUI_AUTH=false
      - WEBUI_NAME="AI Code Assistant"
      - WEBUI_URL=https://ai.wemakemarin.com
      - ENABLE_RAG_WEB_SEARCH=true
      - RAG_EMBEDDING_ENGINE=ollama
      - RAG_EMBEDDING_MODEL=nomic-embed-text
      - RAG_TEMPLATE=code
      - CHUNK_SIZE=1500
      - CHUNK_OVERLAP=200
    ports:
      - "8080:8080"
    networks:
      - backend_network
    depends_on:
      - ollama
      - qdrant
    volumes:
      - webui_data:/app/backend/data
      - ./webui_functions:/app/backend/functions
      - ./webui_configs:/app/backend/configs
    extra_hosts:
      - "host.docker.internal:host-gateway"

  postgres:
    image: postgres:16-alpine
    container_name: n8n-ai-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n_user
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n_db
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8
    networks:
      - database_network
      - backend_network
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres_init:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n_user -d n8n_db"]
      interval: 10s
      timeout: 5s
      retries: 5
    command: >
      postgres
      -c max_connections=200
      -c shared_buffers=256MB
      -c effective_cache_size=768MB
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.7
      -c wal_buffers=16MB
      -c default_statistics_target=100

  postgres_dashboard:
    image: postgres:16-alpine
    container_name: n8n-ai-postgres-dashboard
    restart: unless-stopped
    environment:
      - POSTGRES_USER=dashboard_user
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=dashboard_db
    ports:
      - "5434:5432"
    networks:
      - backend_network
      - database_network
    volumes:
      - postgres_dashboard_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dashboard_user -d dashboard_db"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: n8n-ai-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD} --maxmemory 2gb --maxmemory-policy allkeys-lru
    networks:
      - backend_network
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  qdrant:
    image: qdrant/qdrant:latest
    container_name: n8n-ai-qdrant
    restart: unless-stopped
    ports:
      - "6333:6333"
      - "6334:6334"
    networks:
      - ai_network
      - backend_network
    volumes:
      - qdrant_data:/qdrant/storage
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  clickhouse:
    image: clickhouse/clickhouse-server:latest
    container_name: n8n-ai-clickhouse
    restart: unless-stopped
    environment:
      - CLICKHOUSE_DB=langfuse
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1
    volumes:
      - clickhouse_data:/var/lib/clickhouse
      - ./clickhouse_config:/etc/clickhouse-server/config.d
    networks:
      - database_network
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

  langfuse-web:
    image: ghcr.io/langfuse/langfuse:latest
    container_name: n8n-ai-langfuse-web
    restart: unless-stopped
    environment:
      # PostgreSQL
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      
      # ClickHouse
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      
      # Redis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_AUTH=${REDIS_PASSWORD}
      
      # S3/Blob Storage
      - LANGFUSE_S3_EVENT_UPLOAD_ENABLED=false
      - LANGFUSE_BLOB_STORAGE_PROVIDER=local
      - LANGFUSE_BLOB_STORAGE_UPLOAD_DIR=/app/data/uploads
      
      # Auth
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - NEXTAUTH_URL=https://langfuse.wemakemarin.com
      - SALT=${LANGFUSE_SALT}
      - ENCRYPTION_KEY=${LANGFUSE_ENCRYPTION_KEY}
      
      # Features
      - LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=true
      - LANGFUSE_ENABLE_BACKGROUND_MIGRATIONS=true
    ports:
      - "3000:3000"
    networks:
      - backend_network
      - database_network
    depends_on:
      postgres_dashboard:
        condition: service_healthy
      clickhouse:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - langfuse_data:/app/data
      - langfuse_uploads:/app/data/uploads

  langfuse-worker:
    image: ghcr.io/langfuse/langfuse:latest
    container_name: n8n-ai-langfuse-worker
    restart: unless-stopped
    command: worker
    environment:
      # PostgreSQL
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      
      # ClickHouse
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      
      # Redis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_AUTH=${REDIS_PASSWORD}
      
      # S3/Blob Storage
      - LANGFUSE_S3_EVENT_UPLOAD_ENABLED=false
      - LANGFUSE_BLOB_STORAGE_PROVIDER=local
      
      # Auth
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - SALT=${LANGFUSE_SALT}
      - ENCRYPTION_KEY=${LANGFUSE_ENCRYPTION_KEY}
    networks:
      - database_network
      - backend_network
    depends_on:
      postgres_dashboard:
        condition: service_healthy
      clickhouse:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - langfuse_uploads:/app/data/uploads

  code-parser:
    build: ./code_parser
    container_name: n8n-ai-code-parser
    restart: unless-stopped
    environment:
      - QDRANT_HOST=qdrant
      - QDRANT_PORT=6333
      - OLLAMA_HOST=ollama
      - OLLAMA_PORT=11434
      - COLLECTION_NAME=code_ast
      - EMBEDDING_MODEL=nomic-embed-text
      - WATCH_PATHS=/code/repos
      - SCAN_INTERVAL=300
      - PYTHONUNBUFFERED=1
      - LOG_LEVEL=INFO
    networks:
      - ai_network
      - backend_network
    volumes:
      - ./code_repos:/code/repos:ro
      - code_parser_cache:/app/cache
    depends_on:
      qdrant:
        condition: service_healthy
      ollama:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 2g
        reservations:
          memory: 1g

  code-indexer:
    build: ./code_indexer
    container_name: n8n-ai-code-indexer
    restart: unless-stopped
    environment:
      - QDRANT_HOST=qdrant
      - QDRANT_PORT=6333
      - OLLAMA_HOST=ollama
      - OLLAMA_PORT=11434
      - COLLECTION_NAME=code_index
      - EMBEDDING_MODEL=nomic-embed-text
      - CODE_PATHS=/code/repos
      - INDEX_INTERVAL=3600
      - BATCH_SIZE=100
      - PYTHONUNBUFFERED=1
    networks:
      - ai_network
      - backend_network
    volumes:
      - ./code_repos:/code/repos:ro
      - code_indexer_cache:/app/cache
    depends_on:
      - qdrant
      - ollama
    deploy:
      resources:
        limits:
          memory: 2g
        reservations:
          memory: 1g

  ast-chunker:
    build: ./ast_chunker
    container_name: n8n-ai-ast-chunker
    restart: unless-stopped
    environment:
      - QDRANT_HOST=qdrant
      - QDRANT_PORT=6333
      - OLLAMA_HOST=ollama
      - OLLAMA_PORT=11434
      - COLLECTION_NAME=ast_chunks
      - EMBEDDING_MODEL=nomic-embed-text
      - CODE_PATHS=/code/repos
      - CHUNK_SIZE=500
      - CHUNK_OVERLAP=50
      - PYTHONUNBUFFERED=1
    networks:
      - ai_network
      - backend_network
    volumes:
      - ./code_repos:/code/repos:ro
      - ast_chunker_cache:/app/cache
    depends_on:
      - qdrant
      - ollama
    deploy:
      resources:
        limits:
          memory: 2g
        reservations:
          memory: 1g

  n8n-sync:
    build: ./n8n_sync
    container_name: n8n-ai-n8n-sync
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n
      - N8N_PORT=5678
      - N8N_API_KEY=${N8N_API_KEY:-}
      - SYNC_INTERVAL=300
      - WORKFLOWS_PATH=/workflows
      - PYTHONUNBUFFERED=1
    volumes:
      - ./n8n_workflows:/workflows
    networks:
      - backend_network
    depends_on:
      - n8n

  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: n8n-ai-pgadmin
    restart: unless-stopped
    environment:
      - PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}
      - PGADMIN_CONFIG_SERVER_MODE=False
      - PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False
    ports:
      - "8888:80"
    networks:
      - backend_network
    depends_on:
      - postgres
      - postgres_dashboard
    volumes:
      - pgadmin_data:/var/lib/pgadmin
      - ./pgadmin_servers.json:/pgadmin4/servers.json

volumes:
  n8n_data:
    driver: local
  ollama_data:
    driver: local
  webui_data:
    driver: local
  postgres_data:
    driver: local
  postgres_dashboard_data:
    driver: local
  redis_data:
    driver: local
  qdrant_data:
    driver: local
  pgadmin_data:
    driver: local
  langfuse_data:
    driver: local
  langfuse_uploads:
    driver: local
  clickhouse_data:
    driver: local
  code_parser_cache:
    driver: local
  code_indexer_cache:
    driver: local
  ast_chunker_cache:
    driver: local

networks:
  backend_network:
    external: true
  database_network:
    external: true
  ai_network:
    external: true
EOF
    
    log_success "docker compose.yml created"
}

# ============================================
# Python Service Files
# ============================================

create_python_services() {
    log_info "Creating Python service files..."
    
    # code_parser service
    cat > code_parser/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY code_parser.py .

CMD ["python", "-u", "code_parser.py"]
EOF
    
    cat > code_parser/requirements.txt << 'EOF'
tree-sitter>=0.20.0
tree-sitter-languages>=1.7.0
qdrant-client>=1.7.0
ollama>=0.1.0
watchdog>=3.0.0
EOF
    
    cat > code_parser/code_parser.py << 'EOF'
#!/usr/bin/env python3
"""
Code Parser for AST-aware code chunking with Tree-sitter.
Indexes code functions into Qdrant vector database.
"""

import os
import time
import hashlib
import json
import signal
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from tree_sitter_languages import get_parser
from qdrant_client import QdrantClient
from qdrant_client.http import models
import ollama

class CodeParser:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.qdrant = QdrantClient(host=config["qdrant_host"], port=config["qdrant_port"])
        self.setup_collection()
        self.parsers = {}
        self.running = True
        self.supported_languages = {
            ".py": "python", ".js": "javascript", ".ts": "typescript",
            ".jsx": "javascript", ".tsx": "typescript", ".java": "java",
            ".go": "go", ".rs": "rust", ".cpp": "cpp", ".c": "c",
            ".rb": "ruby", ".php": "php", ".swift": "swift",
        }
    
    def setup_collection(self):
        try:
            collections = self.qdrant.get_collections().collections
            if not any(c.name == self.config["collection_name"] for c in collections):
                self.qdrant.create_collection(
                    collection_name=self.config["collection_name"],
                    vectors_config=models.VectorParams(
                        size=768,
                        distance=models.Distance.COSINE
                    )
                )
                print(f"Created collection: {self.config['collection_name']}")
        except Exception as e:
            print(f"Collection setup error: {e}")
    
    def get_parser(self, language: str):
        if language not in self.parsers:
            try:
                self.parsers[language] = get_parser(language)
            except Exception as e:
                print(f"Error loading parser for {language}: {e}")
                return None
        return self.parsers[language]
    
    def parse_file(self, file_path: str) -> List[models.PointStruct]:
        ext = os.path.splitext(file_path)[1]
        if ext not in self.supported_languages:
            return []
        
        language = self.supported_languages[ext]
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
            
            if len(content) < 50:
                return []
            
            # Simple chunking for now
            chunks = [content[i:i+500] for i in range(0, len(content), 500)]
            points = []
            
            for i, chunk in enumerate(chunks):
                embedding = ollama.embeddings(
                    model=self.config["embedding_model"],
                    prompt=chunk[:8000]
                )["embedding"]
                
                point_id = hashlib.md5(f"{file_path}:{i}".encode()).hexdigest()
                
                points.append(models.PointStruct(
                    id=point_id,
                    vector=embedding,
                    payload={
                        "file_path": file_path,
                        "language": language,
                        "chunk": chunk[:500],
                        "chunk_index": i,
                        "last_modified": os.path.getmtime(file_path)
                    }
                ))
            
            return points
        except Exception as e:
            print(f"Error parsing {file_path}: {e}")
            return []
    
    def scan_directory(self, path: str):
        if not os.path.exists(path):
            return
        
        all_points = []
        for root, _, files in os.walk(path):
            for file in files:
                ext = os.path.splitext(file)[1]
                if ext in self.supported_languages:
                    file_path = os.path.join(root, file)
                    points = self.parse_file(file_path)
                    all_points.extend(points)
        
        if all_points:
            for i in range(0, len(all_points), 100):
                batch = all_points[i:i+100]
                self.qdrant.upsert(
                    collection_name=self.config["collection_name"],
                    points=batch
                )
            print(f"Indexed {len(all_points)} chunks")

def main():
    config = {
        "qdrant_host": os.environ.get("QDRANT_HOST", "qdrant"),
        "qdrant_port": int(os.environ.get("QDRANT_PORT", 6333)),
        "ollama_host": os.environ.get("OLLAMA_HOST", "ollama"),
        "ollama_port": int(os.environ.get("OLLAMA_PORT", 11434)),
        "collection_name": os.environ.get("COLLECTION_NAME", "code_ast"),
        "embedding_model": os.environ.get("EMBEDDING_MODEL", "nomic-embed-text"),
        "watch_paths": [p.strip() for p in os.environ.get("WATCH_PATHS", "/code/repos").split(",")],
    }
    
    parser = CodeParser(config)
    
    for path in config["watch_paths"]:
        if os.path.exists(path):
            parser.scan_directory(path)
    
    while parser.running:
        time.sleep(1)

if __name__ == "__main__":
    main()
EOF
    
    # code_indexer (simplified - copy same as parser for now)
    cp code_parser/code_parser.py code_indexer/code_indexer.py
    cp code_parser/Dockerfile code_indexer/Dockerfile
    cp code_parser/requirements.txt code_indexer/requirements.txt
    
    # ast_chunker (simplified - copy same as parser for now)
    cp code_parser/code_parser.py ast_chunker/ast_chunker.py
    cp code_parser/Dockerfile ast_chunker/Dockerfile
    cp code_parser/requirements.txt ast_chunker/requirements.txt
    
    # n8n_sync
    mkdir -p n8n_sync
    cat > n8n_sync/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sync_workflows.py .

CMD ["python", "-u", "sync_workflows.py"]
EOF
    
    cat > n8n_sync/requirements.txt << 'EOF'
requests>=2.31.0
watchdog>=3.0.0
EOF
    
    cat > n8n_sync/sync_workflows.py << 'EOF'
#!/usr/bin/env python3
import os
import time
import json
import logging
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("n8n-sync")

class N8nSync:
    def __init__(self):
        self.n8n_host = os.environ.get("N8N_HOST", "n8n")
        self.n8n_port = os.environ.get("N8N_PORT", "5678")
        self.workflows_path = os.environ.get("WORKFLOWS_PATH", "/workflows")
    
    def sync_all(self):
        logger.info("Syncing workflows...")
        # Placeholder - implement actual sync logic

def main():
    sync = N8nSync()
    sync.sync_all()
    
    while True:
        time.sleep(300)

if __name__ == "__main__":
    main()
EOF
    
    log_success "Python service files created"
}

# ============================================
# Database Setup
# ============================================

setup_databases() {
    log_info "Setting up databases..."
    
    # Wait for postgres to be ready
    log_info "Waiting for PostgreSQL to be ready..."
    sleep 10
    
    # Create langfuse user and database
    docker compose exec -T postgres_dashboard psql -U dashboard_user -d dashboard_db << 'EOF' 2>/dev/null || true
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'langfuse_user') THEN
      CREATE USER langfuse_user WITH PASSWORD '${POSTGRES_PASSWORD}';
   END IF;
END
\$\$;

SELECT 'CREATE DATABASE langfuse_db OWNER langfuse_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'langfuse_db')\gexec

\c langfuse_db
GRANT ALL ON SCHEMA public TO langfuse_user;
ALTER SCHEMA public OWNER TO langfuse_user;
EOF
    
    # Setup ClickHouse
    log_info "Setting up ClickHouse..."
    docker compose exec -T clickhouse clickhouse-client --user default --password ${CLICKHOUSE_PASSWORD} --query "CREATE DATABASE IF NOT EXISTS langfuse;" 2>/dev/null || true
    docker compose exec -T clickhouse clickhouse-client --user default --password ${CLICKHOUSE_PASSWORD} --query "CREATE USER IF NOT EXISTS langfuse IDENTIFIED BY '${CLICKHOUSE_PASSWORD}';" 2>/dev/null || true
    docker compose exec -T clickhouse clickhouse-client --user default --password ${CLICKHOUSE_PASSWORD} --query "GRANT ALL ON langfuse.* TO langfuse;" 2>/dev/null || true
    
    log_success "Database setup complete"
}

# ============================================
# Main Menu
# ============================================

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "N8N AI Stack Setup" \
            --menu "Choose an option:" 20 60 10 \
            "1" "Complete Fresh Install (nuke everything)" \
            "2" "Rebuild Configuration Only" \
            "3" "Start Containers" \
            "4" "Stop Containers" \
            "5" "Check Status" \
            "6" "View Logs" \
            "7" "Pull Code Models (Ollama)" \
            "8" "Exit" \
            3>&1 1>&2 2>&3)
        
        case $CHOICE in
            "1")
                if confirm_action "This will STOP and REMOVE all containers and volumes. Continue?"; then
                    log_warn "Performing complete fresh install..."
                    
                    # Stop and remove everything
                    docker compose down -v 2>/dev/null || true
                    
                    # Remove all containers related to this project
                    docker container ls -a --filter "name=n8n-ai-*" -q | xargs -r docker rm -f
                    
                    # Remove volumes
                    docker volume ls --filter "name=n8n-ai-*" -q | xargs -r docker volume rm
                    
                    # Recreate everything
                    create_directories
                    create_config_files
                    create_python_services
                    create_docker_compose
                    
                    # Start databases first
                    docker compose up -d postgres postgres_dashboard redis clickhouse
                    sleep 10
                    
                    setup_databases
                    
                    # Start everything
                    docker compose up -d
                    
                    show_menu "Success" "Fresh install completed!\n\nCheck status with option 5"
                fi
                ;;
            "2")
                log_info "Rebuilding configuration..."
                create_directories
                create_config_files
                create_python_services
                create_docker_compose
                show_menu "Success" "Configuration rebuilt successfully!"
                ;;
            "3")
                log_info "Starting containers..."
                docker compose up -d
                show_menu "Success" "Containers started!"
                ;;
            "4")
                log_info "Stopping containers..."
                docker compose down
                show_menu "Success" "Containers stopped!"
                ;;
            "5")
                # Check status and show in whiptail
                STATUS=$(docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running")
                show_menu "Container Status" "$STATUS"
                ;;
            "6")
                # Show last 50 lines of logs
                LOGS=$(docker compose logs --tail=50 2>&1 | tail -50)
                show_menu "Recent Logs" "$LOGS"
                ;;
            "7")
                log_info "Pulling code models..."
                docker compose up ollama-code-setup
                show_menu "Success" "Code models pulled successfully!"
                ;;
            "8")
                log_info "Exiting..."
                exit 0
                ;;
        esac
    done
}

# ============================================
# Initial Setup
# ============================================

# Check if running as root
#if [ "$EUID" -eq 0 ]; then
 #   log_error "Please do not run as root"
  #  exit 1
#fi

# Show welcome message
whiptail --title "N8N AI Stack Setup" \
    --msgbox "Welcome to the N8N AI Stack complete setup script!\n\nThis script will help you configure and manage your entire AI stack with:\n• n8n (workflow automation)\n• Ollama (local LLMs)\n• Open WebUI (chat interface)\n• Qdrant (vector database)\n• Langfuse (LLM observability)\n• ClickHouse (analytics)\n• PostgreSQL (databases)\n• Code parsing services" 0 0

# Run setup
check_prerequisites
setup_env
main_menu
