# flytrap.tcl
################################################################################
# Debugging and dev tools for Tcl

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" in the top level directory for information on usage, 
# redistribution, and for a DISCLAIMER OF ALL WARRANTIES.
################################################################################

package require wob 0.1

# Define namespace
namespace eval ::flytrap {
    # Internal variables
    variable baseLevel; # Level at which the debug command was called
    variable maxDepth; # Maximum debug depth
    variable debugBody; # Command passed to internal Debug command
    variable stack; # Stack of evaluation in debug
    variable verboseFlag; # Whether debug is verbose, or only prints on error.
    variable errorFile; # File that the error occurred on in "debug"
    variable errorLine; # Line that the error occurred on in "debug"
    variable errorFlag; # Whether error has been reached in "debug"

    # Exported commands
	namespace export >; # Print command and result, similar to interactive mode
	namespace export debug; # Run script line-by-line, printing out results
	namespace export pause; # Show file and line and enter interactive mode
	namespace export pvar; # Print variables with their values
	namespace export assert; # Throw error if result is not expected
	namespace export viewVars; # Open a variable viewer
}

# > --
#
# Print out substituted command and result, similar to interactive mode.
# 
# Arguments:
# args:         Command string

proc ::flytrap::> {args} {
    puts "> $args"; # Display fully substituted command
    set result [uplevel 1 $args]; # Evaluate in caller
    puts $result; # Display results
    return $result
}

# debug --
#
# Step through a script, expanding out all commands using enter/leave traces
# If verbose, prints out everything. If not, only the commands up to an error.
#
# Arguments:
# body:         Script to step through
# depth:        Debug depth. Default 0. Steps into procedures if > 0
# verbose:      To print out commands and intermediate steps. Default 0

proc ::flytrap::debug {body {depth 0} {verbose 0}} {
    variable baseLevel [info level]
    variable maxDepth $depth
    variable debugBody $body
    variable stack ""
    variable verboseFlag $verbose
    variable errorFile ""
    variable errorLine NaN
    variable errorFlag 0

    # Check input
    if {![string is integer $depth] || $depth < 0} {
        return -code error "Depth must be integer >= 0"
    }

    # Evaluate command with recursive execution trace
    set code [catch {Debug $debugBody} result options]
    if {$code != 0} {
        # Allow user to diagnose error
        if {!$verboseFlag} {
            foreach line $stack {
                lassign $line type depth string
                set prefix [string repeat "  " $depth]
                switch $type {
                    enter {puts "$prefix> $string"}
                    leave {puts "$prefix$string"}
                }
            }
        }
        set ::errorInfo $result
        set ::errorCode $code
        puts "ERROR, PAUSED..."
        puts "File: $errorFile"
        puts "Line: $errorLine"
        uplevel 1 [list ::wob::mainLoop break]
        return -options $options $result
    }
}

# Debug --
#
# Private procedure to debug each line. Traced by EnterStep and LeaveStep
#
# Arguments:
# body:         Body of code to evaluate

proc ::flytrap::Debug {body} {uplevel 2 $body}

# EnterStep --
# 
# Private procedure to print out intermediate steps

proc ::flytrap::EnterStep {cmdString args} {
    variable baseLevel
    variable maxDepth
    variable debugBody
    variable verboseFlag
    variable stack
    set depth [expr {[info level] - $baseLevel}]
    if {$depth <= $maxDepth} {
        if {$cmdString ne [list uplevel 2 $debugBody]} {
            if {$verboseFlag} {
                set prefix [string repeat "  " $depth]
                puts "$prefix> $cmdString"
            } else {
                lappend stack [list enter $depth $cmdString]
            }  
        }; # end if command not main uplevel
    }; # end if valid depth
}

# LeaveStep --
# 
# Private procedure to print out results from intermediate steps

proc ::flytrap::LeaveStep {cmdString code result args} {
    variable baseLevel
    variable maxDepth
    variable debugBody
    variable stack
    variable verboseFlag
    variable errorFile
    variable errorLine
    variable errorFlag
    if {$errorFlag} {
        return
    }
    set depth [expr {[info level] - $baseLevel}]
    if {$depth <= $maxDepth} {
        if {$cmdString ne [list uplevel 2 $debugBody]} {
            if {$verboseFlag} {
                set prefix [string repeat "  " $depth]
                puts "$prefix$result"
            } else {
                lappend stack [list leave $depth $result]
            }
        }; # end if command not main uplevel
    }; # end if valid depth
    if {$code == 1} {
        set frameInfo [info frame 1]
        set errorFile [dict get $frameInfo file]
        set errorLine [dict get $frameInfo line]
        set errorFlag 1
    }
}

