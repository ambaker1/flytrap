package require tin 0.8
tin depend wob 0.3
set dir [tin mkdir -force flytrap 0.3]
file copy pkgIndex.tcl flytrap.tcl README.md LICENSE $dir
