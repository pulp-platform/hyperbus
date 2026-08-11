# Copyright 2023 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Paul Scheffler <paulsc@iis.ee.ethz.ch>

GIT ?= git
BENDER ?= bender
VSIM ?= vsim
VSIM_BENDER ?= $(lastword $(VSIM))

all: build run

clean: sim_clean

update-regs:
	bash scripts/gen_regs.sh

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
	bender script $(VSIM_BENDER) --vlog-arg="$(VLOG_ARGS)" $2 | grep -v "set ROOT" >> $1
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
HYPER_NONFREE_COMMIT ?= 585adc653916254bb95d09172f0f1ae1f95bbc64

.PHONY: hyper-nonfree-init
hyper-nonfree-init:
	@if [ -d nonfree/.git ]; then \
		git -C nonfree remote set-url origin "$(HYPER_NONFREE_REMOTE)"; \
		if ! git -C nonfree cat-file -e "$(HYPER_NONFREE_COMMIT)^{commit}"; then \
			git -C nonfree fetch origin; \
		fi; \
	else \
		git clone "$(HYPER_NONFREE_REMOTE)" nonfree; \
	fi
	git -C nonfree checkout --detach $(HYPER_NONFREE_COMMIT)

-include nonfree/nonfree.mk
CACHED_MODEL ?= true
CACHED_MODEL_PATH ?=

MODEL_DIR := models/s27ks0641
MODEL_V := $(MODEL_DIR)/s27ks0641.v
MODEL_SDF := $(MODEL_DIR)/s27ks0641.sdf

models/s27ks0641: $(MODEL_V) $(MODEL_SDF)

$(MODEL_V):
	@set -eu; \
	tmp=model_tmp; \
	cleanup() { \
		status=$$?; \
		trap - EXIT INT TERM; \
		rm -rf "$$tmp"; \
		if [ $$status -ne 0 ]; then rm -f "$(MODEL_V)" "$(MODEL_SDF)"; fi; \
		exit $$status; \
	}; \
	trap cleanup EXIT INT TERM; \
	rm -rf "$$tmp"; \
	mkdir -p "$$tmp" "$(MODEL_DIR)"; \
	if [ -f nonfree/nonfree.mk ]; then \
		if [ "$(CACHED_MODEL)" = false ]; then $(MAKE) fetch-model; fi; \
		set -- nonfree/cached/*.zip; \
		if [ "$$#" -ne 1 ] || [ ! -f "$$1" ]; then \
			echo "Expected exactly one cached HyperRAM model archive." >&2; \
			exit 1; \
		fi; \
		cp "$$1" "$$tmp/model.zip"; \
	else \
		archive=; \
		if [ -n "$(CACHED_MODEL_PATH)" ]; then \
			set -- "$(CACHED_MODEL_PATH)"/*.zip; \
			if [ "$$#" -eq 1 ] && [ -f "$$1" ]; then archive=$$1; fi; \
		fi; \
		if [ -n "$$archive" ]; then \
			cp "$$archive" "$$tmp/model.zip"; \
		else \
			echo "The model requires SSO authentication. Download it from:"; \
			echo "https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68&da=t"; \
			echo "Save the archive into \`model_tmp\`, then press enter."; \
			read -r _; \
			set -- "$$tmp"/*.zip; \
			if [ "$$#" -ne 1 ] || [ ! -f "$$1" ]; then \
				echo "Expected exactly one HyperRAM model archive in $$tmp." >&2; \
				exit 1; \
			fi; \
			mv "$$1" "$$tmp/model.zip"; \
		fi; \
	fi; \
	(cd "$$tmp" && unzip -q model.zip); \
	mv "$$tmp/S27KL0641 S27KS0641" "$$tmp/exe_folder"; \
	(cd "$$tmp/exe_folder" && unzip -q S27ks0641.exe); \
	cp "$$tmp/exe_folder/S27ks0641/model/s27ks0641.v" "$(MODEL_V)"; \
	cp "$$tmp/exe_folder/S27ks0641/model/s27ks0641_verilog.sdf" "$(MODEL_SDF)"; \
	test -s "$(MODEL_V)"; \
	test -s "$(MODEL_SDF)"; \
	rm -rf "$$tmp"; \
	trap - EXIT INT TERM

# The Verilog model owns extraction.  Depending on it serializes parallel Make
# invocations while this rule repairs a missing SDF from the same archive.
$(MODEL_SDF): $(MODEL_V)
	@if [ ! -s "$(MODEL_SDF)" ]; then \
		rm -f "$(MODEL_V)" "$(MODEL_SDF)"; \
		$(MAKE) "$(MODEL_V)"; \
	fi
	@test -s "$(MODEL_SDF)"

scripts/compile.tcl: Bender.yml $(MODEL_V) $(MODEL_SDF)
	$(call generate_vsim, $@, -t rtl -t test -t hyper_test,..)

scripts/compile_pad_delay.tcl: Bender.yml
	$(call generate_vsim, $@, -t rtl -t test -t pad_delay_test,..)

build: scripts/compile.tcl
	$(VSIM) -c -do "source scripts/compile.tcl; exit"

run: clean build
	$(VSIM) $(VSIM_ARGS) "source scripts/start.tcl"

.PHONY: run-pad-delay-matrix
run-pad-delay-matrix:
	scripts/run_pad_delay_matrix.sh
