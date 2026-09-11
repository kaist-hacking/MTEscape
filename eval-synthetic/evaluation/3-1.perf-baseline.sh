#!/bin/bash

# Check arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <phoronix|lmbench>"
    exit 1
fi

BENCHMARK_TYPE="$1"

# Check if running on baseline kernel
KERNEL_VERSION=$(uname -r)
if [[ "$KERNEL_VERSION" != *"baseline"* ]]; then
    echo "Error: This script requires the baseline kernel."
    echo "Current kernel: $KERNEL_VERSION"
    echo "Please boot into a baseline kernel."
    exit 1
fi

# Run benchmark based on argument
case "$BENCHMARK_TYPE" in
    phoronix)
        phoronix-test-suite benchmark mitigation-test
        ;;
    lmbench)
        echo "Running lmbench benchmark..."
        LMBENCH_BIN="../kernels/common/benchmark/lmbench/bin/aarch64-linux-gnu"
        RESULT_DIR="./evaluation-result-perf"
        RESULT_FILE="${RESULT_DIR}/baseline.txt"
        ITERATIONS=50

        if [[ ! -d "$LMBENCH_BIN" ]]; then
            echo "Error: lmbench binaries not found at $LMBENCH_BIN"
            echo "Please run 0-1.setup.sh first."
            exit 1
        fi

        mkdir -p "$RESULT_DIR"

        TESTFILE="/tmp/lmbench_testfile"
        dd if=/dev/zero of="$TESTFILE" bs=1M count=128 2>/dev/null

        echo "=== lmbench Baseline Results ===" > "$RESULT_FILE"
        echo "Kernel: $KERNEL_VERSION" >> "$RESULT_FILE"
        echo "Date: $(date)" >> "$RESULT_FILE"
        echo "Iterations: $ITERATIONS" >> "$RESULT_FILE"
        echo "" >> "$RESULT_FILE"

        echo "--- Latency Tests ---" >> "$RESULT_FILE"

        echo "[*] Running lat_ctx ($ITERATIONS iterations)..."
        echo "lat_ctx -s 0 2 (Context Switch Latency):" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/lat_ctx" -s 0 2 2>&1 | tail -1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running lat_syscall null ($ITERATIONS iterations)..."
        echo "lat_syscall null:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/lat_syscall" null 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running lat_syscall read ($ITERATIONS iterations)..."
        echo "lat_syscall read:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/lat_syscall" read 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running lat_syscall write ($ITERATIONS iterations)..."
        echo "lat_syscall write:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/lat_syscall" write 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running lat_syscall stat ($ITERATIONS iterations)..."
        echo "lat_syscall stat /tmp:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/lat_syscall" stat /tmp 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "--- Bandwidth Tests ---" >> "$RESULT_FILE"

        echo "[*] Running bw_file_rd ($ITERATIONS iterations)..."
        echo "bw_file_rd 128M open2close:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/bw_file_rd" 128M open2close "$TESTFILE" 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running bw_unix ($ITERATIONS iterations)..."
        echo "bw_unix:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/bw_unix" 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        echo "[*] Running bw_mem rd ($ITERATIONS iterations)..."
        echo "bw_mem 128M rd:" >> "$RESULT_FILE"
        for i in $(seq 1 $ITERATIONS); do
            "$LMBENCH_BIN/bw_mem" 128M rd 2>&1 | tee -a "$RESULT_FILE"
        done
        echo "" >> "$RESULT_FILE"

        rm -f "$TESTFILE"

        echo "[+] Results saved to: $RESULT_FILE"
        ;;
    *)
        echo "Error: Invalid benchmark type '$BENCHMARK_TYPE'"
        echo "Usage: $0 <phoronix|lmbench>"
        exit 1
        ;;
esac