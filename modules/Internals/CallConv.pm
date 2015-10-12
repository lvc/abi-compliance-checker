###########################################################################
# Module for ACC tool to create a model of calling conventions
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2011-2012 ROSA Laboratory
# Copyright (C) 2012-2015 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux, FreeBSD and Mac OS X
#    x86 - System V ABI Intel386 Architecture Processor Supplement
#    x86_64 - System V ABI AMD64 Architecture Processor Supplement
#
#  MS Windows
#    x86 - MSDN Argument Passing and Naming Conventions
#    x86_64 - MSDN x64 Software Conventions
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

my $BYTE = 8;

my %UsedReg = ();
my %UsedStack = ();

my %IntAlgn = (
    "x86"=>{
        "double"=>4,
        "long double"=>4
    }
);

sub classifyType($$$$$)
{
    my ($Tid, $TInfo, $Arch, $System, $Word) = @_;
    my %Type = get_PureType($Tid, $TInfo);
    my %Classes = ();
    if($Type{"Name"} eq "void")
    {
        $Classes{0}{"Class"} = "VOID";
        return %Classes;
    }
    if($System=~/\A(unix|linux|macos|freebsd)\Z/)
    { # GCC
        if($Arch eq "x86")
        {
            if(isFloat($Type{"Name"})) {
                $Classes{0}{"Class"} = "FLOAT";
            }
            elsif($Type{"Type"}=~/Intrinsic|Enum|Pointer|Ptr/) {
                $Classes{0}{"Class"} = "INTEGRAL";
            }
            else { # Struct, Class, Union
                $Classes{0}{"Class"} = "MEMORY";
            }
        }
        elsif($Arch eq "x86_64")
        {
            if($Type{"Type"}=~/Enum|Pointer|Ptr/
            or isScalar($Type{"Name"})
            or $Type{"Name"}=~/\A(_Bool|bool)\Z/) {
                $Classes{0}{"Class"} = "INTEGER";
            }
            elsif($Type{"Name"} eq "__int128"
            or $Type{"Name"} eq "unsigned __int128")
            {
                $Classes{0}{"Class"} = "INTEGER";
                $Classes{1}{"Class"} = "INTEGER";
            }
            elsif($Type{"Name"}=~/\A(float|double|_Decimal32|_Decimal64|__m64)\Z/) {
                $Classes{0}{"Class"} = "SSE";
            }
            elsif($Type{"Name"}=~/\A(__float128|_Decimal128|__m128)\Z/)
            {
                $Classes{0}{"Class"} = "SSE";
                $Classes{8}{"Class"} = "SSEUP";
            }
            elsif($Type{"Name"} eq "__m256")
            {
                $Classes{0}{"Class"} = "SSE";
                $Classes{24}{"Class"} = "SSEUP";
            }
            elsif($Type{"Name"} eq "long double")
            {
                $Classes{0}{"Class"} = "X87";
                $Classes{8}{"Class"} = "X87UP";
            }
            elsif($Type{"Name"}=~/\Acomplex (float|double)\Z/) {
                $Classes{0}{"Class"} = "MEMORY";
            }
            elsif($Type{"Name"} eq "complex long double") {
                $Classes{0}{"Class"} = "COMPLEX_X87";
            }
            elsif($Type{"Type"}=~/Struct|Class|Union|Array/)
            {
                if($Type{"Size"}>4*8) {
                    $Classes{0}{"Class"} = "MEMORY";
                }
                else {
                    %Classes = classifyAggregate($Tid, $TInfo, $Arch, $System, $Word);
                }
            }
            else {
                $Classes{0}{"Class"} = "MEMORY";
            }
        }
        elsif($Arch eq "arm")
        {
        }
    }
    elsif($System eq "windows")
    { # MS C++ Compiler
        if($Arch eq "x86")
        {
            if(isFloat($Type{"Name"})) {
                $Classes{0}{"Class"} = "FLOAT";
            }
            elsif($Type{"Type"}=~/Intrinsic|Enum|Pointer|Ptr/) {
                $Classes{0}{"Class"} = "INTEGRAL";
            }
            elsif($Type{"Type"}=~/\A(Struct|Union)\Z/ and $Type{"Size"}<=8) {
                $Classes{0}{"Class"} = "POD";
            }
            else { # Struct, Class, Union
                $Classes{0}{"Class"} = "MEMORY";
            }
        }
        elsif($Arch eq "x86_64")
        {
            if($Type{"Name"}=~/\A(float|double|long double)\Z/) {
                $Classes{0}{"Class"} = "FLOAT";
            }
            elsif($Type{"Name"}=~/\A__m128(|i|d)\Z/) {
                $Classes{0}{"Class"} = "M128";
            }
            elsif(isScalar($Type{"Name"})
            or $Type{"Type"}=~/Enum|Pointer|Ptr/
            or $Type{"Name"}=~/\A(_Bool|bool)\Z/
            or ($Type{"Type"}=~/\A(Struct|Union)\Z/ and $Type{"Size"}<=8)
            or $Type{"Name"} eq "__m64") {
                $Classes{0}{"Class"} = "INTEGRAL";
            }
            else {
                $Classes{0}{"Class"} = "MEMORY";
            }
        }
    }
    return %Classes;
}

