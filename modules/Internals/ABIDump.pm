###########################################################################
# A module to create ABI dump from AST tree
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

loadModule("ElfTools");
loadModule("TUDump");
loadModule("GccAst");

my %Cache;

my %RegisteredObj;
my %RegisteredObj_Short;
my %RegisteredSoname;
my %RegisteredObj_Dir;
my %CheckedDyLib;
my %KnownLibs;
my %CheckedArch;
my @RecurLib;

sub createABIDump($)
{
    my $LVer = $_[0];
    
    if($In::Opt{"CheckHeadersOnly"}) {
        $In::ABI{$LVer}{"Language"} = "C++";
    }
    else
    {
        readLibs($LVer);
        
        if(not keys(%{$In::ABI{$LVer}{"SymLib"}})) {
            exitStatus("Error", "the set of public symbols in library(ies) is empty");
        }
    }
    
    if($In::Opt{"TargetArch"}) {
        $In::ABI{$LVer}{"Arch"} = $In::Opt{"TargetArch"};
    }
    else {
        $In::ABI{$LVer}{"Arch"} = getArch_GCC($LVer);
    }
    
    $In::ABI{$LVer}{"WordSize"} = detectWordSize($LVer);
    
    $In::ABI{$LVer}{"LibraryVersion"} = $In::Desc{$LVer}{"Version"};
    $In::ABI{$LVer}{"LibraryName"} = $In::Opt{"TargetLib"};
    
    if(not $In::ABI{$LVer}{"Language"}) {
        $In::ABI{$LVer}{"Language"} = "C";
    }
    
    if($In::Opt{"UserLang"}) {
        $In::ABI{$LVer}{"Language"} = $In::Opt{"UserLang"};
    }
    
    $In::ABI{$LVer}{"GccVersion"} = $In::Opt{"GccVer"};
    
    printMsg("INFO", "Checking header(s) ".$In::Desc{$LVer}{"Version"}." ...");
    my $TUDump = createTUDump($LVer);
    
    if($In::Opt{"Debug"})
    { # debug mode
        copy($TUDump, getDebugDir($LVer)."/translation-unit-dump.txt");
    }
    
    readGccAst($LVer, $TUDump);
    
    if($In::Opt{"DebugMangling"})
    {
        if($In::ABI{$LVer}{"Language"} eq "C++")
        {
            debugMangling($LVer);
        }
    }
    
    delete($In::ABI{$LVer}{"EnumConstants"});
    delete($In::ABI{$LVer}{"ClassVTable_Content"});
    delete($In::ABI{$LVer}{"WeakSymbols"});
    
    cleanDump($LVer);
    
    if(not keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    { # check if created dump is valid
        if(not $In::Opt{"ExtendedCheck"})
        {
            if($In::Opt{"CheckHeadersOnly"}) {
                exitStatus("Empty_Set", "the set of public symbols is empty");
            }
            else {
                exitStatus("Empty_Intersection", "the sets of public symbols in headers and libraries have empty intersection");
            }
        }
    }
    
    foreach my $HPath (keys(%{$In::Desc{$LVer}{"RegHeader"}})) {
        $In::ABI{$LVer}{"Headers"}{getFilename($HPath)} = 1;
    }
    
    foreach my $InfoId (keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    {
        if(my $MnglName = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"MnglName"})
        {
            if(my $Unmangled = getUnmangled($MnglName, $LVer)) {
                $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Unmangled"} = $Unmangled;
            }
        }
    }
    
    my %CompilerConstants = (); # built-in GCC constants
    my $CRef = $In::ABI{$LVer}{"Constants"};
    foreach my $Name (keys(%{$CRef}))
    {
        if(not defined $CRef->{$Name}{"Header"})
        {
            $CompilerConstants{$Name} = $CRef->{$Name}{"Value"};
            delete($CRef->{$Name});
        }
    }
    $In::ABI{$LVer}{"CompilerConstants"} = \%CompilerConstants;
    
    if($In::Opt{"ExtendedCheck"})
    { # --ext option
        $In::ABI{$LVer}{"Mode"} = "Extended";
    }
    if($In::Opt{"BinOnly"})
    { # --binary
        $In::ABI{$LVer}{"BinOnly"} = 1;
    }
    if($In::Opt{"ExtraDump"})
    { # --extra-dump
        $In::ABI{$LVer}{"Extra"} = 1;
    }
    
    $In::ABI{$LVer}{"Target"} = $In::Opt{"Target"};
}

sub readSymbols($)
{
    my $LVer = $_[0];
    
    my @LibPaths = getSOPaths($LVer);
    if($#LibPaths==-1) {
        exitStatus("Error", "library objects are not found");
    }
    
    foreach my $LibPath (@LibPaths) {
        readSymbols_Lib($LVer, $LibPath, 0, "+Weak", 1, 1);
    }
    
    if($In::Opt{"CheckUndefined"})
    {
        my %UndefinedLibs = ();
        
        my @Libs = (keys(%{$In::ABI{$LVer}{"Symbols"}}), keys(%{$In::ABI{$LVer}{"DepSymbols"}}));
        
        foreach my $LibName (sort @Libs)
        {
            if(defined $In::ABI{$LVer}{"UndefinedSymbols"}{$LibName})
            {
                foreach my $Symbol (keys(%{$In::ABI{$LVer}{"UndefinedSymbols"}{$LibName}}))
                {
                    if($In::ABI{$LVer}{"SymLib"}{$Symbol}
                    or $In::ABI{$LVer}{"DepSymLib"}{$Symbol})
                    { # exported by target library
                        next;
                    }
                    if(index($Symbol, '@')!=-1)
                    { # exported default symbol version (@@)
                        $Symbol=~s/\@/\@\@/;
                        if($In::ABI{$LVer}{"SymLib"}{$Symbol}
                        or $In::ABI{$LVer}{"DepSymLib"}{$Symbol}) {
                            next;
                        }
                    }
                    foreach my $Path (find_SymbolLibs($LVer, $Symbol)) {
                        $UndefinedLibs{$Path} = 1;
                    }
                }
            }
        }
        
        if(my @Paths = sort keys(%UndefinedLibs))
        {
            my $LibString = "";
            my %Dirs = ();
            foreach (@Paths)
            {
                $KnownLibs{$_} = 1;
                my ($Dir, $Name) = sepPath($_);
                
                if(not grep {$Dir eq $_} (@{$In::Opt{"SysPaths"}{"lib"}})) {
                    $Dirs{escapeArg($Dir)} = 1;
                }
                
                $Name = libPart($Name, "name");
                $Name=~s/\Alib//;
                
                $LibString .= " -l$Name";
            }
            
            foreach my $Dir (sort {$b cmp $a} keys(%Dirs))
            {
                $LibString = " -L".escapeArg($Dir).$LibString;
            }
            
            if($In::Opt{"ExtraInfo"}) {
                writeFile($In::Opt{"ExtraInfo"}."/libs-string", $LibString);
            }
        }
    }
    
    if($In::Opt{"ExtraInfo"}) {
        writeFile($In::Opt{"ExtraInfo"}."/lib-paths", join("\n", sort keys(%KnownLibs)));
    }
}

sub readSymbols_Lib($$$$$$)
{
    my ($LVer, $Lib_Path, $IsNeededLib, $Weak, $Deps, $Vers) = @_;
    
    my $Real_Path = realpath_F($Lib_Path);
    
    if(not $Real_Path)
    { # broken link
        return ();
    }
    
    my $Lib_Name = getFilename($Real_Path);
    my $LExt = $In::Opt{"Ext"};
    
    if($In::Opt{"ExtraInfo"})
    {
        $KnownLibs{$Real_Path} = 1;
        $KnownLibs{$Lib_Path} = 1; # links
    }
    
    if($IsNeededLib)
    {
        if($CheckedDyLib{$LVer}{$Lib_Name}) {
            return ();
        }
    }
    if($#RecurLib>=1 or isCyclical(\@RecurLib, $Lib_Name)) {
        return ();
    }
    $CheckedDyLib{$LVer}{$Lib_Name} = 1;
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    push(@RecurLib, $Lib_Name);
    my (%Value_Interface, %Interface_Value, %NeededLib) = ();
    my $Lib_ShortName = libPart($Lib_Name, "name+ext");
    
    if(not $IsNeededLib)
    { # special cases: libstdc++ and libc
        if(my $ShortName = libPart($Lib_Name, "short"))
        {
            if($ShortName eq "libstdc++"
            or $ShortName eq "libc++")
            { # libstdc++.so.6
                $In::Opt{"StdcxxTesting"} = 1;
            }
            elsif($ShortName eq "libc")
            { # libc-2.11.3.so
                $In::Opt{"GlibcTesting"} = 1;
            }
        }
    }
    my $DebugPath = "";
    if($In::Opt{"Debug"} and not $In::Opt{"DumpSystem"})
    { # debug mode
        $DebugPath = getDebugDir($LVer)."/libs/".getFilename($Lib_Path).".txt";
        mkpath(getDirname($DebugPath));
    }
    if($In::Opt{"Target"} eq "macos")
    { # Mac OS X: *.dylib, *.a
        my $NM = getCmdPath("nm");
        if(not $NM) {
            exitStatus("Not_Found", "can't find \"nm\"");
        }
        $NM .= " -g \"$Lib_Path\" 2>\"$TmpDir/null\"";
        if($DebugPath)
        { # debug mode
          # write to file
            system($NM." >\"$DebugPath\"");
            open(LIB, $DebugPath);
        }
        else
        { # write to pipe
            open(LIB, $NM." |");
        }
        while(<LIB>)
        {
            if($In::Opt{"CheckUndefined"})
            {
                if(not $IsNeededLib)
                {
                    if(/ U _([\w\$]+)\s*\Z/)
                    {
                        $In::ABI{$LVer}{"UndefinedSymbols"}{$Lib_Name}{$1} = 0;
                        next;
                    }
                }
            }
            
            if(/ [STD] _([\w\$]+)\s*\Z/)
            {
                my $Symbol = $1;
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObj_Short{$LVer}{$Lib_ShortName})
                    {
                        $In::ABI{$LVer}{"DepSymLib"}{$Symbol} = $Lib_Name;
                        $In::ABI{$LVer}{"DepSymbols"}{$Lib_Name}{$Symbol} = 1;
                    }
                }
                else
                {
                    $In::ABI{$LVer}{"SymLib"}{$Symbol} = $Lib_Name;
                    $In::ABI{$LVer}{"Symbols"}{$Lib_Name}{$Symbol} = 1;
                    if($In::ABI{$LVer}{"Language"} ne "C++")
                    {
                        if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                            $In::ABI{$LVer}{"Language"} = "C++";
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps)
        {
            if(not $In::Opt{"UseStaticLibs"})
            { # dependencies
                my $OtoolCmd = getCmdPath("otool");
                if(not $OtoolCmd) {
                    exitStatus("Not_Found", "can't find \"otool\"");
                }
                
                open(LIB, "$OtoolCmd -L \"$Lib_Path\" 2>\"$TmpDir/null\" |");
                while(<LIB>)
                {
                    if(/\s*([\/\\].+\.$LExt)\s*/
                    and $1 ne $Lib_Path) {
                        $NeededLib{$1} = 1;
                    }
                }
                close(LIB);
            }
        }
    }
    elsif($In::Opt{"Target"} eq "windows")
    { # Windows *.dll, *.lib
        my $DumpBinCmd = getCmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin\"");
        }
        $DumpBinCmd .= " /EXPORTS \"".$Lib_Path."\" 2>$TmpDir/null";
        if($DebugPath)
        { # debug mode
          # write to file
            system($DumpBinCmd." >\"$DebugPath\"");
            open(LIB, $DebugPath);
        }
        else
        { # write to pipe
            open(LIB, $DumpBinCmd." |");
        }
        while(<LIB>)
        {
            my $Symbol = undef;
            if($In::Opt{"UseStaticLibs"})
            {
                if(/\A\s{10,}(\d+\s+|)([_\w\?\@]+)(\s*\Z|\s+)/i)
                {
                    # 16 IID_ISecurityInformation
                    # ??_7TestBaseClass@api@@6B@ (const api::TestBaseClass::`vftable')
                    $Symbol = $2;
                }
            }
            else
            { # Dll
                # 1197 4AC 0000A620 SetThreadStackGuarantee
                # 1198 4AD          SetThreadToken (forwarded to ...)
                # 3368 _o2i_ECPublicKey
                # 1 0 00005B30 ??0?N = ... (with pdb)
                if(/\A\s*\d+\s+[a-f\d]+\s+[a-f\d]+\s+([\w\?\@]+)\s*(?:=.+)?\Z/i
                or /\A\s*\d+\s+[a-f\d]+\s+([\w\?\@]+)\s*\(\s*forwarded\s+/
                or /\A\s*\d+\s+_([\w\?\@]+)\s*(?:=.+)?\Z/)
                { # dynamic, static and forwarded symbols
                    $Symbol = $1;
                }
            }
            
            if($Symbol)
            {
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObj_Short{$LVer}{$Lib_ShortName})
                    {
                        $In::ABI{$LVer}{"DepSymLib"}{$Symbol} = $Lib_Name;
                        $In::ABI{$LVer}{"DepSymbols"}{$Lib_Name}{$Symbol} = 1;
                    }
                }
                else
                {
                    $In::ABI{$LVer}{"SymLib"}{$Symbol} = $Lib_Name;
                    $In::ABI{$LVer}{"Symbols"}{$Lib_Name}{$Symbol} = 1;
                    if($In::ABI{$LVer}{"Language"} ne "C++")
                    {
                        if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                            $In::ABI{$LVer}{"Language"} = "C++";
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps)
        {
            if(not $In::Opt{"UseStaticLibs"})
            { # dependencies
                open(LIB, "$DumpBinCmd /DEPENDENTS \"$Lib_Path\" 2>\"$TmpDir/null\" |");
                while(<LIB>)
                {
                    if(/\s*([^\s]+?\.$LExt)\s*/i
                    and $1 ne $Lib_Path) {
                        $NeededLib{pathFmt($1)} = 1;
                    }
                }
                close(LIB);
            }
        }
    }
    else
    { # Unix; *.so, *.a
      # Symbian: *.dso, *.lib
        my $ReadelfCmd = getCmdPath("readelf");
        if(not $ReadelfCmd) {
            exitStatus("Not_Found", "can't find \"readelf\"");
        }
        my $Cmd = $ReadelfCmd." -Ws \"$Lib_Path\" 2>\"$TmpDir/null\"";
        if($DebugPath)
        { # debug mode
          # write to file
            system($Cmd." >\"$DebugPath\"");
            open(LIB, $DebugPath);
        }
        else
        { # write to pipe
            open(LIB, $Cmd." |");
        }
        my $symtab = undef; # indicates that we are processing 'symtab' section of 'readelf' output
        while(<LIB>)
        {
            if(not $In::Opt{"UseStaticLibs"})
            { # dynamic library specifics
                if(defined $symtab)
                {
                    if(index($_, "'.dynsym'")!=-1)
                    { # dynamic table
                        $symtab = undef;
                    }
                    # do nothing with symtab
                    next;
                }
                elsif(index($_, "'.symtab'")!=-1)
                { # symbol table
                    $symtab = 1;
                    next;
                }
            }
            if(my ($Value, $Size, $Type, $Bind, $Vis, $Ndx, $Symbol) = readline_ELF($_))
            { # read ELF entry
                if($Ndx eq "UND")
                { # ignore interfaces that are imported from somewhere else
                    if($In::Opt{"CheckUndefined"})
                    {
                        if(not $IsNeededLib) {
                            $In::ABI{$LVer}{"UndefinedSymbols"}{$Lib_Name}{$Symbol} = 0;
                        }
                    }
                    next;
                }
                if($Bind eq "WEAK")
                {
                    $In::ABI{$LVer}{"WeakSymbols"}{$Symbol} = 1;
                    if($Weak eq "-Weak")
                    { # skip WEAK symbols
                        next;
                    }
                }
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObj_Short{$LVer}{$Lib_ShortName})
                    {
                        $In::ABI{$LVer}{"DepSymLib"}{$Symbol} = $Lib_Name;
                        $In::ABI{$LVer}{"DepSymbols"}{$Lib_Name}{$Symbol} = ($Type eq "OBJECT")?-$Size:1;
                    }
                }
                else
                {
                    $In::ABI{$LVer}{"SymLib"}{$Symbol} = $Lib_Name;
                    $In::ABI{$LVer}{"Symbols"}{$Lib_Name}{$Symbol} = ($Type eq "OBJECT")?-$Size:1;
                    if($Vers)
                    {
                        if($LExt eq "so")
                        { # value
                            $Interface_Value{$LVer}{$Symbol} = $Value;
                            $Value_Interface{$LVer}{$Value}{$Symbol} = 1;
                        }
                    }
                    if($In::ABI{$LVer}{"Language"} ne "C++")
                    {
                        if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                            $In::ABI{$LVer}{"Language"} = "C++";
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps and not $In::Opt{"UseStaticLibs"})
        { # dynamic library specifics
            $Cmd = $ReadelfCmd." -Wd \"$Lib_Path\" 2>\"$TmpDir/null\"";
            open(LIB, $Cmd." |");
            
            while(<LIB>)
            {
                if(/NEEDED.+\[([^\[\]]+)\]/)
                { # dependencies:
                  # 0x00000001 (NEEDED) Shared library: [libc.so.6]
                    $NeededLib{$1} = 1;
                }
            }
            
            close(LIB);
        }
    }
    if($Vers)
    {
        if(not $IsNeededLib and $LExt eq "so")
        { # get symbol versions
            my %Found = ();
            
            # by value
            foreach my $Symbol (sort keys(%{$In::ABI{$LVer}{"Symbols"}{$Lib_Name}}))
            {
                next if(index($Symbol, '@')==-1);
                if(my $Value = $Interface_Value{$LVer}{$Symbol})
                {
                    foreach my $Symbol_SameValue (sort keys(%{$Value_Interface{$LVer}{$Value}}))
                    {
                        if($Symbol_SameValue ne $Symbol
                        and index($Symbol_SameValue, '@')==-1)
                        {
                            $In::ABI{$LVer}{"SymbolVersion"}{$Symbol_SameValue} = $Symbol;
                            $Found{$Symbol} = 1;
                            
                            if(index($Symbol, '@@')==-1) {
                                last;
                            }
                        }
                    }
                }
            }
            
            # default
            foreach my $Symbol (keys(%{$In::ABI{$LVer}{"Symbols"}{$Lib_Name}}))
            {
                next if(defined $Found{$Symbol});
                next if(index($Symbol, '@@')==-1);
                
                if($Symbol=~/\A([^\@]*)\@\@/
                and not $In::ABI{$LVer}{"SymbolVersion"}{$1})
                {
                    $In::ABI{$LVer}{"SymbolVersion"}{$1} = $Symbol;
                    $Found{$Symbol} = 1;
                }
            }
            
            # non-default
            foreach my $Symbol (keys(%{$In::ABI{$LVer}{"Symbols"}{$Lib_Name}}))
            {
                next if(defined $Found{$Symbol});
                next if(index($Symbol, '@')==-1);
                
                if($Symbol=~/\A([^\@]*)\@([^\@]*)/
                and not $In::ABI{$LVer}{"SymbolVersion"}{$1})
                {
                    $In::ABI{$LVer}{"SymbolVersion"}{$1} = $Symbol;
                    $Found{$Symbol} = 1;
                }
            }
        }
    }
    if($Deps)
    {
        foreach my $DyLib (sort keys(%NeededLib))
        {
            if($In::Opt{"ExtraDump"}) {
                $In::ABI{$LVer}{"Needed"}{$Lib_Name}{getFilename($DyLib)} = 1;
            }
            
            if(my $DepPath = getLibPath($LVer, $DyLib))
            {
                if(not $CheckedDyLib{$LVer}{getFilename($DepPath)}) {
                    readSymbols_Lib($LVer, $DepPath, 1, "+Weak", $Deps, $Vers);
                }
            }
        }
    }
    pop(@RecurLib);
    return $In::ABI{$LVer}{"Symbols"};
}

sub readSymbols_App($)
{
    my $Path = $_[0];
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    my @Imported = ();
    if($In::Opt{"Target"} eq "macos")
    {
        my $NM = getCmdPath("nm");
        if(not $NM) {
            exitStatus("Not_Found", "can't find \"nm\"");
        }
        open(APP, "$NM -g \"$Path\" 2>\"$TmpDir/null\" |");
        while(<APP>)
        {
            if(/ U _([\w\$]+)\s*\Z/) {
                push(@Imported, $1);
            }
        }
        close(APP);
    }
    elsif($In::Opt{"Target"} eq "windows")
    {
        my $DumpBinCmd = getCmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin.exe\"");
        }
        open(APP, "$DumpBinCmd /IMPORTS \"$Path\" 2>\"$TmpDir/null\" |");
        while(<APP>)
        {
            if(/\s*\w+\s+\w+\s+\w+\s+([\w\?\@]+)\s*/) {
                push(@Imported, $1);
            }
        }
        close(APP);
    }
    else
    {
        my $ReadelfCmd = getCmdPath("readelf");
        if(not $ReadelfCmd) {
            exitStatus("Not_Found", "can't find \"readelf\"");
        }
        open(APP, "$ReadelfCmd -Ws \"$Path\" 2>\"$TmpDir/null\" |");
        my $symtab = undef; # indicates that we are processing 'symtab' section of 'readelf' output
        while(<APP>)
        {
            if(defined $symtab)
            { # do nothing with symtab
                if(index($_, "'.dynsym'")!=-1)
                { # dynamic table
                    $symtab = undef;
                }
            }
            elsif(index($_, "'.symtab'")!=-1)
            { # symbol table
                $symtab = 1;
            }
            elsif(my @Info = readline_ELF($_))
            {
                my ($Ndx, $Symbol) = ($Info[5], $Info[6]);
                if($Ndx eq "UND")
                { # only imported symbols
                    push(@Imported, $Symbol);
                }
            }
        }
        close(APP);
    }
    return @Imported;
}

sub cleanDump($)
{ # clean data
    my $LVer = $_[0];
    foreach my $InfoId (keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    {
        if(not keys(%{$In::ABI{$LVer}{"SymbolInfo"}{$InfoId}}))
        {
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId});
            next;
        }
        my $MnglName = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"MnglName"};
        if(not $MnglName)
        {
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId});
            next;
        }
        my $ShortName = $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"ShortName"};
        if(not $ShortName)
        {
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId});
            next;
        }
        if($MnglName eq $ShortName)
        { # remove duplicate data
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"MnglName"});
        }
        if(not keys(%{$In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Param"}})) {
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Param"});
        }
        if(not keys(%{$In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"TParam"}})) {
            delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"TParam"});
        }
        delete($In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Type"});
    }
    foreach my $Tid (keys(%{$In::ABI{$LVer}{"TypeInfo"}}))
    {
        if(not keys(%{$In::ABI{$LVer}{"TypeInfo"}{$Tid}}))
        {
            delete($In::ABI{$LVer}{"TypeInfo"}{$Tid});
            next;
        }
        delete($In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Tid"});
        foreach my $Attr ("Header", "Line", "Size", "NameSpace")
        {
            if(not $In::ABI{$LVer}{"TypeInfo"}{$Tid}{$Attr}) {
                delete($In::ABI{$LVer}{"TypeInfo"}{$Tid}{$Attr});
            }
        }
        if(not keys(%{$In::ABI{$LVer}{"TypeInfo"}{$Tid}{"TParam"}})) {
            delete($In::ABI{$LVer}{"TypeInfo"}{$Tid}{"TParam"});
        }
    }
}

