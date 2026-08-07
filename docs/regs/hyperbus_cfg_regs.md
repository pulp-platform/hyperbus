<!---
Markdown description for SystemRDL register map.

Don't override. Generated from: hyperbus_cfg_regs
  - /home/phsauter/repos/hyperbus-top-split/src/regs/hyperbus_cfg_regs.rdl
-->

## hyperbus_cfg_regs address map

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x1000

<p>HyperBus controller configuration register map. Enabled chip ranges must be 4 MiB aligned, ordered by chip-select index, and non-overlapping.</p>

|Offset| Identifier |Name|
|------|------------|----|
| 0x000| global_cfg |  — |
| 0x100|  frontend  |  — |
| 0x200|   backend  |  — |
| 0x300|    phy_0   |  — |
| 0x340|    phy_1   |  — |
| 0x400|   chip_0   |  — |
| 0x440|   chip_1   |  — |
| 0x480|   chip_2   |  — |
| 0x4C0|   chip_3   |  — |
| 0x500|   chip_4   |  — |
| 0x540|   chip_5   |  — |
| 0x580|   chip_6   |  — |
| 0x5C0|   chip_7   |  — |
| 0xFFC|reserved_top|  — |

## global_cfg register file

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x14

|Offset|  Identifier  |Name|
|------|--------------|----|
| 0x00 |  ip_version  |  — |
| 0x04 |reg_if_version|  — |
| 0x08 |  capability  |  — |
| 0x0C |    command   |  — |
| 0x10 |    status    |  — |

### ip_version register

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x4

<p>IP version (major.minor.patch.revision).</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
| 7:0 | revision |   r  | 0x0 |  — |
| 15:8|   patch  |   r  | 0x9 |  — |
|23:16|   minor  |   r  | 0x0 |  — |
|31:24|   major  |   r  | 0x0 |  — |

### reg_if_version register

- Absolute Address: 0x4
- Base Offset: 0x4
- Size: 0x4

<p>Register interface version.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
| 15:0|   minor  |   r  | 0x0 |  — |
|31:16|   major  |   r  | 0x1 |  — |

### capability register

- Absolute Address: 0x8
- Base Offset: 0x8
- Size: 0x4

<p>Hardware-provided implementation capabilities.</p>

|Bits|    Identifier    |Access|Reset|Name|
|----|------------------|------|-----|----|
| 7:0|     num_chips    |   r  | 0x0 |  — |
|15:8|     num_phys     |   r  | 0x0 |  — |
| 16 |   per_chip_cfg   |   r  | 0x0 |  — |
| 17 |    per_phy_cfg   |   r  | 0x0 |  — |
| 18 |    chip_enable   |   r  | 0x0 |  — |
| 19 |   clock_divider  |   r  | 0x0 |  — |
| 20 |   staged_apply   |   r  | 0x0 |  — |
| 21 |   error_status   |   r  | 0x0 |  — |
| 22 |rwds_sample_timing|   r  | 0x0 |  — |
| 23 |  rwds_oe_timing  |   r  | 0x0 |  — |

#### num_chips field

<p>Number of implemented chip selects.</p>

#### num_phys field

<p>Number of implemented PHY lanes.</p>

#### per_chip_cfg field

<p>Each chip record controls its corresponding chip rather than chip 0 being shared.</p>

#### per_phy_cfg field

<p>Each PHY record controls its corresponding lane rather than PHY 0 being shared.</p>

#### chip_enable field

<p>Per-chip enable bits participate in address decoding.</p>

#### clock_divider field

<p>CLOCK_CFG controls an implemented backend clock divider.</p>

#### staged_apply field

<p>FLUSH and APPLY commands implement a staged configuration barrier.</p>

#### error_status field

<p>STATUS reports sticky controller errors.</p>

#### rwds_sample_timing field

<p>Per-chip RWDS sample timing is implemented.</p>

#### rwds_oe_timing field

<p>Per-PHY RWDS output-enable timing is implemented.</p>

### command register

- Absolute Address: 0xC
- Base Offset: 0xC
- Size: 0x4

<p>Single-cycle write-one command strobes, active when capability.staged_apply is set; otherwise writes are retained only as inert pulses.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 |   flush  |  rw  | 0x0 |  — |
|  1 |   apply  |  rw  | 0x0 |  — |

### status register

- Absolute Address: 0x10
- Base Offset: 0x10
- Size: 0x4

