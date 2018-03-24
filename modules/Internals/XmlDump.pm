###########################################################################
# A module to create and read ABI dump in XML format
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2012-2018 Andrey Ponomarenko's ABI Laboratory
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

my $TAG_ID = 0;
my $INDENT = "    ";

sub createXmlDump($)
{
    my $LVer = $_[0];
    my $ABI_DUMP = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
    
    $ABI_DUMP .= "<ABI_dump version=\"".$In::ABI{$LVer}{"ABI_DUMP_VERSION"}."\"";
    $ABI_DUMP .= " xml_format=\"".$In::ABI{$LVer}{"XML_ABI_DUMP_VERSION"}."\"";
    $ABI_DUMP .= " acc=\"".$In::ABI{$LVer}{"ABI_COMPLIANCE_CHECKER_VERSION"}."\">\n";
    
    $ABI_DUMP .= addTag("library", $In::ABI{$LVer}{"LibraryName"});
    $ABI_DUMP .= addTag("library_version", $In::ABI{$LVer}{"LibraryVersion"});
    $ABI_DUMP .= addTag("language", $In::ABI{$LVer}{"Language"});
    
    $ABI_DUMP .= addTag("gcc", $In::ABI{$LVer}{"GccVersion"});
    $ABI_DUMP .= addTag("clang", $In::ABI{$LVer}{"ClangVersion"});
    $ABI_DUMP .= addTag("architecture", $In::ABI{$LVer}{"Arch"});
    $ABI_DUMP .= addTag("target", $In::ABI{$LVer}{"Target"});
    $ABI_DUMP .= addTag("word_size", $In::ABI{$LVer}{"WordSize"});
    
    if($In::ABI{$LVer}{"Mode"}) {
        $ABI_DUMP .= addTag("mode", $In::ABI{$LVer}{"Mode"});
    }
    if($In::ABI{$LVer}{"SrcBin"}) {
        $ABI_DUMP .= addTag("kind", "SrcBin");
    }
    elsif($In::ABI{$LVer}{"BinOnly"}) {
        $ABI_DUMP .= addTag("kind", "BinOnly");
    }
    
    if(my @Headers = keys(%{$In::ABI{$LVer}{"Headers"}}))
    {
        @Headers = sort {$In::ABI{$LVer}{"Headers"}{$a}<=>$In::ABI{$LVer}{"Headers"}{$b}} @Headers;
        $ABI_DUMP .= openTag("headers");
        foreach my $Name (@Headers) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("headers");
    }
    
    if(my @Sources = keys(%{$In::ABI{$LVer}{"Sources"}}))
    {
        @Sources = sort {$In::ABI{$LVer}{"Sources"}{$a}<=>$In::ABI{$LVer}{"Sources"}{$b}} @Sources;
        $ABI_DUMP .= openTag("sources");
        foreach my $Name (@Sources) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("sources");
    }
    
    if(my @Libs = keys(%{$In::ABI{$LVer}{"Needed"}}))
    {
        $ABI_DUMP .= openTag("needed");
        foreach my $Name (sort {lc($a) cmp lc($b)} @Libs) {
            $ABI_DUMP .= addTag("library", $Name);
        }
        $ABI_DUMP .= closeTag("needed");
    }
    
    if(my @NameSpaces = keys(%{$In::ABI{$LVer}{"NameSpaces"}}))
    {
        $ABI_DUMP .= openTag("namespaces");
        foreach my $NameSpace (sort {lc($a) cmp lc($b)} @NameSpaces) {
            $ABI_DUMP .= addTag("name", $NameSpace);
        }
        $ABI_DUMP .= closeTag("namespaces");
    }
    
    if(my @TypeInfo = keys(%{$In::ABI{$LVer}{"TypeInfo"}}))
    {
        $ABI_DUMP .= openTag("type_info");
        foreach my $ID (sort {$a<=>$b} @TypeInfo)
        {
            my %TInfo = %{$In::ABI{$LVer}{"TypeInfo"}{$ID}};
            $ABI_DUMP .= openTag("data_type");
            $ABI_DUMP .= addTag("id", $ID);
            foreach my $Attr ("Name", "Type", "Size",
            "Header", "Line", "NameSpace", "Class", "Return", "Algn")
            {
                if(defined $TInfo{$Attr}) {
                    $ABI_DUMP .= addTag(lc($Attr), $TInfo{$Attr});
                }
            }
            if($TInfo{"Private"}) {
                $ABI_DUMP .= addTag("access", "private");
            }
            if($TInfo{"Protected"}) {
                $ABI_DUMP .= addTag("access", "protected");
            }
            if(my @Positions = keys(%{$TInfo{"Memb"}}))
            {
                $ABI_DUMP .= openTag("members");
                foreach my $Pos (sort { $a<=>$b } @Positions)
                {
                    $ABI_DUMP .= openTag("field");
                    $ABI_DUMP .= addTag("name", $TInfo{"Memb"}{$Pos}{"name"});
                    if(my $MTid = $TInfo{"Memb"}{$Pos}{"type"}) {
                        $ABI_DUMP .= addTag("type", $MTid);
                    }
                    if(my $Access = $TInfo{"Memb"}{$Pos}{"access"}) {
                        $ABI_DUMP .= addTag("access", $Access);
                    }
                    my $Val = $TInfo{"Memb"}{$Pos}{"value"};
                    if(defined $Val) {
                        $ABI_DUMP .= addTag("value", $Val);
                    }
                    if(my $Align = $TInfo{"Memb"}{$Pos}{"algn"}) {
                        $ABI_DUMP .= addTag("algn", $Align);
                    }
                    if(my $Bitfield = $TInfo{"Memb"}{$Pos}{"bitfield"}) {
                        $ABI_DUMP .= addTag("bitfield", $Bitfield);
                    }
                    if($TInfo{"Memb"}{$Pos}{"mutable"}) {
                        $ABI_DUMP .= addTag("spec", "mutable");
                    }
                    $ABI_DUMP .= addTag("pos", $Pos);
                    $ABI_DUMP .= closeTag("field");
                }
                $ABI_DUMP .= closeTag("members");
            }
            if(my @Positions = keys(%{$TInfo{"Param"}}))
            {
                $ABI_DUMP .= openTag("parameters");
                foreach my $Pos (sort { $a<=>$b } @Positions)
                {
                    $ABI_DUMP .= openTag("param");
                    if(my $PTid = $TInfo{"Param"}{$Pos}{"type"}) {
                        $ABI_DUMP .= addTag("type", $PTid);
                    }
                    $ABI_DUMP .= addTag("pos", $Pos);
                    $ABI_DUMP .= closeTag("param");
                }
                $ABI_DUMP .= closeTag("parameters");
            }
            if(my @Positions = keys(%{$TInfo{"TParam"}}))
            {
                $ABI_DUMP .= openTag("template_parameters");
                foreach my $Pos (sort { $a<=>$b } @Positions)
                {
                    $ABI_DUMP .= openTag("param");
                    $ABI_DUMP .= addTag("name", $TInfo{"TParam"}{$Pos}{"name"});
                    $ABI_DUMP .= addTag("pos", $Pos);
                    $ABI_DUMP .= closeTag("param");
                }
                $ABI_DUMP .= closeTag("template_parameters");
            }
            if(my @Offsets = keys(%{$TInfo{"VTable"}}))
            {
                $ABI_DUMP .= openTag("vtable");
                foreach my $Offset (sort { $a<=>$b } @Offsets)
                {
                    $ABI_DUMP .= openTag("entry");
                    $ABI_DUMP .= addTag("offset", $Offset);
                    $ABI_DUMP .= addTag("value", $TInfo{"VTable"}{$Offset});
                    $ABI_DUMP .= closeTag("entry");
                }
                $ABI_DUMP .= closeTag("vtable");
            }
            if(my $BTid = $TInfo{"BaseType"}) {
                $ABI_DUMP .= addTag("base_type", $BTid);
            }
            if(my @BaseIDs = keys(%{$TInfo{"Base"}}))
            {
                @BaseIDs = sort { $TInfo{"Base"}{$a}{"pos"}<=>$TInfo{"Base"}{$b}{"pos"} } @BaseIDs;
                $ABI_DUMP .= openTag("base");
                foreach my $BaseID (@BaseIDs)
                {
                    $ABI_DUMP .= openTag("class");
                    $ABI_DUMP .= addTag("id", $BaseID);
                    if(my $Access = $TInfo{"Base"}{$BaseID}{"access"}) {
                        $ABI_DUMP .= addTag("access", $Access);
                    }
                    if(my $Virt = $TInfo{"Base"}{$BaseID}{"virtual"}) {
                        $ABI_DUMP .= addTag("inherit", "virtual");
                    }
                    $ABI_DUMP .= addTag("pos", $TInfo{"Base"}{$BaseID}{"pos"});
                    $ABI_DUMP .= closeTag("class");
                }
                $ABI_DUMP .= closeTag("base");
            }
            if($TInfo{"Copied"}) {
                $ABI_DUMP .= addTag("note", "copied");
            }
            if($TInfo{"Spec"}) {
                $ABI_DUMP .= addTag("note", "specialization");
            }
            if($TInfo{"Forward"}) {
                $ABI_DUMP .= addTag("note", "forward");
            }
            $ABI_DUMP .= closeTag("data_type");
        }
        $ABI_DUMP .= closeTag("type_info");
    }
    
    if(my @Constants = keys(%{$In::ABI{$LVer}{"Constants"}}))
    {
        $ABI_DUMP .= openTag("constants");
        foreach my $Constant (@Constants)
        {
            my %CInfo = %{$In::ABI{$LVer}{"Constants"}{$Constant}};
            $ABI_DUMP .= openTag("constant");
            $ABI_DUMP .= addTag("name", $Constant);
            $ABI_DUMP .= addTag("value", $CInfo{"Value"});
            $ABI_DUMP .= addTag("header", $CInfo{"Header"});
            $ABI_DUMP .= closeTag("constant");
        }
        $ABI_DUMP .= closeTag("constants");
    }
    
    if(my @SymbolInfo = keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    {
        my %TR = (
            "MnglName" => "mangled",
            "ShortName" => "short"
        );
        $ABI_DUMP .= openTag("symbol_info");
        foreach my $ID (sort {$a<=>$b} @SymbolInfo)
        {
            my %SInfo = %{$In::ABI{$LVer}{"SymbolInfo"}{$ID}};
            $ABI_DUMP .= openTag("symbol");
            $ABI_DUMP .= addTag("id", $ID);
            foreach my $Attr ("MnglName", "ShortName", "Class",
            "Header", "Line", "Return", "NameSpace", "Value")
            {
                if(defined $SInfo{$Attr})
                {
                    my $Tag = $Attr;
                    if($TR{$Attr}) {
                        $Tag = $TR{$Attr};
                    }
                    $ABI_DUMP .= addTag(lc($Tag), $SInfo{$Attr});
                }
            }
            if($SInfo{"Constructor"}) {
                $ABI_DUMP .= addTag("kind", "constructor");
            }
            if($SInfo{"Destructor"}) {
                $ABI_DUMP .= addTag("kind", "destructor");
            }
            if($SInfo{"Data"}) {
                $ABI_DUMP .= addTag("kind", "data");
            }
            if($SInfo{"Virt"}) {
                $ABI_DUMP .= addTag("spec", "virtual");
            }
            elsif($SInfo{"PureVirt"}) {
                $ABI_DUMP .= addTag("spec", "pure virtual");
            }
            elsif($SInfo{"Static"}) {
                $ABI_DUMP .= addTag("spec", "static");
            }
            if($SInfo{"InLine"}) {
                $ABI_DUMP .= addTag("spec", "inline");
            }
            if($SInfo{"Const"}) {
                $ABI_DUMP .= addTag("spec", "const");
            }
            if($SInfo{"Volatile"}) {
                $ABI_DUMP .= addTag("spec", "volatile");
            }
            if($SInfo{"Private"}) {
                $ABI_DUMP .= addTag("access", "private");
            }
            if($SInfo{"Protected"}) {
                $ABI_DUMP .= addTag("access", "protected");
            }
            if($SInfo{"Artificial"}) {
                $ABI_DUMP .= addTag("note", "artificial");
            }
            if(my $Lang = $SInfo{"Lang"}) {
                $ABI_DUMP .= addTag("lang", $Lang);
            }
            if(my @Positions = keys(%{$SInfo{"Param"}}))
            {
                $ABI_DUMP .= openTag("parameters");
                foreach my $Pos (sort { $a<=>$b } @Positions)
                {
                    $ABI_DUMP .= openTag("param");
                    if(my $PName = $SInfo{"Param"}{$Pos}{"name"}) {
                        $ABI_DUMP .= addTag("name", $PName);
                    }
                    if(my $PTid = $SInfo{"Param"}{$Pos}{"type"}) {
                        $ABI_DUMP .= addTag("type", $PTid);
                    }
                    my $Default = $SInfo{"Param"}{$Pos}{"default"};
                    if(defined $Default) {
                        $ABI_DUMP .= addTag("default", $Default);
                    }
                    if(my $Align = $SInfo{"Param"}{$Pos}{"algn"}) {
                        $ABI_DUMP .= addTag("algn", $Align);
                    }
                    if(defined $SInfo{"Param"}{$Pos}{"reg"}) {
                        $ABI_DUMP .= addTag("call", "register");
                    }
                    $ABI_DUMP .= addTag("pos", $Pos);
                    $ABI_DUMP .= closeTag("param");
                }
                $ABI_DUMP .= closeTag("parameters");
            }
            if(my @Positions = keys(%{$SInfo{"TParam"}}))
            {
                $ABI_DUMP .= openTag("template_parameters");
                foreach my $Pos (sort { $a<=>$b } @Positions)
                {
                    $ABI_DUMP .= openTag("param");
                    $ABI_DUMP .= addTag("name", $SInfo{"TParam"}{$Pos}{"name"});
                    $ABI_DUMP .= closeTag("param");
                }
                $ABI_DUMP .= closeTag("template_parameters");
            }
            $ABI_DUMP .= closeTag("symbol");
        }
        $ABI_DUMP .= closeTag("symbol_info");
    }
    
    foreach my $K ("Symbols", "UndefinedSymbols")
    {
        if($In::ABI{$LVer}{$K} and my @Libs = keys(%{$In::ABI{$LVer}{$K}}))
        {
            my $SymTag = "symbols";
            if($K eq "UndefinedSymbols") {
                $SymTag = "undefined_symbols";
            }
            
            $ABI_DUMP .= openTag($SymTag);
            
            foreach my $Lib (sort {lc($a) cmp lc($b)} @Libs)
            {
                $ABI_DUMP .= openTag("library", "name", $Lib);
                foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%{$In::ABI{$LVer}{$K}{$Lib}}))
                {
                    if((my $Size = $In::ABI{$LVer}{$K}{$Lib}{$Symbol})<0)
                    { # data
                        $ABI_DUMP .= addTag("symbol", $Symbol, "size", -$Size);
                    }
                    else
                    { # functions
                        $ABI_DUMP .= addTag("symbol", $Symbol);
                    }
                }
                $ABI_DUMP .= closeTag("library");
            }
            $ABI_DUMP .= closeTag($SymTag);
        }
    }
    
    if(my @DepLibs = keys(%{$In::ABI{$LVer}{"DepSymbols"}}))
    {
        $ABI_DUMP .= openTag("dep_symbols");
        foreach my $Lib (sort {lc($a) cmp lc($b)} @DepLibs)
        {
            $ABI_DUMP .= openTag("library", "name", $Lib);
            foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%{$In::ABI{$LVer}{"DepSymbols"}{$Lib}}))
            {
                if((my $Size = $In::ABI{$LVer}{"DepSymbols"}{$Lib}{$Symbol})<0)
                { # data
                    $ABI_DUMP .= addTag("symbol", $Symbol, "size", -$Size);
                }
                else
                { # functions
                    $ABI_DUMP .= addTag("symbol", $Symbol);
                }
            }
            $ABI_DUMP .= closeTag("library");
        }
        $ABI_DUMP .= closeTag("dep_symbols");
    }
    
    if(my @VSymbols = keys(%{$In::ABI{$LVer}{"SymbolVersion"}}))
    {
        $ABI_DUMP .= openTag("symbol_version");
        foreach my $Symbol (sort {lc($a) cmp lc($b)} @VSymbols)
        {
            $ABI_DUMP .= openTag("symbol");
            $ABI_DUMP .= addTag("name", $Symbol);
            $ABI_DUMP .= addTag("version", $In::ABI{$LVer}{"SymbolVersion"}{$Symbol});
            $ABI_DUMP .= closeTag("symbol");
        }
        $ABI_DUMP .= closeTag("symbol_version");
    }
    
    if(my @TargetHeaders = keys(%{$In::Desc{$LVer}{"TargetHeader"}}))
    {
        $ABI_DUMP .= openTag("target_headers");
        foreach my $Name (sort {lc($a) cmp lc($b)} @TargetHeaders) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("target_headers");
    }
    
    $ABI_DUMP .= "</ABI_dump>\n";
    
    checkTags();
    
    return $ABI_DUMP;
}

sub readXmlDump($)
{
    my $ABI_DUMP = readFile($_[0]);
    my %ABI = ();
    
    $ABI{"LibraryName"} = parseTag(\$ABI_DUMP, "library");
    $ABI{"LibraryVersion"} = parseTag(\$ABI_DUMP, "library_version");
    $ABI{"Language"} = parseTag(\$ABI_DUMP, "language");
    $ABI{"GccVersion"} = parseTag(\$ABI_DUMP, "gcc");
    $ABI{"ClangVersion"} = parseTag(\$ABI_DUMP, "clang");
    $ABI{"Arch"} = parseTag(\$ABI_DUMP, "architecture");
    $ABI{"Target"} = parseTag(\$ABI_DUMP, "target");
    $ABI{"WordSize"} = parseTag(\$ABI_DUMP, "word_size");
    
    my $Pos = 0;
    
    if(my $Headers = parseTag(\$ABI_DUMP, "headers"))
    {
        while(my $Name = parseTag(\$Headers, "name")) {
            $ABI{"Headers"}{$Name} = $Pos++;
        }
    }
    
    if(my $Sources = parseTag(\$ABI_DUMP, "sources"))
    {
        while(my $Name = parseTag(\$Sources, "name")) {
            $ABI{"Sources"}{$Name} = $Pos++;
        }
    }
    
    if(my $Needed = parseTag(\$ABI_DUMP, "needed"))
    {
        while(my $Lib = parseTag(\$Needed, "library")) {
            $ABI{"Needed"}{$Lib} = 1;
        }
    }
    
    if(my $NameSpaces = parseTag(\$ABI_DUMP, "namespaces"))
    {
        while(my $Name = parseTag(\$NameSpaces, "name")) {
            $ABI{"NameSpaces"}{$Name} = 1;
        }
    }
    
    if(my $TypeInfo = parseTag(\$ABI_DUMP, "type_info"))
    {
        while(my $DataType = parseTag(\$TypeInfo, "data_type"))
        {
            my %TInfo = ();
            my $ID = parseTag(\$DataType, "id");
            
            if(my $Members = parseTag(\$DataType, "members"))
            {
                $Pos = 0;
                while(my $Field = parseTag(\$Members, "field"))
                {
                    my %MInfo = ();
                    $MInfo{"name"} = parseTag(\$Field, "name");
                    if(my $Tid = parseTag(\$Field, "type")) {
                        $MInfo{"type"} = $Tid;
                    }
                    if(my $Access = parseTag(\$Field, "access")) {
                        $MInfo{"access"} = $Access;
                    }
                    my $Val = parseTag(\$Field, "value");
                    if(defined $Val) {
                        $MInfo{"value"} = $Val;
                    }
                    if(my $Align = parseTag(\$Field, "algn")) {
                        $MInfo{"algn"} = $Align;
                    }
                    if(my $Bitfield = parseTag(\$Field, "bitfield")) {
                        $MInfo{"bitfield"} = $Bitfield;
                    }
                    if(my $Spec = parseTag(\$Field, "spec")) {
                        $MInfo{$Spec} = 1;
                    }
                    $TInfo{"Memb"}{$Pos++} = \%MInfo;
                }
            }
            
            if(my $Parameters = parseTag(\$DataType, "parameters"))
            {
                $Pos = 0;
                while(my $Parameter = parseTag(\$Parameters, "param"))
                {
                    my %PInfo = ();
                    if(my $Tid = parseTag(\$Parameter, "type")) {
                        $PInfo{"type"} = $Tid;
                    }
                    $TInfo{"Param"}{$Pos++} = \%PInfo;
                }
            }
            if(my $TParams = parseTag(\$DataType, "template_parameters"))
            {
                $Pos = 0;
                while(my $TParam = parseTag(\$TParams, "param")) {
                    $TInfo{"TParam"}{$Pos++}{"name"} = parseTag(\$TParam, "name");
                }
            }
            if(my $VTable = parseTag(\$DataType, "vtable"))
            {
                $Pos = 0;
                while(my $Entry = parseTag(\$VTable, "entry")) {
                    $TInfo{"VTable"}{parseTag(\$Entry, "offset")} = parseTag(\$Entry, "value");
                }
            }
            if(my $BTid = parseTag(\$DataType, "base_type")) {
                $TInfo{"BaseType"} = $BTid;
            }
            if(my $Base = parseTag(\$DataType, "base"))
            {
                $Pos = 0;
                while(my $Class = parseTag(\$Base, "class"))
                {
                    my %CInfo = ();
                    $CInfo{"pos"} = parseTag(\$Class, "pos");
                    if(my $Access = parseTag(\$Class, "access")) {
                        $CInfo{"access"} = $Access;
                    }
                    if(my $Inherit = parseTag(\$Class, "inherit"))
                    {
                        if($Inherit eq "virtual") {
                            $CInfo{"virtual"} = 1;
                        }
                    }
                    $TInfo{"Base"}{parseTag(\$Class, "id")} = \%CInfo;
                }
            }
            while(my $Note = parseTag(\$DataType, "note"))
            {
                if($Note eq "copied") {
                    $TInfo{"Copied"} = 1;
                }
                elsif($Note eq "specialization") {
                    $TInfo{"Spec"} = 1;
                }
                elsif($Note eq "forward") {
                    $TInfo{"Forward"} = 1;
                }
            }
            foreach my $Attr ("Name", "Type", "Size",
            "Header", "Line", "NameSpace", "Class", "Return", "Algn")
            {
                my $Val = parseTag(\$DataType, lc($Attr));
                if(defined $Val) {
                    $TInfo{$Attr} = $Val;
                }
            }
            if(my $Access = parseTag(\$DataType, "access")) {
                $TInfo{ucfirst($Access)} = 1;
            }
            $ABI{"TypeInfo"}{$ID} = \%TInfo;
        }
    }
    
    if(my $Constants = parseTag(\$ABI_DUMP, "constants"))
    {
        while(my $Constant = parseTag(\$Constants, "constant"))
        {
            if(my $Name = parseTag(\$Constant, "name"))
            {
                my %CInfo = ();
                $CInfo{"Value"} = parseTag(\$Constant, "value");
                $CInfo{"Header"} = parseTag(\$Constant, "header");
                $ABI{"Constants"}{$Name} = \%CInfo;
            }
        }
    }
    
    if(my $SymbolInfo = parseTag(\$ABI_DUMP, "symbol_info"))
    {
        my %TR = (
            "MnglName"=>"mangled",
            "ShortName"=>"short"
        );
        while(my $Symbol = parseTag(\$SymbolInfo, "symbol"))
        {
            my %SInfo = ();
            my $ID = parseTag(\$Symbol, "id");
            
            if(my $Parameters = parseTag(\$Symbol, "parameters"))
            {
                $Pos = 0;
                while(my $Parameter = parseTag(\$Parameters, "param"))
                {
                    my %PInfo = ();
                    if(my $PName = parseTag(\$Parameter, "name")) {
                        $PInfo{"name"} = $PName;
                    }
                    if(my $PTid = parseTag(\$Parameter, "type")) {
                        $PInfo{"type"} = $PTid;
                    }
                    my $Default = parseTag(\$Parameter, "default", "spaces");
                    if(defined $Default) {
                        $PInfo{"default"} = $Default;
                    }
                    if(my $Align = parseTag(\$Parameter, "algn")) {
                        $PInfo{"algn"} = $Align;
                    }
                    if(my $Call = parseTag(\$Parameter, "call"))
                    {
                        if($Call eq "register") {
                            $PInfo{"reg"} = 1;
                        }
                    }
                    $SInfo{"Param"}{$Pos++} = \%PInfo;
                }
            }
            if(my $TParams = parseTag(\$Symbol, "template_parameters"))
            {
                $Pos = 0;
                while(my $TParam = parseTag(\$TParams, "param")) {
                    $SInfo{"TParam"}{$Pos++}{"name"} = parseTag(\$TParam, "name");
                }
            }
            
            foreach my $Attr ("MnglName", "ShortName", "Class",
            "Header", "Line", "Return", "NameSpace", "Value")
            {
                my $Tag = lc($Attr);
                if($TR{$Attr}) {
                    $Tag = $TR{$Attr};
                }
                my $Val = parseTag(\$Symbol, $Tag);
                if(defined $Val) {
                    $SInfo{$Attr} = $Val;
                }
            }
            if(my $Kind = parseTag(\$Symbol, "kind")) {
                $SInfo{ucfirst($Kind)} = 1;
            }
            while(my $Spec = parseTag(\$Symbol, "spec"))
            {
                if($Spec eq "virtual") {
                    $SInfo{"Virt"} = 1;
                }
                elsif($Spec eq "pure virtual") {
                    $SInfo{"PureVirt"} = 1;
                }
                elsif($Spec eq "inline") {
                    $SInfo{"InLine"} = 1;
                }
                else
                { # const, volatile, static
                    $SInfo{ucfirst($Spec)} = 1;
                }
            }
            if(my $Access = parseTag(\$Symbol, "access")) {
                $SInfo{ucfirst($Access)} = 1;
            }
            if(my $Note = parseTag(\$Symbol, "note")) {
                $SInfo{ucfirst($Note)} = 1;
            }
            if(my $Lang = parseTag(\$Symbol, "lang")) {
                $SInfo{"Lang"} = $Lang;
            }
            $ABI{"SymbolInfo"}{$ID} = \%SInfo;
        }
    }
    
    foreach my $K ("Symbols", "UndefinedSymbols")
    {
        my ($SymTag, $SymVal) = ("symbols", 1);
        
        if($K eq "UndefinedSymbols") {
            ($SymTag, $SymVal) = ("undefined_symbols", 0);
        }
        
        if(my $Symbols = parseTag(\$ABI_DUMP, $SymTag))
        {
            my %LInfo = ();
            while(my $LibSymbols = parseTag_E(\$Symbols, "library", \%LInfo))
            {
                my %SInfo = ();
                while(my $Symbol = parseTag_E(\$LibSymbols, "symbol", \%SInfo))
                {
                    if(my $Size = $SInfo{"size"}) {
                        $ABI{$K}{$LInfo{"name"}}{$Symbol} = -$Size;
                    }
                    else {
                        $ABI{$K}{$LInfo{"name"}}{$Symbol} = $SymVal;
                    }
                    %SInfo = ();
                }
                %LInfo = ();
            }
        }
    }
    
    if(my $DepSymbols = parseTag(\$ABI_DUMP, "dep_symbols"))
    {
        my %LInfo = ();
        while(my $LibSymbols = parseTag_E(\$DepSymbols, "library", \%LInfo))
        {
            my %SInfo = ();
            while(my $Symbol = parseTag_E(\$LibSymbols, "symbol", \%SInfo))
            {
                if(my $Size = $SInfo{"size"}) {
                    $ABI{"DepSymbols"}{$LInfo{"name"}}{$Symbol} = -$Size;
                }
                else {
                    $ABI{"DepSymbols"}{$LInfo{"name"}}{$Symbol} = 1;
                }
                %SInfo = ();
            }
            %LInfo = ();
        }
    }
    
    $ABI{"SymbolVersion"} = {};
    
    if(my $SymbolVersion = parseTag(\$ABI_DUMP, "symbol_version"))
    {
        while(my $Symbol = parseTag(\$SymbolVersion, "symbol")) {
            $ABI{"SymbolVersion"}{parseTag(\$Symbol, "name")} = parseTag(\$Symbol, "version");
        }
    }
    
    if(my $TargetHeaders = parseTag(\$ABI_DUMP, "target_headers"))
    {
        while(my $Name = parseTag(\$TargetHeaders, "name")) {
            $ABI{"TargetHeaders"}{$Name} = 1;
        }
    }
    
    if(my $Mode = parseTag(\$ABI_DUMP, "mode")) {
        $ABI{"Mode"} = $Mode;
    }
    if(my $Kind = parseTag(\$ABI_DUMP, "kind"))
    {
        if($Kind eq "BinOnly") {
            $ABI{"BinOnly"} = 1;
        }
        elsif($Kind eq "SrcBin") {
            $ABI{"SrcBin"} = 1;
        }
    }
    
    my %RInfo = ();
    parseTag_E(\$ABI_DUMP, "ABI_dump", \%RInfo);
    
    $ABI{"ABI_DUMP_VERSION"} = $RInfo{"version"};
    $ABI{"XML_ABI_DUMP_VERSION"} = $RInfo{"xml_format"};
    $ABI{"ABI_COMPLIANCE_CHECKER_VERSION"} = $RInfo{"acc"};
    
    return \%ABI;
}

sub parseTag_E($$$)
{
    my ($CodeRef, $Tag, $Info) = @_;
    if(not $Tag or not $CodeRef
    or not $Info) {
        return undef;
    }
    if(${$CodeRef}=~s/\<\Q$Tag\E(\s+([^<>]+)|)\>((.|\n)*?)\<\/\Q$Tag\E\>//)
    {
        my ($Ext, $Content) = ($2, $3);
        $Content=~s/\A\s+//g;
        $Content=~s/\s+\Z//g;
        if($Ext)
        {
            while($Ext=~s/(\w+)\=\"([^\"]*)\"//)
            {
                my ($K, $V) = ($1, $2);
                $Info->{$K} = xmlSpecChars_R($V);
            }
        }
        if(substr($Content, 0, 1) ne "<") {
            $Content = xmlSpecChars_R($Content);
        }
        return $Content;
    }
    return undef;
}

sub addTag(@)
{
    my $Tag = shift(@_);
    my $Val = shift(@_);
    my @Ext = @_;
    my $Content = openTag($Tag, @Ext);
    chomp($Content);
    $Content .= xmlSpecChars($Val);
    $Content .= "</$Tag>\n";
    $TAG_ID-=1;
    
    return $Content;
}

sub openTag(@)
{
    my $Tag = shift(@_);
    my @Ext = @_;
    my $Content = "";
    foreach (1 .. $TAG_ID) {
        $Content .= $INDENT;
    }
    $TAG_ID+=1;
    if(@Ext)
    {
        $Content .= "<".$Tag;
        my $P = 0;
        while($P<=$#Ext-1)
        {
            $Content .= " ".$Ext[$P];
            $Content .= "=\"".xmlSpecChars($Ext[$P+1])."\"";
            $P+=2;
        }
        $Content .= ">\n";
    }
    else {
        $Content .= "<".$Tag.">\n";
    }
    return $Content;
}

sub closeTag($)
{
    my $Tag = $_[0];
    my $Content = "";
    $TAG_ID-=1;
    foreach (1 .. $TAG_ID) {
        $Content .= $INDENT;
    }
    $Content .= "</".$Tag.">\n";
    return $Content;
}

sub checkTags()
{
    if($TAG_ID!=0) {
        printMsg("WARNING", "the number of opened tags is not equal to number of closed tags");
    }
}

return 1;
