# MTEscape

This repository contains the evaluation artifacts for the paper "MTEscape: Bypassing Asynchronous Kernel MTE via Conventional Memory Corruption Vulnerabilities".

## Overview

MTEscape is a kernel exploitation technique that bypasses ARM Memory Tagging Extension (MTE) in asynchronous mode by exploiting the race condition between memory corruption and tag fault handling.

This artifact reproduces the three evaluations reported in the paper:

1. **Synthetic bugs** — success rate of MTEscape against synthetic OOB/UAF vulnerabilities across allocation sizes, plus the runtime overhead of the proposed mitigation.
2. **Real-world exploits** — end-to-end MTEscape exploits against 10 real-world kernel CVEs backported onto Linux 6.16 with MTE enabled.
3. **Race stabilization** — comparison of race stabilization techniques (*naive*, *CARDSHARK*, *MTEscape*) on backported real-world kernel CVEs.

## Hardware Requirements

This artifact requires ARM64 architecture with MTE support. Compatible devices include:

- Radxa Orion O6
- Google Pixel 8 or later

While the exploits can run in virtualized environments (e.g., QEMU), race timing behavior may differ significantly from native execution.

## Repository Structure

```
MTEscape-artifact/
├── eval-synthetic/          # Synthetic OOB/UAF + mitigation overhead
├── eval-real-world/         # End-to-end real-world CVE exploits
└── eval-race-stabilization/ # Race stabilization comparison (naive / CARDSHARK / MTEscape)
```

Each subdirectory is self-contained and has its own `README.md` with detailed setup and run instructions:

- [`eval-synthetic/README.md`](eval-synthetic/README.md)
- [`eval-real-world/README.md`](eval-real-world/README.md)
- [`eval-race-stabilization/README.md`](eval-race-stabilization/README.md)

## Publication

```bibtex
@inproceedings{Kim2026MTEscape,
  author = {Kyeongmin Kim and Insu Yun},
  booktitle = {Proceedings of the 2026 ACM SIGSAC Conference on Computer and Communications Security},
  title = {{MTEscape: Bypassing Asynchronous Kernel MTE via Conventional Memory Corruption Vulnerabilities}},
  year = {2026}
}
```
