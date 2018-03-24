###########################################################################
# A module with basic functions
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

my %Cache;

my %IntrinsicKeywords = map {$_=>1} (
    "true",
    "false",
    "_Bool",
    "_Complex",
    "const",
    "int",
    "long",
    "void",
    "short",
    "float",
    "volatile",
    "restrict",
    "unsigned",
    "signed",
    "char",
    "double",
    "class",
    "struct",
    "union",
    "enum"
);

sub initABI($)
{
    my $V = $_[0];
    foreach my $K ("SymbolInfo", "TypeInfo", "TName_Tid", "Constants")
    {
        if(not defined $In::ABI{$V}{$K}) {
            $In::ABI{$V}{$K} = {};
        }
    }
}

sub cmdFind(@)
{ # native "find" is much faster than File::Find (~6x)
  # also the File::Find doesn't support --maxdepth N option
  # so using the cross-platform wrapper for the native one
    my ($Path, $Type, $Name, $MaxDepth, $UseRegex) = ();
    
    $Path = shift(@_);
    if(@_) {
        $Type = shift(@_);
    }
    if(@_) {
        $Name = shift(@_);
    }
    if(@_) {
        $MaxDepth = shift(@_);
    }
    if(@_) {
        $UseRegex = shift(@_);
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    if($In::Opt{"OS"} eq "windows")
    {
        $Path = getAbsPath($Path);
        my $Cmd = "cmd /C dir \"$Path\" /B /O";
        if($MaxDepth!=1) {
            $Cmd .= " /S";
        }
        if($Type eq "d") {
            $Cmd .= " /AD";
        }
        elsif($Type eq "f") {
            $Cmd .= " /A-D";
        }
        my @Files = split(/\n/, qx/$Cmd/);
        if($Name)
        {
            if(not $UseRegex)
            { # FIXME: how to search file names in MS shell?
              # wildcard to regexp
                $Name=~s/\*/.*/g;
                $Name='\A'.$Name.'\Z';
            }
            @Files = grep { /$Name/i } @Files;
        }
        my @AbsPaths = ();
        foreach my $File (@Files)
        {
            if(not isAbsPath($File)) {
                $File = join_P($Path, $File);
            }
            if($Type eq "f" and not -f $File)
            { # skip dirs
                next;
            }
            push(@AbsPaths, pathFmt($File));
        }
        if($Type eq "d") {
            push(@AbsPaths, $Path);
        }
        return @AbsPaths;
    }
    else
    {
        my $FindCmd = "find";
        if(not checkCmd($FindCmd)) {
            exitStatus("Not_Found", "can't find a \"find\" command");
        }
        $Path = getAbsPath($Path);
        if(-d $Path and -l $Path
        and $Path!~/\/\Z/)
        { # for directories that are symlinks
            $Path.="/";
        }
        my $Cmd = $FindCmd." \"$Path\"";
        if($MaxDepth) {
            $Cmd .= " -maxdepth $MaxDepth";
        }
        if($Type) {
            $Cmd .= " -type $Type";
        }
        if($Name and not $UseRegex)
        { # wildcards
            $Cmd .= " -name \"$Name\"";
        }
        my $Res = `$Cmd 2>\"$TmpDir/null\"`;
        if($? and $!) {
            printMsg("ERROR", "problem with \'find\' utility ($?): $!");
        }
        my @Files = split(/\n/, $Res);
        if($Name and $UseRegex)
        { # regex
            @Files = grep { /$Name/ } @Files;
        }
        return @Files;
    }
}

sub findLibs($$$)
{ # FIXME: correct the search pattern
    my ($Path, $Type, $MaxDepth) = @_;
    return cmdFind($Path, $Type, '\.'.$In::Opt{"Ext"}.'[0-9.]*\Z', $MaxDepth, 1);
}

sub getPrefixes($)
{
    my %Prefixes = ();
    getPrefixes_I([$_[0]], \%Prefixes);
    return keys(%Prefixes);
}

sub getPrefixes_I($$)
{
    my $S = "/";
    if($In::Opt{"OS"} eq "windows") {
        $S = "\\";
    }
    
    foreach my $P (@{$_[0]})
    {
        my @Parts = reverse(split(/[\/\\]+/, $P));
        my $Name = $Parts[0];
        foreach (1 .. $#Parts)
        {
            $_[1]->{$Name}{$P} = 1;
            if($_>4 or $Parts[$_] eq "include") {
                last;
            }
            $Name = $Parts[$_].$S.$Name;
        }
    }
}

sub getCompileCmd($$$$)
{
    my ($Path, $Opt, $Inc, $LVer) = @_;
    my $GccCall = $In::Opt{"GccPath"};
    if($Opt) {
        $GccCall .= " ".$Opt;
    }
    $GccCall .= " -x ";
    if($In::Opt{"OS"} eq "macos") {
        $GccCall .= "objective-";
    }
    
    if($In::Opt{"GccMissedMangling"})
    { # workaround for GCC 4.8 (C only)
        $GccCall .= "c++";
    }
    elsif(checkGcc("4"))
    { # compile as "C++" header
      # to obtain complete dump using GCC 4.0
        $GccCall .= "c++-header";
    }
    else
    { # compile as "C++" source
      # GCC 3.3 cannot compile headers
        $GccCall .= "c++";
    }
    if(my $Opts = platformSpecs($LVer))
    { # platform-specific options
        $GccCall .= " ".$Opts;
    }
    # allow extra qualifications
    # and other nonconformant code
    $GccCall .= " -fpermissive";
    $GccCall .= " -w";
    if($In::Opt{"NoStdInc"})
    {
        $GccCall .= " -nostdinc";
        $GccCall .= " -nostdinc++";
    }
    if(my $Opts = getGccOptions($LVer))
    { # user-defined options
        $GccCall .= " ".$Opts;
    }
    $GccCall .= " \"$Path\"";
    if($Inc)
    { # include paths
        $GccCall .= " ".$Inc;
    }
    return $GccCall;
}

sub platformSpecs($)
{
    my $LVer = $_[0];
    
    if($In::Opt{"Target"} eq "symbian")
    { # options for GCCE compiler
        my @Symbian_Opts = (
            "-D__GCCE__",
            "-DUNICODE",
            "-fexceptions",
            "-D__SYMBIAN32__",
            "-D__MARM_INTERWORK__",
            "-D_UNICODE",
            "-D__S60_50__",
            "-D__S60_3X__",
            "-D__SERIES60_3X__",
            "-D__EPOC32__",
            "-D__MARM__",
            "-D__EABI__",
            "-D__MARM_ARMV5__",
            "-D__SUPPORT_CPP_EXCEPTIONS__",
            "-march=armv5t",
            "-mapcs",
            "-mthumb-interwork",
            "-DEKA2",
            "-DSYMBIAN_ENABLE_SPLIT_HEADERS"
        );
        return join(" ", @Symbian_Opts);
    }
    elsif($In::Opt{"OS"} eq "windows"
    and $In::Opt{"GccTarget"}=~/mingw/i)
    { # add options to MinGW compiler
      # to simulate the MSVC compiler
        my @MinGW_Opts = (
            "-D__unaligned=\" \"",
            "-D__nullptr=\"nullptr\"",
            "-D_WIN32",
            "-D_STDCALL_SUPPORTED",
            "-D__int64=\"long long\"",
            "-D__int32=int",
            "-D__int16=short",
            "-D__int8=char",
            "-D__possibly_notnullterminated=\" \"",
            "-D__nullterminated=\" \"",
            "-D__nullnullterminated=\" \"",
            "-D__assume=\" \"",
            "-D__w64=\" \"",
            "-D__ptr32=\" \"",
            "-D__ptr64=\" \"",
            "-D__forceinline=inline",
            "-D__inline=inline",
            "-D__uuidof(x)=IID()",
            "-D__try=",
            "-D__except(x)=",
            "-D__declspec(x)=__attribute__((x))",
            "-D__pragma(x)=",
            "-D_inline=inline",
            "-D__forceinline=__inline",
            "-D__stdcall=__attribute__((__stdcall__))",
            "-D__cdecl=__attribute__((__cdecl__))",
            "-D__fastcall=__attribute__((__fastcall__))",
            "-D__thiscall=__attribute__((__thiscall__))",
            "-D_stdcall=__attribute__((__stdcall__))",
            "-D_cdecl=__attribute__((__cdecl__))",
            "-D_fastcall=__attribute__((__fastcall__))",
            "-D_thiscall=__attribute__((__thiscall__))",
            "-DSHSTDAPI_(x)=x",
            "-D_MSC_EXTENSIONS",
            "-DSECURITY_WIN32",
            "-D_MSC_VER=1500",
            "-D_USE_DECLSPECS_FOR_SAL",
            "-D__noop=\" \"",
            "-DDECLSPEC_DEPRECATED=\" \"",
            "-D__builtin_alignof(x)=__alignof__(x)",
            "-DSORTPP_PASS");
        
        if($In::ABI{$LVer}{"Arch"} eq "x86")
        {
            push(@MinGW_Opts, "-D_X86_=300");
            push(@MinGW_Opts, "-D_M_IX86=300");
        }
        elsif($In::ABI{$LVer}{"Arch"} eq "x86_64")
        {
            push(@MinGW_Opts, "-D_AMD64_=300");
            push(@MinGW_Opts, "-D_M_AMD64=300");
            push(@MinGW_Opts, "-D_M_X64=300");
        }
        elsif($In::ABI{$LVer}{"Arch"} eq "ia64")
        {
            push(@MinGW_Opts, "-D_IA64_=300");
            push(@MinGW_Opts, "-D_M_IA64=300");
        }
        
        return join(" ", @MinGW_Opts);
    }
    return undef;
}

sub uncoverTypedefs($$)
{
    my ($TypeName, $LVer) = @_;
    
    if(defined $Cache{"uncoverTypedefs"}{$LVer}{$TypeName}) {
        return $Cache{"uncoverTypedefs"}{$LVer}{$TypeName};
    }
    my ($TypeName_New, $TypeName_Pre) = (formatName($TypeName, "T"), "");
    while($TypeName_New ne $TypeName_Pre)
    {
        $TypeName_Pre = $TypeName_New;
        my $TypeName_Copy = $TypeName_New;
        my %Words = ();
        while($TypeName_Copy=~s/\b([a-z_]([\w:]*\w|))\b//io)
        {
            if(not $IntrinsicKeywords{$1}) {
                $Words{$1} = 1;
            }
        }
        foreach my $Word (keys(%Words))
        {
            my $BaseType_Name = $In::ABI{$LVer}{"TypedefBase"}{$Word};
            
            next if(not $BaseType_Name);
            next if($BaseType_Name=~/\b$Word\b/);
            next if($TypeName_New=~/\b(struct|union|enum)\s\Q$Word\E\b/);
            
            if($BaseType_Name=~/\([\*]+\)/)
            { # FuncPtr
                if($TypeName_New=~/\Q$Word\E(.*)\Z/)
                {
                    my $Type_Suffix = $1;
                    $TypeName_New = $BaseType_Name;
                    if($TypeName_New=~s/\(([\*]+)\)/($1 $Type_Suffix)/) {
                        $TypeName_New = formatName($TypeName_New, "T");
                    }
                }
            }
            else
            {
                if($TypeName_New=~s/\b\Q$Word\E\b/$BaseType_Name/g) {
                    $TypeName_New = formatName($TypeName_New, "T");
                }
            }
        }
    }
    return ($Cache{"uncoverTypedefs"}{$LVer}{$TypeName} = $TypeName_New);
}

sub getGccOptions($)
{
    my $LVer = $_[0];
    
    my @Opt = ();
    
    if(my $COpt = $In::Desc{$LVer}{"CompilerOptions"})
    { # user-defined options
        push(@Opt, $COpt);
    }
    if($In::Opt{"GccOptions"})
    { # additional
        push(@Opt, $In::Opt{"GccOptions"});
    }
    
    if(@Opt) {
        return join(" ", @Opt);
    }
    
    return undef;
}

sub setTarget($)
{
    my $Target = $_[0];
    
    if($Target eq "default")
    {
        $Target = getOSgroup();
        
        $In::Opt{"OS"} = $Target;
        $In::Opt{"Ar"} = getArExt($Target);
    }
    
    $In::Opt{"Target"} = $Target;
    $In::Opt{"Ext"} = getLibExt($Target, $In::Opt{"UseStaticLibs"});
}

sub filterFormat($)
{
    my $FiltRef = $_[0];
    foreach my $Entry (keys(%{$FiltRef}))
    {
        foreach my $Filt (@{$FiltRef->{$Entry}})
        {
            if($Filt=~/[\/\\]/) {
                $Filt = pathFmt($Filt);
            }
        }
    }
}

sub checkGcc(@)
{
    my $Req = shift(@_);
    my $Gcc = $In::Opt{"GccPath"};
    
    if(@_) {
        $Gcc = shift(@_);
    }
    
    if(defined $Cache{"checkGcc"}{$Gcc}{$Req}) {
        return $Cache{"checkGcc"}{$Gcc}{$Req};
    }
    if(my $Ver = dumpVersion($Gcc))
    {
        $Ver=~s/(-|_)[a-z_]+.*\Z//; # remove suffix (like "-haiku-100818")
        if(cmpVersions($Ver, $Req)>=0) {
            return ($Cache{"checkGcc"}{$Gcc}{$Req} = $Gcc);
        }
    }
    return ($Cache{"checkGcc"}{$Gcc}{$Req} = "");
}

sub dumpVersion($)
{
    my $Cmd = $_[0];
    
    if($Cache{"dumpVersion"}{$Cmd}) {
        return $Cache{"dumpVersion"}{$Cmd};
    }
    my $TmpDir = $In::Opt{"Tmp"};
    my $V = `$Cmd -dumpversion 2>\"$TmpDir/null\"`;
    chomp($V);
    return ($Cache{"dumpVersion"}{$Cmd} = $V);
}

sub dumpMachine($)
{
    my $Cmd = $_[0];
    
    if($Cache{"dumpMachine"}{$Cmd}) {
        return $Cache{"dumpMachine"}{$Cmd};
    }
    my $TmpDir = $In::Opt{"Tmp"};
    my $Machine = `$Cmd -dumpmachine 2>\"$TmpDir/null\"`;
    chomp($Machine);
    return ($Cache{"dumpMachine"}{$Cmd} = $Machine);
}

return 1;
