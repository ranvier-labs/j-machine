# The shell supplies clk_main_a0 at 250 MHz. Retain an alias so later target
# timing constraints can refer to it without replacing the shell clock.
set clk_main_a0 [get_clocks -of_objects [get_ports clk_main_a0]]
