###########################################################################
# A module to read ELF binaries
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

my %ELF_BIND = map {$_=>1} (
    "WEAK",
    "GLOBAL"
);

my %ELF_TYPE = map {$_=>1} (
    "FUNC",
    "IFUNC",
    "OBJECT",
    "COMMON"
);

my %ELF_VIS = map {$_=>1} (
    "DEFAULT",
    "PROTECTED"
);

sub readline_ELF($)
{ # read the line of 'readelf' output corresponding to the symbol
    my @Info = split(/\s+/, $_[0]);
    #  Num:   Value      Size Type   Bind   Vis       Ndx  Name
    #  3629:  000b09c0   32   FUNC   GLOBAL DEFAULT   13   _ZNSt12__basic_fileIcED1Ev@@GLIBCXX_3.4
    #  135:   00000000    0   FUNC   GLOBAL DEFAULT   UND  av_image_fill_pointers@LIBAVUTIL_52 (3)
    shift(@Info); # spaces
    shift(@Info); # num
    
    if($#Info==7)
    { # UND SYMBOL (N)
        if($Info[7]=~/\(\d+\)/) {
            pop(@Info);
        }
    }
    
    if($#Info!=6)
    { # other lines
        return ();
    }
    return () if(not defined $ELF_TYPE{$Info[2]} and $Info[5] ne "UND");
    return () if(not defined $ELF_BIND{$Info[3]});
    return () if(not defined $ELF_VIS{$Info[4]});
    if($Info[5] eq "ABS" and $Info[0]=~/\A0+\Z/)
    { # 1272: 00000000     0 OBJECT  GLOBAL DEFAULT  ABS CXXABI_1.3
        return ();
    }
    if($In::Opt{"Target"} eq "symbian")
    { # _ZN12CCTTokenType4NewLE4TUid3RFs@@ctfinder{000a0000}[102020e5].dll
        if(index($Info[6], "_._.absent_export_")!=-1)
        { # "_._.absent_export_111"@@libstdcpp{00010001}[10282872].dll
            return ();
        }
        $Info[6]=~s/\@.+//g; # remove version
    }
    if(index($Info[2], "0x") == 0)
    { # size == 0x3d158
        $Info[2] = hex($Info[2]);
    }
    return @Info;
}

sub getSONAME($)
{
    my $Path = $_[0];
    
    if(defined $Cache{"getSONAME"}{$Path}) {
        return $Cache{"getSONAME"}{$Path};
    }
    my $Objdump = getCmdPath("objdump");
    if(not $Objdump) {
        exitStatus("Not_Found", "can't find \"objdump\"");
    }
    my $TmpDir = $In::Opt{"Tmp"};
    my $SonameCmd = "$Objdump -x \"$Path\" 2>$TmpDir/null";
    if($In::Opt{"OS"} eq "windows") {
        $SonameCmd .= " | find \"SONAME\"";
    }
    else {
        $SonameCmd .= " | grep SONAME";
    }
    if(my $Info = `$SonameCmd`)
    {
        if($Info=~/SONAME\s+([^\s]+)/) {
            return ($Cache{"getSONAME"}{$Path} = $1);
        }
    }
    return ($Cache{"getSONAME"}{$Path}="");
}

sub getArch_Object($)
{
    my $Path = $_[0];
    
    my %MachineType = (
        "14C" => "x86",
        "8664" => "x86_64",
        "1C0" => "arm",
        "200" => "ia64"
    );
    
    my %ArchName = (
        "s390:31-bit" => "s390",
        "s390:64-bit" => "s390x",
        "powerpc:common" => "ppc32",
        "powerpc:common64" => "ppc64",
        "i386:x86-64" => "x86_64",
        "mips:3000" => "mips",
        "sparc:v8plus" => "sparcv9"
    );
    
    if($In::Opt{"OS"} eq "windows")
    {
        my $DumpbinCmd = getCmdPath("dumpbin");
        if(not $DumpbinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin\"");
        }
        
        my $Cmd = $DumpbinCmd." /headers \"$Path\"";
        my $Out = `$Cmd`;
        
        if($Out=~/(\w+)\smachine/)
        {
            if(my $Type = $MachineType{uc($1)})
            {
                return $Type;
            }
        }
    }
    elsif($In::Opt{"OS"} eq "macos")
    {
        my $OtoolCmd = getCmdPath("otool");
        if(not $OtoolCmd) {
            exitStatus("Not_Found", "can't find \"otool\"");
        }
        
        my $Cmd = $OtoolCmd." -hv -arch all \"$Path\"";
        my $Out = qx/$Cmd/;
        
        if($Out=~/X86_64/i) {
            return "x86_64";
        }
        elsif($Out=~/X86/i) {
            return "x86";
        }
    }
    else
    { # linux, bsd, gnu, solaris, ...
        my $ObjdumpCmd = getCmdPath("objdump");
        if(not $ObjdumpCmd) {
            exitStatus("Not_Found", "can't find \"objdump\"");
        }
        
        my $TmpDir = $In::Opt{"Tmp"};
        my $Cmd = $ObjdumpCmd." -f \"$Path\" 2>$TmpDir/null";
        
        my $Locale = $In::Opt{"Locale"};
        if($In::Opt{"OS"} eq "windows") {
            $Cmd = "set LANG=$Locale & ".$Cmd;
        }
        else {
            $Cmd = "LANG=$Locale ".$Cmd;
        }
        my $Out = `$Cmd`;
        
        if($Out=~/architecture:\s+([\w\-\:]+)/)
        {
            my $Arch = $1;
            if($Arch=~s/\:(.+)//)
            {
                my $Suffix = $1;
                
                if(my $Name = $ArchName{$Arch.":".$Suffix})
                {
                    $Arch = $Name;
                }
            }
            
            if($Arch=~/i[3-6]86/) {
                $Arch = "x86";
            }
            
            if($Arch eq "x86-64") {
                $Arch = "x86_64";
            }
            
            if($Arch eq "ia64-elf64") {
                $Arch = "ia64";
            }
            
            return $Arch;
        }
    }
    
    return undef;
}

sub getArch_GCC($)
{
    my $LVer = $_[0];
    
    if(defined $Cache{"getArch_GCC"}{$LVer}) {
        return $Cache{"getArch_GCC"}{$LVer};
    }
    
    my $GccPath = $In::Opt{"GccPath"};
    
    if(not $GccPath) {
        return undef;
    }
    
    my $Arch = undef;
    
    if(my $Target = $In::Opt{"GccTarget"})
    {
        if($Target=~/x86_64/) {
            $Arch = "x86_64";
        }
        elsif($Target=~/i[3-6]86/) {
            $Arch = "x86";
        }
        elsif($Target=~/\Aarm/i) {
            $Arch = "arm";
        }
    }
    
    if(not $Arch)
    {
        my $TmpDir = $In::Opt{"Tmp"};
        my $OrigDir = $In::Opt{"OrigDir"};
        
        writeFile($TmpDir."/test.c", "int main(){return 0;}\n");
        
        my $Cmd = $GccPath." test.c -o test";
        if(my $Opts = getGccOptions($LVer))
        { # user-defined options
            $Cmd .= " ".$Opts;
        }
        
        chdir($TmpDir);
        system($Cmd);
        chdir($OrigDir);
        
        my $EX = join_P($TmpDir, "test");
        
        if($In::Opt{"OS"} eq "windows") {
            $EX = join_P($TmpDir, "test.exe");
        }
        
        $Arch = getArch_Object($EX);
        
        unlink("$TmpDir/test.c");
        unlink($EX);
    }
    
    if(not $Arch) {
        exitStatus("Error", "can't check ARCH type");
    }
    
    return ($Cache{"getArch_GCC"}{$LVer} = $Arch);
}

return 1;
