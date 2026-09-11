#!/usr/bin/env bash
# Purpose: Install all three kernels (profiling, baseline, mitigation) and register with GRUB
# Usage: sudo ./0-3.install.sh
set -euo pipefail

# Require root
if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root. Use sudo."
    exit 1
fi

echo "[*] Installing evaluation kernels"
echo ""

INSTALL_SCRIPT="../kernels/common/install.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "[-] Error: Install script not found: $INSTALL_SCRIPT"
    exit 1
fi

# Install profiling kernel
echo "========================================="
echo "[1/3] Installing profiling kernel"
echo "========================================="
cd ../kernels/common
./install.sh profiling
cd ../../evaluation
echo ""

# Install baseline kernel
echo "========================================="
echo "[2/3] Installing baseline kernel"
echo "========================================="
cd ../kernels/common
./install.sh baseline
cd ../../evaluation
echo ""

# Install mitigation kernel
echo "========================================="
echo "[3/3] Installing mitigation kernel"
echo "========================================="
cd ../kernels/common
./install.sh mitigation
cd ../../evaluation
echo ""

echo "========================================="
echo "[+] All kernels installed successfully!"
echo "========================================="
echo ""
echo "[>] Next steps: Reboot and select a kernel from the GRUB menu, then run:"
echo ""
echo "  1. OOB Exploit Evaluation (baseline kernel):"
echo "     ./1-1.oob-profile.sh        # Timing calibration (profiling kernel)"
echo "     ./1-2.oob-exploit.sh <size> # Single exploit run"
echo "     ./1-3.oob-reliability.sh    # Reliability measurement"
echo ""
echo "  2. UAF Exploit Evaluation (baseline kernel):"
echo "     ./2-1.uaf-exploit.sh <size> # Single exploit run"
echo "     ./2-2.uaf-reliability.sh    # Reliability measurement"
echo ""
echo "  3. Mitigation Performance Evaluation:"
echo "     ./3-1.perf-baseline.sh <benchmark>   # Baseline (baseline kernel)"
echo "     ./3-2.perf-mitigation.sh <benchmark> # Mitigation (mitigation kernel)"
echo "     # <benchmark>: phoronix or lmbench"
echo ""
