#!/bin/bash

echo "Verifying DNS Setup for wemakemarin.com"
echo "========================================"

echo ""
echo "1. Checking DNS propagation..."
echo ""

echo "n8n.wemakemarin.com:"
dig n8n.wemakemarin.com +short
echo ""

echo "ai.wemakemarin.com:"
dig ai.wemakemarin.com +short
echo ""

echo "2. Expected result:"
echo "Both should resolve to: 1ac8cba0-2e8c-48f2-94ab-225f12516eaa.cfargotunnel.com"
echo ""

echo "3. Testing tunnel connection..."
echo "If tunnel is running, these should work:"
echo ""
echo "Tunnel status:"
docker exec n8n-ai-cloudflared cloudflared tunnel info 2>/dev/null || \
  echo "Tunnel not running. Start with: docker-compose up -d cloudflared"
echo ""

echo "4. Once DNS propagates (5-10 minutes), test:"
echo "   curl -I https://n8n.wemakemarin.com"
echo "   curl -I https://ai.wemakemarin.com"
echo ""
echo "You should get HTTP 200 or 302 responses."
