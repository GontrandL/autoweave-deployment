#!/bin/bash

# AutoWeave Installation Script
# This script installs all AutoWeave modules and dependencies

set -e

echo "🚀 AutoWeave Installation Script v1.0.0"
echo "======================================"
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

# GitHub base URL
GITHUB_BASE="https://github.com/GontrandL"

# List of AutoWeave modules
MODULES=(
    "autoweave-core"
    "autoweave-memory"
    "autoweave-integrations"
    "autoweave-agents"
    "autoweave-ui"
    "autoweave-cli"
)

# Function to check command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to clone or update module
clone_or_update_module() {
    local module=$1
    local module_dir="$MODULES_DIR/$module"
    
    if [ -d "$module_dir" ]; then
        echo -e "${BLUE}Updating $module...${NC}"
        cd "$module_dir"
        git pull origin main || git pull origin master
    else
        echo -e "${BLUE}Checking $module availability...${NC}"
        # Check if repository exists
        if git ls-remote "$GITHUB_BASE/$module.git" &>/dev/null; then
            echo -e "${BLUE}Cloning $module...${NC}"
            git clone "$GITHUB_BASE/$module.git" "$module_dir"
        else
            echo -e "${RED}✗ Repository $module not accessible${NC}"
            echo -e "${RED}  Please check your internet connection or GitHub access${NC}"
            echo ""
            echo "The module repositories are now available at:"
            echo "  https://github.com/GontrandL/$module"
            echo ""
            echo "Try again later or clone manually."
            exit 1
        fi
    fi
}

echo -e "${YELLOW}📋 Step 1: Checking prerequisites${NC}"
echo ""

# Check Node.js
if command_exists node; then
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        echo -e "${RED}✗ Node.js version is less than 18. Please upgrade.${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ Node.js $(node --version)${NC}"
    fi
else
    echo -e "${RED}✗ Node.js not found. Please install Node.js 18+${NC}"
    exit 1
fi

# Check Python
if command_exists python3; then
    echo -e "${GREEN}✓ Python3 $(python3 --version)${NC}"
    
    # Check for python3-venv
    if ! python3 -m venv --help >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ python3-venv not installed${NC}"
        echo -e "${YELLOW}  Installing python3-venv...${NC}"
        
        # Detect OS and install venv
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y python3-venv
        elif command_exists yum; then
            sudo yum install -y python3-venv
        elif command_exists dnf; then
            sudo dnf install -y python3-venv
        else
            echo -e "${RED}✗ Cannot install python3-venv automatically${NC}"
            echo "Please install python3-venv manually and re-run this script"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ python3-venv available${NC}"
    fi
    
    # Check for pip
    if ! command_exists pip3; then
        echo -e "${YELLOW}⚠ pip3 not installed${NC}"
        echo -e "${YELLOW}  Installing pip3...${NC}"
        
        if command_exists apt-get; then
            sudo apt-get install -y python3-pip
        elif command_exists yum; then
            sudo yum install -y python3-pip
        else
            echo -e "${RED}✗ Cannot install pip3 automatically${NC}"
            echo "Please install python3-pip manually and re-run this script"
            exit 1
        fi
    fi
else
    echo -e "${RED}✗ Python3 not found${NC}"
    exit 1
fi

# Check Docker
if command_exists docker; then
    echo -e "${GREEN}✓ Docker $(docker --version | cut -d' ' -f3 | tr -d ',')${NC}"
    
    # Check Docker permissions
    if ! docker info >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Docker installed but cannot connect to daemon${NC}"
        echo -e "${YELLOW}  This might be a permission issue.${NC}"
        
        # Check if user is in docker group
        if ! groups | grep -q docker; then
            echo -e "${YELLOW}  Adding user to docker group...${NC}"
            sudo usermod -aG docker $USER
            echo -e "${YELLOW}  Please log out and log back in for changes to take effect${NC}"
            echo -e "${YELLOW}  Or run: newgrp docker${NC}"
        else
            echo -e "${YELLOW}  User is in docker group but daemon is not accessible${NC}"
            echo -e "${YELLOW}  Try: sudo systemctl start docker${NC}"
        fi
    else
        echo -e "${GREEN}✓ Docker daemon accessible${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Docker not found (optional but recommended)${NC}"
    echo -e "${YELLOW}  To install: curl -fsSL https://get.docker.com | sh${NC}"
fi

# Check kubectl
if command_exists kubectl; then
    echo -e "${GREEN}✓ kubectl $(kubectl version --client --short 2>/dev/null || echo 'installed')${NC}"
