#!/bin/bash

set -e

STATE_FILE="./evaluation-result-oob-noise/eval-state.txt"
RESULT_BASE_DIR="./evaluation-result-oob-noise"

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

if ! command -v stress-ng >/dev/null 2>&1; then
    echo "Error: stress-ng is required for the noise experiment."
    exit 1
fi
for cpu in cpu cpu0 cpu1 cpu2 cpu3; do
    if ! awk -v cpu="$cpu" '$1 == cpu { found = 1 } END { exit !found }' /proc/stat; then
        echo "Error: /proc/stat does not contain $cpu."
        exit 1
    fi
done

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
if [ "$PREVIOUS_RUN" = true ] &&
    [ "${MTE_LAUNCHER_MANAGED:-0}" != 1 ]; then
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

echo "Starting OOB noise experiment: Size=$CURRENT_SIZE, Iteration=$CURRENT_INDEX"
echo "Waiting 10 seconds..."
sleep 10

# Prepare result directory
RESULT_DIR="$RESULT_BASE_DIR/result-${CURRENT_SIZE}"
mkdir -p "$RESULT_DIR"
RESULT_DIR_ABS=$(cd "$RESULT_DIR" && pwd)

STRESS_LOG="$RESULT_DIR_ABS/${CURRENT_INDEX}-stress.log"
CPU_LOG="$RESULT_DIR_ABS/${CURRENT_INDEX}-cpu.log"
CPU_LOG_PARTIAL="${CPU_LOG}.partial"
HELPER_RESULT="$RESULT_DIR_ABS/${CURRENT_INDEX}-helper.log"
DMESG_LOG="$RESULT_DIR_ABS/${CURRENT_INDEX}-dmesg.txt"

# Start the requested load and immediately begin the one-second CPU sample.
stress-ng \
    --cpu 4 \
    --io 4 \
    --vm 4 \
    --vm-bytes 128M \
    > "$STRESS_LOG" 2>&1 &

CPU_STAT_BEFORE=$(awk '$1 == "cpu" || $1 ~ /^cpu[0-3]$/ { print }' /proc/stat)
sleep 1
CPU_STAT_AFTER=$(awk '$1 == "cpu" || $1 ~ /^cpu[0-3]$/ { print }' /proc/stat)

{
    printf '%s\n' "$CPU_STAT_BEFORE"
    printf '%s\n' __SECOND_SNAPSHOT__
    printf '%s\n' "$CPU_STAT_AFTER"
} | LC_ALL=C awk '
    BEGIN {
        names[0] = "cpu"
        names[1] = "cpu0"
        names[2] = "cpu1"
        names[3] = "cpu2"
        names[4] = "cpu3"
    }
    $1 == "__SECOND_SNAPSHOT__" {
        second = 1
        next
    }
    {
        total = 0
        for (i = 2; i <= 9; i++)
            total += $i
        idle = $5 + $6

        if (!second) {
            before_total[$1] = total
            before_idle[$1] = idle
            saw_before[$1] = 1
        } else {
            after_total[$1] = total
            after_idle[$1] = idle
            saw_after[$1] = 1
        }
    }
    END {
        for (i = 0; i < 5; i++) {
            name = names[i]
            if (!saw_before[name] || !saw_after[name]) {
                printf "Error: missing %s CPU snapshot\n", name > "/dev/stderr"
                bad = 1
            }
        }
        if (bad)
            exit 1

        print "sample_seconds=1"
        for (i = 0; i < 5; i++) {
            name = names[i]
            total_delta = after_total[name] - before_total[name]
            idle_delta = after_idle[name] - before_idle[name]
            if (total_delta <= 0) {
                printf "Error: invalid %s CPU delta\n", name > "/dev/stderr"
                exit 1
            }
            busy_percent = 100 * (total_delta - idle_delta) / total_delta
            label = (name == "cpu") ? "aggregate" : name
            printf "%s_busy_percent=%.2f\n", label, busy_percent
        }
    }
' > "$CPU_LOG_PARTIAL"
mv -f "$CPU_LOG_PARTIAL" "$CPU_LOG"
sync "$STRESS_LOG" "$CPU_LOG"

# Start watchdog only after the noise sample and helper output path are ready.
sudo systemctl start watchdog

MTE_HELPER_RESULT="$HELPER_RESULT" ./1-2.oob-exploit.sh "$CURRENT_SIZE"
sleep 6
dmesg > "$DMESG_LOG"
sync

echo "OOB noise experiment completed; inspect $HELPER_RESULT for the kill-switch dump."
