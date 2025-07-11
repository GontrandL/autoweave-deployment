# @autoweave/deployment

AutoWeave Deployment - Infrastructure and deployment configurations

## Overview

This module contains all deployment-related configurations and scripts for AutoWeave:
- Kubernetes manifests
- Docker configurations
- Setup and installation scripts
- CI/CD workflows
- Infrastructure as Code

## Directory Structure

```
deployment/
├── k8s/                    # Kubernetes manifests
│   ├── memory/            # Memory system (Qdrant + Memgraph)
│   ├── autoweave/         # AutoWeave application
│   ├── sillytavern-manifests.yaml
│   └── appsmith-values.yaml
├── docker/                 # Docker configurations
│   └── Dockerfile         # Main AutoWeave image
├── scripts/               # Deployment scripts
│   ├── setup/            # Setup scripts
│   ├── dev/              # Development helpers
│   └── cleanup/          # Cleanup utilities
├── .github/workflows/     # CI/CD workflows
│   ├── docker-build.yml
│   └── k8s-deploy.yml
├── install.sh            # Main installation script
└── start-autoweave.sh    # Start script
```

## Quick Start

### Prerequisites

- Kubernetes cluster (Kind, Minikube, or cloud provider)
- kubectl configured
- Helm 3.x installed
- Docker (for local builds)

### Installation

```bash
# Full installation
./install.sh

# Or step by step:
npm run setup:memory     # Deploy memory system
npm run setup:kagent     # Setup kagent
npm run setup:appsmith   # Deploy Appsmith dashboard
```

### Starting AutoWeave

```bash
./start-autoweave.sh
```

## Deployment Options

### Kubernetes Deployment

```bash
# Deploy all components
npm run deploy:k8s

# Or individually:
kubectl apply -f k8s/memory/
kubectl apply -f k8s/autoweave/
kubectl apply -f k8s/sillytavern-manifests.yaml

# Deploy Appsmith with Helm
helm repo add appsmith https://helm.appsmith.com
helm repo update
helm install appsmith appsmith/appsmith -f k8s/appsmith-values.yaml
```

### Docker Deployment

```bash
# Build Docker image
npm run deploy:docker

# Run with docker-compose
docker-compose up -d
```

## Components

### Memory System
- **Qdrant**: Vector database for contextual memory
- **Memgraph**: Graph database for structural memory
- **Namespace**: `autoweave-memory`

### AutoWeave Application
- Main application server
- Default port: 3000
- Integrates with memory system

### SillyTavern
- Chat interface for AutoWeave
- Default port: 8081
- Pre-configured with AutoWeave extension

### Appsmith Dashboard
- Monitoring and management interface
- Default port: 8080
- Deployed via Helm chart

## Configuration

### Environment Variables

Create a `.env` file with:

```env
# OpenAI Configuration
OPENAI_API_KEY=your-api-key

# Kubernetes Configuration
KAGENT_NAMESPACE=default
KUBECONFIG=/path/to/kubeconfig

# Memory System
QDRANT_HOST=qdrant-service
QDRANT_PORT=6333
MEMGRAPH_HOST=memgraph-service
MEMGRAPH_PORT=7687

# Application
LOG_LEVEL=info
PORT=3000
```

### Kubernetes Secrets

```bash
# Create OpenAI secret
kubectl create secret generic openai-secret \
  --from-literal=api-key=$OPENAI_API_KEY

# Create memory credentials
kubectl create secret generic memory-credentials \
  --from-literal=qdrant-api-key=your-qdrant-key \
  --from-literal=memgraph-password=your-memgraph-password
```

## CI/CD

### GitHub Actions Workflows

1. **Docker Build**: Automatically builds and pushes Docker images
2. **K8s Deploy**: Deploys to Kubernetes clusters

### Manual Deployment

```bash
# Deploy to development
kubectl apply -k k8s/overlays/development/

# Deploy to production
kubectl apply -k k8s/overlays/production/
```

## Monitoring

### Health Checks

```bash
# Check memory system
curl http://localhost:3000/api/memory/health

# Check AutoWeave
curl http://localhost:3000/health

# Check agent status
curl http://localhost:3000/api/agents
```

### Logs

```bash
# AutoWeave logs
kubectl logs -f deployment/autoweave

# Memory system logs
kubectl logs -f deployment/qdrant-deployment -n autoweave-memory
kubectl logs -f deployment/memgraph-deployment -n autoweave-memory
```

## Troubleshooting

### Common Issues

1. **Memory System Not Ready**
   ```bash
   kubectl get pods -n autoweave-memory
   kubectl describe pod <pod-name> -n autoweave-memory
   ```

2. **AutoWeave Can't Connect to Memory**
   - Check service discovery
   - Verify network policies
   - Check credentials

3. **Appsmith Installation Failed**
   ```bash
   helm status appsmith
   helm get values appsmith
   ```

## Security

- All secrets stored in Kubernetes secrets
- Network policies restrict inter-service communication
- RBAC configured for service accounts
- TLS enabled for external endpoints

## Scaling

### Horizontal Scaling

```bash
# Scale AutoWeave
kubectl scale deployment/autoweave --replicas=3

# Scale memory system
kubectl scale deployment/qdrant-deployment --replicas=2 -n autoweave-memory
```

### Vertical Scaling

Edit resource limits in deployment manifests:

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 2Gi
```

## Backup and Recovery

### Memory System Backup

```bash
# Backup Qdrant
kubectl exec -n autoweave-memory deployment/qdrant-deployment -- \
  qdrant-backup create /backup/qdrant-$(date +%Y%m%d)

# Backup Memgraph
kubectl exec -n autoweave-memory deployment/memgraph-deployment -- \
  mg_dump > memgraph-backup-$(date +%Y%m%d).cypher
```

## License

MIT