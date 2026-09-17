
# 2-Way Set Associative Cache Controller

A high-performance, synthesizable cache controller design implemented in **SystemVerilog**, featuring a robust, object-oriented verification suite.

---

## 📐 Architecture Overview

This design implements a **2-way set associative cache** with a **write-back policy**. It uses a parameterizable architecture, allowing address widths, block sizes, and set counts to be adjusted to meet specific memory sub-system requirements.

---

## 🧪 Verification Environment

The project includes a professional-grade, **self-checking testbench** architecture designed to ensure total functional correctness.

### Testbench Components

| Component | Description |
|---|---|
| **Generator** | Creates randomized transaction stimuli (Read/Write requests) based on defined constraints. |
| **Driver** | Bridges the Generator to the hardware interfaces, driving signals onto the `cpu_cache_if`. |
| **Monitor** | Observes bus activity in real time, capturing transaction results. |
| **Golden Reference Model (Scoreboard)** | Maintains a "Golden Memory" state and compares every transaction captured by the Monitor against a local associative array model, automatically flagging any data mismatches. |
| **Self-Checking Mechanism** | The scoreboard performs automatic verification, ensuring cache behavior perfectly mirrors the Golden Memory — providing a PASS/FAIL status without manual log inspection. |

---

## ⚙️ Technical Features

- **Parameterized Design** — configurable `ADDRESS_WIDTH`, `DATA_WIDTH`, `BLOCK_SIZE`, and `NUM_SETS`.
- **2-Way Set Associativity** — implements an LRU (Least Recently Used) replacement policy.
- **Modular Interfaces** — uses SystemVerilog interfaces to cleanly abstract communication between the CPU, Cache, and Memory.

---

## 📁 Directory Structure

```
├── RTL/    # Core design sources (Cache Controller, Tag/Data RAMs, Main Memory)
├── Sim/    # Verification environment (Testbench, Scoreboard, Drivers, Monitors, Generators)
└── Docs/   # Interface definitions and technical specifications
```

---

## ✅ Verification Status

The design has been validated using the **Vivado Simulator (XSim)**. The verification suite utilizes a scoreboard with a golden reference model, confirming functional correctness across randomized transaction scenarios with automated pass/fail reporting.

---

*Developed as a high-performance memory subsystem design project.*
