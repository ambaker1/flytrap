if {![package vsatisfies [package provide Tcl] 8.6]} {return}
package ifneeded flytrap 1.1 [list source [file join $dir flytrap.tcl]]
