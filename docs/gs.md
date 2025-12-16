# Getting Started

This page walks you through cloning the repository, installing dependencies, and running your
first simulation. For integration into a larger SoC or FPGA design, see the [User Manual](um.md).

---
 
## Prerequisites
 
### Required tools
 
| Tool | Minimum version | Purpose |
|---|---|---|
| Python | ≥ 3.11 | Build scripts and utilities |
| [Bender](https://github.com/pulp-platform/bender) | ≥ 0.27.1 | Hardware IP and dependency management |
| Rust / Cargo | latest stable | To install Bender via `cargo` |
 
### Simulation-only additional requirements
 
| Tool | Notes |
|---|---|
| QuestaSim / ModelSim | Tested with QuestaSim; other simulators not validated yet |
| Proprietary device models | **see license notice below** |
 
> note "Bender"
> [Bender](https://github.com/pulp-platform/bender) is the dependency manager used across the
> PULP platform for hardware IP. It resolves transitive dependencies between SystemVerilog
> packages and generates scripts for simulation and synthesis tools.
 
---
 
## Repository Structure
 
```
hyperbus/
├── src/          # SystemVerilog RTL sources
├── test/         # Testbench top-level and directed tests
├── target/       # Target-specific setups (sim, FPGA, ASIC)
├── models/       # Device simulation models
│   └── s27ks0641/  # Infineon HyperRAM model (proprietary — downloaded on demand)
├── padframe/     # Pad-frame wrappers for physical integration
└── docs/         # MkDocs documentation sources
```
 
For a detailed description of each module inside `src/`, see [Specification → Module Breakdown](spec.md#module-breakdown).
 
---


## Installation
 
### 1. Clone the repository
 
```bash
git clone https://github.com/FondazioneChipsIT/hyperbus.git
cd hyperbus
```
 
### 2. Install Python dependencies
 
We recommend [uv](https://docs.astral.sh/uv/) or [pyenv](https://github.com/pyenv/pyenv) for fast, reproducible installs, but `pip` works too.
 
#### uv

```bash
# Create .venv/ and install all pinned dependencies
uv sync

# Activate the virtual environment
source .venv/bin/activate
```
 
#### pip
 
```bash
# (Optional) create and activate a virtual environment first
python3 -m venv .venv
source .venv/bin/activate

# Install all dependencies declared in pyproject.toml
pip install .
```
 
### 3. Fetch hardware dependencies
 
```bash
bender update
```
 
This resolves all hardware IP dependencies declared in `Bender.yml` and creates the lock file
`Bender.lock`. No network access is required after this step.
 
---
 
## Build Targets
 
Run `make <target>` from the repository root:
 
| Target | Description |
|---|---|
| `build` | Generate hardware (IPs, register files) |
| `run` | Prepare simulation scripts and fetch external device models (†) |
| `all` | Run all of the above (†) |
| `nonfree-init` | Clone internal non-free resources (CI, etc.) — **not required for normal use** |
 
!!! warning "Proprietary simulation models (†)"
    Targets marked with (†) will download the **Infineon s27ks0641 HyperRAM simulation model**
    (`models/s27ks0641/s27ks0641.v`) from its publicly accessible source.
    This model is **proprietary** and subject to Infineon's non-free license terms.
 
    By running `make run` or `make all`, you accept those terms.
    See the `Makefile` for the exact download source and license details.
 
---
 
## Running a Simulation
 
Once dependencies are installed and the model has been downloaded:
 
```bash
bender update          # if not done already
make run               # downloads proprietary models and prepares sim scripts
```
 
Then launch QuestaSim on the generated scripts:
 
```bash
# Example — adjust to your QuestaSim installation
vsim -do target/sim/start.tcl
```
 
For a full description of the testbench structure and available tests,
see the [Verification](ver.md) page.
 
---
