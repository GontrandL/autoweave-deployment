#!/bin/bash

# AutoWeave Health Check Script
# Checks the health of all AutoWeave components

set -e

echo "🏥 AutoWeave Health Check"
echo "========================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load environment variables
if [ -f "$BASE_DIR/.env" ]; then
    export $(cat "$BASE_DIR/.env" | grep -v '^#' | xargs)
fi

# Service check results
HEALTH_STATUS=0

# Function to check service health
check_service() {
    local service_name=$1
    local url=$2
    local expected_response=$3
    
    echo -n "Checking $service_name... "
    
    if response=$(curl -s -f -m 5 "$url" 2>/dev/null); then
        if [ -n "$expected_response" ]; then
            if echo "$response" | grep -q "$expected_response"; then
                echo -e "${GREEN}✓ Healthy${NC}"
                return 0
            else
                echo -e "${YELLOW}⚠ Unexpected response${NC}"
                HEALTH_STATUS=1
                return 1
            fi
        else
            echo -e "${GREEN}✓ Reachable${NC}"
            return 0
        fi
    else
        echo -e "${RED}✗ Unreachable${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

# Function to check port
check_port() {
    local service_name=$1
    local host=$2
    local port=$3
    
    echo -n "Checking $service_name on $host:$port... "
    
    if nc -z "$host" "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ Port open${NC}"
        return 0
    else
        echo -e "${RED}✗ Port closed${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

# Function to check process
check_process() {
    local process_name=$1
    local pid_file=$2
    
    echo -n "Checking $process_name process... "
    
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Running (PID: $pid)${NC}"
            return 0
        else
            echo -e "${RED}✗ Not running (stale PID file)${NC}"
            HEALTH_STATUS=1
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ PID file not found${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

echo -e "${YELLOW}📋 Core Services${NC}"
echo "----------------"

# Check AutoWeave Core
check_service "AutoWeave Core API" "http://localhost:${PORT:-3000}/api/health" "healthy"
check_service "AutoWeave Core Docs" "http://localhost:${PORT:-3000}/api/docs" ""

# Check ANP Server
check_service "ANP Server" "http://localhost:${ANP_PORT:-8083}/agent" "agentId"

# Check MCP Server
check_service "MCP Server" "http://localhost:${MCP_PORT:-3002}/mcp/v1/tools" ""

echo ""
echo -e "${YELLOW}📋 Memory Services${NC}"
echo "-----------------"

# Check Qdrant
check_service "Qdrant API" "http://localhost:${QDRANT_PORT:-6333}/collections" "result"
check_service "Qdrant Dashboard" "http://localhost:${QDRANT_PORT:-6333}/dashboard" ""

# Check Memgraph
check_port "Memgraph Bolt" "localhost" "${MEMGRAPH_PORT:-7687}"

# Check Redis
check_port "Redis" "localhost" "${REDIS_PORT:-6379}"
if command -v redis-cli >/dev/null 2>&1; then
    echo -n "Redis PING test... "
    if redis-cli -p "${REDIS_PORT:-6379}" ping | grep -q "PONG"; then
        echo -e "${GREEN}✓ PONG${NC}"
    else
        echo -e "${RED}✗ No PONG${NC}"
        HEALTH_STATUS=1
    fi
fi

echo ""
echo -e "${YELLOW}📋 Process Status${NC}"
echo "-----------------"

# Check processes
check_process "AutoWeave Core" "$BASE_DIR/autoweave-core.pid"
check_process "AutoWeave UI" "$BASE_DIR/autoweave-ui.pid"

echo ""
echo -e "${YELLOW}📋 Docker Services${NC}"
echo "------------------"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep autoweave || echo "No AutoWeave containers running"
else
    echo -e "${YELLOW}⚠ Docker not available${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Kubernetes Services${NC}"
echo "---------------------"

if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    echo "Kubernetes pods in autoweave-memory namespace:"
    kubectl get pods -n autoweave-memory --no-headers 2>/dev/null || echo "Namespace not found"
    
    echo ""
    echo "Kubernetes services:"
    kubectl get services -n autoweave-memory --no-headers 2>/dev/null || echo "No services found"
else
    echo -e "${YELLOW}⚠ Kubernetes not available${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Memory Usage${NC}"
echo "---------------"

# Check memory metrics from AutoWeave
if curl -s "http://localhost:${PORT:-3000}/api/memory/metrics" 2>/dev/null | jq . 2>/dev/null; then
    echo -e "${GREEN}✓ Memory metrics available${NC}"
else
    echo -e "${YELLOW}⚠ Memory metrics not available${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Log Files${NC}"
echo "------------"

# Check log files
for log_file in "$BASE_DIR/logs/autoweave-core.log" "$BASE_DIR/logs/autoweave-ui.log"; do
    if [ -f "$log_file" ]; then
        echo -n "$(basename "$log_file"): "
        tail -n 1 "$log_file" | head -c 80
        echo "..."
    fi
done

echo ""
echo "================================"

if [ $HEALTH_STATUS -eq 0 ]; then
    echo -e "${GREEN}✅ All systems healthy!${NC}"
else
    echo -e "${RED}❌ Some systems are unhealthy${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "1. Check if services are started: $BASE_DIR/start-autoweave.sh"
    echo "2. Check logs: tail -f $BASE_DIR/logs/*.log"
    echo "3. Check Docker: docker ps -a | grep autoweave"
    echo "4. Check environment: cat $BASE_DIR/.env"
    exit 1
fi