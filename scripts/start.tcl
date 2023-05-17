# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

vsim axi_hyper_tb -t 1ps -voptargs=+acc -classdebug

set StdArithNoWarnings 1
set NumericStdNoWarnings 1
log -r /*

delete wave *

run -all
