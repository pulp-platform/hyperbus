# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

proc run_axi_hyper_variant {top_name wlf_name} {
    puts "=============================="
    puts "= Running $top_name"
    puts "=============================="

    vsim $top_name -wlf $wlf_name -t 1ps -voptargs=+acc -classdebug

    onfinish stop
    set StdArithNoWarnings 1
    set NumericStdNoWarnings 1
    log -r /*

    catch {delete wave *}

    run -all
    quit -sim
}

run_axi_hyper_variant axi_hyper_tb_isochronous  sim_run_isochronous.wlf
run_axi_hyper_variant axi_hyper_tb_synchronous  sim_run_synchronous.wlf
run_axi_hyper_variant axi_hyper_tb_asynchronous sim_run_asynchronous.wlf

quit -f
