# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

Historical entries cover tags with or without GitHub releases. Dates use tag
timestamps for annotated tags, otherwise the tagged commit date.

## [0.1.0] - 2026-10-26

Controller redesign; not a drop-in replacement for 0.0.x.

### Added

- Separate synchronous, isochronous and asynchronous tops.
- PeakRDL-generated registers, C header and register map.
- Per-chip staged configuration (APPLY/FLUSH) and quiescent asynchronous PHY-reset replay.
- RWDS sampling/OE timing controls and device-specific retained DQ drive.
- Functional, parameter, performance and pad-delay regressions.

### Changed

- Separate frontend, configuration, midend and backend; move host buffering into the midend.
- Narrow counters/registers and remove duplicate configuration storage.

### Fixed

- Atomic validation and Compare operand pairing.
- Narrow/generic read accounting and address overflow checks.
- Wait for backend recovery before divider updates; preserve CS setup on segment restarts.

### Compatibility

- Replace legacy `hyperbus` instantiations and migrate parameters/ports.
- Use the new 32-bit, 4 KiB Regbus map; update firmware and APPLY staged settings.
- Limit each PHY to four chip-select ranks; chip ranges must be 4 MiB-aligned, ordered and non-overlapping.
- Remove `hyper_reset_no`; drive memory reset from the platform.

## [0.0.10] - 2026-10-26

Final legacy HyperBus v2 release, retaining `hyperbus`, shared timing registers
and controller-driven memory reset. Register offsets below assume 32-bit Regbus.

### Added

- Configurable CS-to-clock delay (`csn_to_ck_cycles`, default 0).
- Xilinx 7-series clock/RWDS delays with a 200 MHz reference.
- Authenticated/cached models via the nonfree helper or `CACHED_MODEL_PATH`.

### Changed

- Separate normal/additional latency and latch the RWDS latency request.
- Double AXI (8), write-data (16) and default CDC (8) FIFO depths.
- Initialize the model through AXI; extend subword and consecutive-access tests.

### Fixed

- Fix single-PHY byte/16-bit addressing within packed words.
- Reset RWDS capture after read data drains.
- Fix clock-mode forwarding in the simple fixture and lint/synthesis wrapper.

### Compatibility

- Replace `IsClockODelayed` with `UsePhyClkDivider` (`0 -> 1`, `1 -> 0`).
- Remove `AxiLogDepth`; Xilinx builds require `clk_ref200_i`.
- Widen RX/TX delay controls to 8 bits; low 5 select 32 taps. Reset: `0x08 -> 0x10`.
- Add CS-to-clock register at `0x2c`; move chip-range base `0x2c -> 0x30`.
- Model downloads require vendor authentication or a local archive.

## [0.0.9] - 2025-06-03

### Changed

- Work around model-download certificate failures by disabling TLS verification
  (`wget --no-check-certificate`).

## [0.0.8] - 2025-04-08

### Changed

- Require an explicit `MinFreqMhz` argument in `gen_RstCfg`.

## [0.0.7] - 2025-04-08

### Fixed

- Wait for PHY idle/RX FIFO drain when switching PHYs; test both selections.
- Fix model archive extraction and ignore extracted files.
- Make `gen_RstCfg` and its local state automatic.

## [0.0.6] - 2024-05-07

### Added

- Expose register reset values through `RstCfg`, with `gen_RstCfg` defaults.

## [0.0.5] - 2024-04-22

### Added

- Add `t_csh_cycles` for final-clock-to-CS deassertion timing (default 1 cycle).

### Compatibility

- Add timing register at `0x28`; move chip-range base `0x28 -> 0x2c` (32-bit Regbus).

## [carfield_chip-v4.1-2023-11-16-15.15] - 2023-11-09

Carfield snapshot with the same tracked tree as 0.0.5, including `t_csh_cycles`.
Dated by its commit, not the integration timestamp in its name.

## [0.0.4] - 2023-10-06

### Added

- Add a four-entry, non-fall-through AXI ingress FIFO for outstanding requests.

## [0.0.3] - 2023-09-12

### Added

- Add software PHY selection (`phys_in_use`, `which_phy`) to dual-PHY builds.
- Pass `SyncStages` through PHY CDC FIFOs.

### Changed

- Assert DQ/RWDS output enables ahead of data.
- Rename generic delay models to `configurable_delay`.
- Update AXI/common-cells dependencies, logging, scoreboarding and random tests.

### Compatibility

- Add PHY selectors at `0x20`/`0x24`; move chip-range base `0x20 -> 0x28` (32-bit Regbus).
- PHY switching gains idle/drain coordination in 0.0.7.

## [0.0.2] - 2023-06-20

### Fixed

- Remove inferred latches, including burst-length increment logic.
- Allow single-beat AXI FIXED requests; multi-beat FIXED/WRAP remain unsupported.
- Fix testbench timing and scoreboard binding.
- Refresh model/SDF setup and fixture wiring; add the `hyper_test` model target.

## [0.0.1] - 2023-02-27

Initial release of HyperBus v2.

### IP's history

- *2018*: HyperBus v1 for [Scarabaeus](http://asic.ethz.ch/2018/Scarabaeus.html)/Kerbin ([IP home](https://iis-git.ee.ethz.ch/bergerar/hyperbus)).
- *2021*: HyperBus v2 redesign ([IP home](https://iis-git.ee.ethz.ch/bslk/hyperbus)).
- *2021/2022*: Improvements and additions.
- *February 2023*: Initial release.

[0.1.0]: https://github.com/pulp-platform/hyperbus/compare/v0.0.10...v0.1.0
[0.0.10]: https://github.com/pulp-platform/hyperbus/compare/v0.0.9...v0.0.10
[0.0.9]: https://github.com/pulp-platform/hyperbus/compare/v0.0.8...v0.0.9
[0.0.8]: https://github.com/pulp-platform/hyperbus/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/pulp-platform/hyperbus/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/pulp-platform/hyperbus/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/pulp-platform/hyperbus/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/pulp-platform/hyperbus/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/pulp-platform/hyperbus/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/pulp-platform/hyperbus/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/pulp-platform/hyperbus/releases/tag/v0.0.1
[carfield_chip-v4.1-2023-11-16-15.15]: https://github.com/pulp-platform/hyperbus/tree/carfield_chip-v4.1-2023-11-16-15.15
