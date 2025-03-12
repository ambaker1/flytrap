package require tin 2.0
set dir [tin mkdir -force flytrap 1.2]
file copy pkgIndex.tcl flytrap.tcl README.md LICENSE $dir
