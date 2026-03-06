#!/bin/bash
set -euo pipefail

# NOTE: Run this from your HOST machine, not inside the container.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
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

        # Find all containers for this project (running and stopped)
        CONTAINERS=$(docker ps -a -q --filter "$FILTER" 2>/dev/null || true)
        VOLUME_NAMES=""
        IMAGE_IDS=""
        if [ -n "$CONTAINERS" ]; then
            for cid in $CONTAINERS; do
                MOUNTS=$(docker inspect "$cid" --format '{{range .Mounts}}{{.Name}} {{end}}' 2>/dev/null || true)
                VOLUME_NAMES="$VOLUME_NAMES $MOUNTS"
                IMG=$(docker inspect "$cid" --format '{{.Image}}' 2>/dev/null || true)
                if [ -n "$IMG" ]; then
                    IMAGE_IDS="$IMAGE_IDS $IMG"
                fi
            done

            echo "Removing containers..."
            echo "$CONTAINERS" | xargs docker rm -f
        else
            echo "No containers found."
        fi

        # Remove volumes after containers are gone
        for mount in $VOLUME_NAMES; do
            if [ -n "$mount" ]; then
                echo "Removing volume: $mount"
                docker volume rm "$mount" 2>/dev/null || true
            fi
        done

        # If no image IDs found from containers, search by image name
        if [ -z "$IMAGE_IDS" ]; then
            IMAGE_IDS=$(docker images --format '{{.ID}} {{.Repository}}' | grep -F "vsc-${PROJECT_NAME}-" | awk '{print $1}' || true)
        fi

        # Remove images - stop and remove any containers still referencing them
        if [ -n "$IMAGE_IDS" ]; then
            for img in $IMAGE_IDS; do
                RUNNING=$(docker ps -q --filter "ancestor=$img" 2>/dev/null || true)
                if [ -n "$RUNNING" ]; then
                    echo "Stopping containers using this image..."
                    echo "$RUNNING" | xargs docker stop
                fi
                BLOCKING=$(docker ps -a -q --filter "ancestor=$img" 2>/dev/null || true)
                if [ -n "$BLOCKING" ]; then
                    echo "Removing containers blocking image removal..."
                    echo "$BLOCKING" | xargs docker rm -f
                fi
                echo "Removing image: $img"
                docker rmi -f "$img"
            done
        else
            echo "No images found."
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
