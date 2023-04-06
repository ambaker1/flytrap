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
    variable debugType; # source or eval. For "flytrap" and "debug"
    variable debugBody; # Command passed to internal Eval command
    variable maxDepth; # Maximum debug depth
    variable verboseFlag; # Whether debug is verbose, or only prints on error.
    variable baseLevel; # Level at which the debug command was called
    variable stepHistory; # History of enter and leave traces in Eval
    variable errorStack; # Commands evaluated before error
    variable excludeList {catch try}; # Commands to ignore when in debug
    variable myLocation [file normalize [info script]]; # library file path
    variable tclvars; # https://www.tcl-lang.org/man/tcl/TclCmd/tclvars.htm
    # Get list of tclvars from a child interpreter.
    set child [interp create]
    set tclvars [$child eval {info vars}]
    interp delete $child
    unset child

    # Exported commands
    namespace export flytrap; # Source file and catch any bugs
    namespace export debug; # Run script and catch any bugs
    namespace export pause; # Enter interactive mode in current level
	namespace export >; # Print command and result, similar to interactive mode
	namespace export pvar; # Print variables with their values
	namespace export assert; # Throw error if result is not expected
	namespace export viewVars; # Open an interactive variable viewer widget
    namespace export workspace; # Get list of variables in scope (minus tclvars)
}

# flytrap --
#
# Special case of "debug", but only for files

proc ::flytrap::flytrap {filename {depth 0} {verbose 0}} {
    tailcall Debug source $filename $depth $verbose
}

# debug --
#
# Step through a script, expanding out all commands using enter/leave traces
# If verbose, prints out everything. If not, only the commands up to an error.
#
# Arguments:
# body:         Code to debug
# depth:        Debug depth. Default 0. Steps into procedures if > 0
# verbose:      To print out commands and intermediate steps. Default 0

proc ::flytrap::debug {body {depth 0} {verbose 0}} {
    tailcall Debug eval $body $depth $verbose
}

# Debug --
#
# Step through a script, expanding out all commands using enter/leave traces
# If verbose, prints out everything. If not, only the commands up to an error.
#
# Arguments:
# type:         "source" or "eval"
# body:         Code to debug
# depth:        Debug depth. Default 0. Steps into procedures if > 0
# verbose:      To print out commands and intermediate steps. Default 0

proc ::flytrap::Debug {type input depth verbose} {
    variable debugType $type
    variable debugBody ""
    variable maxDepth $depth
    variable verboseFlag $verbose
    variable baseLevel [info level]
    variable stepHistory ""
    variable errorStack ""
    
    # Determine debugBody from debugType
    switch $debugType {
        source {set debugBody [list source $input]}
        eval {set debugBody $input}
        default {return -code error "unknown debug type $debugType"}
    }

    # Check input
    if {![string is integer $depth] || $depth < 0} {
        return -code error "Depth must be integer >= 0"
    }

    # Evaluate command with recursive execution trace
    trace add execution Eval enterstep ::flytrap::EnterStep
    trace add execution Eval leavestep ::flytrap::LeaveStep
    catch {Eval $debugBody} result options
    trace remove execution Eval enterstep ::flytrap::EnterStep
    trace remove execution Eval leavestep ::flytrap::LeaveStep
    # Return normally to user
    return -options $options $result
}

# Eval --
#
# Private procedure to evaluate code, while being debugged.
#
# Arguments:
# body:     Body of code to evaluate

proc ::flytrap::Eval {body} {uplevel 2 $body}

# EnterStep --
# 
# Private procedure to print out intermediate steps

proc ::flytrap::EnterStep {cmdString args} {
    variable debugType
    variable debugBody
    variable maxDepth
    variable verboseFlag
    variable baseLevel
    variable stepHistory
    variable errorStack
    set depth [expr {[info level] - $baseLevel}]
    if {$depth <= $maxDepth} {
        if {$cmdString ne [list uplevel 2 $debugBody]} {
            lappend errorStack $cmdString; # push
            if {[llength $errorStack] == 1 && $debugType eq "source"} {
                return
            }
            if {$verboseFlag} {
                set prefix [string repeat "  " $depth]
                puts "$prefix> $cmdString"
            }
            lappend stepHistory enter $depth $cmdString
        }; # end if command not main uplevel
    }; # end if valid depth
    return
}

# LeaveStep --
# 
# Private procedure to print out results from intermediate steps

