package require tin 0.6
set config [dict create VERSION 0.1.3]
tin bake src build $config

set dir build
source build/pkgIndex.tcl
tin import flytrap
set ::flytrap::DEBUG 1;# For testing
set myLocation [file normalize [info script]]

# "pause" tests
################################################################################
assert [pause] eq "line 13 file \"$myLocation\""
# Pause within proc
proc foo {bar} {
    global myLocation
    puts $bar
    assert [pause] eq "line 18 file \"$myLocation\""
}
foo foo

# Pause within a nested proc with an eval
proc foo {bar} {
    global myLocation
    bar $bar
}
proc bar {bar} {
    puts $bar
    uplevel 1 {
        assert [pause] eq "line 30 file \"$myLocation\""
    }
}
foo foo

# Pause within proc with multiple nested evals (with escaped newlines)
proc foo {bar} {
    puts $bar
    uplevel 1 {
        eval {
            eval {
                assert [\
                        pause] eq "line 42 file \"$myLocation\""
            }
        }
    }
}
foo foo

# Pause within TclOO
# Note: constructor and destructor methods are an anomoly
oo::class create example1 {
    constructor {args} {
        assert [pause] eq "line 2 method <constructor> class ::example1"
    }
    method foo {bar} {
        global myLocation
        puts $bar
        assert [pause] eq "line 58 file \"$::myLocation\""
    }
    destructor {
        assert [pause] eq "line 2 method <destructor> class ::example1"
    }
}
set x [example1 new]
$x foo foo
$x destroy

# Flytrap tests
################################################################################

# Basic in-line error (and no error)
assert [flytrap -body {assert [expr {2 + 2}] == 4} 2 1] eq ""
assert [flytrap -body {
    assert [expr {2 + 2}] == 3
} 2 1] eq "line 74 file \"$myLocation\""

# Test error in nested procs (with eval)
proc foo {x} {
    bar $x
}
proc bar {x} {
    expr {1/$x}
}
assert [flytrap -body {foo 0} 0 0] eq "line 84 file \"$myLocation\""
assert [flytrap -body {foo 0} 1 0] eq "line 79 file \"$myLocation\""
assert [flytrap -body {foo 0} 2 0] eq "line 82 file \"$myLocation\""

# Flytrap files
set error_example [file normalize tests/error_example.tcl]
set noerror_example [file normalize tests/noerror_example.tcl]
assert [flytrap -file $error_example] eq "line 11 file \"$error_example\""
assert [flytrap -file $error_example 1] eq "line 4 file \"$error_example\""
assert [flytrap -file $error_example 2] eq "line 7 file \"$error_example\""
assert [flytrap -file $noerror_example 0 1] eq ""

# Flytrap into methods.
# Note: constructor and destructor methods are an anomoly
oo::class create example2 {
    constructor {args} {
        expr 1/0
    }
}
oo::class create example3 {
    method foo {bar} {
        expr 1/0
    }
    destructor {
        expr 1/0
    }
}
assert [flytrap -body {
    set x [example2 new]
} 1] eq "line 2 method <constructor> class ::example2"
set x [example3 new]
assert [flytrap -body {$x foo foo} 1] eq "line 105 file \"$::myLocation\""
assert [flytrap -body {$x destroy} 1] eq "line 2 method <destructor> class ::example3"

puts "TESTS PASSED."
set ::flytrap::DEBUG 0
puts "Flytrap with DEBUG off"
catch {flytrap -body {expr 1/0}}
assert $::flytrap::INFO eq "line 121 file \"$myLocation\""
puts "Pause with DEBUG off"
pause

# Print variables
set a 5
set b 7
set c(1) 5
set c(2) 6
set d(1) hello
set d(2) world
assert [::flytrap::PrintVars a b c d(1)] eq \
{a = 5
b = 7
c(1) = 5
c(2) = 6
d(1) = hello}
pvar a b c d(1); # for display

# View all variables
viewVars

# Everything ok?
puts "Update main files and install? (Y/N)"
if {[gets stdin] eq "Y"} {
    file copy -force {*}[glob -directory build *] [pwd]
    tin bake doc/template/version.tin doc/template/version.tex $config
    source install.tcl
}
