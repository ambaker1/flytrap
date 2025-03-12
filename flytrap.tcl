# flytrap.tcl
################################################################################
# Debugging and dev tools for Tcl

# Copyright (C) 2023 Alex Baker, ambaker1@mtu.edu
# All rights reserved. 

# See the file "LICENSE" in the top level directory for information on usage, 
# redistribution, and for a DISCLAIMER OF ALL WARRANTIES.
################################################################################

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
    variable userInput; # for mainLoop
    variable userInputComplete; # for mainLoop
    variable interactive 0; # Whether main loop is active

    # Exported commands
    namespace export mainLoop; # Enter event loop, with user input
    namespace export exitMainLoop; # Exit main loop programmatically
    namespace export widget; # Widget class
    namespace export closeAllWidgets; # Close all widgets
    namespace export pause; # Enter interactive mode in current level.
    namespace export flytrap; # Catch bugs in a Tcl script.
    namespace export printVars; # Print variables to screen.
    namespace export viewVars; # View all variables in current level.
    namespace export varViewer; # Widget class for viewing variables.
}

# mainLoop --
#
# Enter the Tcl/Tk event loop, with an interactive command line.
# Values or codes can be returned to caller with "return", or "exitMainLoop"
#
# Syntax:
# mainLoop <$onBlank>
# 
# Arguments:
# onBlank:      Default "continue" ignores blank lines. "break" exits event loop

proc ::flytrap::mainLoop {{onBlank continue}} {
    variable userInput
    variable userInputComplete
    variable interactive
    # Validate input
    if {$onBlank ni {continue break}} {
        return -code error "wrong option: want \"continue\" or \"break\""
    }
    # Enter interactive mainLoop
    set oldFileEvent [fileevent stdin readable]; # Save old file event
    set oldInteractive $interactive; # Save old "interactive" status
    fileevent stdin readable ::flytrap::GetUserInput; # File event for user input
    set interactive 1
    while {1} {
        # Initialize
        set userInput ""
        set userInputComplete 0
        puts -nonewline "> "
        flush stdout; # For normal Tcl
        # Wait for user input
        vwait ::flytrap::userInputComplete
        if {$userInputComplete == 1} {
            # User input
            set code [catch {uplevel 1 $userInput} result options]
        }
        if {$userInputComplete == -1} {
            # "exitMainLoop" called (interactive or scripted)
            set code [catch {uplevel 1 $userInput} result options]
        }
        # Evaluate user input, but catch for error or other return codes
        switch $code {
            0 { # Success. 
                if {[string trim $userInput] eq ""} {$onBlank}
                if {$result ne ""} {puts $result}
            }
            1 { # Error. Print the error message, do not pass error
                puts [dict get $options -errorinfo]
            }
            2 { # Return, return to caller
                # Lower the level of a return code (to account for this level)
                if {[dict get $options -code] == 2} {
                    dict incr options -level -1
                }
                break
            }
            3 { # Break, throw warning
                puts "invoked \"break\" outside of a loop"
            }
            4 { # Continue, throw warning
                puts "invoked \"continue\" outside of a loop"
            }
        }
    }
    # Exit interactive mainLoop
    fileevent stdin readable $oldFileEvent; # Restore old file event
    set interactive $oldInteractive
    # Return user specified code and result
    return -options $options $result
}

# GetUserInput --
#
# File-event on stdin to get user input. Uses userInputComplete for vwait

proc ::flytrap::GetUserInput {} {
    variable userInput
    variable userInputComplete
    # Get user input
    append userInput "[gets stdin]\n"
    if {[info complete $userInput]} {
        set userInputComplete 1
    }
    return
}

# exitMainLoop --
# 
# Used to programmatically return from mainLoop without going through stdin
#
# Syntax:
# exitMainLoop <$arg ...>
#
# Arguments:
# arg ...       Arguments to append to "return"

proc ::flytrap::exitMainLoop {args} {
    variable userInput [list return {*}$args]
    variable userInputComplete
    if {$userInputComplete == 0} {
        # For programmatically exiting
        puts $userInput
    }
    set userInputComplete -1; # Trigger exit
    return
}

