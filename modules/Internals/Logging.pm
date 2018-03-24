###########################################################################
# A module for logging
#
# Copyright (C) 2015-2018 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301 USA
###########################################################################
use strict;

my (%LOG_PATH, %DEBUG_DIR);

my %ERROR_CODE = (
    # Compatible verdict
    "Compatible"=>0,
    "Success"=>0,
    # Incompatible verdict
    "Incompatible"=>1,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot compile header files
    "Cannot_Compile"=>5,
    # Header compiled with errors
    "Compile_Error"=>6,
    # Invalid input ABI dump
    "Invalid_Dump"=>7,
    # Incompatible version of ABI dump
    "Dump_Version"=>8,
    # Cannot find a module
    "Module_Error"=>9,
    # Empty intersection between
    # headers and shared objects
    "Empty_Intersection"=>10,
    # Empty set of symbols in headers
    "Empty_Set"=>11
);

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    printMsg("ERROR", $Msg);
    exit($ERROR_CODE{$Code});
}

sub getErrorCode($) {
    return $ERROR_CODE{$_[0]};
}

sub getCodeError($)
{
    my %CODE_ERROR = reverse(%ERROR_CODE);
    return $CODE_ERROR{$_[0]};
}

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($In::Opt{"Quiet"})
    { # --quiet option
        appendFile($In::Opt{"DefaultLog"}, $Msg);
    }
    else
    {
        if($Type eq "ERROR") {
            print STDERR $Msg;
        }
        else {
            print $Msg;
        }
    }
}

sub initLogging($)
{
    my $LVer = $_[0];
    
    # create log directory
    my ($LogDir, $LogFile) = ("logs/".$In::Opt{"TargetLib"}."/".$In::Desc{$LVer}{"Version"}, "log.txt");
    if(my $LogPath = $In::Desc{$LVer}{"OutputLogPath"})
    { # user-defined by -log-path option
        ($LogDir, $LogFile) = sepPath($LogPath);
    }
    if($In::Opt{"LogMode"} ne "n") {
        mkpath($LogDir);
    }
    $LOG_PATH{$LVer} = join_P(getAbsPath($LogDir), $LogFile);
    if($In::Opt{"Debug"}) {
        initDebugging($LVer);
    }
    
    resetLogging($LVer);
    resetDebugging($LVer);
}

sub initDebugging($)
{
    my $LVer = $_[0];
    
    # debug directory
    $DEBUG_DIR{$LVer} = "debug/".$In::Opt{"TargetLib"}."/".$In::Desc{$LVer}{"Version"};
}

sub getDebugDir($) {
    return $DEBUG_DIR{$_[0]};
}

sub getExtraDir($) {
    return $DEBUG_DIR{$_[0]}."/extra-info";
}

sub writeLog($$)
{
    my ($LVer, $Msg) = @_;
    if($In::Opt{"LogMode"} ne "n") {
        appendFile($LOG_PATH{$LVer}, $Msg);
    }
}

sub resetLogging($)
{
    my $LVer = $_[0];
    if($In::Opt{"LogMode"}!~/a|n/)
    { # remove old log
        unlink($LOG_PATH{$LVer});
    }
}

sub resetDebugging($)
{
    my $LVer = $_[0];
    if($In::Opt{"Debug"})
    {
        if(-d $DEBUG_DIR{$LVer})
        {
            rmtree($DEBUG_DIR{$LVer});
        }
        
        mkpath($DEBUG_DIR{$LVer});
    }
}

sub printErrorLog($)
{
    my $LVer = $_[0];
    if($In::Opt{"LogMode"} ne "n") {
        printMsg("ERROR", "see log for details:\n  ".$LOG_PATH{$LVer}."\n");
    }
}

return 1;