sub readLibs($)
{
    my $LVer = $_[0];
    
    if($In::Opt{"Target"} eq "windows")
    { # dumpbin.exe will crash
        # without VS Environment
        checkWin32Env();
    }
    
    readSymbols($LVer);
    
    translateSymbols(keys(%{$In::ABI{$LVer}{"SymLib"}}), $LVer);
    translateSymbols(keys(%{$In::ABI{$LVer}{"DepSymLib"}}), $LVer);
}

sub getSOPaths($)
{
    my $LVer = $_[0];
    my @Paths = ();
    foreach my $P (keys(%{$In::Desc{$LVer}{"Libs"}}))
    {
        my @Found = getSOPaths_Dir(getAbsPath($P), $LVer);
        foreach (@Found) {
            push(@Paths, $_);
        }
    }
    return sort @Paths;
}

sub getSOPaths_Dir($$)
{
    my ($Path, $LVer) = @_;
    if(skipLib($Path, $LVer)) {
        return ();
    }
    
    my $LExt = $In::Opt{"Ext"};
    
    if(-f $Path)
    {
        if(not libPart($Path, "name")) {
            exitStatus("Error", "incorrect format of library (should be *.$LExt): \'$Path\'");
        }
        registerObject($Path, $LVer);
        registerObject_Dir(getDirname($Path), $LVer);
        return ($Path);
    }
    elsif(-d $Path)
    {
        $Path=~s/[\/\\]+\Z//g;
        my %Libs = ();
        if(my $TN = $In::Opt{"TargetLib"}
        and grep { $Path eq $_ } @{$In::Opt{"SysPaths"}{"lib"}})
        { # you have specified /usr/lib as the search directory (<libs>) in the XML descriptor
          # and the real name of the library by -l option (bz2, stdc++, Xaw, ...)
            foreach my $P (cmdFind($Path,"","*".escapeArg($TN)."*.$LExt*",2))
            { # all files and symlinks that match the name of a library
                if(getFilename($P)=~/\A(|lib)\Q$TN\E[\d\-]*\.$LExt[\d\.]*\Z/i)
                {
                    registerObject($P, $LVer);
                    $Libs{realpath_F($P)} = 1;
                }
            }
        }
        else
        { # search for all files and symlinks
            foreach my $P (findLibs($Path,"",""))
            {
                next if(ignorePath($P));
                next if(skipLib($P, $LVer));
                registerObject($P, $LVer);
                $Libs{realpath_F($P)} = 1;
            }
            if($In::Opt{"OS"} eq "macos")
            { # shared libraries on MacOS X may have no extension
                foreach my $P (cmdFind($Path,"f"))
                {
                    next if(ignorePath($P));
                    next if(skipLib($P, $LVer));
                    if(getFilename($P)!~/\./ and -B $P
                    and cmdFile($P)=~/(shared|dynamic)\s+library/i)
                    {
                        registerObject($P, $LVer);
                        $Libs{realpath_F($P)} = 1;
                    }
                }
            }
        }
        return keys(%Libs);
    }
    
    return ();
}

