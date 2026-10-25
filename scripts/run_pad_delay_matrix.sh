#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: SHL-0.51
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
usage() {
    echo "Usage: $0 regression|characterize BUILD [--profile NAME] [--phys 1|2|both]" >&2
    echo "       [--axis out|in|dq_assert|dq_release|rwds_assert|rwds_release] [--max-ticks N] [--step-ticks N] [--timeout SECONDS]" >&2
    exit 2
}
[[ $# -ge 2 ]] || usage
mode=$1 build=$2
shift 2
profile= axis= max_ticks=8 step_ticks=1 seconds=120 compiled=0
phys_counts=(1 2)
while (( $# )); do
    if [[ $1 == --compiled ]]; then compiled=1; shift; continue; fi
    [[ $# -ge 2 ]] || usage
    case $1 in
        --profile) profile=$2 ;;
        --axis) axis=$2 ;;
        --max-ticks) max_ticks=$2 ;;
        --step-ticks) step_ticks=$2 ;;
        --timeout) seconds=$2 ;;
        --phys) case $2 in 1|2) phys_counts=("$2") ;; both) phys_counts=(1 2) ;; *) usage ;; esac ;;
        *) usage ;;
    esac
    shift 2
done
[[ $mode == regression || $mode == characterize ]] || usage
[[ $max_ticks =~ ^(0|[1-9][0-9]?)$ && $step_ticks =~ ^[1-9][0-9]?$ && $seconds =~ ^[1-9][0-9]*$ ]] || usage
(( max_ticks <= 63 && step_ticks <= 63 )) || usage
axes=(out in dq_assert dq_release rwds_assert rwds_release)
axis_index=-1
for i in "${!axes[@]}"; do [[ ${axes[i]} != "$axis" ]] || axis_index=$i; done
if [[ $mode == characterize ]]; then
    (( axis_index >= 0 )) || usage
    profile=${profile:-baseline}
else
    [[ -z $axis ]] || usage