# Add traces to Debug

trace add execution ::flytrap::Debug enterstep ::flytrap::EnterStep
trace add execution ::flytrap::Debug leavestep ::flytrap::LeaveStep

# pause --
#
# Pauses the script, states the source file and line number it is on, 
# and then enters the event loop, processing user input.
# Pressing enter continues the analysis.
# To pass results to caller, use return.

proc ::flytrap::pause {} {
    # Get frame info, and check for error
    set level -1
    while {1} {
        if {[catch {set frameInfo [info frame $level]}]} {
            # Cannot pause from command window
            return
        } elseif {[dict get $frameInfo type] eq "source"} {
            break
        } else {
            incr level -1
        }
    }    
    # Wait for user input, evaluate user commands.
    puts "PAUSED..."
    puts "File: [dict get $frameInfo file]"
    puts "Line: [dict get $frameInfo line]"
    uplevel 1 [list ::wob::mainLoop break]
}

# pvar --
#
# Same idea as parray. Prints the value of a variable to screen.
# If variable is array, parray will be called, with no pattern.
#
# Arguments:
# args:         Names of variable to print

proc ::flytrap::pvar {args} {
    foreach arg $args {
        upvar 1 $arg var
        if {![info exists var]} {
            return -code error "can't read \"$arg\": no such variable"
        } elseif {[array exists var]} {
            uplevel 1 [list parray $arg]
        } else {
            puts "$arg = $var"
        }
    }
    return
}

# assert --
#
# Assert type or value, throwing error if result is not expected
# 
# Arguments:
# value:        Value to compare
# op:           Operator (using mathop namespace). Default ==
# expected:     Expected value. Default true

proc ::flytrap::assert {value {op ==} {expected true}} {
    if {![::tcl::mathop::$op $value $expected]} {
        return -code error "assert \"$value $op $expected\" failed"
    }
}

# viewVars --
#
# Open a Tk table to view all variables in current scope, allowing for 
# selection and copying. Requires package Tktable and dependent packages

proc ::flytrap::viewVars {} {    
    # Create widget interpreter and ensure required packages are available
    set widget [::wob::widget new "Workspace"]
    $widget eval {package require Tktable}
    
    # Initialize cells with header
    set cells(0,0) "Variable"
    set cells(0,1) "Value"
    
    # Fill with sorted variables and values (not tclVars)
    set i 1
    foreach var [lsort [uplevel 1 info vars]] {
        if {[uplevel 1 [list array exists $var]]} {
            # Array case
            foreach key [lsort [uplevel 1 [list array names $var]]] {
                set cells($i,0) "$var\($key\)"
                set cells($i,1) [uplevel 1 [list subst "$\{$var\($key\)\}"]]
                incr i
            }
        } else {
            # Scalar case
            set cells($i,0) $var
            set cells($i,1) [uplevel 1 [list subst "$\{$var\}"]]
            incr i
        }
    }
    
    # Pass cells to widget interpreter
    $widget eval [list array set cells [array get cells]]
    
    # Create workspace widget
    $widget eval {
        # Modify the clipboard function to copy correctly from table
        trace add execution clipboard leave TrimClipBoard
        proc TrimClipBoard {cmdString args} {
            if {[lindex $cmdString 1] eq "append"} {
                set clipboard [clipboard get]
                clipboard clear
                clipboard append [join [join $clipboard]]
            }
        }

        # Create frame, scroll bar, and button
        frame .f -bd 2 -relief groove
        scrollbar .f.sbar -command {.f.tbl yview}
        
        # Create table
        table .f.tbl -rows [expr {[array size cells]/2}] -cols 2 \
                -titlerows 1 -height 10 -width 2 \
                -yscrollcommand {.f.sbar set} -invertselected 1 \
                -variable cells -state disabled -wrap 1 \
                -rowstretchmode unset -colstretchmode all
        .f.tbl tag configure active -fg black
        .f.tbl height 0 1; # Height of title row 
        .f.tbl width 0 20 1 40; # Width of var and val columns

        # Arrange widget
        grid .f -column 0 -row 0 -columnspan 2 -rowspan 1 -sticky nsew
        grid .f.tbl -column 0 -row 1 -columnspan 1 -rowspan 1 -sticky nsew
        grid .f.sbar -column 1 -row 1 -columnspan 1 -rowspan 1 -sticky ns
        grid columnconfigure . all -weight 1
        grid rowconfigure . all -weight 1
        grid columnconfigure .f .f.tbl -weight 1
        grid rowconfigure .f .f.tbl -weight 1
        # Wait for user to close widget
        vwait forever
    }
    
    return
}

# Finally, provide the package
package provide flytrap 0.1
