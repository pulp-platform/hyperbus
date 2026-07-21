// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

package hyperbus_pkg;

    // Maximal burst size: 2^8 1024-bit words as 16-bit words (plus one as not decremented)
    localparam unsigned HyperBurstWidth = 8 + $clog2(1024/16) + 1;
    typedef logic [HyperBurstWidth-1:0] hyper_blen_t;

    // configuration type
    typedef struct packed {
        logic [3:0]      t_latency_access;
        logic            en_latency_additional;
        logic [15:0]     t_burst_max;
        logic [3:0]      t_read_write_recovery;
        logic [7:0]      t_rx_clk_delay;
        logic [3:0]      t_csh_cycles; // configurable t_CSH for high-frequency operation (200 MHz HyperRAM)
        logic [3:0]      csn_to_ck_cycles; // delay hyper_ck after CS is asserted (more time for t_DSV)
    } chip_phy_cfg_t;

    typedef struct packed {
        logic [4:0]      address_mask_msb;
        logic            address_space;
        logic            phys_in_use;
        logic            which_phy;
    } frontend_cfg_t;

    typedef struct packed {
        chip_phy_cfg_t   chip;
        logic [7:0]      t_tx_clk_delay;
        logic            phys_in_use;
        logic            which_phy;
    } phy_cfg_t;

    function automatic frontend_cfg_t hwif_to_frontend_cfg(
        input hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__out_t hwif,
        input logic num_phys_one
    );
        frontend_cfg_t cfg;

        cfg.address_mask_msb = hwif.address_mask_msb.value.value;
        cfg.address_space    = hwif.address_space.value.value;
        cfg.phys_in_use      = num_phys_one ? 1'b0 : hwif.phys_in_use.value.value;
        cfg.which_phy        = num_phys_one ? 1'b0 : hwif.which_phy.value.value;

        return cfg;
    endfunction

    function automatic phy_cfg_t hwif_to_phy_cfg(
        input hyperbus_cfg_regblock_pkg::hyperbus_cfg_regs__out_t hwif,
        input logic num_phys_one
    );
        phy_cfg_t cfg;

        cfg.chip.t_latency_access      = hwif.t_latency_access.value.value;
        cfg.chip.en_latency_additional = hwif.en_latency_additional.value.value;
        cfg.chip.t_burst_max           = hwif.t_burst_max.value.value;
        cfg.chip.t_read_write_recovery = hwif.t_read_write_recovery.value.value;
        cfg.chip.t_rx_clk_delay        = {
            hwif.t_rx_clk_delay.coarse.value,
            hwif.t_rx_clk_delay.fine.value
        };
        cfg.chip.t_csh_cycles          = hwif.t_csh_cycles.value.value;
        cfg.chip.csn_to_ck_cycles      = hwif.csn_to_ck_cycles.value.value;
        cfg.t_tx_clk_delay             = {
            hwif.t_tx_clk_delay.coarse.value,
            hwif.t_tx_clk_delay.fine.value
        };
        cfg.phys_in_use                = num_phys_one ? 1'b0 : hwif.phys_in_use.value.value;
        cfg.which_phy                  = num_phys_one ? 1'b0 : hwif.which_phy.value.value;

        return cfg;
    endfunction

    typedef struct packed {
        logic           write;     // transaction is a write
        hyper_blen_t    burst;
        logic           burst_type;
        logic           address_space;
        logic [31:0]    address;
    } hyper_tf_t;

    typedef struct packed {
           logic [15:0]    data;
           logic           last;
           logic           error;
    } phy_rx_t;

    typedef enum logic[3:0] {
        Startup,
        Idle,
        DelayCK,
        SendCA,
        WaitLatAccess,
        WaitAddLatAccess,
        Read,
        Write,
        WaitXfer,
        WaitRWR
    } hyper_phy_state_t;

    typedef struct packed {
        logic           write;
        logic           addr_space;
        logic           burst_type;
        logic [28:0]    addr_upper;
        logic [12:0]    reserved;
        logic [2:0]     addr_lower;
    } hyper_phy_ca_t;

endpackage
