# Logfile tests

test writeLogFile {
    # Tests opening a log file
} -body {
    set fid [open logFile.txt w]
    puts $fid "testing"
    close $fid
    openLogFile logFile.txt; # overwrites
    puts -nonewline "hello "
    puts "world"
    puts -nonewline stdout "foo "
    puts stdout "bar"
    closeLogFile
    set fid [open logFile.txt r]
    set data [read $fid]
    close $fid
    set data
} -result {hello world
foo bar
}

test appendLogFile {
    # Append to an existing log file
} -body {
    openLogFile logFile.txt -append
    puts "boo far"
    closeLogFile
    set fid [open logFile.txt r]
    set data [read $fid]
    close $fid
    set data
} -result {hello world
foo bar
boo far
}

# Clean up
file delete logFile.txt