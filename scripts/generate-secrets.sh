#!/bin/bash

# AutoWeave Secrets Generation Script
# Generates secure secrets for all AutoWeave components

set -e

echo "🔐 AutoWeave Secrets Generator"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$BASE_DIR/secrets"

# Function to generate random password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Function to generate random token
generate_token() {
    local length=${1:-64}
    openssl rand -hex "$length"
}

# Create secrets directory
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

echo -e "${YELLOW}📋 Generating secrets${NC}"
echo ""

# Check if .env exists
if [ -f "$BASE_DIR/.env" ]; then
    echo -e "${BLUE}Loading existing .env file...${NC}"
    source "$BASE_DIR/.env"
else
    echo -e "${YELLOW}No .env file found, creating new one...${NC}"
fi

# Generate or use existing secrets
declare -A SECRETS

# Core secrets
SECRETS[NODE_ENV]="${NODE_ENV:-production}"
SECRETS[LOG_LEVEL]="${LOG_LEVEL:-info}"
SECRETS[PORT]="${PORT:-3000}"
SECRETS[HOST]="${HOST:-0.0.0.0}"

# API Keys (prompt if not set)
if [ -z "$OPENAI_API_KEY" ] || [ "$OPENAI_API_KEY" = "YOUR_OPENAI_API_KEY_HERE" ]; then
    echo -e "${YELLOW}OpenAI API Key not found.${NC}"
    read -p "Enter your OpenAI API key (or press Enter to skip): " OPENAI_API_KEY
    if [ -z "$OPENAI_API_KEY" ]; then
        OPENAI_API_KEY="YOUR_OPENAI_API_KEY_HERE"
        echo -e "${YELLOW}⚠ OpenAI API key not set. AutoWeave will not function properly without it.${NC}"
    fi
fi
SECRETS[OPENAI_API_KEY]="$OPENAI_API_KEY"

# Database passwords
SECRETS[MEMGRAPH_PASSWORD]="${MEMGRAPH_PASSWORD:-$(generate_password 24)}"
SECRETS[REDIS_PASSWORD]="${REDIS_PASSWORD:-$(generate_password 24)}"
SECRETS[QDRANT_API_KEY]="${QDRANT_API_KEY:-$(generate_token 32)}"

# JWT and session secrets
SECRETS[JWT_SECRET]="${JWT_SECRET:-$(generate_token 64)}"
SECRETS[SESSION_SECRET]="${SESSION_SECRET:-$(generate_token 32)}"
SECRETS[COOKIE_SECRET]="${COOKIE_SECRET:-$(generate_password 32)}"

# ANP and MCP tokens
SECRETS[ANP_AUTH_TOKEN]="${ANP_AUTH_TOKEN:-$(generate_token 48)}"
SECRETS[MCP_AUTH_TOKEN]="${MCP_AUTH_TOKEN:-$(generate_token 48)}"

# Service endpoints
SECRETS[QDRANT_HOST]="${QDRANT_HOST:-localhost}"
SECRETS[QDRANT_PORT]="${QDRANT_PORT:-6333}"
SECRETS[MEMGRAPH_HOST]="${MEMGRAPH_HOST:-localhost}"
SECRETS[MEMGRAPH_PORT]="${MEMGRAPH_PORT:-7687}"
SECRETS[REDIS_HOST]="${REDIS_HOST:-localhost}"
SECRETS[REDIS_PORT]="${REDIS_PORT:-6379}"

# ANP and MCP ports
SECRETS[ANP_PORT]="${ANP_PORT:-8083}"
SECRETS[MCP_PORT]="${MCP_PORT:-3002}"

# Kubernetes configuration
SECRETS[KUBECONFIG]="${KUBECONFIG:-~/.kube/config}"
SECRETS[KAGENT_NAMESPACE]="${KAGENT_NAMESPACE:-default}"

# External integrations
SECRETS[GITHUB_TOKEN]="${GITHUB_TOKEN:-}"
SECRETS[DOCKERHUB_TOKEN]="${DOCKERHUB_TOKEN:-}"
SECRETS[NPM_TOKEN]="${NPM_TOKEN:-}"

# Create .env file
echo -e "${BLUE}Creating .env file...${NC}"
cat > "$BASE_DIR/.env" <<EOF
# AutoWeave Environment Configuration
# Generated on $(date)

