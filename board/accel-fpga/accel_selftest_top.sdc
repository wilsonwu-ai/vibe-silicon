# Without this, the Timing Analyzer defaults to `derive_clocks -period 1.0`
# (i.e. checks the design against a fictitious 1 GHz clock) and reports
# unmet timing that has nothing to do with reality -- CLOCK_50 is 50 MHz.
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty
