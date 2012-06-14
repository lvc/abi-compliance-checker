###########################################################################
# Module for ABI Compliance Checker to create ABI dumps in XML format
#
# Copyright (C) 2009-2010 The Linux Foundation
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2011-2012 ROSA Laboratory
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

sub createXmlDump($)
{
    my $ABI = $_[0];
    my $ABI_DUMP = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
    
    $ABI_DUMP .= "<ABI_dump version=\"".$ABI->{"ABI_DUMP_VERSION"}."\"";
    $ABI_DUMP .= " xml_format=\"".$ABI->{"XML_ABI_DUMP_VERSION"}."\"";
    $ABI_DUMP .= " acc=\"".$ABI->{"ABI_COMPLIANCE_CHECKER_VERSION"}."\">\n";
    
    $ABI_DUMP .= addTag("library", $ABI->{"LibraryName"});
    $ABI_DUMP .= addTag("library_version", $ABI->{"LibraryVersion"});
    $ABI_DUMP .= addTag("language", $ABI->{"Language"});
    
    $ABI_DUMP .= addTag("gcc", $ABI->{"GccVersion"});
    $ABI_DUMP .= addTag("architecture", $ABI->{"Arch"});
    $ABI_DUMP .= addTag("target", $ABI->{"Target"});
    $ABI_DUMP .= addTag("word_size", $ABI->{"WordSize"});
    
    if($ABI->{"Mode"}) {
        $ABI_DUMP .= addTag("mode", $ABI->{"Mode"});
    }
    if($ABI->{"SrcBin"}) {
        $ABI_DUMP .= addTag("kind", "SrcBin");
    }
    elsif($ABI->{"BinOnly"}) {
        $ABI_DUMP .= addTag("kind", "BinOnly");
    }
    
    if(my @Headers = keys(%{$ABI->{"Headers"}}))
    {
        @Headers = sort {$ABI->{"Headers"}{$a}<=>$ABI->{"Headers"}{$b}} @Headers;
        $ABI_DUMP .= openTag("headers");
        foreach my $Name (@Headers) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("headers");
    }
    
    if(my @NameSpaces = keys(%{$ABI->{"NameSpaces"}}))
    {
        $ABI_DUMP .= openTag("namespaces");
        foreach my $NameSpace (sort {lc($a) cmp lc($b)} @NameSpaces) {
            $ABI_DUMP .= addTag("name", $NameSpace);
        }
        $ABI_DUMP .= closeTag("namespaces");
    }
    
    if(my @TypeInfo = keys(%{$ABI->{"TypeInfo"}}))
    {
        $ABI_DUMP .= openTag("type_info");
        foreach my $ID (sort {$a<=>$b} @TypeInfo)
        {
            my %TInfo = %{$ABI->{"TypeInfo"}{$ID}};
            $ABI_DUMP .= openTag("data_type");
            $ABI_DUMP .= addTag("id", $ID);
            foreach my $Attr ("Name", "Type", "Size",
            "Header", "Line", "NameSpace", "Class", "Return")
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
                    my $Val = $TInfo{"Memb"}{$Pos}{"value"};
                    if(defined $Val) {
                        $ABI_DUMP .= addTag("value", $Val);
                    }
                    if(my $Align = $TInfo{"Memb"}{$Pos}{"algn"}) {
                        $ABI_DUMP .= addTag("algn", $Align);
                    }
                    $ABI_DUMP .= addTag("pos", $Pos);
                    $ABI_DUMP .= closeTag("field");
                }
                $ABI_DUMP .= closeTag("members");
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
            if(my $BTid = $TInfo{"BaseType"}{"Tid"}) {
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
                $ABI_DUMP .= addTag("kind", "copied");
            }
            $ABI_DUMP .= closeTag("data_type");
        }
        $ABI_DUMP .= closeTag("type_info");
    }
    
    if(my @Constants = keys(%{$ABI->{"Constants"}}))
    {
        $ABI_DUMP .= openTag("constants");
        foreach my $Constant (@Constants)
        {
            my %CInfo = %{$ABI->{"Constants"}{$Constant}};
            $ABI_DUMP .= openTag("constant");
            $ABI_DUMP .= addTag("name", $Constant);
            $ABI_DUMP .= addTag("value", $CInfo{"Value"});
            $ABI_DUMP .= addTag("header", $CInfo{"Header"});
            $ABI_DUMP .= closeTag("constant");
        }
        $ABI_DUMP .= closeTag("constants");
    }
    
    if(my @SymbolInfo = keys(%{$ABI->{"SymbolInfo"}}))
    {
        my %TR = (
            "MnglName" => "mangled",
            "ShortName" => "short"
        );
        $ABI_DUMP .= openTag("symbol_info");
        foreach my $ID (sort {$a<=>$b} @SymbolInfo)
        {
            my %SInfo = %{$ABI->{"SymbolInfo"}{$ID}};
            $ABI_DUMP .= openTag("symbol");
            $ABI_DUMP .= addTag("id", $ID);
            foreach my $Attr ("MnglName", "ShortName", "Class",
            "Header", "Line", "Return")
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
                    $ABI_DUMP .= addTag("name", $SInfo{"Param"}{$Pos}{"name"});
                    if(my $MTid = $SInfo{"Param"}{$Pos}{"type"}) {
                        $ABI_DUMP .= addTag("type", $MTid);
                    }
                    if(my $Default = $SInfo{"Param"}{$Pos}{"default"}) {
                        $ABI_DUMP .= addTag("default", $Default);
                    }
                    if(my $Align = $SInfo{"Param"}{$Pos}{"algn"}) {
                        $ABI_DUMP .= addTag("algn", $Align);
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
    
    if(my @Libs = keys(%{$ABI->{"Symbols"}}))
    {
        $ABI_DUMP .= openTag("symbols");
        foreach my $Lib (sort {lc($a) cmp lc($b)} @Libs)
        {
            $ABI_DUMP .= openTag_E("library", "name", $Lib);
            foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%{$ABI->{"Symbols"}{$Lib}}))
            {
                $ABI_DUMP .= addTag("symbol", $Symbol);
            }
            $ABI_DUMP .= closeTag("library");
        }
        $ABI_DUMP .= closeTag("symbols");
    }
    
    if(my @DepLibs = keys(%{$ABI->{"DepSymbols"}}))
    {
        $ABI_DUMP .= openTag("dep_symbols");
        foreach my $Lib (sort {lc($a) cmp lc($b)} @DepLibs)
        {
            $ABI_DUMP .= openTag_E("library", "name", $Lib);
            foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%{$ABI->{"DepSymbols"}{$Lib}}))
            {
                $ABI_DUMP .= addTag("symbol", $Symbol);
            }
            $ABI_DUMP .= closeTag("library");
        }
        $ABI_DUMP .= closeTag("dep_symbols");
    }
    
    if(my @VSymbols = keys(%{$ABI->{"SymbolVersion"}}))
    {
        $ABI_DUMP .= openTag("symbol_version");
        foreach my $Symbol (sort {lc($a) cmp lc($b)} @VSymbols)
        {
            $ABI_DUMP .= openTag("symbol");
            $ABI_DUMP .= addTag("name", $Symbol);
            $ABI_DUMP .= addTag("version", $ABI->{"SymbolVersion"}{$Symbol});
            $ABI_DUMP .= closeTag("symbol");
        }
        $ABI_DUMP .= closeTag("symbol_version");
    }
    
    if(my @SkipTypes = keys(%{$ABI->{"SkipTypes"}}))
    {
        $ABI_DUMP .= openTag("skip_types");
        foreach my $Name (sort {lc($a) cmp lc($b)} @SkipTypes) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("skip_types");
    }
    
    if(my @SkipSymbols = keys(%{$ABI->{"SkipSymbols"}}))
    {
        $ABI_DUMP .= openTag("skip_symbols");
        foreach my $Name (sort {lc($a) cmp lc($b)} @SkipSymbols) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("skip_symbols");
    }
    
    if(my @SkipNameSpaces = keys(%{$ABI->{"SkipNameSpaces"}}))
    {
        $ABI_DUMP .= openTag("skip_namespaces");
        foreach my $Name (sort {lc($a) cmp lc($b)} @SkipNameSpaces) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("skip_namespaces");
    }
    
    if(my @SkipHeaders = keys(%{$ABI->{"SkipHeaders"}}))
    {
        $ABI_DUMP .= openTag("skip_headers");
        foreach my $Name (sort {lc($a) cmp lc($b)} @SkipHeaders) {
            $ABI_DUMP .= addTag("name", $Name);
        }
        $ABI_DUMP .= closeTag("skip_headers");
    }
    
    if(my @TargetHeaders = keys(%{$ABI->{"TargetHeaders"}}))
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

return 1;