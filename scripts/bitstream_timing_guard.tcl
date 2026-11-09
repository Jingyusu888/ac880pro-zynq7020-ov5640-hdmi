# Fail the build rather than emit a new delivery bitstream with negative slack.
foreach mode {max min} {
 set paths [get_timing_paths -delay_type $mode -max_paths 1]
 if {[llength $paths] == 0} {error "No $mode timing path available for guard"}
 set slack [get_property SLACK $paths]
 puts "BITSTREAM_GUARD $mode slack=$slack"
 if {$slack < 0} {error "Refusing bitstream: $mode timing not met ($slack ns)"}
}
