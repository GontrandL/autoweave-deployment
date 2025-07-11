#!/bin/bash

# AutoWeave Start Script for Kubernetes Deployment
# This script starts AutoWeave with Kubernetes backend

set -e

echo "🚀 Starting AutoWeave with Kubernetes Backend"
echo "==========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$BASE_DIR/modules"

# Load environment variables
if [ -f "$BASE_DIR/.env" ]; then
    export $(cat "$BASE_DIR/.env" | grep -v '^#' | xargs)
else
    echo -e "${RED}✗ .env file not found. Please run install.sh first.${NC}"
    exit 1
fi

# Check if OPENAI_API_KEY is set
if [ "$OPENAI_API_KEY" = "YOUR_OPENAI_API_KEY_HERE" ] || [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}✗ OPENAI_API_KEY not configured in .env file${NC}"
    echo "Please edit $BASE_DIR/.env and add your OpenAI API key"
    exit 1
fi

# Function to check if service is running
check_k8s_service() {
    local service=$1
    local namespace=$2
    
    if kubectl get service "$service" -n "$namespace" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $service service exists in namespace $namespace${NC}"
        return 0
    else
        echo -e "${RED}✗ $service service not found in namespace $namespace${NC}"
        return 1
    fi
}

# Function to wait for pod
wait_for_pod() {
    local label=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo -n "Waiting for pod with label $label"
    if kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        return 1
    fi
}

echo -e "${YELLOW}📋 Step 1: Checking Kubernetes cluster${NC}"
echo ""

# Check kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}✗ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check cluster access
CLUSTER_CONTEXT=$(kubectl config current-context 2>/dev/null)
if [ -z "$CLUSTER_CONTEXT" ]; then
    echo -e "${RED}✗ No kubectl context found${NC}"
    echo "Please configure kubectl to connect to a cluster"
    exit 1
fi

# Try to get cluster info
if ! kubectl cluster-info >/dev/null 2>&1; then
    # Try with specific context if it's a kind cluster
    if [[ "$CLUSTER_CONTEXT" == *"kind"* ]]; then
        if ! kubectl cluster-info --context "$CLUSTER_CONTEXT" >/dev/null 2>&1; then
            echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
            echo "Please ensure kubectl is configured correctly"
            exit 1
        fi
    else
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        echo "Please ensure kubectl is configured correctly"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"

# Get cluster info
echo -e "${BLUE}Cluster: $CLUSTER_CONTEXT${NC}"

echo ""
echo -e "${YELLOW}📋 Step 2: Checking memory services${NC}"
echo ""

# Check if namespace exists
if ! kubectl get namespace autoweave-memory >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating namespace autoweave-memory...${NC}"
    kubectl create namespace autoweave-memory
fi

# Check services
SERVICES_OK=true
check_k8s_service "qdrant-service" "autoweave-memory" || SERVICES_OK=false
check_k8s_service "redis-service" "autoweave-memory" || SERVICES_OK=false
check_k8s_service "memgraph-service" "autoweave-memory" || SERVICES_OK=false

if [ "$SERVICES_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}Some services are missing. Deploying memory infrastructure...${NC}"
    
    if [ -d "$BASE_DIR/k8s/memory" ]; then
        kubectl apply -f "$BASE_DIR/k8s/namespace.yaml"
        kubectl apply -f "$BASE_DIR/k8s/memory/"
        
        # Wait for pods
        echo ""
        echo -e "${BLUE}Waiting for pods to be ready...${NC}"
        wait_for_pod "app=qdrant" "autoweave-memory" || true
        wait_for_pod "app=redis" "autoweave-memory" || true
        wait_for_pod "app=memgraph" "autoweave-memory" || true
    else
        echo -e "${RED}✗ k8s/memory directory not found${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}📋 Step 3: Setting up port forwards${NC}"
echo ""

# Kill existing port-forwards
echo "Cleaning up existing port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Function to create port-forward
create_port_forward() {
    local service=$1
    local port=$2
    local namespace=$3
    
    echo -e "${BLUE}Creating port-forward for $service on port $port...${NC}"
    kubectl port-forward -n "$namespace" "service/$service" "$port:$port" >/dev/null 2>&1 &
    local pid=$!
    echo $pid >> "$BASE_DIR/.port-forwards.pids"
    
    # Wait for port to be available
    local attempts=0
    while ! nc -z localhost "$port" 2>/dev/null; do
        if [ $attempts -gt 10 ]; then
            echo -e "${YELLOW}⚠ Port-forward for $service might not be working${NC}"
            return 1
        fi
        sleep 1
        ((attempts++))
    done
    
    echo -e "${GREEN}✓ Port-forward established for $service${NC}"
    return 0
}

# Create PID file for port-forwards
rm -f "$BASE_DIR/.port-forwards.pids"
touch "$BASE_DIR/.port-forwards.pids"

# Create port-forwards
create_port_forward "qdrant-service" "${QDRANT_PORT:-6333}" "autoweave-memory"
create_port_forward "redis-service" "${REDIS_PORT:-6379}" "autoweave-memory"
create_port_forward "memgraph-service" "${MEMGRAPH_PORT:-7687}" "autoweave-memory" || true

echo ""
echo -e "${YELLOW}📋 Step 4: Starting AutoWeave Core${NC}"
echo ""

# Check if modules are installed
if [ ! -d "$MODULES_DIR/autoweave-core" ]; then
    echo -e "${YELLOW}⚠ AutoWeave core module not found${NC}"
    echo -e "${YELLOW}  Creating mock module for testing...${NC}"
    
    # Create mock autoweave-core module
    mkdir -p "$MODULES_DIR/autoweave-core"
    cat > "$MODULES_DIR/autoweave-core/package.json" << EOF
{
  "name": "@autoweave/core",
  "version": "0.0.1",
  "description": "Mock AutoWeave Core for testing",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {}
}
EOF
    
    # Create mock server
    cat > "$MODULES_DIR/autoweave-core/index.js" << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  console.log(`Request: ${req.method} ${req.url}`);
  
  if (req.url === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      message: 'AutoWeave Mock Core is running',
      timestamp: new Date().toISOString(),
      version: '0.0.1-mock'
    }));
  } else if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('AutoWeave Mock Core - Real module not yet available\n');
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found\n');
  }
});

