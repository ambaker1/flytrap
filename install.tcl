package require tin 2.0
tin add wob 1.1 https://github.com/ambaker1/wob v1.1 install.tcl
tin depend wob 1.1
set dir [tin mkdir -force flytrap 1.1.1]
file copy pkgIndex.tcl flytrap.tcl README.md LICENSE $dir
