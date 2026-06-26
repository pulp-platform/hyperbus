# HyperBus Controller
 
HyperBus is a fully synthesizable, AXI4-compliant RTL implementation of a HyperBus controller IP.
It abstracts the HyperBus protocol and exposes a standard AXI4 slave interface to the host system,
enabling seamless integration into PULP-based SoCs, FPGAs, and custom ASICs.
 
HyperBus is primarily used for high-bandwidth, low-pin-count off-chip memories — HyperRAM (PSRAM)
and HyperFlash (NOR Flash) — but also supports generic peripherals that implement the HyperBus
electrical and timing specifications.

HyperBus is part of the [PULP (Parallel Ultra-Low-Power) platform](https://pulp-platform.org/).

## Key Features
 
| Feature | Details |
|---|---|
| Host interface | AXI4 slave (read/write, bursts) |
| Device interface | HyperBus protocol (CK/CK#, RWDS, CS#, DQ[7:0]) |
| Supported devices | HyperRAM (PSRAM), HyperFlash (NOR Flash) |
| Configuration interface | Regbus (register-mapped, parameterizable width) |
| Burst support | Any AXI burst length |
| Address width | Fully parameterizable |
| Multi-chip | Multiple CS# lines supported |
| Multi-phy | 1 or 2 device interfaces |
 
## Current limitations

- AXI atomics are **not** supported.
- Only **linear** HyperBus bursts are supported.
- All non-byte accesses must be **aligned to 16-bit boundaries**.
- HyperFlash support is **work in progress** — only HyperRAM has been fully tested.
 

## Quick Start

- **[Getting Started](gs.md)** Clone the repo, install dependencies, and run your first simulation.
- **[Specification](spec.md)** Block diagram, interface description, register map, and implementation details.
- **[Verification](ver.md)** Testbench architecture, test plan, and coverage strategy.
- **[User Manual](um.md)** Integration guide, programmer's guide, and how to run simulation and other flow steps.
- **[HyperBus™ specification](https://www.cypress.com/file/213356/download)**.

## Repository Layout
 
```
hyperbus/
├── src/          # Hardware sources (SystemVerilog RTL)
├── test/         # Testbench and tests
├── target/       # Simulation, FPGA, and other targets setups
├── models/       # Device simulation models (HyperRAM, HyperFlash)
├── padframe/     # Pad-frame wrappers (optional)
└── docs/         # This documentation (MkDocs sources)
```
 
---

## License

Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license. All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see `LICENSE`) or compatible licenses.

