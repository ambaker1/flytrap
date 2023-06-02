package require tin 0.6
set config [dict create VERSION 0.1.3]
tin bake src build $config

set dir build
source build/pkgIndex.tcl
tin import flytrap
tin import errmsg; # For assert
set ::flytrap::DEBUG 1
source tests/pause.test
source tests/flytrap.test
interp debug {} -frame 1
source tests/pause.test
source tests/flytrap.test

puts "ALL TESTS PASSED!"

# Everything ok?
set ::flytrap::DEBUG 0
puts "Press Enter to Update Main Files and Install"
pause
assert ::flytrap::INFO eq "line 21 file \"[file normalize [info script]]\""

# Copy files over to main folder and install.
file copy -force {*}[glob -directory build *] [pwd]
tin bake doc/template/version.tin doc/template/version.tex $config
source install.tcl

