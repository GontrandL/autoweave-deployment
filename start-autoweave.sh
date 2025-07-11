#!/bin/bash

# AutoWeave Start Script
# This script starts the AutoWeave ecosystem

set -e

echo "🚀 Starting AutoWeave Ecosystem"
echo "=============================="
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
check_service() {
    local service=$1
    local port=$2
    
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ $service is running on port $port${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ $service is not running on port $port${NC}"
        return 1
    fi
}

# Function to wait for service
wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=0
    
    echo -n "Waiting for $service to start"
    while ! nc -z localhost "$port" 2>/dev/null; do
        if [ $attempt -eq $max_attempts ]; then
            echo -e "\n${RED}✗ $service failed to start after $max_attempts seconds${NC}"
            return 1
        fi
        echo -n "."
        sleep 1
        ((attempt++))
    done
    echo -e "\n${GREEN}✓ $service started successfully${NC}"
    return 0
}

echo -e "${YELLOW}📋 Step 1: Checking dependencies${NC}"
echo ""

# Check if modules are installed
if [ ! -d "$MODULES_DIR/autoweave-core" ]; then
    echo -e "${YELLOW}⚠ AutoWeave core module not found${NC}"
    echo -e "${YELLOW}  Please run install.sh to install all modules${NC}"
    echo -e "${YELLOW}  Or create the modules manually${NC}"
    exit 1
fi

echo -e "${GREEN}✓ AutoWeave modules found${NC}"

echo ""
echo -e "${YELLOW}📋 Step 2: Starting infrastructure services${NC}"
echo ""

# Detect deployment method
DEPLOYMENT_METHOD=""
USE_KUBERNETES=false
USE_DOCKER=false

# Check if services are already running in Kubernetes
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    if kubectl get pods -n autoweave-memory 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✓ Memory services detected in Kubernetes${NC}"
        USE_KUBERNETES=true
        DEPLOYMENT_METHOD="kubernetes"
    fi
fi

# Check if services are already running in Docker
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker ps 2>/dev/null | grep -q "autoweave-"; then
        echo -e "${GREEN}✓ Memory services detected in Docker${NC}"
        USE_DOCKER=true
        DEPLOYMENT_METHOD="docker"
    fi
fi

# If no services are running, ask user for preference
if [ "$DEPLOYMENT_METHOD" = "" ]; then
    echo -e "${YELLOW}Select deployment method:${NC}"
    echo "1) Kubernetes (recommended for production)"
    echo "2) Docker Compose (recommended for development)"
    echo "3) Skip memory services (not recommended)"
    read -p "Choice (1-3): " DEPLOY_CHOICE
    
    case $DEPLOY_CHOICE in
        1)
            if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
                USE_KUBERNETES=true
                DEPLOYMENT_METHOD="kubernetes"
            else
                echo -e "${RED}✗ Kubernetes not available${NC}"
                exit 1
            fi
            ;;
        2)
            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                USE_DOCKER=true
                DEPLOYMENT_METHOD="docker"
            else
                echo -e "${RED}✗ Docker not available${NC}"
                exit 1
            fi
            ;;
        3)
            echo -e "${YELLOW}⚠ Running without memory persistence${NC}"
            DEPLOYMENT_METHOD="none"
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
fi

# Start services based on deployment method
if [ "$USE_DOCKER" = true ]; then
    # Start Docker services
    if [ -f "$BASE_DIR/docker/docker-compose.yml" ]; then
        echo -e "${BLUE}Starting memory systems with Docker Compose...${NC}"
        docker-compose -f "$BASE_DIR/docker/docker-compose.yml" up -d
        
        # Wait for services
        wait_for_service "Qdrant" "${QDRANT_PORT:-6333}"
        wait_for_service "Redis" "${REDIS_PORT:-6379}"
    else
        echo -e "${YELLOW}⚠ docker-compose.yml not found${NC}"
    fi
elif [ "$USE_KUBERNETES" = true ]; then
    echo -e "${BLUE}Using Kubernetes deployment${NC}"
    echo -e "${YELLOW}Setting up port-forwards...${NC}"
    
    # Kill any existing port-forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Start port-forwards in background
    kubectl port-forward -n autoweave-memory service/qdrant-service ${QDRANT_PORT:-6333}:6333 >/dev/null 2>&1 &
    kubectl port-forward -n autoweave-memory service/redis-service ${REDIS_PORT:-6379}:6379 >/dev/null 2>&1 &
    
    # Wait a moment for port-forwards to establish
    sleep 3
    
    # Test connections
    wait_for_service "Qdrant" "${QDRANT_PORT:-6333}"
    wait_for_service "Redis" "${REDIS_PORT:-6379}"
fi


echo ""
echo -e "${YELLOW}📋 Step 3: Starting AutoWeave Core${NC}"
echo ""

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

# Start in background with logging
nohup npm start > "$BASE_DIR/logs/autoweave-core.log" 2>&1 &
CORE_PID=$!

echo "AutoWeave Core started with PID: $CORE_PID"
echo $CORE_PID > "$BASE_DIR/autoweave-core.pid"

# Wait for core service to start
wait_for_service "AutoWeave Core" "${PORT:-3000}"

echo ""
echo -e "${YELLOW}📋 Step 4: Starting additional services${NC}"
echo ""

# Start UI service if available
if [ -d "$MODULES_DIR/autoweave-ui" ]; then
    echo -e "${BLUE}Starting UI service...${NC}"
    cd "$MODULES_DIR/autoweave-ui"
    nohup npm start > "$BASE_DIR/logs/autoweave-ui.log" 2>&1 &
    UI_PID=$!
    echo $UI_PID > "$BASE_DIR/autoweave-ui.pid"
fi

# Install CLI globally if available
if [ -d "$MODULES_DIR/autoweave-cli" ]; then
    echo -e "${BLUE}Installing AutoWeave CLI...${NC}"
    cd "$MODULES_DIR/autoweave-cli"
    npm link
    echo -e "${GREEN}✓ AutoWeave CLI installed globally${NC}"
fi

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
echo -e "${GREEN}🎉 AutoWeave is running!${NC}"
echo ""
echo -e "${BLUE}📍 Access Points:${NC}"
echo "  • API: http://localhost:${PORT:-3000}"
echo "  • Health: http://localhost:${PORT:-3000}/api/health"
echo "  • Docs: http://localhost:${PORT:-3000}/api/docs"
echo ""
echo -e "${BLUE}📊 Infrastructure:${NC}"
check_service "Qdrant" "${QDRANT_PORT:-6333}" && echo "  • Qdrant UI: http://localhost:${QDRANT_PORT:-6333}/dashboard"
check_service "Redis" "${REDIS_PORT:-6379}" && echo "  • Redis: localhost:${REDIS_PORT:-6379}"
echo ""
echo -e "${BLUE}📝 Logs:${NC}"
echo "  • Core: tail -f $BASE_DIR/logs/autoweave-core.log"
echo "  • UI: tail -f $BASE_DIR/logs/autoweave-ui.log"
echo ""
echo -e "${BLUE}🛑 To stop AutoWeave:${NC}"
echo "  $BASE_DIR/stop-autoweave.sh"
echo ""
echo -e "${GREEN}Happy agent weaving! 🚀${NC}"