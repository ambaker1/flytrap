# flytrap
Debugging tools for Tcl

Walk through execution of Tcl code, pause your Tcl script and enter interactive mode, and other debugging and development tools. build unit tests.

Full documentation [here](doc/flytrap.pdf).
 
## Installation
This package is a Tin package. Tin makes installing Tcl packages easy, and is available [here](https://github.com/ambaker1/Tin).

After installing Tin, either download the latest release of flytrap and run "install.tcl", or simply run the following script in a Tcl interpreter:
```tcl
package require tin 0.4.2
tin add -auto flytrap https://github.com/ambaker1/flytrap install.tcl
tin install flytrap
```
