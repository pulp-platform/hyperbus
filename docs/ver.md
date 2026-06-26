# Verification

This page describes the verification strategy, testbench architecture, and test suite for the
HyperBus v2 controller.

---

## Test Plan 


### Scope

The verification targets the `hyperbus` top-level module in RTL simulation, exercising:

- Correct AXI4 slave protocol behavior (compliance, back-pressure, response codes)
- Correct HyperBus protocol generation (CA packets, timing, RWDS handling)
- Data integrity across all supported transaction types
- Corner cases: maximum burst length, bus turnaround, latency extension, clock stop

### Out of Scope

- Post-synthesis / gate-level simulation (not yet validated)
- HyperFlash command sequences (WIP — see [Specification → TODOs](spec.md#open-todos))
- Formal property verification

### Test Plan Table

| Test category | Status | Description |
|---|---|---|
| Single-word read — fixed latency | ✅ | Basic read, no latency extension |
| Single-word read — variable latency | ✅ | RWDS-signaled latency extension |
| Single-word write | ✅ | Basic write with correct RWDS strobe |
| Burst read | ✅ | Multiple words, clock-stop stalling |
| Burst write | ✅ | Multiple words, correct byte strobes |
| AXI back-pressure | ✅ | Stall on W/R channel, verify no data loss |
| Multi-chip access | 🔄 | CS# selection for multiple devices |
| Register access (Regbus) | ✅ | Read/write all configuration registers |
| HyperRAM register space | ✅ | Access to device CR0/CR1 configuration registers |
| Byte-aligned access | ❌ | Not yet supported — see TODOs |
| HyperFlash operations | ❌ | Work in progress |
| Error / timeout injection | 🔄 | Planned |

*Legend: ✅ done · 🔄 in progress · ❌ not yet supported*

---


## Testbench Architecture

```
test/
├── tb_axi_hyper.sv       # Top-level testbench
├── axi_master_bfm.sv     # AXI4 master Bus Functional Model
├── hyper_device_bfm.sv   # HyperBus device BFM (wraps proprietary model)
└── tests/
    ├── single_read.sv
    ├── burst_write.sv
    └── ...
```

### Key Components

**AXI4 Master BFM (`axi_master_bfm`)**

Drives AXI4 read and write transactions to the `axi_hyper` DUT. Built on top of the
[`axi_test`](https://github.com/pulp-platform/axi) package from the PULP AXI library.
Supports randomized burst length, address alignment, and transaction interleaving.

**HyperBus Device Model**

The `models/s27ks0641/` directory contains the Infineon s27ks0641 HyperRAM simulation model.
This model is proprietary; it is downloaded automatically by `make run`.

!!! warning "License"
    By running `make run`, you download and use the Infineon s27ks0641 model under
    Infineon's non-free license terms. See the `Makefile` for details.

**Testbench Top (`tb_axi_hyper`)**

Instantiates the DUT, AXI master BFM, and the HyperRAM model. Generates clocks and resets,
applies the test sequence, and checks results via assertions and scoreboards.

---

## Properties, Assertions, and Assumptions

### AXI Protocol Assertions

The testbench uses the
[AXI4 protocol checker](https://github.com/pulp-platform/axi/blob/master/src/axi_protocol_checker.sv)
from the PULP AXI library to continuously verify:

- Valid handshake sequences (VALID before READY is not required, but enforced)
- No X/Z propagation on payload signals
- Response codes consistent with transaction outcome

### HyperBus Protocol Assertions

!!! info "Work in progress"
    Formal assertions covering the HyperBus PHY output (CA packet format, RWDS timing,
    clock-stop rules) are planned but not yet implemented.

### Assumptions

- The AXI master BFM only issues INCR bursts (WRAP and FIXED are not tested, as they are
  not supported by the DUT).
- The HyperRAM model operates with default timing parameters unless the test reconfigures
  the device via the Regbus interface.

---

## Tests

### Running Tests

```bash
# Install dependencies and fetch device models
bender update
make run        # downloads proprietary Infineon model

# Launch simulation in QuestaSim
vsim -do target/sim/start.tcl
```

### Directed Tests

| Test | File | What it checks |
|---|---|---|
| `single_read` | `tests/single_read.sv` | One AXI read → one HyperBus read transaction |
| `burst_write` | `tests/burst_write.sv` | AXI burst write → HyperBus burst write, data integrity |
| `regbus_rw` | `tests/regbus_rw.sv` | Write/read all Regbus config registers |
| *(more TBD)* | | |

---

## Randomization

!!! info "Work in progress"
    Constrained-random stimulus (randomized burst length, address, latency, interleaved R+W)
    is planned. Contributions welcome.

---

## Coverage

!!! info "Work in progress"
    Functional coverage groups targeting:

    - AXI burst lengths (1, 2, 4, 8, 16, max)
    - Unaligned vs. aligned addresses
    - Latency: fixed vs. variable, single vs. double
    - Clock-stop events per burst
    - Multi-chip CS# selection
    - Register access: all addresses hit

    Coverage reports will be added here once the coverage model is implemented.

---
