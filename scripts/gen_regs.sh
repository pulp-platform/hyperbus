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

mkdir -p "${ROOT}/include" "${ROOT}/docs/regs"
rm -rf "${ROOT}/docs/regs/hyperbus_cfg_regs"

uvx --from peakrdl-cli \
  --with peakrdl-regblock \
  --with peakrdl-cheader \
  --with peakrdl-markdown \
  peakrdl regblock \
  --cpuif apb4-flat \
  --default-reset arst_n \
  --module-name hyperbus_cfg_regblock \
  --package-name hyperbus_cfg_regblock_pkg \
  --addr-width 7 \
  -o "${ROOT}/src/regs" \
  "${RDL}"

uvx --from peakrdl-cli \
  --with peakrdl-regblock \
  --with peakrdl-cheader \
  --with peakrdl-markdown \
  peakrdl c-header \
  -o "${ROOT}/include/hyperbus_cfg_regs.h" \
  "${RDL}"

uvx --from peakrdl-cli \
  --with peakrdl-regblock \
  --with peakrdl-cheader \
  --with peakrdl-markdown \
  peakrdl markdown \
  -o "${ROOT}/docs/regs/hyperbus_cfg_regs.md" \
  "${RDL}"
