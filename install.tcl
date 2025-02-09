package require tin 2.0
tin depend wob 1.0
set dir [tin mkdir -force flytrap 1.1]
file copy pkgIndex.tcl flytrap.tcl README.md LICENSE $dir
