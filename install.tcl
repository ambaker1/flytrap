package require tin 0.4.1
tin depend wob 0.2.4
set dir [tin mkdir -force flytrap 0.2]
file copy pkgIndex.tcl flytrap.tcl README.md LICENSE $dir
