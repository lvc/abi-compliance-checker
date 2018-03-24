###########################################################################
# A module to handle type attributes
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

my %TypeSpecAttributes = (
    "Const" => 1,
    "Volatile" => 1,
    "ConstVolatile" => 1,
    "Restrict" => 1,
    "Typedef" => 1
);

my (%TypeInfo, %TName_Tid) = ();

sub initAliases_TypeAttr($)
{
    my $LVer = $_[0];
    
    $TypeInfo{$LVer} = $In::ABI{$LVer}{"TypeInfo"};
    $TName_Tid{$LVer} = $In::ABI{$LVer}{"TName_Tid"};
}

sub getTypeIdByName($$)
{
    my ($TypeName, $LVer) = @_;
    return $TName_Tid{$LVer}{formatName($TypeName, "T")};
}

sub getShortClass($$)
{
    my ($TypeId, $LVer) = @_;
    my $TypeName = $TypeInfo{$LVer}{$TypeId}{"Name"};
    if($TypeInfo{$LVer}{$TypeId}{"Type"}!~/Intrinsic|Class|Struct|Union|Enum/) {
        $TypeName = uncoverTypedefs($TypeName, $LVer);
    }
    if(my $NameSpace = $TypeInfo{$LVer}{$TypeId}{"NameSpace"}) {
        $TypeName=~s/\A(struct |)\Q$NameSpace\E\:\://g;
    }
    return $TypeName;
}

sub goToFirst($$$)
{
    my ($TypeId, $LVer, $Type_Type) = @_;
    
    if(defined $Cache{"goToFirst"}{$TypeId}{$LVer}{$Type_Type}) {
        return %{$Cache{"goToFirst"}{$TypeId}{$LVer}{$Type_Type}};
    }
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return ();
    }
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if(not $Type{"Type"}) {
        return ();
    }
    if($Type{"Type"} ne $Type_Type)
    {
        if(not $Type{"BaseType"}) {
            return ();
        }
        %Type = goToFirst($Type{"BaseType"}, $LVer, $Type_Type);
    }
    $Cache{"goToFirst"}{$TypeId}{$LVer}{$Type_Type} = \%Type;
    return %Type;
}

sub getPureType($$)
{
    my ($TypeId, $LVer) = @_;
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return ();
    }
    if(defined $Cache{"getPureType"}{$TypeId}{$LVer}) {
        return %{$Cache{"getPureType"}{$TypeId}{$LVer}};
    }
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if(not $Type{"BaseType"}) {
        return %Type;
    }
    if($TypeSpecAttributes{$Type{"Type"}}) {
        %Type = getPureType($Type{"BaseType"}, $LVer);
    }
    $Cache{"getPureType"}{$TypeId}{$LVer} = \%Type;
    return %Type;
}

sub getPLevel($$)
{
    my ($TypeId, $LVer) = @_;
    
    if(defined $Cache{"getPLevel"}{$TypeId}{$LVer}) {
        return $Cache{"getPLevel"}{$TypeId}{$LVer};
    }
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return 0;
    }
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if($Type{"Type"}=~/FuncPtr|FieldPtr/) {
        return 1;
    }
    my $PLevel = 0;
    if($Type{"Type"} =~/Pointer|Ref|FuncPtr|FieldPtr/) {
        $PLevel += 1;
    }
    if(not $Type{"BaseType"}) {
        return $PLevel;
    }
    $PLevel += getPLevel($Type{"BaseType"}, $LVer);
    $Cache{"getPLevel"}{$TypeId}{$LVer} = $PLevel;
    return $PLevel;
}

sub getBaseType($$)
{
    my ($TypeId, $LVer) = @_;
    
    if(defined $Cache{"getBaseType"}{$TypeId}{$LVer}) {
        return %{$Cache{"getBaseType"}{$TypeId}{$LVer}};
    }
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return ();
    }
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if(not $Type{"BaseType"}) {
        return %Type;
    }
    %Type = getBaseType($Type{"BaseType"}, $LVer);
    $Cache{"getBaseType"}{$TypeId}{$LVer} = \%Type;
    return %Type;
}

sub getOneStepBaseType($$)
{
    my ($TypeId, $LVer) = @_;
    
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return ();
    }
    
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if(not $Type{"BaseType"}) {
        return %Type;
    }
    if(my $BTid = $Type{"BaseType"})
    {
        if($TypeInfo{$LVer}{$BTid}) {
            return %{$TypeInfo{$LVer}{$BTid}};
        }
        
        # something is going wrong
        return ();
    }
    
    return %Type;
}

sub getType($$)
{
    my ($TypeId, $LVer) = @_;
    
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return ();
    }
    return %{$TypeInfo{$LVer}{$TypeId}};
}

sub getBaseTypeQual($$)
{
    my ($TypeId, $LVer) = @_;
    if(not $TypeInfo{$LVer}{$TypeId}) {
        return "";
    }
    my %Type = %{$TypeInfo{$LVer}{$TypeId}};
    if(not $Type{"BaseType"}) {
        return "";
    }
    my $Qual = "";
    if($Type{"Type"} eq "Pointer") {
        $Qual .= "*";
    }
    elsif($Type{"Type"} eq "Ref") {
        $Qual .= "&";
    }
    elsif($Type{"Type"} eq "ConstVolatile") {
        $Qual .= "const volatile";
    }
    elsif($Type{"Type"} eq "Const"
    or $Type{"Type"} eq "Volatile"
    or $Type{"Type"} eq "Restrict") {
        $Qual .= lc($Type{"Type"});
    }
    my $BQual = getBaseTypeQual($Type{"BaseType"}, $LVer);
    return $BQual.$Qual;
}

sub isCopyingClass($$)
{
    my ($TypeId, $LVer) = @_;
    return $TypeInfo{$LVer}{$TypeId}{"Copied"};
}

sub getSubClasses($$$)
{
    my ($ClassId, $LVer, $Recursive) = @_;
    if(not defined $In::ABI{$LVer}{"Class_SubClasses"}{$ClassId}) {
        return ();
    }
    
    my @Subs = ();
    foreach my $SubId (keys(%{$In::ABI{$LVer}{"Class_SubClasses"}{$ClassId}}))
    {
        if($Recursive)
        {
            foreach my $SubSubId (getSubClasses($SubId, $LVer, $Recursive)) {
                push(@Subs, $SubSubId);
            }
        }
        push(@Subs, $SubId);
    }
    return @Subs;
}

sub getBaseClasses($$$)
{
    my ($ClassId, $LVer, $Recursive) = @_;
    my %ClassType = getType($ClassId, $LVer);
    if(not defined $ClassType{"Base"}) {
        return ();
    }
    
    my @Bases = ();
    foreach my $BaseId (sort {$ClassType{"Base"}{$a}{"pos"}<=>$ClassType{"Base"}{$b}{"pos"}}
    keys(%{$ClassType{"Base"}}))
    {
        if($Recursive)
        {
            foreach my $SubBaseId (getBaseClasses($BaseId, $LVer, $Recursive)) {
                push(@Bases, $SubBaseId);
            }
        }
        push(@Bases, $BaseId);
    }
    return @Bases;
}

return 1;
