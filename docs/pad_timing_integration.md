# Pad Timing Integration

Require bounded DQ-pin skew; shared TX CK/RX RWDS phase adjustments cannot correct
individual pins. Budget pad, package, board, jitter and PVT delays at both the
memory pins and macro capture boundary. Below, `T` is the PHY clock period;
`tx_phase_delay` is the programmed CK delay.

## Setup and CA

`csn_to_ck_cycles` adds full PHY cycles before CK on initial and restarted segments;
zero keeps the fast path. DQ OE remains asserted during setup. Budget from command
acceptance, not speculative valid. With ideal RTL clocks, CS falls on a PHY falling
edge and the first CK rising edge follows after:

`(csn_to_ck_cycles + 0.5) * T + tx_phase_delay`

Add external CS/CK/DQ/OE differential delays separately. Set `rwds_sample_delay`
at most `t_latency_access - 2`, and place the sample inside the device's latency
indication window after accounting for outbound CS and inbound RWDS delays. The
register range check alone does not guarantee this.

## Write Latency

`LATENCY_CFG.keep_dq_driven` (bit 24, reset 0) retains DQ drive through normal/
additional latency and RWDS setup waits, avoiding another OE transition without
adding cycles. **Enable only for devices permitting this:** generic HyperBus
requires high-Z DQ during initial latency. The driven value is not write data.
Read direction, RWDS OE and recovery are unchanged. Zero-latency writes already
retain DQ drive and never enable host RWDS.

`rwds_oe_setup_cycles` sets minimum RWDS-enable setup before write data. Natural
latency covers it where possible; otherwise CK pauses at the data boundary.
Separately verify that the memory releases RWDS before the host pad drives it.

## Read Ending and Recovery

`t_csh_cycles` extends final CK-to-CS spacing with CK stopped. The current pipeline
provides at least this ideal-RTL interval from final CK falling edge to CS rising:

`(t_csh_cycles + 1) * T - tx_phase_delay`

It can be longer if CK already stopped. Keep CS active through final-byte capture
setup/hold, accounting for memory timing, CS/CK differential delay, return skew
and receiver phase. Matched DQ/RWDS input delay does not automatically require an
equal CS-hold extension.

Capture stays enabled until outstanding words drain; the next segment waits for
that drain. CS deassertion uses configured hold, not downstream response acceptance.
After CS rises, `t_read_write_recovery` separates owners. Check actual release/
acquisition at the pins: recovery cannot repair a truncated final byte. Respect
the device's maximum CS-low duration across all waits.

See [Verification](verification.md) for tested cases. Electrical limits still
require characterization for the chosen technology and device.
