#!/bin/bash

# ============================================
# ClickHouse Single-Node Fix for Langfuse
# Uses docker compose (v2) with docker-compose.yml
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

# Check if docker compose is available
if ! docker compose version &>/dev/null; then
    log_error "docker compose (v2) not found. Please install Docker Compose v2."
    exit 1
fi

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
    log_info "Loaded .env file"
else
    log_error ".env file not found"
    exit 1
fi

log_info "Configuring ClickHouse for single-node mode (no replication)..."

# 1. Create ClickHouse config to disable replication and set up single-node
mkdir -p clickhouse_config

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
    <interserver_http_host>clickhouse</interserver_http_host>
    
    <!-- Disable replication features -->
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>
    
    <logger>
        <level>trace</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>
    
    <!-- Disable ZooKeeper (no replication) -->
    <zookeeper>
        <node>
            <host>disabled</host>
            <port>0</port>
        </node>
    </zookeeper>
    
    <!-- Default database -->
    <default_database>langfuse</default_database>
    
    <!-- Macros for single node -->
    <macros>
        <shard>01</shard>
        <replica>01</replica>
    </macros>
</clickhouse>
EOF

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
    
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
        </default>
    </profiles>
    
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF

# 2. Restart ClickHouse with new config
log_info "Restarting ClickHouse with new configuration..."
docker compose stop clickhouse
docker compose rm -f clickhouse
docker compose up -d clickhouse
sleep 15

# 3. Create database and user
log_info "Creating ClickHouse database and user..."
docker compose exec -T clickhouse clickhouse-client --user default --query "CREATE DATABASE IF NOT EXISTS langfuse;" 2>/dev/null || true
docker compose exec -T clickhouse clickhouse-client --user default --query "CREATE USER IF NOT EXISTS langfuse IDENTIFIED BY '${CLICKHOUSE_PASSWORD}';" 2>/dev/null || true
docker compose exec -T clickhouse clickhouse-client --user default --query "GRANT ALL ON langfuse.* TO langfuse;" 2>/dev/null || true

# 4. Create a special migration table manually (to avoid replicated engine)
log_info "Creating schema_migrations table with MergeTree engine..."
docker compose exec -T clickhouse clickhouse-client --user default --database langfuse --query "
CREATE TABLE IF NOT EXISTS schema_migrations (
    version Int64,
    dirty UInt8,
    sequence UInt64
) ENGINE = MergeTree()
ORDER BY sequence;
" 2>/dev/null || true

# 5. Update Langfuse configuration for single-node ClickHouse
log_info "Updating Langfuse configuration for single-node ClickHouse..."

# Create a docker-compose.override.yml file that will be automatically merged
cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  langfuse-web:
    environment:
      # PostgreSQL (working)
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      
      # ClickHouse - single node configuration
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_SSL=false
      
      # Disable clustering/replication features
      - LANGFUSE_CLICKHOUSE_CLUSTER_ENABLED=false
      - LANGFUSE_CLICKHOUSE_REPLICATED=false
      
      # Redis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_AUTH=${REDIS_PASSWORD}
      
      # S3/Blob Storage
      - LANGFUSE_S3_EVENT_UPLOAD_ENABLED=false
      - LANGFUSE_BLOB_STORAGE_PROVIDER=local
      - LANGFUSE_BLOB_STORAGE_UPLOAD_DIR=/app/data/uploads
      
      # Auth
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - NEXTAUTH_URL=https://langfuse.wemakemarin.com
      - SALT=${LANGFUSE_SALT}
      - ENCRYPTION_KEY=${LANGFUSE_ENCRYPTION_KEY}
      
      # Features
      - LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES=true
      - LANGFUSE_ENABLE_BACKGROUND_MIGRATIONS=true
    depends_on:
      postgres_dashboard:
        condition: service_healthy
      clickhouse:
        condition: service_started
      redis:
        condition: service_healthy

  langfuse-worker:
    environment:
      # PostgreSQL
      - DATABASE_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      - DIRECT_URL=postgresql://langfuse_user:${POSTGRES_PASSWORD}@postgres_dashboard:5432/langfuse_db
      
      # ClickHouse - single node configuration
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_SSL=false
      
      # Disable clustering/replication features
      - LANGFUSE_CLICKHOUSE_CLUSTER_ENABLED=false
      - LANGFUSE_CLICKHOUSE_REPLICATED=false
      
      # Redis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_AUTH=${REDIS_PASSWORD}
      
      # S3/Blob Storage
      - LANGFUSE_S3_EVENT_UPLOAD_ENABLED=false
      - LANGFUSE_BLOB_STORAGE_PROVIDER=local
      
      # Auth
      - NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
      - SALT=${LANGFUSE_SALT}
      - ENCRYPTION_KEY=${LANGFUSE_ENCRYPTION_KEY}
      
      # Features
      - LANGFUSE_ENABLE_BACKGROUND_MIGRATIONS=true
    depends_on:
      postgres_dashboard:
        condition: service_healthy
      clickhouse:
        condition: service_started
      redis:
        condition: service_healthy
EOF

log_success "Created docker-compose.override.yml with single-node ClickHouse configuration"

# 6. Stop and remove old Langfuse containers
log_info "Restarting Langfuse with single-node configuration..."
docker compose stop langfuse-web langfuse-worker
docker compose rm -f langfuse-web langfuse-worker

# 7. Start fresh (override.yml will be automatically merged)
log_info "Starting Langfuse with new configuration..."
docker compose up -d langfuse-web langfuse-worker

# 8. Wait and monitor
log_info "Waiting 30 seconds for Langfuse to initialize..."
sleep 30

log_info "Recent Langfuse logs:"
docker compose logs --tail=50 langfuse-web langfuse-worker

log_success "Fix applied!"
log_info "If still having issues, check ClickHouse configuration:"
echo ""
echo "1. Check ClickHouse tables:"
echo "   docker compose exec clickhouse clickhouse-client --user default --query \"SHOW DATABASES;\""
echo "   docker compose exec clickhouse clickhouse-client --user default --database langfuse --query \"SHOW TABLES;\""
echo ""
echo "2. Check Langfuse logs in real-time:"
echo "   docker compose logs -f langfuse-web langfuse-worker"
echo ""
echo "3. View merged configuration:"
echo "   docker compose config"
