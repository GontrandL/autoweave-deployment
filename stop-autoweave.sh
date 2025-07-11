#!/bin/bash

# Stop AutoWeave services

echo "🛑 Stopping AutoWeave services..."
echo ""

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stop core service
if [ -f "$BASE_DIR/autoweave-core.pid" ]; then
    PID=$(cat "$BASE_DIR/autoweave-core.pid")
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping AutoWeave Core (PID: $PID)..."
        kill $PID
        rm "$BASE_DIR/autoweave-core.pid"
    fi
fi

# Stop UI service
if [ -f "$BASE_DIR/autoweave-ui.pid" ]; then
    PID=$(cat "$BASE_DIR/autoweave-ui.pid")
    if kill -0 $PID 2>/dev/null; then
        echo "Stopping AutoWeave UI (PID: $PID)..."
        kill $PID
        rm "$BASE_DIR/autoweave-ui.pid"
    fi
fi

# Stop Docker services
if [ -f "$BASE_DIR/docker/docker-compose.yml" ] && command -v docker-compose >/dev/null 2>&1; then
    echo "Stopping Docker services..."
    docker-compose -f "$BASE_DIR/docker/docker-compose.yml" down
fi

echo ""
echo "✅ AutoWeave services stopped"