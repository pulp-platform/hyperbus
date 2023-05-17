# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Paul Scheffler <paulsc@iis.ee.ethz.ch>

GIT ?= git
BENDER ?= bender
VSIM ?= vsim

all: build run

clean: sim_clean

# Ensure half-built targets are purged
.DELETE_ON_ERROR:

ifdef gui
VSIM_ARGS := -do
else
VSIM_ARGS := -c -do
endif

# --------------
# RTL SIMULATION
# --------------

VLOG_ARGS += -suppress vlog-2583 -suppress vlog-13314 -suppress vlog-13233 -timescale \"1 ns / 1 ps\"
XVLOG_ARGS += -64bit -compile -vtimescale 1ns/1ns -quiet

define generate_vsim
	echo 'set ROOT [file normalize [file dirname [info script]]/$3]' > $1
	bender script $(VSIM) --vlog-arg="$(VLOG_ARGS)" $2 | grep -v "set ROOT" >> $1
	echo >> $1
endef

sim_all: scripts/compile.tcl
sim_all: models/generic_delay_D4_O1_3P750_CG0.behav.sv

sim_clean:
	rm -rf scripts/compile.tcl
	rm -rf work

models/s27ks0641:
	git clone git@iis-git.ee.ethz.ch:carfield/hyp_vip.git $@

scripts/compile.tcl: Bender.yml
	$(call generate_vsim, $@, -t rtl -t test -t hyper_test,..)

build:
	$(VSIM) -c -do "source scripts/compile.tcl; exit"

run:
	$(VSIM) $(VSIM_ARGS) "source scripts/start.tcl"
