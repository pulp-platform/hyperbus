# Verification

Tests check required behavior at their module boundary. They must not require an
incidental queue depth, internal state name or microtransaction count unless that
property is an explicit implementation contract. Preserve nonvacuity: a scenario
that never exercises its intended condition is not evidence for that condition.

## Suites

Run the Questa suites with `bash scripts/run_regression.sh SUITE BUILD_DIRECTORY`.
Use the site's resource limiter only when the run meets its resource thresholds.
The suites require Bender, Questa and the separately
obtained HyperRAM model. The runner generates its compile script and retains logs
in the selected build directory. `BENDER` and `VSIM` override the executables.

| Suite | Purpose |
| --- | --- |
| `fast` | Atomic unit/integration, register ABI, reset replay, divider, PHY timing and pad-delay model checks |
| `integration` | Existing synchronous, asynchronous and isochronous AXI configurations, including one PHY; data, IDs, stalls, boundaries, restart and early-W/FLUSH |
| `performance` | Enforced read/write cycle budgets on the existing configurations |
| `pad` | Focused nonzero pad-delay integration on synchronous single- and dual-PHY configurations |
| `all` | All of the above |

The focused Verilator scripts do not need the vendor memory model. The atomic
unit runner covers host widths 16 through 1024; AXI integration covers 16 through
256. Its independent reference ALU
and byte-addressed integration model cover different layers; neither replaces the
other. The reset and divider tests cover the real control path and supported reset
contract, not arbitrary in-flight PHY reset recovery.

`scripts/run_read_counter_test.sh BUILD_DIRECTORY` checks minimum-width consecutive
PHY words, active-byte payloads, exact response counts and LAST, unaligned/narrow
reads, producer/consumer stalls and the generic 32768-byte boundary. Payload
checks use an independent address-derived oracle, not only a second RTL instance.
Generic counter widths cover the encoded host-beat byte span; bounded AXI widths
remain derived from the maximum AXI burst.
The focused matrix includes bounded 256-beat profiles for both PHY counts at
128/256/512/1024-bit host widths. Wide cases sweep transfer sizes at offsets zero
and the last host byte, including single-PHY mode on a dual-PHY implementation.

Physical-link errors mark the host transaction failed: at least one host response
must report AccessError for an accepted errored physical word. Per-byte or
every-affected-host-beat attribution is not promised. The current PHY ties its
error output low; alternate backends must observe this transaction-level contract.
Injected narrow-read tests permit either Okay or AccessError on individual beats,
require at least one AccessError, and retain payload/count/LAST/stability checks.

The generic midend also requires the total rounded physical span to fit its
15-bit count of 16-bit words, before chip segmentation: at most 65534 bytes with
one PHY, or 65532 bytes with two PHYs (including single-PHY mode). This existing
command-format limit is checked by `HostPhysicalBurstFits`; a widened read-adapter
counter does not remove it. AXI's 256-beat maximum at the supported host widths
fits this bound. Generic clients must satisfy both the host-beat and physical-span
bounds.

`bash scripts/run_burst_bound_test.sh BUILD_DIRECTORY` checks the legal 256-beat
rejected-read boundary with response stalls, then requires an oversized request
to fail specifically at the burst-bound assertion. It also checks a mapped
32768-byte read through the generic midend against an independent payload oracle,
and requires an oversized physical span to fail its own assertion. Expected-failure
runs are separate from the ordinary passing Questa suite.
Small-address cases exercise 12-bit address spaces with both PHY counts: a large
overflowing read/write must produce decode-error responses without backend
commands; a read ending exactly at the address-space endpoint must succeed, while
one extending beyond it must fail. Span arithmetic retains the full encoded host
burst and address carry before any overflow rejection or narrowing.

## Queue Parameters

The supported queue controls are `AxiMaxReadTxns >= 1`,
`AxiMaxWriteTxns >= 1`, and `HostWriteBufferBytes` at least one host beat and
an integer multiple of its byte width. The command queue remains fixed at two
entries; it is not another exposed parameter.

`test/axi_queue_profiles.txt` is the shared profile matrix for the focused
Verilator barrier runner and Questa fast suite. Run the vendor-free matrix with
`bash scripts/run_axi_barrier_test.sh BUILD_DIRECTORY`; the same profiles are
included in the Questa `fast` and `all` suites. At 64-bit AXI it covers:

| Read Limit | Write Limit | Buffered W Beats | Purpose |
| --- | --- | --- | --- |
| 1 | 1 | 1 | Minimum counters and buffers |
| 1 | 4 | 1 | Minimum read limit with more write ownership |
| 4 | 1 | 2 | Minimum write limit with more read ownership |
| 2 | 2 | 2 | Two-entry boundary |
| 3 | 5 | 3 | Non-power-of-two, asymmetric limits |
| 5 | 3 | 5 | Reverse asymmetry and wider counters |
| 4 | 4 | 8 | Default configuration |

