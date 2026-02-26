#!/bin/bash

# ============================================
# Add ZooKeeper for ClickHouse Replication
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

log_info "Adding ZooKeeper for ClickHouse replication..."

# Stop services
docker compose stop langfuse-web langfuse-worker clickhouse

# Add ZooKeeper to docker-compose.override.yml
cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  zookeeper:
    image: zookeeper:3.8
    container_name: n8n-ai-zookeeper
    restart: unless-stopped
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=zookeeper:2888:3888;2181
    ports:
      - "2181:2181"
    volumes:
      - zookeeper_data:/data
      - zookeeper_datalog:/datalog
    networks:
      - database_network
    healthcheck:
      test: ["CMD", "zkServer.sh", "status"]
      interval: 10s
      timeout: 5s
      retries: 5

  clickhouse:
    depends_on:
      zookeeper:
        condition: service_healthy
    environment:
      - CLICKHOUSE_DB=langfuse
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1
    volumes:
      - ./clickhouse_config:/etc/clickhouse-server/config.d:ro

  langfuse-web:
    environment:
      # ClickHouse with cluster support
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_CLUSTER=default
      - CLICKHOUSE_REPLICATED=true
    depends_on:
      zookeeper:
        condition: service_healthy

  langfuse-worker:
    environment:
      - CLICKHOUSE_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse:${CLICKHOUSE_PASSWORD}@clickhouse:9000/langfuse
      - CLICKHOUSE_HOST=clickhouse
      - CLICKHOUSE_PORT=9000
      - CLICKHOUSE_USER=langfuse
      - CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}
      - CLICKHOUSE_DATABASE=langfuse
      - CLICKHOUSE_PROTOCOL=native
      - CLICKHOUSE_CLUSTER=default
      - CLICKHOUSE_REPLICATED=true
    depends_on:
      zookeeper:
        condition: service_healthy

volumes:
  zookeeper_data:
    driver: local
  zookeeper_datalog:
    driver: local
EOF

# Create ClickHouse config with ZooKeeper
mkdir -p clickhouse_config

cat > clickhouse_config/config.xml << 'EOF'
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
    <listen_host>::</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    
    <zookeeper>
        <node>
            <host>zookeeper</host>
            <port>2181</port>
        </node>
    </zookeeper>
    
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
        <pool_size>1</pool_size>
        <max_queue_size>1000</max_queue_size>
    </distributed_ddl>
    
    <macros>
        <shard>01</shard>
        <replica>01</replica>
        <cluster>default</cluster>
    </macros>
    
    <remote_servers>
        <default>
            <shard>
                <internal_replication>true</internal_replication>
                <replica>
                    <host>clickhouse</host>
                    <port>9000</port>
                </replica>
            </shard>
        </default>
    </remote_servers>
</clickhouse>
EOF

# Start ZooKeeper first
log_info "Starting ZooKeeper..."
docker compose up -d zookeeper
sleep 15

# Start ClickHouse with new config
log_info "Starting ClickHouse with ZooKeeper support..."
docker compose up -d clickhouse
sleep 15

# Initialize database
log_info "Initializing ClickHouse..."
docker compose exec -T clickhouse clickhouse-client --user default --query "CREATE DATABASE IF NOT EXISTS langfuse;" || true
docker compose exec -T clickhouse clickhouse-client --user default --query "CREATE USER IF NOT EXISTS langfuse IDENTIFIED BY '${CLICKHOUSE_PASSWORD}';" || true
docker compose exec -T clickhouse clickhouse-client --user default --query "GRANT ALL ON langfuse.* TO langfuse;" || true

# Start Langfuse
log_info "Starting Langfuse..."
docker compose up -d langfuse-web langfuse-worker

log_success "ZooKeeper setup complete!"
log_info "Check logs with: docker compose logs -f langfuse-web langfuse-worker"
