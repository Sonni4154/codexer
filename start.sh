#!/bin/bash
set -e
echo "Starting n8n-AI stack..."
docker-compose up -d
echo "Services started!"
echo "n8n: http://localhost:5678"
echo "pgAdmin: http://localhost:5050"
echo "Qdrant: http://localhost:6333"
