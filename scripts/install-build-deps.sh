#!/bin/bash
# Installs all system-level dependencies needed to build the Linux runner agent.
# Must be run as root or with sudo. The .NET SDK itself is downloaded automatically
# by dev.sh at build time; this script only installs OS packages.
#
# Usage: sudo ./scripts/install-build-deps.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root or with sudo." >&2
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo "Cannot detect OS: /etc/os-release not found." >&2
    exit 1
fi

. /etc/os-release
echo "Detected OS: $PRETTY_NAME"

# ---------------------------------------------------------------------------
# Debian / Ubuntu
# ---------------------------------------------------------------------------
if [ -f /etc/debian_version ]; then
    apt-get update -y

    # Build toolchain
    apt-get install -y \
        curl \
        git \
        tar \
        unzip \
        ca-certificates

    # .NET 8 SDK and runner runtime dependencies.
    # libssl and libicu have different package names across distro versions;
    # try each in order and keep going after the first that works.
    apt-get install -y libkrb5-3 zlib1g

    install_first_available() {
        for pkg in "$@"; do
            # Strip trailing $ used as an anchor in some package name patterns
            clean="${pkg%$}"
            if apt-get install -y "$clean" 2>/dev/null; then
                return 0
            fi
        done
        echo "Warning: could not install any of: $*" >&2
        return 0  # non-fatal; newer distros may ship these under different names
    }

    install_first_available liblttng-ust1t64 liblttng-ust1 liblttng-ust0
    install_first_available libssl3t64 libssl3 libssl1.1 libssl1.0.2 libssl1.0.0
    install_first_available libicu80 libicu79 libicu78 libicu77 libicu76 libicu75 \
        libicu74 libicu73 libicu72 libicu71 libicu70 libicu69 libicu68 libicu67 \
        libicu66 libicu65 libicu63 libicu60 libicu57 libicu55 libicu52

# ---------------------------------------------------------------------------
# Fedora / RHEL / CentOS
# ---------------------------------------------------------------------------
elif [ -f /etc/redhat-release ]; then
    if [ -f /etc/fedora-release ]; then
        PKG_MGR="dnf"
    else
        PKG_MGR="yum"
    fi

    $PKG_MGR install -y \
        curl \
        git \
        tar \
        unzip \
        ca-certificates \
        lttng-ust \
        openssl-libs \
        krb5-libs \
        zlib \
        libicu

# ---------------------------------------------------------------------------
# SUSE / OpenSUSE
# ---------------------------------------------------------------------------
elif grep -qi "suse" /etc/os-release 2>/dev/null; then
    zypper -n install \
        curl \
        git \
        tar \
        unzip \
        ca-certificates \
        lttng-ust \
        libopenssl1_1 \
        krb5 \
        zlib \
        libicu60_2

else
    echo "Unsupported OS. Install these packages manually:" >&2
    echo "  curl git tar unzip ca-certificates" >&2
    echo "  Plus .NET 8 runtime deps: lttng-ust openssl krb5 zlib libicu" >&2
    echo "  See: https://learn.microsoft.com/dotnet/core/install/linux" >&2
    exit 1
fi

echo ""
echo "Build dependencies installed successfully."
echo "You can now run: ./scripts/build-linux-runner.sh"
