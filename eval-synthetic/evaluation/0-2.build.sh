#!/usr/bin/env bash
# Purpose: Build all three kernels (profiling, baseline, mitigation)
set -euo pipefail

echo "[*] Building evaluation kernels"
echo ""

BUILD_SCRIPT="../kernels/common/build.sh"

if [[ ! -f "$BUILD_SCRIPT" ]]; then
    echo "[-] Error: Build script not found: $BUILD_SCRIPT"
    exit 1
fi

# Build profiling kernel
echo "========================================="
echo "[1/3] Building profiling kernel"
echo "========================================="
cd ../kernels/common
./build.sh profiling
cd ../../evaluation
echo ""

# Build baseline kernel
echo "========================================="
echo "[2/3] Building baseline kernel"
echo "========================================="
cd ../kernels/common
./build.sh baseline
cd ../../evaluation
echo ""

# Build mitigation kernel
echo "========================================="
echo "[3/3] Building mitigation kernel"
echo "========================================="
cd ../kernels/common
./build.sh mitigation
cd ../../evaluation
echo ""

echo "========================================="
echo "[+] All kernels built successfully!"
echo "========================================="
echo ""

# Build kernel modules
echo "========================================="
echo "Building kernel modules for all kernels"
echo "========================================="
cd ../kernels/common/kernel_module

echo "[1/3] Building module for profiling kernel"
./build-module.sh profiling

echo "[2/3] Building module for baseline kernel"
./build-module.sh baseline

echo "[3/3] Building module for mitigation kernel"
./build-module.sh mitigation

echo "========================================="
echo "[+] All kernel modules built successfully!"
echo "========================================="
echo ""
echo "[+] Build complete!"
echo ""
echo "[>] Next step - Install kernels:"
echo "  sudo ./0-3.install.sh"
