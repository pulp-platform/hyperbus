#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
UV_TOOL_DIR="${UV_TOOL_DIR:-/tmp/uv-tools}"
export UV_CACHE_DIR
export UV_TOOL_DIR

RDL="${ROOT}/src/regs/hyperbus_cfg_regs.rdl"
PEAKRDL_ARGS=(
  --from "peakrdl-cli==1.5.0"
  --with "peakrdl-regblock==1.3.1"
  --with "peakrdl-cheader==1.1.0"
  --with "peakrdl-markdown==1.0.3"
)

mkdir -p "${ROOT}/include" "${ROOT}/docs/regs"
rm -rf "${ROOT}/docs/regs/hyperbus_cfg_regs"

uvx "${PEAKRDL_ARGS[@]}" \
  peakrdl regblock \
  --cpuif apb4-flat \
  --default-reset arst_n \
  --module-name hyperbus_cfg_regblock \
  --package-name hyperbus_cfg_regblock_pkg \
  --addr-width 12 \
  -o "${ROOT}/src/regs" \
  "${RDL}"

uvx "${PEAKRDL_ARGS[@]}" \
  peakrdl c-header \
  -o "${ROOT}/include/hyperbus_cfg_regs.h" \
  "${RDL}"

uvx "${PEAKRDL_ARGS[@]}" \
  peakrdl markdown \
  -o "${ROOT}/docs/regs/hyperbus_cfg_regs.md" \
  "${RDL}"

# Keep generated RTL compatible with the repository whitespace checks.
sed -i 's/[[:space:]]\+$//' \
  "${ROOT}/src/regs/hyperbus_cfg_regblock.sv" \
  "${ROOT}/src/regs/hyperbus_cfg_regblock_pkg.sv"
