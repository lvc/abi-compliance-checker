###########################################################################
# A module to handle XML descriptors
#
# Copyright (C) 2015-2016 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License or the GNU Lesser
# General Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# and the GNU Lesser General Public License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use strict;

sub createDesc($$)
{
    my ($Path, $LVer) = @_;
    
    if(not -e $Path) {
        return undef;
    }
    
    if(-d $Path)
    { # directory with headers files and shared objects
        return "
            <version>
                ".$In::Desc{$LVer}{"TargetVersion"}."
            </version>

            <headers>
                $Path
            </headers>

            <libs>
                $Path
            </libs>";
    }
    else
    { # files
        if($Path=~/\.(xml|desc)\Z/i)
        { # standard XML-descriptor
            return readFile($Path);
        }
        elsif(isHeaderFile($Path))
        { # header file
            $In::Opt{"CheckHeadersOnly"} = 1;
            return "
                <version>
                    ".$In::Desc{$LVer}{"TargetVersion"}."
                </version>

                <headers>
                    $Path
                </headers>

                <libs>
                </libs>";
        }
        else
        { # standard XML-descriptor
            return readFile($Path);
        }
    }
}

sub readDesc($$)
{
    my ($Content, $LVer) = @_;
    
    if(not $Content) {
        exitStatus("Error", "XML descriptor is empty");
    }
    if($Content!~/\</) {
        exitStatus("Error", "incorrect descriptor (see -d1 option)");
    }
    
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    
    my $DescRef = $In::Desc{$LVer};
    
    $DescRef->{"Version"} = parseTag(\$Content, "version");
    if(my $TV = $DescRef->{"TargetVersion"}) {
        $DescRef->{"Version"} = $TV;
    }
    elsif($DescRef->{"Version"}=="")
    {
        if($LVer==1)
        {
            $DescRef->{"Version"} = "X";
            print STDERR "WARNING: version number #1 is not set (use --v1=NUM option)\n";
        }
        else
        {
            $DescRef->{"Version"} = "Y";
            print STDERR "WARNING: version number #2 is not set (use --v2=NUM option)\n";
        }
    }
    
    if(not $DescRef->{"Version"}) {
        exitStatus("Error", "version in the XML descriptor is not specified (section \"version\")");
    }
    if($Content=~/{RELPATH}/)
    {
        if(my $RelDir = $DescRef->{"RelativeDirectory"}) {
            $Content =~ s/{RELPATH}/$RelDir/g;
        }
        else {
            exitStatus("Error", "you have not specified -relpath* option, but the XML descriptor contains {RELPATH} macro");
        }
    }
    
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "headers")))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        
        $DescRef->{"Headers"}{$Path} = keys(%{$DescRef->{"Headers"}});
    }
    if(not defined $DescRef->{"Headers"}) {
        exitStatus("Error", "can't find header files info in the XML descriptor");
    }
    
    if(not $In::Opt{"CheckHeadersOnly"})
    {
        foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "libs")))
        {
            if(not -e $Path) {
                exitStatus("Access_Error", "can't access \'$Path\'");
            }
            
            $DescRef->{"Libs"}{$Path} = 1;
        }
        
        if(not defined $DescRef->{"Libs"}) {
            exitStatus("Error", "can't find libraries info in the XML descriptor");
        }
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_headers")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = getAbsPath($Path);
        push_U($In::Opt{"SysPaths"}{"include"}, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_libs")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = getAbsPath($Path);
        push_U($In::Opt{"SysPaths"}{"lib"}, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "tools")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = getAbsPath($Path);
        push_U($In::Opt{"SysPaths"}{"bin"}, $Path);
        $In::Opt{"TargetTools"}{$Path} = 1;
    }
    if(my $Prefix = parseTag(\$Content, "cross_prefix")) {
        $In::Opt{"CrossPrefix"} = $Prefix;
    }
    
    $DescRef->{"IncludePaths"} = [];
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "include_paths")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = getAbsPath($Path);
        push(@{$DescRef->{"IncludePaths"}}, $Path);
    }
    
    if(not @{$DescRef->{"IncludePaths"}}) {
        $DescRef->{"AutoIncludePaths"} = 1;
    }
    
    $DescRef->{"AddIncludePaths"} = [];
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "add_include_paths")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = getAbsPath($Path);
        push(@{$DescRef->{"AddIncludePaths"}}, $Path);
    }
    
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_include_paths")))
    { # skip some auto-generated include paths
        $Path = getAbsPath($Path);
        $DescRef->{"SkipIncludePaths"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_including")))
    { # skip direct including of some headers
        if(my ($CPath, $Type) = classifyPath($Path)) {
            $DescRef->{"SkipHeaders"}{$Type}{$CPath} = 2;
        }
    }
    foreach my $Option (split(/\s*\n\s*/, parseTag(\$Content, "gcc_options")))
    {
        if($Option!~/\A\-(Wl|l|L)/)
        { # skip linker options
            $DescRef->{"CompilerOptions"} .= " ".$Option;
        }
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_headers")))
    {
        if(my ($CPath, $Type) = classifyPath($Path)) {
            $DescRef->{"SkipHeaders"}{$Type}{$CPath} = 1;
        }
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_libs")))
    {
        if(my ($CPath, $Type) = classifyPath($Path)) {
            $DescRef->{"SkipLibs"}{$Type}{$CPath} = 1;
        }
    }
    if(my $DDefines = parseTag(\$Content, "defines"))
    {
        if($DescRef->{"Defines"})
        { # multiple descriptors
            $DescRef->{"Defines"} .= "\n".$DDefines;
        }
        else {
            $DescRef->{"Defines"} = $DDefines;
        }
    }
    foreach my $Order (split(/\s*\n\s*/, parseTag(\$Content, "include_order")))
    {
        if($Order=~/\A(.+):(.+)\Z/) {
            $DescRef->{"IncludeOrder"}{$1} = $2;
        }
    }
    foreach my $NameSpace (split(/\s*\n\s*/, parseTag(\$Content, "add_namespaces"))) {
        $DescRef->{"AddNameSpaces"}{$NameSpace} = 1;
    }
    if(my $DIncPreamble = parseTag(\$Content, "include_preamble"))
    {
        if($DescRef->{"IncludePreamble"})
        { # multiple descriptors
            $DescRef->{"IncludePreamble"} .= "\n".$DIncPreamble;
        }
        else {
            $DescRef->{"IncludePreamble"} = $DIncPreamble;
        }
    }
    
    readFilter($Content, $LVer);
}

sub readFilter($$)
{
    my ($Content, $LVer) = @_;
    
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    
    my $DescRef = $In::Desc{$LVer};
    
    foreach my $TName (split(/\s*\n\s*/, parseTag(\$Content, "opaque_types")),
    split(/\s*\n\s*/, parseTag(\$Content, "skip_types"))) {
        $DescRef->{"SkipTypes"}{$TName} = 1;
    }
    foreach my $Symbol (split(/\s*\n\s*/, parseTag(\$Content, "skip_interfaces")),
    split(/\s*\n\s*/, parseTag(\$Content, "skip_symbols"))) {
        $DescRef->{"SkipSymbols"}{$Symbol} = 1;
    }
    foreach my $NameSpace (split(/\s*\n\s*/, parseTag(\$Content, "skip_namespaces"))) {
        $DescRef->{"SkipNameSpaces"}{$NameSpace} = 1;
    }
    foreach my $Constant (split(/\s*\n\s*/, parseTag(\$Content, "skip_constants"))) {
        $DescRef->{"SkipConstants"}{$Constant} = 1;
    }
}

return 1;
