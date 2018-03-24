###########################################################################
# A module to filter symbols
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

sub symbolFilter($$$$)
{ # some special cases when the symbol cannot be imported
    my ($Symbol, $SInfo, $Type, $Level, $LVer) = @_;
    
    if($SInfo->{"Private"})
    { # skip private methods
        return 0;
    }
    
    if(isPrivateData($Symbol))
    { # non-public global data
        return 0;
    }
    
    if(defined $In::Opt{"SkipInternalSymbols"}
    and my $Pattern = $In::Opt{"SkipInternalSymbols"})
    {
        if($Symbol=~/($Pattern)/) {
            return 0;
        }
    }
    
    if($Symbol=~/\A_Z/)
    {
        if($Symbol=~/[CD][3-4]E/) {
            return 0;
        }
    }
    
    if($Type=~/Affected/)
    {
        my $Header = $SInfo->{"Header"};
        
        if($In::Desc{$LVer}{"SkipSymbols"}{$Symbol})
        { # user defined symbols to ignore
            return 0;
        }
        
        if($In::Opt{"SymbolsListPath"} and not $In::Desc{$LVer}{"SymbolsList"}{$Symbol})
        { # user defined symbols
            if(not $In::Opt{"TargetHeadersPath"} or not $Header
            or not isTargetHeader($Header, $LVer))
            { # -symbols-list | -headers-list
                return 0;
            }
        }
        
        if($In::Opt{"AppPath"} and not $In::Opt{"SymbolsList_App"}{$Symbol})
        { # user defined symbols (in application)
            return 0;
        }
        
        my $ClassId = $SInfo->{"Class"};
        
        if($ClassId)
        {
            if(not isTargetType($ClassId, $LVer)) {
                return 0;
            }
        }
        
        my $NameSpace = $SInfo->{"NameSpace"};
        if(not $NameSpace and $ClassId)
        { # class methods have no "NameSpace" attribute
            $NameSpace = $In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"NameSpace"};
        }
        if($NameSpace)
        { # user defined namespaces to ignore
            if($In::Desc{$LVer}{"SkipNameSpaces"}{$NameSpace}) {
                return 0;
            }
            foreach my $NS (keys(%{$In::Desc{$LVer}{"SkipNameSpaces"}}))
            { # nested namespaces
                if($NameSpace=~/\A\Q$NS\E(\:\:|\Z)/) { 
                    return 0;
                }
            }
        }
        if($Header)
        {
            if(my $Skip = skipHeader($Header, $LVer))
            { # --skip-headers or <skip_headers> (not <skip_including>)
                if($Skip==1) {
                    return 0;
                }
            }
        }
        if($In::Opt{"TypesListPath"} and $ClassId)
        { # user defined types
            my $CName = $In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"Name"};
            
            if(not $In::Desc{$LVer}{"TypesList"}{$CName})
            {
                if(my $NS = $In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"NameSpace"})
                {
                    $CName=~s/\A\Q$NS\E\:\://g;
                }
                
                if(not $In::Desc{$LVer}{"TypesList"}{$CName})
                {
                    my $Found = 0;
                    
                    while($CName=~s/\:\:.+?\Z//)
                    {
                        if($In::Desc{$LVer}{"TypesList"}{$CName})
                        {
                            $Found = 1;
                            last;
                        }
                    }
                    
                    if(not $Found) {
                        return 0;
                    }
                }
            }
        }
        
        if(not selectSymbol($Symbol, $SInfo, $Level, $LVer))
        { # non-target symbols
            return 0;
        }
        
        if($Level eq "Binary")
        {
            if($SInfo->{"InLine"}
            or (not $SInfo->{"Static"} and isInLineInst($SInfo, $LVer)))
            { # example: _ZN6Givaro6ZpzDomINS_7IntegerEE3EndEv is not exported (inlined)
                if($ClassId and $SInfo->{"Virt"})
                { # inline virtual methods
                    if($Type=~/InlineVirt/) {
                        return 1;
                    }
                    my $Allocable = (not isCopyingClass($ClassId, $LVer));
                    if(not $Allocable)
                    { # check bases
                        foreach my $DCId (getSubClasses($ClassId, $LVer, 1))
                        {
                            if(not isCopyingClass($DCId, $LVer))
                            { # exists a derived class without default c-tor
                                $Allocable=1;
                                last;
                            }
                        }
                    }
                    if(not $Allocable) {
                        return 0;
                    }
                }
                else
                { # inline non-virtual methods
                    return 0;
                }
            }
        }
    }
    return 1;
}

