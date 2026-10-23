# Integration Requirements

## Atomic Operands

AtomicStore, AtomicLoad and AtomicSwap accept naturally aligned 1/2/4/8-byte
operands fitting one AXI beat. Arithmetic is little-endian; bitwise operations
ignore the endianness bit.

AtomicCompare carries 2/4/8/16/32 bytes of compare/swap payload in one beat. Its
memory operand is half that size and naturally aligned. The addressed half holds
compare; the other holds swap. Use INCR for compare in the lower half, WRAP for
the upper half. Ordinary WRAP bursts and multi-beat atomics are unsupported.

## Configuration and Queues

Writes are staged. APPLY drains traffic before activating settings; FLUSH drains
without applying them. Both finish already-exposed AXI offers, even before their
external handshake. New offers wait; producers retain valid/payload until accepted.
Apply changes to `phys_in_use`/`which_phy` before traffic using the new mapping.

`AxiMaxReadTxns` and `AxiMaxWriteTxns` must be at least 1. `HostWriteBufferBytes`
must hold at least one host beat and be a multiple of its byte width. The command
queue is fixed at two entries.

## PHY-Only Reset

Only the asynchronous top supports independent PHY reset. Assert it with
`test_mode_i=0` and no outstanding AXI transaction, unfinished/offered CSR access,
barrier or backend recovery. In-flight reset is not a recovery mechanism.

System-side configuration survives. Replay restores applied settings before AXI
admission; staged edits remain unapplied. Wait for replay before another reset.
New AXI/CSR offers after reset is stable must remain valid until acknowledged.
STATUS briefly stalls on reset entry, then stays accessible during replay;
other CSRs wait for replay to finish.

## Generic Clients and Errors

Generic clients must fit both the encoded host-beat span and the rounded physical
span before chip segmentation. The latter is limited by a 15-bit count of 16-bit
words: 65534 bytes for one PHY, 65532 for two (also in single-PHY mode).
`HostPhysicalBurstFits` checks this; supported 256-beat AXI bursts fit the bound.

An accepted errored physical word must cause at least one host response to report
AccessError. Per-byte or per-beat attribution is unspecified. The current PHY
ties its error output low; alternate backends must honor this contract.

See [pad timing](pad_timing_integration.md) for electrical integration.
