set myLocation [file normalize [info script]]
# Basic in-line error (and no error)
assert [flytrap -body {expr {2 + 2}}] eq ""
assert [flytrap -body {
    expr {2 + 2/0}
}] eq "line 5 file \"$myLocation\""

# Test error in nested procs (with eval)
proc foo {x} {
    bar $x
}
proc bar {x} {
    expr {1/$x}
}
assert [flytrap -body {foo 0} 0 0] eq "line 15 file \"$myLocation\""
assert [flytrap -body {foo 0} 1 0] eq "line 10 file \"$myLocation\""
assert [flytrap -body {foo 0} 2 0] eq "line 13 file \"$myLocation\""

# Flytrap files
set error_example [file normalize tests/error_example.tcl]
set noerror_example [file normalize tests/noerror_example.tcl]
assert [flytrap -file $error_example] eq "line 11 file \"$error_example\""
assert [flytrap -file $error_example 1] eq "line 4 file \"$error_example\""
assert [flytrap -file $error_example 2] eq "line 8 file \"$error_example\""
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
assert [flytrap -body {$x foo foo} 1] eq "line 36 file \"$::myLocation\""
assert [flytrap -body {$x destroy} 1] eq "line 2 method <destructor> class ::example3"

example2 destroy
example3 destroy