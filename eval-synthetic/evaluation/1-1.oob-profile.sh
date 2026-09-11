#!/bin/bash

# Check if running on profiling kernel
KERNEL_VERSION=$(uname -r)
if [[ "$KERNEL_VERSION" != *"profiling"* ]]; then
    echo "Error: This script requires the profiling kernel."
    echo "Current kernel: $KERNEL_VERSION"
    echo "Please boot into a profiling kernel."
    exit 1
fi

# Load our custom kernel module
sudo insmod ../kernels/profiling/module/vuln.ko

# Enable our profiler to log userland timing value
# sudo chmod 666 /dev/kmsg

cd ../exploits
make clean
make

for i in {1..100}; do
    ./oob-profile
    sleep 5
done