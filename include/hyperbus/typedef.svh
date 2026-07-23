// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`ifndef HYPERBUS_TYPEDEF_SVH_
`define HYPERBUS_TYPEDEF_SVH_

`define HYPERBUS_TYPEDEF_HOST_REQ_T(__name, __addr_t) \
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

`define HYPERBUS_TYPEDEF_HOST_ALL_CT(__name, __addr_t, __data_t, __strb_t) \
  `HYPERBUS_TYPEDEF_HOST_REQ_T(__name``_req_t, __addr_t)                   \
  `HYPERBUS_TYPEDEF_HOST_W_T(__name``_w_t, __data_t, __strb_t)            \
  `HYPERBUS_TYPEDEF_HOST_R_T(__name``_r_t, __data_t)                      \
  `HYPERBUS_TYPEDEF_HOST_WRSP_T(__name``_wrsp_t)

`endif