# widget --
# 
# TclOO object used for creating GUIs within their own Tcl interpreter.
# Useful for testing out/debugging Tk applications
#
# Syntax:
# widget new <$title>
#
# Arguments:
# title:        Window title for widget. Default "Widget"

oo::class create ::flytrap::widget {
# Make $interp available in all methods
variable interp

# Define constructor (load Tk, setup widget)
# Arguments:
# title:        Title for window. Default Widget.
constructor {{title Widget}} {
    # Create unique interpreter
    set interp [interp create]
    # Create widget window
    $interp eval {package require Tk}
    $interp eval [list wm title . $title]
    # Configure "exit" to destroy the widget
    # This modified "exit" command does not have the option for return code.
    $interp alias exit [self] destroy
    # Bind window "Destroy" event to call exit alias
    $interp eval {
        bind . <Destroy> {
            if {"%W" == [winfo toplevel %W]} {
                exit
            }
        }
    }
    return
}

# Bind destruction of object to deletion of interpreter
destructor {
    if {[interp exists $interp]} {
        interp cancel -unwind $interp
        interp delete $interp
    }
}

# Basic methods
################################################################################

# eval --
# 
# Evaluate code in the widget interpreter, and handle window closing error
#
# Syntax:
# $widget eval $arg ...
#
# Arguments:
# widget        Widget object name
# $arg ...      Code to evaluate in widget interpreter.

method eval {args} {
    set code [catch {$interp eval {*}$args} result options]
    # Handle case where user closed window (return nothing)
    if {$code == 1} {
        set errorCode [lrange [dict get $options -errorcode] 0 end-1]
        if {$errorCode eq {TCL CANCEL IUNWIND}} {
            return
        }
    }
    # Normally, just return the result of eval
    return {*}$options $result
}

# alias --
#
# Create an alias command in the widget interpreter to interface with the
# main Tcl interpreter.
#
# Syntax:
# $widget alias $srcCmd $targetCmd <$arg ...>
#
# Arguments:
# widget        Widget object name
# srcCmd        Command in source interpreter
# targetCmd     Command in widget interpreter
# arg ...       Additional arguments to prepend to $targetCmd

method alias {srcCmd targetCmd args} {
    $interp alias $srcCmd $targetCmd {*}$args
}

# upvar --
#
# Link a variable in the parent interpreter to one in the child interpreter
# Initializes srcVar (and myVar) as blank if it does not exist.
#
# Syntax:
# $widget upvar $srcVar $myVar <$srcVar $myVar ...>
#
# Arguments:
# widget        Widget object name
# srcVar        Variable in source interpreter (must be scalar or array element)
# myVar         Variable in widget interpreter (must be scalar or array element)

method upvar {srcVar myVar args} {
    # Check arity
    if {[llength $args] % 2 == 1} {
        return -code error "wrong # args: should be\
                \"widget upvar srcVar myVar ?srcVar myVar ...?\"" 
    }
    upvar 1 $srcVar var
    # Ensure that srcVar is scalar (or array element)
    if {![info exists var]} {
        set var ""; 
    } elseif {[array exists var]} {
        return -code error "srcVar cannot be array"
    }
    # Ensure that myVar is not array (throw error if the case)
    if {[my eval [list info exists $myVar]]} {
        if {[my eval [list array exists $myVar]]} {
            return -code error "myVar cannot be array"
        }
    }
    # Initialize targetVar and traces that link the variable to the widget
    my set $myVar $var
    ::flytrap::Unlink var [self] $myVar; # Prevent duplicate traces
    trace add variable var read [list ::flytrap::ReadTrace [self] $myVar]
    trace add variable var write [list ::flytrap::WriteTrace [self] $myVar]
    trace add variable var unset [list ::flytrap::UnsetTrace [self] $myVar]
    # Tail recursion
    if {[llength $args] > 0} {
        tailcall my upvar {*}$args
    }
    return
}

# interp --
#
# Get the interpreter name (for advanced introspection)
#
# Syntax:
# $widget interp
#
# Arguments:
# widget        Widget object name

method interp {} {
    return $interp
}

# Short-hand variable access methods
################################################################################

# set --
# 
# Set the value of a variable in a widget
#
# Syntax:
# $widget set $varName $value
#
# Arguments:
# widget        Widget object name
# varName       Variable name in widget interpreter
# value         Value to set

method set {varName value} {
    my eval [list set $varName $value]
}

# $widget get --
# 
# Get the value of a variable in a widget
#
# Syntax:
# $widget set $varName $value
#
# Arguments:
# widget        Widget object name
# varName       Variable name in widget interpreter
# value         Value to set

method get {varName} {
    my eval [list set $varName]
}

}; # end of class definition

