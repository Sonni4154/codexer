#!/bin/bash

# ============================================
# Langfuse Database Fix Script
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
    log_info "Loaded .env file"
else
    log_error ".env file not found"
    exit 1
fi

# Stop Langfuse services to prevent connection spam
log_info "Stopping Langfuse services..."
docker compose stop langfuse-web langfuse-worker

# Ensure postgres_dashboard is running
log_info "Ensuring postgres_dashboard is running..."
docker compose up -d postgres_dashboard
sleep 5

# Direct database fix - connect to default database first
log_info "Creating langfuse_user and database directly..."

# Use a here document with proper variable substitution
docker compose exec -T postgres_dashboard psql -U dashboard_user -d postgres << EOF
-- Drop existing if any (clean slate)
DROP DATABASE IF EXISTS langfuse_db;
DROP USER IF EXISTS langfuse_user;

-- Create user with password from .env
CREATE USER langfuse_user WITH PASSWORD '${POSTGRES_PASSWORD}' SUPERUSER;

-- Create database
CREATE DATABASE langfuse_db OWNER langfuse_user;

-- Connect to new database and set permissions
\c langfuse_db
GRANT ALL PRIVILEGES ON DATABASE langfuse_db TO langfuse_user;
GRANT ALL ON SCHEMA public TO langfuse_user;
ALTER SCHEMA public OWNER TO langfuse_user;

-- Verify
SELECT 'User created: ' || usename FROM pg_user WHERE usename = 'langfuse_user';
SELECT 'Database created: ' || datname FROM pg_database WHERE datname = 'langfuse_db';
EOF

# Test the connection directly
log_info "Testing connection as langfuse_user..."
if docker compose exec -T postgres_dashboard psql -U langfuse_user -d langfuse_db -c "SELECT 'Connection successful' as test;" 2>/dev/null; then
    log_success "✅ Connection successful!"
else
    log_error "❌ Connection failed. Trying with password from .env..."
    
    # Try with explicit password
    PGPASSWORD=${POSTGRES_PASSWORD} docker compose exec -T postgres_dashboard psql -U langfuse_user -d langfuse_db -c "SELECT 'Connection successful' as test;"
fi

# Update Langfuse services with correct configuration
log_info "Updating Langfuse configuration..."

# Create a temporary docker compose override
cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  langfuse-web:
    environment:
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
    depends_on:
      postgres_dashboard:
        condition: service_healthy

  langfuse-worker:
    environment:
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
    depends_on:
      postgres_dashboard:
        condition: service_healthy
EOF

# Restart Langfuse
log_info "Starting Langfuse services..."
docker compose up -d langfuse-web langfuse-worker

# Wait and check logs
log_info "Waiting for Langfuse to initialize (30 seconds)..."
sleep 30

# Check status
log_info "Checking Langfuse status..."
docker compose ps langfuse-web langfuse-worker

# Show recent logs
log_info "Recent Langfuse logs:"
docker compose logs --tail=20 langfuse-web langfuse-worker

log_success "Fix completed!"
log_info "If still having issues, run this manual check:"
echo ""
echo "  # Connect directly to verify:"
echo "  docker compose exec postgres_dashboard psql -U langfuse_user -d langfuse_db"
echo ""
echo "  # Check Langfuse logs:"
echo "  docker compose logs -f langfuse-web langfuse-worker"
