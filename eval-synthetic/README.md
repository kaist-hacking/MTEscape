# Synthetic Bug Evaluation

## Overview

This evaluation measures the effectiveness of MTEscape and the runtime overhead of the proposed mitigation.

- **Attack effectiveness** — success rate of the MTEscape bypass against synthetic OOB and UAF vulnerabilities across allocation sizes (64, 128, 192, 256, 512, 1024, 2048, 4096 bytes). Measured in §1 and §2.
- **Mitigation performance** — runtime overhead of the mitigation patch, measured with Phoronix Test Suite and lmbench in §3.

## Layout

```
eval-synthetic/
├── evaluation/       # Numbered entry-point scripts (run from here)
│   ├── 0-1.setup.sh           # Env check + dependency clone
│   ├── 0-2.build.sh           # Build all three kernels
│   ├── 0-3.install.sh         # Install kernels + register GRUB entries
│   ├── 1-1.oob-profile.sh     # OOB timing calibration
│   ├── 1-2.oob-exploit.sh     # OOB single run
│   ├── 1-3.oob-reliability.sh # OOB reliability (100× per size, auto-reboot)
│   ├── 1-4.oob-reliability-noise.sh # OOB reliability under stress-ng load
│   ├── 2-1.uaf-exploit.sh     # UAF single run
│   ├── 2-2.uaf-reliability.sh # UAF reliability (100× per size, auto-reboot)
│   ├── 2-3.uaf-reliability-noise.sh # UAF reliability under stress-ng load
│   ├── 3-1.perf-baseline.sh   # Benchmarks on baseline kernel
│   └── 3-2.perf-mitigation.sh # Benchmarks on mitigation kernel
├── exploits/         # Exploit and profiling sources
│   ├── oob-profile.c
│   ├── oob-exploit.c
│   ├── uaf-exploit.c
│   └── util.h
└── kernels/
    ├── common/       # Shared kernel source, build/install helpers, kernel module
    ├── profiling/    # Kernel with timing instrumentation (calibration only)
    ├── baseline/     # Vanilla kernel with MTE enabled (exploit runs)
    └── mitigation/   # Kernel with the MTEscape mitigation patch
```

All numbered scripts are run from `eval-synthetic/evaluation/`.

## 0. Setup

Run the setup scripts sequentially from `0-1` to `0-3`.

### 0-1. Environment Setup (`0-1.setup.sh`)

Verifies the execution environment meets requirements and clones the necessary dependencies:
- Checks ARM64 architecture and MTE support
- Clones Linux kernel 6.16 source
- Installs benchmarks and `stress-ng`

```bash
cd eval-synthetic/evaluation
./0-1.setup.sh
```

### 0-2. Build Kernels (`0-2.build.sh`)

Builds all three evaluation kernels and their corresponding kernel modules:

- **profiling** — kernel with timing instrumentation for calibrating exploit delay parameters.
- **baseline** — vanilla kernel with MTE enabled, used for exploit evaluation.
- **mitigation** — kernel with the MTEscape mitigation patch applied.

Each kernel takes approximately 15 minutes to build, totaling around 45 minutes on Radxa Orion O6.

```bash
./0-2.build.sh
```

### 0-3. Install Kernels (`0-3.install.sh`)

Installs the built kernels and registers them with GRUB for boot selection.

```bash
sudo ./0-3.install.sh
```

After installation, reboot and select the desired kernel from the GRUB menu.

## 1. OOB Exploit Evaluation

The `1-*.sh` scripts demonstrate MTEscape against Out-of-Bounds vulnerabilities.

### 1-1. Timing Calibration (`1-1.oob-profile.sh`)

The default delay values are calibrated for Radxa Orion O6. If running on different hardware or observing low success rates, recalibrate the timing parameters:

```bash
# Boot into the profiling kernel first
./1-1.oob-profile.sh
```

This runs the profiling binary 100 times to collect timing measurements. After running, check the kernel log with `dmesg` to view the measured timing values. Calculate the average of `(oob_window_start + oob_window_end) / 2 - dwp_point` across all runs, then update the `DELAY_OFFSET` value in `eval-synthetic/exploits/oob-exploit.c` accordingly.

