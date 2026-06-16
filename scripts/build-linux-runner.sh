#!/bin/bash
# Builds the Linux runner agent and produces a distributable tarball.
# Run this from the repository root after cloning.
# The .NET 8.0.421 SDK is downloaded automatically into src/_dotnetsdk/ on
# first run; no manual SDK installation is required.
#
# Usage:
#   ./scripts/build-linux-runner.sh [runtime]
#
#   runtime  Target RID: linux-x64 (default), linux-arm64, or linux-arm.
#            Defaults to the architecture of the current machine.
#
# Output:
#   _package/actions-runner-<runtime>-<version>.tar.gz

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"
PACKAGE_DIR="$REPO_ROOT/_package"

# ---------------------------------------------------------------------------
# Determine target runtime
# ---------------------------------------------------------------------------
if [ -n "$1" ]; then
    RUNTIME_ID="$1"
else
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
# Report output
# ---------------------------------------------------------------------------
TARBALL="$(ls "$PACKAGE_DIR"/actions-runner-"$RUNTIME_ID"-*.tar.gz 2>/dev/null | head -1)"

if [ -z "$TARBALL" ]; then
    echo "Build succeeded but no tarball found in $PACKAGE_DIR" >&2
    exit 1
fi

TARBALL_SIZE="$(du -sh "$TARBALL" | cut -f1)"

echo ""
echo "============================================"
echo " Build complete"
echo "  Output : $TARBALL"
echo "  Size   : $TARBALL_SIZE"
echo "============================================"
echo ""
echo "To deploy, copy the tarball to your target host and run:"
echo "  mkdir actions-runner && tar -xzf $(basename "$TARBALL") -C actions-runner"
echo "  sudo ./actions-runner/bin/installdependencies.sh"
echo "  ./actions-runner/config.sh --url <repo-url> --token <token>"
echo "  ./actions-runner/run.sh"
