set a 4
proc foo {x} {
    set b [expr {$x * 2}]
    return [bar [expr {$b - 10}]]
}
proc bar {x} {
    eval [list expr {1/[expr {$x*2}]}]
}
foo $a

