#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
# Compilation and simulations share an isolated work library.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
suite=${1:-all}
case "$suite" in all|fast|integration|performance|pad|compile) ;; *)
    printf 'Usage: %s [all|fast|integration|performance|pad|compile] [build-directory]\n' "$0" >&2
    exit 2 ;;
esac
build=${2:-"$root/build/regression-$suite"}
mkdir -p "$build"
build=$(realpath "$build")
read -ra bender <<< "${BENDER:-bender}"
read -ra vsim <<< "${VSIM:-vsim}"
cd "$root"
"${bender[@]}" --local script vsim -t rtl -t test -t hyper_test \
    --vlog-arg='-suppress 2583 -suppress 13314 -suppress 13233 -timescale "1 ns / 1 ps"' \
    > "$build/compile.tcl"
cd "$build"
if [[ ! -e models ]]; then ln -s "$root/models" models; fi
if ! "${vsim[@]}" -c -do \
    'set failed [catch {source compile.tcl} result]; if {$failed || $result eq "1"} {puts stderr $result; quit -code 1 -f}; quit -code 0 -f' \
    > compile.log 2>&1; then
    tail -80 compile.log >&2
    exit 1
fi
if grep -Eq '^#? \*\* (Error|Fatal)( \([^)]*\))?:|^# Errors: [1-9]' compile.log; then
    tail -80 compile.log >&2
    exit 1
fi
[[ $suite != compile ]] || exit 0
export HYPERBUS_TEST_SUITE="$suite"
"${vsim[@]}" -c -do "source {$root/scripts/start.tcl}" > run.log 2>&1 || {
    tail -100 run.log >&2
    exit 1
}
if [[ $suite == all || $suite == pad ]]; then
    bash "$root/scripts/run_pad_delay_matrix.sh" regression "$build" --compiled
fi
printf 'HyperBus %s regression passed. Logs: %s\n' "$suite" "$build"
