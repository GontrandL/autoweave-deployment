#!/bin/bash

# AutoWeave Kubernetes Deployment Script
# Deploys all AutoWeave components to Kubernetes

set -e

echo "☸️  AutoWeave Kubernetes Deployment"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default values
NAMESPACE_MEMORY="autoweave-memory"
NAMESPACE_CORE="autoweave-core"
NAMESPACE_AGENTS="autoweave-agents"
CREATE_INGRESS=false
INGRESS_HOST="autoweave.local"
STORAGE_CLASS="standard"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ingress)
            CREATE_INGRESS=true
            shift
            ;;
        --ingress-host)
            INGRESS_HOST="$2"
            shift 2
            ;;
        --storage-class)
            STORAGE_CLASS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ingress          Create ingress resources"
            echo "  --ingress-host     Set ingress hostname (default: autoweave.local)"
            echo "  --storage-class    Set storage class (default: standard)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites${NC}"

if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}✗ kubectl is required but not installed${NC}"
    echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}✗ No Kubernetes cluster available${NC}"
    echo "Please configure kubectl to connect to a cluster"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster available${NC}"

# Get cluster info
CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep Server | cut -d' ' -f3)
echo "Cluster version: $CLUSTER_VERSION"

# Check for required resources
echo ""
echo -e "${YELLOW}📋 Checking cluster resources${NC}"

# Check storage classes
echo -n "Storage classes: "
if kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ $STORAGE_CLASS available${NC}"
else
    echo -e "${YELLOW}⚠ $STORAGE_CLASS not found, using default${NC}"
    STORAGE_CLASS=$(kubectl get storageclass -o json | jq -r '.items[0].metadata.name')
fi

# Create namespaces
echo ""
echo -e "${YELLOW}📋 Creating namespaces${NC}"

echo "Applying namespace configurations..."
kubectl apply -f "$BASE_DIR/k8s/namespace.yaml"

echo -e "${GREEN}✓ Namespaces created${NC}"

# Generate secrets
echo ""
echo -e "${YELLOW}📋 Generating secrets${NC}"

# Check if secrets already exist
if ! kubectl get secret autoweave-secrets -n "$NAMESPACE_CORE" >/dev/null 2>&1; then
    echo "Creating secrets..."
    
    # Load environment variables
    if [ -f "$BASE_DIR/.env" ]; then
        export $(cat "$BASE_DIR/.env" | grep -v '^#' | xargs)
    fi
    
    # Create core secrets
    kubectl create secret generic autoweave-secrets \
        --namespace="$NAMESPACE_CORE" \
        --from-literal=openai-api-key="${OPENAI_API_KEY:-}" \
        --from-literal=memgraph-password="${MEMGRAPH_PASSWORD:-memgraph}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Copy secrets to other namespaces
    kubectl get secret autoweave-secrets -n "$NAMESPACE_CORE" -o yaml | \
        sed "s/namespace: $NAMESPACE_CORE/namespace: $NAMESPACE_MEMORY/" | \
        kubectl apply -f -
    
    kubectl get secret autoweave-secrets -n "$NAMESPACE_CORE" -o yaml | \
        sed "s/namespace: $NAMESPACE_CORE/namespace: $NAMESPACE_AGENTS/" | \
        kubectl apply -f -
    
    echo -e "${GREEN}✓ Secrets created${NC}"
else
    echo -e "${BLUE}ℹ Secrets already exist${NC}"
fi

# Deploy memory system
echo ""
echo -e "${YELLOW}📋 Deploying memory system${NC}"

# Update storage class in manifests
if [ "$STORAGE_CLASS" != "standard" ]; then
    echo "Updating storage class to $STORAGE_CLASS..."
    find "$BASE_DIR/k8s/memory" -name "*.yaml" -exec sed -i.bak "s/storageClassName: standard/storageClassName: $STORAGE_CLASS/g" {} \;
fi

echo "Applying memory system manifests..."
kubectl apply -f "$BASE_DIR/k8s/memory/"

echo -e "${GREEN}✓ Memory system deployed${NC}"

# Wait for memory pods
echo ""
echo -e "${YELLOW}📋 Waiting for memory pods${NC}"

