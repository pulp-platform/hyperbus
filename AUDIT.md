# HyperBus v2 — Code, Verification & ASIC-Readiness Audit

**Date:** 2026-07-06
**Repository:** `neuromorphs-openram-hyperbus.git` (PULP HyperBus v2, ETH Zurich / Univ. Bologna)
**Scope:** all RTL (`src/*.sv`, ~2,900 LoC), verification (`test/*.sv`, ~1,600 LoC), build/CI, models, and the untracked `openram/` directory.
**Method:** direct review of the timing-critical RTL plus three focused sub-audits (RTL quality/bugs, verification, ASIC/PDK readiness).

---

## 1. Executive summary

This repository is the **PULP HyperBus v2 controller** — an AXI4-compliant controller and source-synchronous PHY for off-chip **HyperRAM/HyperFlash** DDR memories. It is a mature, well-architected research IP with a clean AXI front end, correct CDC methodology, and a working FPGA (Xilinx) target. It is **simulation- and FPGA-ready**.

It is **not ASIC-ready**, and it contains **no PDK enablement of any kind**. There is no synthesis flow, no timing constraints, no I/O ring, and — most critically — **no synthesizable delay-line macro**, which is the heart of the read-capture PHY. The `openram/` directory, despite the repository name, is an **empty Python virtual-environment** (only `pip` installed): there is no OpenRAM memory compiler, no SRAM macro, and no PDK collateral anywhere in the repo.

### Verdict by dimension

| Dimension | Rating | One-line justification |
|---|---|---|
| Code quality | **Good** | Idiomatic PULP style, clean CDC primitives, strong comments; some lint debt and a stale wrapper. |
| Bug likelihood | **Moderate** | Core datapath sound; risk concentrated in the RWDS read domain and AXI burst conversion. |
| Test coverage | **Moderate** | Two self-checking testbenches + 2,000 random txns, but **zero coverage metrics**, no error-path tests, and commercial-tool + proprietary-model lock-in. |
| ASIC readiness | **Not ready** | No SDC, no synthesis scripts, no I/O ring, **no ASIC delay-line macro**, tech cells unmapped. |
| Sky130 support | **Absent** | No enablement present; feasible only at reduced speed with major PHY/IO work. |
| GF180 support | **Absent** | Same as Sky130, harder — 180 nm cannot hit rated HyperBus speed. |
| TSMC 65 nm | **Absent but most viable** | No enablement present, but the only target that can realistically reach rated performance. |

---

## 2. What the repository contains

### 2.1 RTL (`src/`, synthesizable core)