### 1-2. Single Exploit Run (`1-2.oob-exploit.sh`)

Executes the OOB exploit once on the baseline kernel:

```bash
# Boot into the baseline kernel first
./1-2.oob-exploit.sh <size>
# Valid sizes: 64, 128, 192, 256, 512, 1024, 2048, 4096
```

### 1-3. Reliability Measurement (`1-3.oob-reliability.sh`)

Runs the exploit multiple times to measure success rate. This script:
- Runs 100 iterations for each allocation size (4096, 2048, 1024, 512, 256, 192, 128, 64)
- Collects kernel logs for each iteration
- Uses a watchdog to automatically reboot after each exploit attempt
- Automatically tracks experiment state across reboots

```bash
# Boot into the baseline kernel first
./1-3.oob-reliability.sh
```

Results are saved to `eval-synthetic/evaluation/evaluation-result-oob/`.

`1-4.oob-reliability-noise.sh` uses the same state and reboot flow with a
separate result directory. It runs the configured `stress-ng` workload,
records CPU utilization over one second, and then starts the
same OOB wrapper and kill-switch observer.

For automated evaluation:
1. Configure this script to run on boot (e.g., via systemd or rc.local).
2. Set the GRUB default boot kernel to `baseline`.
3. The script will automatically iterate through all test configurations.

## 2. UAF Exploit Evaluation

The `2-*.sh` scripts demonstrate MTEscape against Use-After-Free vulnerabilities.

### 2-1. Single Exploit Run (`2-1.uaf-exploit.sh`)

Executes the UAF exploit once on the baseline kernel:

```bash
# Boot into the baseline kernel first
./2-1.uaf-exploit.sh <size>
# Valid sizes: 64, 128, 192, 256, 512, 1024, 2048, 4096
```

### 2-2. Reliability Measurement (`2-2.uaf-reliability.sh`)

Similar to the OOB reliability test, this script runs the UAF exploit multiple times to measure success rate:
- Runs 100 iterations for each allocation size (4096, 2048, 1024, 512, 256, 192, 128, 64)
- Collects kernel logs for each iteration
- Uses a watchdog to automatically reboot after each exploit attempt
- Automatically tracks experiment state across reboots

```bash
# Boot into the baseline kernel first
./2-2.uaf-reliability.sh
```

Results are saved to `eval-synthetic/evaluation/evaluation-result-uaf/`.

For the corresponding noise experiment, run:

```bash
./2-3.uaf-reliability-noise.sh
```

Noise results are saved to
`eval-synthetic/evaluation/evaluation-result-uaf-noise/`.
OOB noise results are saved to
`eval-synthetic/evaluation/evaluation-result-oob-noise/`.


For automated evaluation:
1. Configure this script to run on boot.
2. Set the GRUB default boot kernel to `baseline`.
3. The script will automatically iterate through all test configurations.

## 3. Mitigation Performance Evaluation

The `3-*.sh` scripts measure the performance overhead of the MTEscape mitigation patch.

### 3-1. Baseline Performance (`3-1.perf-baseline.sh`)

Runs benchmarks on the baseline kernel (without mitigation):

```bash
# Boot into the baseline kernel first
./3-1.perf-baseline.sh phoronix  # Run Phoronix Test Suite
./3-1.perf-baseline.sh lmbench   # Run lmbench microbenchmarks
```

### 3-2. Mitigation Performance (`3-2.perf-mitigation.sh`)

Runs the same benchmarks on the mitigation kernel:

```bash
# Boot into the mitigation kernel first
./3-2.perf-mitigation.sh phoronix  # Run Phoronix Test Suite
./3-2.perf-mitigation.sh lmbench   # Run lmbench microbenchmarks
```

### Benchmark Details

**Phoronix Test Suite** runs application-level benchmarks including:
- Apache, Redis, Nginx (server workloads)
- 7-Zip compression
- OpenSSL cryptographic operations

**lmbench** runs microbenchmarks measuring:
- Latency: context switch, syscall (read/write/stat)
- Bandwidth: file read, Unix socket, memory read

Results are saved to `eval-synthetic/evaluation/evaluation-result-perf/`.
