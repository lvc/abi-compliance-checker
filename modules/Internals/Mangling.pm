###########################################################################
# A module to mangle C++ symbols
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

my %IntrinsicMangling = (
    "void" => "v",
    "bool" => "b",
    "wchar_t" => "w",
    "char" => "c",
    "signed char" => "a",
    "unsigned char" => "h",
    "short" => "s",
    "unsigned short" => "t",
    "int" => "i",
    "unsigned int" => "j",
    "long" => "l",
    "unsigned long" => "m",
    "long long" => "x",
    "__int64" => "x",
    "unsigned long long" => "y",
    "__int128" => "n",
    "unsigned __int128" => "o",
    "float" => "f",
    "double" => "d",
    "long double" => "e",
    "__float80" => "e",
    "__float128" => "g",
    "..." => "z"
);

my %StdcxxMangling = (
    "3std"=>"St",
    "3std9allocator"=>"Sa",
    "3std12basic_string"=>"Sb",
    "3std12basic_stringIcE"=>"Ss",
    "3std13basic_istreamIcE"=>"Si",
    "3std13basic_ostreamIcE"=>"So",
    "3std14basic_iostreamIcE"=>"Sd"
);

my $DEFAULT_STD_PARMS = "std::(allocator|less|char_traits|regex_traits|istreambuf_iterator|ostreambuf_iterator)";

my %ConstantSuffixR = (
    "u"=>"unsigned int",
    "l"=>"long",
    "ul"=>"unsigned long",
    "ll"=>"long long",
    "ull"=>"unsigned long long"
);

my %OperatorMangling = (
    "~" => "co",
    "=" => "aS",
    "|" => "or",
    "^" => "eo",
    "&" => "an",#ad (addr)
    "==" => "eq",
    "!" => "nt",
    "!=" => "ne",
    "<" => "lt",
    "<=" => "le",
    "<<" => "ls",
    "<<=" => "lS",
    ">" => "gt",
    ">=" => "ge",
    ">>" => "rs",
    ">>=" => "rS",
    "()" => "cl",
    "%" => "rm",
    "[]" => "ix",
    "&&" => "aa",
    "||" => "oo",
    "*" => "ml",#de (deref)
    "++" => "pp",#
    "--" => "mm",#
    "new" => "nw",
    "delete" => "dl",
    "new[]" => "na",
    "delete[]" => "da",
    "+=" => "pL",
    "+" => "pl",#ps (pos)
    "-" => "mi",#ng (neg)
    "-=" => "mI",
    "*=" => "mL",
    "/=" => "dV",
    "&=" => "aN",
    "|=" => "oR",
    "%=" => "rM",
    "^=" => "eO",
    "/" => "dv",
    "->*" => "pm",
    "->" => "pt",#rf (ref)
    "," => "cm",
    "?" => "qu",
    "." => "dt",
    "sizeof"=> "sz"#st
);

my $MAX_CMD_ARG = 4096;
my $MAX_CPPFILT_INPUT = 50000;
my $CPPFILT_SUPPORT_FILE = undef;

my %TrName;
my %GccMangledName;
my %MangledName;

my $DisabledUnmangle_MSVC = undef;

sub mangleSymbol($$$)
{ # mangling for simple methods
  # see gcc-4.6.0/gcc/cp/mangle.c
    my ($InfoId, $Compiler, $LVer) = @_;
    if($Cache{"mangleSymbol"}{$LVer}{$InfoId}{$Compiler}) {
        return $Cache{"mangleSymbol"}{$LVer}{$InfoId}{$Compiler};
    }
    my $Mangled = "";
    if($Compiler eq "GCC") {
        $Mangled = mangleSymbol_GCC($InfoId, $LVer);
    }
    elsif($Compiler eq "MSVC") {
        $Mangled = mangleSymbol_MSVC($InfoId, $LVer);
    }
    return ($Cache{"mangleSymbol"}{$LVer}{$InfoId}{$Compiler} = $Mangled);
}

sub mangleSymbol_MSVC($$)
{ # TODO
    my ($InfoId, $LVer) = @_;
    return "";
}

