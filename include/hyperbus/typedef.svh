// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`ifndef HYPERBUS_TYPEDEF_SVH_
`define HYPERBUS_TYPEDEF_SVH_

`define HYPERBUS_TYPEDEF_HOST_CMD_T(__name, __addr_t) \
  typedef struct packed {                               \
    logic                             write;             \
    __addr_t                          addr;              \
    hyperbus_pkg::hyper_blen_t        beats;             \
    hyperbus_pkg::hyper_host_size_t   size;              \
    hyperbus_pkg::hyper_host_burst_e  burst;             \
    hyperbus_pkg::hyper_atomic_op_e   atomic_op;         \
    logic                             atomic_return;     \
    logic                             ordered;           \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_W_T(__name, __data_t, __strb_t) \
  typedef struct packed {                                      \
    __data_t data;                                             \
    __strb_t strb;                                             \
    logic    last;                                             \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_R_T(__name, __data_t) \
  typedef struct packed {                            \
    __data_t                      data;               \
    hyperbus_pkg::hyper_resp_e   resp;               \
    logic                         last;               \
    logic                         atomic_ok;          \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_WRSP_T(__name)       \
  typedef struct packed {                          \
    hyperbus_pkg::hyper_resp_e resp;               \
    logic                      atomic_ok;          \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_REQ_T(__name, __cmd_t, __w_t) \
  typedef struct packed {                                      \
    __cmd_t cmd;                                               \
    logic   cmd_valid;                                         \
    __w_t   w;                                                 \
    logic   w_valid;                                           \
    logic   r_ready;                                           \
    logic   wrsp_ready;                                        \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_RSP_T(__name, __r_t, __wrsp_t) \
  typedef struct packed {                                      \
    logic    cmd_ready;                                        \
    logic    w_ready;                                          \
    __r_t    r;                                                \
    logic    r_valid;                                          \
    __wrsp_t wrsp;                                             \
    logic    wrsp_valid;                                       \
  } __name;

`define HYPERBUS_TYPEDEF_HOST_ALL_CT(__name, __addr_t, __data_t, __strb_t) \
  `HYPERBUS_TYPEDEF_HOST_CMD_T(__name``_cmd_t, __addr_t)                   \
  `HYPERBUS_TYPEDEF_HOST_W_T(__name``_w_t, __data_t, __strb_t)            \
  `HYPERBUS_TYPEDEF_HOST_R_T(__name``_r_t, __data_t)                      \
  `HYPERBUS_TYPEDEF_HOST_WRSP_T(__name``_wrsp_t)                          \
  `HYPERBUS_TYPEDEF_HOST_REQ_T(__name``_req_t, __name``_cmd_t,            \
                               __name``_w_t)                               \
  `HYPERBUS_TYPEDEF_HOST_RSP_T(__name``_rsp_t, __name``_r_t,              \
                               __name``_wrsp_t)

`define HYPERBUS_TYPEDEF_LINK_ALL_CT(__name, __num_phys, __num_chips) \
  typedef struct packed {                                             \
    logic [(16*__num_phys)-1:0] data;                                 \
    logic                       last;                                 \
    logic [(2*__num_phys)-1:0]  strb;                                 \
  } __name``_tx_t;                                                    \
  typedef struct packed {                                             \
    logic [(16*__num_phys)-1:0] data;                                 \
    logic                       last;                                 \
    logic                       error;                                \
  } __name``_rx_t;                                                    \
  typedef struct packed {                                             \
    logic error;                                                      \
  } __name``_wrsp_t;                                                  \
  typedef struct packed {                                             \
    hyperbus_pkg::hyper_tf_t trans;                                   \
    logic [__num_chips-1:0]  cs;                                      \
  } __name``_cmd_t;                                                   \
  typedef struct packed {                                             \
    __name``_cmd_t  cmd;                                              \
    logic           cmd_valid;                                        \
    __name``_tx_t   tx;                                               \
    logic           tx_valid;                                         \
    logic           rx_ready;                                         \
    logic           wrsp_ready;                                       \
  } __name``_req_t;                                                   \
  typedef struct packed {                                             \
    logic           cmd_ready;                                        \
    logic           tx_ready;                                         \
    __name``_rx_t   rx;                                               \
    logic           rx_valid;                                         \
    __name``_wrsp_t wrsp;                                             \
    logic           wrsp_valid;                                       \
  } __name``_rsp_t;

`endif
