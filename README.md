# flytrap
Debugging tools for Tcl

Walk through execution of Tcl code, pause your Tcl script and enter interactive mode, and other debugging and development tools. build unit tests.

Full documentation [here](doc/flytrap.pdf).
 
## Installation
This package is a Tin package. Tin makes installing Tcl packages easy, and is available [here](https://github.com/ambaker1/Tin).

After installing Tin, either download the latest release and run "pkgInstall.tcl", or simply run the following Tcl code to install flytrap:
```tcl
package require tin
tin add flytrap https://github.com/ambaker1/flytrap
tin install flytrap
```
