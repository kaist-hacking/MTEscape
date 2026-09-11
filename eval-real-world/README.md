# Real-World CVE Evaluation

## Overview

This evaluation applies MTEscape to 10 real-world kernel CVEs, each backported onto Linux 6.16 with hardware-tag-based KASAN in asynchronous mode. Each CVE directory is self-contained and ships with the kernel config + backport patch and the corresponding exploit sources.

## Target CVEs

| CVE            | Type | Cache         |
|:---------------|:----:|:--------------|
| CVE-2021-3715  | UAF  | kmalloc-256   |
| CVE-2021-43267 | OOB  | kmalloc-1k    |
| CVE-2022-0185  | OOB  | kmalloc-4k    |
| CVE-2022-2588  | UAF  | kmalloc-256   |
| CVE-2022-34918 | OOB  | kmalloc-cg-64 |
| CVE-2023-4623  | UAF  | kmalloc-1k    |
| CVE-2024-36016 | OOB  | kmalloc-2k    |
| CVE-2024-53141 | OOB  | kmalloc-cg-2k |
| CVE-2024-58240 | UAF  | kmalloc-1k    |
| CVE-2025-21702 | UAF  | kmalloc-1k    |

## Reproducing

Each `CVE-*/` directory follows the same three-step layout. All commands below are run from inside the CVE directory (e.g. `cd eval-real-world/CVE-2022-34918`).

### 1. Build (`1-build.sh`)

Clones Linux 6.16, applies the CVE backport patch from `kernel/patch.diff`, layers the common config (`../common/config`) and the per-CVE config (`kernel/config`), and builds the kernel.

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

Builds the exploit under `exploit/` and launches it. The script refuses to run if `uname -r` does not match the CVE tag, so you cannot accidentally run an exploit against the wrong kernel.

```bash
./3-run.sh
```

Each exploit races the tag fault handler to overwrite the kill switch and bypass panic handling. On success, the kernel stays alive after the exploit runs (check `dmesg` for the tag-check fault and the exploit's own output). On failure, the kernel panics.