# Private procs for upvar method variable traces

# Unlink --
#
# Unlinks srcVar and targetVar from a widget
#
# Syntax:
# Unlink $srcVar $widget $targetVar
#
# Arguments:
# srcVar        Variable in source interpreter (must be scalar or array element)
# widget        Widget object name
# targetVar     Variable in widget interpreter (must be scalar or array element)

proc ::flytrap::Unlink {srcVar widget targetVar} {
    upvar 1 $srcVar var
    trace remove variable var read [list ::flytrap::ReadTrace $widget $targetVar]
    trace remove variable var write [list ::flytrap::WriteTrace $widget $targetVar]
    trace remove variable var unset [list ::flytrap::UnsetTrace $widget $targetVar]
}

# WriteTrace --
#
# Variable trace on variable in parent interpreter that also sets corresponding
# variable in the widget interpreter on write.
#
# Syntax:
# WriteTrace $widget $targetVar $name1 $name2
#
# Arguments:
# widget        Widget object name
# targetVar     Variable name in widget interpreter
# name1         Variable name in parent interpreter
# name2         Array key name if name1 is array.

proc ::flytrap::WriteTrace {widget targetVar name1 name2 args} {
    upvar 1 $name1 var
    # Unlink variable if $widget no longer exists.
    if {![info object isa object $widget]} {
        if {[array exists var]} {
            Unlink var($name2) $widget $targetVar
        } else {
            Unlink var $widget $targetVar
        }
        return
    }
    if {[array exists var]} {
        $widget set $targetVar $var($name2)
    } else {
        $widget set $targetVar $var
    }
}

# ReadTrace --
# 
# Variable trace on variable in parent interpreter that retrieves value from
# corresponding variable in the widget interpreter on read.
#
# Syntax:
# ReadTrace $widget $targetVar $name1 $name2
#
# Arguments:
# widget        Widget object name
# targetVar     Variable name in widget interpreter
# name1         Variable name in parent interpreter
# name2         Array key name if name1 is array.

proc ::flytrap::ReadTrace {widget targetVar name1 name2 args} {
    upvar 1 $name1 var
    # Unlink variable if $widget no longer exists.
    if {![info object isa object $widget]} {
        if {[array exists var]} {
            Unlink var($name2) $widget $targetVar
        } else {
            Unlink var $widget $targetVar
        }
        return
    }
    # Unset the srcVar if the targetVar was unset.
    if {![$widget eval [list info exists $targetVar]]} {
        if {[array exists var]} {
            unset var($name2)
        } else {
            unset var
        }
        return
    }
    # Set the srcVar to the current value of the targetVar
    if {[array exists var]} {
        set var($name2) [$widget get $targetVar]
    } else {
        set var [$widget get $targetVar]
    }
}

# UnsetTrace --
# 
# Variable trace on variable in parent interpreter that unsets the corresponding
# variable in the widget interpreter on unset.
#
# Syntax:
# UnsetTrace $widget $targetVar
#
# Arguments:
# widget        Widget object name
# targetVar     Variable name in widget interpreter

proc ::flytrap::UnsetTrace {widget targetVar args} {
    $widget eval [list unset $targetVar]
}

# closeAllWidgets --
#
# Close all widgets