<p>Controller status.</p>

|Bits| Identifier |  Access |Reset|Name|
|----|------------|---------|-----|----|
|  0 |decode_error|rw, woclr| 0x0 |  — |
|  1 |    busy    |    r    | 0x0 |  — |
|  2 |    dirty   |    r    | 0x0 |  — |

## frontend register file

- Absolute Address: 0x100
- Base Offset: 0x100
- Size: 0x4

|Offset| Identifier |Name|
|------|------------|----|
|  0x0 |frontend_cfg|  — |

### frontend_cfg register

- Absolute Address: 0x100
- Base Offset: 0x0
- Size: 0x4

<p>Frontend configuration. dual_phy must be 0 or 1.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|  0 | dual_phy |  rw  | 0x1 |  — |

## backend register file

- Absolute Address: 0x200
- Base Offset: 0x200
- Size: 0x4

|Offset|Identifier|Name|
|------|----------|----|
|  0x0 | clock_cfg|  — |

### clock_cfg register

- Absolute Address: 0x200
- Base Offset: 0x0
- Size: 0x4

<p>Backend clock-divider configuration, active when capability.clock_divider is set; divider values must be at least 2.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|  divider |  rw  | 0x8 |  — |

## phy_0 register file

- Absolute Address: 0x300
- Base Offset: 0x300
- Size: 0x8

|Offset| Identifier|Name|
|------|-----------|----|
|  0x0 |  tx_delay |  — |
|  0x4 |rwds_timing|  — |

### tx_delay register

- Absolute Address: 0x300
- Base Offset: 0x0
- Size: 0x4

<p>PHY transmit delay. PHY 0 is shared when capability.per_phy_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

### rwds_timing register

- Absolute Address: 0x304
- Base Offset: 0x4
- Size: 0x4

<p>PHY RWDS output-enable timing. rwds_oe_setup_cycles must be at most 15 and is active when capability.rwds_oe_timing is set.</p>

|Bits|     Identifier     |Access|Reset|Name|
|----|--------------------|------|-----|----|
| 7:0|rwds_oe_setup_cycles|  rw  | 0x1 |  — |

## phy_1 register file

- Absolute Address: 0x340
- Base Offset: 0x340
- Size: 0x8

|Offset| Identifier|Name|
|------|-----------|----|
|  0x0 |  tx_delay |  — |
|  0x4 |rwds_timing|  — |

### tx_delay register

- Absolute Address: 0x340
- Base Offset: 0x0
- Size: 0x4

<p>PHY transmit delay. PHY 0 is shared when capability.per_phy_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

### rwds_timing register

- Absolute Address: 0x344
- Base Offset: 0x4
- Size: 0x4

<p>PHY RWDS output-enable timing. rwds_oe_setup_cycles must be at most 15 and is active when capability.rwds_oe_timing is set.</p>

|Bits|     Identifier     |Access|Reset|Name|
|----|--------------------|------|-----|----|
| 7:0|rwds_oe_setup_cycles|  rw  | 0x1 |  — |

## chip_0 register file

- Absolute Address: 0x400
- Base Offset: 0x400
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x400
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x0 |  — |

### range_bound register

- Absolute Address: 0x404
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x1 |  — |

### address_cfg register

- Absolute Address: 0x408
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x40C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x410
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x414
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x418
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_1 register file

- Absolute Address: 0x440
- Base Offset: 0x440
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x440
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x1 |  — |

### range_bound register

- Absolute Address: 0x444
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x2 |  — |

### address_cfg register

- Absolute Address: 0x448
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x44C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x450
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x454
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x458
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_2 register file

- Absolute Address: 0x480
- Base Offset: 0x480
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x480
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x2 |  — |

### range_bound register

- Absolute Address: 0x484
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x3 |  — |

### address_cfg register

- Absolute Address: 0x488
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x48C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x490
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x494
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x498
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_3 register file

- Absolute Address: 0x4C0
- Base Offset: 0x4C0
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x4C0
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x3 |  — |

### range_bound register

- Absolute Address: 0x4C4
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x4 |  — |

### address_cfg register

- Absolute Address: 0x4C8
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x4CC
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x4D0
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x4D4
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x4D8
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_4 register file

- Absolute Address: 0x500
- Base Offset: 0x500
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x500
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x4 |  — |

### range_bound register

- Absolute Address: 0x504
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x5 |  — |