These are behavioral tests, not elaboration-only checks. Each profile retains
the six atomic FLUSH/APPLY cases and exercises queue pressure, held requests,
write-data debt and response backpressure against independent acceptance,
response and byte-memory checks. The matrix samples minimum, power-of-two and
non-power-of-two width classes; it is not an exhaustive Cartesian product of
all positive integer settings. Other focused tests cover host-data widths.

The integration suite also runs the minimum limits and one-beat write buffer
through the isochronous, synchronous and asynchronous public tops, plus the
single-PHY synchronous configuration. These additional runs are functional;
the default performance profiles and their existing cycle ceilings are unchanged.

## Performance

Performance is a checked requirement, not a report-only trend. The deterministic
performance suite keeps the existing per-configuration read/write cycle ceilings
(baseline plus 20 percent and two cycles). Changing a ceiling requires an explicit
performance decision. Functional traffic stalls and nonzero pad-delay cases do not
silently change that baseline.

Exact segment counts and monotonic cycles per beat are not correctness contracts.
Different legal splitting policies can produce different counts. Data integrity,
chip steering, configured timing and forced restart coverage remain functional
requirements. Gate-level simulations do not enforce RTL cycle baselines; physical
timing is checked by the implementation flow.

## Coverage Requirements

- AXI producers hold valid and payload until acceptance. Response checks match IDs
  and preserve same-ID ordering without requiring ordering between distinct IDs.
- FLUSH/APPLY preserve AR, AW and W offers already exposed to the serializer,
  including atomic AW before its external acceptance. These offers participate
  in drain completion; offers first arriving during the barrier wait. The
  vendor-free AXI barrier test uses real command CSRs and checks AW-before-W,
  independent write data, responses, memory contents and acceptance ownership.
- Buffering tests allow legal backpressure. The pre-AW test requires actual early-W
  acceptance for the current implementation. Its explicit AW-gated mode does not
  claim early-W coverage. Complete and partial early-W debt are distinct cases.
- Atomic results, returned original data, strobes, neighboring bytes and isolation
  matter. A failed Compare need not issue an unchanged writeback. Malformed-request
  expectations remain unchanged by this test cleanup.
- Reset tests preserve staged settings and restore the last-applied effective
  configuration before admitting requests. Internal replay packet counts and
  no-op APPLY suppression are not architectural requirements.
- PHY-only reset deliberately preserves system-side configuration and control
  state; system reset resets that state. The reset network is unchanged. A shared
  two-stage data synchronizer, reset only by system reset, qualifies the PHY-ready
  indication used by surviving control flops. The raw indication still blocks
  admission immediately. STATUS.BUSY uses synchronous control; STATUS accesses
  briefly stall during reset entry until BUSY has caught up, then remain available
  through replay. Tests sweep reset assertion phase and pulse width with distinct
  staged/applied values. They verify logical replay and admission behavior, not
  physical metastability or RDC signoff.
- A PHY-only reset requires CSR quiescence at assertion as well as AXI/barrier/
  backend quiescence. Finish the current CSR access and stop offering new ones
  before asserting reset. New accesses offered after reset is stable hold valid
  and payload until acknowledgement. The reset regression checks producer
  stability, first acknowledged STATUS.BUSY, W1C during a held reset, and a legal
  non-STATUS read blocked until replay. Later W1C readback does not require replay
  to remain busy for an incidental number of cycles.
- Pad-delay model tests validate the stimulus, not controller tolerance. Only
  integrated tests using nonzero delays establish tested controller behavior.
  Measured passing cases are not a technology-independent electrical guarantee.
  The default integration case delays matched input and output bundles by one
  tick; tick rising edges are 2.5 ns apart. OE delays remain zero in this case.
- The directed PHY test identifies CA and its known write payload at CK edges,
  checks pin ownership and measures RWDS-enable setup before the payload. This
  monitor is specific to its controlled stimulus, not a general HyperBus decoder.
  Its internal RWDS sampling-event observation remains a white-box timing check;
  that sampling event has no output pin.

## Failure Evidence

The Questa runner rejects errors, fatal messages and missing completion markers.
Retain failing logs and the stimulus or seed. A passing banner alone is insufficient.
Use a targeted negative control to confirm a replacement test still detects the
original defect; verify the mutation actually changed its intended source before
interpreting its result. Do not relax an assertion merely to make a run pass.

The obsolete `hyperbus_tb` has been retired. Active AXI tests retain its useful
lane, unaligned-access and burst coverage. Its shared fixture remains in use by the
pre-AW regression.