echo "Waiting for Qdrant..."
kubectl wait --for=condition=ready pod -l app=qdrant -n "$NAMESPACE_MEMORY" --timeout=300s || true

echo "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis -n "$NAMESPACE_MEMORY" --timeout=300s || true

echo "Waiting for Memgraph..."
kubectl wait --for=condition=ready pod -l app=memgraph -n "$NAMESPACE_MEMORY" --timeout=300s || true

# Deploy core services
echo ""
echo -e "${YELLOW}📋 Deploying core services${NC}"

# Create ConfigMap for AutoWeave configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: autoweave-config
  namespace: $NAMESPACE_CORE
data:
  NODE_ENV: "production"
  LOG_LEVEL: "info"
  PORT: "3000"
  HOST: "0.0.0.0"
  QDRANT_HOST: "qdrant-service.$NAMESPACE_MEMORY.svc.cluster.local"
  QDRANT_PORT: "6333"
  MEMGRAPH_HOST: "memgraph-service.$NAMESPACE_MEMORY.svc.cluster.local"
  MEMGRAPH_PORT: "7687"
  REDIS_HOST: "redis-service.$NAMESPACE_MEMORY.svc.cluster.local"
  REDIS_PORT: "6379"
  ANP_PORT: "8083"
  MCP_PORT: "3002"
  KAGENT_NAMESPACE: "$NAMESPACE_AGENTS"
EOF

echo -e "${GREEN}✓ Core configuration created${NC}"

# Create ingress if requested
if [ "$CREATE_INGRESS" = true ]; then
    echo ""
    echo -e "${YELLOW}📋 Creating ingress resources${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: autoweave-ingress
  namespace: $NAMESPACE_CORE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
spec:
  rules:
  - host: $INGRESS_HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: autoweave-core-service
            port:
              number: 3000
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: autoweave-core-service
            port:
              number: 3000
      - path: /anp
        pathType: Prefix
        backend:
          service:
            name: autoweave-anp-service
            port:
              number: 8083
EOF
    
    echo -e "${GREEN}✓ Ingress created for $INGRESS_HOST${NC}"
fi

# Show deployment status
echo ""
echo -e "${YELLOW}📋 Deployment Status${NC}"
echo ""

echo "Memory System Pods:"
kubectl get pods -n "$NAMESPACE_MEMORY" --no-headers | while read line; do
    echo "  $line"
done

echo ""
echo "Memory System Services:"
kubectl get services -n "$NAMESPACE_MEMORY" --no-headers | while read line; do
    echo "  $line"
done

echo ""
echo "Core System ConfigMaps:"
kubectl get configmaps -n "$NAMESPACE_CORE" --no-headers | while read line; do
    echo "  $line"
done

# Port forwarding instructions
echo ""
echo -e "${YELLOW}📋 Access Instructions${NC}"
echo ""

echo "To access services locally, use port-forward:"
echo ""
echo "# AutoWeave Core API:"
echo "kubectl port-forward -n $NAMESPACE_CORE svc/autoweave-core-service 3000:3000"
echo ""
echo "# Qdrant Dashboard:"
echo "kubectl port-forward -n $NAMESPACE_MEMORY svc/qdrant-service 6333:6333"
echo ""
echo "# Redis:"
echo "kubectl port-forward -n $NAMESPACE_MEMORY svc/redis-service 6379:6379"
echo ""
echo "# Memgraph:"
echo "kubectl port-forward -n $NAMESPACE_MEMORY svc/memgraph-service 7687:7687"

if [ "$CREATE_INGRESS" = true ]; then
    echo ""
    echo "# Ingress access:"
    echo "Add to /etc/hosts: <INGRESS_IP> $INGRESS_HOST"
    echo "Then access: http://$INGRESS_HOST"
fi

echo ""
echo "================================"
echo -e "${GREEN}✅ Kubernetes deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Deploy AutoWeave Core application"
echo "2. Set up monitoring (Prometheus/Grafana)"
echo "3. Configure backup schedule"
echo "4. Test the deployment with: $BASE_DIR/scripts/check-health.sh"