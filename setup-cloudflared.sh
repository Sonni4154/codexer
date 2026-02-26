#!/bin/bash

echo "Setting up Cloudflare Tunnel..."

# Create necessary directories
mkdir -p cloudflared/config
mkdir -p cloudflared/credentials

# Create config file
cat > cloudflared/config/config.yml << 'CONFIG_EOF'
tunnel: n8n-tunnel
credentials-file: /etc/cloudflared/credentials/credentials.json

ingress:
  - hostname: your-n8n-domain.example.com
    service: http://n8n:5678
    originRequest:
      noTLSVerify: true
  - service: http_status:404
CONFIG_EOF

echo "1. Config file created at cloudflared/config/config.yml"
echo "2. Please update the hostname in the config file with your actual domain"
echo ""
echo "3. To complete setup, run:"
echo "   docker exec -it n8n-ai-cloudflared /bin/sh"
echo "   Then inside the container:"
echo "   - cloudflared tunnel login"
echo "   - cloudflared tunnel create n8n-tunnel"
echo "   - cloudflared tunnel route dns n8n-tunnel your-subdomain.your-domain.com"
