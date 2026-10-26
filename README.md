# HyperBus v2

This peripheral implements an AXI4-compliant interface for the HyperBus protocol, described [in its specification](https://www.cypress.com/file/213356/download). HyperBus v2 is part of the [PULP (Parallel Ultra-Low-Power) platform](https://pulp-platform.org/).

Hyperbus is mainly used for off-chip memories (HyperFlash and HyperRAM), but also supported by some generic peripherals.

## Release 0.0.10

This is the final release of the legacy controller architecture. It retains the
`hyperbus` top, shared timing registers and `hyper_reset_no`; the controller and
configuration redesign is not included. See [CHANGELOG.md](CHANGELOG.md) for the
changes and migration notes for every tag since 0.0.1.

When migrating from 0.0.9, replace `IsClockODelayed` with `UsePhyClkDivider`
(inverted polarity), review the widened delay controls, and update chip-range
register offsets from `0x2c` to `0x30` for a 32-bit register bus.

## Features

The AXI data widths are parameterizable from 16 to 1024, with transfers of all sizes possible. It is also possible to decide how many memories to connect on the same HyperBUS to set the overall available memory.

Multiple memories on the same bus are placed contiguously in the address memory map and selected through their dedicated CS. At runtime, one can communicate to the controller the size
of the HyperRAMs, and the controller will demultiplex the transactions accordingly. Also, one can choose how many HyperBUS interfaces (1 or 2) to expose. Both buses will have the same number of CSs.
When exposing 2 HyperBUSes, the pair of memories on the same chip select will be mapped as interleaved: each memory will be seen as a memory block of 16-bit width. Doing so will double the maximum achievable bandwidth, up to 6.4 Gbps,
doubling the pin count.

The main restrictions are as follows:

- Atomics are not supported.
- AXI INCR bursts and single-beat FIXED requests are supported; multi-beat FIXED
  and WRAP bursts are not supported.
- All accesses except byte-size accesses must be aligned to 16-bit boundaries.
- Only communication with HyperRAMs has been tested. Support for flash is WIP.

The address width is also fully parameterizable. We support bursts of any size permitted by AXI and stalling through PHY-level clock stopping and protocol-level burst splitting. We do _not_ buffer bursts to support devices without the clock stop feature; please ensure your device supports clock stop or ensure sufficient buffering upstream.

The configuration register interface uses the minimal Regbus protocol. Data and address widths are parameterizable, but register sizes must be a power of two larger than 16 bits.

Dual-PHY builds can select one or both PHYs at runtime through `phys_in_use` and
`which_phy`. Changing the active PHY count changes data packing and addressing;
update configuration while the controller is idle.

## Architecture

The block diagram outlines the system-clock and PHY-clock paths, plus the delayed
incoming RWDS read-capture clock. `UsePhyClkDivider=1` divides `clk_phy_i` by two
to generate quadrature PHY clocks. With `UsePhyClkDivider=0`, each PHY uses a
programmable TX clock delay instead. Xilinx delay-line builds additionally require
`clk_ref200_i` at 200 MHz.

![HyperBus v2 block diagram](./docs/axi_hyper.svg)

## Simulation

Simulation requires [Bender](https://github.com/pulp-platform/bender), QuestaSim
and Infineon's proprietary S27KS0641 model. Download the vendor archive after
logging in and pass its containing directory through `CACHED_MODEL_PATH`:

```bash
bender checkout
make run CACHED_MODEL_PATH=/path/to/model-archives
```

`make hyper-nonfree-init` optionally installs the pinned internal model helper;
it requires access to that repository and is not required for local archives.
See [models/README.md](models/README.md) for model setup and license information.

## ToDos

- [ ] Support byte-aligned accesses for non-byte-size transfer
- [ ] Test HyperFlash
- [ ] PSRAM support through additional CA decoder