proc ::flytrap::LeaveStep {cmdString code result args} {
    variable debugType
    variable debugBody
    variable maxDepth
    variable verboseFlag
    variable baseLevel
    variable stepHistory
    variable errorStack
    variable excludeList
    variable myLocation
    set depth [expr {[info level] - $baseLevel}]
    if {$depth <= $maxDepth} {
        # Handle command and error stacks
        if {$cmdString ne [list uplevel 2 $debugBody]} {
            set errorStack [lreplace $errorStack end end]; # pop
            if {$verboseFlag} {
                set prefix [string repeat "  " $depth]
                if {$result ne ""} {puts "$prefix$result"}
            }
            lappend stepHistory leave $depth $result
        }; # end if command not main uplevel
        # Process error not controlled by "catch"
        if {$code == 1} {
            # Verify that it is not wrapped by a built-in error handler
            foreach command $errorStack {
                if {[lindex $command 0] in $excludeList} {
                    return
                }
            }
            # Print command history if not verbose
            if {!$verboseFlag} {
                foreach {type depth string} $stepHistory {
                    set prefix [string repeat "  " $depth]
                    switch $type {
                        enter {puts "$prefix> $string"}
                        leave {if {$result ne ""} {puts "$prefix$string"}}
                    }
                }
            }

            # Get location of error from frame stack
            set foundError 0; # Flag for if the error was found in the stack
            set errorLine 0; # Line in file or proc where error occurred
            set evalLine 1; # Line number of outer eval in proc or file
            set prefix ""; # Prefix for puts statement
            for {set i 1} {$i < [info frame]} {incr i} {
                set frame [info frame -$i]
                if {[dict get $frame type] eq "precompiled"} {
                    continue
                }
                # Looking for "LeaveStep" frame
                if {!$foundError} {
                    if {[dict get $frame type] eq "eval"} {
                        set frameCmd [lindex [dict get $frame cmd] 0]
                        if {$frameCmd eq "::flytrap::LeaveStep"} {
                            set foundError 1
                        }
                    }
                    continue
                }
                # Looking for file frame or proc frame
                switch [dict get $frame type] {
                    source {
                        # Skip flytrap library file
                        if {[dict get $frame file] eq $myLocation} {
                            continue
                        }
                        set prefix "file \"[dict get $frame file]\" line"
                        set errorLine [dict get $frame line]
                        break
                    }
                    proc {
                        # Only applicable for interactive mode
                        set prefix "proc [dict get $frame proc] line"
                        set errorLine [dict get $frame line]
                        break
                    }
                    eval {
                        # Handle index starting at 1 for nested evals
                        incr evalLine [dict get $frame line]
                        incr evalLine -1
                    }
                }
            }
            # Adjust errorLine for any evals
            incr errorLine $evalLine
            incr errorLine -1; # index starts at 1
            
            # Print error line information
            puts "ERROR..."
            puts "($prefix $errorLine)"
            
            # Enter interactive mode, similar to "pause"
            uplevel 1 [list ::wob::mainLoop break]
            # Remove traces, which then unwinds the interpreter
            trace remove execution Eval enterstep ::flytrap::EnterStep
            trace remove execution Eval leavestep ::flytrap::LeaveStep
        }
    }; # end if valid depth
    return
}

# pause --
#
# Pauses the script, states the source file and line number it is on, 
# and then enters the event loop, processing user input.
# Pressing enter continues the analysis.
# To pass results to caller, use return.

proc ::flytrap::pause {} {
    # Get frame info of caller and throw error if 
    set frame [info frame -1]; # Get frame info of caller
    if {[dict get $frame type] ne "source"} {
        # Return if in interactive mode
        return
    }
    puts "PAUSED..."
    puts "(file \"[dict get $frame file]\" line [dict get $frame line])"
    uplevel 1 [list ::wob::mainLoop break]
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

proc ::flytrap::viewVars {args} {
    # Create widget interpreter and ensure required packages are available
    set widget [::wob::widget new "Workspace"]
    $widget eval {package require Tktable}
    
    # Initialize cells with header
    set cells(0,0) "Variable"
    set cells(0,1) "Value"
    
    # Fill with sorted variables and values
    if {[llength $args] == 0} {
        set vars [uplevel 1 ::flytrap::workspace]
    } else {
        set vars $args
    }
    set i 1
    foreach var [lsort $vars] {
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

# workspace --
#
# Get list of variables defined in current scope (minus tclvars)

proc ::flytrap::workspace {} {
    variable tclvars
    set vars [uplevel 1 {info vars}]
    # Filter out tclvars
    if {[info level] == 1} {
        foreach tclvar $tclvars {
            set i [lsearch -exact $vars $tclvar]
            set vars [lreplace $vars $i $i]
        }
    }
    return $vars
}

# Finally, provide the package
package provide flytrap 0.1