sub selectSymbol($$$$)
{ # select symbol to check or to dump
    my ($Symbol, $SInfo, $Level, $LVer) = @_;
    
    if($SInfo->{"Constructor"}==1)
    {
        if(index($Symbol, "C4E")!=-1) {
            return 0;
        }
    }
    elsif($SInfo->{"Destructor"}==1)
    {
        if(index($Symbol, "D4E")!=-1) {
            return 0;
        }
    }
    
    if($Level eq "Dump")
    {
        if($SInfo->{"Virt"} or $SInfo->{"PureVirt"})
        { # TODO: check if this symbol is from
          # base classes of other target symbols
            return 1;
        }
    }
    
    if(not $In::Opt{"StdcxxTesting"} and not $In::Opt{"KeepCxx"}
    and $Symbol=~/\A(_ZS|_ZNS|_ZNKS)/)
    { # stdc++ interfaces
        return 0;
    }
    
    my $Target = 0;
    if(my $Header = $SInfo->{"Header"}) {
        $Target = isTargetHeader($Header, $LVer);
    }
    
    if(not $Target)
    {
        if(my $Source = $SInfo->{"Source"}) {
            $Target = isTargetSource($Source, $LVer);
        }
    }
    
    if($In::Opt{"ExtendedCheck"})
    {
        if(index($Symbol, "external_func_")==0) {
            $Target = 1;
        }
    }
    if($In::Opt{"CheckHeadersOnly"}
    or $Level eq "Source")
    {
        if($Target)
        {
            if($Level eq "Dump")
            { # dumped
                if($In::Opt{"BinOnly"})
                {
                    if(not $SInfo->{"InLine"} or $SInfo->{"Data"}) {
                        return 1;
                    }
                }
                else {
                    return 1;
                }
            }
            elsif($Level eq "Source")
            { # checked
                return 1;
            }
            elsif($Level eq "Binary")
            { # checked
                if(not $SInfo->{"InLine"} or $SInfo->{"Data"}
                or $SInfo->{"Virt"} or $SInfo->{"PureVirt"}) {
                    return 1;
                }
            }
        }
    }
    else
    { # library is available
        if(linkSymbol($Symbol, $LVer, "-Deps"))
        { # exported symbols
            return 1;
        }
        if($Level eq "Dump")
        { # dumped
            if($In::Opt{"BinOnly"})
            {
                if($SInfo->{"Data"})
                {
                    if($Target) {
                        return 1;
                    }
                }
            }
            else
            { # SrcBin
                if($Target) {
                    return 1;
                }
            }
        }
        elsif($Level eq "Source")
        { # checked
            if($SInfo->{"PureVirt"} or $SInfo->{"Data"} or $SInfo->{"InLine"}
            or isInLineInst($SInfo, $LVer))
            { # skip LOCAL symbols
                if($Target) {
                    return 1;
                }
            }
        }
        elsif($Level eq "Binary")
        { # checked
            if($SInfo->{"PureVirt"} or $SInfo->{"Data"})
            {
                if($Target) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

sub linkSymbol($$$)
{
    my ($Symbol, $RunWith, $Deps) = @_;
    if(linkSymbol_I($Symbol, $RunWith, "SymLib")) {
        return 1;
    }
    if($Deps eq "+Deps")
    { # check the dependencies
        if(linkSymbol_I($Symbol, $RunWith, "DepSymLib")) {
            return 1;
        }
    }
    return 0;
}

sub linkSymbol_I($$$)
{
    my ($Symbol, $RunWith, $Where) = @_;
    if(not $Where or not $Symbol) {
        return 0;
    }
    
    my $SRef = $In::ABI{$RunWith}{$Where};
    
    if($SRef->{$Symbol})
    { # the exact match by symbol name
        return 1;
    }
    if(my $VSym = $In::ABI{$RunWith}{"SymbolVersion"}{$Symbol})
    { # indirect symbol version, i.e.
      # foo_old and its symlink foo@v (or foo@@v)
      # foo_old may be in symtab table
        if($SRef->{$VSym}) {
            return 1;
        }
    }
    
    if($Symbol=~/[\@\$]/)
    {
        my ($Sym, $Spec, $Ver) = symbolParts($Symbol);
        if($Sym and $Ver)
        { # search for the symbol with the same version
          # or without version
            if($SRef->{$Sym})
            { # old: foo@v|foo@@v
              # new: foo
                return 1;
            }
            if($SRef->{$Sym."\@".$Ver})
            { # old: foo|foo@@v
              # new: foo@v
                return 1;
            }
            if($SRef->{$Sym."\@\@".$Ver})
            { # old: foo|foo@v
              # new: foo@@v
                return 1;
            }
        }
    }
    
    return 0;
}

sub isPrivateData($)
{ # non-public global data
    my $Symbol = $_[0];
    return ($Symbol=~/\A(_ZGV|_ZTI|_ZTS|_ZTT|_ZTV|_ZTC|_ZThn|_ZTv0_n)/);
}

sub isInLineInst($$) {
    return (isTemplateInstance(@_) and not isTemplateSpec(@_));
}

sub isTemplateInstance($$)
{
    my ($SInfo, $LVer) = @_;
    
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(my $ClassName = $In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"Name"})
        {
            if(index($ClassName,"<")!=-1) {
                return 1;
            }
        }
    }
    if(my $ShortName = $SInfo->{"ShortName"})
    {
        if(index($ShortName,"<")!=-1
        and index($ShortName,">")!=-1) {
            return 1;
        }
    }
    
    return 0;
}

sub isTemplateSpec($$)
{
    my ($SInfo, $LVer) = @_;
    if(my $ClassId = $SInfo->{"Class"})
    {
        if($In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"Spec"})
        { # class specialization
            return 1;
        }
        elsif($SInfo->{"Spec"})
        { # method specialization
            return 1;
        }
    }
    return 0;
}

sub skipHeader($$)
{
    my ($Path, $LVer) = @_;
    
    if(defined $Cache{"skipHeader"}{$LVer}{$Path}) {
        return $Cache{"skipHeader"}{$LVer}{$Path};
    }
    
    if(defined $In::Opt{"Tolerance"}
    and $In::Opt{"Tolerance"}=~/1|2/)
    { # --tolerant
        if(skipAlienHeader($Path)) {
            return ($Cache{"skipHeader"}{$LVer}{$Path} = 1);
        }
    }
    if(not keys(%{$In::Desc{$LVer}{"SkipHeaders"}})) {
        return 0;
    }
    return ($Cache{"skipHeader"}{$LVer}{$Path} = skipHeader_I(@_));
}

sub skipHeader_I($$)
{ # returns:
  #  1 - if header should NOT be included and checked
  #  2 - if header should NOT be included, but should be checked
    my ($Path, $LVer) = @_;
    my $Name = getFilename($Path);
    if(my $Kind = $In::Desc{$LVer}{"SkipHeaders"}{"Name"}{$Name}) {
        return $Kind;
    }
    foreach my $D (sort {$In::Desc{$LVer}{"SkipHeaders"}{"Path"}{$a} cmp $In::Desc{$LVer}{"SkipHeaders"}{"Path"}{$b}}
    keys(%{$In::Desc{$LVer}{"SkipHeaders"}{"Path"}}))
    {
        if(index($Path, $D)!=-1)
        {
            if($Path=~/\Q$D\E([\/\\]|\Z)/) {
                return $In::Desc{$LVer}{"SkipHeaders"}{"Path"}{$D};
            }
        }
    }
    foreach my $P (sort {$In::Desc{$LVer}{"SkipHeaders"}{"Pattern"}{$a} cmp $In::Desc{$LVer}{"SkipHeaders"}{"Pattern"}{$b}}
    keys(%{$In::Desc{$LVer}{"SkipHeaders"}{"Pattern"}}))
    {
        if(my $Kind = $In::Desc{$LVer}{"SkipHeaders"}{"Pattern"}{$P})
        {
            if($Name=~/$P/) {
                return $Kind;
            }
            if($P=~/[\/\\]/ and $Path=~/$P/) {
                return $Kind;
            }
        }
    }
    
    return 0;
}

sub skipLib($$)
{
    my ($Path, $LVer) = @_;
    
    my $Name = getFilename($Path);
    if($In::Desc{$LVer}{"SkipLibs"}{"Name"}{$Name}) {
        return 1;
    }
    my $ShortName = libPart($Name, "name+ext");
    if($In::Desc{$LVer}{"SkipLibs"}{"Name"}{$ShortName}) {
        return 1;
    }
    foreach my $Dir (keys(%{$In::Desc{$LVer}{"SkipLibs"}{"Path"}}))
    {
        if($Path=~/\Q$Dir\E([\/\\]|\Z)/) {
            return 1;
        }
    }
    foreach my $P (keys(%{$In::Desc{$LVer}{"SkipLibs"}{"Pattern"}}))
    {
        if($Name=~/$P/) {
            return 1;
        }
        if($P=~/[\/\\]/ and $Path=~/$P/) {
            return 1;
        }
    }
    return 0;
}

sub addTargetLibs($)
{
    my $LibsRef = $_[0];
    foreach (@{$LibsRef}) {
        $In::Opt{"TargetLibs"}{$_} = 1;
    }
}

sub isTargetLib($)
{
    my $LName = $_[0];
    
    if($In::Opt{"OS"} eq "windows") {
        $LName = lc($LName);
    }
    if(my $TN = $In::Opt{"TargetLib"})
    {
        if($LName!~/\Q$TN\E/) {
            return 0;
        }
    }
    if($In::Opt{"TargetLibs"}
    and not $In::Opt{"TargetLibs"}{$LName}
    and not $In::Opt{"TargetLibs"}{libPart($LName, "name+ext")}) {
        return 0;
    }
    return 1;
}

sub pickType($$)
{
    my ($Tid, $LVer) = @_;
    
    if(my $Dupl = $In::ABI{$LVer}{"TypeTypedef"}{$Tid})
    {
        if(defined $In::ABI{$LVer}{"TypeInfo"}{$Dupl})
        {
            if($In::ABI{$LVer}{"TypeInfo"}{$Dupl}{"Name"} eq $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Name"})
            { # duplicate
                return 0;
            }
        }
    }
    
    my $THeader = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Header"};
    
    if(isBuiltIn($THeader)) {
        return 0;
    }
    
    if($In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Type"}!~/Class|Struct|Union|Enum|Typedef/) {
        return 0;
    }
    
    if(isAnon($In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Name"})) {
        return 0;
    }
    
    if(selfTypedef($Tid, $LVer)) {
        return 0;
    }
    
    if(not isTargetType($Tid, $LVer)) {
        return 0;
    }
    
    return 1;
}

sub isTargetType($$)
{
    my ($Tid, $LVer) = @_;
    
    if(my $THeader = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Header"})
    { # NOTE: header is defined to source if undefined (DWARF dumps)
        if(not isTargetHeader($THeader, $LVer))
        { # from target headers
            return 0;
        }
    }
    elsif(my $TSource = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Source"})
    {
        if(not isTargetSource($TSource, $LVer))
        { # from target sources
            return 0;
        }
    }
    else
    {
        return 0;
    }
    
    if(my $Name = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Name"})
    {
        if(my $Pattern = $In::Opt{"SkipInternalTypes"})
        {
            if($Name=~/($Pattern)/) {
                return 0;
            }
        }
        
        if($In::Desc{$LVer}{"SkipTypes"}{$Name}) {
            return 0;
        }
    }
    
    if($In::ABI{$LVer}{"PublicABI"})
    {
        if(isPrivateABI($Tid, $LVer)) {
            return 0;
        }
    }
    
    return 1;
}

sub selfTypedef($$)
{
    my ($TypeId, $LVer) = @_;
    my %Type = getType($TypeId, $LVer);
    if($Type{"Type"} eq "Typedef")
    {
        my %Base = getOneStepBaseType($TypeId, $LVer);
        if($Base{"Type"}=~/Class|Struct/)
        {
            if($Type{"Name"} eq $Base{"Name"}) {
                return 1;
            }
            elsif($Type{"Name"}=~/::(\w+)\Z/)
            {
                if($Type{"Name"} eq $Base{"Name"}."::".$1)
                { # QPointer<QWidget>::QPointer
                    return 1;
                }
            }
        }
    }
    return 0;
}

sub isOpaque($)
{
    my $T = $_[0];
    if(not defined $T->{"Memb"}
    and not defined $T->{"Size"})
    {
        return 1;
    }
    return 0;
}

sub isPrivateABI($$)
{
    my ($TypeId, $LVer) = @_;
    
    if($In::Opt{"CheckPrivateABI"}) {
        return 0;
    }
    
    if(defined $In::ABI{$LVer}{"TypeInfo"}{$TypeId}{"PrivateABI"}) {
        return 1;
    }
    
    return 0;
}

sub isReserved($)
{ # reserved fields == private
    my $MName = $_[0];
    
    if($In::Opt{"KeepReserved"}) {
        return 0;
    }
    
    if($MName=~/reserved|padding|f_spare/i) {
        return 1;
    }
    if($MName=~/\A[_]*(spare|pad|unused|dummy)[_\d]*\Z/i) {
        return 1;
    }
    if($MName=~/(pad\d+)/i) {
        return 1;
    }
    return 0;
}

sub specificHeader($$)
{
    my ($Header, $Spec) = @_;
    my $Name = getFilename($Header);
    
    if($Spec eq "windows")
    {# MS Windows
        return 1 if($Name=~/(\A|[._-])(win|wince|wnt)(\d\d|[._-]|\Z)/i);
        return 1 if($Name=~/([._-]w|win)(32|64)/i);
        return 1 if($Name=~/\A(Win|Windows)[A-Z]/);
        return 1 if($Name=~/\A(w|win|windows)(32|64|\.)/i);
        my @Dirs = (
            "win32",
            "win64",
            "win",
            "windows",
            "msvcrt"
        ); # /gsf-win32/
        if(my $DIRs = join("|", @Dirs)) {
            return 1 if($Header=~/[\/\\](|[^\/\\]+[._-])($DIRs)(|[._-][^\/\\]+)([\/\\]|\Z)/i);
        }
    }
    elsif($Spec eq "macos")
    { # Mac OS
        return 1 if($Name=~/(\A|[_-])mac[._-]/i);
    }
    
    return 0;
}

sub skipAlienHeader($)
{
    my $Path = $_[0];
    my $Name = getFilename($Path);
    my $Dir = getDirname($Path);
    
    if($In::Opt{"Tolerance"}=~/2/)
    { # 2 - skip internal headers
        my @Terms = (
            "p",
            "priv",
            "int",
            "impl",
            "implementation",
            "internal",
            "private",
            "old",
            "compat",
            "debug",
            "test",
            "gen"
        );
        
        my @Dirs = (
            "private",
            "priv",
            "port",
            "impl",
            "internal",
            "detail",
            "details",
            "old",
            "compat",
            "debug",
            "config",
            "compiler",
            "platform",
            "test"
        );
        
        if(my $TERMs = join("|", @Terms)) {
            return 1 if($Name=~/(\A|[._-])($TERMs)([._-]|\Z)/i);
        }
        if(my $DIRs = join("|", @Dirs)) {
            return 1 if($Dir=~/(\A|[\/\\])(|[^\/\\]+[._-])($DIRs)(|[._-][^\/\\]+)([\/\\]|\Z)/i);
        }
        
        return 1 if($Name=~/[a-z](Imp|Impl|I|P)(\.|\Z)/);
    }
    
    if($In::Opt{"Tolerance"}=~/1/)
    { # 1 - skip non-Linux headers
        if($In::Opt{"OS"} ne "windows")
        {
            if(specificHeader($Path, "windows")) {
                return 1;
            }
        }
        if($In::Opt{"OS"} ne "macos")
        {
            if(specificHeader($Path, "macos")) {
                return 1;
            }
        }
    }
    
    # valid
    return 0;
}

sub isTargetHeader($$)
{ # --header, --headers-list
    my ($H, $V) = @_;
    
    if(defined $In::Desc{$V}{"TargetHeader"})
    {
        if(defined $In::Desc{$V}{"TargetHeader"}{$H}) {
            return 1;
        }
    }
    elsif($In::ABI{$V}{"Headers"})
    {
        if(defined $In::ABI{$V}{"Headers"}{$H}) {
            return 1;
        }
    }
    
    return 0;
}

sub isTargetSource($$)
{
    my ($S, $V) = @_;
    
    if($In::ABI{$V}{"Sources"})
    {
        if(defined $In::ABI{$V}{"Sources"}{$S}) {
            return 1;
        }
    }
    
    return 0;
}

sub ignorePath($)
{
    my $Path = $_[0];
    if($Path=~/\~\Z/)
    {# skipping system backup files
        return 1;
    }
    if($Path=~/(\A|[\/\\]+)(\.(svn|git|bzr|hg)|CVS)([\/\\]+|\Z)/)
    {# skipping hidden .svn, .git, .bzr, .hg and CVS directories
        return 1;
    }
    return 0;
}

return 1;
