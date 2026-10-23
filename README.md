# HyperBus v2

AXI4 controller for [HyperBus](https://www.cypress.com/file/213356/download),
part of the [PULP platform](https://pulp-platform.org/). Tested with HyperRAM.
`v0.0.10` is the final legacy release; see [CHANGELOG.md](CHANGELOG.md).

## Features

- 16-1024-bit AXI data; two PHYs require at least 32 bits.
- One or two PHYs, four chip-select ranks each. Dual-PHY mode interleaves paired
  devices per rank: up to eight devices and twice the data bandwidth.
- Per-chip address ranges/timing, staged configuration and runtime PHY selection.
- Subword transfers, byte strobes and single-beat atomics.
- Clock stopping and segmentation for backpressure and chip boundaries.

## Clocking Options

All tops keep the AXI frontend, configuration frontend and midend on `clk_sys_i`.

### Synchronous

[`hyperbus_synchronous`](src/hyperbus_synchronous.sv) also runs the backend on
`clk_sys_i`, without a system-to-PHY bridge. Use it for a shared clock.

### Isochronous

[`hyperbus_isochronous`](src/hyperbus_isochronous.sv) derives the backend clock
through a programmable integer divider (minimum 2). Control uses isochronous
handshakes; data uses spill registers. Use it for a slower, related PHY clock.
Divider updates wait for idle and backend recovery.

### Asynchronous

[`hyperbus_asynchronous`](src/hyperbus_asynchronous.sv) takes independent system
and PHY clocks. CDC FIFOs carry data; synchronized handshakes carry commands,
configuration and write responses. Use it for unrelated clocks.

All variants capture read data using delayed RWDS, including a source-synchronous
crossing in the synchronous top. TX CK and RX RWDS delays are programmable.
Xilinx delay-line builds require `clk_ref200_i` at 200 MHz.

## Configuration and Limits

The [register map](docs/regs/hyperbus_cfg_regs.md) uses a 4 KiB, 32-bit Regbus
window. Writes are staged: APPLY drains traffic and activates settings; FLUSH
drains without applying them. AXI offers remain stable until accepted.

- Ordinary bursts support INCR and single-beat FIXED, not WRAP.
- Atomics require naturally aligned operands in one beat. AtomicCompare uses WRAP
  only for operand ordering; see [integration requirements](docs/integration.md).
- Devices must tolerate clock stopping, or sufficient buffering must prevent it.
- Only the asynchronous top supports quiescent PHY-only reset and configuration replay.

See [pad timing](docs/pad_timing_integration.md) for electrical margins.

## Simulation

Install Bender and QuestaSim, then obtain the [vendor memory model](models/README.md):

```bash
bender checkout
make models/s27ks0641 CACHED_MODEL_PATH=/path/to/model-archives
bash scripts/run_regression.sh all build/regression
```

See [Verification](docs/verification.md) for suites and vendor-free Verilator tests.

## TODOs

- [ ] Complete unaligned-transfer coverage for dual-PHY and multi-beat traffic.
- [ ] Support additional PSRAM command/address formats.
