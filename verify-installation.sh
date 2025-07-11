#!/bin/bash

# AutoWeave Installation Verification Script
# This script verifies that all modules are properly installed and configured

set -e

echo "🔍 AutoWeave Installation Verification"
echo "====================================="
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

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Function to check module
check_module() {
    local module=$1
    local module_dir="$MODULES_DIR/$module"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    echo -e "${BLUE}Checking $module...${NC}"
    
    if [ -d "$module_dir" ]; then
        if [ -f "$module_dir/package.json" ]; then
            # Check if it's a real module (not placeholder)
            if grep -q '"version": "1.0.0"' "$module_dir/package.json"; then
                echo -e "  ${GREEN}✓ Module installed (real)${NC}"
                
                # Check for key files based on module
                case $module in
                    "autoweave-core")
                        if [ -f "$module_dir/src/core/autoweave.js" ]; then
                            echo -e "  ${GREEN}✓ Core files present${NC}"
                        else
                            echo -e "  ${RED}✗ Core files missing${NC}"
                            return 1
                        fi
                        ;;
                    "autoweave-memory")
                        if [ -f "$module_dir/src/memory/hybrid-memory.js" ]; then
                            echo -e "  ${GREEN}✓ Memory files present${NC}"
                        else
                            echo -e "  ${RED}✗ Memory files missing${NC}"
                            return 1
                        fi
                        ;;
                    "autoweave-integrations")
                        if [ -f "$module_dir/src/mcp/discovery.js" ]; then
                            echo -e "  ${GREEN}✓ Integration files present${NC}"
                        else
                            echo -e "  ${RED}✗ Integration files missing${NC}"
                            return 1
                        fi
                        ;;
                    "autoweave-agents")
                        if [ -f "$module_dir/src/agents/debugging-agent.js" ]; then
                            echo -e "  ${GREEN}✓ Agent files present${NC}"
                        else
                            echo -e "  ${RED}✗ Agent files missing${NC}"
                            return 1
                        fi
                        ;;
                    "autoweave-ui")
                        if [ -f "$module_dir/src/agui/ui-agent.js" ]; then
                            echo -e "  ${GREEN}✓ UI files present${NC}"
                        else
                            echo -e "  ${RED}✗ UI files missing${NC}"
                            return 1
                        fi
                        ;;
                    "autoweave-cli")
                        if [ -f "$module_dir/bin/autoweave" ]; then
                            echo -e "  ${GREEN}✓ CLI files present${NC}"
                        else
                            echo -e "  ${RED}✗ CLI files missing${NC}"
                            return 1
                        fi
                        ;;
                esac
                
                PASSED_CHECKS=$((PASSED_CHECKS + 1))
            else
                echo -e "  ${YELLOW}⚠ Module is a placeholder${NC}"
                return 1
            fi
        else
            echo -e "  ${RED}✗ No package.json found${NC}"
            return 1
        fi
    else
        echo -e "  ${RED}✗ Module not installed${NC}"
        return 1
    fi
    
    return 0
}

echo -e "${YELLOW}📋 Step 1: Checking modules${NC}"
echo ""

# List of modules to check
MODULES=(
    "autoweave-core"
    "autoweave-memory"
    "autoweave-integrations"
    "autoweave-agents"
    "autoweave-ui"
    "autoweave-cli"
)

# Check each module
for module in "${MODULES[@]}"; do
    check_module "$module" || true
    echo ""
done

echo -e "${YELLOW}📋 Step 2: Checking configuration${NC}"
echo ""

# Check .env file
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -f "$BASE_DIR/.env" ]; then
    echo -e "${GREEN}✓ .env file exists${NC}"
    
    # Check for OPENAI_API_KEY
    if grep -q "OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE" "$BASE_DIR/.env"; then
        echo -e "${YELLOW}⚠ OPENAI_API_KEY not configured${NC}"
    elif grep -q "OPENAI_API_KEY=" "$BASE_DIR/.env"; then
        echo -e "${GREEN}✓ OPENAI_API_KEY configured${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}✗ OPENAI_API_KEY missing${NC}"
    fi
else
    echo -e "${RED}✗ .env file not found${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Step 3: Checking infrastructure${NC}"
echo ""

# Check Docker
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Docker is running${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠ Docker installed but not running${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Docker not installed${NC}"
fi

# Check kubectl
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Kubernetes cluster available${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${YELLOW}⚠ kubectl installed but no cluster${NC}"
    fi
else
    echo -e "${YELLOW}⚠ kubectl not installed${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Results${NC}"
echo ""

# Calculate percentage
PERCENTAGE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

echo -e "Checks passed: ${PASSED_CHECKS}/${TOTAL_CHECKS} (${PERCENTAGE}%)"
echo ""

if [ $PASSED_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}🎉 All checks passed! AutoWeave is ready to use.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Start infrastructure: ./scripts/setup-memory-system.sh"
    echo "  2. Start AutoWeave: ./start-autoweave.sh"
    exit 0
elif [ $PERCENTAGE -ge 70 ]; then
    echo -e "${YELLOW}⚠ Most checks passed. AutoWeave should work with some limitations.${NC}"
    echo ""
    echo "To fix issues:"
    echo "  1. Run ./install.sh to install missing modules"
    echo "  2. Configure your .env file"
    echo "  3. Install/start Docker or Kubernetes"
    exit 0
else
    echo -e "${RED}✗ Many checks failed. Please run ./install.sh first.${NC}"
    exit 1
fi