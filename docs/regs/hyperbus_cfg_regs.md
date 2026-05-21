<!---
Markdown description for SystemRDL register map.

Don't override. Generated from: hyperbus_cfg_regs
  - /home/phsauter/repos/hyperbus/src/regs/hyperbus_cfg_regs.rdl
-->

## hyperbus_cfg_regs address map

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x50

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

<p>RX sampling delay-line tap setting.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

### t_tx_clk_delay register

- Absolute Address: 0x14
- Base Offset: 0x14
- Size: 0x4

<p>TX clock delay-line tap setting.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

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

<p>Inclusive base address for chip-select 0 decoding.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|31:0|   value  |  rw  | 0x0 |  — |

### chip0_bound register

- Absolute Address: 0x34
- Base Offset: 0x34
- Size: 0x4

<p>Exclusive bound address for chip-select 0 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x10000|  — |

### chip1_base register

- Absolute Address: 0x38
- Base Offset: 0x38
- Size: 0x4

<p>Inclusive base address for chip-select 1 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x10000|  — |

### chip1_bound register

- Absolute Address: 0x3C
- Base Offset: 0x3C
- Size: 0x4

<p>Exclusive bound address for chip-select 1 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x20000|  — |

### chip2_base register

- Absolute Address: 0x40
- Base Offset: 0x40
- Size: 0x4

<p>Inclusive base address for chip-select 2 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x20000|  — |

### chip2_bound register

- Absolute Address: 0x44
- Base Offset: 0x44
- Size: 0x4

<p>Exclusive bound address for chip-select 2 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x30000|  — |

### chip3_base register

- Absolute Address: 0x48
- Base Offset: 0x48
- Size: 0x4

<p>Inclusive base address for chip-select 3 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x30000|  — |

### chip3_bound register

- Absolute Address: 0x4C
- Base Offset: 0x4C
- Size: 0x4

<p>Exclusive bound address for chip-select 3 decoding.</p>

|Bits|Identifier|Access| Reset |Name|
|----|----------|------|-------|----|
|31:0|   value  |  rw  |0x40000|  — |
