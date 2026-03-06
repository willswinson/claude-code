#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND="${1:-clean}"
FILTER="label=devcontainer.local_folder=$PROJECT_DIR"

stop_containers() {
    RUNNING=$(docker ps -q --filter "$FILTER" 2>/dev/null || true)
    if [ -n "$RUNNING" ]; then
        echo "Stopping containers..."
        echo "$RUNNING" | xargs docker stop
    else
        echo "No running containers found."
    fi
}

case "$COMMAND" in
    stop)
        echo "Stopping devcontainer for: $PROJECT_DIR"
        stop_containers
        ;;
    clean)
        echo "Cleaning devcontainer for: $PROJECT_DIR"
        stop_containers

        # Remove containers
        CONTAINERS=$(docker ps -a -q --filter "$FILTER" 2>/dev/null || true)
        if [ -n "$CONTAINERS" ]; then
            echo "Removing containers..."
            # Grab volume names before removing containers
            for cid in $CONTAINERS; do
                MOUNTS=$(docker inspect "$cid" --format '{{range .Mounts}}{{.Name}} {{end}}' 2>/dev/null || true)
                for mount in $MOUNTS; do
                    if [ -n "$mount" ]; then
                        echo "Removing volume: $mount"
                        docker volume rm "$mount" 2>/dev/null || true
                    fi
                done
            done
            echo "$CONTAINERS" | xargs docker rm -f
        fi

        # Remove the image built for this project
        IMAGES=$(docker images --format '{{.ID}} {{.Repository}}' | grep "vsc-$(basename "$PROJECT_DIR")" | awk '{print $1}' || true)
        if [ -n "$IMAGES" ]; then
            echo "Removing images..."
            echo "$IMAGES" | xargs docker rmi -f
        fi

        echo "Done. Reopen in VS Code to rebuild."
        ;;
    *)
        echo "Usage: $(basename "$0") [stop|clean]"
        echo "  stop   - Stop the running devcontainer"
        echo "  clean  - Stop, remove container, volumes, and image"
        exit 1
        ;;
esac