### address_cfg register

- Absolute Address: 0x508
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x50C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x510
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x514
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x518
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_5 register file

- Absolute Address: 0x540
- Base Offset: 0x540
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x540
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x5 |  — |

### range_bound register

- Absolute Address: 0x544
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x6 |  — |

### address_cfg register

- Absolute Address: 0x548
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x54C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x550
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x554
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x558
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_6 register file

- Absolute Address: 0x580
- Base Offset: 0x580
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x580
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x6 |  — |

### range_bound register

- Absolute Address: 0x584
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x7 |  — |

### address_cfg register

- Absolute Address: 0x588
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x58C
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x590
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x594
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x598
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

## chip_7 register file

- Absolute Address: 0x5C0
- Base Offset: 0x5C0
- Size: 0x1C

|Offset| Identifier|Name|
|------|-----------|----|
| 0x00 | range_base|  — |
| 0x04 |range_bound|  — |
| 0x08 |address_cfg|  — |
| 0x0C |latency_cfg|  — |
| 0x10 | burst_cfg |  — |
| 0x14 |chip_timing|  — |
| 0x18 |  rx_delay |  — |

### range_base register

- Absolute Address: 0x5C0
- Base Offset: 0x0
- Size: 0x4

<p>Inclusive 4 MiB-aligned chip address range base.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x7 |  — |

### range_bound register

- Absolute Address: 0x5C4
- Base Offset: 0x4
- Size: 0x4

<p>Exclusive 4 MiB-aligned chip address range bound.</p>

| Bits|Identifier|Access|Reset|Name|
|-----|----------|------|-----|----|
|31:22|   value  |  rw  | 0x8 |  — |

### address_cfg register

- Absolute Address: 0x5C8
- Base Offset: 0x8
- Size: 0x4

<p>Chip address-space interpretation and enable. address_space and enable must be 0 or 1, and address_mask_msb must be at most 31. Chip 0 is shared when capability.per_chip_cfg is clear; enable is active when capability.chip_enable is set.</p>

|Bits|   Identifier   |Access|Reset|Name|
|----|----------------|------|-----|----|
| 7:0|  address_space |  rw  | 0x0 |  — |
|15:8|address_mask_msb|  rw  | 0x19|  — |
| 16 |     enable     |  rw  | 0x1 |  — |

### latency_cfg register

- Absolute Address: 0x5CC
- Base Offset: 0xC
- Size: 0x4

<p>Chip latency configuration. t_latency_access must be 3 through 15; rwds_sample_delay must be at most t_latency_access minus 2 and is active when capability.rwds_sample_timing is set. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|      Identifier     |Access|Reset|Name|
|----|---------------------|------|-----|----|
| 7:0|   t_latency_access  |  rw  | 0x6 |  — |
|15:8|  rwds_sample_delay  |  rw  | 0x0 |  — |
| 16 |en_latency_additional|  rw  | 0x0 |  — |

### burst_cfg register

- Absolute Address: 0x5D0
- Base Offset: 0x10
- Size: 0x4

<p>Chip burst configuration. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits| Identifier|Access|Reset|Name|
|----|-----------|------|-----|----|
|15:0|t_burst_max|  rw  |0x15E|  — |

### chip_timing register

- Absolute Address: 0x5D4
- Base Offset: 0x14
- Size: 0x4

<p>Chip-select and read/write timing; byte-backed timing values must be at most 15. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

| Bits|      Identifier     |Access|Reset|Name|
|-----|---------------------|------|-----|----|
| 7:0 |t_read_write_recovery|  rw  | 0x6 |  — |
| 15:8|     t_csh_cycles    |  rw  | 0x1 |  — |
|23:16|   csn_to_ck_cycles  |  rw  | 0x0 |  — |

### rx_delay register

- Absolute Address: 0x5D8
- Base Offset: 0x18
- Size: 0x4

<p>Chip receive delay. Chip 0 is shared when capability.per_chip_cfg is clear.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
| 7:0|   value  |  rw  | 0x10|  — |

### reserved_top register

- Absolute Address: 0xFFC
- Base Offset: 0xFFC
- Size: 0x4

<p>Reserved endpoint that fixes the register window size to 4 KiB.</p>

|Bits|Identifier|Access|Reset|Name|
|----|----------|------|-----|----|
|31:0|   value  |   r  | 0x0 |  — |
