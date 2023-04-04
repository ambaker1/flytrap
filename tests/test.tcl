package require dbug
namespace import dbug::*

# Verbose command evaluation
> set a 5
> expr {$a + 2}

# Tcl debugger
proc add {a b} {
	return [expr {$a + $b}]
}
set a 5
set b 7
debug {
	add [expr {$a*2}] $b
} 1

# Assert value (throws error if not correct)
assert [expr {2 + 2}] == 4

# Pause the script
pause