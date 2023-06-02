# View all local variables
proc foo {a b c} {
    set varViewer [viewVars]
    # Make sure that linked array is correct
    assert [$varViewer eval {array size cells}] == 9; # Plus one for "active" key
    assert [$varViewer get cells(0,0)] eq "Variable"
    assert [$varViewer get cells(0,1)] eq "Value"
    assert [$varViewer get cells(1,0)] eq "a"
    assert [$varViewer get cells(2,0)] eq "b"
    assert [$varViewer get cells(3,0)] eq "c"
    assert [$varViewer get cells(1,1)] == $a
    assert [$varViewer get cells(2,1)] == $b
    assert [$varViewer get cells(3,1)] == $c
    set a [expr {$a * 2}]
    unset b
    set c "hello world"
    assert [$varViewer get cells(1,1)] == $a
    assert [$varViewer eval {info exists cells(2,1)}] is false
    assert [$varViewer get cells(3,1)] == "hello world"
    $varViewer destroy
}
foo 1 2 3
