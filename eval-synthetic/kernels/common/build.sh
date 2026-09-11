#!/usr/bin/env bash
# Purpose: Common build script for all MTEscape kernels
# Usage: ./build.sh <kernel-type>
#   kernel-type: profiling, baseline, or mitigation
set -euo pipefail

KERNEL_TYPE="${1:-}"
KDIR="linux-6.16"

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

echo "[*] Building $KERNEL_TYPE kernel..."

# Check if clone is complete
COMPLETE_MARKER=".clone_complete"
if [[ ! -f "$COMPLETE_MARKER" ]]; then
    echo "[-] Error: Kernel source not ready (missing .clone_complete marker)"
    echo "    Run 'cd ../../evaluation && ./0.setup.sh' first"
    exit 1
fi

# Check if reference kernel source exists
if [[ ! -d "$KDIR" ]]; then
    echo "[-] Error: Reference kernel source not found: $KDIR"
    echo "    This should not happen after successful setup"
    exit 1
fi

# Navigate to kernel directory
cd "../$KERNEL_TYPE"

# Copy kernel source if not exists
if [[ ! -d "$KDIR" ]]; then
    echo "[*] Copying kernel source from common/..."
    cp -r "../common/$KDIR" "./$KDIR"
    echo "    Copy complete: $(du -sh "$KDIR" | cut -f1)"
else
    echo "[*] Using existing kernel source: $KDIR"
fi

cd "$KDIR"

# Check if kernel is already built
if [[ -f "vmlinux" ]] && [[ -f "arch/arm64/boot/Image" ]]; then
    echo "[*] Kernel already built (vmlinux exists)"
    echo ""
    echo "[+] Build complete!"
    echo "[+] If you made changes, run \`make clean\` at the modified kernel and rebuild."
    echo ""
    echo "Kernel built: $(make -s kernelrelease)"
    echo ""
    exit 0
fi

# Apply patch if exists
echo "[*] Applying patch for $KERNEL_TYPE kernel..."
if [[ -f ../patch.diff ]]; then
    if git apply --check ../patch.diff 2>/dev/null; then
        git apply ../patch.diff
        echo "    [+] Patch applied successfully"
    else
        echo "    [!] Patch already applied or conflicts detected, skipping..."
    fi
else
    echo "    [!] No patch.diff found, skipping..."
fi

# Configure kernel
echo "[*] Configuring kernel..."
make defconfig
cat ../../common/config ../config >> .config
make olddefconfig

# Build
echo "[*] Building kernel (this may take a while)..."
make -j$(nproc)

echo ""
echo "[+] Build complete!"
echo ""
echo "Kernel built: $(make -s kernelrelease)"
echo ""