sub registerObject_Dir($$)
{
    my ($Dir, $LVer) = @_;
    if(grep {$_ eq $Dir} @{$In::Opt{"SysPaths"}{"lib"}})
    { # system directory
        return;
    }
    if($RegisteredObj_Dir{$LVer}{$Dir})
    { # already registered
        return;
    }
    foreach my $Path (findLibs($Dir,"",1))
    {
        if(ignorePath($Path)) {
            next;
        }
        if(skipLib($Path, $LVer)) {
            next;
        }
        registerObject($Path, $LVer);
    }
    $RegisteredObj_Dir{$LVer}{$Dir} = 1;
}

sub registerObject($$)
{
    my ($Path, $LVer) = @_;
    
    my $Name = getFilename($Path);
    $RegisteredObj{$LVer}{$Name} = $Path;
    if($In::Opt{"Target"}=~/linux|bsd|gnu|solaris/i)
    {
        if(my $SONAME = getSONAME($Path)) {
            $RegisteredSoname{$LVer}{$SONAME} = $Path;
        }
    }
    if(my $Short = libPart($Name, "name+ext")) {
        $RegisteredObj_Short{$LVer}{$Short} = $Path;
    }
    
    if(not $CheckedArch{$LVer} and -f $Path)
    {
        if(my $ObjArch = getArch_Object($Path))
        {
            if($ObjArch ne getArch_GCC($LVer))
            { # translation unit dump generated by the GCC compiler should correspond to input objects
                $CheckedArch{$LVer} = 1;
                printMsg("WARNING", "the architectures of input objects and the used GCC compiler are not equal, please change the compiler by --gcc-path=PATH option.");
            }
        }
    }
}

