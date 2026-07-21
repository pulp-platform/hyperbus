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

    vsim $top_name -wlf $wlf_name -t 1ps -voptargs=+acc -classdebug

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

run_test axi_hyper_tb           sim_run_axi.wlf
run_test hyperbus_cfg_regs_tb   sim_run_cfg_regs.wlf

quit -code $regression_failed -f
