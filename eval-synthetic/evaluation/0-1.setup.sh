#!/usr/bin/env bash
# Purpose: Verify hardware requirements and clone Linux kernel source
set -euo pipefail

KERNEL_VERSION="6.16"
KERNEL_URL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
SOURCE_DIR="../kernels/common/linux-${KERNEL_VERSION}"

# Check 1: Architecture
echo "[1/7] Checking architecture..."
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo "    [!] Warning: This system is $ARCH, but ARM64 (aarch64) is required"
    echo "      MTEscape requires ARM64 with MTE support"
    read -p "    Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "    [+] Architecture: $ARCH"
fi

# Check 2: MTE support
echo "[2/7] Checking MTE support..."
if [[ -f /proc/cpuinfo ]]; then
    if grep -q "mte" /proc/cpuinfo; then
        echo "    [+] MTE support detected in /proc/cpuinfo"
    else
        echo "    [!] Warning: MTE not detected in /proc/cpuinfo"
        echo "      This may indicate:"
        echo "        - CPU does not support MTE"
        echo "        - MTE is disabled in current kernel"
        read -p "    Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "    [!] Warning: Cannot check MTE support (/proc/cpuinfo not found)"
fi

# Check 3: Install noise generator
echo "[3/7] Checking stress-ng..."
if command -v stress-ng &> /dev/null; then
    echo "    [+] stress-ng is already installed"
elif command -v apt-get &> /dev/null; then
    echo "    [*] Installing stress-ng..."
    sudo apt-get update
    sudo apt-get install -y stress-ng
else
    echo "[-] Error: stress-ng is required for noise reliability tests"
    exit 1
fi

# Check 4: Clone kernel source
echo "[4/7] Cloning Linux kernel source..."
COMPLETE_MARKER="../kernels/common/.clone_complete"

# Check if clone is complete
if [[ -f "$COMPLETE_MARKER" ]]; then
    echo "    [+] Linux ${KERNEL_VERSION} already cloned"
elif [[ -d "$SOURCE_DIR" ]]; then
    echo "    [!] Warning: Incomplete clone detected (no .clone_complete marker)"
    echo "      Cleaning up and retrying..."
    rm -rf "$SOURCE_DIR"
fi

# Perform clone if needed
if [[ ! -f "$COMPLETE_MARKER" ]]; then
    echo "    [*] Cloning Linux ${KERNEL_VERSION}..."
    if git clone --depth 1 --branch "v${KERNEL_VERSION}" "$KERNEL_URL" "$SOURCE_DIR"; then
        touch "$COMPLETE_MARKER"
        echo "    [+] Clone complete: $(du -sh "$SOURCE_DIR" | cut -f1)"
    else
        echo "[-] Error: Clone failed"
        rm -rf "$SOURCE_DIR"
        exit 1
    fi
fi

# Check 5: Install Phoronix Test Suite
echo "[5/7] Installing Phoronix Test Suite..."
if command -v phoronix-test-suite &> /dev/null; then
    echo "    [+] Phoronix Test Suite already installed: $(phoronix-test-suite version | head -1)"
else
    echo "    [*] Installing Phoronix Test Suite..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y php-cli php-xml php-json curl libpcre3-dev
        PTS_DEB="/tmp/phoronix-test-suite.deb"
        curl -L -o "$PTS_DEB" https://github.com/phoronix-test-suite/phoronix-test-suite/releases/download/v10.8.4/phoronix-test-suite_10.8.4_all.deb
        sudo dpkg -i "$PTS_DEB"
        rm -f "$PTS_DEB"
    else
        echo "    [-] Error: apt-get not found. Please install Phoronix Test Suite manually."
        exit 1
    fi
    echo "    [+] Phoronix Test Suite installed"
fi

# Check 6: Install benchmark tests
echo "[6/7] Installing Phoronix benchmark tests..."
BENCHMARKS="pts/apache pts/redis pts/nginx pts/compress-7zip pts/openssl"
echo "    [*] Installing: $BENCHMARKS"
phoronix-test-suite install $BENCHMARKS
echo "    [+] Benchmark tests installed"
mkdir -p ~/.phoronix-test-suite/test-suites/local
cp -r ../kernels/common/benchmark/mitigation-test ~/.phoronix-test-suite/test-suites/local/
echo "    [+] Custom test suite installed"

# Check 7: Clone and build lmbench
echo "[7/7] Setting up lmbench..."
LMBENCH_DIR="../kernels/common/benchmark/lmbench"
LMBENCH_URL="https://github.com/intel/lmbench.git"
LMBENCH_MARKER="../.lmbench_complete"

if [[ -f "$LMBENCH_MARKER" ]]; then
    echo "    [+] lmbench already set up"
else
    # Clone lmbench
    if [[ -d "$LMBENCH_DIR" ]]; then
        echo "    [!] Warning: Incomplete lmbench setup detected, cleaning up..."
        rm -rf "$LMBENCH_DIR"
    fi

    echo "    [*] Cloning lmbench from GitHub..."
    if git clone "$LMBENCH_URL" "$LMBENCH_DIR"; then
        echo "    [+] Clone complete"
    else
        echo "    [-] Error: Failed to clone lmbench"
        exit 1
    fi

    # Build lmbench
    echo "    [*] Building lmbench..."
    cd "$LMBENCH_DIR"
    if make; then
        touch "$LMBENCH_MARKER"
        echo "    [+] lmbench build complete"
    else
        echo "    [-] Error: Failed to build lmbench"
        exit 1
    fi
    cd - > /dev/null
fi

echo ""
echo "[+] Setup complete!"
echo ""
echo "[>] Next step - Build kernels:"
echo "  ./0-2.build.sh"
