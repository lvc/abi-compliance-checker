###########################################################################
# A module with functions to handle paths
#
# Copyright (C) 2017-2018 Andrey Ponomarenko's ABI Laboratory
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
use Cwd qw(realpath);

sub pathFmt(@)
{
    my $Path = shift(@_);
    my $Fmt = $In::Opt{"OS"};
    if(@_) {
        $Fmt = shift(@_);
    }
    
    $Path=~s/[\/\\]+\.?\Z//g;
    if($Fmt eq "windows")
    {
        $Path=~s/\//\\/g;
        $Path = lc($Path);
    }
    else
    { # forward slash to pass into MinGW GCC
        $Path=~s/\\/\//g;
    }
    
    $Path=~s/[\/\\]+\Z//g;
    
    return $Path;
}

sub getAbsPath($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them
    my $Path = $_[0];
    if(not isAbsPath($Path)) {
        $Path = abs_path($Path);
    }
    return pathFmt($Path);
}

sub realpath_F($)
{
    my $Path = $_[0];
    return pathFmt(realpath($Path));
}

sub classifyPath($)
{
    my $Path = $_[0];
    if($Path=~/[\*\+\(\[\|]/)
    { # pattern
        return ($Path, "Pattern");
    }
    elsif($Path=~/[\/\\]/)
    { # directory or relative path
        return (pathFmt($Path), "Path");
    }
    else {
        return ($Path, "Name");
    }
}

sub join_P($$)
{
    my $S = "/";
    if($In::Opt{"OS"} eq "windows") {
        $S = "\\";
    }
    return join($S, @_);
}

return 1;
