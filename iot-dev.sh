#!/bin/bash

IMAGE_NAME="iot-dev"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Override possible: PROJECT_PATH=/abs/path ./iot-dev.sh run
PROJECT_PATH="${PROJECT_PATH:-${SCRIPT_DIR}}"

case "$1" in
  build)
    echo "[*] Building $IMAGE_NAME..."
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    ;;
  run)
    echo "[*] Starting $IMAGE_NAME ..."
    docker run -it --rm \
      --name iot-dev \
      --privileged \
      -v "$PROJECT_PATH":/iot \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -p 8080:8080 \
      -p 8888:8888 \
      -p 6443:6443 \
      -p 2746:2746 \
      "$IMAGE_NAME"
    ;;
  *)
    echo "Usage: $0 {build|run}"
    echo ""
    echo "  build  — build the Docker image"
    echo "  run    — enter the container (mounts /iot, shares Docker socket)"
    echo "           (optional) PROJECT_PATH=/abs/path $0 run"
    ;;
esac
