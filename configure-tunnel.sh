#!/bin/bash

TOKEN="eyJhIjoiZDkyOTQxODhjNDE3ZTFmMTZjZDk0ZjY5ZGU3ZDU3M2UiLCJ0IjoiM2NiNjZlNzEtNTYwMi00ZGQ5LWFjNDctOWE5YTA3MTRkMzdiIiwicyI6Ik9UY3hNelZrT0dJdE5HWmpaUzAwTjJaaUxXSXdOekF0Wm1ZelpHRmpaVEE0TkRsbSJ9"

echo "Configuring Cloudflare Tunnel Routes..."
echo ""

echo "1. Setting up n8n.wemakemarin.com route..."
docker run --rm \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --token "$TOKEN" \
  route dns n8n-ai-tunnel n8n.wemakemarin.com

echo ""
echo "2. Setting up ai.wemakemarin.com route..."
docker run --rm \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --token "$TOKEN" \
  route dns n8n-ai-tunnel ai.wemakemarin.com

echo ""
echo "3. Verifying routes..."
docker run --rm \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --token "$TOKEN" list

echo ""
echo "✓ Tunnel configured!"
echo "Your services will be available at:"
echo "- https://n8n.wemakemarin.com"
echo "- https://ai.wemakemarin.com"
echo ""
echo "Note: DNS changes may take 5-10 minutes to propagate."
