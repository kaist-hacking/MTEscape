#!/usr/bin/env bash
# Purpose: Build kernel module for specific kernel type
# Usage: ./build.sh <kernel-type>
#   kernel-type: profiling, baseline, or mitigation
set -euo pipefail

KERNEL_TYPE="${1:-}"

if [[ -z "$KERNEL_TYPE" ]]; then
    echo "Usage: $0 <kernel-type>"
    echo "  kernel-type: profiling, baseline, or mitigation"
    exit 1
fi

if [[ ! "$KERNEL_TYPE" =~ ^(profiling|baseline|mitigation)$ ]]; then
    echo "[-] Error: Invalid kernel type '$KERNEL_TYPE'"
    echo "    Must be one of: profiling, baseline, mitigation"
    exit 1
fi

KDIR="$(pwd)/../../$KERNEL_TYPE/linux-6.16"
MODULE_OUTPUT_DIR="$(pwd)/../../$KERNEL_TYPE/module"

# Check if kernel source exists
if [[ ! -d "$KDIR" ]]; then
    echo "[-] Error: Kernel source not found: $KDIR"
    echo "    Build the kernel first using: cd ../common && ./build.sh $KERNEL_TYPE"
    exit 1
fi

# Check if kernel is built (vmlinux exists)
if [[ ! -f "$KDIR/vmlinux" ]]; then
    echo "[-] Error: Kernel not built (vmlinux not found)"
    echo "    Build the kernel first using: cd ../common && ./build.sh $KERNEL_TYPE"
    exit 1
fi

echo "[*] Building kernel module for $KERNEL_TYPE kernel..."
echo "    Kernel source: $KDIR"

# Clean previous build
make clean KDIR="$KDIR" 2>/dev/null || true

# Build module
make KDIR="$KDIR"

if [[ ! -f "vuln.ko" ]]; then
    echo "[-] Error: Module build failed (vuln.ko not found)"
    exit 1
fi

# Create output directory and copy module
mkdir -p "$MODULE_OUTPUT_DIR"
cp vuln.ko "$MODULE_OUTPUT_DIR/"

# Clean build artifacts to avoid conflicts between different kernel builds
echo "[*] Cleaning build artifacts..."
make clean KDIR="$KDIR" 2>/dev/null || true

echo ""
echo "[+] Module build complete!"
echo "    Module: $MODULE_OUTPUT_DIR/vuln.ko"
echo ""
