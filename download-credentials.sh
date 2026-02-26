#!/bin/bash

TOKEN="eyJhIjoiZDkyOTQxODhjNDE3ZTFmMTZjZDk0ZjY5ZGU3ZDU3M2UiLCJ0IjoiMWJkZDQ3ZjctOTk2ZS00N2I2LTllMDItNTQxMThjYmMxZDk3IiwicyI6Ik56Rm1ZbUZpTXpndE1tUXdPUzAwTUdJNExXRXpNall0TmpnMU5URmtZV0l5TURnMyJ9"
TUNNEL_ID="1ac8cba0-2e8c-48f2-94ab-225f12516eaa"

echo "Downloading credentials for tunnel: $TUNNEL_ID"
echo ""

# Create credentials directory
mkdir -p cloudflared/credentials

# Download the credentials file
docker run --rm \
  -v $(pwd)/cloudflared/credentials:/credentials \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --token "$TOKEN" token \
  --cred-file /credentials/$TUNNEL_ID.json \
  $TUNNEL_ID

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Credentials downloaded successfully!"
  echo "File saved to: cloudflared/credentials/$TUNNEL_ID.json"
  echo ""
  echo "You can now start the tunnel with:"
  echo "docker-compose up -d cloudflared"
else
  echo ""
  echo "✗ Failed to download credentials"
  echo "Please check your token and tunnel ID"
fi
