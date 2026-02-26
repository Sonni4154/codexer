#!/bin/bash

echo "AI Stack Setup Script"
echo "====================="

# Function to pull Ollama models
pull_model() {
  echo "Pulling model: $1"
  docker exec -it n8n-ai-ollama ollama pull $1
  echo ""
}

# Create models directory for custom models
mkdir -p models

echo "1. Starting all services..."
docker-compose up -d

echo ""
echo "2. Waiting for Ollama to start..."
sleep 10

echo ""
echo "3. Available GPU check:"
docker exec n8n-ai-ollama nvidia-smi 2>/dev/null || echo "No NVIDIA GPU detected, using CPU"

echo ""
echo "4. Recommended model downloads:"
echo "   Choose models based on your hardware:"
echo ""
echo "   For 4-8GB RAM:"
echo "   - llama3.2:3b (1.9GB)"
echo "   - phi3:mini (2.0GB)"
echo ""
echo "   For 8-16GB RAM:"
echo "   - mistral:7b (4.1GB)"
echo "   - llama3.1:8b (4.7GB)"
echo "   - qwen2.5:7b (4.4GB)"
echo ""
echo "   For 16+GB RAM:"
echo "   - llama3.1:70b (40GB)"
echo "   - mixtral:8x7b (46GB)"

echo ""
read -p "Would you like to download some models now? (y/n): " choice

if [[ $choice == "y" || $choice == "Y" ]]; then
  echo ""
  echo "Available models to download:"
  echo "1. llama3.2:3b (Fast, small, good for testing)"
  echo "2. mistral:7b (Good balance of speed/quality)"
  echo "3. qwen2.5:7b (Good for coding)"
  echo "4. Custom model (enter name)"
  
  read -p "Enter choice (1-4): " model_choice
  
  case $model_choice in
    1)
      pull_model "llama3.2:3b"
      ;;
    2)
      pull_model "mistral:7b"
      ;;
    3)
      pull_model "qwen2.5:7b"
      ;;
    4)
      read -p "Enter model name (e.g., llama3.1:8b): " custom_model
      pull_model "$custom_model"
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
fi

echo ""
echo "5. Setup complete!"
echo ""
echo "Services:"
echo "- N8N: http://localhost:5678"
echo "- Open WebUI: http://localhost:8080"
echo "- Ollama API: http://localhost:11434"
echo "- Qdrant: http://localhost:6333"
echo "- pgAdmin: http://localhost:5050"
echo ""
echo "To use with cloudflared, update the config file at:"
echo "cloudflared/config/config.yml"
echo ""
echo "To list downloaded models: docker exec n8n-ai-ollama ollama list"
echo "To pull more models: docker exec -it n8n-ai-ollama ollama pull <model>"
