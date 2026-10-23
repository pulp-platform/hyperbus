# HyperBus v2

AXI4 controller for the [HyperBus protocol](https://www.cypress.com/file/213356/download),
part of the [PULP platform](https://pulp-platform.org/). Tested with HyperRAM.

`v0.0.10` is the final legacy release with the `hyperbus` top. This branch contains
the redesigned controller; see [CHANGELOG.md](CHANGELOG.md) for release history.

## Features

- 16-1024-bit AXI data; two PHYs require at least 32 bits.
- One or two PHYs, with four chip-select ranks each. Dual-PHY interleaving pairs
  devices at each rank, doubling data bandwidth: four ranks, up to eight devices.
- Per-chip address ranges and timing, staged configuration, and runtime PHY selection.
- Subword transfers, byte strobes and single-beat atomics.
- Clock stopping and transaction segmentation for backpressure and chip boundaries.

## Clocking Options

All three tops keep the AXI frontend, configuration frontend and midend on the
system clock. They share the same physical backend.

### Synchronous

[`hyperbus_synchronous`](src/hyperbus_synchronous.sv) runs the frontend and backend
on `clk_sys_i`, without a system-to-PHY bridge. Choose it when the backend can
share the system clock.

### Isochronous

[`hyperbus_isochronous`](src/hyperbus_isochronous.sv) derives the backend clock from
`clk_sys_i` using a programmable integer divider (minimum 2). It uses isochronous
handshakes for control and spill registers for data, rather than asynchronous
data FIFOs. Choose it for a slower, related PHY clock without a separate clock input.
Divider changes wait for idle and completed backend recovery.

### Asynchronous

[`hyperbus_asynchronous`](src/hyperbus_asynchronous.sv) accepts independent
`clk_sys_i` and `clk_phy_i` clocks. CDC FIFOs carry data; synchronized handshakes
carry commands, configuration and write responses. Choose it for unrelated
system and PHY clock domains.

All variants capture incoming read data using delayed RWDS, so the synchronous
option still contains that source-synchronous clock crossing. TX clock and RX RWDS
delays are programmable. Xilinx delay-line builds require `clk_ref200_i` at 200 MHz.

The [legacy block diagram](docs/axi_hyper.svg) predates this split.

## Configuration

The [register map](docs/regs/hyperbus_cfg_regs.md) occupies a 4 KiB window on a
32-bit Regbus interface. Writes are staged: APPLY drains traffic and activates
the new values; FLUSH drains without applying them. AXI offers must remain stable
until accepted, including during a barrier.

The asynchronous top can replay the last-applied settings after a quiescent
PHY-only reset. See [integration requirements](docs/integration.md) for the reset
conditions and atomic operand encoding.

## Limits

- Ordinary AXI traffic supports INCR and single-beat FIXED requests, not WRAP.
- Atomics require naturally aligned operands and one write-data beat. AtomicCompare
  permits WRAP only to encode operand order; see the integration note.
- Devices must tolerate clock stopping, or the system must provide enough buffering
  to avoid it. The controller does not buffer complete bursts for such devices.
- Unaligned-access coverage is incomplete (see TODOs).

## Simulation

Install Bender and QuestaSim, then obtain Infineon's proprietary model archive
using a vendor login. See [model setup](models/README.md) for licensing and the
optional `make hyper-nonfree-init` helper.

```bash
bender checkout
make models/s27ks0641 CACHED_MODEL_PATH=/path/to/model-archives
bash scripts/run_regression.sh all build/regression
```

Suites: `all`, `fast`, `integration`, `performance`. Performance tests enforce
latency budgets; logs and work libraries stay in the chosen build directory.

Focused control tests need no vendor model. They use Verilator; the divider/reset
runners select OSEDA 2026.09:

```bash
bash scripts/run_atomic_tests.sh build/atomic
bash scripts/run_iso_clock_div_test.sh build/iso_clock_div
bash scripts/run_phy_reset_cfg_test.sh
```

## TODOs

- [ ] Complete unaligned-transfer coverage for dual-PHY and multi-beat traffic.
- [ ] Support additional PSRAM command/address formats.
