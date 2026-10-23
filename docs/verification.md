# Verification

## Running Tests

The Questa runner requires Bender and the [vendor memory model](../models/README.md):

```bash
bash scripts/run_regression.sh SUITE BUILD_DIRECTORY
```

`BENDER` and `VSIM` select executables. Compile scripts and logs stay in the build directory.

| Suite | Coverage |
| --- | --- |
| `fast` | Atomics, CSRs, queue/barrier matrix, counters, address bounds, reset, divider and PHY timing |
| `integration` | All clocking tops at default/minimum queues, single-PHY traffic and pre-AW drain |
| `performance` | Read/write cycle ceilings |
| `pad` | Synchronous single-/dual-PHY traffic with nonzero matched pad delays |
| `all` | All suites |

Vendor-free Verilator runners take an optional build directory:

| Script in `scripts/` | Coverage |
| --- | --- |
| `run_atomic_tests.sh` | Handler widths 16-1024, AXI widths 16-256 and backend fault injection |
| `run_axi_barrier_test.sh` | FLUSH/APPLY and queue pressure across [queue profiles](../test/axi_queue_profiles.txt) |
| `run_read_counter_test.sh` | Narrow/unaligned reads, wide hosts, stalls, payload/count/LAST and generic burst limits |
| `run_burst_bound_test.sh` | Host/physical-span assertions, mapped 32768-byte reads and address overflow/endpoints |
| `run_phy_reset_cfg_test.sh` | Applied/staged configuration and quiescent PHY-reset replay |
| `run_iso_clock_div_test.sh` | Divider updates and recovery |
| `run_phy_timing_test.sh` | CS/CK timing, DQ ownership, RWDS setup and delayed read completion |

## Test Contracts

Check observable behavior with independent oracles, not incidental state names,
replay counts or splitting policies. A test must exercise the condition it claims
to cover. Queue profiles sample minimum, asymmetric and non-power-of-two settings;
supported limits and reset/error contracts are in [Integration](integration.md).

- Hold valid/payload until acceptance. Check data, IDs, same-ID ordering, response
  counts, LAST, strobes and neighboring bytes; allow reordering between distinct IDs.
- Barriers drain already-exposed AR/AW/W offers, including unaccepted atomic AW.
  Test complete/partial early-W debt and response backpressure. AW-gated stimulus
  does not establish early-W coverage.
- Check atomic results, original data and isolation independently. Failed Compare
  may omit unchanged writeback.
- Reset tests distinguish staged/applied settings and sweep assertion phase and
  pulse width. They check replay/admission, not metastability or RDC signoff.
- Pad-model unit tests validate stimulus, not controller tolerance. The integrated
  `pad` case delays matched input/output bundles by one 2.5 ns tick each, with zero
  OE delay. Passing cases are not technology-independent electrical guarantees.
- Directed PHY checks use known CA/data and a synthetic read return, not a full
  memory decoder/model. RWDS sampling-event checks are necessarily white-box.

## Performance and Failures

Performance ceilings are the baseline plus 20% and two cycles. Changing them
requires an explicit performance decision; stalls and pad-delay tests do not
change the baseline. Exact segment counts and monotonic cycles/beat are not
contracts. RTL cycle ceilings do not apply to gate-level runs; physical timing
belongs to the implementation flow.

The runner requires completion markers and error-free transcripts. Retain failing
logs and seeds. Use targeted negative controls when replacing regression checks.
