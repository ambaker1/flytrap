# flytrap.tcl
################################################################################
# Debugging and dev tools for Tcl

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" in the top level directory for information on usage, 
# redistribution, and for a DISCLAIMER OF ALL WARRANTIES.
################################################################################

# Required packages
package require wob 0.1

# Define namespace
namespace eval ::flytrap {
    # Internal variables
    variable DEBUG 0; # Toggle for testing flytrap
    variable INFO ""; # Line info dictionary for testing flytrap
    variable baseLevel; # Reference level (for flytrap)
    variable maxDepth; # Maximum debug depth (for flytrap)
    variable minFrame; # Minimum frame number (for flytrap)
    variable verboseFlag; # Whether debug is verbose, or only prints on error.
    variable errorStack; # Commands evaluated before error
    variable stepHistory; # History of enter and leave traces in Eval
    variable excludeList {catch try}; # Commands to ignore (for flytrap)
       
    # Exported commands
    namespace export pause; # Enter interactive mode in current level
    namespace export flytrap; # Catch bugs in a Tcl script
}

# pause --
#
# Pauses the script, states the source file and line number it is on, 
# and then enters the event loop, processing user input.
# Pressing enter continues the analysis.
# To pass results to caller, use return.
# When in DEBUG mode, does not pause, just returns INFO
#
# Syntax:
# pause

proc ::flytrap::pause {} {
    variable DEBUG
    variable INFO ""
    # Get frame info of caller
    set frame [info frame]
    set INFO [GetLineInfo [incr frame -1]]
    # If DEBUG, just return the line info (for testing)
    if {$DEBUG} {
        return $INFO
    }
    # Print pause line information and enter interactive mode
    puts "PAUSED...\n($INFO)"
    uplevel 1 [list ::wob::mainLoop break]
}

# GetLineInfo --
#
# Private procedure used by both pause and flytrap to get frame info to display.
#
# Syntax:
# GetLineInfo $max
#
# Arguments:
# max       Maximum frame (absolute reference)

proc ::flytrap::GetLineInfo {max} {
    set evalLines 0
    for {set i $max} {$i > 0} {incr i -1} {
        # Get frame dictionary
        set frameInfo [info frame $i]
        
        # Skip flytrap-specific commands
        if {[dict exists $frameInfo proc]} {
            # Main body of "Eval"
            if {[dict get $frameInfo proc] eq "::flytrap::Eval"} {
                if {[dict get $frameInfo cmd] eq {uplevel 2 $body}} {
                    continue
                }
            }
            # Call of "Eval" in "flytrap"
            if {[dict get $frameInfo proc] eq "::flytrap::flytrap"} {
                if {[dict get $frameInfo cmd] in {
                    {Eval $body} {catch {Eval $body} result options}
                }} then {
                    continue
                }
            }
        }
        
        # Skip precompiled code
        if {[dict get $frameInfo type] eq "precompiled"} {
            continue
        }
        
        # Get line and initialize lineInfo dictionary
        set line [dict get $frameInfo line]
        set lineInfo [dict create line $line]
        
        # Switch for frame type
        switch [dict get $frameInfo type] {
            source { # Frame is a source frame
                set file [dict get $frameInfo file]
                dict set lineInfo file "\"$file\""
                break
            }
            proc { # Frame is a proc frame
                if {[dict exists $frameInfo proc]} {
                    # Normal proc call
                    dict set lineInfo proc [dict get $frameInfo proc]
                } elseif {[dict exists $frameInfo method]} {
                    # TclOO method call
                    dict set lineInfo method [dict get $frameInfo method]
                    dict set lineInfo class [dict get $frameInfo class]
                    # In Tcl 8.6.10, there is no call frame for the file in 
                    # which the constructor is defined. And for the destructor,
                    # the calling file line number is -1. So simply return the
                    # line number in the constructor/destructor.
                    if {[dict get $frameInfo method] in {
                        <constructor> <destructor>
                    }} then {
                        break
                    }
                }
                set evalLines 0
            }
            eval { # Frame is a command evaluation. 
                # Only save the lowest level eval.
                if {$evalLines == 0} {
                    set cmd [dict get $frameInfo cmd]
                    dict set lineInfo cmd "\{$cmd\}"
                    set evalLines $line
                }
            }
        }
    }
    # Adjust for eval lines
    if {$evalLines != 0} {
        dict incr lineInfo line $evalLines
        dict incr lineInfo line -1
    }
    return [join $lineInfo]
}

