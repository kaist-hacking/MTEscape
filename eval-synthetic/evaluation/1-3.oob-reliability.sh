#!/bin/bash

set -e

STATE_FILE="./evaluation-result-oob/eval-state.txt"
RESULT_BASE_DIR="./evaluation-result-oob"

SIZES=(4096 2048 1024 512 256 192 128 64)

MAX_ITERATIONS=100

persist_state() {
    local value=$1

    printf '%s\n' "$value" > "${STATE_FILE}.tmp"
    sync "${STATE_FILE}.tmp"
    mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
    sync
}

# Check if running on baseline kernel
KERNEL_VERSION=$(uname -r)
if [[ "$KERNEL_VERSION" != "6.16.0-baseline" ]]; then
    echo "Error: This script requires the 6.16.0-baseline kernel."
    echo "Current kernel: $KERNEL_VERSION"
    exit 1
fi

# Create result base directory
mkdir -p "$RESULT_BASE_DIR"

# Initialize or read state
if [ ! -f "$STATE_FILE" ]; then
    # First run - initialize state
    CURRENT_SIZE=4096
    CURRENT_INDEX=1
    PREVIOUS_RUN=false
    persist_state "$CURRENT_SIZE:$CURRENT_INDEX"
else
    # Read previous state
    STATE=$(cat "$STATE_FILE")
    CURRENT_SIZE=$(echo "$STATE" | cut -d':' -f1)
    CURRENT_INDEX=$(echo "$STATE" | cut -d':' -f2)
    PREVIOUS_RUN=true
fi

# Function to get next state
get_next_state() {
    local size=$1
    local index=$2

    if [ "$index" -lt "$MAX_ITERATIONS" ]; then
        # Continue with same size
        echo "$size:$((index + 1))"
    else
        # Move to next size
        local found=false
        for next_size in "${SIZES[@]}"; do
            if [ "$found" = true ]; then
                echo "$next_size:1"
                return
            fi
            if [ "$next_size" = "$size" ]; then
                found=true
            fi
        done
        # All done
        echo "DONE"
    fi
}

# Check if all experiments are complete
if [ "$CURRENT_SIZE" = "DONE" ]; then
    # Save the last experiment log
    LAST_SIZE=${SIZES[-1]}
    echo "Saving final experiment log..."
    RESULT_DIR="$RESULT_BASE_DIR/result-${LAST_SIZE}"
    mkdir -p "$RESULT_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="$RESULT_DIR/${MAX_ITERATIONS}-${TIMESTAMP}.txt"
    journalctl -k -b -1 > "$LOG_FILE"
    echo "Saved logs to $LOG_FILE"

    echo "All experiments completed. Exiting."
    exit 0
fi

# If this is not the first run, save previous experiment results
if [ "$PREVIOUS_RUN" = true ]; then
    echo "Collecting logs from previous experiment..."

    # Determine previous experiment's size and index
    PREV_INDEX=$((CURRENT_INDEX - 1))
    if [ "$PREV_INDEX" -lt 1 ]; then
        # Need to find previous size
        PREV_SIZE=""
        found_current=false
        for size in "${SIZES[@]}"; do
            if [ "$found_current" = true ]; then
                break
            fi
            if [ "$size" = "$CURRENT_SIZE" ]; then
                found_current=true
            else
                PREV_SIZE=$size
            fi
        done
        PREV_INDEX=$MAX_ITERATIONS
    else
        PREV_SIZE=$CURRENT_SIZE
    fi

    if [ -n "$PREV_SIZE" ]; then
        RESULT_DIR="$RESULT_BASE_DIR/result-${PREV_SIZE}"
        mkdir -p "$RESULT_DIR"

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        LOG_FILE="$RESULT_DIR/${PREV_INDEX}-${TIMESTAMP}.txt"

        # Collect kernel logs from previous boot
        journalctl -k -b -1 > "$LOG_FILE"
        echo "Saved logs to $LOG_FILE"
    fi
fi

# Check if current experiment should run
NEXT_STATE=$(get_next_state "$CURRENT_SIZE" "$CURRENT_INDEX")

persist_state "$NEXT_STATE"

echo "Starting experiment: Size=$CURRENT_SIZE, Iteration=$CURRENT_INDEX"
echo "Waiting 10 seconds..."
sleep 10

# Prepare result directory
RESULT_DIR="$RESULT_BASE_DIR/result-${CURRENT_SIZE}"
mkdir -p "$RESULT_DIR"
HELPER_RESULT="$RESULT_DIR/${CURRENT_INDEX}-helper.log"

# Start watchdog, it will automatically reboot the system after bypass
sudo systemctl start watchdog

# Run experiment
MTE_HELPER_RESULT="$HELPER_RESULT" ./1-2.oob-exploit.sh "$CURRENT_SIZE"
sleep 6

dmesg > "$RESULT_DIR/${CURRENT_INDEX}-dmesg.txt"
sync

echo "OOB observation complete"
