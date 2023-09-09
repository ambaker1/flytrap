# Spoof an interactive command-line session with "value" input option of exec
exec tclsh << {
package require tin 1.0
set dir build
source build/pkgIndex.tcl
tin import flytrap
tin import assert from tin
set ::flytrap::DEBUG 1
proc foo {a b} {
    expr {$a/$b}
    pause
}
# Error within a proc
assert [flytrap -depth 1 -body {foo 5 0}] eq "line 2 proc ::foo"
# Pause within a proc
assert [foo 3 4] eq "line 3 proc ::foo"
# Pause within a pause in interactive mode (no info)
after idle {
    after idle exitMainLoop
    assert [pause] eq ""
    exitMainLoop
}
# Pause in-line
assert [pause] eq "line 1"

# Flytrap into methods.
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
assert [flytrap -depth 1 -body {
    set x [example2 new]
}] eq "line 2 method <constructor> class ::example2"
set x [example3 new]
assert [flytrap -depth 1 -body {$x foo foo}] eq "line 2 method foo class ::example3"
assert [flytrap -depth 1 -body {$x destroy}] eq "line 2 method <destructor> class ::example3"

example2 destroy
example3 destroy
}