sub remove_Unused($$)
{ # remove unused data types from the ABI dump
    my ($LVer, $Kind) = @_;
    
    my %UsedType = ();
    
    foreach my $InfoId (sort {$a<=>$b} keys(%{$In::ABI{$LVer}{"SymbolInfo"}}))
    {
        registerSymbolUsage($InfoId, \%UsedType, $LVer);
    }
    foreach my $Tid (sort {$a<=>$b} keys(%{$In::ABI{$LVer}{"TypeInfo"}}))
    {
        if($UsedType{$Tid})
        { # All & Extended
            next;
        }
        
        if($Kind eq "Extended")
        {
            if(pickType($Tid, $LVer))
            {
                my %Tree = ();
                registerTypeUsage($Tid, \%Tree, $LVer);
                
                my $Tmpl = 0;
                foreach (sort {$a<=>$b} keys(%Tree))
                {
                    if(defined $In::ABI{$LVer}{"TypeInfo"}{$_}{"Template"}
                    or $In::ABI{$LVer}{"TypeInfo"}{$_}{"Type"} eq "TemplateParam")
                    {
                        $Tmpl = 1;
                        last;
                    }
                }
                if(not $Tmpl)
                {
                    foreach (keys(%Tree)) {
                        $UsedType{$_} = 1;
                    }
                }
            }
        }
    }
    
    my %Delete = ();
    
    foreach my $Tid (sort {$a<=>$b} keys(%{$In::ABI{$LVer}{"TypeInfo"}}))
    { # remove unused types
        if($UsedType{$Tid})
        { # All & Extended
            next;
        }
        
        if($Kind eq "Extra")
        {
            my %Tree = ();
            registerTypeUsage($Tid, \%Tree, $LVer);
            
            foreach (sort {$a<=>$b} keys(%Tree))
            {
                if(defined $In::ABI{$LVer}{"TypeInfo"}{$_}{"Template"}
                or $In::ABI{$LVer}{"TypeInfo"}{$_}{"Type"} eq "TemplateParam")
                {
                    $Delete{$Tid} = 1;
                    last;
                }
            }
        }
        else
        {
            # remove type
            delete($In::ABI{$LVer}{"TypeInfo"}{$Tid});
        }
    }
    
    if($Kind eq "Extra")
    { # remove duplicates
        foreach my $Tid (sort {$a<=>$b} keys(%{$In::ABI{$LVer}{"TypeInfo"}}))
        {
            if($UsedType{$Tid})
            { # All & Extended
                next;
            }
            
            my $Name = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Name"};
            
            if($In::ABI{$LVer}{"TName_Tid"}{$Name} ne $Tid) {
                delete($In::ABI{$LVer}{"TypeInfo"}{$Tid});
            }
        }
    }
    
    foreach my $Tid (keys(%Delete))
    {
        delete($In::ABI{$LVer}{"TypeInfo"}{$Tid});
    }
}

