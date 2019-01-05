###########################################################################
# A module to parse GCC AST
#
# Copyright (C) 2015-2019 Andrey Ponomarenko's ABI Laboratory
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
use Storable qw(dclone);

my %Cache;

my $BYTE = 8;

my %OperatorIndication = (
    "not" => "~",
    "assign" => "=",
    "andassign" => "&=",
    "orassign" => "|=",
    "xorassign" => "^=",
    "or" => "|",
    "xor" => "^",
    "addr" => "&",
    "and" => "&",
    "lnot" => "!",
    "eq" => "==",
    "ne" => "!=",
    "lt" => "<",
    "lshift" => "<<",
    "lshiftassign" => "<<=",
    "rshiftassign" => ">>=",
    "call" => "()",
    "mod" => "%",
    "modassign" => "%=",
    "subs" => "[]",
    "land" => "&&",
    "lor" => "||",
    "rshift" => ">>",
    "ref" => "->",
    "le" => "<=",
    "deref" => "*",
    "mult" => "*",
    "preinc" => "++",
    "delete" => " delete",
    "vecnew" => " new[]",
    "vecdelete" => " delete[]",
    "predec" => "--",
    "postinc" => "++",
    "postdec" => "--",
    "plusassign" => "+=",
    "plus" => "+",
    "minus" => "-",
    "minusassign" => "-=",
    "gt" => ">",
    "ge" => ">=",
    "new" => " new",
    "multassign" => "*=",
    "divassign" => "/=",
    "div" => "/",
    "neg" => "-",
    "pos" => "+",
    "memref" => "->*",
    "compound" => ","
);

my %NodeType= (
    "array_type" => "Array",
    "binfo" => "Other",
    "boolean_type" => "Intrinsic",
    "complex_type" => "Intrinsic",
    "const_decl" => "Other",
    "enumeral_type" => "Enum",
    "field_decl" => "Other",
    "function_decl" => "Other",
    "function_type" => "FunctionType",
    "identifier_node" => "Other",
    "integer_cst" => "Other",
    "integer_type" => "Intrinsic",
    "vector_type" => "Vector",
    "method_type" => "MethodType",
    "namespace_decl" => "Other",
    "parm_decl" => "Other",
    "pointer_type" => "Pointer",
    "real_cst" => "Other",
    "real_type" => "Intrinsic",
    "record_type" => "Struct",
    "reference_type" => "Ref",
    "string_cst" => "Other",
    "template_decl" => "Other",
    "template_type_parm" => "TemplateParam",
    "typename_type" => "TypeName",
    "sizeof_expr" => "SizeOf",
    "tree_list" => "Other",
    "tree_vec" => "Other",
    "type_decl" => "Other",
    "union_type" => "Union",
    "var_decl" => "Other",
    "void_type" => "Intrinsic",
    "nop_expr" => "Other",
    "addr_expr" => "Other",
    "offset_type" => "Other"
);

my %UnQual = (
    "r"=>"restrict",
    "v"=>"volatile",
    "c"=>"const",
    "cv"=>"const volatile"
);

my %IntrinsicNames = map {$_=>1} (
    "void",
    "bool",
    "wchar_t",
    "char",
    "signed char",
    "unsigned char",
    "short",
    "unsigned short",
    "int",
    "unsigned int",
    "long",
    "unsigned long",
    "long long",
    "__int64",
    "unsigned long long",
    "__int128",
    "unsigned __int128",
    "float",
    "double",
    "long double" ,
    "__float80",
    "__float128",
    "..."
);

my %ConstantSuffix = (
    "unsigned int"=>"u",
    "long"=>"l",
    "unsigned long"=>"ul",
    "long long"=>"ll",
    "unsigned long long"=>"ull"
);

my %DefaultStdArgs = map {$_=>1} (
    "_Alloc",
    "_Compare",
    "_Traits",
    "_Rx_traits",
    "_InIter",
    "_OutIter"
);

my %LibInfo;
my %UnknownOperator;
my %Typedef_Tr;
my %Typedef_Eq;
my %StdCxxTypedef;
my %MissedTypedef;
my %MissedBase;
my %MissedBase_R;
my %CheckedTypeInfo;
my %TemplateInstance;
my %BasicTemplate;
my %TemplateArg;
my %TemplateDecl;
my %TemplateMap;
my %EnumMembName_Id;
my %TypedefToAnon;
my %MangledNames;
my $MAX_ID = 0;

my $V = undef;

# Aliases
my (%SymbolInfo, %TypeInfo, %TName_Tid) = ();

foreach (1, 2)
{
    $SymbolInfo{$_} = $In::ABI{$_}{"SymbolInfo"};
    $TypeInfo{$_} = $In::ABI{$_}{"TypeInfo"};
    $TName_Tid{$_} = $In::ABI{$_}{"TName_Tid"};
}

