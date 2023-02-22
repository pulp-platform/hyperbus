// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

package hyperbus_pkg;

    // Maximal burst size: 2^8 1024-bit words as 16-bit words (plus one as not decremented)
    localparam unsigned HyperBurstWidth = 8 + $clog2(1024/16) + 1;
    typedef logic [HyperBurstWidth-1:0] hyper_blen_t;

    // configuration type
    typedef struct packed {
        logic [3:0]     t_latency_access;
        logic           en_latency_additional;
        logic [15:0]    t_burst_max;
        logic [3:0]     t_read_write_recovery;
        logic [3:0]     t_rx_clk_delay;
        logic [3:0]     t_tx_clk_delay;
        logic [4:0]     address_mask_msb;
        logic           address_space;
    } hyper_cfg_t;

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
        SendCA,
        WaitLatAccess,
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
