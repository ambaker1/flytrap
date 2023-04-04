set a 5
proc foo {x} {
    set b [expr {$x * 2}]
    return [bar [expr {$b - 10}]]
}
proc bar {x} {
    eval [list expr {1/[expr {$x - $x}]}]
}
pause
catch {foo $a}
foo $a
