<!---
Markdown description for SystemRDL register map.

Don't override. Generated from: hyperbus_cfg_regs
  - /home/phsauter/repos/hyperbus/src/regs/hyperbus_cfg_regs.rdl
-->

## hyperbus_cfg_regs address map

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x78

<p>HyperBus controller configuration. Chip address ranges must be 4 MiB aligned, ordered by chip-select index, and non-overlapping.</p>

|Offset|      Identifier     |Name|
|------|---------------------|----|
| 0x00 |   t_latency_access  |  — |
| 0x04 |en_latency_additional|  — |
| 0x08 |     t_burst_max     |  — |
| 0x0C |t_read_write_recovery|  — |
| 0x10 |    t_rx_clk_delay   |  — |
| 0x14 |    t_tx_clk_delay   |  — |
| 0x18 |   address_mask_msb  |  — |
| 0x1C |    address_space    |  — |
| 0x20 |     phys_in_use     |  — |
| 0x24 |      which_phy      |  — |
| 0x28 |     t_csh_cycles    |  — |
| 0x2C |   csn_to_ck_cycles  |  — |
| 0x30 |      chip0_base     |  — |
| 0x34 |     chip0_bound     |  — |
| 0x38 |      chip1_base     |  — |
| 0x3C |     chip1_bound     |  — |
| 0x40 |      chip2_base     |  — |
| 0x44 |     chip2_bound     |  — |
| 0x48 |      chip3_base     |  — |
| 0x4C |     chip3_bound     |  — |
| 0x58 |      chip4_base     |  — |
| 0x5C |     chip4_bound     |  — |
| 0x60 |      chip5_base     |  — |
| 0x64 |     chip5_bound     |  — |
| 0x68 |      chip6_base     |  — |
| 0x6C |     chip6_bound     |  — |
| 0x70 |      chip7_base     |  — |
| 0x74 |     chip7_bound     |  — |

### t_latency_access register

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x4

<p>Initial latency cycles before read or write data.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 3:0|   value  |  rw  | 0x6 |  — |

### en_latency_additional register

- Absolute Address: 0x4
- Base Offset: 0x4
- Size: 0x4

<p>Enable additional latency cycles when requested by RWDS.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 |   value  |  rw  | 0x0 |  — |

### t_burst_max register

- Absolute Address: 0x8
- Base Offset: 0x8
- Size: 0x4

<p>Maximum continuous burst length before the PHY restarts a transfer.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|15:0|   value  |  rw  |0x15E|  — |

### t_read_write_recovery register

- Absolute Address: 0xC
- Base Offset: 0xC
- Size: 0x4

<p>Recovery cycles inserted between read and write phases.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 3:0|   value  |  rw  | 0x6 |  — |

### t_rx_clk_delay register

- Absolute Address: 0x10
- Base Offset: 0x10
- Size: 0x4

<p>RX sampling delay with fine taps in bits 4:0 and coarse taps in bits 7:5.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 4:0|   fine   |  rw  | 0x10|  — |
| 7:5|  coarse  |  rw  | 0x0 |  — |

#### fine field

<p>Fine delay-line tap setting, nominally about 78 ps per tap.</p>

#### coarse field

<p>Coarse delay-line tap setting with an implementation-defined step size.</p>

### t_tx_clk_delay register

- Absolute Address: 0x14
- Base Offset: 0x14
- Size: 0x4

<p>TX clock delay with fine taps in bits 4:0 and coarse taps in bits 7:5.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 4:0|   fine   |  rw  | 0x10|  — |
| 7:5|  coarse  |  rw  | 0x0 |  — |

#### fine field

<p>Fine delay-line tap setting, nominally about 78 ps per tap.</p>

#### coarse field

<p>Coarse delay-line tap setting with an implementation-defined step size.</p>

### address_mask_msb register

- Absolute Address: 0x18
- Base Offset: 0x18
- Size: 0x4

<p>Most-significant address bit used by frontend address packing.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 4:0|   value  |  rw  | 0x19|  — |

### address_space register

- Absolute Address: 0x1C
- Base Offset: 0x1C
- Size: 0x4

<p>Select HyperRAM or HyperFlash address-space interpretation.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 |   value  |  rw  | 0x0 |  — |

### phys_in_use register

- Absolute Address: 0x20
- Base Offset: 0x20
- Size: 0x4

<p>Select whether one or both PHY lanes are active.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 |   value  |  rw  | 0x1 |  — |

### which_phy register

- Absolute Address: 0x24
- Base Offset: 0x24
- Size: 0x4

<p>Select the PHY lane used when only one PHY is active.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 |   value  |  rw  | 0x1 |  — |

### t_csh_cycles register

- Absolute Address: 0x28
- Base Offset: 0x28
- Size: 0x4

<p>Chip-select high time between transfers.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 3:0|   value  |  rw  | 0x1 |  — |

### csn_to_ck_cycles register

- Absolute Address: 0x2C
- Base Offset: 0x2C
- Size: 0x4

<p>Delay cycles from chip-select assertion to clock start.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 3:0|   value  |  rw  | 0x0 |  — |

### chip0_base register

- Absolute Address: 0x30
- Base Offset: 0x30
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 0 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x0 |  — |

### chip0_bound register

- Absolute Address: 0x34
- Base Offset: 0x34
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 0 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x1 |  — |

### chip1_base register

- Absolute Address: 0x38
- Base Offset: 0x38
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 1 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x1 |  — |

### chip1_bound register

- Absolute Address: 0x3C
- Base Offset: 0x3C
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 1 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x2 |  — |

### chip2_base register

- Absolute Address: 0x40
- Base Offset: 0x40
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 2 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x2 |  — |

### chip2_bound register

- Absolute Address: 0x44
- Base Offset: 0x44
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 2 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x3 |  — |

### chip3_base register

- Absolute Address: 0x48
- Base Offset: 0x48
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 3 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x3 |  — |

### chip3_bound register

- Absolute Address: 0x4C
- Base Offset: 0x4C
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 3 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x4 |  — |

### chip4_base register

- Absolute Address: 0x58
- Base Offset: 0x58
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 4 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x4 |  — |

### chip4_bound register

- Absolute Address: 0x5C
- Base Offset: 0x5C
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 4 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x5 |  — |

### chip5_base register

- Absolute Address: 0x60
- Base Offset: 0x60
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 5 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x5 |  — |

### chip5_bound register

- Absolute Address: 0x64
- Base Offset: 0x64
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 5 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x6 |  — |

### chip6_base register

- Absolute Address: 0x68
- Base Offset: 0x68
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 6 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x6 |  — |

### chip6_bound register

- Absolute Address: 0x6C
- Base Offset: 0x6C
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 6 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x7 |  — |

### chip7_base register

- Absolute Address: 0x70
- Base Offset: 0x70
- Size: 0x4

<p>Inclusive 4 MiB-aligned address for chip-select 7 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x7 |  — |

### chip7_bound register

- Absolute Address: 0x74
- Base Offset: 0x74
- Size: 0x4

<p>Exclusive 4 MiB-aligned address for chip-select 7 decoding.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x8 |  — |