sub getFirst($$)
{
    my ($Tid, $LVer) = @_;
    if(not $Tid) {
        return $Tid;
    }
    
    if(my $Name = $In::ABI{$LVer}{"TypeInfo"}{$Tid}{"Name"})
    {
        if($In::ABI{$LVer}{"TName_Tid"}{$Name}) {
            return $In::ABI{$LVer}{"TName_Tid"}{$Name};
        }
    }
    
    return $Tid;
}

sub registerSymbolUsage($$$)
{
    my ($InfoId, $UsedType, $LVer) = @_;
    
    my %FuncInfo = %{$In::ABI{$LVer}{"SymbolInfo"}{$InfoId}};
    if(my $RTid = getFirst($FuncInfo{"Return"}, $LVer))
    {
        registerTypeUsage($RTid, $UsedType, $LVer);
        $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Return"} = $RTid;
    }
    if(my $FCid = getFirst($FuncInfo{"Class"}, $LVer))
    {
        registerTypeUsage($FCid, $UsedType, $LVer);
        $In::ABI{$LVer}{"SymbolInfo"}{$InfoId}{"Class"} = $FCid;
        
        if(my $ThisId = getTypeIdByName($In::ABI{$LVer}{"TypeInfo"}{$FCid}{"Name"}."*const", $LVer))
        { # register "this" pointer
            registerTypeUsage($ThisId, $UsedType, $LVer);
        }
        if(my $ThisId_C = getTypeIdByName($In::ABI{$LVer}{"TypeInfo"}{$FCid}{"Name"}." const*const", $LVer))
        { # register "this" pointer (const method)
            registerTypeUsage($ThisId_C, $UsedType, $LVer);
        }
    }
    foreach my $PPos (sort {$a<=>$b} keys(%{$FuncInfo{"Param"}}))
    {
        if(my $PTid = getFirst($FuncInfo{"Param"}{$PPos}{"type"}, $LVer))
        {
            registerTypeUsage($PTid, $UsedType, $LVer);
            $FuncInfo{"Param"}{$PPos}{"type"} = $PTid;
        }
    }
    foreach my $TPos (sort {$a<=>$b} keys(%{$FuncInfo{"TParam"}}))
    {
        my $TPName = $FuncInfo{"TParam"}{$TPos}{"name"};
        if(my $TTid = $In::ABI{$LVer}{"TName_Tid"}{$TPName}) {
            registerTypeUsage($TTid, $UsedType, $LVer);
        }
    }
}

