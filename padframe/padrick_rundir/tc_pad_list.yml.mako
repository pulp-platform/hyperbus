# Copyright 2026 Fondazione Chips-IT.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#

#-------------------------------------------------#
#                                                 #
#  ****** TOP/RIGHT: north and east sides ******  #
#                                                 #
#-------------------------------------------------#

- name: config_tc_pad
  description: "Config and internal signals instantation"
  pad_type: CONFIG_TC_PAD_DEF
  is_static: true
  # connections:
  #   retcin: retcin_i

#-----------------------#
#                       #
#  ****** NORTH ******  #
#                       #
#-----------------------#

#-----------------------------------------
# POWER MANAGEMENT PADS - North 
#-----------------------------------------

- name: pwr_mng_north
  description: "Power management vertical pad cell"
  pad_type: PAD_PWR_MNG_V
  is_static: true

#-----------------------------------------
# I/O POWER - North
#-----------------------------------------

- name: vdd_io_{i}_v
  multiple: 3
  description: "I/O power domain vertical VDD pad"
  pad_type: PAD_VDD_IO_V
  is_static: true

- name: vss_io_{i}_v
  multiple: 3
  description: "I/O power domain vertical VSS pad"
  pad_type: PAD_VSS_IO_V
  is_static: true

#-----------------------------------------
# CORE POWER - North
#-----------------------------------------

- name: vdd_core_{i}_v
  multiple: 3
  description: "Core power domain vertical VDD pad"
  pad_type: PAD_VDD_CORE_V
  is_static: true

- name: vss_core_{i}_v
  multiple: 2
  description: "Core power domain vertical VSS pad"
  pad_type: PAD_VSS_CORE_V
  is_static: true

#-----------------------------------------
# POWER MANAGEMENT PADS - East
#-----------------------------------------

- name: pwr_mng_east
  description: "Power management horizontal pad cell"
  pad_type: PAD_PWR_MNG_H
  is_static: true

#-----------------------------------------
# I/O POWER - East
#-----------------------------------------

- name: vdd_io_{i}_h
  multiple: 3
  description: "I/O power domain horizontal VDD pad"
  pad_type: PAD_VDD_IO_H
  is_static: true

- name: vss_io_{i}_h
  multiple: 3
  description: "I/O power domain horizontal VSS pad"
  pad_type: PAD_VSS_IO_H
  is_static: true

#-----------------------------------------
# CORE POWER - East
#-----------------------------------------

- name: vdd_core_{i}_h
  multiple: 3
  description: "Core power domain horizontal VDD pad"
  pad_type: PAD_VDD_CORE_H
  is_static: true

- name: vss_core_{i}_h
  multiple: 2
  description: "Core power domain horizontal VSS pad"
  pad_type: PAD_VSS_CORE_H
  is_static: true

#-----------------------------------------
# HYPERBUS
#-----------------------------------------

% for phy, side, orien in [('phy1', 'North', 'V'), ('phy0', 'East', 'H'),]:
#-----------------------------------------
# HYPERBUS - ${side}
#-----------------------------------------

- name: hyper_${phy}_cs_n_{i}
  multiple: 2
  description: "Hyperbus cs out, active-low"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_cs_no_{i}
    output_en: 1'b1
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

- name: hyper_${phy}_ck
  description: "Hyperbus ck out"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_ck_o
    output_en: 1'b1
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

- name: hyper_${phy}_ck_n
  description: "Hyperbus ck out, active-low"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_ck_no
    output_en: 1'b1
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

- name: hyper_${phy}_rwds
  description: "Hyperbus rwds in/out"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_rwds_o
    pad2chip: hyper_${phy}_rwds_i
    input_en: ~hyper_${phy}_rwds_oe_o
    output_en: hyper_${phy}_rwds_oe_o
    schmitt_en: hyper_${phy}_schmitt_en_o
    pu_en: hyper_${phy}_pu_en_o
    pd_en: hyper_${phy}_pd_en_o
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

- name: hyper_${phy}_reset_n
  description: "Hyperbus reset out, active-low"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_reset_no
    output_en: 1'b1
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

- name: hyper_${phy}_dq_b{i}
  multiple: 8
  description: "Hyperbus dq in/out"
  pad_type: PAD_BIDIR_${orien}
  is_static: true
  connections:
    chip2pad: hyper_${phy}_dq_o_b{i}
    pad2chip: hyper_${phy}_dq_i_b{i}
    input_en: ~hyper_${phy}_dq_oe_o_b{i}
    output_en: hyper_${phy}_dq_oe_o_b{i}
    schmitt_en: hyper_${phy}_schmitt_en_o
    pu_en: hyper_${phy}_pu_en_o
    pd_en: hyper_${phy}_pd_en_o
    slew_en: hyper_${phy}_slew_en_o
    drive_strength: hyper_${phy}_drive_strength_o

% endfor