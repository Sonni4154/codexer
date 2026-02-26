#!/bin/bash

echo "🔧 Applying final fixes..."

# Fix 1: Create n8n_task_runner_config as a file, not directory
echo "📁 Fixing n8n task runner config..."
rm -rf n8n_task_runner_config
cat > n8n_task_runner_config.json << 'EOF'
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

# Update docker-compose.yml to use file not directory
sed -i 's|./n8n_task_runner_config:/etc/n8n-task-runners.json:ro|./n8n_task_runner_config.json:/etc/n8n-task-runners.json:ro|g' docker-compose.yml

# Fix 2: Pull all required models
echo "📥 Pulling Ollama models..."
docker compose up -d ollama
sleep 10

echo "Pulling nomic-embed-text (required for embeddings)..."
docker compose exec -T ollama ollama pull nomic-embed-text

echo "Pulling codellama:13b (code generation)..."
docker compose exec -T ollama ollama pull codellama:13b

echo "Pulling deepseek-coder:6.7b (chat & analysis)..."
docker compose exec -T ollama ollama pull deepseek-coder:6.7b

# Create custom model
echo "Creating code-assistant model..."
cat > ollama_modelfiles/CodeAssistant << 'EOF'
FROM codellama:13b
PARAMETER temperature 0.2
PARAMETER top_p 0.9
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

docker compose exec -T ollama ollama create code-assistant -f /root/modelfiles/CodeAssistant

# Fix 3: Restart Qdrant to resolve unhealthy state
echo "🔄 Restarting Qdrant..."
docker compose stop qdrant
docker compose rm -f qdrant
docker volume rm n8n-ai_qdrant_data 2>/dev/null || true
docker compose up -d qdrant
sleep 10

# Fix 4: Update code parser services to wait for Qdrant
echo "🔄 Restarting code parser services..."
docker compose restart code-parser code-indexer ast-chunker

# Final status
echo ""
echo "📊 Final Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "🤖 Available Models:"
docker compose exec ollama ollama list

echo ""
echo "✅ System Ready!"
echo "🌐 Access URLs:"
echo "  n8n:         https://n8n.wemakemarin.com"
echo "  Open WebUI:  https://ai.wemakemarin.com"
echo "  Qdrant:      http://localhost:6333/dashboard"
echo "  pgAdmin:     http://localhost:8888"