sub classifyAggregate($$$$$)
{
    my ($Tid, $TInfo, $Arch, $System, $Word) = @_;
    my %Type = get_PureType($Tid, $TInfo);
    my %Group = ();
    my $GroupID = 0;
    my %Classes = ();
    my %Offsets = ();
    if($Type{"Type"} eq "Array")
    {
        my %Base = get_OneStep_BaseType($Tid, $TInfo);
        my %BaseType = get_PureType($Base{"Tid"}, $TInfo);
        my $Pos = 0;
        my $Max = 0;
        if(my $BSize = $BaseType{"Size"}) {
            $Max = ($Type{"Size"}/$BSize) - 1;
        }
        foreach my $Pos (0 .. $Max)
        {
            # if($TInfo->{1}{"Name"} eq "void")
            # { # DWARF ABI Dump
            #     $Type{"Memb"}{$Pos}{"offset"} = $Type{"Size"}/($Max+1);
            # }
            $Type{"Memb"}{$Pos}{"algn"} = getAlignment_Model($BaseType{"Tid"}, $TInfo, $Arch);
            $Type{"Memb"}{$Pos}{"type"} = $BaseType{"Tid"};
            $Type{"Memb"}{$Pos}{"name"} = "[$Pos]";
        }
    }
    if($Type{"Type"} eq "Union")
    {
        foreach my $Pos (keys(%{$Type{"Memb"}}))
        {
            $Offsets{$Pos} = $Pos;
            $Group{0}{$Pos} = 1;
        }
    }
    else
    { # Struct, Class
        foreach my $Pos (keys(%{$Type{"Memb"}}))
        {
            my $Offset = getOffset($Pos, \%Type, $TInfo, $Arch, $Word)/$BYTE;
            $Offsets{$Pos} = $Offset;
            my $GroupOffset = int($Offset/$Word)*$Word;
            $Group{$GroupOffset}{$Pos} = 1;
        }
    }
    foreach my $GroupOffset (sort {int($a)<=>int($b)} (keys(%Group)))
    {
        my %GroupClasses = ();
        foreach my $Pos (sort {int($a)<=>int($b)} (keys(%{$Group{$GroupOffset}})))
        { # split the field into the classes
            my $MTid = $Type{"Memb"}{$Pos}{"type"};
            my $MName = $Type{"Memb"}{$Pos}{"name"};
            my %SubClasses = classifyType($MTid, $TInfo, $Arch, $System, $Word);
            foreach my $Offset (sort {int($a)<=>int($b)} keys(%SubClasses))
            {
                if(defined $SubClasses{$Offset}{"Elems"})
                {
                    foreach (keys(%{$SubClasses{$Offset}{"Elems"}})) {
                        $SubClasses{$Offset}{"Elems"}{$_} = joinFields($MName, $SubClasses{$Offset}{"Elems"}{$_});
                    }
                }
                else {
                    $SubClasses{$Offset}{"Elems"}{0} = $MName;
                }
            }
            
            # add to the group
            foreach my $Offset (sort {int($a)<=>int($b)} keys(%SubClasses)) { 
                $GroupClasses{$Offsets{$Pos}+$Offset} = $SubClasses{$Offset};
            }
        }
        
        # merge classes in the group
        my %MergeGroup = ();
        
        foreach my $Offset (sort {int($a)<=>int($b)} keys(%GroupClasses)) {
            $MergeGroup{int($Offset/$Word)}{$Offset} = $GroupClasses{$Offset};
        }
        
        foreach my $Offset (sort {int($a)<=>int($b)} keys(%MergeGroup)) {
            while(postMerger($Arch, $System, $MergeGroup{$Offset})) { };
        }
        
        %GroupClasses = ();
        foreach my $M_Offset (sort {int($a)<=>int($b)} keys(%MergeGroup))
        {
            foreach my $Offset (sort {int($a)<=>int($b)} keys(%{$MergeGroup{$M_Offset}}))
            {
                $GroupClasses{$Offset} = $MergeGroup{$M_Offset}{$Offset};
            }
        }
        
        # add to the result list of classes
        foreach my $Offset (sort {int($a)<=>int($b)} keys(%GroupClasses))
        {
            if($Type{"Type"} eq "Union")
            {
                foreach my $P (keys(%{$GroupClasses{$Offset}{"Elems"}}))
                {
                    if($P!=0) {
                        delete($GroupClasses{$Offset}{"Elems"}{$P});
                    }
                }
            }
            $Classes{$Offset} = $GroupClasses{$Offset};
        }
    }
    
    return %Classes;
}

