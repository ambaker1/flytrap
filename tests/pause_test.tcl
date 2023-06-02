set myLocation [file normalize [info script]]
assert [pause] eq "line 2 file \"$myLocation\""
# Pause within proc
proc foo {bar} {
    global myLocation
    puts $bar
    assert [pause] eq "line 7 file \"$myLocation\""
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
        assert [pause] eq "line 19 file \"$myLocation\""
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
                        pause] eq "line 31 file \"$myLocation\""
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
        assert [pause] eq "line 47 file \"$::myLocation\""
    }
    destructor {
        assert [pause] eq "line 2 method <destructor> class ::example1"
    }
}
set x [example1 new]
$x foo foo
$x destroy

assert [pause] eq "line 57 file \"$myLocation\""

example1 destroy
