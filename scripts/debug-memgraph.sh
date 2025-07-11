#!/bin/bash

# Debug Memgraph Issues
# This script helps diagnose and fix Memgraph deployment problems

set -e

echo "🔍 Memgraph Debugging Script"
echo "=========================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

NAMESPACE="autoweave-memory"

echo -e "${YELLOW}📋 Step 1: Checking Memgraph pod status${NC}"
echo ""

# Get pod status
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=memgraph -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}✗ No Memgraph pod found${NC}"
    echo "Try deploying with: kubectl apply -f k8s/memory/memgraph.yaml"
    exit 1
fi

echo -e "${BLUE}Pod name: $POD_NAME${NC}"

# Get pod status
POD_STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
echo -e "${BLUE}Pod status: $POD_STATUS${NC}"

# Get restart count
RESTART_COUNT=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo -e "${BLUE}Restart count: $RESTART_COUNT${NC}"

echo ""
echo -e "${YELLOW}📋 Step 2: Checking recent events${NC}"
echo ""

kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$POD_NAME --sort-by='.lastTimestamp' | tail -10

echo ""
echo -e "${YELLOW}📋 Step 3: Checking pod logs${NC}"
echo ""

echo "Last 20 lines of logs:"
kubectl logs $POD_NAME -n $NAMESPACE --tail=20 2>/dev/null || echo "No logs available"

# Check previous logs if crashed
if [ "$POD_STATUS" = "CrashLoopBackOff" ] || [ "$RESTART_COUNT" -gt "0" ]; then
    echo ""
    echo -e "${YELLOW}Previous container logs:${NC}"
    kubectl logs $POD_NAME -n $NAMESPACE --previous --tail=20 2>/dev/null || echo "No previous logs available"
fi

echo ""
echo -e "${YELLOW}📋 Step 4: Checking pod description${NC}"
echo ""

kubectl describe pod $POD_NAME -n $NAMESPACE | grep -A 10 "Conditions:" || true
kubectl describe pod $POD_NAME -n $NAMESPACE | grep -A 20 "Events:" || true

echo ""
echo -e "${YELLOW}📋 Step 5: Testing fixes${NC}"
echo ""

echo "1. Try the minimal deployment:"
echo -e "${BLUE}kubectl delete pod $POD_NAME -n $NAMESPACE${NC}"
echo -e "${BLUE}kubectl apply -f k8s/memory/memgraph-minimal.yaml${NC}"
echo ""

echo "2. Or try running Memgraph with debug mode:"
echo -e "${BLUE}kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/bash${NC}"
echo "Then run:"
echo -e "${BLUE}/usr/lib/memgraph/memgraph --help${NC}"
echo ""

echo "3. Check system compatibility:"
echo -e "${BLUE}kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/cpuinfo | grep flags | head -1${NC}"
echo ""

# Check if SSE4.2 is supported (required by Memgraph)
echo -e "${YELLOW}Checking CPU features...${NC}"
kubectl exec $POD_NAME -n $NAMESPACE -- sh -c 'cat /proc/cpuinfo | grep -q sse4_2 && echo "✓ SSE4.2 supported" || echo "✗ SSE4.2 NOT supported"' 2>/dev/null || echo "Cannot check CPU features"

echo ""
echo -e "${YELLOW}📋 Step 6: Alternative solutions${NC}"
echo ""

echo "If Memgraph continues to fail, consider:"
echo "1. Using the minimal deployment (memgraph-minimal.yaml)"
echo "2. Running Memgraph outside Kubernetes with Docker:"
echo -e "${BLUE}docker run -p 7687:7687 -p 3000:3000 memgraph/memgraph:2.11.1${NC}"
echo ""
echo "3. Using Memgraph Platform instead (includes Memgraph Lab):"
echo -e "${BLUE}docker run -p 7687:7687 -p 3000:3000 memgraph/memgraph-platform:2.11.1${NC}"

echo ""
echo -e "${GREEN}Debug information collected!${NC}"