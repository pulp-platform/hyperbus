# Pad timing integration

Require bounded skew within DQ[7:0]. Use the shared TX CK and RX RWDS phase
adjustments to centre the data eye; they cannot compensate skew between DQ pins.
Account for pad, package, board, jitter, and PVT contributions at the memory pins
and the macro capture boundary.

## Transaction setup and CA

`csn_to_ck_cycles` inserts complete PHY cycles before CK starts, on both the
first transaction and every internally restarted segment. Zero retains the
fast path. DQ OE stays asserted throughout this setup interval. Budget from the
latest command acceptance, not an earlier speculative command-valid transition.
For ideal RTL timing, CS falls on a PHY falling edge and the first CK rising edge
follows by `(csn_to_ck_cycles + 0.5) * T + tx_phase_delay`. External differential
delays between CS, CK, DQ and OE must be added separately.

RWDS latency-indication timing uses the existing `csn_to_ck_cycles` and
`rwds_sample_delay` controls. The latter must be at most `t_latency_access - 2`.
The complete integration must place the sample inside the memory's valid
latency-indication window, including outbound CS and inbound RWDS delays.
The range check alone does not establish that electrical timing requirement.

## Write latency

Per-chip `LATENCY_CFG.keep_dq_driven` (bit 24, reset 0) keeps DQ OE asserted
through normal latency, additional latency, and an extended RWDS setup wait.
This avoids a second pad-enable transition between CA and write data. It does
not add cycles. It does not change RWDS OE, read direction, or recovery.

This is a device-specific opt-in: the generic HyperBus interface-state table
specifies high-Z DQ during initial latency. Enable it only when the attached
device permits host-driven DQ throughout write latency. The driven value during
latency is not write data and must not be interpreted as such by the device.
Zero-latency writes already maintain DQ drive and never enable host RWDS.

`rwds_oe_setup_cycles` establishes the existing minimum RWDS enable setup before
write data. Natural latency covers the wait where possible; otherwise CK pauses
at the data boundary. This setting does not by itself establish non-overlap with
the memory's preceding RWDS drive. Check memory release against actual pad enable
timing independently.

## Read ending and recovery

`t_csh_cycles` extends the final CK-to-CS interval while CK is stopped. With the
current pipeline and ideal RTL clocks, that interval is at least
`(t_csh_cycles + 1) * T - tx_phase_delay`, measured from the final CK falling edge
to CS rising (longer if CK was already stopped). Determine the required setting from the complete final-byte capture
window; do not treat the field as an exact count starting at an external pin edge.

Keep CS active long enough to preserve the last byte's capture setup and hold.
Matched input delay shifts both data and the return strobe, and is not automatically
an equal extra CS-hold requirement. Account separately for memory output timing,
CS/CK differential output delay, return skew, and receiver phase adjustment.

The receive capture enable remains active until outstanding read words drain.
The next segment waits for that drain before restarting. CS deassertion itself
uses the configured hold interval rather than downstream response acceptance,
so consumer backpressure does not indefinitely extend an active memory transaction.

After CS rises, `t_read_write_recovery` provides the existing recovery interval.
Verify actual output release and next-owner acquisition at the pins. Recovery
cannot repair a final byte truncated by an early CS edge. All programmed waits
must also respect the device's maximum CS-low duration.

## Verification

`hyperbus_phy_timing_tb` checks macro-boundary CS-to-CK timing on initial and
restarted write segments, both DQ modes, latency variants, RWDS setup waits,
late write data, zero-latency writes, and configured final CK-to-CS spacing.
Read cases deliberately leave a sample outstanding, return delayed DQ/RWDS after
CS deasserts, and check the received word and transaction completion. This is a
directed return stimulus, not a complete memory model. The synchronous single- and
dual-PHY AXI regressions additionally check
segmented write/readback in both DQ modes with extended CS setup and hold.
The `pad` regression suite enables nonzero matched input/output delays; the normal
functional and performance suites retain zero pad delay. Delay-model unit tests
alone do not establish controller tolerance.
Electrical pad-delay limits still require characterization for the
selected technology and device.
