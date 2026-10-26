# Simulation Models

The Infineon/Cypress S27KS0641 device model is proprietary and is not distributed
with this repository. Obtain the S27KL0641/S27KS0641 Verilog model archive from
[Infineon](https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68&da=t)
using your vendor login and comply with its license terms.

Pass the archive's directory to `make models/s27ks0641 CACHED_MODEL_PATH=DIR`.
The Makefile extracts both `s27ks0641.v` and its SDF into `models/s27ks0641/`.
Alternatively, populate that directory manually with the model and SDF (named
`s27ks0641.sdf`). The optional `hyper-nonfree-init` helper requires internal access.

## Vendor Specific Peripherals

- `s27ks0641`: Cypress, HyperBus pseudo SRAM model/self-refresh DRAM (8/16 MByte)

## Generic Delay

- `configurable_delay.behav.sv`: behavioral clock delay. The default
  `hyperbus_delay` wrapper selects 32 taps, modeled at 78 ps per tap plus 10 ps.
- `configurable_delay.fpga.sv`: FPGA clock-buffer (`IBUF`) fallback without a
  programmable delay. Xilinx 7-series programmable wrappers are in `target/xilinx/`
  and selected through the `xilinx` and `hyperbus_dline` Bender targets.
