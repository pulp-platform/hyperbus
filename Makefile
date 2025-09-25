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

sim_clean:
	rm -rf scripts/compile.tcl
	rm -rf work

# Nonfree components. As observed from July 15th, 2025, Infineon requires SSO
# authentication to get the model. For internal usage, we support fetching the
# model from a cached location, or automatically downloading it, through the
# variable `CACHED_MODEL`, default to `true`. However, open-source users must
# manually download the models with their credentials.
HYPER_NONFREE_REMOTE ?= git@iis-git.ee.ethz.ch:pulp-restricted/hyperbus-nonfree.git
HYPER_NONFREE_COMMIT ?= fba6af4

.PHONY: hyper-nonfree-init
hyper-nonfree-init:
	git clone $(HYPER_NONFREE_REMOTE) nonfree
	cd nonfree && git checkout $(HYPER_NONFREE_COMMIT)

-include nonfree/nonfree.mk
CACHED_MODEL ?= true

models/s27ks0641:
	mkdir -p $@
	rm -rf model_tmp && mkdir model_tmp
	@if [ -f "nonfree/nonfree.mk" ]; then \
		[ "$(CACHED_MODEL)" = "false" ] && $(MAKE) fetch-model; \
		cp nonfree/cached/*.zip model_tmp/; \
	else \
		echo "The model requires SSO authenatication for dowload. Download it manually from:"; \
		echo "https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68&da=t"; \
		echo "Save the .zip file into: \`model_tmp\`"; \
		read -p "Press enter once the file is placed in \`model_tmp\`..."; \
	fi
	mv model_tmp/*.zip model_tmp/model.zip; \
	cd model_tmp; unzip -q model.zip
	cd model_tmp; mv 'S27KL0641 S27KS0641' exe_folder
	cd model_tmp/exe_folder; unzip S27ks0641.exe
	cp model_tmp/exe_folder/S27ks0641/model/s27ks0641.v $@
	cp model_tmp/exe_folder/S27ks0641/model/s27ks0641_verilog.sdf models/s27ks0641/s27ks0641.sdf
	rm -rf model_tmp

scripts/compile.tcl: Bender.yml models/s27ks0641
	$(call generate_vsim, $@, -t rtl -t test -t hyper_test,..)

build: scripts/compile.tcl
	$(VSIM) -c -do "source scripts/compile.tcl; exit"

run: clean build
	$(VSIM) $(VSIM_ARGS) "source scripts/start.tcl"
