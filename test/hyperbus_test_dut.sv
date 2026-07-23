// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module hyperbus_test_dut #(
    parameter int unsigned  DutVariant       = 0,
    parameter int unsigned  NumChips         = -1,
    parameter int unsigned  NumPhys          = 2,
    parameter int unsigned  AxiAddrWidth     = -1,
    parameter int unsigned  AxiDataWidth     = -1,
    parameter int unsigned  AxiIdWidth       = -1,
    parameter int unsigned  AxiUserWidth     = -1,
    parameter type          axi_req_t        = logic,
    parameter type          axi_rsp_t        = logic,
    parameter type          axi_w_chan_t     = logic,
    parameter type          axi_b_chan_t     = logic,
    parameter type          axi_ar_chan_t    = logic,
    parameter type          axi_r_chan_t     = logic,
    parameter type          axi_aw_chan_t    = logic,
    parameter int unsigned  RegAddrWidth     = -1,
    parameter int unsigned  RegDataWidth     = -1,
    parameter int unsigned  MinFreqMHz       = 100,
    parameter type          reg_req_t        = logic,
    parameter type          reg_rsp_t        = logic,
    parameter type          axi_rule_t       = logic
) (
    input  logic                        clk_sys_i,
    input  logic                        rst_sys_ni,
    input  logic                        clk_phy_i,
    input  logic                        rst_phy_ni,
`ifdef TARGET_XILINX
    input  logic                        clk_ref200_i,
`endif
    input  logic                        test_mode_i,

    input  axi_req_t                    axi_req_i,
    output axi_rsp_t                    axi_rsp_o,

    input  reg_req_t                    reg_req_i,
    output reg_rsp_t                    reg_rsp_o,

    output logic [NumPhys-1:0][NumChips-1:0] hyper_cs_no,
    output logic [NumPhys-1:0]               hyper_ck_o,
    output logic [NumPhys-1:0]               hyper_ck_no,
    output logic [NumPhys-1:0]               hyper_rwds_o,
    input  logic [NumPhys-1:0]               hyper_rwds_i,
    output logic [NumPhys-1:0]               hyper_rwds_oe_o,
    input  logic [NumPhys-1:0][7:0]          hyper_dq_i,
    output logic [NumPhys-1:0][7:0]          hyper_dq_o,
    output logic [NumPhys-1:0]               hyper_dq_oe_o,
    output logic [NumPhys-1:0]               hyper_reset_no
);

    localparam int unsigned VariantIsochronous  = 0;
    localparam int unsigned VariantSynchronous  = 1;
    localparam int unsigned VariantAsynchronous = 2;

    if (DutVariant == VariantIsochronous) begin : gen_isochronous
        hyperbus_isochronous #(
            .NumChips       ( NumChips      ),
            .NumPhys        ( NumPhys       ),
            .AxiAddrWidth   ( AxiAddrWidth  ),
            .AxiDataWidth   ( AxiDataWidth  ),
            .AxiIdWidth     ( AxiIdWidth    ),
            .AxiUserWidth   ( AxiUserWidth  ),
            .axi_req_t      ( axi_req_t     ),
            .axi_rsp_t      ( axi_rsp_t     ),
            .axi_aw_chan_t  ( axi_aw_chan_t ),
            .axi_w_chan_t   ( axi_w_chan_t  ),
            .axi_b_chan_t   ( axi_b_chan_t  ),
            .axi_ar_chan_t  ( axi_ar_chan_t ),
            .axi_r_chan_t   ( axi_r_chan_t  ),
            .RegAddrWidth   ( RegAddrWidth  ),
            .RegDataWidth   ( RegDataWidth  ),
            .MinFreqMHz     ( MinFreqMHz    ),
            .reg_req_t      ( reg_req_t     ),
            .reg_rsp_t      ( reg_rsp_t     ),
            .axi_rule_t     ( axi_rule_t    )
        ) i_dut (
            .clk_sys_i              ( clk_sys_i         ),
            .rst_sys_ni             ( rst_sys_ni        ),
`ifdef TARGET_XILINX
            .clk_ref200_i           ( clk_ref200_i      ),
`endif
            .test_mode_i            ( test_mode_i       ),
            .axi_req_i              ( axi_req_i         ),
            .axi_rsp_o              ( axi_rsp_o         ),
            .reg_req_i              ( reg_req_i         ),
            .reg_rsp_o              ( reg_rsp_o         ),
            .hyper_cs_no            ( hyper_cs_no       ),
            .hyper_ck_o             ( hyper_ck_o        ),
            .hyper_ck_no            ( hyper_ck_no       ),
            .hyper_rwds_o           ( hyper_rwds_o      ),
            .hyper_rwds_i           ( hyper_rwds_i      ),
            .hyper_rwds_oe_o        ( hyper_rwds_oe_o   ),
            .hyper_dq_i             ( hyper_dq_i        ),
            .hyper_dq_o             ( hyper_dq_o        ),
            .hyper_dq_oe_o          ( hyper_dq_oe_o     ),
            .hyper_reset_no         ( hyper_reset_no    )
        );
    end else if (DutVariant == VariantSynchronous) begin : gen_synchronous
        hyperbus_synchronous #(
            .NumChips       ( NumChips      ),
            .NumPhys        ( NumPhys       ),
            .AxiAddrWidth   ( AxiAddrWidth  ),
            .AxiDataWidth   ( AxiDataWidth  ),
            .AxiIdWidth     ( AxiIdWidth    ),
            .AxiUserWidth   ( AxiUserWidth  ),
            .axi_req_t      ( axi_req_t     ),
            .axi_rsp_t      ( axi_rsp_t     ),
            .axi_aw_chan_t  ( axi_aw_chan_t ),
            .axi_w_chan_t   ( axi_w_chan_t  ),
            .axi_b_chan_t   ( axi_b_chan_t  ),
            .axi_ar_chan_t  ( axi_ar_chan_t ),
            .axi_r_chan_t   ( axi_r_chan_t  ),
            .RegAddrWidth   ( RegAddrWidth  ),
            .RegDataWidth   ( RegDataWidth  ),
            .MinFreqMHz     ( MinFreqMHz    ),
            .reg_req_t      ( reg_req_t     ),
            .reg_rsp_t      ( reg_rsp_t     ),
            .axi_rule_t     ( axi_rule_t    )
        ) i_dut (
            .clk_sys_i              ( clk_sys_i         ),
            .rst_sys_ni             ( rst_sys_ni        ),
`ifdef TARGET_XILINX
            .clk_ref200_i           ( clk_ref200_i      ),
`endif
            .test_mode_i            ( test_mode_i       ),
            .axi_req_i              ( axi_req_i         ),
            .axi_rsp_o              ( axi_rsp_o         ),
            .reg_req_i              ( reg_req_i         ),
            .reg_rsp_o              ( reg_rsp_o         ),
            .hyper_cs_no            ( hyper_cs_no       ),
            .hyper_ck_o             ( hyper_ck_o        ),
            .hyper_ck_no            ( hyper_ck_no       ),
            .hyper_rwds_o           ( hyper_rwds_o      ),
            .hyper_rwds_i           ( hyper_rwds_i      ),
            .hyper_rwds_oe_o        ( hyper_rwds_oe_o   ),
            .hyper_dq_i             ( hyper_dq_i        ),
            .hyper_dq_o             ( hyper_dq_o        ),
            .hyper_dq_oe_o          ( hyper_dq_oe_o     ),
            .hyper_reset_no         ( hyper_reset_no    )
        );
    end else if (DutVariant == VariantAsynchronous) begin : gen_asynchronous
        hyperbus_asynchronous #(
            .NumChips       ( NumChips      ),
            .NumPhys        ( NumPhys       ),
            .AxiAddrWidth   ( AxiAddrWidth  ),
            .AxiDataWidth   ( AxiDataWidth  ),
            .AxiIdWidth     ( AxiIdWidth    ),
            .AxiUserWidth   ( AxiUserWidth  ),
            .axi_req_t      ( axi_req_t     ),
            .axi_rsp_t      ( axi_rsp_t     ),
            .axi_aw_chan_t  ( axi_aw_chan_t ),
            .axi_w_chan_t   ( axi_w_chan_t  ),
            .axi_b_chan_t   ( axi_b_chan_t  ),
            .axi_ar_chan_t  ( axi_ar_chan_t ),
            .axi_r_chan_t   ( axi_r_chan_t  ),
            .RegAddrWidth   ( RegAddrWidth  ),
            .RegDataWidth   ( RegDataWidth  ),
            .MinFreqMHz     ( MinFreqMHz    ),
            .reg_req_t      ( reg_req_t     ),
            .reg_rsp_t      ( reg_rsp_t     ),
            .axi_rule_t     ( axi_rule_t    )
        ) i_dut (
            .clk_sys_i              ( clk_sys_i         ),
            .rst_sys_ni             ( rst_sys_ni        ),
            .clk_phy_i              ( clk_phy_i         ),
            .rst_phy_ni             ( rst_phy_ni        ),
`ifdef TARGET_XILINX
            .clk_ref200_i           ( clk_ref200_i      ),
`endif
            .test_mode_i            ( test_mode_i       ),
            .axi_req_i              ( axi_req_i         ),
            .axi_rsp_o              ( axi_rsp_o         ),
            .reg_req_i              ( reg_req_i         ),
            .reg_rsp_o              ( reg_rsp_o         ),
            .hyper_cs_no            ( hyper_cs_no       ),
            .hyper_ck_o             ( hyper_ck_o        ),
            .hyper_ck_no            ( hyper_ck_no       ),
            .hyper_rwds_o           ( hyper_rwds_o      ),
            .hyper_rwds_i           ( hyper_rwds_i      ),
            .hyper_rwds_oe_o        ( hyper_rwds_oe_o   ),
            .hyper_dq_i             ( hyper_dq_i        ),
            .hyper_dq_o             ( hyper_dq_o        ),
            .hyper_dq_oe_o          ( hyper_dq_oe_o     ),
            .hyper_reset_no         ( hyper_reset_no    )
        );
    end else begin : gen_invalid_variant
        initial begin
            $fatal(1, "Unsupported HyperBus DUT variant %0d", DutVariant);
        end
    end

endmodule
