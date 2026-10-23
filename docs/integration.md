# Integration Requirements

## Atomic Operands

AtomicStore, AtomicLoad and AtomicSwap support naturally aligned 1-, 2-, 4- and
8-byte operands that fit the AXI data width. Arithmetic operands are little-endian;
bitwise operations do not depend on the endianness bit.

AtomicCompare carries a combined compare/swap payload of 2, 4, 8, 16 or 32 bytes
within one AXI beat. Its memory operand is half that size and naturally aligned.
The addressed half of the payload contains the compare operand; the other half
contains the swap operand. Use INCR when it occupies the lower half and WRAP when
it occupies the upper half. This does not enable ordinary WRAP bursts.
Multi-beat atomics are unsupported.

## Configuration Barriers

Configuration writes update staged registers. APPLY drains accepted transactions
before activating those settings. FLUSH drains without applying staged edits.
Both barriers also finish AXI channel offers already exposed to the serializer,
even if their external handshake is pending. New offers wait; producers must
retain valid and payload until acceptance.

Changing `phys_in_use` or `which_phy` changes data packing and addressing. Apply
the change before issuing traffic that depends on the new mapping.

## PHY-Only Reset

Only the asynchronous top supports an independent PHY reset. Assert it in
functional mode (`test_mode_i=0`) while the complete controller is quiescent:
no outstanding AXI transaction, unfinished or concurrently offered CSR access,
configuration barrier, or backend recovery interval.

System-side staged and applied configuration survives. After reset, the controller
restores the last-applied PHY settings before accepting new AXI requests; staged
edits remain unapplied. Wait for replay to finish before another PHY-only reset.
Reset during traffic or a configuration barrier is not a recovery mechanism.

New AXI requests may be presented after reset is stably asserted, but must remain
stable until acknowledged. STATUS is accessible during replay after the short
reset-entry guard; other CSR accesses wait for replay to complete.
