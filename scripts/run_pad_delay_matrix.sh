#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/.." && pwd)"
vsim="${VSIM:-vsim}"
out_dir="${PAD_DELAY_MATRIX_OUT:-${root}/test/pad_delay_matrix}"
compile_log="${out_dir}/compile.log"
summary="${out_dir}/summary.csv"

mkdir -p "${out_dir}"
rm -f "${out_dir}"/*.log "${summary}"
cd "${root}"

if ! make scripts/compile_pad_delay.tcl >"${out_dir}/compile_tcl.log" 2>&1; then
  echo "pad-delay matrix: failed to generate scripts/compile_pad_delay.tcl" >&2
  tail -80 "${out_dir}/compile_tcl.log" >&2
  exit 1
fi

if ! "${vsim}" -c -do \
  "if {[file exists work]} {vdel -all -lib work}; vlib work; \
   if {[catch {source scripts/compile_pad_delay.tcl} result]} {puts stderr \$result; quit -code 1}; \
   quit -code 0" >"${compile_log}" 2>&1; then
  echo "pad-delay matrix: compilation failed" >&2
  tail -120 "${compile_log}" >&2
  exit 1
fi

printf 'case,result,expected_diagnostic,log\n' >"${summary}"
failures=0

run_direct() {
  local log="${out_dir}/direct.log"
  local status
  local result="FAIL"

  echo "[PAD-MATRIX] direct"
  set +e
  "${vsim}" -c hyperbus_pad_delay_direct_tb -t 1ps -voptargs=+acc \
    -do "run -all; quit -f" >"${log}" 2>&1
  status=$?
  set -e
  if (( status == 0 )) && grep -Fq '[PAD-LATENCY] direct pad delay check passed' "${log}" &&
     ! grep -Eq '^# \*\* (Error|Fatal):' "${log}"; then
    result="PASS"
  fi
  printf 'direct,%s,,%s\n' "${result}" "${log}" >>"${summary}"
  if [[ "${result}" != PASS ]]; then
    echo "[PAD-MATRIX] direct: unexpected result (exit ${status})" >&2
    tail -120 "${log}" >&2
    exit 1
  fi
  echo "[PAD-MATRIX] direct: PASS"
}

run_case() {
  local name="$1"
  local expectation="$2"
  local diagnostic="$3"
  shift 3
  local log="${out_dir}/${name}.log"
  local result="FAIL"
  local status
  local marker='[PAD-LATENCY] passed'
  case "${name}" in
    segment_restart) marker='[PAD-LATENCY] segment_restart passed' ;;
    late_write_data) marker='[PAD-LATENCY] late_write_data passed' ;;
  esac

  echo "[PAD-MATRIX] ${name}"
  set +e
  "${vsim}" -c axi_hyper_pad_delay_tb -t 1ps -voptargs=+acc \
    "$@" -do "run -all; quit -f" >"${log}" 2>&1
  status=$?
  set -e

  if [[ "${expectation}" == pass ]]; then
    if (( status == 0 )) && grep -Fq "${marker}" "${log}" &&
       ! grep -Eq '^# \*\* (Error|Fatal):' "${log}"; then
      result="PASS"
    fi
  else
    # Expected protocol violations terminate the focused test with severity 3.
    # Questa may still return status 0 after $fatal, so require one anchored,
    # exact fatal line and reject every other Error/Fatal line.
    local expected_fatal="# ** Fatal: [HYPERRAM-MODEL] ${diagnostic}"
    if awk -v expected="${expected_fatal}" \
      '/^# \*\* (Error|Fatal):/ { count++; if ($0 != expected) bad=1 } \
       END { exit !(count == 1 && !bad) }' "${log}"; then
      result="EXPECTED_FAIL"
    fi
  fi

  printf '%s,%s,%s,%s\n' "${name}" "${result}" "${diagnostic}" "${log}" >>"${summary}"
  if [[ "${result}" == FAIL ]]; then
    failures=$((failures + 1))
    echo "[PAD-MATRIX] ${name}: unexpected result (exit ${status})" >&2
    tail -80 "${log}" >&2
  else
    echo "[PAD-MATRIX] ${name}: ${result}"
  fi
}

run_direct

# The focused test is synchronous and uses a 4 ns model reference cycle.
# Variable-latency cases use cfg0=0x871f and the artificial always-extra policy.
run_case baseline pass ''
run_case single_phy pass '' -gNumPhys=1
run_case forced_additional pass '' -gTbAssumeAdditionalLatency=1
run_case segment_restart pass '' -gTbModelCfg0ResetValue=34591 +scenario=segment_restart
run_case late_write_data pass '' +scenario=late_write_data
run_case output4_sample1 pass '' -gTbModelCfg0ResetValue=34591 -gTbModelLatencyPolicy=1 -gTbExpectedModelExtraLatencyTransactions=2 \
  +pad_out_q=4 +dq_oe_assert_q=4 +dq_oe_release_q=4 +rwds_oe_assert_q=4 +rwds_oe_release_q=4 +rwds_sample_q=1
run_case input4_sample1 pass '' -gTbModelCfg0ResetValue=34591 -gTbModelLatencyPolicy=1 -gTbExpectedModelExtraLatencyTransactions=2 \
  +pad_in_q=4 +rwds_sample_q=1
run_case output4_input4_sample2 pass '' -gTbModelCfg0ResetValue=34591 -gTbModelLatencyPolicy=1 -gTbExpectedModelExtraLatencyTransactions=2 \
  +pad_out_q=4 +pad_in_q=4 +dq_oe_assert_q=4 +dq_oe_release_q=4 +rwds_oe_assert_q=4 +rwds_oe_release_q=4 +rwds_sample_q=2
# With variable latency selected, an over-late RWDS sample makes the controller
# end the segment on its shorter schedule; the model reports this at CS release.
run_case output4_input4_sample3 expected_fail 'CS# deasserted before the data phase' \
  -gTbModelCfg0ResetValue=34591 -gTbModelLatencyPolicy=1 -gTbExpectedModelExtraLatencyTransactions=2 \
  +pad_out_q=4 +pad_in_q=4 +dq_oe_assert_q=4 +dq_oe_release_q=4 +rwds_oe_assert_q=4 +rwds_oe_release_q=4 +rwds_sample_q=3

run_case dq_assert1_read pass '' -gTbReadOnly=1 +dq_oe_assert_q=1
run_case dq_assert8_read_csn0 expected_fail 'DQ is not driven by host at CA/write sampling edge' \
  -gTbReadOnly=1 -gTbCsnToCkCycles=0 +dq_oe_assert_q=8

run_case rwds_assert24_setup15 pass '' -gTbRwdsOeSetupCycles=15 -gTbExpectedRwdsOeWaitCycles=5 +rwds_oe_assert_q=24
run_case rwds_assert24_setup0 pass '' \
  -gTbRwdsOeSetupCycles=0 +rwds_oe_assert_q=24

run_case dq_release40_fixed pass '' -gTbReadOnly=1 +dq_oe_release_q=40
run_case dq_release48_fixed expected_fail 'host did not release DQ/RWDS before read data turnaround' \
  -gTbReadOnly=1 +dq_oe_release_q=48

run_case rwds_release20_default pass '' +rwds_oe_release_q=20
run_case rwds_release28_default expected_fail 'RWDS driven by host outside write-mask ownership window' \
  +rwds_oe_release_q=28
run_case rwds_release28_recovery8 pass '' +rwds_oe_release_q=28 +t_read_write_recovery=8

echo "[PAD-MATRIX] summary: ${summary}"
if (( failures != 0 )); then
  exit 1
fi
