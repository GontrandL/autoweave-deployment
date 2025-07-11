#!/bin/bash

# AutoWeave Memory Backup Script
# Creates backups of all memory system data

set -e

echo "💾 AutoWeave Memory Backup"
echo "========================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$BASE_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"

# Load environment variables
if [ -f "$BASE_DIR/.env" ]; then
    export $(cat "$BASE_DIR/.env" | grep -v '^#' | xargs)
fi

# Create backup directory
mkdir -p "$BACKUP_PATH"

echo -e "${YELLOW}📋 Backup Configuration${NC}"
echo "Backup directory: $BACKUP_PATH"
echo ""

# Function to backup Docker volume
backup_docker_volume() {
    local volume_name=$1
    local backup_name=$2
    
    echo -n "Backing up Docker volume $volume_name... "
    
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
        docker run --rm \
            -v "$volume_name:/source:ro" \
            -v "$BACKUP_PATH:/backup" \
            alpine \
            tar czf "/backup/$backup_name.tar.gz" -C /source .
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Done${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ Volume not found${NC}"
        return 1
    fi
}

# Function to backup Kubernetes PVC
backup_k8s_pvc() {
    local namespace=$1
    local pvc_name=$2
    local backup_name=$3
    
    echo -n "Backing up K8s PVC $pvc_name... "
    
    if kubectl get pvc "$pvc_name" -n "$namespace" >/dev/null 2>&1; then
        # Create a backup pod
        cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: backup-pod-$TIMESTAMP
  namespace: $namespace
spec:
  containers:
  - name: backup
    image: alpine
    command: ['sleep', '3600']
    volumeMounts:
    - name: source
      mountPath: /source
      readOnly: true
  volumes:
  - name: source
    persistentVolumeClaim:
      claimName: $pvc_name
EOF
        
        # Wait for pod to be ready
        kubectl wait --for=condition=ready pod/backup-pod-$TIMESTAMP -n "$namespace" --timeout=60s >/dev/null 2>&1
        
        # Create backup
        kubectl exec -n "$namespace" backup-pod-$TIMESTAMP -- tar czf - -C /source . > "$BACKUP_PATH/$backup_name.tar.gz"
        
        # Clean up
        kubectl delete pod backup-pod-$TIMESTAMP -n "$namespace" >/dev/null 2>&1
        
        echo -e "${GREEN}✓ Done${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ PVC not found${NC}"
        return 1
    fi
}

# Function to backup Qdrant
backup_qdrant() {
    echo -e "${BLUE}Backing up Qdrant...${NC}"
    
    # Check if Qdrant is accessible
    if curl -s "http://localhost:${QDRANT_PORT:-6333}/collections" >/dev/null 2>&1; then
        # Create snapshot
        echo -n "Creating Qdrant snapshot... "
        
        response=$(curl -s -X POST "http://localhost:${QDRANT_PORT:-6333}/snapshots")
        snapshot_name=$(echo "$response" | jq -r '.result.name' 2>/dev/null)
        
        if [ -n "$snapshot_name" ] && [ "$snapshot_name" != "null" ]; then
            echo -e "${GREEN}✓ Snapshot created: $snapshot_name${NC}"
            
            # Download snapshot
            echo -n "Downloading snapshot... "
            curl -s "http://localhost:${QDRANT_PORT:-6333}/snapshots/$snapshot_name" \
                -o "$BACKUP_PATH/qdrant_snapshot_$snapshot_name" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Done${NC}"
            else
                echo -e "${RED}✗ Failed${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to create snapshot${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Qdrant not accessible${NC}"
    fi
}

# Function to backup Redis
backup_redis() {
    echo -e "${BLUE}Backing up Redis...${NC}"
    
    if command -v redis-cli >/dev/null 2>&1; then
        # Trigger BGSAVE
        echo -n "Creating Redis dump... "
        redis-cli -p "${REDIS_PORT:-6379}" BGSAVE >/dev/null 2>&1
        
        # Wait for save to complete
        while [ "$(redis-cli -p "${REDIS_PORT:-6379}" LASTSAVE)" = "$(redis-cli -p "${REDIS_PORT:-6379}" LASTSAVE)" ]; do
            sleep 1
        done
        
        echo -e "${GREEN}✓ Done${NC}"
        
        # Copy dump file
        if command -v docker >/dev/null 2>&1 && docker ps | grep -q autoweave-redis; then
            echo -n "Copying Redis dump... "
            docker cp autoweave-redis:/data/dump.rdb "$BACKUP_PATH/redis_dump.rdb" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Done${NC}"
            else
                echo -e "${RED}✗ Failed${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Redis CLI not available${NC}"
    fi
}

# Function to backup Memgraph
backup_memgraph() {
    echo -e "${BLUE}Backing up Memgraph...${NC}"
    
    # Check if we can connect to Memgraph
    if nc -z localhost "${MEMGRAPH_PORT:-7687}" 2>/dev/null; then
        echo -n "Creating Memgraph dump... "
        
        # Use mgconsole or cypher-shell if available
        if command -v mgconsole >/dev/null 2>&1; then
            mgconsole --host localhost --port "${MEMGRAPH_PORT:-7687}" \
                --output-format=csv \
                --execute "CALL mg.dump_database()" > "$BACKUP_PATH/memgraph_dump.cypher" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Done${NC}"
            else
                echo -e "${RED}✗ Failed${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ mgconsole not available${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Memgraph not accessible${NC}"
    fi
}

echo -e "${YELLOW}📋 Starting backup process${NC}"
echo ""

# Determine deployment type
if docker ps | grep -q autoweave; then
    echo -e "${BLUE}Docker deployment detected${NC}"
    echo ""
    
    # Backup Docker volumes
    backup_docker_volume "autoweave-deployment_qdrant_data" "qdrant_volume"
    backup_docker_volume "autoweave-deployment_memgraph_data" "memgraph_volume"
    backup_docker_volume "autoweave-deployment_redis_data" "redis_volume"
    
elif kubectl get namespace autoweave-memory >/dev/null 2>&1; then
    echo -e "${BLUE}Kubernetes deployment detected${NC}"
    echo ""
    
    # Backup Kubernetes PVCs
    backup_k8s_pvc "autoweave-memory" "qdrant-pvc" "qdrant_pvc"
    backup_k8s_pvc "autoweave-memory" "memgraph-pvc" "memgraph_pvc"
    backup_k8s_pvc "autoweave-memory" "redis-pvc" "redis_pvc"
fi

echo ""
echo -e "${YELLOW}📋 Service-specific backups${NC}"
echo ""

# Backup individual services
backup_qdrant
backup_redis
backup_memgraph

echo ""
echo -e "${YELLOW}📋 Configuration backup${NC}"
echo ""

# Backup configuration files
echo -n "Backing up configuration files... "
cp "$BASE_DIR/.env" "$BACKUP_PATH/.env" 2>/dev/null || true
cp -r "$BASE_DIR/config" "$BACKUP_PATH/config" 2>/dev/null || true
echo -e "${GREEN}✓ Done${NC}"

# Create backup metadata
cat > "$BACKUP_PATH/backup_metadata.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$(date)",
  "autoweave_version": "$(cat "$BASE_DIR/package.json" | jq -r .version 2>/dev/null || echo 'unknown')",
  "deployment_type": "$(docker ps | grep -q autoweave && echo 'docker' || echo 'kubernetes')",
  "services": {
    "qdrant": "$(curl -s http://localhost:${QDRANT_PORT:-6333}/ | jq -r .version 2>/dev/null || echo 'unknown')",
    "redis": "$(redis-cli -p ${REDIS_PORT:-6379} INFO server 2>/dev/null | grep redis_version | cut -d: -f2 | tr -d '\r' || echo 'unknown')"
  }
}
EOF

# Compress entire backup
echo ""
echo -n "Compressing backup... "
cd "$BACKUP_DIR"
tar czf "autoweave_backup_$TIMESTAMP.tar.gz" "backup_$TIMESTAMP"
rm -rf "backup_$TIMESTAMP"
echo -e "${GREEN}✓ Done${NC}"

# Calculate backup size
BACKUP_SIZE=$(du -h "$BACKUP_DIR/autoweave_backup_$TIMESTAMP.tar.gz" | cut -f1)

echo ""
echo "================================"
echo -e "${GREEN}✅ Backup completed successfully!${NC}"
echo ""
echo "Backup file: $BACKUP_DIR/autoweave_backup_$TIMESTAMP.tar.gz"
echo "Backup size: $BACKUP_SIZE"
echo ""
echo "To restore from this backup, use:"
echo "  $BASE_DIR/scripts/restore-memory.sh $BACKUP_DIR/autoweave_backup_$TIMESTAMP.tar.gz"

# Cleanup old backups (keep last 7)
echo ""
echo -n "Cleaning up old backups... "
cd "$BACKUP_DIR"
ls -t autoweave_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
echo -e "${GREEN}✓ Done${NC}"