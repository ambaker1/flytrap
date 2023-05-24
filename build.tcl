package require tin 0.6
set config [dict create VERSION 0.1.2]
tin bake src build $config

set dir build
source build/pkgIndex.tcl
package require flytrap
namespace import flytrap::*

# Assert value (throws error if not correct)
flytrap -body {assert [expr {2 + 2}] == 4} 2 1

# Ensure that the line numbers are correct
assert [dict get [info frame 0] line] == 14

proc foo {x} {
    return [expr {1/$x}]
}
puts "Error should be on line 20"
catch {flytrap -body {foo 0}}
puts "Error should be on line 17"
catch {flytrap -body {foo 0} 1}

puts "Error should be on line 8 of error_example.tcl"
catch {flytrap -body {
    set a 5
    source tests/error_example.tcl
} 3}

puts "Error should be on line 11 of error_example.tcl"
catch {flytrap -file tests/error_example.tcl}
puts "Error should be on line 4 of error_example.tcl"
catch {flytrap -file tests/error_example.tcl 1}
puts "Error should be on line 8 of error_example.tcl"
catch {flytrap -file tests/error_example.tcl 2}
puts "No error, but verbose"
catch {flytrap -file tests/noerror_example.tcl 0 1}

# Pause the script
pause

# Print variables
set a 5
set b 7
set c(1) 5
set c(2) 6
pvar a b c

# View all variables
viewVars

# Everything ok?
puts "Update main files and install? (Y/N)"
set result [gets stdin]
if {$result eq "Y"} {
    file copy -force {*}[glob -directory build *] [pwd]
    tin bake doc/template/version.tin doc/template/version.tex $config
    source install.tcl
}