sub mangleSymbol_GCC($$)
{ # see gcc-4.6.0/gcc/cp/mangle.c
    my ($InfoId, $LVer) = @_;
    
    my $SInfo = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId};
    
    my ($Mangled, $ClassId, $NameSpace) = ("_Z", 0, "");
    
    my $Return = $SInfo->{"Return"};
    my %Repl = (); # SN_ replacements
    if($ClassId = $SInfo->{"Class"})
    {
        my $MangledClass = mangleParam($ClassId, $LVer, \%Repl);
        if($MangledClass!~/\AN/) {
            $MangledClass = "N".$MangledClass;
        }
        else {
            $MangledClass=~s/E\Z//;
        }
        if($SInfo->{"Const"}) {
            $MangledClass=~s/\AN/NK/;
        }
        if($SInfo->{"Volatile"}) {
            $MangledClass=~s/\AN/NV/;
        }
        $Mangled .= $MangledClass;
    }
    elsif($NameSpace = $SInfo->{"NameSpace"})
    { # mangled by name due to the absence of structured info
        my $MangledNS = mangleNs($NameSpace, $LVer, \%Repl);
        if($MangledNS!~/\AN/) {
            $MangledNS = "N".$MangledNS;
        }
        else {
            $MangledNS=~s/E\Z//;
        }
        $Mangled .= $MangledNS;
    }
    my ($ShortName, $TmplParams) = templateBase($SInfo->{"ShortName"});
    my @TParams = ();
    if(my @TPos = sort {$a<=>$b} keys(%{$SInfo->{"TParam"}}))
    { # parsing mode
        foreach my $PPos (@TPos) {
            push(@TParams, $SInfo->{"TParam"}{$PPos}{"name"});
        }
    }
    elsif($TmplParams)
    { # remangling mode
      # support for old ABI dumps
        @TParams = sepParams($TmplParams, 0, 0);
    }
    if(my $Ctor = $SInfo->{"Constructor"})
    {
        if($Ctor ne "1") {
            $Mangled .= $Ctor;
        }
        else {
            $Mangled .= "C1";
        }
    }
    elsif(my $Dtor = $SInfo->{"Destructor"})
    {
        if($Dtor ne "1") {
            $Mangled .= $Dtor;
        }
        else {
            $Mangled .= "D0";
        }
    }
    elsif($ShortName)
    {
        if($SInfo->{"Data"})
        {
            if(not $SInfo->{"Class"}
            and isConstType($Return, $LVer))
            { # "const" global data is mangled as _ZL...
                $Mangled .= "L";
            }
        }
        if($ShortName=~/\Aoperator(\W.*)\Z/)
        {
            my $Op = $1;
            $Op=~s/\A[ ]+//g;
            if(my $OpMngl = $OperatorMangling{$Op}) {
                $Mangled .= $OpMngl;
            }
            else { # conversion operator
                $Mangled .= "cv".mangleParam(getTypeIdByName($Op, $LVer), $LVer, \%Repl);
            }
        }
        else {
            $Mangled .= length($ShortName).$ShortName;
        }
        if(@TParams)
        { # templates
            $Mangled .= "I";
            foreach my $TParam (@TParams) {
                $Mangled .= mangleTemplateParam($TParam, $LVer, \%Repl);
            }
            $Mangled .= "E";
        }
        if(not $ClassId and @TParams) {
            addSubst($ShortName, \%Repl, 0);
        }
    }
    if($ClassId or $NameSpace) {
        $Mangled .= "E";
    }
    if(@TParams)
    {
        if($Return) {
            $Mangled .= mangleParam($Return, $LVer, \%Repl);
        }
    }
    if(not $SInfo->{"Data"})
    {
        my @Params = ();
        if(defined $SInfo->{"Param"}
        and not $SInfo->{"Destructor"})
        {
            @Params = sort {$a<=>$b} keys(%{$SInfo->{"Param"}});
            
            if($SInfo->{"Class"}
            and not $SInfo->{"Static"})
            {
                if($SInfo->{"Param"}{"0"}{"name"} eq "this") {
                    shift(@Params);
                }
            }
        }
        foreach my $PPos (sort {$a<=>$b} @Params)
        { # checking parameters
            my $PTid = $SInfo->{"Param"}{$PPos}{"type"};
            $Mangled .= mangleParam($PTid, $LVer, \%Repl);
        }
        if(not @Params) {
            $Mangled .= "v";
        }
    }
    $Mangled = writeCxxSubstitution($Mangled);
    if($Mangled eq "_Z") {
        return "";
    }
    return $Mangled;
}