else
    echo -e "${YELLOW}⚠ kubectl not found (optional for Kubernetes deployment)${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Step 2: Creating directory structure${NC}"

# Create necessary directories
mkdir -p "$MODULES_DIR"
mkdir -p "$BASE_DIR/data"
mkdir -p "$BASE_DIR/logs"
mkdir -p "$BASE_DIR/config"

echo -e "${GREEN}✓ Directory structure created${NC}"

echo ""
echo -e "${YELLOW}📋 Step 3: Cloning AutoWeave modules${NC}"

# Clone all modules
for module in "${MODULES[@]}"; do
    clone_or_update_module "$module"
done

echo -e "${GREEN}✓ All modules cloned/updated${NC}"

echo ""
echo -e "${YELLOW}📋 Step 4: Installing dependencies${NC}"

# Install dependencies for each module
for module in "${MODULES[@]}"; do
    module_dir="$MODULES_DIR/$module"
    if [ -f "$module_dir/package.json" ]; then
        echo -e "${BLUE}Installing dependencies for $module...${NC}"
        cd "$module_dir"
        npm install --production
    fi
done

echo -e "${GREEN}✓ All Node.js dependencies installed${NC}"

# Install Python dependencies if requirements.txt exists
if [ -f "$BASE_DIR/requirements.txt" ]; then
    echo -e "${BLUE}Installing Python dependencies...${NC}"
    pip3 install -r "$BASE_DIR/requirements.txt" --user
    echo -e "${GREEN}✓ Python dependencies installed${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Step 5: Setting up configuration${NC}"

# Create .env file if it doesn't exist
if [ ! -f "$BASE_DIR/.env" ]; then
    if [ -f "$BASE_DIR/.env.example" ]; then
        cp "$BASE_DIR/.env.example" "$BASE_DIR/.env"
        echo -e "${YELLOW}⚠ Created .env file from template${NC}"
        echo -e "${YELLOW}  Please edit .env and add your OPENAI_API_KEY${NC}"
    else
        echo -e "${YELLOW}⚠ No .env.example found, creating basic .env${NC}"
        cat > "$BASE_DIR/.env" << EOF
# AutoWeave Environment Configuration
OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
NODE_ENV=production
LOG_LEVEL=info
PORT=3000
HOST=0.0.0.0

# Memory System
QDRANT_HOST=localhost
QDRANT_PORT=6333
MEMGRAPH_HOST=localhost
MEMGRAPH_PORT=7687
REDIS_HOST=localhost
REDIS_PORT=6379

# ANP Configuration
ANP_PORT=8083
MCP_PORT=3002

# Kubernetes
KUBECONFIG=~/.kube/config
KAGENT_NAMESPACE=default
EOF
        echo -e "${YELLOW}⚠ Created .env file. Please add your OPENAI_API_KEY${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}📋 Step 6: Creating launch scripts${NC}"

# Create unified start script
cat > "$BASE_DIR/start-all.sh" << 'EOF'
#!/bin/bash
# Start all AutoWeave services

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BASE_DIR/.env"

echo "Starting AutoWeave services..."

# Start memory systems if docker is available
if command -v docker >/dev/null 2>&1; then
    echo "Starting memory systems..."
    docker-compose -f "$BASE_DIR/docker/docker-compose.yml" up -d
fi

# Start core service
echo "Starting AutoWeave Core..."
cd "$BASE_DIR/modules/autoweave-core"
npm start &

echo "AutoWeave is starting on http://localhost:${PORT:-3000}"
echo "Health check: http://localhost:${PORT:-3000}/api/health"
EOF

chmod +x "$BASE_DIR/start-all.sh"

echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo -e "${GREEN}🎉 AutoWeave has been successfully installed!${NC}"
echo ""
echo -e "${YELLOW}📋 Next steps:${NC}"
echo "1. Edit the configuration file:"
echo "   nano $BASE_DIR/.env"
echo ""
echo "2. Add your OpenAI API key to the .env file"
echo ""
echo "3. Deploy the infrastructure (optional):"
echo "   $BASE_DIR/scripts/setup-memory-system.sh"
echo ""
echo "4. Start AutoWeave:"
echo "   $BASE_DIR/start-autoweave.sh"
echo ""
echo "5. Access AutoWeave:"
echo "   http://localhost:3000"
echo ""
echo -e "${GREEN}Happy agent weaving! 🚀${NC}"