sub readGccAst($$)
{
    my ($LVer, $DumpPath) = @_;
    
    $V = $LVer;
    
    open(TU_DUMP, $DumpPath);
    local $/ = undef;
    my $Content = <TU_DUMP>;
    close(TU_DUMP);
    
    unlink($DumpPath);
    
    $Content=~s/\n[ ]+/ /g;
    my @Lines = split(/\n/, $Content);
    
    # clean memory
    undef $Content;
    
    $MAX_ID = $#Lines+1; # number of lines == number of nodes
    
    foreach (0 .. $#Lines)
    {
        if($Lines[$_]=~/\A\@(\d+)[ ]+([a-z_]+)[ ]+(.+)\Z/i)
        { # get a number and attributes of a node
            next if(not $NodeType{$2});
            $LibInfo{$V}{"info_type"}{$1} = $2;
            $LibInfo{$V}{"info"}{$1} = $3." ";
        }
        
        # clean memory
        delete($Lines[$_]);
    }
    
    # clean memory
    undef @Lines;
    
    # processing info
    setTemplateParams_All();
    
    if($In::Opt{"ExtraDump"}) {
        setAnonTypedef_All();
    }
    
    getTypeInfo_All();
    simplifyNames();
    simplifyConstants();
    getVarInfo_All();
    getSymbolInfo_All();
    
    # clean memory
    %LibInfo = ();
    %TemplateInstance = ();
    %BasicTemplate = ();
    %MangledNames = ();
    %TemplateDecl = ();
    %StdCxxTypedef = ();
    %MissedTypedef = ();
    %Typedef_Tr = ();
    %Typedef_Eq = ();
    %TypedefToAnon = ();
    
    # clean cache
    delete($Cache{"getTypeAttr"});
    delete($Cache{"getTypeDeclId"});
    
    if($In::Opt{"ExtraDump"})
    {
        remove_Unused($V, "Extra");
    }
    else
    { # remove unused types
        if($In::Opt{"BinOnly"} and not $In::Opt{"ExtendedCheck"})
        { # --binary
            remove_Unused($V, "All");
        }
        else {
            remove_Unused($V, "Extended");
        }
    }
    
    if($In::Opt{"CheckInfo"})
    {
        foreach my $Tid (keys(%{$TypeInfo{$V}})) {
            checkCompleteness($TypeInfo{$V}{$Tid});
        }
        
        foreach my $Sid (keys(%{$SymbolInfo{$V}})) {
            checkCompleteness($SymbolInfo{$V}{$Sid});
        }
    }
}

sub checkCompleteness($)
{
    my $Info = $_[0];
    
    # data types
    if(defined $Info->{"Memb"})
    {
        foreach my $Pos (keys(%{$Info->{"Memb"}}))
        {
            if(defined $Info->{"Memb"}{$Pos}{"type"}) {
                checkTypeInfo($Info->{"Memb"}{$Pos}{"type"});
            }
        }
    }
    if(defined $Info->{"Base"})
    {
        foreach my $Bid (keys(%{$Info->{"Base"}})) {
            checkTypeInfo($Bid);
        }
    }
    if(defined $Info->{"BaseType"}) {
        checkTypeInfo($Info->{"BaseType"});
    }
    if(defined $Info->{"TParam"})
    {
        foreach my $Pos (keys(%{$Info->{"TParam"}}))
        {
            my $TName = $Info->{"TParam"}{$Pos}{"name"};
            if($TName=~/\A\(.+\)(true|false|\d.*)\Z/) {
                next;
            }
            if($TName eq "_BoolType") {
                next;
            }
            if($TName=~/\Asizeof\(/) {
                next;
            }
            if(my $Tid = $TName_Tid{$V}{$TName}) {
                checkTypeInfo($Tid);
            }
            else
            {
                if(defined $In::Opt{"Debug"}) {
                    printMsg("WARNING", "missed type $TName");
                }
            }
        }
    }
    
    # symbols
    if(defined $Info->{"Param"})
    {
        foreach my $Pos (keys(%{$Info->{"Param"}}))
        {
            if(defined $Info->{"Param"}{$Pos}{"type"}) {
                checkTypeInfo($Info->{"Param"}{$Pos}{"type"});
            }
        }
    }
    if(defined $Info->{"Return"}) {
        checkTypeInfo($Info->{"Return"});
    }
    if(defined $Info->{"Class"}) {
        checkTypeInfo($Info->{"Class"});
    }
}

sub checkTypeInfo($)
{
    my $Tid = $_[0];
    
    if(defined $CheckedTypeInfo{$V}{$Tid}) {
        return;
    }
    $CheckedTypeInfo{$V}{$Tid} = 1;
    
    if(defined $TypeInfo{$V}{$Tid})
    {
        if(not $TypeInfo{$V}{$Tid}{"Name"}) {
            printMsg("ERROR", "missed type name ($Tid)");
        }
        checkCompleteness($TypeInfo{$V}{$Tid});
    }
    else {
        printMsg("ERROR", "missed type id $Tid");
    }
}

sub getSymbolInfo_All()
{
    foreach (sort {$b<=>$a} keys(%{$LibInfo{$V}{"info"}}))
    { # reverse order
        if($LibInfo{$V}{"info_type"}{$_} eq "function_decl") {
            getSymbolInfo($_);
        }
    }
    
    if($In::Opt{"AddTemplateInstances"})
    {
        # templates
        foreach my $Sid (sort {$a<=>$b} keys(%{$SymbolInfo{$V}}))
        {
            my %Map = ();
            
            if(my $ClassId = $SymbolInfo{$V}{$Sid}{"Class"})
            {
                if(defined $TemplateMap{$V}{$ClassId})
                {
                    foreach (keys(%{$TemplateMap{$V}{$ClassId}})) {
                        $Map{$_} = $TemplateMap{$V}{$ClassId}{$_};
                    }
                }
            }
            
            if(defined $TemplateMap{$V}{$Sid})
            {
                foreach (keys(%{$TemplateMap{$V}{$Sid}})) {
                    $Map{$_} = $TemplateMap{$V}{$Sid}{$_};
                }
            }
            
            if(defined $SymbolInfo{$V}{$Sid}{"Param"})
            {
                foreach (sort {$a<=>$b} keys(%{$SymbolInfo{$V}{$Sid}{"Param"}}))
                {
                    my $PTid = $SymbolInfo{$V}{$Sid}{"Param"}{$_}{"type"};
                    $SymbolInfo{$V}{$Sid}{"Param"}{$_}{"type"} = instType(\%Map, $PTid);
                }
            }
            if(my $Return = $SymbolInfo{$V}{$Sid}{"Return"}) {
                $SymbolInfo{$V}{$Sid}{"Return"} = instType(\%Map, $Return);
            }
        }
    }
}

sub getVarInfo_All()
{
    foreach (sort {$b<=>$a} keys(%{$LibInfo{$V}{"info"}}))
    { # reverse order
        if($LibInfo{$V}{"info_type"}{$_} eq "var_decl") {
            getVarInfo($_);
        }
    }
}

sub getTypeInfo_All()
{
    if(not checkGcc("4.5"))
    { # support for GCC < 4.5
      # missed typedefs: QStyle::State is typedef to QFlags<QStyle::StateFlag>
      # but QStyleOption.state is of type QFlags<QStyle::StateFlag> in the TU dump
      # FIXME: check GCC versions
        addMissedTypes_Pre();
    }
    
    foreach (sort {$a<=>$b} keys(%{$LibInfo{$V}{"info"}}))
    { # forward order only
        my $IType = $LibInfo{$V}{"info_type"}{$_};
        if($IType=~/_type\Z/ and $IType ne "function_type"
        and $IType ne "method_type") {
            getTypeInfo("$_");
        }
    }
    
    # add "..." type
    $TypeInfo{$V}{"-1"} = {
        "Name" => "...",
        "Type" => "Intrinsic",
        "Tid" => "-1"
    };
    $TName_Tid{$V}{"..."} = "-1";
    
    if(not checkGcc("4.5"))
    { # support for GCC < 4.5
        addMissedTypes_Post();
    }
    
    if($In::Opt{"AddTemplateInstances"})
    {
        # templates
        foreach my $Tid (sort {$a<=>$b} keys(%{$TypeInfo{$V}}))
        {
            if(defined $TemplateMap{$V}{$Tid}
            and not defined $TypeInfo{$V}{$Tid}{"Template"})
            {
                if(defined $TypeInfo{$V}{$Tid}{"Memb"})
                {
                    foreach my $Pos (sort {$a<=>$b} keys(%{$TypeInfo{$V}{$Tid}{"Memb"}}))
                    {
                        if(my $MembTypeId = $TypeInfo{$V}{$Tid}{"Memb"}{$Pos}{"type"})
                        {
                            if(my $MAttr = getTypeAttr($MembTypeId))
                            {
                                $TypeInfo{$V}{$Tid}{"Memb"}{$Pos}{"algn"} = $MAttr->{"Algn"};
                                $MembTypeId = $TypeInfo{$V}{$Tid}{"Memb"}{$Pos}{"type"} = instType($TemplateMap{$V}{$Tid}, $MembTypeId);
                            }
                        }
                    }
                }
                if(defined $TypeInfo{$V}{$Tid}{"Base"})
                {
                    foreach my $Bid (sort {$a<=>$b} keys(%{$TypeInfo{$V}{$Tid}{"Base"}}))
                    {
                        my $NBid = instType($TemplateMap{$V}{$Tid}, $Bid);
                        
                        if($NBid ne $Bid
                        and $NBid ne $Tid)
                        {
                            %{$TypeInfo{$V}{$Tid}{"Base"}{$NBid}} = %{$TypeInfo{$V}{$Tid}{"Base"}{$Bid}};
                            delete($TypeInfo{$V}{$Tid}{"Base"}{$Bid});
                        }
                    }
                }
            }
        }
    }
}

sub getVarInfo($)
{
    my $InfoId = $_[0];
    if(my $NSid = getTreeAttr_Scpe($InfoId))
    {
        my $NSInfoType = $LibInfo{$V}{"info_type"}{$NSid};
        if($NSInfoType and $NSInfoType eq "function_decl") {
            return;
        }
    }
    
    if(not $SymbolInfo{$V}{$InfoId}) {
        $SymbolInfo{$V}{$InfoId} = {};
    }
    
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    ($SInfo->{"Header"}, $SInfo->{"Line"}) = getLocation($InfoId);
    if(not $SInfo->{"Header"}
    or isBuiltIn($SInfo->{"Header"})) {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    my $ShortName = getTreeStr(getTreeAttr_Name($InfoId));
    if(not $ShortName) {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    if($ShortName=~/\Atmp_add_class_\d+\Z/) {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    $SInfo->{"ShortName"} = $ShortName;
    if(my $MnglName = getTreeStr(getTreeAttr_Mngl($InfoId)))
    {
        if($In::Opt{"OS"} eq "windows")
        { # cut the offset
            $MnglName=~s/\@\d+\Z//g;
        }
        $SInfo->{"MnglName"} = $MnglName;
    }
    if($SInfo->{"MnglName"}
    and index($SInfo->{"MnglName"}, "_Z")!=0)
    { # validate mangled name
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    if(not $SInfo->{"MnglName"}
    and index($ShortName, "_Z")==0)
    { # _ZTS, etc.
        $SInfo->{"MnglName"} = $ShortName;
    }
    if(isPrivateData($SInfo->{"MnglName"}))
    { # non-public global data
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    $SInfo->{"Data"} = 1;
    if(my $Rid = getTypeId($InfoId))
    {
        if(not defined $TypeInfo{$V}{$Rid}
        or not $TypeInfo{$V}{$Rid}{"Name"})
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
        $SInfo->{"Return"} = $Rid;
        my $Val = getDataVal($InfoId, $Rid);
        if(defined $Val) {
            $SInfo->{"Value"} = $Val;
        }
    }
    setClassAndNs($InfoId);
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(not defined $TypeInfo{$V}{$ClassId}
        or not $TypeInfo{$V}{$ClassId}{"Name"})
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(not $In::Opt{"StdcxxTesting"})
        { # stdc++ data
            if(index($TypeInfo{$V}{$ClassId}{"Name"}, "std::")==0)
            {
                delete($SymbolInfo{$V}{$InfoId});
                return;
            }
        }
        
        if($TypeInfo{$V}{$ClassId}{"NameSpace"})
        {
            if(index($TypeInfo{$V}{$ClassId}{"NameSpace"}, "__gnu_cxx")==0)
            {
                delete($SymbolInfo{$V}{$InfoId});
                return;
            }
        }
    }
    
    if($SInfo->{"NameSpace"})
    {
        if(index($SInfo->{"NameSpace"}, "__gnu_cxx")==0)
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    
    if($LibInfo{$V}{"info"}{$InfoId}=~/ lang:[ ]*C /i)
    { # extern "C"
        $SInfo->{"Lang"} = "C";
        $SInfo->{"MnglName"} = $ShortName;
    }
    if($In::Opt{"UserLang"} eq "C")
    { # --lang=C option
        $SInfo->{"MnglName"} = $ShortName;
    }
    if(not $In::Opt{"CheckHeadersOnly"})
    {
        if(not $SInfo->{"Class"})
        {
            if(not $SInfo->{"MnglName"}
            or not linkSymbol($SInfo->{"MnglName"}, $V, "-Deps"))
            {
                if(linkSymbol($ShortName, $V, "-Deps"))
                { # "const" global data is mangled as _ZL... in the TU dump
                  # but not mangled when compiling a C shared library
                    $SInfo->{"MnglName"} = $ShortName;
                }
            }
        }
    }
    if($In::ABI{$V}{"Language"} eq "C++")
    {
        if(not $SInfo->{"MnglName"})
        { # for some symbols (_ZTI) the short name is the mangled name
            if(index($ShortName, "_Z")==0) {
                $SInfo->{"MnglName"} = $ShortName;
            }
        }
        
        if(not $SInfo->{"MnglName"}
        or $In::Opt{"Target"} eq "windows")
        { # try to mangle symbol (link with libraries)
            if(my $Mangled = linkWithSymbol($InfoId)) {
                $SInfo->{"MnglName"} = $Mangled;
            }
        }
    }
    if(not $SInfo->{"MnglName"})
    {
        if($SInfo->{"Class"}) {
            return;
        }
        $SInfo->{"MnglName"} = $ShortName;
    }
    if(my $Symbol = $SInfo->{"MnglName"})
    {
        if(not selectSymbol($Symbol, $SInfo, "Dump", $V))
        { # non-target symbols
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    if(my $Rid = $SInfo->{"Return"})
    {
        if(defined $MissedTypedef{$V}{$Rid})
        {
            if(my $AddedTid = $MissedTypedef{$V}{$Rid}{"Tid"}) {
                $SInfo->{"Return"} = $AddedTid;
            }
        }
    }
    setFuncAccess($InfoId);
    if(index($SInfo->{"MnglName"}, "_ZTV")==0) {
        delete($SInfo->{"Return"});
    }
    if($ShortName=~/\A(_Z|\?)/) {
        delete($SInfo->{"ShortName"});
    }
    
    if($In::Opt{"ExtraDump"}) {
        $SInfo->{"Header"} = guessHeader($InfoId);
    }
}

sub getSymbolInfo($)
{
    my $InfoId = $_[0];
    if(isInternal($InfoId)) { 
        return;
    }
    
    if(not $SymbolInfo{$V}{$InfoId}) {
        $SymbolInfo{$V}{$InfoId} = {};
    }
    
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    ($SInfo->{"Header"}, $SInfo->{"Line"}) = getLocation($InfoId);
    if(not $SInfo->{"Header"}
    or isBuiltIn($SInfo->{"Header"}))
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    setFuncAccess($InfoId);
    setFuncKind($InfoId);
    if($SInfo->{"PseudoTemplate"})
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    
    $SInfo->{"Type"} = getFuncType($InfoId);
    if(my $Return = getFuncReturn($InfoId))
    {
        if(not defined $TypeInfo{$V}{$Return}
        or not $TypeInfo{$V}{$Return}{"Name"})
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
        $SInfo->{"Return"} = $Return;
    }
    if(my $Rid = $SInfo->{"Return"})
    {
        if(defined $MissedTypedef{$V}{$Rid})
        {
            if(my $AddedTid = $MissedTypedef{$V}{$Rid}{"Tid"}) {
                $SInfo->{"Return"} = $AddedTid;
            }
        }
    }
    if(not $SInfo->{"Return"}) {
        delete($SInfo->{"Return"});
    }
    my $Orig = getFuncOrig($InfoId);
    $SInfo->{"ShortName"} = getFuncShortName($Orig);
    if(index($SInfo->{"ShortName"}, "\._")!=-1)
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    
    if(index($SInfo->{"ShortName"}, "tmp_add_func")==0)
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    
    if(defined $TemplateInstance{$V}{"Func"}{$Orig})
    {
        my $Tmpl = $BasicTemplate{$V}{$InfoId};
        
        my @TParams = getTParams($Orig, "Func");
        if(not @TParams)
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
        foreach my $Pos (0 .. $#TParams)
        {
            my $Val = $TParams[$Pos];
            $SInfo->{"TParam"}{$Pos}{"name"} = $Val;
            
            if($Tmpl)
            {
                if(my $Arg = $TemplateArg{$V}{$Tmpl}{$Pos})
                {
                    $TemplateMap{$V}{$InfoId}{$Arg} = $Val;
                }
            }
        }
        
        if($Tmpl)
        {
            foreach my $Pos (sort {$a<=>$b} keys(%{$TemplateArg{$V}{$Tmpl}}))
            {
                if($Pos>$#TParams)
                {
                    my $Arg = $TemplateArg{$V}{$Tmpl}{$Pos};
                    $TemplateMap{$V}{$InfoId}{$Arg} = "";
                }
            }
        }
        
        if($SInfo->{"ShortName"}=~/\Aoperator\W+\Z/)
        { # operator<< <T>, operator>> <T>
            $SInfo->{"ShortName"} .= " ";
        }
        
        if(@TParams) {
            $SInfo->{"ShortName"} .= "<".join(", ", @TParams).">";
        }
        else {
            $SInfo->{"ShortName"} .= "<...>";
        }
        
        $SInfo->{"ShortName"} = formatName($SInfo->{"ShortName"}, "S");
    }
    else
    { # support for GCC 3.4
        $SInfo->{"ShortName"}=~s/<.+>\Z//;
    }
    if(my $MnglName = getTreeStr(getTreeAttr_Mngl($InfoId)))
    {
        if($In::Opt{"OS"} eq "windows")
        { # cut the offset
            $MnglName=~s/\@\d+\Z//g;
        }
        $SInfo->{"MnglName"} = $MnglName;
        
        # NOTE: mangling of some symbols may change depending on GCC version
        # GCC 4.6: _ZN28QExplicitlySharedDataPointerI11QPixmapDataEC2IT_EERKS_IT_E
        # GCC 4.7: _ZN28QExplicitlySharedDataPointerI11QPixmapDataEC2ERKS1_
    }
    
    if($SInfo->{"MnglName"}
    and index($SInfo->{"MnglName"}, "_Z")!=0)
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    if(not $SInfo->{"Destructor"})
    { # destructors have an empty parameter list
        my $Skip = setFuncParams($InfoId);
        if($Skip)
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    if($LibInfo{$V}{"info"}{$InfoId}=~/ artificial /i) {
        $SInfo->{"Artificial"} = 1;
    }
    
    if(setClassAndNs($InfoId))
    {
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(not defined $TypeInfo{$V}{$ClassId}
        or not $TypeInfo{$V}{$ClassId}{"Name"})
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    
    if($SInfo->{"Constructor"})
    {
        my $CShort = getFuncShortName($InfoId);
        
        if($CShort eq "__comp_ctor") {
            $SInfo->{"Constructor"} = "C1";
        }
        elsif($CShort eq "__base_ctor") {
            $SInfo->{"Constructor"} = "C2";
        }
    }
    elsif($SInfo->{"Destructor"})
    {
        my $DShort = getFuncShortName($InfoId);
        
        if($DShort eq "__deleting_dtor") {
            $SInfo->{"Destructor"} = "D0";
        }
        elsif($DShort eq "__comp_dtor") {
            $SInfo->{"Destructor"} = "D1";
        }
        elsif($DShort eq "__base_dtor") {
            $SInfo->{"Destructor"} = "D2";
        }
    }
    
    if(not $SInfo->{"Constructor"}
    and my $Spec = getVirtSpec($Orig))
    { # identify virtual and pure virtual functions
      # NOTE: constructors cannot be virtual
      # NOTE: in GCC 4.7 D1 destructors have no virtual spec
      # in the TU dump, so taking it from the original symbol
        if(not ($SInfo->{"Destructor"}
        and $SInfo->{"Destructor"} eq "D2"))
        { # NOTE: D2 destructors are not present in a v-table
            $SInfo->{$Spec} = 1;
        }
    }
    
    if(isInline($InfoId)) {
        $SInfo->{"InLine"} = 1;
    }
    
    if(hasThrow($InfoId)) {
        $SInfo->{"Throw"} = 1;
    }
    
    if($SInfo->{"Constructor"}
    and my $ClassId = $SInfo->{"Class"})
    {
        if(not $SInfo->{"InLine"}
        and not $SInfo->{"Artificial"})
        { # inline or auto-generated constructor
            delete($TypeInfo{$V}{$ClassId}{"Copied"});
        }
    }
    
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(not $In::Opt{"StdcxxTesting"})
        { # stdc++ interfaces
            if(not $SInfo->{"Virt"} and not $SInfo->{"PureVirt"})
            {
                if(index($TypeInfo{$V}{$ClassId}{"Name"}, "std::")==0)
                {
                    delete($SymbolInfo{$V}{$InfoId});
                    return;
                }
            }
        }
        
        if($TypeInfo{$V}{$ClassId}{"NameSpace"})
        {
            if(index($TypeInfo{$V}{$ClassId}{"NameSpace"}, "__gnu_cxx")==0)
            {
                delete($SymbolInfo{$V}{$InfoId});
                return;
            }
        }
    }
    
    if($SInfo->{"NameSpace"})
    {
        if(index($SInfo->{"NameSpace"}, "__gnu_cxx")==0)
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    
    if($LibInfo{$V}{"info"}{$InfoId}=~/ lang:[ ]*C /i)
    { # extern "C"
        $SInfo->{"Lang"} = "C";
        $SInfo->{"MnglName"} = $SInfo->{"ShortName"};
    }
    if($In::Opt{"UserLang"} eq "C")
    { # --lang=C option
        $SInfo->{"MnglName"} = $SInfo->{"ShortName"};
    }
    
    if($In::ABI{$V}{"Language"} eq "C++")
    { # correct mangled & short names
      # C++ or --headers-only mode
        if($SInfo->{"ShortName"}=~/\A__(comp|base|deleting)_(c|d)tor\Z/)
        { # support for old GCC versions: reconstruct real names for constructors and destructors
            $SInfo->{"ShortName"} = getNameByInfo(getTypeDeclId($SInfo->{"Class"}));
            $SInfo->{"ShortName"}=~s/<.+>\Z//;
        }
        
        if(not $SInfo->{"MnglName"}
        or $In::Opt{"Target"} eq "windows")
        { # try to mangle symbol (link with libraries)
            if(my $Mangled = linkWithSymbol($InfoId)) {
                $SInfo->{"MnglName"} = $Mangled;
            }
        }
    }
    else
    { # not mangled in C
        $SInfo->{"MnglName"} = $SInfo->{"ShortName"};
    }
    if(not $In::Opt{"CheckHeadersOnly"}
    and $SInfo->{"Type"} eq "Function"
    and not $SInfo->{"Class"})
    {
        my $Incorrect = 0;
        
        if($SInfo->{"MnglName"})
        {
            if(index($SInfo->{"MnglName"}, "_Z")==0
            and not linkSymbol($SInfo->{"MnglName"}, $V, "-Deps"))
            { # mangled in the TU dump, but not mangled in the library
                $Incorrect = 1;
            }
        }
        else
        {
            if($SInfo->{"Lang"} ne "C")
            { # all C++ functions are not mangled in the TU dump
                $Incorrect = 1;
            }
        }
        if($Incorrect)
        {
            if(linkSymbol($SInfo->{"ShortName"}, $V, "-Deps")) {
                $SInfo->{"MnglName"} = $SInfo->{"ShortName"};
            }
        }
    }
    
    if(not $SInfo->{"MnglName"})
    { # can't detect symbol name
        delete($SymbolInfo{$V}{$InfoId});
        return;
    }
    
    if(my $Symbol = $SInfo->{"MnglName"})
    {
        if(not $In::Opt{"ExtraDump"})
        {
            if(not selectSymbol($Symbol, $SInfo, "Dump", $V))
            { # non-target symbols
                delete($SymbolInfo{$V}{$InfoId});
                return;
            }
        }
    }
    if($SInfo->{"Type"} eq "Method"
    or $SInfo->{"Constructor"}
    or $SInfo->{"Destructor"}
    or $SInfo->{"Class"})
    {
        if($SInfo->{"MnglName"}!~/\A(_Z|\?)/)
        {
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
    }
    if($SInfo->{"MnglName"})
    {
        if($MangledNames{$V}{$SInfo->{"MnglName"}})
        { # one instance for one mangled name only
            delete($SymbolInfo{$V}{$InfoId});
            return;
        }
        else {
            $MangledNames{$V}{$SInfo->{"MnglName"}} = 1;
        }
    }
    if($SInfo->{"Constructor"}
    or $SInfo->{"Destructor"}) {
        delete($SInfo->{"Return"});
    }
    if($SInfo->{"MnglName"}=~/\A(_Z|\?)/
    and $SInfo->{"Class"})
    {
        if($SInfo->{"Type"} eq "Function")
        { # static methods
            $SInfo->{"Static"} = 1;
        }
    }
    if(getFuncLink($InfoId) eq "Static") {
        $SInfo->{"Static"} = 1;
    }
    if($SInfo->{"MnglName"}=~/\A(_Z|\?)/)
    {
        if(my $Unmangled = getUnmangled($SInfo->{"MnglName"}, $V))
        {
            if($Unmangled=~/\.\_\d/)
            {
                delete($SymbolInfo{$V}{$InfoId});
                return;
            }
        }
    }
    
    if($SInfo->{"MnglName"}=~/\A_ZN(V|)K/) {
        $SInfo->{"Const"} = 1;
    }
    if($SInfo->{"MnglName"}=~/\A_ZN(K|)V/) {
        $SInfo->{"Volatile"} = 1;
    }
    
    if($In::ABI{$V}{"WeakSymbols"}{$SInfo->{"MnglName"}}) {
        $SInfo->{"Weak"} = 1;
    }
    
    if($In::Opt{"ExtraDump"}) {
        $SInfo->{"Header"} = guessHeader($InfoId);
    }
}

sub getTypeInfo($)
{
    my $TypeId = $_[0];
    $TypeInfo{$V}{$TypeId} = getTypeAttr($TypeId);
    my $TName = $TypeInfo{$V}{$TypeId}{"Name"};
    if(not $TName) {
        delete($TypeInfo{$V}{$TypeId});
    }
}

sub getTypeAttr($)
{
    my $TypeId = $_[0];
    
    if(defined $TypeInfo{$V}{$TypeId}
    and $TypeInfo{$V}{$TypeId}{"Name"})
    { # already created
        return $TypeInfo{$V}{$TypeId};
    }
    elsif($Cache{"getTypeAttr"}{$V}{$TypeId})
    { # incomplete type
        return {};
    }
    $Cache{"getTypeAttr"}{$V}{$TypeId} = 1;
    
    my %TypeAttr = ();
    
    my $TypeDeclId = getTypeDeclId($TypeId);
    $TypeAttr{"Tid"} = $TypeId;
    
    if(not $MissedBase{$V}{$TypeId} and isTypedef($TypeId))
    {
        if(my $Info = $LibInfo{$V}{"info"}{$TypeId})
        {
            if($Info=~/qual[ ]*:/)
            {
                my $NewId = ++$MAX_ID;
                
                $MissedBase{$V}{$TypeId} = "$NewId";
                $MissedBase_R{$V}{$NewId} = $TypeId;
                $LibInfo{$V}{"info"}{$NewId} = $LibInfo{$V}{"info"}{$TypeId};
                $LibInfo{$V}{"info_type"}{$NewId} = $LibInfo{$V}{"info_type"}{$TypeId};
            }
        }
        $TypeAttr{"Type"} = "Typedef";
    }
    else {
        $TypeAttr{"Type"} = getTypeType($TypeId);
    }
    
    if(my $ScopeId = getTreeAttr_Scpe($TypeDeclId))
    {
        if($LibInfo{$V}{"info_type"}{$ScopeId} eq "function_decl")
        { # local code
            return {};
        }
    }
    
    if($TypeAttr{"Type"} eq "Unknown") {
        return {};
    }
    elsif($TypeAttr{"Type"}=~/(Func|Method|Field)Ptr/)
    {
        my $MemPtrAttr = getMemPtrAttr(pointTo($TypeId), $TypeId, $TypeAttr{"Type"});
        if(my $TName = $MemPtrAttr->{"Name"})
        {
            $TypeInfo{$V}{$TypeId} = $MemPtrAttr;
            $TName_Tid{$V}{$TName} = $TypeId;
            return $MemPtrAttr;
        }
        
        return {};
    }
    elsif($TypeAttr{"Type"} eq "Array")
    {
        my ($BTid, $BTSpec) = selectBaseType($TypeId);
        if(not $BTid) {
            return {};
        }
        if(my $Algn = getAlgn($TypeId)) {
            $TypeAttr{"Algn"} = $Algn/$BYTE;
        }
        $TypeAttr{"BaseType"} = $BTid;
        if(my $BTAttr = getTypeAttr($BTid))
        {
            if(not $BTAttr->{"Name"}) {
                return {};
            }
            if(my $NElems = getArraySize($TypeId, $BTAttr->{"Name"}))
            {
                if(my $Size = getSize($TypeId)) {
                    $TypeAttr{"Size"} = $Size/$BYTE;
                }
                if($BTAttr->{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                    $TypeAttr{"Name"} = $1."[$NElems]".$2;
                }
                else {
                    $TypeAttr{"Name"} = $BTAttr->{"Name"}."[$NElems]";
                }
            }
            else
            {
                $TypeAttr{"Size"} = $In::ABI{$V}{"WordSize"}; # pointer
                if($BTAttr->{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                    $TypeAttr{"Name"} = $1."[]".$2;
                }
                else {
                    $TypeAttr{"Name"} = $BTAttr->{"Name"}."[]";
                }
            }
            $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}, "T");
            if($BTAttr->{"Header"})  {
                $TypeAttr{"Header"} = $BTAttr->{"Header"};
            }
            
            $TName_Tid{$V}{$TypeAttr{"Name"}} = $TypeId;
            $TypeInfo{$V}{$TypeId} = \%TypeAttr;
            return \%TypeAttr;
        }
        return {};
    }
    elsif($TypeAttr{"Type"}=~/\A(Intrinsic|Union|Struct|Enum|Class|Vector)\Z/)
    {
        my $TrivialAttr = getTrivialTypeAttr($TypeId);
        if($TrivialAttr->{"Name"})
        {
            $TypeInfo{$V}{$TypeId} = $TrivialAttr;
            
            if(not defined $IntrinsicNames{$TrivialAttr->{"Name"}}
            or getTypeDeclId($TrivialAttr->{"Tid"}))
            { # NOTE: register only one int: with built-in decl
                if(not $TName_Tid{$V}{$TrivialAttr->{"Name"}}) {
                    $TName_Tid{$V}{$TrivialAttr->{"Name"}} = $TypeId;
                }
            }
            
            return $TrivialAttr;
        }
        
        return {};
    }
    elsif($TypeAttr{"Type"}=~/TemplateParam|TypeName/)
    {
        my $TrivialAttr = getTrivialTypeAttr($TypeId);
        if($TrivialAttr->{"Name"})
        {
            $TypeInfo{$V}{$TypeId} = $TrivialAttr;
            if(not $TName_Tid{$V}{$TrivialAttr->{"Name"}}) {
                $TName_Tid{$V}{$TrivialAttr->{"Name"}} = $TypeId;
            }
            return $TrivialAttr;
        }
        
        return {};
    }
    elsif($TypeAttr{"Type"} eq "SizeOf")
    {
        $TypeAttr{"BaseType"} = getTreeAttr_Type($TypeId);
        my $BTAttr = getTypeAttr($TypeAttr{"BaseType"});
        $TypeAttr{"Name"} = "sizeof(".$BTAttr->{"Name"}.")";
        if($TypeAttr{"Name"})
        {
            $TypeInfo{$V}{$TypeId} = \%TypeAttr;
            return \%TypeAttr;
        }
        
        return {};
    }
    else
    { # derived types
        my ($BTid, $BTSpec) = selectBaseType($TypeId);
        if(not $BTid) {
            return {};
        }
        $TypeAttr{"BaseType"} = $BTid;
        if(defined $MissedTypedef{$V}{$BTid})
        {
            if(my $MissedTDid = $MissedTypedef{$V}{$BTid}{"TDid"})
            {
                if($MissedTDid ne $TypeDeclId) {
                    $TypeAttr{"BaseType"} = $MissedTypedef{$V}{$BTid}{"Tid"};
                }
            }
        }
        my $BTAttr = getTypeAttr($TypeAttr{"BaseType"});
        if(not $BTAttr->{"Name"})
        { # templates
            return {};
        }
        if($BTAttr->{"Type"} eq "Typedef")
        { # relinking typedefs
            my %BaseBase = getType($BTAttr->{"BaseType"}, $V);
            if($BTAttr->{"Name"} eq $BaseBase{"Name"}) {
                $TypeAttr{"BaseType"} = $BaseBase{"Tid"};
            }
        }
        if($BTSpec)
        {
            if($TypeAttr{"Type"} eq "Pointer"
            and $BTAttr->{"Name"}=~/\([\*]+\)/)
            {
                $TypeAttr{"Name"} = $BTAttr->{"Name"};
                $TypeAttr{"Name"}=~s/\(([*]+)\)/($1*)/g;
            }
            else {
                $TypeAttr{"Name"} = $BTAttr->{"Name"}." ".$BTSpec;
            }
        }
        else {
            $TypeAttr{"Name"} = $BTAttr->{"Name"};
        }
        if($TypeAttr{"Type"} eq "Typedef")
        {
            $TypeAttr{"Name"} = getNameByInfo($TypeDeclId);
            
            if(index($TypeAttr{"Name"}, "tmp_add_type")==0) {
                return {};
            }
            
            if(isAnon($TypeAttr{"Name"}))
            { # anon typedef to anon type: ._N
                return {};
            }
            
            if($LibInfo{$V}{"info"}{$TypeDeclId}=~/ artificial /i)
            { # artificial typedef of "struct X" to "X"
                $TypeAttr{"Artificial"} = 1;
            }
            
            if(my $NS = getNameSpace($TypeDeclId))
            {
                my $TypeName = $TypeAttr{"Name"};
                if($NS=~/\A(struct |union |class |)((.+)::|)\Q$TypeName\E\Z/)
                { # "some_type" is the typedef to "struct some_type" in C++
                    if($3) {
                        $TypeAttr{"Name"} = $3."::".$TypeName;
                    }
                }
                else
                {
                    $TypeAttr{"NameSpace"} = $NS;
                    $TypeAttr{"Name"} = $TypeAttr{"NameSpace"}."::".$TypeAttr{"Name"};
                    
                    if($TypeAttr{"NameSpace"}=~/\Astd(::|\Z)/
                    and $TypeAttr{"Name"}!~/>(::\w+)+\Z/)
                    {
                        if($BTAttr->{"NameSpace"}
                        and $BTAttr->{"NameSpace"}=~/\Astd(::|\Z)/ and $BTAttr->{"Name"}=~/</)
                        { # types like "std::fpos<__mbstate_t>" are
                          # not covered by typedefs in the TU dump
                          # so trying to add such typedefs manually
                            $StdCxxTypedef{$V}{$BTAttr->{"Name"}}{$TypeAttr{"Name"}} = 1;
                            if(length($TypeAttr{"Name"})<=length($BTAttr->{"Name"}))
                            {
                                if(($BTAttr->{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/))
                                { # skip "other" in "std" and "type" in "boost"
                                    $Typedef_Eq{$V}{$BTAttr->{"Name"}} = $TypeAttr{"Name"};
                                }
                            }
                        }
                    }
                }
            }
            if($TypeAttr{"Name"} ne $BTAttr->{"Name"} and not $TypeAttr{"Artificial"}
            and $TypeAttr{"Name"}!~/>(::\w+)+\Z/ and $BTAttr->{"Name"}!~/>(::\w+)+\Z/)
            {
                $In::ABI{$V}{"TypedefBase"}{$TypeAttr{"Name"}} = $BTAttr->{"Name"};
                if($BTAttr->{"Name"}=~/</)
                {
                    if(($BTAttr->{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/)) {
                        $Typedef_Tr{$V}{$BTAttr->{"Name"}}{$TypeAttr{"Name"}} = 1;
                    }
                }
            }
            ($TypeAttr{"Header"}, $TypeAttr{"Line"}) = getLocation($TypeDeclId);
        }
        if(not $TypeAttr{"Size"})
        {
            if($TypeAttr{"Type"} eq "Pointer") {
                $TypeAttr{"Size"} = $In::ABI{$V}{"WordSize"};
            }
            elsif($BTAttr->{"Size"}) {
                $TypeAttr{"Size"} = $BTAttr->{"Size"};
            }
        }
        if(my $Algn = getAlgn($TypeId)) {
            $TypeAttr{"Algn"} = $Algn/$BYTE;
        }
        $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}, "T");
        if(not $TypeAttr{"Header"} and $BTAttr->{"Header"})  {
            $TypeAttr{"Header"} = $BTAttr->{"Header"};
        }
        %{$TypeInfo{$V}{$TypeId}} = %TypeAttr;
        if($TypeAttr{"Name"} ne $BTAttr->{"Name"})
        { # typedef to "class Class"
          # should not be registered in TName_Tid
            if(not $TName_Tid{$V}{$TypeAttr{"Name"}}) {
                $TName_Tid{$V}{$TypeAttr{"Name"}} = $TypeId;
            }
        }
        return \%TypeAttr;
    }
}

sub getTrivialName($$)
{
    my ($TypeInfoId, $TypeId) = @_;
    my %TypeAttr = ();
    $TypeAttr{"Name"} = getNameByInfo($TypeInfoId);
    if(not $TypeAttr{"Name"}) {
        $TypeAttr{"Name"} = getTreeTypeName($TypeId);
    }
    ($TypeAttr{"Header"}, $TypeAttr{"Line"}) = getLocation($TypeInfoId);
    $TypeAttr{"Type"} = getTypeType($TypeId);
    $TypeAttr{"Name"}=~s/<(.+)\Z//g; # GCC 3.4.4 add template params to the name
    if(isAnon($TypeAttr{"Name"}))
    {
        my $NameSpaceId = $TypeId;
        while(my $NSId = getTreeAttr_Scpe(getTypeDeclId($NameSpaceId)))
        { # searching for a first not anon scope
            if($NSId eq $NameSpaceId) {
                last;
            }
            else
            {
                $TypeAttr{"NameSpace"} = getNameSpace(getTypeDeclId($TypeId));
                if(not $TypeAttr{"NameSpace"}
                or not isAnon($TypeAttr{"NameSpace"})) {
                    last;
                }
            }
            $NameSpaceId = $NSId;
        }
    }
    else
    {
        if(my $NameSpaceId = getTreeAttr_Scpe($TypeInfoId))
        {
            if($NameSpaceId ne $TypeId) {
                $TypeAttr{"NameSpace"} = getNameSpace($TypeInfoId);
            }
        }
    }
    if($TypeAttr{"NameSpace"} and not isAnon($TypeAttr{"Name"})) {
        $TypeAttr{"Name"} = $TypeAttr{"NameSpace"}."::".$TypeAttr{"Name"};
    }
    $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}, "T");
    if(isAnon($TypeAttr{"Name"}))
    { # anon-struct-header.h-line
        $TypeAttr{"Name"} = "anon-".lc($TypeAttr{"Type"})."-";
        $TypeAttr{"Name"} .= $TypeAttr{"Header"}."-".$TypeAttr{"Line"};
        if($TypeAttr{"NameSpace"}) {
            $TypeAttr{"Name"} = $TypeAttr{"NameSpace"}."::".$TypeAttr{"Name"};
        }
    }
    if(defined $TemplateInstance{$V}{"Type"}{$TypeId}
    and getTypeDeclId($TypeId) eq $TypeInfoId)
    {
        if(my @TParams = getTParams($TypeId, "Type")) {
            $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}."< ".join(", ", @TParams)." >", "T");
        }
        else {
            $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}."<...>", "T");
        }
    }
    return ($TypeAttr{"Name"}, $TypeAttr{"NameSpace"});
}

sub getTrivialTypeAttr($)
{
    my $TypeId = $_[0];
    my $TypeInfoId = getTypeDeclId($_[0]);
    
    my %TypeAttr = ();
    
    if($TemplateDecl{$V}{$TypeId})
    { # template_decl
        $TypeAttr{"Template"} = 1;
    }
    
    setTypeAccess($TypeId, \%TypeAttr);
    ($TypeAttr{"Header"}, $TypeAttr{"Line"}) = getLocation($TypeInfoId);
    if(isBuiltIn($TypeAttr{"Header"}))
    {
        delete($TypeAttr{"Header"});
        delete($TypeAttr{"Line"});
    }
    
    $TypeAttr{"Type"} = getTypeType($TypeId);
    ($TypeAttr{"Name"}, $TypeAttr{"NameSpace"}) = getTrivialName($TypeInfoId, $TypeId);
    if(not $TypeAttr{"Name"}) {
        return {};
    }
    if(not $TypeAttr{"NameSpace"}) {
        delete($TypeAttr{"NameSpace"});
    }
    
    if($TypeAttr{"Type"} eq "Intrinsic")
    {
        if(defined $TypeAttr{"Header"})
        {
            if($TypeAttr{"Header"}=~/\Adump[1-2]\.[ih]\Z/)
            { # support for SUSE 11.2
              # integer_type has srcp dump{1-2}.i
                delete($TypeAttr{"Header"});
            }
        }
    }
    
    my $Tmpl = undef;
    
    if(defined $TemplateInstance{$V}{"Type"}{$TypeId})
    {
        $Tmpl = $BasicTemplate{$V}{$TypeId};
        
        if(my @TParams = getTParams($TypeId, "Type"))
        {
            foreach my $Pos (0 .. $#TParams)
            {
                my $Val = $TParams[$Pos];
                $TypeAttr{"TParam"}{$Pos}{"name"} = $Val;
                
                if(not defined $TypeAttr{"Template"})
                {
                    my %Base = getBaseType($TemplateInstance{$V}{"Type"}{$TypeId}{$Pos}, $V);
                    
                    if($Base{"Type"} eq "TemplateParam"
                    or defined $Base{"Template"}) {
                        $TypeAttr{"Template"} = 1;
                    }
                }
                
                if($Tmpl)
                {
                    if(my $Arg = $TemplateArg{$V}{$Tmpl}{$Pos})
                    {
                        $TemplateMap{$V}{$TypeId}{$Arg} = $Val;
                        
                        if($Val eq $Arg) {
                            $TypeAttr{"Template"} = 1;
                        }
                    }
                }
            }
            
            if($Tmpl)
            {
                foreach my $Pos (sort {$a<=>$b} keys(%{$TemplateArg{$V}{$Tmpl}}))
                {
                    if($Pos>$#TParams)
                    {
                        my $Arg = $TemplateArg{$V}{$Tmpl}{$Pos};
                        $TemplateMap{$V}{$TypeId}{$Arg} = "";
                    }
                }
            }
        }
        
        if($In::Opt{"AddTemplateInstances"})
        {
            if($Tmpl)
            {
                if(my $MainInst = getTreeAttr_Type($Tmpl))
                {
                    if(not getTreeAttr_Flds($TypeId))
                    {
                        if(my $Flds = getTreeAttr_Flds($MainInst)) {
                            $LibInfo{$V}{"info"}{$TypeId} .= " flds: \@$Flds ";
                        }
                    }
                    if(not getTreeAttr_Binf($TypeId))
                    {
                        if(my $Binf = getTreeAttr_Binf($MainInst)) {
                            $LibInfo{$V}{"info"}{$TypeId} .= " binf: \@$Binf ";
                        }
                    }
                }
            }
        }
    }
    
    my $StaticFields = setTypeMemb($TypeId, \%TypeAttr);
    
    if(my $Size = getSize($TypeId))
    {
        $Size = $Size/$BYTE;
        $TypeAttr{"Size"} = "$Size";
    }
    else
    {
        if($In::Opt{"ExtraDump"})
        {
            if(not defined $TypeAttr{"Memb"}
            and not $Tmpl)
            { # declaration only
                $TypeAttr{"Forward"} = 1;
            }
        }
    }
    
    if($TypeAttr{"Type"} eq "Struct"
    and ($StaticFields or detectLang($TypeId)))
    {
        $TypeAttr{"Type"} = "Class";
        $TypeAttr{"Copied"} = 1; # default, will be changed in getSymbolInfo()
    }
    if($TypeAttr{"Type"} eq "Struct"
    or $TypeAttr{"Type"} eq "Class")
    {
        my $Skip = setBaseClasses($TypeId, \%TypeAttr);
        if($Skip) {
            return {};
        }
    }
    if(my $Algn = getAlgn($TypeId)) {
        $TypeAttr{"Algn"} = $Algn/$BYTE;
    }
    setSpec($TypeId, \%TypeAttr);
    
    if($TypeAttr{"Type"}=~/\A(Struct|Union|Enum)\Z/)
    {
        if(not $TypedefToAnon{$TypeId}
        and not defined $TemplateInstance{$V}{"Type"}{$TypeId})
        {
            if(not isAnon($TypeAttr{"Name"})) {
                $TypeAttr{"Name"} = lc($TypeAttr{"Type"})." ".$TypeAttr{"Name"};
            }
        }
    }
    
    $TypeAttr{"Tid"} = $TypeId;
    
    if(my $VTable = $In::ABI{$V}{"ClassVTable_Content"}{$TypeAttr{"Name"}})
    {
        my @Entries = split(/\n/, $VTable);
        foreach (1 .. $#Entries)
        {
            my $Entry = $Entries[$_];
            if($Entry=~/\A(\d+)\s+(.+)\Z/) {
                $TypeAttr{"VTable"}{$1} = simplifyVTable($2);
            }
        }
    }
    
    if($TypeAttr{"Type"} eq "Enum")
    {
        if(not $TypeAttr{"NameSpace"})
        {
            foreach my $Pos (keys(%{$TypeAttr{"Memb"}}))
            {
                my $MName = $TypeAttr{"Memb"}{$Pos}{"name"};
                my $MVal = $TypeAttr{"Memb"}{$Pos}{"value"};
                $In::ABI{$V}{"EnumConstants"}{$MName} = {
                    "Value"=>$MVal,
                    "Header"=>$TypeAttr{"Header"}
                };
                if(isAnon($TypeAttr{"Name"}))
                {
                    if($In::Opt{"ExtraDump"} or isTargetHeader($TypeAttr{"Header"}, $V)
                    or isTargetSource($TypeAttr{"Source"}, $V))
                    {
                        $In::ABI{$V}{"Constants"}{$MName} = {
                            "Value" => $MVal,
                            "Header" => $TypeAttr{"Header"}
                        };
                    }
                }
            }
        }
    }
    if($In::Opt{"ExtraDump"})
    {
        if(defined $TypedefToAnon{$TypeId}) {
            $TypeAttr{"AnonTypedef"} = 1;
        }
    }
    
    return \%TypeAttr;
}

sub setAnonTypedef_All()
{
    foreach my $InfoId (keys(%{$LibInfo{$V}{"info"}}))
    {
        if($LibInfo{$V}{"info_type"}{$InfoId} eq "type_decl")
        {
            if(isAnon(getNameByInfo($InfoId))) {
                $TypedefToAnon{getTypeId($InfoId)} = 1;
            }
        }
    }
}

sub setTemplateParams_All()
{
    foreach (sort {$a<=>$b} keys(%{$LibInfo{$V}{"info"}}))
    {
        if($LibInfo{$V}{"info_type"}{$_} eq "template_decl") {
            setTemplateParams($_);
        }
    }
}

sub setTemplateParams($)
{
    my $Tid = getTypeId($_[0]);
    if(my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/(inst|spcs)[ ]*:[ ]*@(\d+) /)
        {
            my $TmplInst_Id = $2;
            setTemplateInstParams($_[0], $TmplInst_Id);
            while($TmplInst_Id = getNextElem($TmplInst_Id)) {
                setTemplateInstParams($_[0], $TmplInst_Id);
            }
        }
        
        $BasicTemplate{$V}{$Tid} = $_[0];
        
        if(my $Prms = getTreeAttr_Prms($_[0]))
        {
            if(my $Valu = getTreeAttr_Valu($Prms))
            {
                my $Vector = getTreeVec($Valu);
                foreach my $Pos (sort {$a<=>$b} keys(%{$Vector}))
                {
                    if(my $Val = getTreeAttr_Valu($Vector->{$Pos}))
                    {
                        if(my $Name = getNameByInfo($Val))
                        {
                            $TemplateArg{$V}{$_[0]}{$Pos} = $Name;
                            if($LibInfo{$V}{"info_type"}{$Val} eq "parm_decl") {
                                $TemplateInstance{$V}{"Type"}{$Tid}{$Pos} = $Val;
                            }
                            else {
                                $TemplateInstance{$V}{"Type"}{$Tid}{$Pos} = getTreeAttr_Type($Val);
                            }
                        }
                    }
                }
            }
        }
    }
    if(my $TypeId = getTreeAttr_Type($_[0]))
    {
        if(my $IType = $LibInfo{$V}{"info_type"}{$TypeId})
        {
            if($IType eq "record_type") {
                $TemplateDecl{$V}{$TypeId} = 1;
            }
        }
    }
}

sub setTemplateInstParams($$)
{
    my ($Tmpl, $Inst) = @_;
    
    if(my $Info = $LibInfo{$V}{"info"}{$Inst})
    {
        my ($Params_InfoId, $ElemId) = ();
        if($Info=~/purp[ ]*:[ ]*@(\d+) /) {
            $Params_InfoId = $1;
        }
        if($Info=~/valu[ ]*:[ ]*@(\d+) /) {
            $ElemId = $1;
        }
        if($Params_InfoId and $ElemId)
        {
            my $Params_Info = $LibInfo{$V}{"info"}{$Params_InfoId};
            while($Params_Info=~s/ (\d+)[ ]*:[ ]*\@(\d+) / /)
            {
                my ($PPos, $PTypeId) = ($1, $2);
                if(my $PType = $LibInfo{$V}{"info_type"}{$PTypeId})
                {
                    if($PType eq "template_type_parm") {
                        $TemplateDecl{$V}{$ElemId} = 1;
                    }
                }
                if($LibInfo{$V}{"info_type"}{$ElemId} eq "function_decl")
                { # functions
                    $TemplateInstance{$V}{"Func"}{$ElemId}{$PPos} = $PTypeId;
                    $BasicTemplate{$V}{$ElemId} = $Tmpl;
                }
                else
                { # types
                    $TemplateInstance{$V}{"Type"}{$ElemId}{$PPos} = $PTypeId;
                    $BasicTemplate{$V}{$ElemId} = $Tmpl;
                }
            }
        }
    }
}

sub getTypeDeclId($)
{
    my $Id = $_[0];
    if($Id)
    {
        if(defined $Cache{"getTypeDeclId"}{$V}{$Id}) {
            return $Cache{"getTypeDeclId"}{$V}{$Id};
        }
        if(my $Info = $LibInfo{$V}{"info"}{$Id})
        {
            if($Info=~/name[ ]*:[ ]*@(\d+)/) {
                return ($Cache{"getTypeDeclId"}{$V}{$Id} = $1);
            }
        }
    }
    return ($Cache{"getTypeDeclId"}{$V}{$Id} = 0);
}

sub addMissedTypes_Pre()
{
    my %MissedTypes = ();
    foreach my $MissedTDid (sort {$a<=>$b} keys(%{$LibInfo{$V}{"info"}}))
    { # detecting missed typedefs
        if($LibInfo{$V}{"info_type"}{$MissedTDid} eq "type_decl")
        {
            my $TypeId = getTreeAttr_Type($MissedTDid);
            next if(not $TypeId);
            my $TypeType = getTypeType($TypeId);
            if($TypeType eq "Unknown")
            { # template_type_parm
                next;
            }
            my $TypeDeclId = getTypeDeclId($TypeId);
            if($TypeDeclId eq $MissedTDid) {
                next;
            }
            if(my $TypedefName = getNameByInfo($MissedTDid))
            {
                if($TypedefName eq "__float80" or isAnon($TypedefName)) {
                    next;
                }
                
                if(not $TypeDeclId
                or getNameByInfo($TypeDeclId) ne $TypedefName) {
                    $MissedTypes{$V}{$TypeId}{$MissedTDid} = 1;
                }
            }
        }
    }
    my %AddTypes = ();
    foreach my $Tid (sort {$a<=>$b} keys(%{$MissedTypes{$V}}))
    { # add missed typedefs
        my @Missed = sort {$a<=>$b} keys(%{$MissedTypes{$V}{$Tid}});
        if(not @Missed or $#Missed>=1) {
            next;
        }
        my $MissedTDid = $Missed[0];
        my ($TypedefName, $TypedefNS) = getTrivialName($MissedTDid, $Tid);
        if(not $TypedefName) {
            next;
        }
        my $NewId = ++$MAX_ID;
        my %MissedInfo = ( # typedef info
            "Name" => $TypedefName,
            "NameSpace" => $TypedefNS,
            "BaseType" => $Tid,
            "Type" => "Typedef",
            "Tid" => "$NewId" );
        my ($H, $L) = getLocation($MissedTDid);
        $MissedInfo{"Header"} = $H;
        $MissedInfo{"Line"} = $L;
        if($TypedefName=~/\*|\&|\s/)
        { # other types
            next;
        }
        if($TypedefName=~/>(::\w+)+\Z/)
        { # QFlags<Qt::DropAction>::enum_type
            next;
        }
        if(getTypeType($Tid)=~/\A(Intrinsic|Union|Struct|Enum|Class)\Z/)
        { # double-check for the name of typedef
            my ($TName, $TNS) = getTrivialName(getTypeDeclId($Tid), $Tid); # base type info
            next if(not $TName);
            if(length($TypedefName)>=length($TName))
            { # too long typedef
                next;
            }
            if($TName=~/\A\Q$TypedefName\E</) {
                next;
            }
            if($TypedefName=~/\A\Q$TName\E/)
            { # QDateTimeEdit::Section and QDateTimeEdit::Sections::enum_type
                next;
            }
            if(getDepth($TypedefName)==0 and getDepth($TName)!=0)
            { # std::_Vector_base and std::vector::_Base
                next;
            }
        }
        
        $AddTypes{$MissedInfo{"Tid"}} = \%MissedInfo;
        
        # register typedef
        $MissedTypedef{$V}{$Tid}{"Tid"} = $MissedInfo{"Tid"};
        $MissedTypedef{$V}{$Tid}{"TDid"} = $MissedTDid;
        $TName_Tid{$V}{$TypedefName} = $MissedInfo{"Tid"};
    }
    
    # add missed & remove other
    $TypeInfo{$V} = \%AddTypes;
    delete($Cache{"getTypeAttr"}{$V});
}

sub addMissedTypes_Post()
{
    foreach my $BaseId (keys(%{$MissedTypedef{$V}}))
    {
        if(my $Tid = $MissedTypedef{$V}{$BaseId}{"Tid"})
        {
            $TypeInfo{$V}{$Tid}{"Size"} = $TypeInfo{$V}{$BaseId}{"Size"};
            if(my $TName = $TypeInfo{$V}{$Tid}{"Name"}) {
                $In::ABI{$V}{"TypedefBase"}{$TName} = $TypeInfo{$V}{$BaseId}{"Name"};
            }
        }
    }
}

sub getArraySize($$)
{
    my ($TypeId, $BaseName) = @_;
    if(my $Size = getSize($TypeId))
    {
        my $Elems = $Size/$BYTE;
        while($BaseName=~s/\s*\[(\d+)\]//) {
            $Elems/=$1;
        }
        if(my $BasicId = $TName_Tid{$V}{$BaseName})
        {
            if(my $BasicSize = $TypeInfo{$V}{$BasicId}{"Size"}) {
                $Elems/=$BasicSize;
            }
        }
        return $Elems;
    }
    return 0;
}

sub getTParams($$)
{
    my ($TypeId, $Kind) = @_;
    my @TmplParams = ();
    my @Positions = sort {$a<=>$b} keys(%{$TemplateInstance{$V}{$Kind}{$TypeId}});
    foreach my $Pos (@Positions)
    {
        my $Param_TypeId = $TemplateInstance{$V}{$Kind}{$TypeId}{$Pos};
        my $NodeType = $LibInfo{$V}{"info_type"}{$Param_TypeId};
        if(not $NodeType)
        { # typename_type
            return ();
        }
        if($NodeType eq "tree_vec")
        {
            if($Pos!=$#Positions)
            { # select last vector of parameters ( ns<P1>::type<P2> )
                next;
            }
        }
        my @Params = getTemplateParam($Pos, $Param_TypeId);
        foreach my $P (@Params)
        {
            if($P eq "") {
                return ();
            }
            elsif($P ne "\@skip\@") {
                @TmplParams = (@TmplParams, $P);
            }
        }
    }
    return @TmplParams;
}

sub getTreeVec($)
{
    my %Vector = ();
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        while($Info=~s/ (\d+)[ ]*:[ ]*\@(\d+) / /)
        { # string length is N-1 because of the null terminator
            $Vector{$1} = $2;
        }
    }
    return \%Vector;
}

sub getTemplateParam($$)
{
    my ($Pos, $Type_Id) = @_;
    return () if(not $Type_Id);
    my $NodeType = $LibInfo{$V}{"info_type"}{$Type_Id};
    return () if(not $NodeType);
    if($NodeType eq "integer_cst")
    { # int (1), unsigned (2u), char ('c' as 99), ...
        my $CstTid = getTreeAttr_Type($Type_Id);
        my $CstType = getTypeAttr($CstTid); # without recursion
        my $Num = getNodeIntCst($Type_Id);
        if(my $CstSuffix = $ConstantSuffix{$CstType->{"Name"}}) {
            return ($Num.$CstSuffix);
        }
        else {
            return ("(".$CstType->{"Name"}.")".$Num);
        }
    }
    elsif($NodeType eq "string_cst") {
        return (getNodeStrCst($Type_Id));
    }
    elsif($NodeType eq "tree_vec")
    {
        my $Vector = getTreeVec($Type_Id);
        my @Params = ();
        foreach my $P1 (sort {$a<=>$b} keys(%{$Vector}))
        {
            foreach my $P2 (getTemplateParam($Pos, $Vector->{$P1})) {
                push(@Params, $P2);
            }
        }
        return @Params;
    }
    elsif($NodeType eq "parm_decl")
    {
        return (getNameByInfo($Type_Id));
    }
    else
    {
        my $ParamAttr = getTypeAttr($Type_Id);
        my $PName = $ParamAttr->{"Name"};
        if(not $PName) {
            return ();
        }
        if($PName=~/\>/)
        {
            if(my $Cover = coverStdcxxTypedef($PName)) {
                $PName = $Cover;
            }
        }
        if($Pos>=1 and
        isDefaultStd($PName))
        { # template<typename _Tp, typename _Alloc = std::allocator<_Tp> >
          # template<typename _Key, typename _Compare = std::less<_Key>
          # template<typename _CharT, typename _Traits = std::char_traits<_CharT> >
          # template<typename _Ch_type, typename _Rx_traits = regex_traits<_Ch_type> >
          # template<typename _CharT, typename _InIter = istreambuf_iterator<_CharT> >
          # template<typename _CharT, typename _OutIter = ostreambuf_iterator<_CharT> >
            return ("\@skip\@");
        }
        return ($PName);
    }
}

sub coverStdcxxTypedef($)
{
    my $TypeName = $_[0];
    if(my @Covers = sort {length($a)<=>length($b)}
    sort keys(%{$StdCxxTypedef{$V}{$TypeName}}))
    { # take the shortest typedef
      # FIXME: there may be more than
      # one typedefs to the same type
        return $Covers[0];
    }
    my $Covered = $TypeName;
    while($TypeName=~s/(>)[ ]*(const|volatile|restrict| |\*|\&)\Z/$1/g){};
    if(my @Covers = sort {length($a)<=>length($b)} sort keys(%{$StdCxxTypedef{$V}{$TypeName}}))
    {
        if(my $Cover = $Covers[0])
        {
            $Covered=~s/\b\Q$TypeName\E(\W|\Z)/$Cover$1/g;
            $Covered=~s/\b\Q$TypeName\E(\w|\Z)/$Cover $1/g;
        }
    }
    return formatName($Covered, "T");
}

sub getNodeIntCst($)
{
    my $CstId = $_[0];
    my $CstTypeId = getTreeAttr_Type($CstId);
    if($EnumMembName_Id{$V}{$CstId}) {
        return $EnumMembName_Id{$V}{$CstId};
    }
    elsif((my $Value = getTreeValue($CstId)) ne "")
    {
        if($Value eq "0")
        {
            if($LibInfo{$V}{"info_type"}{$CstTypeId} eq "boolean_type") {
                return "false";
            }
            else {
                return "0";
            }
        }
        elsif($Value eq "1")
        {
            if($LibInfo{$V}{"info_type"}{$CstTypeId} eq "boolean_type") {
                return "true";
            }
            else {
                return "1";
            }
        }
        else {
            return $Value;
        }
    }
    return "";
}

sub getNodeStrCst($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/strg[ ]*: (.+) lngt:[ ]*(\d+)/)
        { 
            if($LibInfo{$V}{"info_type"}{$_[0]} eq "string_cst")
            { # string length is N-1 because of the null terminator
                return substr($1, 0, $2-1);
            }
            else
            { # identifier_node
                return substr($1, 0, $2);
            }
        }
    }
    return "";
}

sub getMemPtrAttr($$$)
{ # function, method and field pointers
    my ($PtrId, $TypeId, $Type) = @_;
    my $MemInfo = $LibInfo{$V}{"info"}{$PtrId};
    if($Type eq "FieldPtr") {
        $MemInfo = $LibInfo{$V}{"info"}{$TypeId};
    }
    my $MemInfo_Type = $LibInfo{$V}{"info_type"}{$PtrId};
    my $MemPtrName = "";
    my %TypeAttr = ("Size"=>$In::ABI{$V}{"WordSize"}, "Type"=>$Type, "Tid"=>$TypeId);
    if($Type eq "MethodPtr")
    { # size of "method pointer" may be greater than WORD size
        if(my $Size = getSize($TypeId))
        {
            $Size/=$BYTE;
            $TypeAttr{"Size"} = "$Size";
        }
    }
    if(my $Algn = getAlgn($TypeId)) {
        $TypeAttr{"Algn"} = $Algn/$BYTE;
    }
    # Return
    if($Type eq "FieldPtr")
    {
        my $ReturnAttr = getTypeAttr($PtrId);
        if($ReturnAttr->{"Name"}) {
            $MemPtrName .= $ReturnAttr->{"Name"};
        }
        $TypeAttr{"Return"} = $PtrId;
    }
    else
    {
        if($MemInfo=~/retn[ ]*:[ ]*\@(\d+) /)
        {
            my $ReturnTypeId = $1;
            my $ReturnAttr = getTypeAttr($ReturnTypeId);
            if(not $ReturnAttr->{"Name"})
            { # templates
                return {};
            }
            $MemPtrName .= $ReturnAttr->{"Name"};
            $TypeAttr{"Return"} = $ReturnTypeId;
        }
    }
    # Class
    if($MemInfo=~/(clas|cls)[ ]*:[ ]*@(\d+) /)
    {
        $TypeAttr{"Class"} = $2;
        my $ClassAttr = getTypeAttr($TypeAttr{"Class"});
        if($ClassAttr->{"Name"}) {
            $MemPtrName .= " (".$ClassAttr->{"Name"}."\:\:*)";
        }
        else {
            $MemPtrName .= " (*)";
        }
    }
    else {
        $MemPtrName .= " (*)";
    }
    # Parameters
    if($Type eq "FuncPtr"
    or $Type eq "MethodPtr")
    {
        my @ParamTypeName = ();
        if($MemInfo=~/prms[ ]*:[ ]*@(\d+) /)
        {
            my $PTypeInfoId = $1;
            my ($Pos, $PPos) = (0, 0);
            while($PTypeInfoId)
            {
                my $PTypeInfo = $LibInfo{$V}{"info"}{$PTypeInfoId};
                if($PTypeInfo=~/valu[ ]*:[ ]*@(\d+) /)
                {
                    my $PTypeId = $1;
                    my $ParamAttr = getTypeAttr($PTypeId);
                    if(not $ParamAttr->{"Name"})
                    { # templates (template_type_parm), etc.
                        return {};
                    }
                    if($ParamAttr->{"Name"} eq "void") {
                        last;
                    }
                    if($Pos!=0 or $Type ne "MethodPtr")
                    {
                        $TypeAttr{"Param"}{$PPos++}{"type"} = $PTypeId;
                        push(@ParamTypeName, $ParamAttr->{"Name"});
                    }
                    if($PTypeInfoId = getNextElem($PTypeInfoId)) {
                        $Pos+=1;
                    }
                    else {
                        last;
                    }
                }
                else {
                    last;
                }
            }
        }
        $MemPtrName .= " (".join(", ", @ParamTypeName).")";
    }
    $TypeAttr{"Name"} = formatName($MemPtrName, "T");
    return \%TypeAttr;
}

sub getTreeTypeName($)
{
    my $TypeId = $_[0];
    if(my $Info = $LibInfo{$V}{"info"}{$TypeId})
    {
        if($LibInfo{$V}{"info_type"}{$_[0]} eq "integer_type")
        {
            if(my $Name = getNameByInfo($TypeId))
            { # bit_size_type
                return $Name;
            }
            elsif($Info=~/unsigned/) {
                return "unsigned int";
            }
            else {
                return "int";
            }
        }
        elsif($Info=~/name[ ]*:[ ]*@(\d+) /) {
            return getNameByInfo($1);
        }
    }
    return "";
}

sub isFuncPtr($)
{
    my $Ptd = pointTo($_[0]);
    return 0 if(not $Ptd);
    if(my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/unql[ ]*:/ and $Info!~/qual[ ]*:/) {
            return 0;
        }
    }
    if(my $InfoT1 = $LibInfo{$V}{"info_type"}{$_[0]}
    and my $InfoT2 = $LibInfo{$V}{"info_type"}{$Ptd})
    {
        if($InfoT1 eq "pointer_type"
        and $InfoT2 eq "function_type") {
            return 1;
        }
    }
    return 0;
}

sub isMethodPtr($)
{
    my $Ptd = pointTo($_[0]);
    return 0 if(not $Ptd);
    if(my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($LibInfo{$V}{"info_type"}{$_[0]} eq "record_type"
        and $LibInfo{$V}{"info_type"}{$Ptd} eq "method_type"
        and $Info=~/ ptrmem /) {
            return 1;
        }
    }
    return 0;
}

sub isFieldPtr($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($LibInfo{$V}{"info_type"}{$_[0]} eq "offset_type"
        and $Info=~/ ptrmem /) {
            return 1;
        }
    }
    return 0;
}

sub pointTo($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/ptd[ ]*:[ ]*@(\d+)/) {
            return $1;
        }
    }
    return "";
}

sub getTypeTypeByTypeId($)
{
    my $TypeId = $_[0];
    if(my $TType = $LibInfo{$V}{"info_type"}{$TypeId})
    {
        my $NType = $NodeType{$TType};
        if($NType eq "Intrinsic") {
            return $NType;
        }
        elsif(isFuncPtr($TypeId)) {
            return "FuncPtr";
        }
        elsif(isMethodPtr($TypeId)) {
            return "MethodPtr";
        }
        elsif(isFieldPtr($TypeId)) {
            return "FieldPtr";
        }
        elsif($NType ne "Other") {
            return $NType;
        }
    }
    return "Unknown";
}

sub getQual($)
{
    my $TypeId = $_[0];
    if(my $Info = $LibInfo{$V}{"info"}{$TypeId})
    {
        my ($Qual, $To) = ();
        if($Info=~/qual[ ]*:[ ]*(r|c|v|cv) /) {
            $Qual = $UnQual{$1};
        }
        if($Info=~/unql[ ]*:[ ]*\@(\d+)/) {
            $To = $1;
        }
        if($Qual and $To) {
            return ($Qual, $To);
        }
    }
    return ();
}

sub getQualType($)
{
    if($_[0] eq "const volatile") {
        return "ConstVolatile";
    }
    return ucfirst($_[0]);
}

sub getTypeType($)
{
    my $TypeId = $_[0];
    my $TypeDeclId = getTypeDeclId($TypeId);
    if(defined $MissedTypedef{$V}{$TypeId})
    { # support for old GCC versions
        if($MissedTypedef{$V}{$TypeId}{"TDid"} eq $TypeDeclId) {
            return "Typedef";
        }
    }
    my $Info = $LibInfo{$V}{"info"}{$TypeId};
    my ($Qual, $To) = getQual($TypeId);
    if(($Qual or $To) and $TypeDeclId
    and (getTypeId($TypeDeclId) ne $TypeId))
    { # qualified types (special)
        return getQualType($Qual);
    }
    elsif(not $MissedBase_R{$V}{$TypeId}
    and isTypedef($TypeId)) {
        return "Typedef";
    }
    elsif($Qual)
    { # qualified types
        return getQualType($Qual);
    }
    
    if($Info=~/unql[ ]*:[ ]*\@(\d+)/)
    { # typedef struct { ... } name
        $In::ABI{$V}{"TypeTypedef"}{$TypeId} = $1;
    }
    
    my $TypeType = getTypeTypeByTypeId($TypeId);
    if($TypeType eq "Struct")
    {
        if($TypeDeclId
        and $LibInfo{$V}{"info_type"}{$TypeDeclId} eq "template_decl") {
            return "Template";
        }
    }
    return $TypeType;
}

sub isTypedef($)
{
    if($_[0])
    {
        if($LibInfo{$V}{"info_type"}{$_[0]} eq "vector_type")
        { # typedef float La_x86_64_xmm __attribute__ ((__vector_size__ (16)));
            return 0;
        }
        if(my $Info = $LibInfo{$V}{"info"}{$_[0]})
        {
            if(my $TDid = getTypeDeclId($_[0]))
            {
                if(getTypeId($TDid) eq $_[0]
                and getNameByInfo($TDid))
                {
                    if($Info=~/unql[ ]*:[ ]*\@(\d+) /) {
                        return $1;
                    }
                }
            }
        }
    }
    return 0;
}

sub selectBaseType($)
{
    my $TypeId = $_[0];
    if(defined $MissedTypedef{$V}{$TypeId})
    { # add missed typedefs
        if($MissedTypedef{$V}{$TypeId}{"TDid"} eq getTypeDeclId($TypeId)) {
            return ($TypeId, "");
        }
    }
    my $Info = $LibInfo{$V}{"info"}{$TypeId};
    my $InfoType = $LibInfo{$V}{"info_type"}{$TypeId};
    
    my $MB_R = $MissedBase_R{$V}{$TypeId};
    my $MB = $MissedBase{$V}{$TypeId};
    
    my ($Qual, $To) = getQual($TypeId);
    if(($Qual or $To) and $Info=~/name[ ]*:[ ]*\@(\d+) /
    and (getTypeId($1) ne $TypeId)
    and (not $MB_R or getTypeId($1) ne $MB_R))
    { # qualified types (special)
        return (getTypeId($1), $Qual);
    }
    elsif($MB)
    { # add base
        return ($MB, "");
    }
    elsif(not $MB_R and my $Bid = isTypedef($TypeId))
    { # typedefs
        return ($Bid, "");
    }
    elsif($Qual or $To)
    { # qualified types
        return ($To, $Qual);
    }
    elsif($InfoType eq "reference_type")
    {
        if($Info=~/refd[ ]*:[ ]*@(\d+) /) {
            return ($1, "&");
        }
    }
    elsif($InfoType eq "array_type")
    {
        if($Info=~/elts[ ]*:[ ]*@(\d+) /) {
            return ($1, "");
        }
    }
    elsif($InfoType eq "pointer_type")
    {
        if($Info=~/ptd[ ]*:[ ]*@(\d+) /) {
            return ($1, "*");
        }
    }
    
    return (0, "");
}

sub detectLang($)
{
    my $TypeId = $_[0];
    my $Info = $LibInfo{$V}{"info"}{$TypeId};
    
    if(checkGcc("8"))
    {
        if(getTreeAttr_VFld($TypeId)) {
            return 1;
        }
        
        if(my $Chain = getTreeAttr_Flds($TypeId))
        {
            while(1)
            {
                if($LibInfo{$V}{"info_type"}{$Chain} eq "function_decl") {
                    return 1;
                }
                
                $Chain = getTreeAttr_Chain($Chain);
                
                if(not $Chain) {
                    last;
                }
            }
        }
    }
    
    if(checkGcc("4"))
    { # GCC 4 fncs-node points to only non-artificial methods
        return ($Info=~/(fncs)[ ]*:[ ]*@(\d+) /);
    }
    else
    { # GCC 3
        my $Fncs = getTreeAttr_Fncs($TypeId);
        while($Fncs)
        {
            if($LibInfo{$V}{"info"}{$Fncs}!~/artificial/) {
                return 1;
            }
            $Fncs = getTreeAttr_Chan($Fncs);
        }
    }
    
    return 0;
}

sub setSpec($$)
{
    my ($TypeId, $TypeAttr) = @_;
    my $Info = $LibInfo{$V}{"info"}{$TypeId};
    if($Info=~/\s+spec\s+/) {
        $TypeAttr->{"Spec"} = 1;
    }
}

sub setBaseClasses($$)
{
    my ($TypeId, $TypeAttr) = @_;
    my $Info = $LibInfo{$V}{"info"}{$TypeId};
    if(my $Binf = getTreeAttr_Binf($TypeId))
    {
        my $Info = $LibInfo{$V}{"info"}{$Binf};
        my $Pos = 0;
        while($Info=~s/(pub|public|prot|protected|priv|private|)[ ]+binf[ ]*:[ ]*@(\d+) //)
        {
            my ($Access, $BInfoId) = ($1, $2);
            my $ClassId = getBinfClassId($BInfoId);
            
            if($ClassId eq $TypeId)
            { # class A<N>:public A<N-1>
                next;
            }
            
            my $CType = $LibInfo{$V}{"info_type"}{$ClassId};
            if(not $CType or $CType eq "template_type_parm"
            or $CType eq "typename_type")
            { # skip
                # return 1;
            }
            my $BaseInfo = $LibInfo{$V}{"info"}{$BInfoId};
            if($Access=~/prot/) {
                $TypeAttr->{"Base"}{$ClassId}{"access"} = "protected";
            }
            elsif($Access=~/priv/) {
                $TypeAttr->{"Base"}{$ClassId}{"access"} = "private";
            }
            $TypeAttr->{"Base"}{$ClassId}{"pos"} = "$Pos";
            if($BaseInfo=~/virt/)
            { # virtual base
                $TypeAttr->{"Base"}{$ClassId}{"virtual"} = 1;
            }
            
            $Pos += 1;
        }
    }
    return 0;
}

sub getBinfClassId($)
{
    my $Info = $LibInfo{$V}{"info"}{$_[0]};
    if($Info=~/type[ ]*:[ ]*@(\d+) /) {
        return $1;
    }
    
    return "";
}

sub isInternal($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/mngl[ ]*:[ ]*@(\d+) /)
        {
            if($LibInfo{$V}{"info"}{$1}=~/\*[ ]*INTERNAL[ ]*\*/)
            { # _ZN7mysqlpp8DateTimeC1ERKS0_ *INTERNAL*
                return 1;
            }
        }
    }
    return 0;
}

sub getDataVal($$)
{
    my ($InfoId, $TypeId) = @_;
    if(my $Info = $LibInfo{$V}{"info"}{$InfoId})
    {
        if($Info=~/init[ ]*:[ ]*@(\d+) /)
        {
            if(defined $LibInfo{$V}{"info_type"}{$1}
            and $LibInfo{$V}{"info_type"}{$1} eq "nop_expr")
            {
                if(my $Nop = getTreeAttr_Op($1))
                {
                    if(defined $LibInfo{$V}{"info_type"}{$Nop}
                    and $LibInfo{$V}{"info_type"}{$Nop} eq "addr_expr")
                    {
                        if(my $Addr = getTreeAttr_Op($1)) {
                            return getInitVal($Addr, $TypeId);
                        }
                    }
                }
            }
            else {
                return getInitVal($1, $TypeId);
            }
        }
    }
    return undef;
}

sub getInitVal($$)
{
    my ($InfoId, $TypeId) = @_;
    if(my $Info = $LibInfo{$V}{"info"}{$InfoId})
    {
        if(my $InfoType = $LibInfo{$V}{"info_type"}{$InfoId})
        {
            if($InfoType eq "integer_cst")
            {
                my $Val = getNodeIntCst($InfoId);
                if($TypeId and $TypeInfo{$V}{$TypeId}{"Name"}=~/\Achar(| const)\Z/)
                { # characters
                    $Val = chr($Val);
                }
                return $Val;
            }
            elsif($InfoType eq "string_cst") {
                return getNodeStrCst($InfoId);
            }
            elsif($InfoType eq "var_decl")
            {
                if(my $Name = getNodeStrCst(getTreeAttr_Mngl($InfoId))) {
                    return $Name;
                }
            }
        }
    }
    return undef;
}

sub setClassAndNs($)
{
    my $InfoId = $_[0];
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    if(my $Info = $LibInfo{$V}{"info"}{$InfoId})
    {
        if($Info=~/scpe[ ]*:[ ]*@(\d+) /)
        {
            my $NSInfoId = $1;
            if(my $InfoType = $LibInfo{$V}{"info_type"}{$NSInfoId})
            {
                if($InfoType eq "namespace_decl") {
                    $SInfo->{"NameSpace"} = getNameSpace($InfoId);
                }
                elsif($InfoType eq "record_type") {
                    $SInfo->{"Class"} = $NSInfoId;
                }
            }
        }
    }
    if($SInfo->{"Class"}
    or $SInfo->{"NameSpace"})
    {
        if($In::ABI{$V}{"Language"} ne "C++")
        { # skip
            return 1;
        }
    }
    
    return 0;
}

sub isInline($)
{ # "body: undefined" in the tree
  # -fkeep-inline-functions GCC option should be specified
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/ undefined /i) {
            return 0;
        }
    }
    return 1;
}

sub hasThrow($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return getTreeAttr_Unql($1, "unql");
        }
    }
    return 1;
}

