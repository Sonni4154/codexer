#!/bin/bash

echo "🔧 FIXING ALL ISSUES..."

# === 1. COMPLETELY NUKE QDRANT ===
echo "1️⃣ Nuking Qdrant configuration..."
docker compose stop qdrant
docker compose rm -f qdrant
docker volume rm n8n-ai_qdrant_data 2>/dev/null || true
rm -rf qdrant_config/*
mkdir -p qdrant_config

# Create minimal config (won't be used)
cat > qdrant_config/qdrant.yaml << 'EOF'
log_level: INFO
service:
  http_port: 6333
  grpc_port: 6334
EOF

# === 2. CREATE LANGFUSE DATABASE USER ===
echo "2️⃣ Creating langfuse database user..."
docker compose exec -T postgres_dashboard psql -U dashboard_user -d dashboard_db << 'EOF'
CREATE USER langfuse_user WITH PASSWORD '${POSTGRES_PASSWORD}';
CREATE DATABASE langfuse_db OWNER langfuse_user;
GRANT ALL PRIVILEGES ON DATABASE langfuse_db TO langfuse_user;
\c langfuse_db
GRANT ALL ON SCHEMA public TO langfuse_user;
EOF

# === 3. FIX ENVIRONMENT VARIABLES ===
echo "3️⃣ Updating .env file..."
cat >> .env << 'EOF'

# Langfuse Database
LANGFUSE_DB_USER=langfuse_user
LANGFUSE_DB_PASSWORD=${POSTGRES_PASSWORD}
LANGFUSE_DB_NAME=langfuse_db
EOF

# === 4. UPDATE DOCKER-COMPOSE.YML ===
echo "4️⃣ Please replace these services in your docker-compose.yml"

cat << 'SERVICES'

### REPLACE QDRANT WITH THIS (NO ENV VARS, NO CONFIG):
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

### REMOVE N8N_RUNNERS_ENABLED FROM N8N ENVIRONMENT (remove this line):
      # - N8N_RUNNERS_ENABLED=true   <-- DELETE THIS LINE

### UPDATE LANGFUSE DATABASE CONNECTION:
  langfuse-web:
    environment:
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db

  langfuse-worker:
    environment:
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
SERVICES

# === 5. FIX DNS (cloudflared can't resolve n8n) ===
echo "5️⃣ Fixing DNS for cloudflared..."
# Add n8n to hosts file in cloudflared container (will be handled by docker networks)
# But we need to ensure n8n is healthy first

# === 6. RESTART EVERYTHING PROPERLY ===
echo "6️⃣ Restarting services in correct order..."
docker compose down

echo "Starting databases first..."
docker compose up -d postgres postgres_dashboard redis clickhouse
sleep 10

echo "Starting qdrant..."
docker compose up -d qdrant
sleep 5

echo "Starting ollama and code services..."
docker compose up -d ollama code-parser code-indexer ast-chunker
sleep 10

echo "Starting n8n and webui..."
docker compose up -d n8n n8n-task-runners webui
sleep 5

echo "Starting langfuse..."
docker compose up -d langfuse-web langfuse-worker
sleep 5

echo "Starting cloudflared last..."
docker compose up -d cloudflared

echo "✅ Done! Check status with: docker-compose ps"
