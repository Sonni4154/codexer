#!/bin/bash

echo "🔧 Fixing Qdrant configuration..."

# Backup old config
if [ -d "qdrant_config" ]; then
  mv qdrant_config qdrant_config_backup_$(date +%s)
fi

# Create fresh config directory (optional, not used in Option 1)
mkdir qdrant_config

# Update docker-compose.yml - YOU NEED TO EDIT THIS MANUALLY
echo ""
echo "⚠️  Please replace your qdrant service in docker-compose.yml with:"
echo ""
echo "  qdrant:"
echo "    image: qdrant/qdrant:latest"
echo "    container_name: n8n-ai-qdrant"
echo "    restart: unless-stopped"
echo "    environment:"
echo "      - QDRANT__LOG_LEVEL=INFO"
echo "      - QDRANT__SERVICE__HTTP_PORT=6333"
echo "      - QDRANT__SERVICE__GRPC_PORT=6334"
echo "      - QDRANT__STORAGE__OPTIMIZERS__MEMMAP_THRESHOLD=10000"
echo "      - QDRANT__STORAGE__OPTIMIZERS__INDEXING_THRESHOLD=10000"
echo "    ports:"
echo "      - \"6333:6333\""
echo "      - \"6334:6334\""
echo "    networks:"
echo "      - ai_network"
echo "      - backend_network"
echo "    volumes:"
echo "      - qdrant_data:/qdrant/storage"
echo "    healthcheck:"
echo "      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:6333/healthz\"]"
echo "      interval: 30s"
echo "      timeout: 10s"
echo "      retries: 3"
echo ""

# Ensure n8n custom directory is properly set up
echo "📁 Fixing n8n custom module directory..."
mkdir -p n8n_custom

if [ ! -f "n8n_custom/package.json" ]; then
  cat > n8n_custom/package.json << 'EOF'
{
  "name": "n8n-custom",
  "version": "1.0.0",
  "description": "Custom n8n modules",
  "main": "index.js",
  "dependencies": {}
}
EOF
fi

if [ ! -f "n8n_custom/index.js" ]; then
  cat > n8n_custom/index.js << 'EOF'
module.exports = {};
EOF
fi

echo "✅ n8n custom module directory ready"

# Check for any stray Qdrant config
echo "🔍 Checking for stray Qdrant configuration..."
find . -name "*qdrant*" -type f -not -path "*/\.*" -not -path "*/backup*" 2>/dev/null | grep -v "docker-compose.yml"

echo ""
echo "🚀 Now:"
echo "1. Update your docker-compose.yml with the qdrant service above"
echo "2. Run: docker-compose down"
echo "3. Run: docker-compose up -d"
