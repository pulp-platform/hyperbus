# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

Entries through 0.0.9 describe the existing tags, including tags without a GitHub
release. Dates use the annotated tag date where available, otherwise the tagged
commit date.

## [0.0.10] - Unreleased

Final release of the legacy HyperBus v2 architecture, before the controller and
configuration redesign. Retains the `hyperbus` top, shared timing configuration
and controller-driven memory reset.

### Added

- Configurable chip-select-to-clock-start delay, `csn_to_ck_cycles`, defaulting to
  zero additional cycles.
- Xilinx 7-series clock/RWDS delay wrappers and Bender targets for selecting them,
  with a 200 MHz delay-calibration reference clock.
- Model acquisition through a pinned optional nonfree helper, a local archive
  directory (`CACHED_MODEL_PATH`), or a manually downloaded vendor archive.

### Changed

- Separate normal and additional latency handling and latch the RWDS latency
  request so later signal changes do not erase the decision.
- Increase AXI ingress FIFO depth from 4 to 8, write-data FIFO depth from 8 to 16,
  and default CDC FIFO depths from 4 to 8 entries to reduce buffering bubbles.
- Initialize the memory model through AXI before randomized traffic and extend
  single-PHY subword and consecutive-access regression coverage.

### Fixed

- Correct single-PHY command addressing for byte and 16-bit accesses at odd word
  positions within the internal data packing.
- Reset RWDS read capture only after launched read words have drained, preventing
  stale capture state between accesses.
- Update stale clock-mode parameter forwarding in the simple test fixture and
  lint/synthesis wrapper. Preserve the wrapper's existing parameter polarity.

### Compatibility

- `hyperbus` replaces `IsClockODelayed` with `UsePhyClkDivider`: old value 0 maps
  to new value 1, and old value 1 maps to new value 0. The unused `AxiLogDepth`
  parameter is removed. Xilinx delay-line builds add the `clk_ref200_i` port.
- RX/TX delay controls widen from 4 to 8 bits. The supplied generic/Xilinx delay
  implementations use the low 5 bits for 32 taps; reset settings change from
  `0x08` to `0x10`. Recheck timing settings when migrating.
- The new CS-to-clock register occupies word index 11. Chip-range registers move
  from word index 11 to 12: byte offset `0x2c` to `0x30` for a 32-bit register bus.
- Infineon's model download now requires vendor authentication; the former
  unauthenticated download path is no longer used.

## [0.0.9] - 2025-06-03

### Changed

- Work around Infineon model-download certificate failures using
  `wget --no-check-certificate`. This historical download path disables TLS
  certificate verification; 0.0.10 replaces it with authenticated/cached access.

## [0.0.8] - 2025-04-08

### Changed

- Remove the default `MinFreqMhz` argument from `gen_RstCfg`. Direct callers must
  supply it explicitly; module defaults already pass their `MinFreqMHz` parameter.

## [0.0.7] - 2025-04-08

### Fixed

- Coordinate runtime PHY selection with PHY activity and RX FIFO draining in
  dual-PHY configurations; gate handshakes to the active PHYs. Extend tests to
  select PHY 0 and PHY 1 separately.
- Correct HyperRAM model download/extraction naming and ignore extracted models.
- Make reset-configuration generation automatic, including its local state.

## [0.0.6] - 2024-05-07

### Added

- Expose register reset configuration through the `RstCfg` parameter on
  `hyperbus` and its register block, using `hyperbus_pkg::gen_RstCfg` defaults.

## [0.0.5] - 2024-04-22

### Added

- Configurable final-clock-to-chip-select-deassertion timing, `t_csh_cycles`,
  defaulting to one cycle.

### Compatibility

- The new timing register occupies word index 10. Chip-range registers move from
  word index 10 to 11: byte offset `0x28` to `0x2c` for a 32-bit register bus.

## [carfield_chip-v4.1-2023-11-16-15.15] - 2023-11-09

Carfield integration snapshot, not a numbered HyperBus release. Its tracked tree
matches 0.0.5, including `t_csh_cycles` and the corresponding register-map shift.
The date above is the tagged commit date; the integration timestamp is in the name.

## [0.0.4] - 2023-10-06

### Added

- A four-entry, non-fall-through AXI ingress FIFO to buffer requests and support
  more outstanding transactions.

## [0.0.3] - 2023-09-12

### Added

- Software selection of one or both PHYs in dual-PHY builds, using `phys_in_use`
  and `which_phy`; adapt AXI data packing and command addressing accordingly.
- Propagate the configurable `SyncStages` parameter through PHY CDC FIFOs.

### Changed

- Assert DQ/RWDS output enables earlier than data to allow pad enable settling.
- Rename generic delay models to `configurable_delay`; update AXI/common-cells
  dependencies and simulation logging, scoreboarding and random traffic.

### Compatibility

- PHY-selection registers occupy word indices 8 and 9. Chip-range registers move
  from word index 8 to 10: byte offset `0x20` to `0x28` for a 32-bit register bus.
- Runtime PHY switching is subsequently coordinated with idle/drain state in
  0.0.7; this initial selector should not be treated as that later implementation.

## [0.0.2] - 2023-06-20

### Fixed

- Remove unintended combinational latches, including burst-length increment logic.
- Accept single-beat AXI FIXED requests (`len = 0`). Multi-beat FIXED and WRAP
  bursts remain unsupported.
- Correct testbench clock/application/sample timing and reconnect the scoreboard.
- Update vendor-model integration and SDF back-annotation, align fixture wiring,
  and isolate device-model compilation behind the `hyper_test` target.

## [0.0.1] - 2023-02-27

Initial release of HyperBus v2.

### IP's history

 - *February to June 2018*: Development of HyperBus v1 for [Scarabaeus](http://asic.ethz.ch/2018/Scarabaeus.html) as part of the *Kerbin* project - [IP home](https://iis-git.ee.ethz.ch/bergerar/hyperbus).
 - *February to June 2021*: Cleanup and redesign to HyperBus v2 - [IP home](https://iis-git.ee.ethz.ch/bslk/hyperbus).
 - *2021/2022*: Various improvements and additions
 - *February 2023*: Release

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