# Core Configuration
NODE_ENV=${SECRETS[NODE_ENV]}
LOG_LEVEL=${SECRETS[LOG_LEVEL]}
PORT=${SECRETS[PORT]}
HOST=${SECRETS[HOST]}

# API Keys
OPENAI_API_KEY=${SECRETS[OPENAI_API_KEY]}

# Security Secrets
JWT_SECRET=${SECRETS[JWT_SECRET]}
SESSION_SECRET=${SECRETS[SESSION_SECRET]}
COOKIE_SECRET=${SECRETS[COOKIE_SECRET]}

# Memory System
QDRANT_HOST=${SECRETS[QDRANT_HOST]}
QDRANT_PORT=${SECRETS[QDRANT_PORT]}
QDRANT_API_KEY=${SECRETS[QDRANT_API_KEY]}
MEMGRAPH_HOST=${SECRETS[MEMGRAPH_HOST]}
MEMGRAPH_PORT=${SECRETS[MEMGRAPH_PORT]}
MEMGRAPH_USER=memgraph
MEMGRAPH_PASSWORD=${SECRETS[MEMGRAPH_PASSWORD]}
REDIS_HOST=${SECRETS[REDIS_HOST]}
REDIS_PORT=${SECRETS[REDIS_PORT]}
REDIS_PASSWORD=${SECRETS[REDIS_PASSWORD]}

# ANP Configuration
ANP_PORT=${SECRETS[ANP_PORT]}
ANP_AUTH_TOKEN=${SECRETS[ANP_AUTH_TOKEN]}

# MCP Configuration  
MCP_PORT=${SECRETS[MCP_PORT]}
MCP_AUTH_TOKEN=${SECRETS[MCP_AUTH_TOKEN]}

# Kubernetes
KUBECONFIG=${SECRETS[KUBECONFIG]}
KAGENT_NAMESPACE=${SECRETS[KAGENT_NAMESPACE]}

# External Integrations (Optional)
GITHUB_TOKEN=${SECRETS[GITHUB_TOKEN]}
DOCKERHUB_TOKEN=${SECRETS[DOCKERHUB_TOKEN]}
NPM_TOKEN=${SECRETS[NPM_TOKEN]}
EOF

chmod 600 "$BASE_DIR/.env"
echo -e "${GREEN}✓ .env file created${NC}"

# Create Docker secrets file
echo ""
echo -e "${BLUE}Creating Docker secrets...${NC}"
cat > "$SECRETS_DIR/docker-secrets.env" <<EOF
# Docker Secrets for AutoWeave
MEMGRAPH_PASSWORD=${SECRETS[MEMGRAPH_PASSWORD]}
REDIS_PASSWORD=${SECRETS[REDIS_PASSWORD]}
QDRANT_API_KEY=${SECRETS[QDRANT_API_KEY]}
EOF
chmod 600 "$SECRETS_DIR/docker-secrets.env"
echo -e "${GREEN}✓ Docker secrets created${NC}"

# Create Kubernetes secrets
echo ""
echo -e "${BLUE}Creating Kubernetes secret manifests...${NC}"

# Base64 encode secrets for Kubernetes
B64_OPENAI_API_KEY=$(echo -n "${SECRETS[OPENAI_API_KEY]}" | base64 -w 0)
B64_MEMGRAPH_PASSWORD=$(echo -n "${SECRETS[MEMGRAPH_PASSWORD]}" | base64 -w 0)
B64_REDIS_PASSWORD=$(echo -n "${SECRETS[REDIS_PASSWORD]}" | base64 -w 0)
B64_QDRANT_API_KEY=$(echo -n "${SECRETS[QDRANT_API_KEY]}" | base64 -w 0)
B64_JWT_SECRET=$(echo -n "${SECRETS[JWT_SECRET]}" | base64 -w 0)
B64_ANP_AUTH_TOKEN=$(echo -n "${SECRETS[ANP_AUTH_TOKEN]}" | base64 -w 0)
B64_MCP_AUTH_TOKEN=$(echo -n "${SECRETS[MCP_AUTH_TOKEN]}" | base64 -w 0)

cat > "$SECRETS_DIR/k8s-secrets.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: autoweave-secrets
  namespace: autoweave-core
type: Opaque
data:
  openai-api-key: $B64_OPENAI_API_KEY
  memgraph-password: $B64_MEMGRAPH_PASSWORD
  redis-password: $B64_REDIS_PASSWORD
  qdrant-api-key: $B64_QDRANT_API_KEY
  jwt-secret: $B64_JWT_SECRET
  anp-auth-token: $B64_ANP_AUTH_TOKEN
  mcp-auth-token: $B64_MCP_AUTH_TOKEN
