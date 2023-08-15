# Define version numbers
set version 1.0
set tin_version 0.8
set wob_version 1.0

# Source required packages for testing
package require tin $tin_version
tin import tcltest
tin import assert from tin

# Define configuration and bake the source files
set config ""
dict set config VERSION $version
dict set config WOB_REQ $wob_version
dict set config TIN_REQ $tin_version
tin bake src build $config

# Load the package
set dir build
source build/pkgIndex.tcl
tin import flytrap

# Perform tests
set ::flytrap::DEBUG 1
source tests/pause_test.tcl
source tests/flytrap_test.tcl
interp debug {} -frame 1
source tests/pause_test.tcl
source tests/flytrap_test.tcl

# Test printVars 
test printVars {
    # Test to make sure that the mechanism behind printVars works
} -body {
    set a 5
    set b 7
    set c(1) 5
    set c(2) 6
    set d(1) hello
    set d(2) world
    ::flytrap::PrintVars a b c d(1)
} -result {a = 5
b = 7
c(1) = 5
c(2) = 6
d(1) = hello}

printVars a b c d(1); # for display
unset a b c d

# Test the viewVars widget and the interactive behavior of pause and flytrap
source tests/viewVars_test.tcl
source tests/interactive_test.tcl

# Check number of failed tests
set nFailed $::tcltest::numTests(Failed)

# Clean up and report on tests
cleanupTests

# If tests failed, return error
if {$nFailed > 0} {
    error "$nFailed tests failed"
}

# Interactive test (make sure it looks right)
puts "ALL TESTS PASSED!"
puts "Press Enter to Update Main Files and Install"
set ::flytrap::DEBUG 0
viewVars

# Copy files over to main folder and install.
file copy -force {*}[glob -directory build *] [pwd]
tin bake doc/template/version.tin doc/template/version.tex $config
source install.tcl

# Verify installation
tin forget flytrap
tin clear
tin import flytrap -exact $version

exit
