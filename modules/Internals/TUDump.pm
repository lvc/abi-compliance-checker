###########################################################################
# A module to create AST dump
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

my %C_Structure = map {$_=>1} (
# FIXME: Can't separate union and struct data types before dumping,
# so it sometimes cause compilation errors for unknown reason
# when trying to declare TYPE* tmp_add_class_N
# This is a list of such structures + list of other C structures
    "sigval",
    "sigevent",
    "sigaction",
    "sigvec",
    "sigstack",
    "timeval",
    "timezone",
    "rusage",
    "rlimit",
    "wait",
    "flock",
    "stat",
    "_stat",
    "stat32",
    "_stat32",
    "stat64",
    "_stat64",
    "_stati64",
    "if_nameindex",
    "usb_device",
    "sigaltstack",
    "sysinfo",
    "timeLocale",
    "tcp_debug",
    "rpc_createerr",
    "dirent",
    "dirent64",
    "pthread_attr_t",
    "_fpreg",
    "_fpstate",
    "_fpx_sw_bytes",
    "_fpxreg",
    "_libc_fpstate",
    "_libc_fpxreg",
    "_libc_xmmreg",
    "_xmmreg",
    "_xsave_hdr",
    "_xstate",
    "_ymmh_state",
    "_prop_t",
 # Other
    "timespec",
    "random_data",
    "drand48_data",
    "_IO_marker",
    "_IO_FILE",
    "lconv",
    "sched_param",
    "tm",
    "itimerspec",
    "_pthread_cleanup_buffer",
    "fd_set",
    "siginfo",
    "mallinfo",
    "timex",
    "sigcontext",
    "ucontext",
 # Mac
    "_timex",
    "_class_t",
    "_category_t",
    "_class_ro_t",
    "_protocol_t",
    "_message_ref_t",
    "_super_message_ref_t",
    "_ivar_t",
    "_ivar_list_t"
);

my %CppKeywords_C = map {$_=>1} (
    # C++ 2003 keywords
    "public",
    "protected",
    "private",
    "default",
    "template",
    "new",
    #"asm",
    "dynamic_cast",
    "auto",
    "try",
    "namespace",
    "typename",
    "using",
    "reinterpret_cast",
    "friend",
    "class",
    "virtual",
    "const_cast",
    "mutable",
    "static_cast",
    "export",
    # C++0x keywords
    "noexcept",
    "nullptr",
    "constexpr",
    "static_assert",
    "explicit",
    # cannot be used as a macro name
    # as it is an operator in C++
    "and",
    #"and_eq",
    "not",
    #"not_eq",
    "or"
    #"or_eq",
    #"bitand",
    #"bitor",
    #"xor",
    #"xor_eq",
    #"compl"
);

my %CppKeywords_F = map {$_=>1} (
    "delete",
    "catch",
    "alignof",
    "thread_local",
    "decltype",
    "typeid"
);

my %CppKeywords_O = map {$_=>1} (
    "bool",
    "register",
    "inline",
    "operator"
);

my %CppKeywords_A = map {$_=>1} (
    "this",
    "throw",
    "template"
);

foreach (keys(%CppKeywords_C),
keys(%CppKeywords_F),
keys(%CppKeywords_O)) {
    $CppKeywords_A{$_}=1;
}

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

my %PreprocessedHeaders;
my %TUnit_NameSpaces;
my %TUnit_Classes;
my %TUnit_Funcs;
my %TUnit_Vars;

my %AutoPreambleMode = (
  "1"=>0,
  "2"=>0
);

my %MinGWMode = (
  "1"=>0,
  "2"=>0
);

my %Cpp0xMode = (
  "1"=>0,
  "2"=>0
);