fi
mapfile -t profiles < <(tail -n +2 "$root/test/pad_delay_profiles.csv")
IFS=, read -ra baseline <<< "${profiles[0]}"
if [[ -n $profile ]]; then
    selected=()
    for row in "${profiles[@]}"; do [[ ${row%%,*} != "$profile" ]] || selected+=("$row"); done
    (( ${#selected[@]} )) || { echo "Unknown profile: $profile" >&2; exit 2; }
    profiles=("${selected[@]}")
fi
mkdir -p "$build"
build=$(realpath "$build")
pid=
trap 'if [[ -n $pid ]]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; kill -KILL -- -"$pid" 2>/dev/null || :; fi; exit 130' INT TERM HUP
wait_job() {
    local rc=0
    wait "$pid" || rc=$?
    # timeout can exit when its leader dies, leaving TERM-ignoring children.
    if (( rc >= 124 )); then kill -KILL -- -"$pid" 2>/dev/null || :; fi
    pid=
    return "$rc"
}
if (( !compiled )); then
    timeout -k 5 600 bash "$root/scripts/run_regression.sh" compile "$build" &
    pid=$!
    wait_job
fi
read -ra vsim <<< "${VSIM:-vsim}"
plusargs=(PAD_OUT_TICKS PAD_IN_TICKS DQ_OE_ASSERT_TICKS DQ_OE_RELEASE_TICKS
          RWDS_OE_ASSERT_TICKS RWDS_OE_RELEASE_TICKS PAD_CSN_TO_CK PAD_RWDS_SAMPLE
          PAD_RWDS_SETUP PAD_CSH PAD_RECOVERY PAD_VARIABLE_LATENCY)
cd "$build"
printf 'case,phys,status,%s\n' "$(head -n 1 "$root/test/pad_delay_profiles.csv" | cut -d, -f2-)" > results.csv
echo 'case,phys,lane,axis,samples,min_ps,max_ps' > measurements.csv
echo 'control,phys,observed,outcome' > negative_controls.csv
failed=0
run_case() {
    local name=$1 phys=$2 expected=${3:-} fault=${4:-} rc=0 status log suffix cfg
    local args=()
    log="${name}_phys${phys}.log"
    suffix=synchronous
    (( phys != 1 )) || suffix=synchronous_one_phy
    for i in "${!plusargs[@]}"; do args+=("+${plusargs[i]}=${values[i]}"); done
    [[ -z $fault ]] || args+=("+$fault")
    timeout -k 5 "$seconds" bash -c '"$@"' pad-matrix "${vsim[@]}" \
        -c "axi_hyper_tb_$suffix" -t 1ps -voptargs=+acc -suppress 8386 \
        +HYPERBUS_PAD_MATRIX "${args[@]}" \
        -do 'onfinish stop; run -all; quit -code 0 -f' > "$log" 2>&1 &
    pid=$!
    wait_job || rc=$?
    # Only explicit pin/data failures are sweep boundaries; tool, adapter and
    # watchdog failures must not turn into successful characterization results.
    status=$(awk -v rc="$rc" '
        /^#?[[:space:]]*\*\* (Error|Fatal)( \([^)]*\))?:/ {
            errors++
            if ($0 !~ /\[(PAD-(PINS|DATA)|AXI(-[A-Z-]+)?|MIDEND-BUFFER|CROSS-CHIP)\]/) bad=1
            if ($0 ~ /\*\* Fatal/) fatal=1
        }
        /^#?[[:space:]]*\[PAD-MATRIX\] passed[[:space:]]*$/ { done=1 }
        END {
            if (rc > 1 || bad || (!done && !fatal)) print "ERROR"
            else if (errors) print "FAIL"
            else if (rc == 0 && done) print "PASS"
            else print "ERROR"
        }' "$log")
    if [[ -n $expected ]]; then
        if [[ $status != FAIL ]] || ! grep -Eq "^#?[[:space:]]*\*\* (Error|Fatal).*\[$expected\]" "$log"; then
            echo "$name phys=$phys: ERROR (expected $expected failure, got $status); see $log" >&2
            return 1
        fi
        echo "$name,$phys,$status,PASS" >> negative_controls.csv
        echo "$name phys=$phys: PASS (expected failure)"
        return
    fi
    if [[ $status == PASS ]]; then
        printf -v cfg '[PAD-MATRIX] phys=%s chips=2 out=%s in=%s dq_assert=%s dq_release=%s rwds_assert=%s rwds_release=%s csn_to_ck=%s rwds_sample=%s rwds_setup=%s csh=%s recovery=%s variable_latency=%s' "$phys" "${values[@]}"
        grep -Fq "$cfg" "$log" || status=ERROR
    fi
    if ! awk -v name="$name" -v phys="$phys" -v status="$status" '
        /^#?[[:space:]]*\[PAD-MEASURE\] phy=/ {
            sub(/^#?[[:space:]]*/, "")
            for (i=2; i<=NF; i++) { split($i, a, "="); value[a[1]]=a[2] }
            count[value["phy"]]++; total++
            print name "," phys "," value["phy"] "," value["axis"] "," value["samples"] "," value["min_ps"] "," value["max_ps"]
        }
        END { if (status == "PASS") {
            if (total != 6 * phys) exit 1
            for (p=0; p<phys; p++) if (count[p] != 6) exit 1
        }}' "$log" >> measurements.csv; then status=ERROR; fi
    printf '%s,%s,%s' "$name" "$phys" "$status" >> results.csv
    printf ',%s' "${values[@]}" >> results.csv
    printf '\n' >> results.csv
    echo "$name phys=$phys: $status ($log)"
    [[ $status != ERROR ]] || return 1
    if [[ $status == FAIL ]]; then
        [[ $mode != regression ]] || failed=1
        if [[ $mode == characterize && ${values[axis_index]} == 0 ]]; then
            echo 'Zero-delay sweep control failed' >&2
            return 1
        fi
    fi
}
if [[ $mode == regression ]]; then
    values=("${baseline[@]:1}")
    for phys in "${phys_counts[@]}"; do
        run_case negative_read "$phys" AXI PAD_INJECT_READ_FAULT
        run_case negative_read_x "$phys" AXI PAD_INJECT_READ_X
        run_case negative_ca "$phys" PAD-PINS PAD_INJECT_CA_OE_FAULT
    done
fi
for row in "${profiles[@]}"; do
    IFS=, read -ra fields <<< "$row"
    values=("${fields[@]:1}")
    limit=0
    [[ $mode != characterize ]] || limit=$max_ticks
    for ((ticks=0; ticks<=limit; ticks+=step_ticks)); do
        name=${fields[0]}
        if [[ $mode == characterize ]]; then values[axis_index]=$ticks; name+="_${axis}_${ticks}"; fi
        for phys in "${phys_counts[@]}"; do run_case "$name" "$phys"; done
    done
done
echo "Results: $build/results.csv; measurements: $build/measurements.csv"
exit "$failed"
