# flytrap
Debugging tools for Tcl

Full documentation [here](https://raw.githubusercontent.com/ambaker1/flytrap/main/doc/flytrap.pdf).
 
## Installation
This package is a Tin package. Tin makes installing Tcl packages easy, and is available [here](https://github.com/ambaker1/Tin).
After installing Tin, simply include the following in your script to install the package:

```tcl
package require tin 2.0
tin autoadd flytrap https://github.com/ambaker1/flytrap install.tcl 1.1-
tin import flytrap
```