sub templateBase($)
{ # NOTE: std::_Vector_base<mysqlpp::mysql_type_info>::_Vector_impl
  # NOTE: operators: >>, <<
    my $Name = $_[0];
    if($Name!~/>\Z/ or $Name!~/</) {
        return $Name;
    }
    my $TParams = $Name;
    while(my $CPos = findCenter($TParams, "<"))
    { # search for the last <T>
        $TParams = substr($TParams, $CPos);
    }
    if($TParams=~s/\A<(.+)>\Z/$1/) {
        $Name=~s/<\Q$TParams\E>\Z//;
    }
    else
    { # error
        $TParams = "";
    }
    return ($Name, $TParams);
}

sub getSubNs($)
{
    my $Name = $_[0];
    my @NS = ();
    while(my $CPos = findCenter($Name, ":"))
    {
        push(@NS, substr($Name, 0, $CPos));
        $Name = substr($Name, $CPos);
        $Name=~s/\A:://;
    }
    return (join("::", @NS), $Name);
}

sub mangleNs($$$)
{
    my ($Name, $LVer, $Repl) = @_;
    if(my $Tid = $In::ABI{$LVer}{"TName_Tid"}{$Name})
    {
        my $Mangled = mangleParam($Tid, $LVer, $Repl);
        $Mangled=~s/\AN(.+)E\Z/$1/;
        return $Mangled;
        
    }
    else
    {
        my ($MangledNS, $SubNS) = ("", "");
        ($SubNS, $Name) = getSubNs($Name);
        if($SubNS) {
            $MangledNS .= mangleNs($SubNS, $LVer, $Repl);
        }
        $MangledNS .= length($Name).$Name;
        addSubst($MangledNS, $Repl, 0);
        return $MangledNS;
    }
}

