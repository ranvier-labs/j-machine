// Verilator's generated timing shim expects this legacy callback even though
// these cycle-driven runners do not use timestamped delays.
double sc_time_stamp() { return 0.0; }
