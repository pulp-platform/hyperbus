# User Manual

This manual is intended for engineers integrating HyperBus into a SoC or FPGA design, and
for developers running the digital implementation flows.

---

## How to Configure and Integrate the IP

### Step 1 — Declare the dependency in Bender

Add HyperBus to your project's `Bender.yml`:

```yaml
dependencies:
  hyperbus:
    git: https://github.com/FondazioneChipsIT/hyperbus.git
    rev: <tag-or-commit>
```

Then run:

```bash
bender update
```

### Step 2 — Instantiate `hyperbus` TODO!!!

Instantiate the top-level module in your SoC integration layer:

```systemverilog
TODO!!!

```

!!! note
    Exact port names should be verified against `src/hyperbus.sv` in the repository.
    <!-- TODO: confirm port names from RTL -->

### Step 3 — Connect the pad-frame TODO!!!

Use the wrappers in `padframe/` to connect HyperBus signals to the chip's IO cells.
These wrappers handle bidirectional pads (`DQ`, `RWDS`) with correct enable logic.

### Step 4 — Configure via Regbus

Before issuing AXI transactions, configure the controller's timing registers to match
your target device's datasheet. Minimum required configuration:

1. Write `tACC` (access / initial latency) — match the device's latency code setting
2. Write `tRC` (read cycle time) — minimum time between two consecutive reads
3. Write `tCSHI` (CS# high time) — minimum CS# deassert time
4. Set latency mode: fixed (0) or variable (1), matching the device's CR0 setting

See [Specification → Register Map](spec.md#register-map) for the full register list.

---

## Design Constraints TODO!!!

### Timing Constraints

The following constraints must be included in your synthesis / PnR flow:

```tcl
# System clock — adjust frequency to your design
create_clock -name clk_i -period 10.0 [get_ports clk_i]

# PHY clock — typically 2x or same frequency as clk_i
create_clock -name clk_phy_i -period 5.0 [get_ports clk_phy_i]

# HyperBus output clock — derived from clk_phy_i
# (clock-domain crossing to PHY is handled inside the IP)

# False paths on async reset (if used)
# set_false_path -from [get_ports rst_ni]
```

!!! warning
    The HyperBus protocol has tight IO timing requirements. Consult the device datasheet for
    `tIS` (setup) and `tIH` (hold) on DQ/RWDS, and ensure your IO constraints account for
    PCB trace delays.

### IO Constraints

- `DQ[7:0]` and `RWDS` are bidirectional — use tristate IO cells with the enables driven
  from the padframe wrapper.
- `CK`/`CK#` should be routed as a differential pair; avoid stubs.
- `CS#` is a slow control signal; standard IO cell drive strength is sufficient.

---

## Programmer's Guide

### Basic Read Transaction

To perform a single 16-bit read from HyperRAM address `0x00001000`:

1. Ensure the controller is configured (see Step 4 above).
2. Issue a 2-byte AXI4 read to the address mapped to HyperRAM in your memory map.
3. The controller will:
    - Assert `CS#`
    - Send the CA (Command/Address) packet: read, memory space, address `0x00001000`
    - Wait for initial latency (as signaled by `RWDS`)
    - Sample 2 bytes from `DQ`, latched on `RWDS` edges
    - Deassert `CS#` and return data on the AXI R channel

### Basic Write Transaction

1. Issue a 2-byte AXI4 write to the target HyperRAM address.
2. The controller will:
    - Assert `CS#`
    - Send the CA packet: write, memory space, target address
    - Wait for fixed write latency
    - Drive data on `DQ` with `RWDS` as byte strobe
    - Deassert `CS#` and return `OKAY` on the AXI B channel

### Accessing HyperRAM Configuration Registers

HyperRAM devices expose internal configuration registers (CR0, CR1) at a separate
*register space* address (as opposed to *memory space*). To access them:

1. Set the register-space bit in the CA packet — this is controlled by the address mapping
   in your SoC integration. Consult the device datasheet for the register space address.
2. Perform an AXI read or write to that address.

!!! note
    The distinction between memory space and register space in HyperRAM is encoded in bit 46
    of the CA packet. Consult the HyperBus Specification §8 for the full CA format.

---

## How to run flow steps

TODO!!!

---

## How to simulate TODO!!!

† * `models/s27ks0641/s27ks0641.v` will download externally provided peripheral simulation models, some proprietary and with non-free license terms, from their publically accessible sources; see `Makefile` for details. By running `models/s27ks0641/s27ks0641.v` or the default target `run`, you accept this.*

To run a simulation you need [Bender](https://github.com/pulp-platform/bender) and Questasim. Export your path to include your bender binary, and then:

```bash
bender update
make run #(will download proprietary models from Infineon !!)
```
 ---