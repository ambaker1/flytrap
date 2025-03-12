# Define version numbers
set version 1.2
set tin_version 2.0

# Source required packages for testing
package require tin $tin_version
tin import tcltest
tin import assert from tin

# Define configuration and bake the source files
set config ""
dict set config VERSION $version
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


# Ensure that widgets are initialized properly
test widget {
    # Ensures that the "title" argument works
} -body {
    set widget [widget new foo]
    $widget eval {wm title .}
} -result {foo}
$widget destroy

# create and close widgets
test createWidgets {
    # Create widgets
} -body {
    set w1 [widget new]
    set w2 [widget new]
    set w3 [widget new]
    llength [info class instances ::flytrap::widget]
} -result {3}

test closeAllWidgets {
    # Close all widgets
} -body {
    closeAllWidgets
    llength [info class instances ::flytrap::widget]
} -result {0}

test mainLoop_scope {
    # Ensure that the mainLoop userInput is being executed in the proper scope
} -body {
    set x 0
    after idle {
        puts ""
        set ::flytrap::userInput "set x 1"
        set ::flytrap::userInputComplete 1
        after idle exitMainLoop
    }
    mainLoop
    set x
} -result {1}

test mainLoop_interactive {
    # Check the values of the variable "::flytrap::interactive"
} -body {
    global result
    set result ""
    lappend result $::flytrap::interactive
    after idle {
        global result
        lappend result $::flytrap::interactive
        after idle {
            global result
            lappend result $::flytrap::interactive
            exitMainLoop
        }
        puts "mainLoop"
        mainLoop
        lappend result $::flytrap::interactive
        exitMainLoop
    }
    mainLoop
    lappend result $::flytrap::interactive
} -result {0 1 1 1 0}

# Test out exitMainLoop
test exitMainLoop_1 {
    # Try out mainLoop and exitMainLoop
} -body {
    after idle {exitMainLoop}
    mainLoop
} -result {}

test exitMainLoop_2 {
    # Advanced applications of exitMainLoop
} -body {
    set result ""; # initialize
    # Return value
    after idle {exitMainLoop foo}
    while {1} {
        lappend result [mainLoop]
        after idle {exitMainLoop -code break}; # Return break
    }
    # Return "return"
    proc foo {} {
        mainLoop
        return
    }
    after idle {exitMainLoop -code return bar}
    lappend result [foo]
    set result
} -result {foo bar}

test widget_upvar_write_ss {
    # write variable (scalar to scalar link)
} -body {
    set widget [widget new]
    $widget upvar x x
    set x 10
    $widget get x
} -result {10}

test widget_upvar_read_ss {
    # read variable (scalar to scalar link)
} -body {
    $widget set x 5
    set x
} -result {5}

test widget_upvar_unset_ss1 {
    # unset variable (scalar to scalar link) (from parent)
} -body {
    unset x
    $widget eval info exists x
} -result {0}

test widget_upvar_unset_ss2 {
    # unset variable (scalar to scalar link) (from widget)
} -body {
    $widget upvar x x
    set x 5
    $widget eval {unset x}
    info exists x
} -result {0}

test widget_upvar_write_se {
    # write variable (scalar to array element link)
} -body {
    $widget upvar foo x(1)
    $widget upvar bar x(2)
    set foo "hello "
    set bar "world"
    $widget eval {string cat $x(1) $x(2)}
} -result {hello world}

test widget_upvar_read_se {
    # read variable (scalar to array element link)
} -body {
    $widget set x(1) "goodbye "
    $widget set x(2) "moon"
    string cat $foo $bar
} -result {goodbye moon}

test widget_upvar_unset_se_1 {
    # unset variable (scalar to array element link) (from parent)
} -body {
    unset foo bar
    set result ""
    lappend result [$widget eval info exists x(1)]
    lappend result [$widget eval info exists x(2)]
    lappend result [$widget eval info exists x]
} -result {0 0 1}

test widget_upvar_unset_se_2 {
    # unset variable (scalar to array element link) (from widget)
    # Also verify that you can use multiple inputs to upvar.
} -body {
    $widget upvar foo x(1) bar x(2)
    set foo hi 
    set bar there
    $widget eval unset x
    list [info exists foo] [info exists bar]
} -result {0 0}

test widget_upvar_write_ee {
    # write variable (array element to array element link)
} -body {
    $widget upvar x(1) x(1)
    set x(1) 5
    $widget get x(1)
} -result 5

test widget_upvar_read_ee {
    # read variable (array element to array element link)
} -body {
    $widget set x(1) 10
    set x(1)
} -result {10}

test widget_upvar_unset_ee1 {
    # unset variable (array element to array element link) (from parent)
} -body {
    unset x
    $widget eval {list [info exists x(1)] [info exists x]}
} -result {0 1}

test widget_upvar_unset_ee2 {
    # unset variable (array element to array element link) (from widget)
} -body {
    $widget upvar x(1) x(1)
    set x(1) 5
    $widget eval {unset x}
    list [info exists x(1)] [info exists x]
} -result {0 1}

test widget_upvar_write_es {
    # write variable (array element to scalar link)
} -body {
    $widget upvar x(1) y
    set x(1) 5
    set x(2) 6; # this element not linked
    $widget get y
} -result {5}

test widget_upvar_read_es {
    # read variable (array element to scalar link)
} -body {
    $widget set y 10
    array get x
} -result {1 10 2 6}

test widget_upvar_unset_es1 {
    # unset variable (array element to scalar link) (from parent)
} -body {
    unset x
    $widget eval info exists y
} -result {0}

test widget_upvar_unset_es2 {
    # unset variable (array element to scalar link) (from widget)
} -body {
    $widget upvar x(1) y
    set x(1) 5
    $widget eval {unset y}
    list [info exists x(1)] [info exists x]
} -result {0 1}

$widget destroy; # Clean up

test widget_unlink1 {
    # ensure that destroying the widget also destroys upvars
} -body {
    set a 5
    set widget [widget new]
    $widget upvar a a
    $widget destroy
    set a
} -result {5}

test widget_unlink2 {
    # ensure that destroying the widget also destroys upvars
} -body {
    set widget [widget new]
    $widget upvar a a
    $widget destroy
    set a 3
} -result {3}

test widget_unlink3 {
    # ensure that destroying the widget also destroys upvars
} -body {
    set widget [widget new]
    $widget upvar a a
    $widget destroy
    unset x
} -result {}

test widget_unlink1_e {
    # ensure that destroying the widget also destroys upvars (array element)
} -body {
    set x(1) 5
    set widget [widget new]
    $widget upvar x(1) y
    $widget destroy
    set x(1)
} -result {5}

test widget_unlink2_e {
    # ensure that destroying the widget also destroys upvars (array element)
} -body {
    set widget [widget new]
    $widget upvar x(1) y
    $widget destroy
    set x(1) 3
} -result {3}

test widget_unlink3_e {
    # ensure that destroying the widget also destroys upvars (array element)
} -body {
    set widget [widget new]
    $widget upvar x(1) y
    $widget destroy
    unset x
} -result {}

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


pause

# Verify installation
tin forget flytrap
tin clear
tin import flytrap -exact $version

exit