sub registerTypeUsage($$$)
{
    my ($TypeId, $UsedType, $LVer) = @_;
    if(not $TypeId) {
        return;
    }
    if($UsedType->{$TypeId})
    { # already registered
        return;
    }
    
    my %TInfo = getType($TypeId, $LVer);
    if($TInfo{"Type"})
    {
        if(my $NS = $TInfo{"NameSpace"})
        {
            if(my $NSTid = $In::ABI{$LVer}{"TName_Tid"}{$NS}) {
                registerTypeUsage($NSTid, $UsedType, $LVer);
            }
        }
        
        if($TInfo{"Type"}=~/\A(Struct|Union|Class|FuncPtr|Func|MethodPtr|FieldPtr|Enum)\Z/)
        {
            $UsedType->{$TypeId} = 1;
            if($TInfo{"Type"}=~/\A(Struct|Class)\Z/)
            {
                foreach my $BaseId (sort {$a<=>$b} keys(%{$TInfo{"Base"}})) {
                    registerTypeUsage($BaseId, $UsedType, $LVer);
                }
                foreach my $TPos (sort {$a<=>$b} keys(%{$TInfo{"TParam"}}))
                {
                    my $TPName = $TInfo{"TParam"}{$TPos}{"name"};
                    if(my $TTid = $In::ABI{$LVer}{"TName_Tid"}{$TPName}) {
                        registerTypeUsage($TTid, $UsedType, $LVer);
                    }
                }
            }
            foreach my $Memb_Pos (sort {$a<=>$b} keys(%{$TInfo{"Memb"}}))
            {
                if(my $MTid = getFirst($TInfo{"Memb"}{$Memb_Pos}{"type"}, $LVer))
                {
                    registerTypeUsage($MTid, $UsedType, $LVer);
                    $TInfo{"Memb"}{$Memb_Pos}{"type"} = $MTid;
                }
            }
            if($TInfo{"Type"} eq "FuncPtr"
            or $TInfo{"Type"} eq "MethodPtr"
            or $TInfo{"Type"} eq "Func")
            {
                if(my $RTid = $TInfo{"Return"}) {
                    registerTypeUsage($RTid, $UsedType, $LVer);
                }
                foreach my $PPos (sort {$a<=>$b} keys(%{$TInfo{"Param"}}))
                {
                    if(my $PTid = $TInfo{"Param"}{$PPos}{"type"}) {
                        registerTypeUsage($PTid, $UsedType, $LVer);
                    }
                }
            }
            if($TInfo{"Type"} eq "FieldPtr")
            {
                if(my $RTid = $TInfo{"Return"}) {
                    registerTypeUsage($RTid, $UsedType, $LVer);
                }
                if(my $CTid = $TInfo{"Class"}) {
                    registerTypeUsage($CTid, $UsedType, $LVer);
                }
            }
            if($TInfo{"Type"} eq "MethodPtr")
            {
                if(my $CTid = $TInfo{"Class"}) {
                    registerTypeUsage($CTid, $UsedType, $LVer);
                }
            }
        }
        elsif($TInfo{"Type"}=~/\A(Const|ConstVolatile|Volatile|Pointer|Ref|Restrict|Array|Typedef)\Z/)
        {
            $UsedType->{$TypeId} = 1;
            if(my $BTid = getFirst($TInfo{"BaseType"}, $LVer))
            {
                registerTypeUsage($BTid, $UsedType, $LVer);
                $In::ABI{$LVer}{"TypeInfo"}{$TypeId}{"BaseType"} = $BTid;
            }
        }
        else
        { # Intrinsic, TemplateParam, TypeName, SizeOf, etc.
            $UsedType->{$TypeId} = 1;
        }
    }
}