| Module | Responsibility |
|---|---|
| `hyperbus.sv` | Top level; instantiates cfg regs, AXI slave, PHY, and the four `clk_sys`↔`clk_phy` CDC primitives. |
| `hyperbus_axi.sv` | AXI4 front end: FIFO, atomics filter, ID serializer, AR/AW arbiter, address→CS decode, AXI-beat↔16-bit-word burst conversion. |
| `hyperbus_cfg_regs.sv` | Reg-bus config register file (timings, per-chip address ranges, PHY select). |
| `hyperbus_phy.sv` | Core PHY FSM: command-address (CA) generation, latency, burst timing, R/W/B sequencing. |
| `hyperbus_phy_if.sv` | Instantiates 1–2 PHY lanes + per-lane RX FIFOs; dual-PHY activation. |
| `hyperbus_trx.sv` | Transceiver: DDR TX, RWDS-clocked DDR RX capture, RWDS→system CDC FIFO, pad OE control. |
| `hyperbus_w2phy.sv` / `hyperbus_phy2r.sv` | Write upsizer / read downsizer + aligner FSMs. |
| `hyperbus_clk_gen.sv` | Divide-by-2 quadrature (0/90/180/270°) clock generator. |
| `hyperbus_clock_diff_out.sv` | Gated differential output clock (CK/CK#). |
| `hyperbus_ddr_out.sv` | Single-bit mux-based DDR output cell. |
| `hyperbus_delay.sv` | Wrapper around the configurable tap-delay line (RX/TX phase shift). |
| `hyperbus_pkg.sv` | Types, config struct, reset-value function. |
| `hyperbus_synth_wrap.sv` | Flat-port lint/synth wrapper (`hyperbus_lint_wrap`). |
| `hyperbus_stub.sv` | All-zeros tie-off stub. |

### 2.2 Models, targets, verification, build

- **`models/`** — `configurable_delay.behav.sv` (non-synthesizable `#delay` sim model) and `configurable_delay.fpga.sv` (Xilinx `IBUF` placeholder, no actual delay). `models/README.md` documents a proprietary Cypress/Infineon `s27ks0641` HyperRAM sim model (downloaded at build time) and references a `generic_delay_D4_O1_3P750_CG0.behav.sv` macro **that is not present in the repo**.
- **`target/xilinx/`** — real `IDELAYE2`/`IDELAYCTRL` delay lines for FPGA.
- **`test/`** — two class-based testbenches on the PULP `axi_test` library (directed `hyperbus_tb` + constrained-random `axi_hyper_tb`), fixtures, and an alternate DUT wrapper.
- **Build/CI** — `Bender.yml` (file lists + targets), `Makefile` (QuestaSim compile/run + Infineon model download), `.gitlab-ci.yml` (vsim compile + two sim regressions). **No synthesis stage anywhere.**

### 2.3 The `openram/` directory — nothing usable

`openram/` is **untracked** (not in git; `.gitignore` scope) and is a bare Python `venv`: `pyvenv.cfg` + `bin/` symlinks to a system Python 3.12 + a `site-packages` containing only `pip`. **No OpenRAM install, no SRAM macros, no LEF/LIB/GDS, no PDK config.** All `sky130`/`openroad`/`openlane` string matches in the tree resolve to pip vendor files — false positives. The repository name notwithstanding, **there is currently no memory-compiler or PDK integration here.**

---

## 3. Code quality

**Strengths**

- Consistent ETH/PULP house style: `_d`/`_q` naming, `FFARN`/`FFAR` reset macros, labeled `proc_*` blocks, extensive parameterization (AXI width 16–1024, addr width, NumChips, NumPhys, FIFO depths).
- **Correct CDC methodology** between `clk_sys` and `clk_phy`: `cdc_2phase` for control/B-response, `cdc_fifo_gray` for TX/RX data.
- Consistent async-active-low reset throughout; coherent dual-reset-domain structure.
- Three clean enum FSMs with `_d = _q` defaults; strong intent-revealing comments in the PHY latency logic.
- Non-synthesizable constructs (`initial`, assertions) are properly guarded with `pragma translate_off` / `` `ifndef SYNTHESIS `` / `` `ifndef VERILATOR ``.

**Weaknesses / lint debt**

- **Implicit net:** `rx_rwds_clk_n` is used (`src/hyperbus_trx.sv:207,217`) but never declared → implicit wire; fails `default_nettype none`.
- **Dead signals:** `phys_in_use` assigned but unread (`src/hyperbus_axi.sv:164-166`); `is_16_bw`/`is_8_bw` declared, never used (`src/hyperbus_phy2r.sv:53`).
- **`parameter … = -1` "must-override" idiom** used as `int unsigned` (`src/hyperbus.sv:10-25`, `src/hyperbus_phy2r.sv:8-12`) — a forgotten override silently becomes a huge positive number instead of erroring.
- **Width truncations:** 32-bit `wmask` OR-ed against 1–16-bit config fields then truncated (`src/hyperbus_cfg_regs.sv:92-103`); `int` timer constant truncated to 16 bits (`src/hyperbus_phy.sv:437`).
- The AXI burst-length conversion block (`src/hyperbus_axi.sv:316-348`) is essentially uncommented and hard to review.

---

## 4. Bug likelihood — ranked findings

Severity is for an ASIC context (silicon is unforgiving of the clocking hazards). "Author-flagged" means an in-RTL TODO already acknowledges the risk.

1. **[HIGH] Stale synth/lint wrapper will not elaborate.** `src/hyperbus_synth_wrap.sv:136` passes `.IsClockODelayed(...)`, but `hyperbus.sv` renamed this parameter to `UsePhyClkDivider` (`src/hyperbus.sv:12`). `hyperbus_stub.sv` likewise has an outdated port list. The lint wrapper — the natural synthesis/CI entry point — is **out of sync with the DUT and errors on elaboration.** *Verified.*

2. **[HIGH, author-flagged] Unsynchronized combinational async-reset in the RWDS read domain.** `src/hyperbus_trx.sv:177` derives `rx_rwds_soft_rst` combinationally and uses it as an **async reset** on the RX capture flops (`:180-203`), while `rx_rwds_clk_ena` crosses from `clk_i` into the free-running RWDS clock domain **without a synchronizer**. Reset deassertion is unsynchronized → metastability / first-word capture race. The RTL asks "TODO: is this safe?" (`:176`).

3. **[MED/HIGH] RX FIFO push ignores back-pressure.** `rx_rwds_fifo_valid` is hard-tied high after the first edge and data is pushed every RWDS edge **without checking `rx_rwds_fifo_ready`** (`src/hyperbus_trx.sv:180-183`). Overflow is prevented *only* by the PHY suspending the read clock (`src/hyperbus_phy.sv:202-204`). If FIFO depth / suspend latency is mis-sized for a given `RxFifoLogDepth`+`SyncStages`, read data is **silently dropped** — guarded only by a sim-only assertion (`:231-233`).

4. **[MED] AXI burst-length conversion is opaque and off-by-one-prone.** `src/hyperbus_axi.sv:316-348` mixes AXI `size` (log2 bytes) with `NumPhys` (lane count) and hand-codes per-size address-bit subtractions; the alignment assertion is **commented out** (`:546-548`). High likelihood of edge-case errors for narrow/unaligned bursts; hard to prove correct by reading.

5. **[MED] Missing write-error reporting.** `src/hyperbus_phy.sv:185` hard-codes `b_error_o = 1'b0 // TODO`. The B channel always returns OKAY — device/protocol write errors are never surfaced.

6. **[MED] Implicit cross-module guard on transaction latching.** `src/hyperbus_phy.sv:267-268` asserts `trans_ready_o` in Idle but only latches when no B is pending; safe today only because the AXI side gates on `trans_active_q` (`src/hyperbus_axi.sv:274`) — a latent hazard if upstream gating changes.

7. **[MED, inherent] Generated/divided/gated/muxed clocks are SDC-dependent hazards.** The divide-by-2 quadrature generator (`src/hyperbus_clk_gen.sv`), DDR clock-mux (`src/hyperbus_ddr_out.sv:29`), and gated differential CK (`src/hyperbus_clock_diff_out.sv:35`) are standard source-synchronous techniques but are only safe with matching constraints. The RTL warns that `tx_clk_ena_q` must arrive before `tx_clk_90` or the gate glitches (`src/hyperbus_trx.sv:78-79`) — **no such constraint ships in the repo.**

**TODO/FIXME inventory:** only 5 markers total (`hyperbus_trx.sv:78,176`; `hyperbus_phy.sv:29,185`; `hyperbus_phy_if.sv:29`) — the risky spots are acknowledged rather than hidden, but they cluster exactly on the ASIC-critical RWDS/clocking path.

---

## 5. Test coverage

**What exists:** two self-checking, class-based (non-UVM) testbenches on the PULP `axi_test`/`reg_test` libraries:

- **Directed** (`test/hyperbus_tb.sv` + `fixture_hyperbus.sv`): ~120 hand-written transfers with an associative-array reference model that `$fatal`s on mismatch/X; drives the **real proprietary `s27ks0641` model through pin-level bidirectional pads** with SDF timing. Uses genuinely asymmetric clocks (`clk_sys=4 ns`, `clk_phy=6 ns`).
- **Constrained-random** (`test/axi_hyper_tb.sv`): `axi_rand_master` + library `axi_scoreboard`, 1,000 writes + 1,000 reads, reconfigured per-PHY and re-run.

**What is actually exercised:** AXI read/write with read-back checking; all transfer sizes (8–128 bit); burst lengths up to `len=4090` (forcing controller burst-splitting); wide + narrow bursts; aligned + some unaligned accesses; write strobes / sub-word writes; dual-PHY interleaving (`NumPhys=2`); multiple CS; variable-latency mode; basic config-register writes.

**Gaps (tapeout-relevant):**

- **No coverage of any kind** — zero `covergroup`/`coverpoint`/`cover property`, no code/toggle coverage in the Makefile or CI. Pass/fail is scoreboard + `grep "Error:"` on logs. **There is no quantitative measure of what the 2,000 random transactions actually hit.**
- **No error-path testing** — no `SLVERR`/`DECERR` injection, no out-of-range decode test, no illegal/unaligned/FIXED/WRAP-burst rejection (random master is constrained to INCR only). The commented-out `access_16b_align` assertion is never proven.
- **CDC under-stressed in the high-volume suite** — `test/dut_if.sv:147-149` ties `clk_phy_i = clk_sys_i`, so the 2,000-txn random run does **not** stress the sys↔phy crossing.
- **No mid-traffic reset**, no clock-stop timing assertion, no systematic X-checking, essentially **no SVA** (3–4 trivial elaboration asserts only).
- **HyperFlash and byte-aligned non-byte-size accesses:** untested (open README ToDos).
- **Config register file:** only a couple of fields poked; no read-back, reset-value, or error-response checks.

**CI / reproducibility:** `.gitlab-ci.yml` requires **QuestaSim** and a **privately-staged copy of the proprietary Infineon model** (`before_script` copies from `/home/ci-pulp/`). Pass/fail is grep-based (a hang or unmatched message passes). The TBs lean on `axi_test::` classes, `$sdf_annotate`, and the vendor model's `specify` timing — **none of which Verilator/Icarus support**, and there is no open-source sim target. **A third party cannot regress this without a commercial license and manual acceptance/download of non-free IP** — a significant open-source blocker.

---

## 6. ASIC readiness & PDK support

### 6.1 The delay line is the #1 blocker

The source-synchronous read path centers a programmable delay (32 taps @ ~78 ps ≈ 2.5 ns) on RWDS. `Bender.yml` selects the `configurable_delay` body by target — and **there is no ASIC variant**:

- **Sim:** `models/configurable_delay.behav.sv:36` — transport `#delay`, non-synthesizable.
- **FPGA generic:** `models/configurable_delay.fpga.sv` — Xilinx `IBUF`, no actual delay (placeholder).
- **Xilinx real:** `target/xilinx/hyperbus_{clk,rwds}_delay.sv` — `IDELAYE2` + `IDELAYCTRL`, bypassing the wrapper.
- **ASIC:** **none.** For a plain ASIC build, `src/hyperbus_delay.sv` instantiates `configurable_delay` with **no synthesizable body linked → elaboration fails.** The referenced hard macro (`generic_delay_D4_O1_3P750_CG0.behav.sv`) is documentation-only and **absent**.

An ASIC needs a **characterized, monotonic, PVT-tolerant digitally-selectable delay** (~2.5–3.75 ns, <~80 ps taps): a hand-built standard-cell delay chain + mux tree with an SDC that models per-tap delay and disables STA optimization, a DLL hard IP, or a self-calibrating macro. **No Sky130/GF180/TSMC65 drop-in IDELAYE2 equivalent exists** — this must be designed and characterized and is the dominant PHY risk.

### 6.2 Everything else missing for a tapeout

- **Tech-cell mapping:** `tc_clk_inverter`, `tc_clk_gating`, `tc_clk_mux2` (from `tech_cells_generic`) sit on **clock nets** (DDR mux, RWDS capture, differential CK) and must map to real characterized clock-tree cells (CKINV/CKMUX2/ICG), not generic logic. No mapping provided.
- **Constraints (SDC):** none. No `create_clock` for `clk_sys`/`clk_phy`; no `create_generated_clock` for the divide-by-2, 90°-phase, delay-line, or gated/muxed/inverted RWDS clocks; no I/O delays; no `set_case_analysis` on `test_mode_i`; no CDC exceptions for the `cdc_*` crossings.
- **I/O ring:** none. Direction is surfaced as `*_oe_o` nets only — no bidirectional DDR pads for DQ[7:0]/RWDS, no differential/pseudo-diff driver for CK/CK#, no ESD/level-shifters. Pad instantiation is entirely the integrator's job.
- **Flow & collateral:** no Yosys/OpenROAD/OpenLane/DC/Genus/Innovus scripts; no floorplan/DEF; no UPF/CPF power intent; no LEF/LIB/PDK reference. The only TCL (`scripts/start.tcl`) is a vsim run script.

### 6.3 Clock architecture (constraint burden)

Clocks: `clk_sys`, `clk_phy`, generated `clk_phy_0`/`clk_phy_90` (via divide-by-2 **or** delay line, per `UsePhyClkDivider`), and the externally-sourced `rx_rwds_clk` (delayed → gated → muxed → inverted). Every derived clock must be hand-declared in SDC. The 90° phase has **no PLL/MMCM on ASIC** — it comes from a divider's opposite edge or an uncharacterized delay line, so a true PVT-stable 90° at speed is a physical-design problem, not just a constraint problem.

---

## 7. Open-source PDK viability

None of the three targets is *supported* today (zero enablement exists). Ranked by realistic feasibility:

### Sky130 (SkyWater 130 nm) — **feasible only at reduced speed, with major PHY/IO work**
- RTL is standard-cell synthesizable after `tc_*` remapping (Sky130 HD/HS libs have clock inverters, ICGs; a glitch-safe clock mux needs care).
- **Delay line:** must be custom-built and characterized — no hard IP; 130 nm PVT spread makes a robust calibrated delay the hard part.
- **I/O:** the open Sky130 GPIO is slow (tens of MHz) and has **no fast DDR-capable or differential pad** — the real bottleneck. HyperBus at its rated ~200 MHz DDR (3.2 Gb/s) is **not achievable**; expect operation at a small fraction of rated clock.
- **Memory:** if the intent (per the repo name) is an on-die SRAM behind this AXI port, OpenRAM can target Sky130 — but **nothing here is wired up**, and HyperBus is an *external-memory* controller, so that would be a different architecture.

### GF180 (GlobalFoundries 180 nm) — **feasible but slower than Sky130**
- Same enablement gaps as Sky130. At 180 nm, achievable logic/IO speed is lower still, so rated HyperBus performance is firmly out of reach; useful only as a low-speed / educational bring-up.

### TSMC 65 nm — **most viable of the three (at rated performance), but commercial**
- 65 nm comfortably supports ≥200 MHz DDR logic and has **mature commercial DDR-capable I/O, differential drivers, and delay-line/DLL/PLL IP** — the pieces Sky130/GF180 lack. This is the only target where the PHY can plausibly hit rated speed.
- It is **not open-source**: PDK/IP/tools require foundry NDAs and (typically) commercial EDA — the opposite of the open-flow reproducibility this project would need to add. No 65 nm collateral exists here either.

---

## 8. Prioritized recommendations

**To reach a first ASIC tapeout (any PDK):**
1. Provide a **synthesizable, PVT-characterized `configurable_delay`** (std-cell chain or DLL) — unblocks elaboration and the read PHY.
2. Fix the **stale `hyperbus_synth_wrap`/`hyperbus_stub`** parameter mismatch so the lint/synth entry point elaborates.
3. Add **PDK tech-cell mappings** for the `tc_clk_*` cells.
4. Author the **full SDC** (primary + generated + gated/muxed/inverted clocks, I/O delays, `set_case_analysis`, CDC exceptions).
5. Add the **I/O ring**: bidirectional DDR pads (DQ/RWDS), differential CK driver, matched output timing.
6. Add a **synthesis + P&R flow** and (for open PDKs) an **OpenLane/OpenROAD** config; add **UPF** and floorplan.

**To de-risk correctness before tapeout:**
7. Resolve the **RWDS async-reset synchronization** (#4.2) and the **no-back-pressure RX FIFO push** (#4.3).
8. Document/verify the **AXI burst-length conversion** (#4.4); re-enable the `access_16b_align` assertion.
9. Implement **write-error (`b_error`) reporting** (#4.5).

**To make verification tapeout-grade:**
10. Add **functional + code/toggle coverage** and gate CI on it.
11. Add **error-path and full-AXI-randomization** tests (FIXED/WRAP, wait-states, reordering); run the random suite with **asymmetric `clk_sys`/`clk_phy`**.
12. Provide an **open behavioral HyperRAM model** and a **Verilator/Icarus** target so the flow is reproducible without QuestaSim or the proprietary Infineon model; make CI pass/fail **exit-code-based**, not grep-based.

**Repository hygiene:**
13. Remove or `.gitignore` the empty `openram/` venv (it implies a memory-compiler integration that does not exist), or actually populate it with the intended OpenRAM flow and document the goal.