sub createTUDump($)
{
    my $LVer = $_[0];
    
    if(not $In::Opt{"GccPath"}) {
        exitStatus("Error", "internal error - GCC path is not set");
    }
    
    searchForHeaders($LVer);
    
    my @Headers = keys(%{$In::Desc{$LVer}{"RegHeader"}});
    @Headers = sort {$In::Desc{$LVer}{"RegHeader"}{$a}{"Pos"}<=>$In::Desc{$LVer}{"RegHeader"}{$b}{"Pos"}} @Headers;
    
    my @IncHeaders = (@{$In::Desc{$LVer}{"Include_Preamble"}}, @Headers);
    my $IncludeString = getIncString(getIncPaths(\@IncHeaders, $LVer), "GCC");
    
    my $TmpDir = $In::Opt{"Tmp"};
    my $TmpHeaderPath = $TmpDir."/dump".$LVer.".h";
    my $HeaderPath = $TmpHeaderPath;
    
    # write tmp-header
    open(TMP_HEADER, ">", $TmpHeaderPath) || die ("can't open file \'$TmpHeaderPath\': $!\n");
    if(my $AddDefines = $In::Desc{$LVer}{"Defines"})
    {
        $AddDefines=~s/\n\s+/\n  /g;
        print TMP_HEADER "\n  // add defines\n  ".$AddDefines."\n";
    }
    print TMP_HEADER "\n  // add includes\n";
    foreach my $HPath (@{$In::Desc{$LVer}{"Include_Preamble"}}) {
        print TMP_HEADER "  #include \"".pathFmt($HPath, "unix")."\"\n";
    }
    foreach my $HPath (@Headers)
    {
        if(not grep {$HPath eq $_} (@{$In::Desc{$LVer}{"Include_Preamble"}})) {
            print TMP_HEADER "  #include \"".pathFmt($HPath, "unix")."\"\n";
        }
    }
    close(TMP_HEADER);
    
    if(my $EInfo = $In::Opt{"ExtraInfo"})
    {
        if($IncludeString) {
            writeFile($EInfo."/include-string", $IncludeString);
        }
        dumpFilesInfo($LVer);
    }
    
    if(not defined $In::Desc{$LVer}{"TargetHeader"}) {
        addTargetHeaders($LVer);
    }
    
    # preprocessing stage
    my $Pre = callPreprocessor($TmpHeaderPath, $IncludeString, $LVer);
    checkPreprocessedUnit($Pre, $LVer);
    
    if(my $EInfo = $In::Opt{"ExtraInfo"})
    { # extra information for other tools
        writeFile($EInfo."/header-paths", join("\n", sort keys(%{$PreprocessedHeaders{$LVer}})));
    }
    
    # clean memory
    delete($PreprocessedHeaders{$LVer});
    
    if($In::ABI{$LVer}{"Language"} eq "C++") {
        checkCTags($Pre, $LVer);
    }
    
    if(my $PrePath = preChange($TmpHeaderPath, $IncludeString, $LVer))
    { # try to correct the preprocessor output
        $HeaderPath = $PrePath;
    }
    
    my $GCC_8 = checkGcc("8"); # support for GCC 8 and new options
    
    if($In::ABI{$LVer}{"Language"} eq "C++")
    { # add classes and namespaces to the dump
        my $CHdump = "-fdump-class-hierarchy";
        if($GCC_8)
        { # -fdump-lang-class instead of -fdump-class-hierarchy
            $CHdump = "-fdump-lang-class";
        }
        $CHdump .= " -c";
        
        if($In::Desc{$LVer}{"CppMode"}==1
        or $MinGWMode{$LVer}==1) {
            $CHdump .= " -fpreprocessed";
        }
        my $ClassHierarchyCmd = getCompileCmd($HeaderPath, $CHdump, $IncludeString, $LVer);
        chdir($TmpDir);
        system($ClassHierarchyCmd." >null 2>&1");
        chdir($In::Opt{"OrigDir"});
        if(my $ClassDump = (cmdFind($TmpDir,"f","*.class",1))[0])
        {
            my $Content = readFile($ClassDump);
            foreach my $ClassInfo (split(/\n\n/, $Content))
            {
                if($ClassInfo=~/\AClass\s+(.+)\s*/i)
                {
                    my $CName = $1;
                    if($CName=~/\A(__|_objc_|_opaque_)/) {
                        next;
                    }
                    $TUnit_NameSpaces{$LVer}{$CName} = -1;
                    if($CName=~/\A[\w:]+\Z/)
                    { # classes
                        $TUnit_Classes{$LVer}{$CName} = 1;
                    }
                    if($CName=~/(\w[\w:]*)::/)
                    { # namespaces
                        my $NS = $1;
                        if(not defined $TUnit_NameSpaces{$LVer}{$NS}) {
                            $TUnit_NameSpaces{$LVer}{$NS} = 1;
                        }
                    }
                }
                elsif($ClassInfo=~/\AVtable\s+for\s+(.+)\n((.|\n)+)\Z/i)
                { # read v-tables (advanced approach)
                    my ($CName, $VTable) = ($1, $2);
                    $In::ABI{$LVer}{"ClassVTable_Content"}{$CName} = $VTable;
                }
            }
            foreach my $NS (keys(%{$In::Desc{$LVer}{"AddNameSpaces"}}))
            { # add user-defined namespaces
                $TUnit_NameSpaces{$LVer}{$NS} = 1;
            }
            if($In::Opt{"Debug"})
            { # debug mode
                copy($ClassDump, getDebugDir($LVer)."/class-hierarchy-dump.txt");
            }
            unlink($ClassDump);
        }
        
        # add namespaces and classes
        if(my $NSAdd = getNSAdditions($LVer, $TUnit_NameSpaces{$LVer}))
        { # GCC on all supported platforms does not include namespaces to the dump by default
            appendFile($HeaderPath, "\n  // add namespaces\n".$NSAdd);
            
            if($HeaderPath ne $TmpHeaderPath) {
                appendFile($TmpHeaderPath, "\n  // add namespaces\n".$NSAdd);
            }
        }
        # some GCC versions don't include class methods to the TU dump by default
        my ($AddClass, $ClassNum) = ("", 0);
        my $GCC_44 = checkGcc("4.4"); # support for old GCC versions
        foreach my $CName (sort keys(%{$TUnit_Classes{$LVer}}))
        {
            next if($C_Structure{$CName});
            next if(not $In::Opt{"StdcxxTesting"} and $CName=~/\Astd::/);
            next if($In::Desc{$LVer}{"SkipTypes"}{$CName});
            if(not $In::Opt{"Force"} and $GCC_44
            and $In::Opt{"OS"} eq "linux")
            { # optimization for linux with GCC >= 4.4
              # disable this code by -force option
                if(index($CName, "::")!=-1)
                { # should be added by name space
                    next;
                }
            }
            else
            {
                if($CName=~/\A(.+)::[^:]+\Z/
                and $TUnit_Classes{$LVer}{$1})
                { # classes inside other classes
                    next;
                }
            }
            if(defined $TUnit_Funcs{$LVer}{$CName})
            { # the same name for a function and type
                next;
            }
            if(defined $TUnit_Vars{$LVer}{$CName})
            { # the same name for a variable and type
                next;
            }
            $AddClass .= "  $CName* tmp_add_class_".($ClassNum++).";\n";
        }
        if($AddClass)
        {
            appendFile($HeaderPath, "\n  // add classes\n".$AddClass);
            
            if($HeaderPath ne $TmpHeaderPath) {
                appendFile($TmpHeaderPath, "\n  // add classes\n".$AddClass);
            }
        }
    }
    writeLog($LVer, "Temporary header file \'$TmpHeaderPath\' with the following content will be compiled to create GCC translation unit dump:\n".readFile($TmpHeaderPath)."\n");
    
    # create TU dump
    my $TUdump = "-fdump-translation-unit";
    if ($GCC_8)
    { # -fdump-lang-raw instead of -fdump-translation-unit
        $TUdump = "-fdump-lang-raw";
    }
    $TUdump .= " -fkeep-inline-functions -c";
    if($In::Opt{"UserLang"} eq "C") {
        $TUdump .= " -U__cplusplus -D_Bool=\"bool\"";
    }
    if($In::Desc{$LVer}{"CppMode"}==1
    or $MinGWMode{$LVer}==1) {
        $TUdump .= " -fpreprocessed";
    }
    my $SyntaxTreeCmd = getCompileCmd($HeaderPath, $TUdump, $IncludeString, $LVer);
    writeLog($LVer, "The GCC parameters:\n  $SyntaxTreeCmd\n\n");
    chdir($TmpDir);
    system($SyntaxTreeCmd." >\"$TmpDir/tu_errors\" 2>&1");
    chdir($In::Opt{"OrigDir"});
    
    my $Errors = "";
    if($?)
    { # failed to compile, but the TU dump still can be created
        if($Errors = readFile($TmpDir."/tu_errors"))
        { # try to recompile
          # FIXME: handle errors and try to recompile
            if($AutoPreambleMode{$LVer}!=-1
            and my $AddHeaders = detectPreamble($Errors, $LVer))
            { # add auto preamble headers and try again
                $AutoPreambleMode{$LVer}=-1;
                my @Headers = sort {$b cmp $a} keys(%{$AddHeaders}); # sys/types.h should be the first
                foreach my $Num (0 .. $#Headers)
                {
                    my $Path = $Headers[$Num];
                    if(not grep {$Path eq $_} (@{$In::Desc{$LVer}{"Include_Preamble"}}))
                    {
                        push_U($In::Desc{$LVer}{"Include_Preamble"}, $Path);
                        printMsg("INFO", "Adding \'".$AddHeaders->{$Path}{"Header"}."\' preamble header for \'".$AddHeaders->{$Path}{"Type"}."\'");
                    }
                }
                resetLogging($LVer);
                $TmpDir = tempdir(CLEANUP=>1);
                return createTUDump($LVer);
            }
            elsif($Cpp0xMode{$LVer}!=-1
            and ($Errors=~/\Q-std=c++0x\E/
            or $Errors=~/is not a class or namespace/))
            { # c++0x: enum class
                if(checkGcc("4.6"))
                {
                    $Cpp0xMode{$LVer}=-1;
                    printMsg("INFO", "Enabling c++0x mode");
                    resetLogging($LVer);
                    $TmpDir = tempdir(CLEANUP=>1);
                    $In::Desc{$LVer}{"CompilerOptions"} .= " -std=c++0x";
                    return createTUDump($LVer);
                }
                else {
                    printMsg("WARNING", "Probably c++0x element detected");
                }
                
            }
            writeLog($LVer, $Errors);
        }
        else {
            writeLog($LVer, "$!: $?\n");
        }
        printMsg("ERROR", "some errors occurred when compiling headers");
        printErrorLog($LVer);
        $In::Opt{"CompileError"} = 1;
        writeLog($LVer, "\n"); # new line
    }
    
    unlink($TmpHeaderPath);
    unlink($HeaderPath);

    my $dumpExt;
    if ($GCC_8) {
        $dumpExt = "*.raw";
    }
    else {
        $dumpExt = "*.tu";
    }
    if(my @TUs = cmdFind($TmpDir,"f",$dumpExt,1)) {
        return $TUs[0];
    }
    else
    {
        my $Msg = "can't compile header(s)";
        if($Errors=~/error trying to exec \W+cc1plus\W+/) {
            $Msg .= "\nDid you install G++?";
        }
        exitStatus("Cannot_Compile", $Msg);
    }
}

sub detectPreamble($$)
{
    my ($Content, $LVer) = @_;
    my %HeaderElems = (
        # Types
        "stdio.h" => ["FILE", "va_list"],
        "stddef.h" => ["NULL", "ptrdiff_t"],
        "stdint.h" => ["uint8_t", "uint16_t", "uint32_t", "uint64_t",
                       "int8_t", "int16_t", "int32_t", "int64_t"],
        "time.h" => ["time_t"],
        "sys/types.h" => ["ssize_t", "u_int32_t", "u_short", "u_char",
                          "u_int", "off_t", "u_quad_t", "u_long", "mode_t"],
        "unistd.h" => ["gid_t", "uid_t", "socklen_t"],
        "stdbool.h" => ["_Bool"],
        "rpc/xdr.h" => ["bool_t"],
        "in_systm.h" => ["n_long", "n_short"],
        # Fields
        "arpa/inet.h" => ["fw_src", "ip_src"],
        # Functions
        "stdlib.h" => ["free", "malloc", "size_t"],
        "string.h" => ["memmove", "strcmp"]
    );
    my %AutoPreamble = ();
    foreach (keys(%HeaderElems))
    {
        foreach my $Elem (@{$HeaderElems{$_}}) {
            $AutoPreamble{$Elem} = $_;
        }
    }
    my %Types = ();
    while($Content=~s/error\:\s*(field\s*|)\W+(.+?)\W+//)
    { # error: 'FILE' has not been declared
        $Types{$2} = 1;
    }
    if(keys(%Types))
    {
        my %AddHeaders = ();
        foreach my $Type (keys(%Types))
        {
            if(my $Header = $AutoPreamble{$Type})
            {
                if(my $Path = identifyHeader($Header, $LVer))
                {
                    if(skipHeader($Path, $LVer)) {
                        next;
                    }
                    $Path = pathFmt($Path);
                    $AddHeaders{$Path}{"Type"} = $Type;
                    $AddHeaders{$Path}{"Header"} = $Header;
                }
            }
        }
        if(keys(%AddHeaders)) {
            return \%AddHeaders;
        }
    }
    return undef;
}

sub checkCTags($$)
{
    my ($Path, $LVer) = @_;
    
    my $CTags = undef;
    
    if($In::Opt{"OS"} eq "bsd")
    { # use ectags on BSD
        $CTags = getCmdPath("ectags");
        if(not $CTags) {
            printMsg("WARNING", "can't find \'ectags\' program");
        }
    }
    if(not $CTags) {
        $CTags = getCmdPath("ctags");
    }
    if(not $CTags)
    {
        printMsg("WARNING", "can't find \'ctags\' program");
        return;
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    if($In::Opt{"OS"} ne "linux")
    { # macos, freebsd, etc.
        my $Info = `$CTags --version 2>\"$TmpDir/null\"`;
        if($Info!~/universal|exuberant/i)
        {
            printMsg("WARNING", "incompatible version of \'ctags\' program");
            return;
        }
    }
    
    my $Out = $TmpDir."/ctags.txt";
    system("$CTags --c-kinds=pxn -f \"$Out\" \"$Path\" 2>\"$TmpDir/null\"");
    if($In::Opt{"Debug"}) {
        copy($Out, getDebugDir($LVer)."/ctags.txt");
    }
    open(CTAGS, "<", $Out);
    while(my $Line = <CTAGS>)
    {
        chomp($Line);
        my ($Name, $Header, $Def, $Type, $Scpe) = split(/\t/, $Line);
        if(defined $IntrinsicKeywords{$Name})
        { # noise
            next;
        }
        if($Type eq "n")
        {
            if(index($Scpe, "class:")==0) {
                next;
            }
            if(index($Scpe, "struct:")==0) {
                next;
            }
            if(index($Scpe, "namespace:")==0)
            {
                if($Scpe=~s/\Anamespace://) {
                    $Name = $Scpe."::".$Name;
                }
            }
            $TUnit_NameSpaces{$LVer}{$Name} = 1;
        }
        elsif($Type eq "p")
        {
            if(not $Scpe or index($Scpe, "namespace:")==0) {
                $TUnit_Funcs{$LVer}{$Name} = 1;
            }
        }
        elsif($Type eq "x")
        {
            if(not $Scpe or index($Scpe, "namespace:")==0) {
                $TUnit_Vars{$LVer}{$Name} = 1;
            }
        }
    }
    close(CTAGS);
}

sub preChange($$$)
{
    my ($HeaderPath, $IncStr, $LVer) = @_;
    
    my $TmpDir = $In::Opt{"Tmp"};
    my $PreprocessCmd = getCompileCmd($HeaderPath, "-E", $IncStr, $LVer);
    my $Content = undef;
    
    if(not defined $In::Opt{"MinGWCompat"}
    and $In::Opt{"Target"} eq "windows"
    and $In::Opt{"GccTarget"}=~/mingw/i
    and $MinGWMode{$LVer}!=-1)
    { # modify headers to compile by MinGW
        if(not $Content)
        { # preprocessing
            $Content = `$PreprocessCmd 2>\"$TmpDir/null\"`;
        }
        if($Content=~s/__asm\s*(\{[^{}]*?\}|[^{};]*)//g)
        { # __asm { ... }
            $MinGWMode{$LVer}=1;
        }
        if($Content=~s/\s+(\/ \/.*?)\n/\n/g)
        { # comments after preprocessing
            $MinGWMode{$LVer}=1;
        }
        if($Content=~s/(\W)(0x[a-f]+|\d+)(i|ui)(8|16|32|64)(\W)/$1$2$5/g)
        { # 0xffui8
            $MinGWMode{$LVer}=1;
        }
        
        if($MinGWMode{$LVer}) {
            printMsg("INFO", "Using MinGW compatibility mode");
        }
    }
    
    if(defined $In::Opt{"CxxIncompat"}
    and $In::ABI{$LVer}{"Language"} eq "C"
    and $In::Desc{$LVer}{"CppMode"}!=-1 and not $In::Opt{"CppHeaders"})
    { # rename C++ keywords in C code
        printMsg("INFO", "Checking the code for C++ keywords");
        if(not $Content)
        { # preprocessing
            $Content = `$PreprocessCmd 2>\"$TmpDir/null\"`;
        }
        
        my $RegExp_C = join("|", keys(%CppKeywords_C));
        my $RegExp_F = join("|", keys(%CppKeywords_F));
        my $RegExp_O = join("|", keys(%CppKeywords_O));
        
        my $Detected = undef;
        my $Regex = undef;
        
        $Regex = qr/(\A|\n[^\#\/\n][^\n]*?|\n)(\*\s*|\s+|\@|\,|\()($RegExp_C|$RegExp_F)(\s*([\,\)\;\.\[]|\-\>|\:\s*\d))/;
        while($Content=~/$Regex/)
        { # MATCH:
          # int foo(int new, int class, int (*new)(int));
          # int foo(char template[], char*);
          # unsigned private: 8;
          # DO NOT MATCH:
          # #pragma GCC visibility push(default)
            my $Sentence_O = "$1$2$3$4";
            
            if($Sentence_O=~/\s+decltype\(/)
            { # C++
              # decltype(nullptr)
                last;
            }
            else
            {
                $Content=~s/$Regex/$1$2c99_$3$4/g;
                $In::Desc{$LVer}{"CppMode"} = 1;
                if(not defined $Detected) {
                    $Detected = $Sentence_O;
                }
            }
        }
        if($Content=~s/([^\w\s]|\w\s+)(?<!operator )(delete)(\s*\()/$1c99_$2$3/g)
        { # MATCH:
          # int delete(...);
          # int explicit(...);
          # DO NOT MATCH:
          # void operator delete(...)
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\s+)($RegExp_O)(\s*(\;|\:))/$1c99_$2$3/g)
        { # MATCH:
          # int bool;
          # DO NOT MATCH:
          # bool X;
          # return *this;
          # throw;
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\s+)(operator)(\s*(\(\s*\)\s*[^\(\s]|\(\s*[^\)\s]))/$1c99_$2$3/g)
        { # MATCH:
          # int operator(...);
          # DO NOT MATCH:
          # int operator()(...);
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/([^\w\(\,\s]\s*|\s+)(operator)(\s*(\,\s*[^\(\s]|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(int operator);
          # int foo(int operator, int other);
          # DO NOT MATCH:
          # int operator,(...);
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\*\s*|\w\s+)(bool)(\s*(\,|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(gboolean *bool);
          # DO NOT MATCH:
          # void setTabEnabled(int index, bool);
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\w)(\s*[^\w\(\,\s]\s*|\s+)(this|throw)(\s*[\,\)])/$1$2c99_$3$4/g)
        { # MATCH:
          # int foo(int* this);
          # int bar(int this);
          # int baz(int throw);
          # DO NOT MATCH:
          # foo(X, this);
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2$3$4" if(not defined $Detected);
        }
        if($Content=~s/(struct |extern )(template) /$1c99_$2 /g)
        { # MATCH:
          # struct template {...};
          # extern template foo(...);
            $In::Desc{$LVer}{"CppMode"} = 1;
            $Detected = "$1$2" if(not defined $Detected);
        }
        
        if($In::Desc{$LVer}{"CppMode"} == 1)
        {
            if($In::Opt{"Debug"})
            {
                $Detected=~s/\A\s+//g;
                printMsg("INFO", "Detected code: \"$Detected\"");
            }
        }
        
        # remove typedef enum NAME NAME;
        my @FwdTypedefs = $Content=~/typedef\s+enum\s+(\w+)\s+(\w+);/g;
        my $N = 0;
        while($N<=$#FwdTypedefs-1)
        {
            my $S = $FwdTypedefs[$N];
            if($S eq $FwdTypedefs[$N+1])
            {
                $Content=~s/typedef\s+enum\s+\Q$S\E\s+\Q$S\E;//g;
                $In::Desc{$LVer}{"CppMode"} = 1;
                
                if($In::Opt{"Debug"}) {
                    printMsg("INFO", "Detected code: \"typedef enum $S $S;\"");
                }
            }
            $N+=2;
        }
        
        if($In::Desc{$LVer}{"CppMode"}==1) {
            printMsg("INFO", "Using C++ compatibility mode");
        }
        else {
            printMsg("INFO", "C++ keywords in the C code are not found");
        }
    }
        
    if($In::Desc{$LVer}{"CppMode"}==1
    or $MinGWMode{$LVer}==1)
    {
        my $IPath = $TmpDir."/dump$LVer.i";
        writeFile($IPath, $Content);
        return $IPath;
    }
    
    return undef;
}

sub getNSAdditions($$)
{
    my ($LVer, $NameSpaces) = @_;
    
    my ($Additions, $AddNameSpaceId) = ("", 1);
    foreach my $NS (sort {$a=~/_/ <=> $b=~/_/} sort {lc($a) cmp lc($b)} keys(%{$NameSpaces}))
    {
        next if($In::Desc{$LVer}{"SkipNameSpaces"}{$NS});
        next if(not $NS or $NameSpaces->{$NS}==-1);
        next if($NS=~/(\A|::)iterator(::|\Z)/i);
        next if($NS=~/\A__/i);
        next if(($NS=~/\Astd::/ or $NS=~/\A(std|tr1|rel_ops|fcntl)\Z/) and not $In::Opt{"StdcxxTesting"});
        
        $In::ABI{$LVer}{"NameSpaces"}{$NS} = 1; # for future use in reports
        
        my ($TypeDecl_Prefix, $TypeDecl_Suffix) = ();
        my @NS_Parts = split(/::/, $NS);
        next if($#NS_Parts==-1);
        next if($NS_Parts[0]=~/\A(random|or)\Z/);
        foreach my $NS_Part (@NS_Parts)
        {
            $TypeDecl_Prefix .= "namespace $NS_Part\{";
            $TypeDecl_Suffix .= "}";
        }
        my $TypeDecl = $TypeDecl_Prefix."typedef int tmp_add_type_".$AddNameSpaceId.";".$TypeDecl_Suffix;
        my $FuncDecl = "$NS\:\:tmp_add_type_$AddNameSpaceId tmp_add_func_$AddNameSpaceId(){return 0;};";
        $Additions .= "  $TypeDecl\n  $FuncDecl\n";
        $AddNameSpaceId += 1;
    }
    return $Additions;
}

sub includeOpt($$)
{
    my ($Path, $Style) = @_;
    if($Style eq "GCC")
    { # GCC options
        if($In::Opt{"OS"} eq "windows")
        { # to MinGW GCC
            return "-I\"".pathFmt($Path, "unix")."\"";
        }
        elsif($In::Opt{"OS"} eq "macos"
        and $Path=~/\.framework\Z/)
        { # to Apple's GCC
            return "-F".escapeArg(getDirname($Path));
        }
        else {
            return "-I".escapeArg($Path);
        }
    }
    elsif($Style eq "CL") {
        return "/I \"".$Path."\"";
    }
    return "";
}

sub checkPreprocessedUnit($$)
{
    my ($Path, $LVer) = @_;
    
    my $TmpDir = $In::Opt{"Tmp"};
    my ($CurHeader, $CurHeaderName) = ("", "");
    my $CurClass = ""; # extra info
    
    my $CRef = $In::ABI{$LVer}{"Constants"};
    
    if(not $CRef) {
        $CRef = {};
    }
    
    open(PREPROC, $Path) || die ("can't open file \'$Path\': $!\n");
    while(my $Line = <PREPROC>)
    { # detecting public and private constants
        if(substr($Line, 0, 1) eq "#")
        {
            chomp($Line);
            if($Line=~/\A\#\s+\d+\s+\"(.+)\"/)
            {
                $CurHeader = pathFmt($1);
                $CurHeaderName = getFilename($CurHeader);
                $CurClass = "";
                
                if(index($CurHeader, $TmpDir)==0) {
                    next;
                }
                
                if(substr($CurHeaderName, 0, 1) eq "<")
                { # <built-in>, <command-line>, etc.
                    $CurHeaderName = "";
                    $CurHeader = "";
                }
                
                if($In::Opt{"ExtraInfo"})
                {
                    if($CurHeaderName) {
                        $PreprocessedHeaders{$LVer}{$CurHeader} = 1;
                    }
                }
            }
            if(not $In::Opt{"ExtraDump"})
            {
                if($CurHeaderName)
                {
                    if(not $In::Desc{$LVer}{"IncludeNeighbors"}{$CurHeaderName}
                    and not $In::Desc{$LVer}{"RegHeader"}{$CurHeader})
                    { # not a target
                        next;
                    }
                    if(not isTargetHeader($CurHeaderName, 1)
                    and not isTargetHeader($CurHeaderName, 2))
                    { # user-defined header
                        next;
                    }
                }
            }
            
            if($Line=~/\A\#\s*define\s+(\w+)\s+(.+)\s*\Z/)
            {
                my ($Name, $Value) = ($1, $2);
                if(not $CRef->{$Name}{"Access"})
                {
                    $CRef->{$Name}{"Access"} = "public";
                    $CRef->{$Name}{"Value"} = $Value;
                    if($CurHeaderName) {
                        $CRef->{$Name}{"Header"} = $CurHeaderName;
                    }
                }
            }
            elsif($Line=~/\A\#[ \t]*undef[ \t]+([_A-Z]+)[ \t]*/) {
                $CRef->{$1}{"Access"} = "private";
            }
        }
        else
        {
            if($In::Opt{"ExtraDump"})
            {
                if($Line=~/(\w+)\s*\(/)
                { # functions
                    $In::ABI{$LVer}{"SymbolHeader"}{$CurClass}{$1} = $CurHeader;
                }
                elsif($Line=~/(\A|\s)class\s+(\w+)/) {
                    $CurClass = $2;
                }
            }
        }
    }
    close(PREPROC);
    
    foreach my $Constant (keys(%{$CRef}))
    {
        if($CRef->{$Constant}{"Access"} eq "private")
        {
            delete($CRef->{$Constant});
            next;
        }
        
        if(not $In::Opt{"ExtraDump"} and ($Constant=~/_h\Z/i
        or isBuiltIn($CRef->{$Constant}{"Header"})))
        { # skip
            delete($CRef->{$Constant});
        }
        else {
            delete($CRef->{$Constant}{"Access"});
        }
    }
    
    if($In::Opt{"Debug"}) {
        copy($Path, getDebugDir($LVer)."/preprocessor.txt");
    }
}

return 1;