sub postMerger($$$)
{
    my ($Arch, $System, $PreClasses) = @_;
    my @Offsets = sort {int($a)<=>int($b)} keys(%{$PreClasses});
    if($#Offsets==0) {
        return 0;
    }
    my %PostClasses = ();
    my $Num = 0;
    my $Merged = 0;
    while($Num<=$#Offsets-1)
    {
        my $Offset1 = $Offsets[$Num];
        my $Offset2 = $Offsets[$Num+1];
        my $Class1 = $PreClasses->{$Offset1}{"Class"};
        my $Class2 = $PreClasses->{$Offset2}{"Class"};
        my $ResClass = "";
        if($System=~/\A(unix|linux|macos|freebsd)\Z/)
        { # GCC
            if($Arch eq "x86_64")
            {
                if($Class1 eq $Class2) {
                    $ResClass = $Class1;
                }
                elsif($Class1 eq "MEMORY"
                or $Class2 eq "MEMORY") {
                    $ResClass = "MEMORY";
                }
                elsif($Class1 eq "INTEGER"
                or $Class2 eq "INTEGER") {
                    $ResClass = "INTEGER";
                }
                elsif($Class1=~/X87/
                or $Class2=~/X87/) {
                    $ResClass = "MEMORY";
                }
                else {
                    $ResClass = "SSE";
                }
            }
        }
        if($ResClass)
        { # combine
            $PostClasses{$Offset1}{"Class"} = $ResClass;
            foreach (keys(%{$PreClasses->{$Offset1}{"Elems"}})) {
                $PostClasses{$Offset1}{"Elems"}{$Offset1+$_} = $PreClasses->{$Offset1}{"Elems"}{$_};
            }
            foreach (keys(%{$PreClasses->{$Offset2}{"Elems"}})) {
                $PostClasses{$Offset1}{"Elems"}{$Offset2+$_} = $PreClasses->{$Offset2}{"Elems"}{$_};
            }
            $Merged = 1;
        }
        else
        { # save unchanged
            $PostClasses{$Offset1} = $PreClasses->{$Offset1};
            $PostClasses{$Offset2} = $PreClasses->{$Offset2};
        }
        $Num += 2;
    }
    if($Num==$#Offsets) {
        $PostClasses{$Offsets[$Num]} = $PreClasses->{$Offsets[$Num]};
    }
    %{$PreClasses} = %PostClasses;
    return $Merged;
}

sub callingConvention_R_Model($$$$$$) {
    return callingConvention_R_I_Model(@_, 1);
}

sub joinFields($$)
{
    my ($F1, $F2) = @_;
    if(substr($F2, 0, 1) eq "[")
    { # array elements
        return $F1.$F2;
    }
    else { # fields
        return $F1.".".$F2;
    }
}

sub callingConvention_R_I_Model($$$$$$)
{
    my ($SInfo, $TInfo, $Arch, $System, $Word, $Target) = @_;
    my %Conv = ();
    my $RTid = $SInfo->{"Return"};
    my %Type = get_PureType($RTid, $TInfo);
    
    if($Target) {
        %UsedReg = ();
    }
    
    my %UsedReg_Copy = %UsedReg;
    
    my %Classes = classifyType($RTid, $TInfo, $Arch, $System, $Word);
    
    foreach my $Offset (sort {int($a)<=>int($b)} keys(%Classes))
    {
        my $Elems = undef;
        if(defined $Classes{$Offset}{"Elems"})
        {
            foreach (keys(%{$Classes{$Offset}{"Elems"}})) {
                $Classes{$Offset}{"Elems"}{$_} = joinFields(".result", $Classes{$Offset}{"Elems"}{$_});
            }
            $Elems = $Classes{$Offset}{"Elems"};
        }
        else {
            $Elems = { 0 => ".result" };
        }
        
        my $CName = $Classes{$Offset}{"Class"};
        
        if($CName eq "VOID") {
            next;
        }
        
        if($System=~/\A(unix|linux|macos|freebsd)\Z/)
        { # GCC
            if($Arch eq "x86")
            {
                if($CName eq "FLOAT")
                { # x87 register
                    useRegister("st0", "f", $Elems, $SInfo);
                }
                elsif($CName eq "INTEGRAL")
                {
                    useRegister("eax", "f", $Elems, $SInfo);
                }
                elsif($CName eq "MEMORY") {
                    pushStack_R($SInfo, $Word);
                }
            }
            elsif($Arch eq "x86_64")
            {
                my @INT = ("rax", "rdx");
                my @SSE = ("xmm0", "xmm1");
                if($CName eq "INTEGER")
                {
                    if(my $R = getLastAvailable($SInfo, "f", @INT))
                    {
                        useRegister($R, "f", $Elems, $SInfo);
                    }
                    else
                    { # revert registers
                      # pass as MEMORY
                        %UsedReg = %UsedReg_Copy;
                        useHidden($SInfo, $Arch, $System, $Word);
                        $Conv{"Hidden"} = 1;
                        last;
                    }
                }
                elsif($CName eq "SSE")
                {
                    if(my $R = getLastAvailable($SInfo, "8l", @SSE))
                    {
                        useRegister($R, "8l", $Elems, $SInfo);
                    }
                    else
                    {
                        %UsedReg = %UsedReg_Copy;
                        useHidden($SInfo, $Arch, $System, $Word);
                        $Conv{"Hidden"} = 1;
                        last;
                    }
                }
                elsif($CName eq "SSEUP")
                {
                    if(my $R = getLastUsed($SInfo, "xmm0", "xmm1"))
                    {
                        useRegister($R, "8h", $Elems, $SInfo);
                    }
                    else
                    {
                        %UsedReg = %UsedReg_Copy;
                        useHidden($SInfo, $Arch, $System, $Word);
                        $Conv{"Hidden"} = 1;
                        last;
                    }
                }
                elsif($CName eq "X87")
                {
                    useRegister("st0", "8l", $Elems, $SInfo);
                }
                elsif($CName eq "X87UP")
                {
                    useRegister("st0", "8h", $Elems, $SInfo);
                }
                elsif($CName eq "COMPLEX_X87")
                {
                    useRegister("st0", "f", $Elems, $SInfo);
                    useRegister("st1", "f", $Elems, $SInfo);
                }
                elsif($CName eq "MEMORY")
                {
                    useHidden($SInfo, $Arch, $System, $Word);
                    $Conv{"Hidden"} = 1;
                    last;
                }
            }
            elsif($Arch eq "arm")
            { # TODO
            }
        }
        elsif($System eq "windows")
        { # MS C++ Compiler
            if($Arch eq "x86")
            {
                if($CName eq "FLOAT")
                {
                    useRegister("fp0", "f", $Elems, $SInfo);
                }
                elsif($CName eq "INTEGRAL")
                {
                    useRegister("eax", "f", $Elems, $SInfo);
                }
                elsif($CName eq "POD")
                {
                    useRegister("eax", "f", $Elems, $SInfo);
                    useRegister("edx", "f", $Elems, $SInfo);
                }
                elsif($CName eq "MEMORY" or $CName eq "M128")
                {
                    useHidden($SInfo, $Arch, $System, $Word);
                    $Conv{"Hidden"} = 1;
                }
            }
            elsif($Arch eq "x86_64")
            {
                if($CName eq "FLOAT" or $CName eq "M128")
                {
                    useRegister("xmm0", "f", $Elems, $SInfo);
                }
                elsif($CName eq "INTEGRAL")
                {
                    useRegister("eax", "f", $Elems, $SInfo);
                }
                elsif($CName eq "MEMORY")
                {
                    useHidden($SInfo, $Arch, $System, $Word);
                    $Conv{"Hidden"} = 1;
                }
            }
        }
    }
    
    
    if(my %Regs = usedBy(".result", $SInfo))
    {
        $Conv{"Method"} = "reg";
        $Conv{"Registers"} = join(", ", sort(keys(%Regs)));
    }
    elsif(my %Regs = usedBy(".result_ptr", $SInfo))
    {
        $Conv{"Method"} = "reg";
        $Conv{"Registers"} = join(", ", sort(keys(%Regs)));
    }
    
    if(not $Conv{"Method"})
    { # unknown
        if($Type{"Name"} ne "void")
        {
            $Conv{"Method"} = "stack";
            $Conv{"Hidden"} = 1;
        }
    }
    
    return %Conv;
}

sub usedBy($$)
{
    my ($Name, $SInfo) = @_;
    my %Regs = ();
    foreach my $Reg (sort keys(%{$UsedReg{$SInfo}}))
    {
        foreach my $Size (sort keys(%{$UsedReg{$SInfo}{$Reg}}))
        {
            foreach my $Offset (sort keys(%{$UsedReg{$SInfo}{$Reg}{$Size}}))
            {
                if($UsedReg{$SInfo}{$Reg}{$Size}{$Offset}=~/\A\Q$Name\E(\.|\Z)/) {
                    $Regs{$Reg} = 1;
                }
            }
        }
    }
    return %Regs;
}

sub useHidden($$$$)
{
    my ($SInfo, $Arch, $System, $Word) = @_;
    if($System=~/\A(unix|linux|macos|freebsd)\Z/)
    { # GCC
        if($Arch eq "x86") {
            pushStack_R($SInfo, $Word);
        }
        elsif($Arch eq "x86_64")
        {
            my $Elems = { 0 => ".result_ptr" };
            useRegister("rdi", "f", $Elems, $SInfo);
        }
    }
    elsif($System eq "windows")
    { # MS C++ Compiler
        if($Arch eq "x86") {
            pushStack_R($SInfo, $Word);
        }
        elsif($Arch eq "x86_64")
        {
            my $Elems = { 0 => ".result_ptr" };
            useRegister("rcx", "f", $Elems, $SInfo);
        }
    }
}

sub pushStack_P($$$$)
{
    my ($SInfo, $Pos, $TInfo, $StackAlgn) = @_;
    my $PTid = $SInfo->{"Param"}{$Pos}{"type"};
    my $PName = $SInfo->{"Param"}{$Pos}{"name"};
    
    if(my $Offset = $SInfo->{"Param"}{$Pos}{"offset"})
    { # DWARF ABI Dump
        return pushStack_Offset($SInfo, $Offset, $TInfo->{$PTid}{"Size"}, { 0 => $PName });
    }
    else
    {
        my $Alignment = $SInfo->{"Param"}{$Pos}{"algn"};
        if($Alignment<$StackAlgn) {
            $Alignment = $StackAlgn;
        }
        return pushStack($SInfo, $Alignment, $TInfo->{$PTid}{"Size"}, { 0 => $PName });
    }
}

sub pushStack_R($$)
{
    my ($SInfo, $Word) = @_;
    return pushStack($SInfo, $Word, $Word, { 0 => ".result_ptr" });
}

sub pushStack_C($$$)
{
    my ($SInfo, $Class, $TInfo) = @_;
    return pushStack($SInfo, $Class->{"Algn"}, $Class->{"Size"}, $Class->{"Elems"});
}

sub pushStack($$$$)
{
    my ($SInfo, $Algn, $Size, $Elem) = @_;
    my $Offset = 0;
    if(my @Offsets = sort {int($a)<=>int($b)} keys(%{$UsedStack{$SInfo}}))
    {
        $Offset = $Offsets[$#Offsets];
        $Offset += $UsedStack{$SInfo}{$Offset}{"Size"};
        $Offset += getPadding($Offset, $Algn);
    }
    return pushStack_Offset($SInfo, $Offset, $Size, $Elem);
}

sub pushStack_Offset($$$$)
{
    my ($SInfo, $Offset, $Size, $Elem) = @_;
    my %Info = (
        "Size" => $Size,
        "Elem" => $Elem
    );
    $UsedStack{$SInfo}{$Offset} = \%Info;
    return $Offset;
}

sub useRegister($$$$)
{
    my ($R, $Offset, $Elems, $SInfo) = @_;
    if(defined $UsedReg{$SInfo}{$R})
    {
        if(defined $UsedReg{$SInfo}{$R}{$Offset})
        { # busy
            return 0;
        }
    }
    $UsedReg{$SInfo}{$R}{$Offset}=$Elems;
    return $R;
}

sub getLastAvailable(@)
{
    my $SInfo = shift(@_);
    my $Offset = shift(@_);
    my $Pos = 0;
    foreach (@_)
    {
        if(not defined $UsedReg{$SInfo}{$_}) {
            return $_;
        }
        elsif(not defined $UsedReg{$SInfo}{$_}{$Offset}) {
            return $_;
        }
    }
    return undef;
}

sub getLastUsed(@)
{
    my $SInfo = shift(@_);
    my $Pos = 0;
    foreach (@_)
    {
        if(not defined $UsedReg{$SInfo}{$_})
        {
            if($Pos>0) {
                return @_[$Pos-1];
            }
            else {
                return @_[0];
            }
        }
        $Pos+=1;
    }
    return undef;
}

sub callingConvention_P_Model($$$$$$) {
    return callingConvention_P_I_Model(@_, 1);
}

sub callingConvention_P_I_Model($$$$$$$)
{ # calling conventions for different compilers and operating systems
    my ($SInfo, $Pos, $TInfo, $Arch, $System, $Word, $Target) = @_;
    my %Conv = ();
    my $ParamTypeId = $SInfo->{"Param"}{$Pos}{"type"};
    my $PName = $SInfo->{"Param"}{$Pos}{"name"};
    my %Type = get_PureType($ParamTypeId, $TInfo);
    
    if($Target)
    {
        %UsedReg = ();
        
        # distribute return value
        if(my $RTid = $SInfo->{"Return"}) {
            callingConvention_R_I_Model($SInfo, $TInfo, $Arch, $System, $Word, 0);
        }
        # distribute other parameters
        if($Pos>0)
        {
            my %PConv = ();
            my $PPos = 0;
            while($PConv{"Next"} ne $Pos)
            {
                %PConv = callingConvention_P_I_Model($SInfo, $PPos++, $TInfo, $Arch, $System, $Word, 0);
                if(not $PConv{"Next"}) {
                    last;
                }
            }
        }
    }
    
    my %UsedReg_Copy = %UsedReg;
    
    my %Classes = classifyType($ParamTypeId, $TInfo, $Arch, $System, $Word);
    
    my $Error = 0;
    foreach my $Offset (sort {int($a)<=>int($b)} keys(%Classes))
    {
        my $Elems = undef;
        if(defined $Classes{$Offset}{"Elems"})
        {
            foreach (keys(%{$Classes{$Offset}{"Elems"}})) {
                $Classes{$Offset}{"Elems"}{$_} = joinFields($PName, $Classes{$Offset}{"Elems"}{$_});
            }
            $Elems = $Classes{$Offset}{"Elems"};
        }
        else {
            $Elems = { 0 => $PName };
        }
        
        my $CName = $Classes{$Offset}{"Class"};
        
        if($CName eq "VOID") {
            next;
        }
        
        if($System=~/\A(unix|linux|macos|freebsd)\Z/)
        { # GCC
            if($Arch eq "x86")
            {
                pushStack_P($SInfo, $Pos, $TInfo, $Word);
                last;
            }
            elsif($Arch eq "x86_64")
            {
                my @INT = ("rdi", "rsi", "rdx", "rcx", "r8", "r9");
                my @SSE = ("xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7");
                
                if($CName eq "INTEGER")
                {
                    if(my $R = getLastAvailable($SInfo, "f", @INT)) {
                        useRegister($R, "f", $Elems, $SInfo);
                    }
                    else
                    { # revert registers and
                      # push the argument on the stack
                        %UsedReg = %UsedReg_Copy;
                        pushStack_P($SInfo, $Pos, $TInfo, $Word);
                        last;
                    }
                }
                elsif($CName eq "SSE")
                {
                    if(my $R = getLastAvailable($SInfo, "8l", @SSE)) {
                        useRegister($R, "8l", $Elems, $SInfo);
                    }
                    else
                    {
                        %UsedReg = %UsedReg_Copy;
                        pushStack_P($SInfo, $Pos, $TInfo, $Word);
                        last;
                    }
                }
                elsif($CName eq "SSEUP")
                {
                    if(my $R = getLastUsed($SInfo, @SSE)) {
                        useRegister($R, "8h", $Elems, $SInfo);
                    }
                    else
                    {
                        %UsedReg = %UsedReg_Copy;
                        pushStack_P($SInfo, $Pos, $TInfo, $Word);
                        last;
                    }
                }
                elsif($CName=~/X87|MEMORY/)
                { # MEMORY, X87, X87UP, COMPLEX_X87
                    pushStack_P($SInfo, $Pos, $TInfo, $Word);
                    last;
                }
                else
                {
                    pushStack_P($SInfo, $Pos, $TInfo, $Word);
                    last;
                }
            }
            elsif($Arch eq "arm")
            { # Procedure Call Standard for the ARM Architecture
              # TODO
                pushStack_P($SInfo, $Pos, $TInfo, $Word);
                last;
            }
            else
            { # TODO
                pushStack_P($SInfo, $Pos, $TInfo, $Word);
                last;
            }
        }
        elsif($System eq "windows")
        { # MS C++ Compiler
            if($Arch eq "x86")
            {
                pushStack_P($SInfo, $Pos, $TInfo, $Word);
                last;
            }
            elsif($Arch eq "x86_64")
            {
                if($Pos<=3)
                {
                    if($CName eq "FLOAT")
                    {
                        useRegister("xmm".$Pos, "8l", $Elems, $SInfo);
                    }
                    elsif($CName eq "INTEGRAL")
                    {
                        if($Pos==0) {
                            useRegister("rcx", "f", $Elems, $SInfo);
                        }
                        elsif($Pos==1) {
                            useRegister("rdx", "f", $Elems, $SInfo);
                        }
                        elsif($Pos==2) {
                            useRegister("r8", "f", $Elems, $SInfo);
                        }
                        elsif($Pos==3) {
                            useRegister("r9", "f", $Elems, $SInfo);
                        }
                        else
                        {
                            pushStack_P($SInfo, $Pos, $TInfo, $Word);
                            last;
                        }
                    }
                    else
                    {
                        pushStack_P($SInfo, $Pos, $TInfo, $Word);
                        last;
                    }
                }
                else
                {
                    pushStack_P($SInfo, $Pos, $TInfo, $Word);
                    last;
                }
            }
        }
        else
        { # TODO
            pushStack_P($SInfo, $Pos, $TInfo, $Word);
            last;
        }
    }
    
    if(my %Regs = usedBy($PName, $SInfo))
    {
        $Conv{"Method"} = "reg";
        $Conv{"Registers"} = join(", ", sort(keys(%Regs)));
    }
    else
    {
        if($Type{"Name"} ne "void") {
            $Conv{"Method"} = "stack";
        }
    }
    
    if(defined $SInfo->{"Param"}{$Pos+1})
    { # TODO
        $Conv{"Next"} = $Pos+1;
    }
    
    return %Conv;
}

sub getAlignment_Model($$$)
{
    my ($Tid, $TInfo, $Arch) = @_;
    
    if(not $Tid)
    { # incomplete ABI dump
        return 0;
    }
    
    if(defined $TInfo->{$Tid}{"Algn"}) {
        return $TInfo->{$Tid}{"Algn"};
    }
    else
    {
        if($TInfo->{$Tid}{"Type"}=~/Struct|Class|Union|MethodPtr/)
        {
            if(defined $TInfo->{$Tid}{"Memb"})
            {
                my $Max = 0;
                foreach my $Pos (keys(%{$TInfo->{$Tid}{"Memb"}}))
                {
                    my $Algn = $TInfo->{$Tid}{"Memb"}{$Pos}{"algn"};
                    if(not $Algn) {
                        $Algn = getAlignment_Model($TInfo->{$Tid}{"Memb"}{$Pos}{"type"}, $TInfo, $Arch);
                    }
                    if($Algn>$Max) {
                        $Max = $Algn;
                    }
                }
                return $Max;
            }
            return 0;
        }
        elsif($TInfo->{$Tid}{"Type"} eq "Array")
        {
            my %Base = get_OneStep_BaseType($Tid, $TInfo);
            
            if($Base{"Tid"} eq $Tid)
            { # emergency exit
                return 0;
            }
            
            return getAlignment_Model($Base{"Tid"}, $TInfo, $Arch);
        }
        elsif($TInfo->{$Tid}{"Type"}=~/Intrinsic|Enum|Pointer|FuncPtr/)
        { # model
            return getInt_Algn($Tid, $TInfo, $Arch);
        }
        else
        {
            my %PureType = get_PureType($Tid, $TInfo);
            
            if($PureType{"Tid"} eq $Tid)
            { # emergency exit
                return 0;
            }
            
            return getAlignment_Model($PureType{"Tid"}, $TInfo, $Arch);
        }
    }
}

sub getInt_Algn($$$)
{
    my ($Tid, $TInfo, $Arch) = @_;
    my $Name = $TInfo->{$Tid}{"Name"};
    if(my $Algn = $IntAlgn{$Arch}{$Name}) {
        return $Algn;
    }
    else
    {
        my $Size = $TInfo->{$Tid}{"Size"};
        if($Arch eq "x86_64")
        { # x86_64: sizeof==alignment
            return $Size;
        }
        elsif($Arch eq "arm")
        {
            if($Size>8)
            { # 128-bit vector (16)
                return 8;
            }
            return $Size;
        }
        elsif($Arch eq "x86")
        {
            if($Size>4)
            { # "double" (8) and "long double" (12)
                return 4;
            }
            return $Size;
        }
        return $Size;
    }
}

sub getAlignment($$$$$)
{
    my ($Pos, $TypePtr, $TInfo, $Arch, $Word) = @_;
    my $Tid = $TypePtr->{"Memb"}{$Pos}{"type"};
    my %Type = get_PureType($Tid, $TInfo);
    my $Computed = $TypePtr->{"Memb"}{$Pos}{"algn"};
    my  $Alignment = 0;
    
    if(my $BSize = $TypePtr->{"Memb"}{$Pos}{"bitfield"})
    { # bitfields
        if($Computed)
        { # real in bits
            $Alignment = $Computed;
        }
        else
        { # model
            if($BSize eq $Type{"Size"}*$BYTE)
            {
                $Alignment = $BSize;
            }
            else {
                $Alignment = 1;
            }
        }
        return ($Alignment, $BSize);
    }
    else
    { # other fields
        if($Computed)
        { # real in bytes
            $Alignment = $Computed*$BYTE;
        }
        else
        { # model
            $Alignment = getAlignment_Model($Tid, $TInfo, $Arch)*$BYTE;
        }
        return ($Alignment, $Type{"Size"}*$BYTE);
    }
}

sub getOffset($$$$$)
{ # offset of the field including padding
    my ($FieldPos, $TypePtr, $TInfo, $Arch, $Word) = @_;
    
    if($TypePtr->{"Type"} eq "Union") {
        return 0;
    }
    
    # if((my $Off = $TypePtr->{"Memb"}{$FieldPos}{"offset"}) ne "")
    # { # DWARF ABI Dump (generated by the ABI Dumper tool)
    #    return $Off*$BYTE;
    # }
    
    my $Offset = 0;
    my $Buffer=0;
    
    foreach my $Pos (0 .. keys(%{$TypePtr->{"Memb"}})-1)
    {
        my ($Alignment, $MSize) = getAlignment($Pos, $TypePtr, $TInfo, $Arch, $Word);
        
        if(not $Alignment)
        { # support for old ABI dumps
            if($MSize=~/\A(8|16|32|64)\Z/)
            {
                if($Buffer+$MSize<$Word*$BYTE)
                {
                    $Alignment = 1;
                    $Buffer += $MSize;
                }
                else
                {
                    $Alignment = $MSize;
                    $Buffer = 0;
                }
            }
            else
            {
                $Alignment = 1;
                $Buffer += $MSize;
            }
        }
        
        # padding
        $Offset += getPadding($Offset, $Alignment);
        if($Pos==$FieldPos)
        { # after the padding
          # before the field
            return $Offset;
        }
        $Offset += $MSize;
    }
    return $FieldPos; # if something is going wrong
}

sub getPadding($$)
{
    my ($Offset, $Alignment) = @_;
    my $Padding = 0;
    if($Offset % $Alignment!=0)
    { # not aligned, add padding
        $Padding = $Alignment - $Offset % $Alignment;
    }
    return $Padding;
}

sub isMemPadded($$$$$$)
{ # check if the target field can be added/removed/changed
  # without shifting other fields because of padding bits
    my ($FieldPos, $Size, $TypePtr, $Skip, $TInfo, $Arch, $Word) = @_;
    return 0 if($FieldPos==0);
    delete($TypePtr->{"Memb"}{""});
    my $Offset = 0;
    my (%Alignment, %MSize) = ();
    my $MaxAlgn = 0;
    my $End = keys(%{$TypePtr->{"Memb"}})-1;
    my $NextField = $FieldPos+1;
    foreach my $Pos (0 .. $End)
    {
        if($Skip and $Skip->{$Pos})
        { # skip removed/added fields
            if($Pos > $FieldPos)
            { # after the target
                $NextField += 1;
                next;
            }
        }
        ($Alignment{$Pos}, $MSize{$Pos}) = getAlignment($Pos, $TypePtr, $TInfo, $Arch, $Word);
        
        if(not $Alignment{$Pos})
        { # emergency exit
            return 0;
        }
        
        if($Alignment{$Pos}>$MaxAlgn) {
            $MaxAlgn = $Alignment{$Pos};
        }
        if($Pos==$FieldPos)
        {
            if($Size==-1)
            { # added/removed fields
                if($Pos!=$End)
                { # skip target field and see
                  # if enough padding will be
                  # created on the next step
                  # to include this field
                    next;
                }
            }
        }
        # padding
        my $Padding = 0;
        if($Offset % $Alignment{$Pos}!=0)
        { # not aligned, add padding
            $Padding = $Alignment{$Pos} - $Offset % $Alignment{$Pos};
        }
        if($Pos==$NextField)
        { # try to place target field in the padding
            if($Size==-1)
            { # added/removed fields
                my $TPadding = 0;
                if($Offset % $Alignment{$FieldPos}!=0)
                {# padding of the target field
                    $TPadding = $Alignment{$FieldPos} - $Offset % $Alignment{$FieldPos};
                }
                if($TPadding+$MSize{$FieldPos}<=$Padding)
                { # enough padding to place target field
                    return 1;
                }
                else {
                    return 0;
                }
            }
            else
            { # changed fields
                my $Delta = $Size-$MSize{$FieldPos};
                if($Delta>=0)
                { # increased
                    if($Size-$MSize{$FieldPos}<=$Padding)
                    { # enough padding to change target field
                        return 1;
                    }
                    else {
                        return 0;
                    }
                }
                else
                { # decreased
                    $Delta = abs($Delta);
                    if($Delta+$Padding>=$MSize{$Pos})
                    { # try to place the next field
                        if(($Offset-$Delta) % $Alignment{$Pos} != 0)
                        { # padding of the next field in new place
                            my $NPadding = $Alignment{$Pos} - ($Offset-$Delta) % $Alignment{$Pos};
                            if($NPadding+$MSize{$Pos}<=$Delta+$Padding)
                            { # enough delta+padding to store next field
                                return 0;
                            }
                        }
                        else
                        {
                            return 0;
                        }
                    }
                    return 1;
                }
            }
        }
        elsif($Pos==$End)
        { # target field is the last field
            if($Size==-1)
            { # added/removed fields
                if($Offset % $MaxAlgn!=0)
                { # tail padding
                    my $TailPadding = $MaxAlgn - $Offset % $MaxAlgn;
                    if($Padding+$MSize{$Pos}<=$TailPadding)
                    { # enough tail padding to place the last field
                        return 1;
                    }
                }
                return 0;
            }
            else
            { # changed fields
                # scenario #1
                my $Offset1 = $Offset+$Padding+$MSize{$Pos};
                if($Offset1 % $MaxAlgn != 0)
                { # tail padding
                    $Offset1 += $MaxAlgn - $Offset1 % $MaxAlgn;
                }
                # scenario #2
                my $Offset2 = $Offset+$Padding+$Size;
                if($Offset2 % $MaxAlgn != 0)
                { # tail padding
                    $Offset2 += $MaxAlgn - $Offset2 % $MaxAlgn;
                }
                if($Offset1!=$Offset2)
                { # different sizes of structure
                    return 0;
                }
                return 1;
            }
        }
        $Offset += $Padding+$MSize{$Pos};
    }
    return 0;
}

sub isScalar($) {
    return ($_[0]=~/\A(unsigned |)(char|short|int|long|long long)\Z/);
}

sub isFloat($) {
    return ($_[0]=~/\A(float|double|long double)\Z/);
}

sub callingConvention_R_Real($)
{
    my $SInfo = $_[0];
    my %Conv = ();
    my %Regs = ();
    my $Hidden = 0;
    foreach my $Elem (keys(%{$SInfo->{"Reg"}}))
    {
        my $Reg = $SInfo->{"Reg"}{$Elem};
        if($Elem eq ".result_ptr")
        {
            $Hidden = 1;
            $Regs{$Reg} = 1;
        }
        elsif(index($Elem, ".result")==0) {
            $Regs{$Reg} = 1;
        }
    }
    if(my @R = sort keys(%Regs))
    {
        $Conv{"Method"} = "reg";
        $Conv{"Registers"} = join(", ", @R);
        if($Hidden) {
            $Conv{"Hidden"} = 1;
        }
    }
    else
    {
        $Conv{"Method"} = "stack";
        $Conv{"Hidden"} = 1;
    }
    return %Conv;
}

sub callingConvention_P_Real($$)
{
    my ($SInfo, $Pos) = @_;
    my %Conv = ();
    my %Regs = ();
    foreach my $Elem (keys(%{$SInfo->{"Reg"}}))
    {
        my $Reg = $SInfo->{"Reg"}{$Elem};
        if($Elem=~/\A$Pos([\.\+]|\Z)/) {
            $Regs{$Reg} = 1;
        }
    }
    if(my @R = sort keys(%Regs))
    {
        $Conv{"Method"} = "reg";
        $Conv{"Registers"} = join(", ", @R);
    }
    else
    {
        $Conv{"Method"} = "stack";
        
        if(defined $SInfo->{"Param"}
        and defined $SInfo->{"Param"}{0})
        {
            if(not defined $SInfo->{"Param"}{0}{"offset"})
            {
                $Conv{"Method"} = "unknown";
            }
        }
    }
    
    return %Conv;
}

return 1;