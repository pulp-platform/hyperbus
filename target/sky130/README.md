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

## Full controller harden (AXI + dual PHY)

Beyond the minimal PHY front-end, the **complete PULP `hyperbus` controller**
(AXI4-128 + RegBus + dual PHY + CDC FIFOs) also hardens on sky130.

Flow (`../../syn/sky130/gen_full_rtl.sh` → `../../openlane/hyperbus/config.json`):

```bash
# needs bender + sv2v on PATH (prebuilt binaries)
bash -c 'export PATH=/path/to/bender-sv2v:$PATH; \
  zsh syn/sky130/gen_full_rtl.sh && \
  librelane --pdk-root ~/.volare openlane/hyperbus/config.json'
```

`gen_full_rtl.sh` = **bender** (resolve the 4 PULP deps from `Bender.lock`) →
**sv2v** (SystemVerilog → Verilog, `--top hyperbus_lint_wrap` to prune to the
used hierarchy) → one flat `hyperbus_full.v`. It bakes in the fixes needed for
the open frontend: strip sim-only SVA, select the sky130 delay/ICG cells, pin
the `-1` "must-override" parameter defaults, and **widen an sv2v-mis-sized
type-param that otherwise truncated the transaction CDC to 38 bits**.

### Result at 40 MHz (CLOCK_PERIOD = 25 ns), sky130_fd_sc_hd

| Metric | Value |
|---|---|
| Instances | 261,287 |
| Std-cell area | ~1.26 mm² (die 1.14×1.14 mm) |
| Route wirelength | 2.43 m |
| Detailed-route / Magic / KLayout DRC | **0 / 0 / 0** |
| LVS | **clean** |
| Setup / Hold violations | **0 / 0** (WNS +4.37 ns / +1.26 ns) |
| Max-slew / cap / fanout violations | 16556 / 123 / 22 |

Post-route WNS +4.37 ns at 25 ns → critical path ≈ 20.6 ns, i.e. the layout has
**headroom to ~48 MHz**. A pre-PnR STA sweep (worst corner ss_100C) set the
target: 40 MHz is the tightest that closes; abc keeps shrinking the path below
that but slack goes negative.

| Target | WNS (ss) | fmax |
|---|---|---|
| 35 ns | +6.24 | 34.8 MHz |
| 30 ns | +3.29 | 37.4 MHz |
| **25 ns** | **+0.29** | **40.5 MHz** (chosen) |
| 20 ns | −2.71 | fails |

**Caveats for the full controller harden:** the RTL is the sv2v-lowered tree
(open-flow only; a commercial SV synth needs none of the workarounds); the
~16.5k max-slew + 123 max-cap violations come from the unconstrained
generated/gated PHY clocks and high-fanout nets — **no custom SDC**, so this is
a **bring-up harden, not signoff**. The delay line is coarse (see above) and no
I/O ring is included.

### External interface & pin table

Hardened configuration: `NumPhys = 2`, `NumChips = 2`, `AxiDataWidth = 128`,
`UsePhyClkDivider = 1`.

The RAM-facing bidirectional signals are exposed as `_o`/`_i`/`_oe_o` triplets;
on silicon each triplet is **one bidirectional pad** (the `_oe` is internal
tristate control, not a pin). External (HyperBus, RAM-facing) pins:

| Signal | RTL width | Phys pins | Dir | On READ | On WRITE |
|---|---|---|---|---|---|
| `hyper_ck_o` + `hyper_ck_no` | [2]+[2] | 4 | out | differential clock CK/CK# | same |
| `hyper_cs_no` | [2]×[2] | 4 | out | chip-select (1 per chip) | same |
| `hyper_dq_{o,i,oe}` | [2]×8 | 16 | bidir | data **in** | CA + write data **out** |
| `hyper_rwds_{o,i,oe}` | [2] | 2 | bidir | read strobe **in** | byte-mask **out** |
| `hyper_reset_no` | [2] | 2 | out | device reset | same |
| **Total external** | | **28** | | | |

`CK/CK#`, `CS#`, `RESET#` are always controller outputs. `DQ[7:0]` and `RWDS`
are bidirectional and flip direction with the transaction; every transfer
starts with the controller driving a 48-bit Command-Address on `DQ`.

**Internal (SoC-facing, not board pins):** the AXI4 subordinate port
(128-bit `w`/`r` data), the RegBus config port (`rbus_req_*`/`rbus_rsp_*`), and
`clk_phy_i`, `clk_sys_i`, `rst_phy_ni`, `rst_sys_ni`, `test_mode_i`.

### Bandwidth & memory capacity

With `UsePhyClkDivider = 1`, `hyper_ck = clk_phy / 2 = 20 MHz`; DDR doubles it to
**40 MT/s per DQ**:

| Mode | Width | Aggregate |
|---|---|---|
| Per PHY | 8-bit | 320 Mb/s ≈ **40 MB/s** |
| Dual-PHY interleaved | 16-bit | 640 Mb/s ≈ **80 MB/s** |

(At the layout's ~48 MHz headroom, ~96 MB/s. Rated HyperBus at 166–200 MHz CK is
~5–6.4 Gb/s — this open sky130 bring-up is ~10× below rated, as expected without
a fast I/O PHY.)

**HyperRAM chips:** `NumPhys × NumChips = 4` devices max (2 chip-selects per
bus). In dual-PHY interleaved mode, the chips at a matching CS pair into a
16-bit-wide logical memory (2 logical memories over the 4 devices); in
independent mode they are 4 separate 8-bit devices.

### Inspect the hardened layout

```bash
librelane --pdk-root ~/.volare --flow openinopenroad --last-run openlane/hyperbus/config.json  # OpenROAD GUI
librelane --pdk-root ~/.volare --flow openinklayout  --last-run openlane/hyperbus/config.json  # KLayout on final GDS
```

## Honest limitations (read before trusting this for silicon)

1. **Two hardens exist: minimal PHY front-end and full controller.**
   `hyperbus_phy_sky130` (this dir) is just the tech-dependent PHY front-end.
   The full `hyperbus` (AXI4 + RegBus + dual PHY, pulp-platform `common_cells`/
   `axi`/`register_interface`) is hardened separately via `gen_full_rtl.sh` +
   `openlane/hyperbus/` — see "Full controller harden" above. Its RTL is
   sv2v-lowered and depends on Bender-resolved sources, not vendored in-tree.

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
