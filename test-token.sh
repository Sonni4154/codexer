#!/bin/bash

TOKEN="eyJhIjoiZDkyOTQxODhjNDE3ZTFmMTZjZDk0ZjY5ZGU3ZDU3M2UiLCJ0IjoiMWJkZDQ3ZjctOTk2ZS00N2I2LTllMDItNTQxMghjYmMxZDk3IiwicyI6Ik56Rm1ZbUZpTXpndE1tUXdPUzAwTUdJNExXRXpNall0TmpnMU5URmtZV0l5TURnMyJ9"

echo "Testing Cloudflare Token..."
echo ""

# Try to list tunnels with the token
docker run --rm \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --token "$TOKEN" list 2>&1

echo ""
echo "If you see 'Invalid credentials' or similar, the token is invalid."
echo "You may need to generate a new token from Cloudflare Dashboard."
