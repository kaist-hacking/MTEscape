# Race Stabilization Evaluation

## Overview

This evaluation compares three race stabilization techniques — *naive*, *CARDSHARK*, and *MTEscape* — by measuring their success rate on 5 real-world OOB CVEs, each backported onto Linux 6.16 with hardware-tag-based KASAN in asynchronous mode.

Each technique (other than *naive*) is exercised in two modes:

- **profiling** — measures the execution-time disparity between the race window center and the DWP point. The measurement is used as the `-d` delay offset for the exploit mode.
- **exploit** — runs the exploit with the measured `-d` offset for many iterations and records, per iteration, whether the DWP point falls inside the OOB race window.

*naive* simply spawns the OOB-write and DWP threads back-to-back with no timing trick, and therefore has no profiling mode.

## Target CVEs

| CVE            | Type | Cache         |
|:---------------|:----:|:--------------|
| CVE-2021-43267 | OOB  | kmalloc-1k    |
| CVE-2022-0185  | OOB  | kmalloc-4k    |
| CVE-2022-34918 | OOB  | kmalloc-cg-64 |
| CVE-2024-36016 | OOB  | kmalloc-2k    |
| CVE-2024-53141 | OOB  | kmalloc-cg-2k |

Only OOB CVEs are evaluated here — UAF vulnerabilities do not involve the race that these techniques stabilize.

## Reproducing

Each `CVE-*/` directory follows the same three-step layout. All commands below are run from inside the CVE directory (e.g. `cd eval-race-stabilization/CVE-2022-34918`).

### 1. Build (`1-build.sh`)

Clones Linux 6.16, applies the CVE backport patch from `kernel/patch.diff` (which also instruments the kernel to publish `oob_window_start`, `oob_window_end`, and `dwp_point`), layers the common config (`../common/config`) and the per-CVE config (`kernel/config`), and builds the kernel.

```bash
./1-build.sh
```

### 2. Install (`2-install.sh`)

Installs the built kernel and registers a `MTEscape (<kernelrelease>)` entry in GRUB.

```bash
sudo ./2-install.sh
```

Reboot and select the newly added entry before proceeding.

### 3. Run (`3-run.sh`)

`3-run.sh` selects the stabilization technique and the mode, builds the exploit under `evaluation/`, and runs it repeatedly (default: 120 iterations, sleeping 5 s between launches). It refuses to run unless `uname -r` matches the CVE tag.

```bash
# naive — no profiling phase
./3-run.sh --naive

# CARDSHARK — first measure the disparity, then run the exploit
./3-run.sh --CARDSHARK --profiling
./3-run.sh --CARDSHARK --exploit

# MTEscape — same two-phase workflow
./3-run.sh --MTEscape --profiling
./3-run.sh --MTEscape --exploit

# override iteration count
./3-run.sh --MTEscape --exploit -i 200
```

Results are collected from `journalctl -k -b` and saved to `log_<method>_<mode>.txt` in the CVE directory.

**Hardware note.** The `-d` delay offsets hard-coded in `3-run.sh` were measured on a Radxa Orion O6 (16 GB RAM). Re-run `--profiling` on other hardware and update the corresponding `D_ARG` values in the script before running `--exploit`.

**Success criterion.** Each iteration emits `oob_window_start`, `oob_window_end`, and `dwp_point` to the kernel log. The attempt succeeds when `dwp_point` falls inside `[oob_window_start, oob_window_end]`. Aggregate success rate is the fraction of iterations that meet this condition.
