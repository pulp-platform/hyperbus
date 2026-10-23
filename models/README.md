# Simulation Models

## HyperRAM

The proprietary S27KL0641/S27KS0641 model is not distributed here. Obtain its archive
from [Infineon](https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68&da=t)
using a vendor login and follow its license.

`make models/s27ks0641 CACHED_MODEL_PATH=DIR` extracts the Verilog and SDF from
the archive directory. Alternatively, install `s27ks0641.v` and `s27ks0641.sdf`
in `models/s27ks0641/`. `make hyper-nonfree-init` requires internal access.

## Delay Models

- `configurable_delay.behav.sv`: default wrapper uses 32 taps at 78 ps/tap plus 10 ps.
- `configurable_delay.fpga.sv`: `IBUF` fallback, without programmable delay.
  Xilinx 7-series programmable wrappers live in `target/xilinx/`, selected by
  Bender targets `xilinx` and `hyperbus_dline`.
