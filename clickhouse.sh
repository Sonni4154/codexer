#!/bin/bash

# Clean ClickHouse Configuration
echo "Fixing ClickHouse configuration..."

# Backup existing config
mkdir -p clickhouse_config_backup
mv clickhouse_config/* clickhouse_config_backup/ 2>/dev/null

# Create minimal config files
mkdir -p clickhouse_config

# Main config
cat > clickhouse_config/config.xml << 'EOF'
<clickhouse>
    <listen_host>0.0.0.0</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    
    <logger>
        <level>warning</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>
</clickhouse>
EOF

# Users config
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
    </users>
</clickhouse>
EOF

# Restart ClickHouse
docker compose restart clickhouse

echo "ClickHouse reconfigured. Check logs:"
docker compose logs --tail=50 clickhouse
