package require tin 0.6
set config ""
dict set config VERSION 0.2
dict set config WOB_REQ 0.2.4
tin bake src build $config

set dir build
source build/pkgIndex.tcl
tin import flytrap
tin import assert from errmsg
set ::flytrap::DEBUG 1
source tests/pause_test.tcl
source tests/flytrap_test.tcl
interp debug {} -frame 1
source tests/pause_test.tcl
source tests/flytrap_test.tcl

# Test the viewVars widget and the interactive behavior of pause and flytrap
source tests/viewVars_test.tcl
source tests/interactive_test.tcl

# Interactive test (make sure it looks right)
puts "ALL TESTS PASSED!"
puts "Press Enter to Update Main Files and Install"
set ::flytrap::DEBUG 0
viewVars
pause

# Copy files over to main folder and install.
file copy -force {*}[glob -directory build *] [pwd]
tin bake doc/template/version.tin doc/template/version.tex $config
source install.tcl

exit