---
apiVersion: v1
kind: Secret
metadata:
  name: autoweave-secrets
  namespace: autoweave-memory
type: Opaque
data:
  memgraph-password: $B64_MEMGRAPH_PASSWORD
  redis-password: $B64_REDIS_PASSWORD
  qdrant-api-key: $B64_QDRANT_API_KEY
---
apiVersion: v1
kind: Secret
metadata:
  name: autoweave-secrets
  namespace: autoweave-agents
type: Opaque
data:
  openai-api-key: $B64_OPENAI_API_KEY
  anp-auth-token: $B64_ANP_AUTH_TOKEN
EOF

chmod 600 "$SECRETS_DIR/k8s-secrets.yaml"
echo -e "${GREEN}✓ Kubernetes secrets created${NC}"

# Create JWT key pair for advanced authentication
echo ""
echo -e "${BLUE}Generating JWT key pair...${NC}"
openssl genrsa -out "$SECRETS_DIR/jwt-private.pem" 4096 2>/dev/null
openssl rsa -in "$SECRETS_DIR/jwt-private.pem" -pubout -out "$SECRETS_DIR/jwt-public.pem" 2>/dev/null
chmod 600 "$SECRETS_DIR/jwt-private.pem"
chmod 644 "$SECRETS_DIR/jwt-public.pem"
echo -e "${GREEN}✓ JWT key pair generated${NC}"

# Create TLS certificates for secure communication
echo ""
echo -e "${BLUE}Generating TLS certificates...${NC}"

# Create certificate configuration
cat > "$SECRETS_DIR/cert.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = AutoWeave
OU = Development
CN = autoweave.local

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = autoweave.local
DNS.2 = *.autoweave.local
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "$SECRETS_DIR/tls.key" \
    -out "$SECRETS_DIR/tls.crt" \
    -config "$SECRETS_DIR/cert.conf" 2>/dev/null

chmod 600 "$SECRETS_DIR/tls.key"
chmod 644 "$SECRETS_DIR/tls.crt"
rm "$SECRETS_DIR/cert.conf"
echo -e "${GREEN}✓ TLS certificates generated${NC}"

# Create summary file
echo ""
echo -e "${BLUE}Creating secrets summary...${NC}"
cat > "$SECRETS_DIR/README.md" <<EOF
# AutoWeave Secrets

This directory contains sensitive configuration files for AutoWeave.

## Files

- \`.env\` - Main environment configuration (copy to project root)
- \`docker-secrets.env\` - Docker-specific secrets
- \`k8s-secrets.yaml\` - Kubernetes secret manifests
- \`jwt-private.pem\` - JWT private key for token signing
- \`jwt-public.pem\` - JWT public key for token verification
- \`tls.key\` - TLS private key
- \`tls.crt\` - TLS certificate

## Security Notes

1. **Never commit these files to version control**
2. Keep backups in a secure location
3. Rotate secrets regularly
4. Use different secrets for production

## Applying Kubernetes Secrets

\`\`\`bash
kubectl apply -f k8s-secrets.yaml
\`\`\`

## Docker Usage

\`\`\`bash
docker run --env-file docker-secrets.env ...
\`\`\`

Generated on: $(date)
EOF

echo -e "${GREEN}✓ Secrets summary created${NC}"

# Display summary
echo ""
echo "================================"
echo -e "${GREEN}✅ Secrets generation complete!${NC}"
echo ""
echo "Generated files in $SECRETS_DIR:"
echo "  • .env (copied to $BASE_DIR/.env)"
echo "  • docker-secrets.env"
echo "  • k8s-secrets.yaml"
echo "  • JWT key pair (jwt-private.pem, jwt-public.pem)"
echo "  • TLS certificates (tls.key, tls.crt)"
echo ""
echo -e "${YELLOW}⚠ Security reminders:${NC}"
echo "  • Never commit secrets to version control"
echo "  • Keep the secrets directory secure (chmod 700)"
echo "  • Rotate secrets regularly"
echo "  • Use different secrets for production"
echo ""
if [ "$OPENAI_API_KEY" = "YOUR_OPENAI_API_KEY_HERE" ]; then
    echo -e "${RED}⚠ Don't forget to add your OpenAI API key to .env!${NC}"
fi