server.listen(port, () => {
  console.log(`AutoWeave Mock Core listening on port ${port}`);
  console.log('This is a mock server. Please install the real autoweave-core module.');
});
EOF
    
    echo -e "${GREEN}✓ Created mock autoweave-core module${NC}"
fi

# Check if package.json has start script
if [ -f "$MODULES_DIR/autoweave-core/package.json" ]; then
    if ! grep -q '"start"' "$MODULES_DIR/autoweave-core/package.json"; then
        echo -e "${YELLOW}⚠ No start script found in autoweave-core${NC}"
        echo -e "${RED}✗ Cannot start AutoWeave Core${NC}"
        exit 1
    fi
fi

# Prepare core module
cd "$MODULES_DIR/autoweave-core"

# Link other modules
echo -e "${BLUE}Linking AutoWeave modules...${NC}"
npm link "$MODULES_DIR/autoweave-memory" 2>/dev/null || true
npm link "$MODULES_DIR/autoweave-integrations" 2>/dev/null || true
npm link "$MODULES_DIR/autoweave-agents" 2>/dev/null || true

# Create logs directory
mkdir -p "$BASE_DIR/logs"

# Start the core service
echo -e "${BLUE}Starting AutoWeave Core service...${NC}"

# Export all environment variables for the core service
export NODE_ENV="${NODE_ENV:-production}"
export PORT="${PORT:-3000}"
export HOST="${HOST:-0.0.0.0}"
export LOG_LEVEL="${LOG_LEVEL:-info}"
export AUTOWEAVE_DATA_DIR="$BASE_DIR/data"
export AUTOWEAVE_LOGS_DIR="$BASE_DIR/logs"
export DEPLOYMENT_METHOD="kubernetes"

# Start in background with logging
nohup npm start > "$BASE_DIR/logs/autoweave-core.log" 2>&1 &
CORE_PID=$!

echo "AutoWeave Core started with PID: $CORE_PID"
echo $CORE_PID > "$BASE_DIR/autoweave-core.pid"

# Wait for core service to start
echo -n "Waiting for AutoWeave Core to start"
attempts=0
while ! nc -z localhost "${PORT:-3000}" 2>/dev/null; do
    if [ $attempts -gt 30 ]; then
        echo -e "\n${RED}✗ AutoWeave Core failed to start${NC}"
        echo "Check logs: tail -f $BASE_DIR/logs/autoweave-core.log"
        exit 1
    fi
    echo -n "."
    sleep 1
    ((attempts++))
done
echo -e "\n${GREEN}✓ AutoWeave Core started successfully${NC}"

echo ""
echo -e "${YELLOW}📋 Step 5: Health check${NC}"
echo ""

# Perform health check
sleep 2
HEALTH_URL="http://localhost:${PORT:-3000}/api/health"
echo "Checking health at $HEALTH_URL..."

if curl -s "$HEALTH_URL" | grep -q "healthy"; then
    echo -e "${GREEN}✓ AutoWeave is healthy!${NC}"
else
    echo -e "${YELLOW}⚠ Health check failed, but service might still be starting...${NC}"
fi

echo ""
echo -e "${GREEN}🎉 AutoWeave is running with Kubernetes backend!${NC}"
echo ""
echo -e "${BLUE}📍 Access Points:${NC}"
echo "  • API: http://localhost:${PORT:-3000}"
echo "  • Health: http://localhost:${PORT:-3000}/api/health"
echo "  • Docs: http://localhost:${PORT:-3000}/api/docs"
echo ""
echo -e "${BLUE}📊 Infrastructure (via port-forward):${NC}"
echo "  • Qdrant UI: http://localhost:${QDRANT_PORT:-6333}/dashboard"
echo "  • Redis: localhost:${REDIS_PORT:-6379}"
echo "  • Memgraph: bolt://localhost:${MEMGRAPH_PORT:-7687}"
echo ""
echo -e "${BLUE}🎮 Kubernetes Commands:${NC}"
echo "  • View pods: kubectl get pods -n autoweave-memory"
echo "  • View logs: kubectl logs -n autoweave-memory <pod-name>"
echo "  • Get services: kubectl get svc -n autoweave-memory"
echo ""
echo -e "${BLUE}📝 Logs:${NC}"
echo "  • Core: tail -f $BASE_DIR/logs/autoweave-core.log"
echo ""
echo -e "${BLUE}🛑 To stop AutoWeave:${NC}"
echo "  $BASE_DIR/stop-autoweave.sh"
echo ""
echo -e "${YELLOW}⚠ Note: Port-forwards are running in background${NC}"
echo "  PIDs stored in: $BASE_DIR/.port-forwards.pids"
echo ""
echo -e "${GREEN}Happy agent weaving! 🚀${NC}"