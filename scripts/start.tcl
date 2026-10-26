# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set regression_failed 0
set suite all
if {[info exists ::env(HYPERBUS_TEST_SUITE)]} {
    set suite $::env(HYPERBUS_TEST_SUITE)
}
if {$suite ni {all fast integration performance pad}} {
    puts stderr "Unknown HYPERBUS_TEST_SUITE: $suite"
    quit -code 1 -f
}
if {$suite eq "pad"} {
    puts stderr "The pad-delay suite is not available in this revision."
    quit -code 1 -f
}

proc run_test {top_name name completion_marker args} {
    global regression_failed

    puts "=============================="
    puts "= Running $top_name"
    puts "=============================="

    set transcript_name "${name}.log"
    file delete -force $transcript_name
    transcript file $transcript_name

    # Questa 10.7 rejects enum assignments in common_cells clearable CDC models.
    if {[catch {
        vsim $top_name -wlf "${name}.wlf" -t 1ps -voptargs=+acc -suppress 8386 {*}$args
        onfinish stop
        set StdArithNoWarnings 1
        set NumericStdNoWarnings 1
        run -all
    } detail]} {
        puts "Simulation command failed: $detail"
        set regression_failed 1
    }
    catch {quit -sim}

    transcript file {}
    set transcript_fd [open $transcript_name r]
    set transcript_data [read $transcript_fd]
    close $transcript_fd
    # Questa writes the previous design's summary when loading the next one.
    # Count diagnostic messages here, not that stale Errors summary.
    if {[regexp -line {^#\s+\*\* (Error|Fatal)( \([^)]*\))?:} $transcript_data] ||
        [string first $completion_marker $transcript_data] < 0} {
        puts "Regression failed or completion marker missing: $transcript_name"
        set regression_failed 1
    }
}

if {$suite in {all fast}} {
    run_test hyperbus_atomic_handler_tb atomic_handler {Atomic handler operation and protocol tests passed}
    run_test hyperbus_axi_atomic_tb axi_atomic {AXI atomic frontend/midend tests passed}
    run_test hyperbus_read_counter_tb read_counters_one_phy {Read counter tests passed}
    run_test hyperbus_read_counter_tb read_counters_two_phy {Read counter tests passed} -gNumPhys=2
    run_test hyperbus_read_counter_tb read_counters_generic {Read counter tests passed} -gMaxHostBurstBeats=0
    run_test hyperbus_read_counter_tb read_counters_generic_two_phy {Read counter tests passed} -gMaxHostBurstBeats=0 -gNumPhys=2
    run_test hyperbus_read_counter_tb read_counters_min_one_phy {Read counter tests passed} -gHostDataWidth=16
    run_test hyperbus_read_counter_tb read_counters_min_two_phy {Read counter tests passed} -gHostDataWidth=32 -gNumPhys=2
    run_test hyperbus_read_counter_tb read_counters_wide_generic {Read counter tests passed} -gHostDataWidth=1024 -gMaxHostBurstBeats=0
    foreach width {128 256 512 1024} {
        foreach phys {1 2} {
            run_test hyperbus_read_counter_tb read_counters_bounded_${width}_${phys} {Read counter tests passed} -gHostDataWidth=$width -gNumPhys=$phys
        }
    }
    run_test hyperbus_burst_bound_tb burst_bound {PASS: maximum burst rejected}
    run_test hyperbus_burst_bound_tb generic_mapped_read {PASS: generic mapped 32768-byte read} -gMaxHostBurstBeats=0 +mapped-read
    run_test hyperbus_cfg_regs_tb cfg_regs {[CFG-REGS] all checks completed}
}
if {$suite in {all integration}} {
    foreach variant {isochronous synchronous asynchronous synchronous_one_phy} {
        run_test axi_hyper_tb_$variant functional_$variant {[AXI-TEST] passed} +HYPERBUS_FUNCTIONAL_ONLY
    }
    run_test axi_pre_aw_drain_tb pre_aw_drain {Pre-AW W drain regressions passed}
}
if {$suite in {all performance}} {
    foreach variant {isochronous synchronous asynchronous synchronous_one_phy} {
        run_test axi_hyper_tb_$variant performance_$variant {[AXI-TEST] passed} +HYPERBUS_PERFORMANCE_ONLY
    }
}

quit -code $regression_failed -f