sub detectWordSize($)
{
    my $LVer = $_[0];
    
    my $Size = undef;
    
    # speed up detection
    if(my $Arch = $In::ABI{$LVer}{"Arch"})
    {
        if($Arch=~/\A(x86_64|s390x|ppc64|ia64|alpha)\Z/) {
            $Size = "8";
        }
        elsif($Arch=~/\A(x86|s390|ppc32)\Z/) {
            $Size = "4";
        }
    }
    
    if(my $GccPath = $In::Opt{"GccPath"})
    {
        my $TmpDir = $In::Opt{"Tmp"};
        writeFile("$TmpDir/empty.h", "");
        
        my $Cmd = $GccPath." -E -dD empty.h";
        if(my $Opts = getGccOptions($LVer))
        { # user-defined options
            $Cmd .= " ".$Opts;
        }
        
        chdir($TmpDir);
        my $Defines = `$Cmd`;
        chdir($In::Opt{"OrigDir"});
        
        unlink("$TmpDir/empty.h");
        
        if($Defines=~/ __SIZEOF_POINTER__\s+(\d+)/)
        { # GCC 4
            $Size = $1;
        }
        elsif($Defines=~/ __PTRDIFF_TYPE__\s+(\w+)/)
        { # GCC 3
            my $PTRDIFF = $1;
            if($PTRDIFF=~/long/) {
                $Size = "8";
            }
            else {
                $Size = "4";
            }
        }
    }
    
    if(not $Size) {
        exitStatus("Error", "can't check WORD size");
    }
    
    return $Size;
}

sub getLibPath($$)
{
    my ($LVer, $Name) = @_;
    if(defined $Cache{"getLibPath"}{$LVer}{$Name}) {
        return $Cache{"getLibPath"}{$LVer}{$Name};
    }
    return ($Cache{"getLibPath"}{$LVer}{$Name} = getLibPath_I($LVer, $Name));
}