sub getTypeId($)
{
    my $Id = $_[0];
    if($Id and my $Info = $LibInfo{$V}{"info"}{$Id})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub setTypeMemb($$)
{
    my ($TypeId, $TypeAttr) = @_;
    my $TypeType = $TypeAttr->{"Type"};
    my ($Pos, $UnnamedPos) = (0, 0);
    my $StaticFields = 0;
    if($TypeType eq "Enum")
    {
        my $MInfoId = getTreeAttr_Csts($TypeId);
        while($MInfoId)
        {
            $TypeAttr->{"Memb"}{$Pos}{"value"} = getEnumMembVal($MInfoId);
            my $MembName = getTreeStr(getTreeAttr_Purp($MInfoId));
            $TypeAttr->{"Memb"}{$Pos}{"name"} = $MembName;
            if(my $EMId = getTreeAttr_Valu($MInfoId))
            {
                if($TypeAttr->{"NameSpace"}) {
                    $EnumMembName_Id{$V}{$EMId} = $TypeAttr->{"NameSpace"}."::".$MembName;
                }
                else {
                    $EnumMembName_Id{$V}{$EMId} = $MembName;
                }
            }
            $MInfoId = getNextElem($MInfoId);
            $Pos += 1;
        }
    }
    elsif($TypeType=~/\A(Struct|Class|Union)\Z/)
    {
        my $MInfoId = getTreeAttr_Flds($TypeId);
        while($MInfoId)
        {
            my $IType = $LibInfo{$V}{"info_type"}{$MInfoId};
            my $MInfo = $LibInfo{$V}{"info"}{$MInfoId};
            if(not $IType or $IType ne "field_decl")
            { # search for fields, skip other stuff in the declaration
            
                if($IType eq "var_decl")
                { # static field
                    $StaticFields = 1;
                }
                
                $MInfoId = getNextElem($MInfoId);
                next;
            }
            my $StructMembName = getTreeStr(getTreeAttr_Name($MInfoId));
            if(index($StructMembName, "_vptr.")==0)
            { # virtual tables
                $StructMembName = "_vptr";
            }
            if(not $StructMembName)
            { # unnamed fields
                if(index($TypeAttr->{"Name"}, "_type_info_pseudo")==-1)
                {
                    my $UnnamedTid = getTreeAttr_Type($MInfoId);
                    my $UnnamedTName = getNameByInfo(getTypeDeclId($UnnamedTid));
                    if(isAnon($UnnamedTName))
                    { # rename unnamed fields to unnamed0, unnamed1, ...
                        $StructMembName = "unnamed".($UnnamedPos++);
                    }
                }
            }
            if(not $StructMembName)
            { # unnamed fields and base classes
                $MInfoId = getNextElem($MInfoId);
                next;
            }
            my $MembTypeId = getTreeAttr_Type($MInfoId);
            if(defined $MissedTypedef{$V}{$MembTypeId})
            {
                if(my $AddedTid = $MissedTypedef{$V}{$MembTypeId}{"Tid"}) {
                    $MembTypeId = $AddedTid;
                }
            }
            
            $TypeAttr->{"Memb"}{$Pos}{"type"} = $MembTypeId;
            $TypeAttr->{"Memb"}{$Pos}{"name"} = $StructMembName;
            if((my $Access = getTreeAccess($MInfoId)) ne "public")
            { # marked only protected and private, public by default
                $TypeAttr->{"Memb"}{$Pos}{"access"} = $Access;
            }
            if($MInfo=~/spec:\s*mutable /)
            { # mutable fields
                $TypeAttr->{"Memb"}{$Pos}{"mutable"} = 1;
            }
            if(my $Algn = getAlgn($MInfoId)) {
                $TypeAttr->{"Memb"}{$Pos}{"algn"} = $Algn;
            }
            if(my $BFSize = getBitField($MInfoId))
            { # in bits
                $TypeAttr->{"Memb"}{$Pos}{"bitfield"} = $BFSize;
            }
            else
            { # in bytes
                if($TypeAttr->{"Memb"}{$Pos}{"algn"}==1)
                { # template
                    delete($TypeAttr->{"Memb"}{$Pos}{"algn"});
                }
                else {
                    $TypeAttr->{"Memb"}{$Pos}{"algn"} /= $BYTE;
                }
            }
            
            $MInfoId = getNextElem($MInfoId);
            $Pos += 1;
        }
    }
    
    return $StaticFields;
}

sub setFuncParams($)
{
    my $InfoId = $_[0];
    my $ParamInfoId = getTreeAttr_Args($InfoId);
    
    my $FType = getFuncType($InfoId);
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    if($FType eq "Method")
    { # check type of "this" pointer
        my $ObjectTypeId = getTreeAttr_Type($ParamInfoId);
        if(my $ObjectName = $TypeInfo{$V}{$ObjectTypeId}{"Name"})
        {
            if($ObjectName=~/\bconst(| volatile)\*const\b/) {
                $SInfo->{"Const"} = 1;
            }
            if($ObjectName=~/\bvolatile\b/) {
                $SInfo->{"Volatile"} = 1;
            }
        }
        else
        { # skip
            return 1;
        }
        # skip "this"-parameter
        # $ParamInfoId = getNextElem($ParamInfoId);
    }
    my ($Pos, $PPos, $Vtt_Pos) = (0, 0, -1);
    while($ParamInfoId)
    { # formal args
        my $ParamTypeId = getTreeAttr_Type($ParamInfoId);
        my $ParamName = getTreeStr(getTreeAttr_Name($ParamInfoId));
        if(not $ParamName)
        { # unnamed
            $ParamName = "p".($PPos+1);
        }
        if(defined $MissedTypedef{$V}{$ParamTypeId})
        {
            if(my $AddedTid = $MissedTypedef{$V}{$ParamTypeId}{"Tid"}) {
                $ParamTypeId = $AddedTid;
            }
        }
        my $PType = $TypeInfo{$V}{$ParamTypeId}{"Type"};
        if(not $PType or $PType eq "Unknown") {
            return 1;
        }
        my $PTName = $TypeInfo{$V}{$ParamTypeId}{"Name"};
        if(not $PTName) {
            return 1;
        }
        if($PTName eq "void") {
            last;
        }
        if($ParamName eq "__vtt_parm"
        and $TypeInfo{$V}{$ParamTypeId}{"Name"} eq "void const**")
        {
            $Vtt_Pos = $Pos;
            $ParamInfoId = getNextElem($ParamInfoId);
            next;
        }
        $SInfo->{"Param"}{$Pos}{"type"} = $ParamTypeId;
        
        if(my %Base = getBaseType($ParamTypeId, $V))
        {
            if(defined $Base{"Template"}) {
                return 1;
            }
        }
        
        $SInfo->{"Param"}{$Pos}{"name"} = $ParamName;
        if(my $Algn = getAlgn($ParamInfoId)) {
            $SInfo->{"Param"}{$Pos}{"algn"} = $Algn/$BYTE;
        }
        if($LibInfo{$V}{"info"}{$ParamInfoId}=~/spec:\s*register /)
        { # foo(register type arg)
            $SInfo->{"Param"}{$Pos}{"reg"} = 1;
        }
        $ParamInfoId = getNextElem($ParamInfoId);
        $Pos += 1;
        if($ParamName ne "this" or $FType ne "Method") {
            $PPos += 1;
        }
    }
    if(setFuncArgs($InfoId, $Vtt_Pos)) {
        $SInfo->{"Param"}{$Pos}{"type"} = "-1";
    }
    return 0;
}

sub setFuncArgs($$)
{
    my ($InfoId, $Vtt_Pos) = @_;
    my $FuncTypeId = getFuncTypeId($InfoId);
    my $ParamListElemId = getTreeAttr_Prms($FuncTypeId);
    my $FType = getFuncType($InfoId);
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    if($FType eq "Method")
    {
        # skip "this"-parameter
        # $ParamListElemId = getNextElem($ParamListElemId);
    }
    if(not $ParamListElemId)
    { # foo(...)
        return 1;
    }
    my $HaveVoid = 0;
    my ($Pos, $PPos) = (0, 0);
    while($ParamListElemId)
    { # actual params: may differ from formal args
      # formal int*const
      # actual: int*
        if($Vtt_Pos!=-1 and $Pos==$Vtt_Pos)
        {
            $Vtt_Pos=-1;
            $ParamListElemId = getNextElem($ParamListElemId);
            next;
        }
        my $ParamTypeId = getTreeAttr_Valu($ParamListElemId);
        if($TypeInfo{$V}{$ParamTypeId}{"Name"} eq "void")
        {
            $HaveVoid = 1;
            last;
        }
        else
        {
            if(not defined $SInfo->{"Param"}{$Pos}{"type"})
            {
                $SInfo->{"Param"}{$Pos}{"type"} = $ParamTypeId;
                if(not $SInfo->{"Param"}{$Pos}{"name"})
                { # unnamed
                    $SInfo->{"Param"}{$Pos}{"name"} = "p".($PPos+1);
                }
            }
            elsif(my $OldId = $SInfo->{"Param"}{$Pos}{"type"})
            {
                if($Pos>0 or getFuncType($InfoId) ne "Method")
                { # params
                    if($OldId ne $ParamTypeId)
                    {
                        my %Old_Pure = getPureType($OldId, $V);
                        my %New_Pure = getPureType($ParamTypeId, $V);
                        
                        if($Old_Pure{"Name"} ne $New_Pure{"Name"}) {
                            $SInfo->{"Param"}{$Pos}{"type"} = $ParamTypeId;
                        }
                    }
                }
            }
        }
        if(my $PurpId = getTreeAttr_Purp($ParamListElemId))
        { # default arguments
            if(my $PurpType = $LibInfo{$V}{"info_type"}{$PurpId})
            {
                if($PurpType eq "nop_expr")
                { # func ( const char* arg = (const char*)(void*)0 )
                    $PurpId = getTreeAttr_Op($PurpId);
                }
                my $Val = getInitVal($PurpId, $ParamTypeId);
                if(defined $Val) {
                    $SInfo->{"Param"}{$Pos}{"default"} = $Val;
                }
            }
        }
        $ParamListElemId = getNextElem($ParamListElemId);
        if($Pos!=0 or $FType ne "Method") {
            $PPos += 1;
        }
        $Pos += 1;
    }
    return ($Pos>=1 and not $HaveVoid);
}

sub getTreeAttr_Chan($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/chan[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Chain($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/chain[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Unql($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/unql[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Scpe($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/scpe[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Type($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Name($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Mngl($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/mngl[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Prms($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/prms[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Fncs($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/fncs[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Csts($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/csts[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Purp($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/purp[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Op($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/op 0[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Valu($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/valu[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Flds($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/flds[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_VFld($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/vfld[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Binf($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/binf[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Args($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/args[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeValue($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/(low|int)[ ]*:[ ]*([^ ]+) /) {
            return $2;
        }
    }
    return "";
}

sub getTreeAccess($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/accs[ ]*:[ ]*([a-zA-Z]+) /)
        {
            my $Access = $1;
            if($Access eq "prot") {
                return "protected";
            }
            elsif($Access eq "priv") {
                return "private";
            }
        }
        elsif($Info=~/ protected /)
        { # support for old GCC versions
            return "protected";
        }
        elsif($Info=~/ private /)
        { # support for old GCC versions
            return "private";
        }
    }
    return "public";
}

sub setFuncAccess($)
{
    my $Access = getTreeAccess($_[0]);
    if($Access eq "protected") {
        $SymbolInfo{$V}{$_[0]}{"Protected"} = 1;
    }
    elsif($Access eq "private") {
        $SymbolInfo{$V}{$_[0]}{"Private"} = 1;
    }
}

sub setTypeAccess($$)
{
    my ($TypeId, $TypeAttr) = @_;
    my $Access = getTreeAccess($TypeId);
    if($Access eq "protected") {
        $TypeAttr->{"Protected"} = 1;
    }
    elsif($Access eq "private") {
        $TypeAttr->{"Private"} = 1;
    }
}

sub setFuncKind($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/pseudo tmpl/) {
            $SymbolInfo{$V}{$_[0]}{"PseudoTemplate"} = 1;
        }
        elsif($Info=~/ constructor /) {
            $SymbolInfo{$V}{$_[0]}{"Constructor"} = 1;
        }
        elsif($Info=~/ destructor /) {
            $SymbolInfo{$V}{$_[0]}{"Destructor"} = 1;
        }
    }
}

sub getVirtSpec($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/spec[ ]*:[ ]*pure /) {
            return "PureVirt";
        }
        elsif($Info=~/spec[ ]*:[ ]*virt /) {
            return "Virt";
        }
        elsif($Info=~/ pure\s+virtual /)
        { # support for old GCC versions
            return "PureVirt";
        }
        elsif($Info=~/ virtual /)
        { # support for old GCC versions
            return "Virt";
        }
    }
    return "";
}

sub getFuncLink($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/link[ ]*:[ ]*static /) {
            return "Static";
        }
        elsif($Info=~/link[ ]*:[ ]*([a-zA-Z]+) /) {
            return $1;
        }
    }
    return "";
}

sub getNameSpace($)
{
    my $InfoId = $_[0];
    if(my $NSInfoId = getTreeAttr_Scpe($InfoId))
    {
        if(my $InfoType = $LibInfo{$V}{"info_type"}{$NSInfoId})
        {
            if($InfoType eq "namespace_decl")
            {
                if($LibInfo{$V}{"info"}{$NSInfoId}=~/name[ ]*:[ ]*@(\d+) /)
                {
                    my $NameSpace = getTreeStr($1);
                    if($NameSpace eq "::")
                    { # global namespace
                        return "";
                    }
                    if(my $BaseNameSpace = getNameSpace($NSInfoId)) {
                        $NameSpace = $BaseNameSpace."::".$NameSpace;
                    }
                    $In::ABI{$V}{"NameSpaces"}{$NameSpace} = 1;
                    return $NameSpace;
                }
                else {
                    return "";
                }
            }
            elsif($InfoType ne "function_decl")
            { # inside data type
                my ($Name, $NameNS) = getTrivialName(getTypeDeclId($NSInfoId), $NSInfoId);
                return $Name;
            }
        }
    }
    return "";
}

sub getEnumMembVal($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/valu[ ]*:[ ]*\@(\d+)/)
        {
            if(my $VInfo = $LibInfo{$V}{"info"}{$1})
            {
                if($VInfo=~/cnst[ ]*:[ ]*\@(\d+)/)
                { # in newer versions of GCC the value is in the "const_decl->cnst" node
                    return getTreeValue($1);
                }
                else
                { # some old versions of GCC (3.3) have the value in the "integer_cst" node
                    return getTreeValue($1);
                }
            }
        }
    }
    return "";
}

sub getSize($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/size[ ]*:[ ]*\@(\d+)/) {
            return getTreeValue($1);
        }
    }
    return 0;
}

sub getAlgn($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/algn[ ]*:[ ]*(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getBitField($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/ bitfield /) {
            return getSize($_[0]);
        }
    }
    return 0;
}

sub getNextElem($)
{
    if(my $Chan = getTreeAttr_Chan($_[0])) {
        return $Chan;
    }
    elsif(my $Chain = getTreeAttr_Chain($_[0])) {
        return $Chain;
    }
    return "";
}

sub getLocation($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/srcp[ ]*:[ ]*([\w\-\<\>\.\+\/\\]+):(\d+) /) {
            return (pathFmt($1), $2);
        }
    }
    return ();
}

sub getNameByInfo($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /)
        {
            if(my $NInfo = $LibInfo{$V}{"info"}{$1})
            {
                if($NInfo=~/strg[ ]*:[ ]*(.*?)[ ]+lngt/)
                { # short unsigned int (may include spaces)
                    my $Str = $1;
                    if($In::Desc{$V}{"CppMode"}
                    and index($Str, "c99_")==0
                    and $Str=~/\Ac99_(.+)\Z/) {
                        $Str = $1;
                    }
                    return $Str;
                }
            }
        }
    }
    return "";
}

sub getTreeStr($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/strg[ ]*:[ ]*([^ ]*)/)
        {
            my $Str = $1;
            if($In::Desc{$V}{"CppMode"}
            and index($Str, "c99_")==0
            and $Str=~/\Ac99_(.+)\Z/)
            {
                $Str = $1;
            }
            return $Str;
        }
    }
    return "";
}

sub getFuncShortName($)
{
    if(my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if(index($Info, " operator ")!=-1)
        {
            if(index($Info, " conversion ")!=-1)
            {
                if(my $Rid = $SymbolInfo{$V}{$_[0]}{"Return"})
                {
                    if(my $RName = $TypeInfo{$V}{$Rid}{"Name"}) {
                        return "operator ".$RName;
                    }
                }
            }
            else
            {
                if($Info=~/ operator[ ]+([a-zA-Z]+) /)
                {
                    if(my $Ind = $OperatorIndication{$1}) {
                        return "operator".$Ind;
                    }
                    elsif(not $UnknownOperator{$1})
                    {
                        printMsg("WARNING", "unknown operator $1");
                        $UnknownOperator{$1} = 1;
                    }
                }
            }
        }
        else
        {
            if($Info=~/name[ ]*:[ ]*@(\d+) /) {
                return getTreeStr($1);
            }
        }
    }
    return "";
}

sub getFuncReturn($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /)
        {
            if($LibInfo{$V}{"info"}{$1}=~/retn[ ]*:[ ]*@(\d+) /) {
                return $1;
            }
        }
    }
    return "";
}

sub getFuncOrig($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/orig[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return $_[0];
}

sub getFuncType($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /)
        {
            if(my $Type = $LibInfo{$V}{"info_type"}{$1})
            {
                if($Type eq "method_type") {
                    return "Method";
                }
                elsif($Type eq "function_type") {
                    return "Function";
                }
                else {
                    return "Other";
                }
            }
        }
    }
    return "";
}

sub getFuncTypeId($)
{
    if($_[0] and my $Info = $LibInfo{$V}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+)( |\Z)/) {
            return $1;
        }
    }
    return 0;
}



sub guessHeader($)
{
    my $InfoId = $_[0];
    my $SInfo = $SymbolInfo{$V}{$InfoId};
    
    my $ShortName = $SInfo->{"ShortName"};
    my $ClassName = "";
    if(my $ClassId = $SInfo->{"Class"}) {
        $ClassName = getShortClass($ClassId, $V);
    }
    my $Header = $SInfo->{"Header"};
    
    if(my $HPath = $In::ABI{$V}{"SymbolHeader"}{$ClassName}{$ShortName})
    {
        if(getFilename($HPath) eq $Header)
        {
            my $HDir = getFilename(getDirname($HPath));
            if($HDir ne "include"
            and $HDir=~/\A[a-z]+\Z/i) {
                return join_P($HDir, $Header);
            }
        }
    }
    return $Header;
}

sub linkWithSymbol($)
{ # link symbols from shared libraries
  # with the symbols from header files
    my $InfoId = $_[0];
    
    if($In::Opt{"Target"} eq "windows")
    { # link MS C++ symbols from library with GCC symbols from headers
        if(my $Mangled1 = getMangled_MSVC(modelUnmangled($InfoId, "MSVC", $V), $V))
        { # exported symbols
            return $Mangled1;
        }
        elsif(my $Mangled2 = mangleSymbol($InfoId, "MSVC", $V))
        { # pure virtual symbols
            return $Mangled2;
        }
    }
    
    # GCC 3.x doesn't mangle class methods names in the TU dump (only functions and global data)
    # GCC 4.x doesn't mangle C++ functions in the TU dump (only class methods) except extern "C" functions
    # GCC 4.8.[012] and 6.[12].0 don't mangle anything
    
    # try to mangle symbol
    if((not checkGcc("4") and $SymbolInfo{$V}{$InfoId}{"Class"})
    or (checkGcc("4") and not $SymbolInfo{$V}{$InfoId}{"Class"})
    or $In::Opt{"GccMissedMangling"})
    { 
        if(not $In::Opt{"CheckHeadersOnly"})
        {
            if(my $Mangled = getMangled_GCC(modelUnmangled($InfoId, "GCC", $V), $V)) {
                return correctIncharge($InfoId, $V, $Mangled);
            }
        }
        
        if(my $Mangled = mangleSymbol($InfoId, "GCC", $V)) {
            return correctIncharge($InfoId, $V, $Mangled);
        }
    }
    
    return undef;
}

sub simplifyNames()
{
    foreach my $Base (keys(%{$Typedef_Tr{$V}}))
    {
        if($Typedef_Eq{$V}{$Base}) {
            next;
        }
        my @Translations = sort keys(%{$Typedef_Tr{$V}{$Base}});
        if($#Translations==0)
        {
            if(length($Translations[0])<=length($Base)) {
                $Typedef_Eq{$V}{$Base} = $Translations[0];
            }
        }
        else
        { # select most appropriate
            foreach my $Tr (@Translations)
            {
                if($Base=~/\A\Q$Tr\E/)
                {
                    $Typedef_Eq{$V}{$Base} = $Tr;
                    last;
                }
            }
        }
    }
    
    foreach my $TypeId (sort {$a<=>$b} keys(%{$TypeInfo{$V}}))
    { # template instances only
        my $TypeName = $TypeInfo{$V}{$TypeId}{"Name"};
        if(not $TypeName) {
            next;
        }
        if(index($TypeName, "<")==-1) {
            next;
        }
        if($TypeName=~/>(::\w+)+\Z/)
        { # skip unused types
            next;
        }
        
        my $TypeName_N = $TypeName;
        
        foreach my $Base (sort {length($b)<=>length($a)}
        sort {$b cmp $a} keys(%{$Typedef_Eq{$V}}))
        {
            next if(not $Base);
            if(index($TypeName_N, $Base)==-1) {
                next;
            }
            if(length($TypeName_N) - length($Base) <= 3) {
                next;
            }
            
            if(my $Typedef = $Typedef_Eq{$V}{$Base})
            {
                if($TypeName_N=~s/(\<|\,)\Q$Base\E(\W|\Z)/$1$Typedef$2/g
                or $TypeName_N=~s/(\<|\,)\Q$Base\E(\w|\Z)/$1$Typedef $2/g)
                {
                    if(defined $TypeInfo{$V}{$TypeId}{"TParam"})
                    {
                        foreach my $TPos (keys(%{$TypeInfo{$V}{$TypeId}{"TParam"}}))
                        {
                            if(my $TPName = $TypeInfo{$V}{$TypeId}{"TParam"}{$TPos}{"name"})
                            {
                                if(index($TPName, $Base)==-1) {
                                    next;
                                }
                                if($TPName=~s/\A\Q$Base\E(\W|\Z)/$Typedef$1/g
                                or $TPName=~s/\A\Q$Base\E(\w|\Z)/$Typedef $1/g) {
                                    $TypeInfo{$V}{$TypeId}{"TParam"}{$TPos}{"name"} = formatName($TPName, "T");
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if($TypeName_N ne $TypeName)
        {
            $TypeName_N = formatName($TypeName_N, "T");
            $TypeInfo{$V}{$TypeId}{"Name"} = $TypeName_N;
            
            if(not defined $TName_Tid{$V}{$TypeName_N}) {
                $TName_Tid{$V}{$TypeName_N} = $TypeId;
            }
        }
    }
}

sub createType($)
{
    my $Attr = $_[0];
    my $NewId = ++$MAX_ID;
    
    $Attr->{"Tid"} = $NewId;
    $TypeInfo{$V}{$NewId} = $Attr;
    $TName_Tid{$V}{formatName($Attr->{"Name"}, "T")} = $NewId;
    
    return "$NewId";
}

sub instType($$)
{ # create template instances
    my ($Map, $Tid) = @_;
    
    my $TInfoRef = $TypeInfo{$V};
    
    if(not $TInfoRef->{$Tid}) {
        return undef;
    }
    my $Attr = dclone($TInfoRef->{$Tid});
    
    foreach my $Key (sort keys(%{$Map}))
    {
        if(my $Val = $Map->{$Key})
        {
            $Attr->{"Name"}=~s/\b$Key\b/$Val/g;
            
            if(defined $Attr->{"NameSpace"}) {
                $Attr->{"NameSpace"}=~s/\b$Key\b/$Val/g;
            }
            foreach (keys(%{$Attr->{"TParam"}})) {
                $Attr->{"TParam"}{$_}{"name"}=~s/\b$Key\b/$Val/g;
            }
        }
        else
        { # remove absent
          # _Traits, etc.
            $Attr->{"Name"}=~s/,\s*\b$Key(,|>)/$1/g;
            if(defined $Attr->{"NameSpace"}) {
                $Attr->{"NameSpace"}=~s/,\s*\b$Key(,|>)/$1/g;
            }
            foreach (keys(%{$Attr->{"TParam"}}))
            {
                if($Attr->{"TParam"}{$_}{"name"} eq $Key) {
                    delete($Attr->{"TParam"}{$_});
                }
                else {
                    $Attr->{"TParam"}{$_}{"name"}=~s/,\s*\b$Key(,|>)/$1/g;
                }
            }
        }
    }
    
    my $Tmpl = 0;
    
    if(defined $Attr->{"TParam"})
    {
        foreach (sort {$a<=>$b} keys(%{$Attr->{"TParam"}}))
        {
            my $PName = $Attr->{"TParam"}{$_}{"name"};
            
            if(my $PTid = $TName_Tid{$V}{$PName})
            {
                my %Base = getBaseType($PTid, $V);
                
                if($Base{"Type"} eq "TemplateParam"
                or defined $Base{"Template"})
                {
                    $Tmpl = 1;
                    last
                }
            }
        }
    }
    
    if(my $Id = getTypeIdByName($Attr->{"Name"}, $V)) {
        return "$Id";
    }
    else
    {
        if(not $Tmpl) {
            delete($Attr->{"Template"});
        }
        
        my $New = createType($Attr);
        
        my %EMap = ();
        if(defined $TemplateMap{$V}{$Tid}) {
            %EMap = %{$TemplateMap{$V}{$Tid}};
        }
        foreach (keys(%{$Map})) {
            $EMap{$_} = $Map->{$_};
        }
        
        if(defined $TInfoRef->{$New}{"BaseType"}) {
            $TInfoRef->{$New}{"BaseType"} = instType(\%EMap, $TInfoRef->{$New}{"BaseType"});
        }
        if(defined $TInfoRef->{$New}{"Base"})
        {
            foreach my $Bid (sort {$a<=>$b} keys(%{$TInfoRef->{$New}{"Base"}}))
            {
                my $NBid = instType(\%EMap, $Bid);
                
                if($NBid ne $Bid
                and $NBid ne $New)
                {
                    %{$TInfoRef->{$New}{"Base"}{$NBid}} = %{$TInfoRef->{$New}{"Base"}{$Bid}};
                    delete($TInfoRef->{$New}{"Base"}{$Bid});
                }
            }
        }
        
        if(defined $TInfoRef->{$New}{"Memb"})
        {
            foreach (sort {$a<=>$b} keys(%{$TInfoRef->{$New}{"Memb"}}))
            {
                if(defined $TInfoRef->{$New}{"Memb"}{$_}{"type"}) {
                    $TInfoRef->{$New}{"Memb"}{$_}{"type"} = instType(\%EMap, $TInfoRef->{$New}{"Memb"}{$_}{"type"});
                }
            }
        }
        
        if(defined $TInfoRef->{$New}{"Param"})
        {
            foreach (sort {$a<=>$b} keys(%{$TInfoRef->{$New}{"Param"}})) {
                $TInfoRef->{$New}{"Param"}{$_}{"type"} = instType(\%EMap, $TInfoRef->{$New}{"Param"}{$_}{"type"});
            }
        }
        
        if(defined $TInfoRef->{$New}{"Return"}) {
            $TInfoRef->{$New}{"Return"} = instType(\%EMap, $TInfoRef->{$New}{"Return"});
        }
        
        return $New;
    }
}

sub correctIncharge($$$)
{
    my ($InfoId, $V, $Mangled) = @_;
    if($In::ABI{$V}{"SymbolInfo"}{$InfoId}{"Constructor"})
    {
        if($MangledNames{$V}{$Mangled}) {
            $Mangled=~s/C1([EI])/C2$1/;
        }
    }
    elsif($In::ABI{$V}{"SymbolInfo"}{$InfoId}{"Destructor"})
    {
        if($MangledNames{$V}{$Mangled}) {
            $Mangled=~s/D0([EI])/D1$1/;
        }
        if($MangledNames{$V}{$Mangled}) {
            $Mangled=~s/D1([EI])/D2$1/;
        }
    }
    return $Mangled;
}

sub simplifyConstants()
{
    my $CRef = $In::ABI{$V}{"Constants"};
    foreach my $Constant (keys(%{$CRef}))
    {
        if(defined $CRef->{$Constant}{"Header"})
        {
            my $Value = $CRef->{$Constant}{"Value"};
            if(defined $In::ABI{$V}{"EnumConstants"}{$Value}) {
                $CRef->{$Constant}{"Value"} = $In::ABI{$V}{"EnumConstants"}{$Value}{"Value"};
            }
        }
    }
}

sub simplifyVTable($)
{
    my $Content = $_[0];
    if($Content=~s/ \[with (.+)]//)
    { # std::basic_streambuf<_CharT, _Traits>::imbue [with _CharT = char, _Traits = std::char_traits<char>]
        if(my @Elems = sepParams($1, 0, 0))
        {
            foreach my $Elem (@Elems)
            {
                if($Elem=~/\A(.+?)\s*=\s*(.+?)\Z/)
                {
                    my ($Arg, $Val) = ($1, $2);
                    
                    if(defined $DefaultStdArgs{$Arg}) {
                        $Content=~s/,\s*$Arg\b//g;
                    }
                    else {
                        $Content=~s/\b$Arg\b/$Val/g;
                    }
                }
            }
        }
    }
    
    return $Content;
}

return 1;