# flytrap --
#
# Step through a script, expanding out all commands using enter/leave traces
# If verbose, prints out everything. If not, only the commands up to an error.
# When an error is encountered, it pauses there and displays the line INFO.
# When in DEBUG mode, it does not pause, just catches the error and returns INFO
# 
# Syntax:
# flytrap -file $filename <$depth> <$verbose>
# flytrap -body $script <$depth> <$verbose>
#
# Arguments:
# filename      File path of file to source (only with -file)
# script        Script to evaluate (only with -body)
# depth         Debug depth. Default 0. Steps into procedures if > 0
# verbose       To print out commands and intermediate steps. Default 0

proc ::flytrap::flytrap {type input {depth 0} {verbose 0}} {
    variable DEBUG
    variable INFO ""
    variable baseLevel [info level]
    variable maxDepth $depth
    variable minFrame [expr {[info frame] + 3}]
    variable verboseFlag $verbose
    variable errorStack ""
    variable stepHistory ""

    # Determine debugBody from debugType
    switch $type {
        -file {set body [list source $input]}
        -body {set body $input}
        default {return -code error "unknown option $type"}
    }

    # Check input
    if {![string is integer $depth] || $depth < 0} {
        return -code error "Depth must be integer >= 0"
    }

    # Evaluate command with recursive execution trace
    trace add execution Eval enterstep ::flytrap::EnterStep
    trace add execution Eval leavestep ::flytrap::LeaveStep
    catch {Eval $body} result options
    trace remove execution Eval enterstep ::flytrap::EnterStep
    trace remove execution Eval leavestep ::flytrap::LeaveStep
    # Handle debug case
    if {$DEBUG} {
        return $INFO
    }
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
    variable baseLevel
    variable maxDepth
    variable minFrame
    variable verboseFlag
    variable errorStack
    variable stepHistory
    
    # Skip if level/frame is outside range
    # Level is for variable and command scope.
    # Frame is for call stack execution
    set depth [expr {[info level] - $baseLevel}]
    set frame [info frame]
    if {$depth > $maxDepth || $frame < $minFrame} {
        return
    }
    lappend errorStack $cmdString; # push
    if {$verboseFlag} {
        set prefix [string repeat "  " $depth]
        puts "$prefix> $cmdString"
    }
    lappend stepHistory enter $depth $cmdString
    return
}

# LeaveStep --
# 
# Private procedure to print out results from intermediate steps

proc ::flytrap::LeaveStep {cmdString code result args} {
    variable DEBUG
    variable INFO
    variable baseLevel
    variable maxDepth
    variable minFrame
    variable verboseFlag
    variable errorStack
    variable stepHistory
    variable excludeList
    # Skip if level/frame is outside range
    # Level is for variable and command scope.
    # Frame is for call stack execution
    set depth [expr {[info level] - $baseLevel}]
    set frame [info frame]
    if {$depth > $maxDepth || $frame < $minFrame} {
        return
    }
    # Handle command and error stacks
    set errorStack [lreplace $errorStack end end]; # pop
    if {$verboseFlag} {
        set prefix [string repeat "  " $depth]
        if {$result ne ""} {puts "$prefix$result"}
    }
    lappend stepHistory leave $depth $result
    # If not an error, return
    if {$code != 1} {
        return
    }
    # Verify that the error is not wrapped by a built-in error handler
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

    # Print error line information and enter interactive mode
    # -1 is LeaveStep, -2 is actual code
    set INFO [GetLineInfo [expr {$frame - 2}]]
    if {!$DEBUG} {
        puts "ERROR...\n($INFO)"
        uplevel 1 [list ::wob::mainLoop break]
    }
    # Remove traces, which then unwinds the interpreter
    trace remove execution Eval enterstep ::flytrap::EnterStep
    trace remove execution Eval leavestep ::flytrap::LeaveStep

    return
}

# Finally, provide the package
package provide flytrap 0.2