sub getLibPath_I($$)
{
    my ($LVer, $Name) = @_;
    if(isAbsPath($Name))
    {
        if(-f $Name)
        { # absolute path
            return $Name;
        }
        else
        { # broken
            return "";
        }
    }
    if(defined $RegisteredObj{$LVer}{$Name})
    { # registered paths
        return $RegisteredObj{$LVer}{$Name};
    }
    if(defined $RegisteredSoname{$LVer}{$Name})
    { # registered paths
        return $RegisteredSoname{$LVer}{$Name};
    }
    if(my $DefaultPath = $In::Opt{"LibDefaultPath"}{$Name})
    { # ldconfig default paths
        return $DefaultPath;
    }
    foreach my $Dir (@{$In::Opt{"DefaultLibPaths"}}, @{$In::Opt{"SysPaths"}{"lib"}})
    { # search in default linker directories
      # and then in all system paths
        if(-f $Dir."/".$Name) {
            return join_P($Dir,$Name);
        }
    }
    
    checkSystemFiles();
    
    if(my @AllObjects = keys(%{$In::Opt{"SystemObjects"}{$Name}})) {
        return $AllObjects[0];
    }
    if(my $ShortName = libPart($Name, "name+ext"))
    {
        if($ShortName ne $Name)
        { # FIXME: check this case
            if(my $Path = getLibPath($LVer, $ShortName)) {
                return $Path;
            }
        }
    }
    # can't find
    return "";
}

my %Prefix_Lib_Map=(
 # symbols for autodetecting library dependencies (by prefix)
    "pthread_" => ["libpthread"],
    "g_" => ["libglib-2.0", "libgobject-2.0", "libgio-2.0"],
    "cairo_" => ["libcairo"],
    "gtk_" => ["libgtk-x11-2.0"],
    "atk_" => ["libatk-1.0"],
    "gdk_" => ["libgdk-x11-2.0"],
    "gl" => ["libGL"],
    "glu" => ["libGLU"],
    "popt" => ["libpopt"],
    "Py" => ["libpython"],
    "jpeg_" => ["libjpeg"],
    "BZ2_" => ["libbz2"],
    "Fc" => ["libfontconfig"],
    "Xft" => ["libXft"],
    "SSL_" => ["libssl"],
    "sem_" => ["libpthread"],
    "snd_" => ["libasound"],
    "art_" => ["libart_lgpl_2"],
    "dbus_g" => ["libdbus-glib-1"],
    "GOMP_" => ["libgomp"],
    "omp_" => ["libgomp"],
    "cms" => ["liblcms"]
);

my %Pattern_Lib_Map=(
    "SL[a-z]" => ["libslang"]
);

my %Symbol_Lib_Map=(
 # symbols for autodetecting library dependencies (by name)
    "pow" => "libm",
    "fmod" => "libm",
    "sin" => "libm",
    "floor" => "libm",
    "cos" => "libm",
    "dlopen" => "libdl",
    "deflate" => "libz",
    "inflate" => "libz",
    "move_panel" => "libpanel",
    "XOpenDisplay" => "libX11",
    "resize_term" => "libncurses",
    "clock_gettime" => "librt",
    "crypt" => "libcrypt"
);

sub find_SymbolLibs($$)
{
    my ($LVer, $Symbol) = @_;
    
    if(index($Symbol, "g_")==0 and $Symbol=~/[A-Z]/)
    { # debug symbols
        return ();
    }
    
    my $LibExt = $In::Opt{"Ext"};
    
    my %Paths = ();
    
    if(my $LibName = $Symbol_Lib_Map{$Symbol})
    {
        if(my $Path = getLibPath($LVer, $LibName.".".$LibExt)) {
            $Paths{$Path} = 1;
        }
    }
    
    if(my $SymbolPrefix = getPrefix($Symbol))
    {
        if(defined $Cache{"find_SymbolLibs"}{$SymbolPrefix}) {
            return @{$Cache{"find_SymbolLibs"}{$SymbolPrefix}};
        }
    
        if(not keys(%Paths))
        {
            if(defined $Prefix_Lib_Map{$SymbolPrefix})
            {
                foreach my $LibName (@{$Prefix_Lib_Map{$SymbolPrefix}})
                {
                    if(my $Path = getLibPath($LVer, $LibName.".".$LibExt)) {
                        $Paths{$Path} = 1;
                    }
                }
            }
        }
        
        if(not keys(%Paths))
        {
            foreach my $Prefix (sort keys(%Pattern_Lib_Map))
            {
                if($Symbol=~/\A$Prefix/)
                {
                    foreach my $LibName (@{$Pattern_Lib_Map{$Prefix}})
                    {
                        if(my $Path = getLibPath($LVer, $LibName.".".$LibExt)) {
                            $Paths{$Path} = 1;
                        }
                    }
                }
            }
        }
    
        if(not keys(%Paths))
        {
            if($SymbolPrefix)
            { # try to find a library by symbol prefix
                if($SymbolPrefix eq "inotify" and
                index($Symbol, "\@GLIBC")!=-1)
                {
                    if(my $Path = getLibPath($LVer, "libc.$LibExt")) {
                        $Paths{$Path} = 1;
                    }
                }
                else
                {
                    if(my $Path = getLibPathPrefix($LVer, $SymbolPrefix)) {
                        $Paths{$Path} = 1;
                    }
                }
            }
        }
        
        if(my @Paths = keys(%Paths)) {
            $Cache{"find_SymbolLibs"}{$SymbolPrefix} = \@Paths;
        }
    }
    return keys(%Paths);
}

sub getLibPathPrefix($$)
{
    my ($LVer, $Prefix) = @_;
    my $LibExt = $In::Opt{"Ext"};
    
    $Prefix = lc($Prefix);
    $Prefix=~s/[_]+\Z//g;
    
    foreach ("-2", "2", "-1", "1", "")
    { # libgnome-2.so
      # libxml2.so
      # libdbus-1.so
        if(my $Path = getLibPath($LVer, "lib".$Prefix.$_.".".$LibExt)) {
            return $Path;
        }
    }
    return "";
}

return 1;
