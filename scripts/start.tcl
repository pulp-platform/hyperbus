# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set regression_failed 0

proc run_test {top_name wlf_name} {
    global regression_failed

    puts "=============================="
    puts "= Running $top_name"
    puts "=============================="

    set transcript_name "[file rootname $wlf_name].log"
    file delete -force $transcript_name
    transcript file $transcript_name

    # Questa 10.7 rejects enum assignments in common_cells clearable CDC models.
    vsim $top_name -wlf $wlf_name -t 1ps -voptargs=+acc -classdebug -suppress 8386

    onfinish stop
    set StdArithNoWarnings 1
    set NumericStdNoWarnings 1
    log -r /*
    catch {delete wave *}

    run -all
    quit -sim

    transcript file {}
    set transcript_fd [open $transcript_name r]
    set transcript_data [read $transcript_fd]
    close $transcript_fd
    if {[regexp -line {^# \*\* (Error|Fatal)( \([^)]*\))?:} $transcript_data]} {
        puts "Regression errors detected in $transcript_name"
        set regression_failed 1
    }
}

run_test axi_hyper_tb_isochronous          sim_run_isochronous.wlf
run_test axi_hyper_tb_synchronous          sim_run_synchronous.wlf
run_test axi_hyper_tb_asynchronous         sim_run_asynchronous.wlf
run_test axi_hyper_tb_synchronous_one_phy  sim_run_synchronous_one_phy.wlf
run_test hyperbus_cfg_regs_tb              sim_run_cfg_regs.wlf

quit -code $regression_failed -f
