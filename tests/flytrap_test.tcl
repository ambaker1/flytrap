set myLocation [file normalize [info script]]
# Basic in-line error (and no error)
assert [flytrap {expr {2 + 2}}] eq ""
assert [flytrap {
    expr {2 + 2/0}
}] eq "line 5 file \"$myLocation\""

# Test error in nested procs (with eval)
proc foo {x} {
    bar $x
}
proc bar {x} {
    expr {1/$x}
}
assert [flytrap -depth 0 -verbose 0 {foo 0}] eq "line 15 file \"$myLocation\""
assert [flytrap -depth 1 -verbose 0 {foo 0}] eq "line 10 file \"$myLocation\""
assert [flytrap -depth 2 -verbose 0 {foo 0}] eq "line 13 file \"$myLocation\""

# Flytrap files
set error_example [file normalize tests/error_example.tcl]
set noerror_example [file normalize tests/noerror_example.tcl]
assert [flytrap -depth 0 -file $error_example] eq "line 11 file \"$error_example\""
assert [flytrap -depth 1 -file $error_example] eq "line 4 file \"$error_example\""
assert [flytrap -depth 2 -file $error_example] eq "line 8 file \"$error_example\""
assert [flytrap -verbose 1 -file $noerror_example] eq ""

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
assert [flytrap -depth 1 {
    set x [example2 new]
}] eq "line 2 method <constructor> class ::example2"
set x [example3 new]
assert [flytrap -depth 1 {$x foo foo}] eq "line 36 file \"$::myLocation\""
assert [flytrap -depth 1 -body {$x destroy}] eq "line 2 method <destructor> class ::example3"

example2 destroy
example3 destroy