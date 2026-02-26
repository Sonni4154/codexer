#!/bin/bash

# ============================================
# ClickHouse Connection Fix Script
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

log_info "Checking ClickHouse status..."

# 1. Check if ClickHouse is running
if ! docker compose ps clickhouse | grep -q "Up"; then
    log_warn "ClickHouse is not running. Starting it..."
    docker compose up -d clickhouse
    sleep 10
fi

# 2. Check ClickHouse logs
log_info "ClickHouse logs:"
docker compose logs --tail=20 clickhouse

# 3. Test ClickHouse connectivity from host
log_info "Testing ClickHouse from host..."
if docker compose exec clickhouse clickhouse-client --user default --password ${CLICKHOUSE_PASSWORD} --query "SELECT 1;" 2>/dev/null; then
    log_success "✅ ClickHouse is accessible from host"
else
    log_error "❌ Cannot connect to ClickHouse from host"
fi

# 4. Get ClickHouse container IP
CLICKHOUSE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' n8n-ai-clickhouse 2>/dev/null)
log_info "ClickHouse IP: ${CLICKHOUSE_IP:-unknown}"

# 5. Test network connectivity from langfuse-web container
log_info "Testing network from langfuse-web container..."
docker compose run --rm langfuse-web sh -c "apt-get update && apt-get install -y netcat-openbsd && nc -zv clickhouse 9000" 2>&1 || true

# 6. Check ClickHouse listening ports
log_info "ClickHouse listening ports:"
docker compose exec clickhouse netstat -tulpn 2>/dev/null || docker compose exec clickhouse ss -tulpn 2>/dev/null || echo "Netstat not available"

# 7. Update ClickHouse configuration to listen on all interfaces
log_info "Updating ClickHouse configuration..."

# Create config file to ensure proper networking
cat > clickhouse_config/config.xml << 'EOF'
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
    <listen_host>::</listen_host>
    <listen_try>1</listen_try>
    
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <mysql_port>9004</mysql_port>
    <postgresql_port>9005</postgresql_port>
    
    <interserver_http_port>9009</interserver_http_port>
    
    <logger>
        <level>trace</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>
</clickhouse>
EOF

# Create users config
cat > clickhouse_config/users.xml << 'EOF'
<clickhouse>
    <users>
        <default>
            <password></password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
        <langfuse>
            <password>${CLICKHOUSE_PASSWORD}</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </langfuse>
    </users>
</clickhouse>
EOF

# 8. Restart ClickHouse with new config
log_info "Restarting ClickHouse..."
docker compose stop clickhouse
docker compose rm -f clickhouse
docker compose up -d clickhouse
sleep 15

# 9. Verify ClickHouse is healthy
log_info "Verifying ClickHouse health..."
docker compose ps clickhouse

# 10. Create langfuse database and user
log_info "Setting up ClickHouse database..."
docker compose exec -T clickhouse clickhouse-client --user default --password "${CLICKHOUSE_PASSWORD}" --query "CREATE DATABASE IF NOT EXISTS langfuse;" 2>/dev/null || true
docker compose exec -T clickhouse clickhouse-client --user default --password "${CLICKHOUSE_PASSWORD}" --query "CREATE USER IF NOT EXISTS langfuse IDENTIFIED BY '${CLICKHOUSE_PASSWORD}';" 2>/dev/null || true
docker compose exec -T clickhouse clickhouse-client --user default --password "${CLICKHOUSE_PASSWORD}" --query "GRANT ALL ON langfuse.* TO langfuse;" 2>/dev/null || true

# 11. Update Langfuse configuration with correct ClickHouse URL
log_info "Updating Langfuse configuration..."

# Create docker compose override for Langfuse
cat > docker compose.override.yml << EOF
version: '3.8'

services:
  langfuse-web:
    environment:
      # ClickHouse with explicit connection parameters
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_SSL=false
      
      # Also add these for compatibility
      - CLICKHOUSE_MIGRATION_HOST=clickhouse
      - CLICKHOUSE_MIGRATION_PORT=9000
      - CLICKHOUSE_MIGRATION_USER=langfuse
      - CLICKHOUSE_MIGRATION_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_MIGRATION_DATABASE=langfuse
    depends_on:
      clickhouse:
        condition: service_healthy

  langfuse-worker:
    environment:
      # ClickHouse with explicit connection parameters
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_SSL=false
      
      # Also add these for compatibility
      - CLICKHOUSE_MIGRATION_HOST=clickhouse
      - CLICKHOUSE_MIGRATION_PORT=9000
      - CLICKHOUSE_MIGRATION_USER=langfuse
      - CLICKHOUSE_MIGRATION_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_MIGRATION_DATABASE=langfuse
    depends_on:
      clickhouse:
        condition: service_healthy
EOF

# 12. Restart Langfuse
log_info "Restarting Langfuse..."
docker compose stop langfuse-web langfuse-worker
docker compose rm -f langfuse-web langfuse-worker
docker compose up -d langfuse-web langfuse-worker

# 13. Wait and check logs
log_info "Waiting 30 seconds for Langfuse to initialize..."
sleep 30

log_info "Recent Langfuse logs:"
docker compose logs --tail=50 langfuse-web langfuse-worker

log_success "Fix completed!"
log_info "If still having issues, try these manual checks:"
echo ""
echo "1. Test ClickHouse directly:"
echo "   docker compose exec clickhouse clickhouse-client --user default --password ${CLICKHOUSE_PASSWORD} --query \"SHOW DATABASES;\""
echo ""
echo "2. Test from Langfuse container:"
echo "   docker compose run --rm langfuse-web sh -c \"apt-get update && apt-get install -y telnet && telnet clickhouse 9000\""
echo ""
echo "3. Check ClickHouse logs:"
echo "   docker compose logs clickhouse"