sub mangleParam($$$)
{
    my ($PTid, $LVer, $Repl) = @_;
    my ($MPrefix, $Mangled) = ("", "");
    my %ReplCopy = %{$Repl};
    my %BaseType = getBaseType($PTid, $LVer);
    my $BaseType_Name = $BaseType{"Name"};
    $BaseType_Name=~s/\A(struct|union|enum) //g;
    if(not $BaseType_Name) {
        return "";
    }
    my ($ShortName, $TmplParams) = templateBase($BaseType_Name);
    my $Suffix = getBaseTypeQual($PTid, $LVer);
    while($Suffix=~s/\s*(const|volatile|restrict)\Z//g){};
    while($Suffix=~/(&|\*|const)\Z/)
    {
        if($Suffix=~s/[ ]*&\Z//) {
            $MPrefix .= "R";
        }
        if($Suffix=~s/[ ]*\*\Z//) {
            $MPrefix .= "P";
        }
        if($Suffix=~s/[ ]*const\Z//)
        {
            if($MPrefix=~/R|P/
            or $Suffix=~/&|\*/) {
                $MPrefix .= "K";
            }
        }
        if($Suffix=~s/[ ]*volatile\Z//) {
            $MPrefix .= "V";
        }
        #if($Suffix=~s/[ ]*restrict\Z//) {
            #$MPrefix .= "r";
        #}
    }
    if(my $Token = $IntrinsicMangling{$BaseType_Name}) {
        $Mangled .= $Token;
    }
    elsif($BaseType{"Type"}=~/(Class|Struct|Union|Enum)/)
    {
        my @TParams = ();
        if(my @TPos = sort {$a<=>$b} keys(%{$BaseType{"TParam"}}))
        { # parsing mode
            foreach (@TPos) {
                push(@TParams, $BaseType{"TParam"}{$_}{"name"});
            }
        }
        elsif($TmplParams)
        { # remangling mode
          # support for old ABI dumps
            @TParams = sepParams($TmplParams, 0, 0);
        }
        my $MangledNS = "";
        my ($SubNS, $SName) = getSubNs($ShortName);
        if($SubNS) {
            $MangledNS .= mangleNs($SubNS, $LVer, $Repl);
        }
        $MangledNS .= length($SName).$SName;
        if(@TParams) {
            addSubst($MangledNS, $Repl, 0);
        }
        $Mangled .= "N".$MangledNS;
        if(@TParams)
        { # templates
            $Mangled .= "I";
            foreach my $TParam (@TParams) {
                $Mangled .= mangleTemplateParam($TParam, $LVer, $Repl);
            }
            $Mangled .= "E";
        }
        $Mangled .= "E";
    }
    elsif($BaseType{"Type"}=~/(FuncPtr|MethodPtr)/)
    {
        if($BaseType{"Type"} eq "MethodPtr") {
            $Mangled .= "M".mangleParam($BaseType{"Class"}, $LVer, $Repl)."F";
        }
        else {
            $Mangled .= "PF";
        }
        $Mangled .= mangleParam($BaseType{"Return"}, $LVer, $Repl);
        my @Params = sort {$a<=>$b} keys(%{$BaseType{"Param"}});
        foreach my $Num (@Params) {
            $Mangled .= mangleParam($BaseType{"Param"}{$Num}{"type"}, $LVer, $Repl);
        }
        if(not @Params) {
            $Mangled .= "v";
        }
        $Mangled .= "E";
    }
    elsif($BaseType{"Type"} eq "FieldPtr")
    {
        $Mangled .= "M".mangleParam($BaseType{"Class"}, $LVer, $Repl);
        $Mangled .= mangleParam($BaseType{"Return"}, $LVer, $Repl);
    }
    $Mangled = $MPrefix.$Mangled; # add prefix (RPK)
    if(my $Optimized = writeSubstitution($Mangled, \%ReplCopy))
    {
        if($Mangled eq $Optimized)
        {
            if($ShortName!~/::/)
            { # remove "N ... E"
                if($MPrefix) {
                    $Mangled=~s/\A($MPrefix)N(.+)E\Z/$1$2/g;
                }
                else {
                    $Mangled=~s/\AN(.+)E\Z/$1/g;
                }
            }
        }
        else {
            $Mangled = $Optimized;
        }
    }
    addSubst($Mangled, $Repl, 1);
    return $Mangled;
}

sub mangleTemplateParam($$$)
{ # types + literals
    my ($TParam, $LVer, $Repl) = @_;
    if(my $TPTid = $In::ABI{$LVer}{"TName_Tid"}{$TParam}) {
        return mangleParam($TPTid, $LVer, $Repl);
    }
    elsif($TParam=~/\A(\d+)(\w+)\Z/)
    { # class_name<1u>::method(...)
        return "L".$IntrinsicMangling{$ConstantSuffixR{$2}}.$1."E";
    }
    elsif($TParam=~/\A\(([\w ]+)\)(\d+)\Z/)
    { # class_name<(signed char)1>::method(...)
        return "L".$IntrinsicMangling{$1}.$2."E";
    }
    elsif($TParam eq "true")
    { # class_name<true>::method(...)
        return "Lb1E";
    }
    elsif($TParam eq "false")
    { # class_name<true>::method(...)
        return "Lb0E";
    }
    else { # internal error
        return length($TParam).$TParam;
    }
}

sub addSubst($$$)
{
    my ($Value, $Repl, $Rec) = @_;
    if($Rec)
    { # subtypes
        my @Subs = ($Value);
        while($Value=~s/\A(R|P|K)//) {
            push(@Subs, $Value);
        }
        foreach (reverse(@Subs)) {
            addSubst($_, $Repl, 0);
        }
        return;
    }
    if($Value=~/\AS(\d*)_\Z/) {
        return;
    }
    $Value=~s/\AN(.+)E\Z/$1/g;
    if(defined $Repl->{$Value}) {
        return;
    }
    if(length($Value)<=1) {
        return;
    }
    if($StdcxxMangling{$Value}) {
        return;
    }
    # check for duplicates
    my $Base = $Value;
    foreach my $Type (sort {$Repl->{$a}<=>$Repl->{$b}} sort keys(%{$Repl}))
    {
        my $Num = $Repl->{$Type};
        my $Replace = macroMangle($Num);
        $Base=~s/\Q$Replace\E/$Type/;
    }
    if(my $OldNum = $Repl->{$Base})
    {
        $Repl->{$Value} = $OldNum;
        return;
    }
    my @Repls = sort {$b<=>$a} values(%{$Repl});
    if(@Repls) {
        $Repl->{$Value} = $Repls[0]+1;
    }
    else {
        $Repl->{$Value} = -1;
    }
    # register duplicates
    # upward
    $Base = $Value;
    foreach my $Type (sort {$Repl->{$a}<=>$Repl->{$b}} sort keys(%{$Repl}))
    {
        if($Base eq $Type) {
            next;
        }
        my $Num = $Repl->{$Type};
        my $Replace = macroMangle($Num);
        $Base=~s/\Q$Type\E/$Replace/;
        $Repl->{$Base} = $Repl->{$Value};
    }
}

sub macroMangle($)
{
    my $Num = $_[0];
    if($Num==-1) {
        return "S_";
    }
    else
    {
        my $Code = "";
        if($Num<10)
        { # S0_, S1_, S2_, ...
            $Code = $Num;
        }
        elsif($Num>=10 and $Num<=35)
        { # SA_, SB_, SC_, ...
            $Code = chr(55+$Num);
        }
        else
        { # S10_, S11_, S12_
            $Code = $Num-26; # 26 is length of english alphabet
        }
        return "S".$Code."_";
    }
}

sub writeCxxSubstitution($)
{
    my $Mangled = $_[0];
    if($StdcxxMangling{$Mangled}) {
        return $StdcxxMangling{$Mangled};
    }
    else
    {
        my @Repls = sort {$b cmp $a} keys(%StdcxxMangling);
        @Repls = sort {length($b)<=>length($a)} @Repls;
        foreach my $MangledType (@Repls)
        {
            my $Replace = $StdcxxMangling{$MangledType};
            #if($Mangled!~/$Replace/) {
                $Mangled=~s/N\Q$MangledType\EE/$Replace/g;
                $Mangled=~s/\Q$MangledType\E/$Replace/g;
            #}
        }
    }
    return $Mangled;
}

sub writeSubstitution($$)
{
    my ($Mangled, $Repl) = @_;
    if(defined $Repl->{$Mangled}
    and my $MnglNum = $Repl->{$Mangled}) {
        $Mangled = macroMangle($MnglNum);
    }
    else
    {
        my @Repls = keys(%{$Repl});
        
        # @Repls = sort {$Repl->{$a}<=>$Repl->{$b}} @Repls;
        # FIXME: how to apply replacements? by num or by pos
        
        @Repls = sort {length($b)<=>length($a)} sort {$b cmp $a} @Repls;
        foreach my $MangledType (@Repls)
        {
            my $Replace = macroMangle($Repl->{$MangledType});
            if($Mangled!~/$Replace/) {
                $Mangled=~s/N\Q$MangledType\EE/$Replace/g;
                $Mangled=~s/\Q$MangledType\E/$Replace/g;
            }
        }
    }
    return $Mangled;
}

sub isDefaultStd($) {
    return ($_[0]=~/\A$DEFAULT_STD_PARMS\</);
}

sub canonifyName($$)
{ # make TIFFStreamOpen(char const*, std::basic_ostream<char, std::char_traits<char> >*)
  # to be TIFFStreamOpen(char const*, std::basic_ostream<char>*)
    my ($Name, $Type) = @_;
    
    # single
    while($Name=~/([^<>,]+),\s*$DEFAULT_STD_PARMS<([^<>,]+)>\s*/ and $1 eq $3)
    {
        my $P = $1;
        $Name=~s/\Q$P\E,\s*$DEFAULT_STD_PARMS<\Q$P\E>\s*/$P/g;
    }
    
    # double
    if($Name=~/$DEFAULT_STD_PARMS/)
    {
        if($Type eq "S")
        {
            my ($ShortName, $FuncParams) = splitSignature($Name);
            
            foreach my $FParam (sepParams($FuncParams, 0, 0))
            {
                if(index($FParam, "<")!=-1)
                {
                    $FParam=~s/>([^<>]+)\Z/>/; # remove quals
                    my $FParam_N = canonifyName($FParam, "T");
                    if($FParam_N ne $FParam) {
                        $Name=~s/\Q$FParam\E/$FParam_N/g;
                    }
                }
            }
        }
        elsif($Type eq "T")
        {
            my ($ShortTmpl, $TmplParams) = templateBase($Name);
            
            my @TParams = sepParams($TmplParams, 0, 0);
            if($#TParams>=1)
            {
                my $FParam = $TParams[0];
                foreach my $Pos (1 .. $#TParams)
                {
                    my $TParam = $TParams[$Pos];
                    if($TParam=~/\A$DEFAULT_STD_PARMS<\Q$FParam\E\s*>\Z/) {
                        $Name=~s/\Q$FParam, $TParam\E\s*/$FParam/g;
                    }
                }
            }
        }
    }
    if($Type eq "S") {
        return formatName($Name, "S");
    }
    return $Name;
}

sub getUnmangled($$)
{
    if(defined $TrName{$_[1]}{$_[0]}) {
        return $TrName{$_[1]}{$_[0]};
    }
    
    return undef;
}

sub getMangled_GCC($$)
{
    if(defined $GccMangledName{$_[1]}{$_[0]}) {
        return $GccMangledName{$_[1]}{$_[0]};
    }
    
    return undef;
}

sub getMangled_MSVC($$)
{
    if(defined $MangledName{$_[1]}{$_[0]}) {
        return $MangledName{$_[1]}{$_[0]};
    }
    
    return $_[0];
}

sub translateSymbols(@)
{
    my $LVer = pop(@_);
    my (@MnglNames1, @MnglNames2, @ZNames, @UnmangledNames) = ();
    my %Versioned = ();
    
    foreach my $Symbol (sort @_)
    {
        if(index($Symbol, "_Z")==0)
        {
            push(@ZNames, $Symbol);
            if($TrName{$LVer}{$Symbol})
            { # already unmangled
                next;
            }
            if($Symbol=~s/([\@\$]+.*)\Z//) {
                $Versioned{$Symbol}{$Symbol.$1} = 1;
            }
            else {
                $Versioned{$Symbol}{$Symbol} = 1;
            }
            push(@MnglNames1, $Symbol);
        }
        elsif(index($Symbol, "?")==0)
        {
            push(@MnglNames2, $Symbol);
        }
    }
    if($#MnglNames1 > -1)
    { # GCC names
        @UnmangledNames = reverse(unmangleArray(@MnglNames1));
        foreach my $MnglName (@MnglNames1)
        {
            if(my $Unmangled = pop(@UnmangledNames))
            {
                foreach my $M (keys(%{$Versioned{$MnglName}}))
                {
                    $TrName{$LVer}{$M} = canonifyName($Unmangled, "S");
                    if(not $GccMangledName{$LVer}{$TrName{$LVer}{$M}}) {
                        $GccMangledName{$LVer}{$TrName{$LVer}{$M}} = $M;
                    }
                }
            }
        }
        
        foreach my $Symbol (@ZNames)
        {
            if(index($Symbol, "_ZTV")==0
            and $TrName{$LVer}{$Symbol}=~/vtable for (.+)/)
            { # bind class name and v-table symbol
                $In::ABI{$LVer}{"ClassVTable"}{$1} = $Symbol;
            }
        }
    }
    if($#MnglNames2 > -1)
    { # MSVC names
        @UnmangledNames = reverse(unmangleArray(@MnglNames2));
        foreach my $MnglName (@MnglNames2)
        {
            if(my $Unmangled = pop(@UnmangledNames))
            {
                $TrName{$LVer}{$MnglName} = formatName($Unmangled, "S");
                $MangledName{$LVer}{$TrName{$LVer}{$MnglName}} = $MnglName;
            }
        }
    }
    return \%{$TrName{$LVer}};
}

sub unmangleArray(@)
{
    if($_[0]=~/\A\?/)
    { # MSVC mangling
        if(defined $DisabledUnmangle_MSVC) {
            return @_;
        }
        my $UndNameCmd = getCmdPath("undname");
        if(not $UndNameCmd)
        {
            if($In::Opt{"OS"} eq "windows") {
                exitStatus("Not_Found", "can't find \"undname\"");
            }
            elsif(not defined $DisabledUnmangle_MSVC)
            {
                printMsg("WARNING", "can't find \"undname\", disable MSVC unmangling");
                $DisabledUnmangle_MSVC = 1;
                return @_;
            }
        }
        my $TmpDir = $In::Opt{"Tmp"};
        writeFile("$TmpDir/unmangle", join("\n", @_));
        return split(/\n/, `$UndNameCmd 0x8386 \"$TmpDir/unmangle\"`);
    }
    else
    { # GCC mangling
        my $CppFiltCmd = getCmdPath("c++filt");
        if(not $CppFiltCmd) {
            exitStatus("Not_Found", "can't find c++filt in PATH");
        }
        if(not defined $CPPFILT_SUPPORT_FILE)
        {
            my $Info = `$CppFiltCmd -h 2>&1`;
            $CPPFILT_SUPPORT_FILE = ($Info=~/\@<file>/);
        }
        my $NoStrip = "";
        
        if($In::Opt{"OS"}=~/macos|windows/) {
            $NoStrip = "-n";
        }
        
        if($CPPFILT_SUPPORT_FILE)
        { # new versions of c++filt can take a file
            if($#_>$MAX_CPPFILT_INPUT)
            { # c++filt <= 2.22 may crash on large files (larger than 8mb)
              # this is fixed in the oncoming version of Binutils
                my @Half = splice(@_, 0, ($#_+1)/2);
                return (unmangleArray(@Half), unmangleArray(@_))
            }
            else
            {
                my $TmpDir = $In::Opt{"Tmp"};
                writeFile("$TmpDir/unmangle", join("\n", @_));
                my $Res = `$CppFiltCmd $NoStrip \@\"$TmpDir/unmangle\"`;
                if($?==139)
                { # segmentation fault
                    printMsg("ERROR", "internal error - c++filt crashed, try to reduce MAX_CPPFILT_FILE_SIZE constant");
                }
                return split(/\n/, $Res);
            }
        }
        else
        { # old-style unmangling
            if($#_>$MAX_CMD_ARG)
            {
                my @Half = splice(@_, 0, ($#_+1)/2);
                return (unmangleArray(@Half), unmangleArray(@_))
            }
            else
            {
                my $Strings = join(" ", @_);
                my $Res = `$CppFiltCmd $NoStrip $Strings`;
                if($?==139)
                { # segmentation fault
                    printMsg("ERROR", "internal error - c++filt crashed, try to reduce MAX_COMMAND_LINE_ARGUMENTS constant");
                }
                return split(/\n/, $Res);
            }
        }
    }
}

sub debugMangling($)
{
    my $LVer = $_[0];
    
    printMsg("INFO", "Debug model mangling and unmangling ($LVer)");
    
    my %Mangled = ();
    foreach my $InfoId (keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    {
        my $SInfo = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId};
        
        if(my $Mngl = $SInfo->{"MnglName"})
        {
            if(my $Class = $SInfo->{"Class"})
            {
                if(defined $In::ABI{$LVer}{"TypeInfo"}{$Class}{"TParam"})
                { # mngl names are not equal because of default tmpl args
                    next;
                }
                
                if(index($In::ABI{$LVer}{"TypeInfo"}{$Class}{"Name"}, "...")!=-1)
                { # no info about tmpl args
                    next;
                }
            }
            
            if($Mngl=~/\A(_Z|\?)/) {
                $Mangled{$Mngl} = $InfoId;
            }
        }
    }
    
    translateSymbols(keys(%Mangled), $LVer);
    
    my $Total = keys(%Mangled);
    my ($GoodMangling, $GoodUnmangling) = (0, 0);
    
    foreach my $Mngl (sort keys(%Mangled))
    {
        my $InfoId = $Mangled{$Mngl};
        
        my $U1 = getUnmangled($Mngl, $LVer);
        my $U2 = modelUnmangled($InfoId, "GCC", $LVer);
        my $U3 = mangleSymbol($InfoId, "GCC", $LVer);
        
        if($U1 ne $U2) {
            printMsg("INFO", "Bad model unmangling:\n  Orig:  $Mngl\n  Unmgl: $U1\n  Model: $U2\n");
        }
        else {
            $GoodUnmangling += 1;
        }
        
        if($Mngl ne $U3) {
            printMsg("INFO", "Bad model mangling:\n  Orig:  $Mngl\n  Model: $U3\n");
        }
        else {
            $GoodMangling += 1;
        }
    }
    
    printMsg("INFO", "Model unmangling: $GoodUnmangling/$Total");
    printMsg("INFO", "Model mangling: $GoodMangling/$Total");
}

sub modelUnmangled($$$)
{
    my ($InfoId, $Compiler, $LVer) = @_;
    if($Cache{"modelUnmangled"}{$LVer}{$Compiler}{$InfoId}) {
        return $Cache{"modelUnmangled"}{$LVer}{$Compiler}{$InfoId};
    }
    
    my $SInfo = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId};
    
    my $PureSignature = $SInfo->{"ShortName"};
    if($SInfo->{"Destructor"}) {
        $PureSignature = "~".$PureSignature;
    }
    if(not $SInfo->{"Data"})
    {
        my (@Params, @ParamTypes) = ();
        if(defined $SInfo->{"Param"}
        and not $SInfo->{"Destructor"})
        {
            @Params = sort {$a<=>$b} keys(%{$SInfo->{"Param"}});
            
            if($SInfo->{"Class"}
            and not $SInfo->{"Static"})
            {
                if($SInfo->{"Param"}{"0"}{"name"} eq "this") {
                    shift(@Params);
                }
            }
        }
        foreach my $ParamPos (@Params)
        { # checking parameters
            my $PTid = $SInfo->{"Param"}{$ParamPos}{"type"};
            my $PTName = $In::ABI{$LVer}{"TypeInfo"}{$PTid}{"Name"};
            
            $PTName = unmangledFormat($PTName, $LVer);
            $PTName=~s/\b(restrict|register)\b//g;
            
            if($Compiler eq "MSVC") {
                $PTName=~s/\blong long\b/__int64/;
            }
            @ParamTypes = (@ParamTypes, $PTName);
        }
        if(@ParamTypes) {
            $PureSignature .= "(".join(", ", @ParamTypes).")";
        }
        else
        {
            if($Compiler eq "MSVC") {
                $PureSignature .= "(void)";
            }
            else
            { # GCC
                $PureSignature .= "()";
            }
        }
        $PureSignature = deleteKeywords($PureSignature);
    }
    if(my $ClassId = $SInfo->{"Class"})
    {
        my $ClassName = unmangledFormat($In::ABI{$LVer}{"TypeInfo"}{$ClassId}{"Name"}, $LVer);
        $PureSignature = $ClassName."::".$PureSignature;
    }
    elsif(my $NS = $SInfo->{"NameSpace"}) {
        $PureSignature = $NS."::".$PureSignature;
    }
    if($SInfo->{"Const"}) {
        $PureSignature .= " const";
    }
    if($SInfo->{"Volatile"}) {
        $PureSignature .= " volatile";
    }
    my $ShowReturn = 0;
    if($Compiler eq "MSVC"
    and $SInfo->{"Data"}) {
        $ShowReturn = 1;
    }
    elsif(index($SInfo->{"ShortName"}, "<")!=-1)
    { # template instance
        $ShowReturn = 1;
    }
    if($ShowReturn)
    { # mangled names for template function specializations include return type
        if(my $ReturnId = $SInfo->{"Return"})
        {
            my %RType = getPureType($ReturnId, $LVer);
            my $ReturnName = unmangledFormat($RType{"Name"}, $LVer);
            $PureSignature = $ReturnName." ".$PureSignature;
        }
    }
    return ($Cache{"modelUnmangled"}{$LVer}{$Compiler}{$InfoId} = formatName($PureSignature, "S"));
}

sub unmangledFormat($$)
{
    my ($Name, $LibVersion) = @_;
    $Name = uncoverTypedefs($Name, $LibVersion);
    while($Name=~s/([^\w>])(const|volatile)(,|>|\Z)/$1$3/g){};
    $Name=~s/\(\w+\)(\d)/$1/;
    return $Name;
}

sub isConstType($$)
{
    my ($TypeId, $LVer) = @_;
    my %Base = getType($TypeId, $LVer);
    while(defined $Base{"Type"} and $Base{"Type"} eq "Typedef") {
        %Base = getOneStepBaseType($Base{"Tid"}, $LVer);
    }
    return ($Base{"Type"} eq "Const");
}

return 1;
