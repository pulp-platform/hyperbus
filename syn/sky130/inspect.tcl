# OpenROAD script: load the yosys sky130 netlist, do a minimal
# floorplan + placement, and open the GUI to inspect the core.
#   openroad -gui syn/sky130/inspect.tcl
# (A gate-level netlist has no physical data; we place it so there is
#  something to view. Adjust die/core size or density as needed.)

set pdk [lindex [glob $env(HOME)/.volare/volare/sky130/versions/*/sky130A/libs.ref/sky130_fd_sc_hd] 0]

read_lef     $pdk/techlef/sky130_fd_sc_hd__nom.tlef
read_lef     $pdk/lef/sky130_fd_sc_hd.lef
read_liberty $pdk/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

read_verilog [file dirname [info script]]/out/hyperbus_phy_sky130.netlist.v
link_design  hyperbus_phy_sky130

# ~60x60 um die, 50x50 um core (~50% utilisation for ~1250 um2 of cells)
initialize_floorplan -die_area {0 0 60 60} -core_area {5 5 55 55} -site unithd
make_tracks

place_pins -hor_layers met3 -ver_layers met2
global_placement -density 0.60
detailed_placement

# In -gui mode OpenROAD drops into the GUI here. Headless? add: exit
