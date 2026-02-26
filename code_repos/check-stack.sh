#!/bin/bash

echo "🔍 Checking AI Stack Status"
echo "==========================="

# Check critical services
SERVICES="n8n webui ollama qdrant postgres postgres_dashboard redis code-parser"

for service in $SERVICES; do
    if docker compose ps $service | grep -q "Up"; then
        echo "✅ $service: Running"
    else
        echo "❌ $service: Not running"
    fi
done

echo ""
echo "📊 Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10

echo ""
echo "🌐 Access URLs:"
echo "  n8n:      https://n8n.wemakemarin.com"
echo "  Open WebUI: https://ai.wemakemarin.com"
echo "  Qdrant:   http://localhost:6333/dashboard"
echo "  pgAdmin:  http://localhost:8888"
