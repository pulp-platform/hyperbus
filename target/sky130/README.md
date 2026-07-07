# SkyWater 130 nm (sky130) support

This directory adds the missing ASIC-enablement pieces that let the
technology-dependent part of the PULP HyperBus PHY **elaborate and synthesize
to sky130 standard cells**. It targets the open `sky130_fd_sc_hd` library and
the Yosys flow in [`../../syn/sky130/`](../../syn/sky130/).

It is the practical follow-up to [`../../AUDIT.md`](../../AUDIT.md), whose #1
ASIC blocker was that the design has **no synthesizable delay line** and its
`tc_clk_*` cells are unmapped.

## What is here

| File | Purpose |
|---|---|
| `tech_cells_sky130.sv` | Synthesizable definitions of `tc_clk_inverter`, `tc_clk_gating`, `tc_clk_mux2` so the design maps to sky130 cells **without** the external `tech_cells_generic` dependency. With `SKY130_NATIVE_CELLS` the clock gate is a real `sky130_fd_sc_hd__dlclkp_1` ICG. |
| `configurable_delay.sky130.sv` | A **synthesizable** `configurable_delay` built from a chain of hard `sky130_fd_sc_hd__dlygate4sd3_1` delay cells + a tap mux. Replaces the sim-only `#delay` model and the absent proprietary `generic_delay_*` macro. |
| `hyperbus_phy_sky130.sv` | A minimal, self-contained PHY front-end top wiring the tech-dependent blocks together (clk gen, differential CK, 9× DDR out, RX delay). |

## How to run

```bash
# needs: yosys + the sky130 PDK (installed here via volare, ~/.volare/…)
bash syn/sky130/run.sh
# outputs:
#   syn/sky130/out/hyperbus_phy_sky130.netlist.v   (gate-level netlist)
#   syn/sky130/out/hyperbus_phy_sky130.area.rpt    (area / cell report)
```
Override the library with `SKY130_LIB=/path/to/…__tt_025C_1v80.lib`.

## Result of the minimal synthesis

Top: `hyperbus_phy_sky130`, mapped to `sky130_fd_sc_hd` (tt, 25 °C, 1.8 V).

- **Total cell area ≈ 1249 µm²**, 107 cells, fully mapped (no unmapped logic).
- Key cells: 22 flip-flops (`dfrtp`/`dfrtn`/`dfstp`) for the quadrature clock
  generator + DDR launch registers; 9× `mux2` DDR output muxes; a real
  `dlclkp` integrated clock gate on the differential CK; **32×
  `dlygate4sd3_1`** forming the RX delay line + a `mux4`/`mux2` tap selector.

This proves the PHY front-end is synthesizable on sky130 — the audit's #1
blocker (no synthesizable delay line, unmapped tech cells) is closed for this
scope.

## Hardened macro (OpenLane / LibreLane)

A full RTL-to-GDS harden of `hyperbus_phy_sky130` is provided via
[`../../openlane/hyperbus_phy_sky130/config.json`](../../openlane/hyperbus_phy_sky130/config.json)
(LibreLane, native/nix — no Docker):

```bash
librelane --pdk-root ~/.volare openlane/hyperbus_phy_sky130/config.json
```

Result at `CLOCK_PERIOD = 40 ns` (25 MHz), sky130_fd_sc_hd, 90×90 µm die:

| Metric | Value |
|---|---|
| Instances (incl. fill/tap/CTS) | 1184 |
| Std-cell area | 5349 µm² (34 % util) |
| Route wirelength | 2187 µm |
| Detailed-route + Magic DRC | **0** |
| LVS | **clean** |
| Setup / Hold WNS | **+0.098 ns / +0.423 ns (met)** |

GDS/DEF/ODB/LEF/SPEF land in `runs/<tag>/final/` (git-ignored). Timing
closes comfortably at 25 MHz, matching the sky130 speed reality below.

### Inspect it in the OpenROAD GUI

```bash
librelane --pdk-root ~/.volare --flow openinopenroad --last-run \
  openlane/hyperbus_phy_sky130/config.json
```

(There is also a stand-alone `syn/sky130/inspect.tcl` that places the raw
yosys netlist for `openroad -gui`, but the hardened ODB above is the real
placed-and-routed view.)

## Honest limitations (read before trusting this for silicon)

1. **This is the tech-dependent PHY front-end, not the whole controller.**
   The full `hyperbus` needs pulp-platform `common_cells`, `axi`,
   `register_interface` (CDC FIFOs, arbiters, AXI). Those are not vendored
   here, so the complete controller is out of scope for this minimal pass —
   synthesize it with Bender + the dependencies, then OpenLane.

2. **Synthesis only — no P&R, no STA, no timing sign-off.** There is still no
   SDC. The generated/divided/gated/muxed clocks (see AUDIT.md §6.3) each need
   constraints before any frequency claim is real.

3. **The delay line is coarse.** `dlygate4sd3_1` is ~0.5 ns/tap at the typical
   corner (vs. the ~78 ps/tap the Xilinx IDELAY path assumes), so 32 taps give
   a ~16 ns range at ~0.5 ns resolution — far too coarse to centre a 200 MHz
   DDR eye, and PVT-dependent. It exists to make the design build; a real
   high-speed part needs a characterised/SDC-pinned delay or a DLL.

4. **No I/O ring.** Bidirectional DDR pads for DQ/RWDS and the differential CK
   driver are the integrator's job (Caravel GPIO on sky130).

## sky130 speed reality

On sky130 with the **stock open GPIO** (no custom IO PHY), a source-synchronous
DDR HyperBus is limited to roughly a **10–25 MHz interface clock (~20–50 MB/s
on the 8-bit bus)** — an order of magnitude below HyperBus's rated ~166–200 MHz.
The pad delay/variation, the lack of a fast/differential DDR pad, and the
absence of a DLL for a clean 90° capture are the limiters, not the core logic.

The reference designs [`embelon/wb_hyperram`](https://github.com/embelon/wb_hyperram)
and [`embelon/wrapped_wb_hyperram`](https://github.com/embelon/wrapped_wb_hyperram)
(a Caravel/sky130 tapeout) take the pragmatic route this implies: they run the
HyperRAM clock at **system-clock ÷ 2** and **capture read data with the core
clock** (using RWDS only as a data-valid qualifier), with **no delay line at
all**. For a real sky130 HyperBus, adopting that slow-clock capture scheme is
more robust than porting the PULP fine-delay approach — the delay line here is
provided so the existing PULP RTL still builds.
