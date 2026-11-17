# Fault-Tolerant Multi-Slave AMBA AXI4-Lite to APB3 Interconnect Bridge with SVA

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog%20(IEEE%201800)-blue.svg)]()
[![Protocol](https://img.shields.io/badge/AMBA-AXI4--Lite%20%E2%86%92%20APB3-orange.svg)]()
[![FPGA](https://img.shields.io/badge/Target-Xilinx%20Artix--7%20(xc7a35ti)-green.svg)]()
[![EDA](https://img.shields.io/badge/EDA-Vivado%202026.1%20XSim-purple.svg)]()
[![Coverage](https://img.shields.io/badge/Functional%20Coverage-100.00%25-brightgreen.svg)]()

## Overview

A synthesizable, fault-tolerant **1-to-4 AMBA AXI4-Lite to APB3 Interconnect Bridge** designed in **SystemVerilog** for SoC peripheral subsystems, accompanied by a **baseline vs. optimized architectural benchmark** and a self-checking **SystemVerilog Assertions (SVA) + Functional Coverage** verification suite.

Standard single-slave bridges leave downstream APB address and data lines toggling during idle cycles and risk permanent interconnect deadlock if an external peripheral stalls `PREADY`. **`lp_axi4lite_apb_bridge`** solves both challenges with three hardware enhancements:
1. **1-to-4 One-Hot Peripheral Address Decoding (`PSEL[3:0]`)**: Decodes `ADDR[13:12]` into four 4 KB memory-mapped APB3 peripheral apertures with multiplexed `PRDATA` and `PSLVERR` return paths.
2. **Low-Power Operand Isolation**: Combinational zero-clamping forces `m_apb_paddr`, `m_apb_pwdata`, and `m_apb_pwrite` to `0` whenever `m_apb_psel == 4'b0000`, eliminating dynamic switching power across peripheral routing trees during idle cycles.
3. **16-Cycle Hardware Watchdog Timer (`TIMEOUT_LIMIT = 16`)**: Automatically aborts unresponsive APB peripherals in `ST_ACCESS`, asserts `timeout_err`, maps the abort to `AXI4-Lite SLVERR (2'b10)` on `BRESP`/`RRESP`, and cleanly recovers to `ST_IDLE`.

---

## System Architecture & FSM Microarchitecture

```mermaid
flowchart LR
    subgraph AXI["AXI4-Lite Host Master (32-bit)"]
        AW["AW / W Channels"]
        AR["AR Channel"]
        RESP["B / R Response Channels"]
    end

    subgraph BRIDGE["lp_axi4lite_apb_bridge (200 MHz)"]
        ARB["Write-Priority Arbiter\n& Address/Data Latch"]
        FSM["3-State APB3 FSM\n(ST_IDLE → ST_SETUP → ST_ACCESS)"]
        WDT["16-Cycle Watchdog Timer\n(timeout_err & SLVERR Recovery)"]
        ISO["Low-Power Operand Isolation\n(Zero-Clamp when PSEL == 0)"]
        DEC["1-to-4 Address Decoder\n(ADDR → PSEL[3:0])"]
    end

    subgraph APB["APB3 Peripheral Subsystem (4 × 4 KB)"]
        S0["Slave 0 (0x0000–0x0FFF)"]
        S1["Slave 1 (0x1000–0x1FFF)"]
        S2["Slave 2 (0x2000–0x2FFF)"]
        S3["Slave 3 (0x3000–0x3FFF)"]
    end

    AW --> ARB
    AR --> ARB
    ARB --> FSM
    FSM <--> WDT
    FSM --> DEC
    FSM --> ISO
    DEC --> S0 & S1 & S2 & S3
    ISO --> S0 & S1 & S2 & S3
    S0 & S1 & S2 & S3 -->|PRDATA / PREADY / PSLVERR| FSM
    FSM --> RESP