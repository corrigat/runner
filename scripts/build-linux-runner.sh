#!/bin/bash
# Builds the Linux runner agent, produces a distributable tarball, and
# optionally builds a Docker image from it.
# Run this from the repository root after cloning.
# The .NET 8.0.421 SDK is downloaded automatically into src/_dotnetsdk/ on
# first run; no manual SDK installation is required.
#
# Usage:
#   ./scripts/build-linux-runner.sh [runtime] [--no-docker]
#
#   runtime     Target RID: linux-x64 (default), linux-arm64, or linux-arm.
#               Defaults to the architecture of the current machine.
#   --no-docker Skip the Docker image build even if Docker is available.
#
# Output:
#   _package/actions-runner-<runtime>-<version>.tar.gz
#   Docker image: actions-runner:<version>-<runtime>  (if Docker is available)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"
PACKAGE_DIR="$REPO_ROOT/_package"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
RUNTIME_ID=""
SKIP_DOCKER=false

for arg in "$@"; do
    case "$arg" in
        --no-docker) SKIP_DOCKER=true ;;
        linux-x64|linux-arm64|linux-arm) RUNTIME_ID="$arg" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Determine target runtime
# ---------------------------------------------------------------------------
if [ -z "$RUNTIME_ID" ]; then
    case "$(uname -m)" in
        x86_64)  RUNTIME_ID="linux-x64"   ;;
        aarch64) RUNTIME_ID="linux-arm64"  ;;
        armv7l)  RUNTIME_ID="linux-arm"    ;;
        *)
            echo "Cannot auto-detect runtime for architecture: $(uname -m)" >&2
            echo "Pass an explicit runtime as the first argument: linux-x64 | linux-arm64 | linux-arm" >&2
            exit 1
            ;;
    esac
fi

case "$RUNTIME_ID" in
    linux-x64|linux-arm64|linux-arm) ;;
    *)
        echo "Unsupported runtime: $RUNTIME_ID" >&2
        echo "Valid options: linux-x64, linux-arm64, linux-arm" >&2
        exit 1
        ;;
esac

RUNNER_VERSION="$(cat "$SRC_DIR/runnerversion")"

echo ""
echo "============================================"
echo " Building GitHub Actions Runner"
echo "  Runtime : $RUNTIME_ID"
echo "  Version : $RUNNER_VERSION"
echo "  Source  : $SRC_DIR"
echo "============================================"
echo ""

cd "$SRC_DIR"

# ---------------------------------------------------------------------------
# Layout: compiles and assembles the runner + downloads Node externals
# ---------------------------------------------------------------------------
echo "--- Layout (compile + assemble) ---"
./dev.sh layout Release "$RUNTIME_ID"

# ---------------------------------------------------------------------------
# Package: strips debug symbols and creates the tarball
# ---------------------------------------------------------------------------
echo "--- Package (create tarball) ---"
./dev.sh package Release "$RUNTIME_ID"

# ---------------------------------------------------------------------------
# Report tarball output
# ---------------------------------------------------------------------------
TARBALL="$(ls "$PACKAGE_DIR"/actions-runner-"$RUNTIME_ID"-*.tar.gz 2>/dev/null | head -1)"

if [ -z "$TARBALL" ]; then
    echo "Build succeeded but no tarball found in $PACKAGE_DIR" >&2
    exit 1
fi

TARBALL_SIZE="$(du -sh "$TARBALL" | cut -f1)"

# ---------------------------------------------------------------------------
# Docker image (skipped with --no-docker or when Docker is not installed)
# ---------------------------------------------------------------------------
IMAGE_TAG=""

if [ "$SKIP_DOCKER" = true ]; then
    echo "Skipping Docker image build (--no-docker)."
elif ! command -v docker &>/dev/null; then
    echo "Docker not found; skipping image build. Install Docker to enable this step."
else
    case "$RUNTIME_ID" in
        linux-x64)   DOCKER_PLATFORM="linux/amd64"  ;;
        linux-arm64) DOCKER_PLATFORM="linux/arm64"  ;;
        linux-arm)   DOCKER_PLATFORM="linux/arm/v7" ;;
    esac

    IMAGE_TAG="actions-runner:${RUNNER_VERSION}-${RUNTIME_ID}"
    CONTEXT_TARBALL="$REPO_ROOT/images/runner.tar.gz"

    # Stage the tarball in the Docker build context; always clean it up on exit.
    cp "$TARBALL" "$CONTEXT_TARBALL"
    trap 'rm -f "$CONTEXT_TARBALL"' EXIT

    echo "--- Docker image ($DOCKER_PLATFORM → $IMAGE_TAG) ---"
    docker buildx build \
        --platform "$DOCKER_PLATFORM" \
        --load \
        --tag "$IMAGE_TAG" \
        --file "$REPO_ROOT/images/Dockerfile.local" \
        "$REPO_ROOT/images/"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo " Build complete"
echo "  Tarball : $TARBALL ($TARBALL_SIZE)"
if [ -n "$IMAGE_TAG" ]; then
echo "  Image   : $IMAGE_TAG"
fi
echo "============================================"
echo ""
echo "Tarball deploy:"
echo "  mkdir actions-runner && tar -xzf $(basename "$TARBALL") -C actions-runner"
echo "  sudo ./actions-runner/bin/installdependencies.sh"
echo "  ./actions-runner/config.sh --url <repo-url> --token <token>"
echo "  ./actions-runner/run.sh"
if [ -n "$IMAGE_TAG" ]; then
echo ""
echo "Docker deploy:"
echo "  docker run --rm $IMAGE_TAG ./run.sh --url <repo-url> --token <token>"
fi
