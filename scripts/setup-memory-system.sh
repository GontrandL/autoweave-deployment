#!/bin/bash

# Setup Memory System for AutoWeave
# Deploys Qdrant, Memgraph, and Redis

set -e

echo "🧠 Setting up AutoWeave Memory System"
echo "===================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites${NC}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker is required but not installed${NC}"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker daemon is not running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker is available${NC}"

# Deployment method selection
echo ""
echo -e "${YELLOW}Select deployment method:${NC}"
echo "1) Docker Compose (recommended for development)"
echo "2) Kubernetes (recommended for production)"
echo "3) Both"
read -p "Choice (1-3): " DEPLOY_CHOICE

case $DEPLOY_CHOICE in
    1)
        DEPLOY_DOCKER=true
        DEPLOY_K8S=false
        ;;
    2)
        DEPLOY_DOCKER=false
        DEPLOY_K8S=true
        ;;
    3)
        DEPLOY_DOCKER=true
        DEPLOY_K8S=true
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Docker Compose deployment
if [ "$DEPLOY_DOCKER" = true ]; then
    echo ""
    echo -e "${YELLOW}📋 Deploying with Docker Compose${NC}"
    
    if [ ! -f "$BASE_DIR/docker/docker-compose.yml" ]; then
        echo -e "${BLUE}Creating docker-compose.yml...${NC}"
        mkdir -p "$BASE_DIR/docker"
        cat > "$BASE_DIR/docker/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: autoweave-qdrant
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage
    environment:
      - QDRANT__SERVICE__HTTP_PORT=6333
    restart: unless-stopped
    networks:
      - autoweave-network

  memgraph:
    image: memgraph/memgraph:latest
    container_name: autoweave-memgraph
    ports:
      - "7687:7687"
      - "3001:3000"
    volumes:
      - memgraph_data:/var/lib/memgraph
    environment:
      - MEMGRAPH_USER=memgraph
      - MEMGRAPH_PASSWORD=memgraph
    command: ["--log-level=INFO"]
    restart: unless-stopped
    networks:
      - autoweave-network

  redis:
    image: redis:7-alpine
    container_name: autoweave-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    restart: unless-stopped
    networks:
      - autoweave-network

  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: autoweave-redis-commander
    ports:
      - "8081:8081"
    environment:
      - REDIS_HOSTS=local:redis:6379
    depends_on:
      - redis
    restart: unless-stopped
    networks:
      - autoweave-network

volumes:
  qdrant_data:
  memgraph_data:
  redis_data:

networks:
  autoweave-network:
    driver: bridge
EOF
    fi
    
    # Create Redis ML configuration
    if [ ! -f "$BASE_DIR/docker/redis-ml.yml" ]; then
        cat > "$BASE_DIR/docker/redis-ml.yml" << 'EOF'
version: '3.8'

services:
  redis-ml:
    image: redislabs/redisai:latest
    container_name: autoweave-redis-ml
    ports:
      - "6380:6379"
    volumes:
      - redis_ml_data:/data
    restart: unless-stopped
    networks:
      - autoweave-network

volumes:
  redis_ml_data:

networks:
  autoweave-network:
    external: true
EOF
    fi
    
    echo -e "${BLUE}Starting Docker containers...${NC}"
    cd "$BASE_DIR/docker"
    docker-compose up -d
    
    # Wait for services
    echo -e "${BLUE}Waiting for services to start...${NC}"
    sleep 10
    
    # Check services
    echo -e "${BLUE}Checking services...${NC}"
    docker-compose ps
    
    echo -e "${GREEN}✓ Docker Compose deployment complete${NC}"
fi

# Kubernetes deployment
if [ "$DEPLOY_K8S" = true ]; then
    echo ""
    echo -e "${YELLOW}📋 Deploying to Kubernetes${NC}"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl is required but not installed${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ No Kubernetes cluster available${NC}"
        echo "Please configure kubectl to connect to a cluster"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Kubernetes cluster available${NC}"
    
    # Create namespace
    echo -e "${BLUE}Creating namespace...${NC}"
    kubectl create namespace autoweave-memory --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply manifests
    if [ -d "$BASE_DIR/k8s/memory" ]; then
        echo -e "${BLUE}Applying Kubernetes manifests...${NC}"
        kubectl apply -f "$BASE_DIR/k8s/memory/"
        
        # Wait for pods
        echo -e "${BLUE}Waiting for pods to be ready...${NC}"
        kubectl wait --for=condition=ready pod -l app=qdrant -n autoweave-memory --timeout=300s || true
        kubectl wait --for=condition=ready pod -l app=memgraph -n autoweave-memory --timeout=300s || true
        kubectl wait --for=condition=ready pod -l app=redis -n autoweave-memory --timeout=300s || true
        
        # Show status
        echo -e "${BLUE}Pod status:${NC}"
        kubectl get pods -n autoweave-memory
        
        echo -e "${BLUE}Services:${NC}"
        kubectl get services -n autoweave-memory
    else
        echo -e "${YELLOW}⚠ Kubernetes manifests not found in k8s/memory/${NC}"
        echo "Creating basic manifests..."
        mkdir -p "$BASE_DIR/k8s/memory"
        
        # We'll need to copy the k8s manifests from the memory module
        if [ -d "$BASE_DIR/modules/autoweave-memory/k8s/memory" ]; then
            cp -r "$BASE_DIR/modules/autoweave-memory/k8s/memory/"* "$BASE_DIR/k8s/memory/"
            kubectl apply -f "$BASE_DIR/k8s/memory/"
        else
            echo -e "${YELLOW}⚠ Memory module k8s manifests not found${NC}"
        fi
    fi
    
    echo -e "${GREEN}✓ Kubernetes deployment complete${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Memory system setup complete!${NC}"
echo ""
echo -e "${BLUE}📊 Service URLs:${NC}"

if [ "$DEPLOY_DOCKER" = true ]; then
    echo -e "${BLUE}Docker Services:${NC}"
    echo "  • Qdrant: http://localhost:6333/dashboard"
    echo "  • Memgraph: bolt://localhost:7687"
    echo "  • Redis: localhost:6379"
    echo "  • Redis Commander: http://localhost:8081"
fi

if [ "$DEPLOY_K8S" = true ]; then
    echo ""
    echo -e "${BLUE}Kubernetes Services:${NC}"
    echo "To access services, use port-forward:"
    echo "  kubectl port-forward -n autoweave-memory svc/qdrant-service 6333:6333"
    echo "  kubectl port-forward -n autoweave-memory svc/memgraph-service 7687:7687"
    echo "  kubectl port-forward -n autoweave-memory svc/redis-service 6379:6379"
fi

echo ""
echo -e "${BLUE}🔍 Testing connections:${NC}"

# Test Qdrant
if curl -s http://localhost:6333/collections | grep -q "result"; then
    echo -e "${GREEN}✓ Qdrant is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Qdrant not accessible on port 6333${NC}"
fi

# Test Redis
if command -v redis-cli >/dev/null 2>&1; then
    if redis-cli -p 6379 ping | grep -q "PONG"; then
        echo -e "${GREEN}✓ Redis is accessible${NC}"
    else
        echo -e "${YELLOW}⚠ Redis not accessible on port 6379${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Memory system is ready for AutoWeave!${NC}"