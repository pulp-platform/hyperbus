# Simulation Models

This folder is just a placeholder. The verilog model of the Spansion s27ks0641 ram is proprietary code of CypressSemiconductor Corporation, which can currently be downloaded from [here](https://www.cypress.com/documentation/models/verilog/s27kl0641-s27ks0641-verilog)

Once the package has been downloaded, the following steps are necessary to integrate the model in the platform:

1. unzip it (it might be necessary to rename it 260016.zip first)
2. execute s27ks0641.exe 
3. move the newly created `s27ks0641.v` file in `models/s27ks0641/s27ks0641.v`, according to the `Bender.yml`

## Vendor Specific Peripherals

- `s27ks0641`: Cypress, HyperBus pseudo SRAM model/self-refresh DRAM (8/16 MByte)

## Generic Delay

- `generic_delay_D4_O1_3P750_CG0.behav.sv`: Delay macro with 4-bit delay control, 1 output, 3.75 ns total delay, no clock gate
