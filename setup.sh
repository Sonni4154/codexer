#!/bin/bash
# Sets up all filse and directories for ast and code_index parts
# Create directory structure
mkdir -p code_parser code_indexer ast_chunker n8n_sync
mkdir -p n8n_workflows n8n_credentials ollama_modelfiles
mkdir -p code_repos qdrant_config postgres_init webui_functions webui_configs
mkdir -p n8n_custom

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cat > .env << EOF
# Database
POSTGRES_PASSWORD=trustno2
REDIS_PASSWORD=trustno2

# Encryption
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
NEXTAUTH_SECRET=$(openssl rand -hex 32)
LANGFUSE_SALT=$(openssl rand -hex 16)
LANGFUSE_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Admin
PGADMIN_EMAIL=spencermreiser@gmail.com
PGADMIN_PASSWORD=trustno2

# Timezone
TZ=America/Los_Angeles
EOF
fi

# Create default qdrant config
cat > qdrant_config/qdrant.yaml << EOF
log_level: INFO
service:
  http_port: 6333
  grpc_port: 6334
storage:
  optimizers:
    default_segment_number: 5
    memmap_threshold: 10000
    indexing_threshold: 10000
EOF

echo "✅ Setup complete!"
echo "Next steps:"
echo "1. Copy the Python files into their respective directories"
echo "2. Run: docker-compose up -d"
echo "3. Run model setup: docker-compose up ollama-code-setup"