proc ::flytrap::closeAllWidgets {} {
    foreach widget [info class instances ::flytrap::widget] {
        $widget destroy
    }
    return
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
    puts "PAUSED..."
    if {$INFO ne ""} {
        puts "($INFO)"
    }
    uplevel 1 {::flytrap::mainLoop break}
}

# GetLineInfo --
#
# Private procedure used by both pause and flytrap to get frame info to display.
#
# Syntax:
# GetLineInfo $maxFrame
#
# Arguments:
# maxFrame     Maximum frame (absolute reference)

proc ::flytrap::GetLineInfo {maxFrame} {
    set evalLines 0
    set lineInfo ""
    # Step through frames, up to top-level
    for {set frame $maxFrame} {$frame > 0} {incr frame -1} {
        # Get frame dictionary
        set frameInfo [info frame $frame]
        
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
            # Called within interactive "mainLoop"
            if {[dict get $frameInfo proc] eq "::flytrap::mainLoop"} {
                if {$::flytrap::interactive} {
                    break
                }
            }
        }
        
        # Skip precompiled code
        if {[dict get $frameInfo type] eq "precompiled"} {
            continue
        }
        
        # Skip if "eval" frame when eval was already found
        if {[dict get $frameInfo type] eq "eval" && $evalLines > 0} {
            continue
        }
            
        # Get line and initialize lineInfo dictionary
        set lineInfo ""
        dict set lineInfo line [dict get $frameInfo line]
        if {$evalLines > 1} {
            dict incr lineInfo line $evalLines
            dict incr lineInfo line -1
        }
        # Switch for frame type
        switch [dict get $frameInfo type] {
            source { # Frame is a source frame
                dict set lineInfo file "\"[dict get $frameInfo file]\""
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
                # Break if no file frame is found above.
                if {[dict exists [GetLineInfo [expr {$frame - 1}]] file]} {
                    break
                }
                # Prefer proc over eval
                set evalLines 1
            }
            eval { # Frame is a command evaluation. 
                set evalLines [dict get $frameInfo line]
            }
        }
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
# flytrap <-depth $depth> <-verbose $verbose> (-file $filename |<-body> $body)
#
# Arguments:
# depth         Debug depth. Default 0. Steps into procedures if > 0
# verbose       To print out commands and intermediate steps. Default 0
# body          Body to evaluate.
# filename      File to source.

proc ::flytrap::flytrap {args} {
    variable DEBUG
    variable INFO ""
    variable baseLevel [info level]
    variable maxDepth 0; # Default
    variable minFrame [expr {[info frame] + 3}]
    variable verboseFlag 0; # Default
    variable errorStack ""
    variable stepHistory ""
    
    # Check arity
    if {[llength $args]%2} {
        set args [linsert $args end-1 -body]; # Default -body option
    }
    if {[llength $args] == 0} {
        return -code error "wrong # args: should be\
                \"flytrap ?option value ...? (-file filename | ?-body? body)\""
    }
    
    # Interpret input
    set input [lindex $args end]
    set type  [lindex $args end-1]
    switch $type {
        -body {
            set body $input
        }
        -file { # Validate file input
            set filename $input
            if {![file isfile $filename]} {
                return -code error "\"$filename\" is not a file"
            }
            set body [list source $filename]
        }
        default {
            return -code error "unknown option \"\$type\". want -body or -file"
        }
    }
    
    # Interpret options
    foreach {option value} [lrange $args 0 end-2] {
        switch $option {
            -depth { # Maximum depth to step into procedures
                if {![string is integer -strict $value] || $value < 0} {
                    return -code error "-depth must be integer >= 0"
                }
                set maxDepth $value
            }
            -verbose { # Whether to print out steps even if no error
                if {![string is boolean -strict $value]} {
                    return -code error "-verbose must be boolean"
                }
                set verboseFlag $value
            }
            default {
                return -code error "unknown option \"\$option\":\
                        want -depth or -verbose"
            }
        }
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
        puts "ERROR..."
        if {$INFO ne ""} {
            puts "($INFO)"
        }
        uplevel 1 {::flytrap::mainLoop break}
    }
    # Remove traces, which then unwinds the interpreter
    trace remove execution Eval enterstep ::flytrap::EnterStep
    trace remove execution Eval leavestep ::flytrap::LeaveStep

    return
}

# printVars --
#
# Same idea as parray. Prints the values of variables to screen.
#
# Syntax:
# printVars $varName ...
#
# Arguments:
# $varName ...      Names of variable to print

proc ::flytrap::printVars {args} {
    puts [uplevel 1 [list ::flytrap::PrintVars {*}$args]]
}

# PrintVars --
#
# Private procedure for testing (returns what is printed with "printVars")

proc ::flytrap::PrintVars {args} {
    foreach varName $args {
        upvar 1 $varName var
        if {![info exists var]} {
            return -code error "can't read \"$varName\": no such variable"
        } elseif {[array exists var]} {
            foreach {key value} [array get var] {
                lappend varList [list "$varName\($key\)" = $value]
            }
        } else {
            lappend varList [list $varName = $var]
        }
    }
    join $varList \n
}

# viewVars --
#
# View all variables in the current scope and enter interactive mode
#
# Syntax:
# viewVars

proc ::flytrap::viewVars {} {
    set varList [uplevel 1 {info vars}]
    set widget [uplevel 1 [list ::flytrap::varViewer new $varList]]
    uplevel 1 {::flytrap::mainLoop break}
    $widget destroy
    return
}

# varViewer --
#
# Widget class for viewing variables. Requires package Tktable.
# Can be used as a framework for monitoring variables.
#
# Syntax:
# varViewer new $varList <$title>
# varViewer create $name $varList <$title>
#
# Arguments:
# name          Widget object name
# varList       Variables to view
# title         Title. Default "Workspace"

::oo::class create ::flytrap::varViewer {
    superclass ::flytrap::widget
    constructor {varList {title Workspace}} {
        next $title; # Initialize widget
        my eval {package require Tktable}
        
        # Initialize cells with headers
        my set cells(0,0) "Variable"
        my set cells(0,1) "Value"
        
        # Fill with sorted variables and values
        set i 1
        foreach varName $varList {
            upvar 1 $varName var
            if {![info exists var]} {
                return -code error "$varName does not exist"
            }
            if {[array exists var]} {
                # Array case
                foreach key [lsort [array names var]] {
                    my set cells($i,0) ${varName}($key)
                    my upvar var($key) cells($i,1)
                    incr i
                }
            } else {
                # Scalar case
                my set cells($i,0) $varName
                my upvar var cells($i,1)
                incr i
            }
        }
        
        # Create variable viewer widget
        my eval {
            # Create frame, scroll bar, and button
            frame .f -bd 2 -relief groove
            scrollbar .f.sbar -command {.f.tbl yview}
            
            # Create table
            table .f.tbl -rows [expr {[array size cells]/2}] -cols 2 
            .f.tbl configure -yscrollcommand {.f.sbar set}
            .f.tbl configure -titlerows 1 -titlecols 1 -height 10 -width 2
            .f.tbl configure -anchor nw -multiline 0 -ellipsis "..."
            .f.tbl configure -rowseparator " " -colseparator "\n"
            .f.tbl configure -selectmode single -invertselected 1 
            .f.tbl configure -variable cells -state disabled
            .f.tbl configure -rowstretchmode all; # stretches all rows
            .f.tbl configure -colstretchmode unset; # only stretches value col
            .f.tbl tag configure active -fg black
            .f.tbl height 0 1; # Height of title row 
            .f.tbl width 0 25 1 50; # Width of var and val columns

            # Arrange widget
            grid .f -column 0 -row 0 -columnspan 2 -rowspan 2 -sticky nsew
            grid .f.tbl -column 0 -row 1 -columnspan 1 -rowspan 1 -sticky nsew
            grid .f.sbar -column 1 -row 1 -columnspan 1 -rowspan 1 -sticky ns
            grid columnconfigure . all -weight 1
            grid rowconfigure . all -weight 1
            grid columnconfigure .f .f.tbl -weight 1
            grid rowconfigure .f .f.tbl -weight 1
        }
    }
}

# Finally, provide the package
package provide flytrap 1.2
