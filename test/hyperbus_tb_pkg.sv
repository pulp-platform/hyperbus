// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

package hyperbus_tb_pkg;

    parameter int unsigned S27KS_ID0_REG_OFFSET  = 32'h0000_0000;
    parameter int unsigned S27KS_ID1_REG_OFFSET  = 32'h0000_0002;
    parameter int unsigned S27KS_CFG0_REG_OFFSET = 32'h0000_2000;
    parameter int unsigned S27KS_CFG1_REG_OFFSET = 32'h0000_2002;

    typedef struct packed {
        bit       deep_power_done;
        bit [2:0] drive_strength;
        bit [3:0] reserved;
        bit [3:0] initial_latency;
        bit       fixed_latency_enable;
        bit       hybrid_burst_enable;
        bit [1:0] burst_length;
    } s27ks_cfg0_reg_t;

    parameter s27ks_cfg0_reg_t s27ks_cfg0_default = s27ks_cfg0_reg_t'{  
        deep_power_done:      1'h1,
        drive_strength:       3'h0,
        reserved:             4'hF,
        initial_latency:      4'h1,
        fixed_latency_enable: 1'b1,
        hybrid_burst_enable:  1'b1,
        burst_length:         2'h3 
    };

endpackage
