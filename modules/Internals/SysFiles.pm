###########################################################################
# A module to find system files and automatically generate include paths
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

loadModule("ElfTools");

my %Cache;

my %BinUtils = map {$_=>1} (
    "c++filt",
    "objdump",
    "readelf"
);

# Header file extensions as described by gcc
my $HEADER_EXT = "h|hh|hp|hxx|hpp|h\\+\\+|tcc|txx|x|inl|inc|ads|isph";

my %GlibcHeader = map {$_=>1} (
    "aliases.h",
    "argp.h",
    "argz.h",
    "assert.h",
    "cpio.h",
    "ctype.h",
    "dirent.h",
    "envz.h",
    "errno.h",
    "error.h",
    "execinfo.h",
    "fcntl.h",
    "fstab.h",
    "ftw.h",
    "glob.h",
    "grp.h",
    "iconv.h",
    "ifaddrs.h",
    "inttypes.h",
    "langinfo.h",
    "limits.h",
    "link.h",
    "locale.h",
    "malloc.h",
    "math.h",
    "mntent.h",
    "monetary.h",
    "nl_types.h",
    "obstack.h",
    "printf.h",
    "pwd.h",
    "regex.h",
    "sched.h",
    "search.h",
    "setjmp.h",
    "shadow.h",
    "signal.h",
    "spawn.h",
    "stdarg.h",
    "stdint.h",
    "stdio.h",
    "stdlib.h",
    "string.h",
    "strings.h",
    "tar.h",
    "termios.h",
    "time.h",
    "ulimit.h",
    "unistd.h",
    "utime.h",
    "wchar.h",
    "wctype.h",
    "wordexp.h" );

my %GlibcDir = map {$_=>1} (
    "arpa",
    "bits",
    "gnu",
    "netinet",
    "net",
    "nfs",
    "rpc",
    "sys",
    "linux" );

my %WinHeaders = map {$_=>1} (
    "dos.h",
    "process.h",
    "winsock.h",
    "config-win.h",
    "mem.h",
    "windows.h",
    "winsock2.h",
    "crtdbg.h",
    "ws2tcpip.h"
);

my %ObsoleteHeaders = map {$_=>1} (
    "iostream.h",
    "fstream.h"
);

my %AlienHeaders = map {$_=>1} (
 # Solaris
    "thread.h",
    "sys/atomic.h",
 # HPUX
    "sys/stream.h",
 # Symbian
    "AknDoc.h",
 # Atari ST
    "ext.h",
    "tos.h",
 # MS-DOS
    "alloc.h",
 # Sparc
    "sys/atomic.h"
);

my %ConfHeaders = map {$_=>1} (
    "atomic",
    "conf.h",
    "config.h",
    "configure.h",
    "build.h",
    "setup.h"
);

my %LocalIncludes = map {$_=>1} (
    "/usr/local/include",
    "/usr/local" );

my %OS_AddPath=(
# These paths are needed if the tool cannot detect them automatically
    "macos"=>{
        "include"=>[
            "/Library",
            "/Developer/usr/include"
        ],
        "lib"=>[
            "/Library",
            "/Developer/usr/lib"
        ],
        "bin"=>[
            "/Developer/usr/bin"
        ]
    },
    "beos"=>{
    # Haiku has GCC 2.95.3 by default
    # try to find GCC>=3.0 in /boot/develop/abi
        "include"=>[
            "/boot/common",
            "/boot/develop"
        ],
        "lib"=>[
            "/boot/common/lib",
            "/boot/system/lib",
            "/boot/apps"
        ],
        "bin"=>[
            "/boot/common/bin",
            "/boot/system/bin",
            "/boot/develop/abi"
        ]
    }
);

my %RegisteredDirs;
my %Header_ErrorRedirect;
my %HeaderName_Paths;
my %Header_Dependency;
my @DefaultCppPaths;
my @DefaultGccPaths;
my @DefaultIncPaths;
my @DefaultBinPaths;
my %SystemHeaders;
my %DefaultCppHeader;
my %DefaultGccHeader;
my @UsersIncPath;
my %Header_Includes;
my %Header_Includes_R;
my %Header_ShouldNotBeUsed;
my %RecursiveIncludes;
my %Header_Include_Prefix;
my @RecurInclude;

my %Include_Paths = (
    "1"=>[],
    "2"=>[]
);

my %Add_Include_Paths = (
    "1"=>[],
    "2"=>[]
);

sub tryCmd($)
{
    my $Cmd = $_[0];
    
    my @Options = (
        "--version",
        "-help"
    );
    foreach my $Opt (@Options)
    {
        my $TmpDir = $In::Opt{"Tmp"};
        my $Info = `$Cmd $Opt 2>\"$TmpDir/null\"`;
        if($Info) {
            return 1;
        }
    }
    return 0;
}

sub searchTool($)
{
    my $Name = $_[0];
    
    if(my @Paths = keys(%{$In::Opt{"TargetTools"}}))
    {
        foreach my $Path (@Paths)
        {
            if(-f join_P($Path, $Name)) {
                return join_P($Path, $Name);
            }
            if(my $CrossPrefix = $In::Opt{"CrossPrefix"})
            { # user-defined prefix (arm-none-symbianelf, ...)
                my $Candidate = join_P($Path, $CrossPrefix."-".$Name);
                if(-f $Candidate) {
                    return $Candidate;
                }
            }
        }
    }
    
    return undef;
}

sub syncWithGcc($)
{
    my $Name = $_[0];
    if(my $GccPath = $In::Opt{"GccPath"})
    {
        if($GccPath=~s/\bgcc(|\.\w+)\Z/$Name$1/) {
            return $GccPath;
        }
    }
    
    return undef;
}

sub getCmdPath($)
{
    my $Name = $_[0];
    
    if(defined $Cache{"getCmdPath"}{$Name}) {
        return $Cache{"getCmdPath"}{$Name};
    }
    
    my $Path = searchTool($Name);
    if(not $Path and $In::Opt{"OS"} eq "windows") {
        $Path = searchTool($Name.".exe");
    }
    
    if(not $Path and $BinUtils{$Name})
    {
        if(my $CrossPrefix = $In::Opt{"CrossPrefix"}) {
            $Path = searchCommand($CrossPrefix."-".$Name);
        }
    }
    
    if(not $Path and $BinUtils{$Name})
    {
        if(my $Cand = syncWithGcc($Name))
        { # sync with GCC
            if($Cand=~/[\/\\]/)
            { # path
                if(-f $Cand) {
                    $Path = $Cand;
                }
            }
            elsif($Cand = searchCommand($Cand))
            { # name
                $Path = $Cand;
            }
        }
    }
    if(not $Path) {
        $Path = searchCommand($Name);
    }
    if(not $Path and $In::Opt{"OS"} eq "windows")
    { # search for *.exe file
        $Path = searchCommand($Name.".exe");
    }
    if($Path=~/\s/) {
        $Path = "\"".$Path."\"";
    }
    return ($Cache{"getCmdPath"}{$Name} = $Path);
}

sub searchCommand($)
{
    my $Name = $_[0];
    
    if(defined $Cache{"searchCommand"}{$Name}) {
        return $Cache{"searchCommand"}{$Name};
    }
    if(my $DefaultPath = getCmdPath_Default($Name)) {
        return ($Cache{"searchCommand"}{$Name} = $DefaultPath);
    }
    foreach my $Path (@{$In::Opt{"SysPaths"}{"bin"}})
    {
        my $CmdPath = join_P($Path,$Name);
        if(-f $CmdPath)
        {
            if($Name=~/gcc/) {
                next if(not checkGcc("3", $CmdPath));
            }
            return ($Cache{"searchCommand"}{$Name} = $CmdPath);
        }
    }
    return ($Cache{"searchCommand"}{$Name} = "");
}

sub getCmdPath_Default($)
{ # search in PATH
    if(defined $Cache{"getCmdPath_Default"}{$_[0]}) {
        return $Cache{"getCmdPath_Default"}{$_[0]};
    }
    return ($Cache{"getCmdPath_Default"}{$_[0]} = getCmdPath_Default_I($_[0]));
}

sub getCmdPath_Default_I($)
{ # search in PATH
    my $Name = $_[0];
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    if($Name=~/find/)
    { # special case: search for "find" utility
        if(`find \"$TmpDir\" -maxdepth 0 2>\"$TmpDir/null\"`) {
            return "find";
        }
    }
    elsif($Name=~/gcc/) {
        return checkGcc("3", $Name);
    }
    if(tryCmd($Name)) {
        return $Name;
    }
    if($In::Opt{"OS"} eq "windows")
    {
        if(`$Name /? 2>\"$TmpDir/null\"`) {
            return $Name;
        }
    }
    foreach my $Path (@DefaultBinPaths)
    {
        if(-f $Path."/".$Name) {
            return join_P($Path, $Name);
        }
    }
    return "";
}

sub checkSystemFiles()
{
    if($Cache{"checkSystemFiles"})
    { # run once
        return;
    }
    $Cache{"checkSystemFiles"} = 1;
    
    my $LibExt = $In::Opt{"Ext"};
    my @SysHeaders = ();
    
    foreach my $DevelPath (@{$In::Opt{"SysPaths"}{"lib"}})
    {
        if(not -d $DevelPath) {
            next;
        }
        
        my @Files = cmdFind($DevelPath,"f");
        foreach my $Link (cmdFind($DevelPath,"l"))
        { # add symbolic links
            if(-f $Link) {
                push(@Files, $Link);
            }
        }
        
        # search for headers in /usr/lib
        my @Headers = grep { /\.h(pp|xx)?\Z|\/include\// } @Files;
        @Headers = grep { not /\/(gcc|jvm|syslinux|kbd|parrot|xemacs|perl|llvm)/ } @Headers;
        push(@SysHeaders, @Headers);
        
        # search for libraries in /usr/lib (including symbolic links)
        my @Libs = grep { /\.$LibExt[0-9.]*\Z/ } @Files;
        foreach my $Path (@Libs)
        {
            my $N = getFilename($Path);
            $In::Opt{"SystemObjects"}{$N}{$Path} = 1;
            $In::Opt{"SystemObjects"}{libPart($N, "name+ext")}{$Path} = 1;
        }
    }
    
    foreach my $DevelPath (@{$In::Opt{"SysPaths"}{"include"}})
    {
        if(not -d $DevelPath) {
            next;
        }
        # search for all header files in the /usr/include
        # with or without extension (ncurses.h, QtCore, ...)
        push(@SysHeaders, cmdFind($DevelPath,"f"));
        foreach my $Link (cmdFind($DevelPath,"l"))
        { # add symbolic links
            if(-f $Link) {
                push(@SysHeaders, $Link);
            }
        }
    }
    getPrefixes_I(\@SysHeaders, \%SystemHeaders);
}

sub libPart($$)
{
    my ($N, $T) = @_;
    if(defined $Cache{"libPart"}{$T}{$N}) {
        return $Cache{"libPart"}{$T}{$N};
    }
    return ($Cache{"libPart"}{$T}{$N} = libPart_I(@_));
}

sub libPart_I($$)
{
    my ($N, $T) = @_;
    
    my $Ext = $In::Opt{"Ext"};
    my $Target = $In::Opt{"Target"};
    
    if($Target eq "symbian")
    {
        if($N=~/(((.+?)(\{.+\}|))\.$Ext)\Z/)
        { # libpthread{00010001}.dso
            if($T eq "name")
            { # libpthread{00010001}
                return $2;
            }
            elsif($T eq "name+ext")
            { # libpthread{00010001}.dso
                return $1;
            }
            elsif($T eq "version")
            { # 00010001
                my $V = $4;
                $V=~s/\{(.+)\}/$1/;
                return $V;
            }
            elsif($T eq "short")
            { # libpthread
                return $3;
            }
            elsif($T eq "shortest")
            { # pthread
                return shortestName($3);
            }
        }
    }
    elsif($Target eq "windows")
    {
        if($N=~/((.+?)\.$Ext)\Z/)
        { # netapi32.dll
            if($T eq "name")
            { # netapi32
                return $2;
            }
            elsif($T eq "name+ext")
            { # netapi32.dll
                return $1;
            }
            elsif($T eq "version")
            { # DLL version embedded
              # at binary-level
                return "";
            }
            elsif($T eq "short")
            { # netapi32
                return $2;
            }
            elsif($T eq "shortest")
            { # netapi
                return shortestName($2);
            }
        }
    }
    else
    { # unix
        if($N=~/((((lib|).+?)([\-\_][\d\-\.\_]+.*?|))\.$Ext)(\.(.+)|)\Z/)
        { # libSDL-1.2.so.0.7.1
          # libwbxml2.so.0.0.18
          # libopcodes-2.21.53-system.20110810.so
            if($T eq "name")
            { # libSDL-1.2
              # libwbxml2
                return $2;
            }
            elsif($T eq "name+ext")
            { # libSDL-1.2.so
              # libwbxml2.so
                return $1;
            }
            elsif($T eq "version")
            {
                if(defined $7
                and $7 ne "")
                { # 0.7.1
                    return $7;
                }
                else
                { # libc-2.5.so (=>2.5 version)
                    my $MV = $5;
                    $MV=~s/\A[\-\_]+//g;
                    return $MV;
                }
            }
            elsif($T eq "short")
            { # libSDL
              # libwbxml2
                return $3;
            }
            elsif($T eq "shortest")
            { # SDL
              # wbxml
                return shortestName($3);
            }
        }
    }
    
    # error
    return "";
}

sub shortestName($)
{
    my $Name = $_[0];
    # remove prefix
    $Name=~s/\A(lib|open)//;
    # remove suffix
    $Name=~s/[\W\d_]+\Z//i;
    $Name=~s/([a-z]{2,})(lib)\Z/$1/i;
    return $Name;
}

sub detectDefaultPaths($$$$)
{
    my ($HSearch, $LSearch, $BSearch, $GSearch) = (@_);
    
    if($Cache{"detectDefaultPaths"}{$HSearch}{$LSearch}{$BSearch}{$GSearch})
    { # enter once
        return;
    }
    $Cache{"detectDefaultPaths"}{$HSearch}{$LSearch}{$BSearch}{$GSearch} = 1;
    
    if(@{$In::Opt{"SysPaths"}{"include"}})
    { # <search_headers> section of the XML descriptor
      # do NOT search for systems headers
        $HSearch = undef;
    }
    if(@{$In::Opt{"SysPaths"}{"lib"}})
    { # <search_libs> section of the XML descriptor
      # do NOT search for systems libraries
        $LSearch = undef;
    }
    
    foreach my $Type (keys(%{$OS_AddPath{$In::Opt{"OS"}}}))
    { # additional search paths
        next if($Type eq "include" and not $HSearch);
        next if($Type eq "lib" and not $LSearch);
        next if($Type eq "bin" and not $BSearch);
        
        push_U($In::Opt{"SysPaths"}{$Type}, grep { -d $_ } @{$OS_AddPath{$In::Opt{"OS"}}{$Type}});
    }
    if($In::Opt{"OS"} ne "windows")
    { # unix-like
        foreach my $Type ("include", "lib", "bin")
        { # automatic detection of system "devel" directories
            next if($Type eq "include" and not $HSearch);
            next if($Type eq "lib" and not $LSearch);
            next if($Type eq "bin" and not $BSearch);
            
            my ($UsrDir, $RootDir) = ("/usr", "/");
            
            if(my $SystemRoot = $In::Opt{"SystemRoot"}
            and $Type ne "bin")
            { # 1. search for target headers and libraries
              # 2. use host commands: ldconfig, readelf, etc.
                ($UsrDir, $RootDir) = ("$SystemRoot/usr", $SystemRoot);
            }
            
            push_U($In::Opt{"SysPaths"}{$Type}, cmdFind($RootDir,"d","*$Type*",1));
            
            if(-d $RootDir."/".$Type)
            { # if "/lib" is symbolic link
                if($RootDir eq "/") {
                    push_U($In::Opt{"SysPaths"}{$Type}, "/".$Type);
                }
                else {
                    push_U($In::Opt{"SysPaths"}{$Type}, $RootDir."/".$Type);
                }
            }
            
            if(-d $UsrDir)
            {
                push_U($In::Opt{"SysPaths"}{$Type}, cmdFind($UsrDir,"d","*$Type*",1));
                if(-d $UsrDir."/".$Type)
                { # if "/usr/lib" is symbolic link
                    push_U($In::Opt{"SysPaths"}{$Type}, $UsrDir."/".$Type);
                }
            }
        }
    }
    if($BSearch)
    {
        detectBinDefaultPaths();
        push_U($In::Opt{"SysPaths"}{"bin"}, @DefaultBinPaths);
    }
    
    # check environment variables
    if($In::Opt{"OS"} eq "beos")
    {
        foreach (my @Paths = @{$In::Opt{"SysPaths"}{"bin"}})
        {
            if($_ eq ".") {
                next;
            }
            # search for /boot/develop/abi/x86/gcc4/tools/gcc-4.4.4-haiku-101111/bin/
            if(my @Dirs = sort cmdFind($_, "d", "bin")) {
                push_U($In::Opt{"SysPaths"}{"bin"}, sort {getDepth($a)<=>getDepth($b)} @Dirs);
            }
        }
        
        if($HSearch)
        {
            push_U(\@DefaultIncPaths, grep { isAbsPath($_) } (
                split(/:|;/, $ENV{"BEINCLUDES"})
                ));
        }
        
        if($LSearch)
        {
            push_U($In::Opt{"DefaultLibPaths"}, grep { isAbsPath($_) } (
                split(/:|;/, $ENV{"BELIBRARIES"}),
                split(/:|;/, $ENV{"LIBRARY_PATH"})
                ));
        }
    }
    if($LSearch)
    { # using linker to get system paths
        if(my $LPaths = detectLibDefaultPaths())
        { # unix-like
            my %Dirs = ();
            foreach my $Name (keys(%{$LPaths}))
            {
                if(my $SystemRoot = $In::Opt{"SystemRoot"})
                {
                    if($LPaths->{$Name}!~/\A\Q$SystemRoot\E\//)
                    { # wrong ldconfig configuration
                      # check your <sysroot>/etc/ld.so.conf
                        next;
                    }
                }
                
                $In::Opt{"LibDefaultPath"}{$Name} = $LPaths->{$Name};
                if(my $Dir = getDirname($LPaths->{$Name})) {
                    $Dirs{$Dir} = 1;
                }
            }
            push_U($In::Opt{"DefaultLibPaths"}, sort {getDepth($a)<=>getDepth($b)} sort keys(%Dirs));
        }
        push_U($In::Opt{"SysPaths"}{"lib"}, @{$In::Opt{"DefaultLibPaths"}});
        
        if(my $EDir = $In::Opt{"ExtraInfo"}) {
            writeFile($EDir."/default-libs", join("\n", @{$In::Opt{"DefaultLibPaths"}}));
        }
    }
    
    if($BSearch)
    {
        if($In::Opt{"CrossPrefix"})
        {
            if(my $GccPath = getGccPath())
            {
                $In::Opt{"GccPath"} = $GccPath;
                if(my $D = getDirname($GccPath)) {
                    $In::Opt{"TargetTools"}{$D}=1;
                }
            }
        }
    }
    
    if($GSearch and my $GccPath = getGccPath())
    { # GCC path and default include dirs
        $In::Opt{"GccPath"} = $GccPath;
        
        my $GccVer = dumpVersion($GccPath);
        
        if($GccVer=~/\A\d+\.\d+\Z/)
        { # on Ubuntu -dumpversion returns 4.8 for gcc 4.8.4
            my $Info = `$GccPath --version`;
            
            if($Info=~/gcc\s+(|\([^()]+\)\s+)(\d+\.\d+\.\d+)/)
            { # gcc (Ubuntu 4.8.4-2ubuntu1~14.04) 4.8.4
              # gcc (GCC) 4.9.2 20150212 (Red Hat 4.9.2-6)
                $GccVer = $2;
            }
        }
        
        if($In::Opt{"OS"}=~/macos/)
        {
            my $Info = `$GccPath --version`;
            
            if($Info=~/clang/i) {
                printMsg("WARNING", "doesn't work with clang, please install GCC instead (and select it by -gcc-path option)");
            }
        }
        
        if($GccVer)
        {
            my $Target = dumpMachine($GccPath);
            
            if($Target=~/linux/) {
                setTarget("linux");
            }
            elsif($Target=~/symbian/) {
                setTarget("symbian");
            }
            elsif($Target=~/solaris/) {
                setTarget("solaris");
            }
            
            $In::Opt{"GccTarget"} = $Target;
            $In::Opt{"GccVer"} = $GccVer;
            
            printMsg("INFO", "Using GCC $GccVer ($Target, target: ".getArch_GCC(1).")");
            
            # check GCC version
            if($GccVer=~/\A(4\.8(|\.[012])|[67](\..*)?)\Z/ or cmpVersions($GccVer, "8")>=0)
            { # GCC 4.8.[0-2]: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=57850
              # GCC 6.[1-2].0: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=78040
              # GCC 7.1: still the same issue ...
              # GCC 8: still the same issue ...
              # ABICC 2.3: enable this for all future GCC versions
                printMsg("WARNING", "May not work properly with GCC 4.8.[0-2], 6.* and higher due to bug #78040 in GCC. Please try other GCC versions with the help of --gcc-path=PATH option or create ABI dumps by ABI Dumper tool instead to avoid using GCC. Test selected GCC version first by -test and -gcc-path options.");
                $In::Opt{"GccMissedMangling"} = 1;
            }
        }
        else {
            exitStatus("Error", "something is going wrong with the GCC compiler");
        }
    }
    
    if($HSearch)
    {
        # GCC standard paths
        if($In::Opt{"GccPath"}
        and not $In::Opt{"NoStdInc"})
        {
            my %DPaths = detectIncDefaultPaths();
            @DefaultCppPaths = @{$DPaths{"Cpp"}};
            @DefaultGccPaths = @{$DPaths{"Gcc"}};
            @DefaultIncPaths = @{$DPaths{"Inc"}};
            push_U($In::Opt{"SysPaths"}{"include"}, @DefaultIncPaths);
        }
        
        # users include paths
        my $IncPath = "/usr/include";
        if(my $SystemRoot = $In::Opt{"SystemRoot"}) {
            $IncPath = $SystemRoot.$IncPath;
        }
        if(-d $IncPath) {
            push_U(\@UsersIncPath, $IncPath);
        }
        
        if(my $EDir = $In::Opt{"ExtraInfo"}) {
            writeFile($EDir."/default-includes", join("\n", (@DefaultCppPaths, @DefaultGccPaths, @DefaultIncPaths)));
        }
    }
    
    
}

sub detectLibDefaultPaths()
{
    my %LPaths = ();
    
    my $TmpDir = $In::Opt{"Tmp"};
    
    if($In::Opt{"OS"} eq "bsd")
    {
        if(my $LdConfig = getCmdPath("ldconfig"))
        {
            foreach my $Line (split(/\n/, `$LdConfig -r 2>\"$TmpDir/null\"`))
            {
                if($Line=~/\A[ \t]*\d+:\-l(.+) \=\> (.+)\Z/)
                {
                    my $Name = "lib".$1;
                    if(not defined $LPaths{$Name}) {
                        $LPaths{$Name} = $2;
                    }
                }
            }
        }
        else {
            printMsg("WARNING", "can't find ldconfig");
        }
    }
    else
    {
        if(my $LdConfig = getCmdPath("ldconfig"))
        {
            if(my $SystemRoot = $In::Opt{"SystemRoot"}
            and $In::Opt{"OS"} eq "linux")
            { # use host (x86) ldconfig with the target (arm) ld.so.conf
                if(-e $SystemRoot."/etc/ld.so.conf") {
                    $LdConfig .= " -f ".$SystemRoot."/etc/ld.so.conf";
                }
            }
            foreach my $Line (split(/\n/, `$LdConfig -p 2>\"$TmpDir/null\"`))
            {
                if($Line=~/\A[ \t]*([^ \t]+) .* \=\> (.+)\Z/)
                {
                    my ($Name, $Path) = ($1, $2);
                    $Path=~s/[\/]{2,}/\//;
                    if(not defined $LPaths{$Name})
                    { # get first element from the list of available paths
                      
                      # libstdc++.so.6 (libc6,x86-64) => /usr/lib/x86_64-linux-gnu/libstdc++.so.6
                      # libstdc++.so.6 (libc6) => /usr/lib/i386-linux-gnu/libstdc++.so.6
                      # libstdc++.so.6 (libc6) => /usr/lib32/libstdc++.so.6
                      
                        $LPaths{$Name} = $Path;
                    }
                }
            }
        }
        elsif($In::Opt{"OS"} eq "linux") {
            printMsg("WARNING", "can't find ldconfig");
        }
    }
    return \%LPaths;
}

sub detectBinDefaultPaths()
{
    my $EnvPaths = $ENV{"PATH"};
    if($In::Opt{"OS"} eq "beos") {
        $EnvPaths.=":".$ENV{"BETOOLS"};
    }
    my $Sep = ":|;";
    if($In::Opt{"OS"} eq "windows") {
        $Sep = ";";
    }
    
    foreach my $Path (split(/$Sep/, $EnvPaths))
    {
        $Path = pathFmt($Path);
        if(not $Path) {
            next;
        }
        if(my $SystemRoot = $In::Opt{"SystemRoot"})
        {
            if($Path=~/\A\Q$SystemRoot\E\//)
            { # do NOT use binaries from target system
                next;
            }
        }
        push_U(\@DefaultBinPaths, $Path);
    }
}

sub detectIncDefaultPaths()
{
    my $GccPath = $In::Opt{"GccPath"};
    my %DPaths = ("Cpp"=>[],"Gcc"=>[],"Inc"=>[]);
    
    my $TmpDir = $In::Opt{"Tmp"};
    writeFile("$TmpDir/empty.h", "");
    
    foreach my $Line (split(/\n/, `$GccPath -v -x c++ -E \"$TmpDir/empty.h\" 2>&1`))
    { # detecting GCC default include paths
        if(index($Line, "/cc1plus ")!=-1) {
            next;
        }
        
        if($Line=~/\A[ \t]*((\/|\w+:\\).+)[ \t]*\Z/)
        {
            my $Path = realpath_F($1);
            if(index($Path, "c++")!=-1
            or index($Path, "/g++/")!=-1)
            {
                push_U($DPaths{"Cpp"}, $Path);
                if(not defined $In::Opt{"MainCppDir"}
                or getDepth($In::Opt{"MainCppDir"})>getDepth($Path)) {
                    $In::Opt{"MainCppDir"} = $Path;
                }
            }
            elsif(index($Path, "gcc")!=-1) {
                push_U($DPaths{"Gcc"}, $Path);
            }
            else
            {
                if($Path=~/local[\/\\]+include/)
                { # local paths
                    next;
                }
                if(my $SystemRoot = $In::Opt{"SystemRoot"})
                {
                    if($Path!~/\A\Q$SystemRoot\E(\/|\Z)/)
                    { # The GCC include path for user headers is not a part of the system root
                      # The reason: you are not specified the --cross-gcc option or selected a wrong compiler
                      # or it is the internal cross-GCC path like arm-linux-gnueabi/include
                        next;
                    }
                }
                push_U($DPaths{"Inc"}, $Path);
            }
        }
    }
    unlink("$TmpDir/empty.h");
    return %DPaths;
}

sub registerGccHeaders()
{
    if($Cache{"registerGccHeaders"})
    { # this function should be called once
        return;
    }
    
    foreach my $Path (@DefaultGccPaths)
    {
        my @Headers = cmdFind($Path,"f");
        @Headers = sort {getDepth($a)<=>getDepth($b)} @Headers;
        foreach my $HPath (@Headers)
        {
            my $FileName = getFilename($HPath);
            if(not defined $DefaultGccHeader{$FileName})
            { # skip duplicated
                $DefaultGccHeader{$FileName} = $HPath;
            }
        }
    }
    $Cache{"registerGccHeaders"} = 1;
}

sub registerCppHeaders()
{
    if($Cache{"registerCppHeaders"})
    { # this function should be called once
        return;
    }
    
    foreach my $CppDir (@DefaultCppPaths)
    {
        my @Headers = cmdFind($CppDir,"f");
        @Headers = sort {getDepth($a)<=>getDepth($b)} @Headers;
        foreach my $Path (@Headers)
        {
            my $FileName = getFilename($Path);
            if(not defined $DefaultCppHeader{$FileName})
            { # skip duplicated
                $DefaultCppHeader{$FileName} = $Path;
            }
        }
    }
    $Cache{"registerCppHeaders"} = 1;
}

sub parseRedirect($$$)
{
    my ($Content, $Path, $LVer) = @_;
    my @Errors = ();
    while($Content=~s/#\s*error\s+([^\n]+?)\s*(\n|\Z)//) {
        push(@Errors, $1);
    }
    my $Redirect = "";
    foreach (@Errors)
    {
        s/\s{2,}/ /g;
        if(/(only|must\ include
        |update\ to\ include
        |replaced\ with
        |replaced\ by|renamed\ to
        |\ is\ in|\ use)\ (<[^<>]+>|[\w\-\/\\]+\.($HEADER_EXT))/ix)
        {
            $Redirect = $2;
            last;
        }
        elsif(/(include|use|is\ in)\ (<[^<>]+>|[\w\-\/\\]+\.($HEADER_EXT))\ instead/i)
        {
            $Redirect = $2;
            last;
        }
        elsif(/this\ header\ should\ not\ be\ used
         |programs\ should\ not\ directly\ include
         |you\ should\ not\ (include|be\ (including|using)\ this\ (file|header))
         |is\ not\ supported\ API\ for\ general\ use
         |do\ not\ use
         |should\ not\ be\ (used|using)
         |cannot\ be\ included\ directly/ix and not /\ from\ /i) {
            $Header_ShouldNotBeUsed{$LVer}{$Path} = 1;
        }
    }
    if($Redirect)
    {
        $Redirect=~s/\A<//g;
        $Redirect=~s/>\Z//g;
    }
    return $Redirect;
}

sub parseIncludes($$)
{
    my ($Content, $Path) = @_;
    my %Includes = ();
    while($Content=~s/^[ \t]*#[ \t]*(include|include_next|import)[ \t]*([<"].+?[">])[ \t]*//m)
    { # C/C++: include, Objective C/C++: import directive
        my $Header = $2;
        my $Method = substr($Header, 0, 1, "");
        substr($Header, length($Header)-1, 1, "");
        $Header = pathFmt($Header);
        if($Method eq "\"" or isAbsPath($Header))
        {
            if(-e join_P(getDirname($Path), $Header))
            { # relative path exists
                $Includes{$Header} = -1;
            }
            else
            { # include "..." that doesn't exist is equal to include <...>
                $Includes{$Header} = 2;
            }
        }
        else {
            $Includes{$Header} = 1;
        }
    }
    if($In::Opt{"ExtraInfo"})
    {
        while($Content=~s/^[ \t]*#[ \t]*(include|include_next|import)[ \t]+(\w+)[ \t]*//m)
        { # FT_FREETYPE_H
            $Includes{$2} = 0;
        }
    }
    return \%Includes;
}

sub sortHeaders($$)
{
    my ($H1, $H2) = @_;
    
    $H1=~s/\.[a-z]+\Z//ig;
    $H2=~s/\.[a-z]+\Z//ig;
    
    my $Hname1 = getFilename($H1);
    my $Hname2 = getFilename($H2);
    my $HDir1 = getDirname($H1);
    my $HDir2 = getDirname($H2);
    my $Dirname1 = getFilename($HDir1);
    my $Dirname2 = getFilename($HDir2);
    
    $HDir1=~s/\A.*[\/\\]+([^\/\\]+[\/\\]+[^\/\\]+)\Z/$1/;
    $HDir2=~s/\A.*[\/\\]+([^\/\\]+[\/\\]+[^\/\\]+)\Z/$1/;
    
    if($_[0] eq $_[1]
    or $H1 eq $H2) {
        return 0;
    }
    elsif($H1=~/\A\Q$H2\E/) {
        return 1;
    }
    elsif($H2=~/\A\Q$H1\E/) {
        return -1;
    }
    elsif($HDir1=~/\Q$Hname1\E/i
    and $HDir2!~/\Q$Hname2\E/i)
    { # include/glib-2.0/glib.h
        return -1;
    }
    elsif($HDir2=~/\Q$Hname2\E/i
    and $HDir1!~/\Q$Hname1\E/i)
    { # include/glib-2.0/glib.h
        return 1;
    }
    elsif($Hname1=~/\Q$Dirname1\E/i
    and $Hname2!~/\Q$Dirname2\E/i)
    { # include/hildon-thumbnail/hildon-thumbnail-factory.h
        return -1;
    }
    elsif($Hname2=~/\Q$Dirname2\E/i
    and $Hname1!~/\Q$Dirname1\E/i)
    { # include/hildon-thumbnail/hildon-thumbnail-factory.h
        return 1;
    }
    elsif($Hname1=~/(config|lib|util)/i
    and $Hname2!~/(config|lib|util)/i)
    { # include/alsa/asoundlib.h
        return -1;
    }
    elsif($Hname2=~/(config|lib|util)/i
    and $Hname1!~/(config|lib|util)/i)
    { # include/alsa/asoundlib.h
        return 1;
    }
    else
    {
        my $R1 = checkRelevance($H1);
        my $R2 = checkRelevance($H2);
        if($R1 and not $R2)
        { # libebook/e-book.h
            return -1;
        }
        elsif($R2 and not $R1)
        { # libebook/e-book.h
            return 1;
        }
        else
        {
            return (lc($H1) cmp lc($H2));
        }
    }
}

sub detectRealIncludes($$)
{
    my ($AbsPath, $LVer) = @_;
    
    if($Cache{"detectRealIncludes"}{$LVer}{$AbsPath}
    or keys(%{$RecursiveIncludes{$LVer}{$AbsPath}})) {
        return keys(%{$RecursiveIncludes{$LVer}{$AbsPath}});
    }
    $Cache{"detectRealIncludes"}{$LVer}{$AbsPath}=1;
    
    my $Path = callPreprocessor($AbsPath, "", $LVer);
    if(not $Path) {
        return ();
    }
    open(PREPROC, $Path);
    while(<PREPROC>)
    {
        if(/#\s+\d+\s+"([^"]+)"[\s\d]*\n/)
        {
            my $Include = pathFmt($1);
            if($Include=~/\<(built\-in|internal|command(\-|\s)line)\>|\A\./) {
                next;
            }
            if($Include eq $AbsPath) {
                next;
            }
            $RecursiveIncludes{$LVer}{$AbsPath}{$Include} = 1;
        }
    }
    close(PREPROC);
    return keys(%{$RecursiveIncludes{$LVer}{$AbsPath}});
}

sub detectHeaderIncludes($$)
{
    my ($Path, $LVer) = @_;
    
    if(defined $Cache{"detectHeaderIncludes"}{$LVer}{$Path}) {
        return;
    }
    $Cache{"detectHeaderIncludes"}{$LVer}{$Path}=1;
    
    if(not -e $Path) {
        return;
    }
    
    my $Content = readFile($Path);
    if(my $Redirect = parseRedirect($Content, $Path, $LVer))
    { # detect error directive in headers
        if(my $RedirectPath = identifyHeader($Redirect, $LVer))
        {
            if($RedirectPath=~/\/usr\/include\// and $Path!~/\/usr\/include\//) {
                $RedirectPath = identifyHeader(getFilename($Redirect), $LVer);
            }
            if($RedirectPath ne $Path) {
                $Header_ErrorRedirect{$LVer}{$Path} = $RedirectPath;
            }
        }
        else
        { # can't find
            $Header_ShouldNotBeUsed{$LVer}{$Path} = 1;
        }
    }
    if(my $Inc = parseIncludes($Content, $Path))
    {
        foreach my $Include (keys(%{$Inc}))
        { # detect includes
            $Header_Includes{$LVer}{$Path}{$Include} = $Inc->{$Include};
            
            if(defined $In::Opt{"Tolerance"}
            and $In::Opt{"Tolerance"}=~/4/)
            {
                if(my $HPath = identifyHeader($Include, $LVer))
                {
                    $Header_Includes_R{$LVer}{$HPath}{$Path} = 1;
                }
            }
        }
    }
}

sub fromLibc($)
{ # system GLIBC header
    my $Path = $_[0];
    my ($Dir, $Name) = sepPath($Path);
    if($In::Opt{"Target"} eq "symbian")
    {
        if(getFilename($Dir) eq "libc" and $GlibcHeader{$Name})
        { # epoc32/include/libc/{stdio, ...}.h
            return 1;
        }
    }
    else
    {
        if($Dir eq "/usr/include" and $GlibcHeader{$Name})
        { # /usr/include/{stdio, ...}.h
            return 1;
        }
    }
    return 0;
}

sub isLibcDir($)
{ # system GLIBC directory
    my $Dir = $_[0];
    my ($OutDir, $Name) = sepPath($Dir);
    if($In::Opt{"Target"} eq "symbian")
    {
        if(getFilename($OutDir) eq "libc"
        and ($Name=~/\Aasm(|-.+)\Z/ or $GlibcDir{$Name}))
        { # epoc32/include/libc/{sys,bits,asm,asm-*}/*.h
            return 1;
        }
    }
    else
    { # linux
        if($OutDir eq "/usr/include"
        and ($Name=~/\Aasm(|-.+)\Z/ or $GlibcDir{$Name}))
        { # /usr/include/{sys,bits,asm,asm-*}/*.h
            return 1;
        }
    }
    return 0;
}

sub detectRecursiveIncludes($$)
{
    my ($AbsPath, $LVer) = @_;
    if(not $AbsPath) {
        return ();
    }
    if(isCyclical(\@RecurInclude, $AbsPath)) {
        return keys(%{$RecursiveIncludes{$LVer}{$AbsPath}});
    }
    my ($AbsDir, $Name) = sepPath($AbsPath);
    if(isLibcDir($AbsDir))
    { # system GLIBC internals
        if(not $In::Opt{"ExtraInfo"}) {
            return ();
        }
    }
    if(keys(%{$RecursiveIncludes{$LVer}{$AbsPath}})) {
        return keys(%{$RecursiveIncludes{$LVer}{$AbsPath}});
    }
    if($In::Opt{"OS"} ne "windows"
    and $Name=~/windows|win32|win64/i) {
        return ();
    }
    
    if($In::Opt{"MainCppDir"} and $AbsPath=~/\A\Q$In::Opt{"MainCppDir"}\E/ and not $In::Opt{"StdcxxTesting"})
    { # skip /usr/include/c++/*/ headers
        if(not $In::Opt{"ExtraInfo"}) {
            return ();
        }
    }
    
    push(@RecurInclude, $AbsPath);
    if(grep { $AbsDir eq $_ } @DefaultGccPaths
    or (grep { $AbsDir eq $_ } @DefaultIncPaths and fromLibc($AbsPath)))
    { # check "real" (non-"model") include paths
        my @Paths = detectRealIncludes($AbsPath, $LVer);
        pop(@RecurInclude);
        return @Paths;
    }
    if(not keys(%{$Header_Includes{$LVer}{$AbsPath}})) {
        detectHeaderIncludes($AbsPath, $LVer);
    }
    foreach my $Include (keys(%{$Header_Includes{$LVer}{$AbsPath}}))
    {
        my $IncType = $Header_Includes{$LVer}{$AbsPath}{$Include};
        my $HPath = "";
        if($IncType<0)
        { # for #include "..."
            my $Candidate = join_P($AbsDir, $Include);
            if(-f $Candidate) {
                $HPath = realpath_F($Candidate);
            }
        }
        elsif($IncType>0
        and $Include=~/[\/\\]/) # and not findInDefaults($Include)
        { # search for the nearest header
          # QtCore/qabstractanimation.h includes <QtCore/qobject.h>
            my $Candidate = join_P(getDirname($AbsDir), $Include);
            if(-f $Candidate) {
                $HPath = $Candidate;
            }
        }
        if(not $HPath) {
            $HPath = identifyHeader($Include, $LVer);
        }
        next if(not $HPath);
        if($HPath eq $AbsPath) {
            next;
        }
        
        #if($In::Opt{"Debug"})
        #{ # boundary headers
        #    if($HPath=~/vtk/ and $AbsPath!~/vtk/)
        #    {
        #        print STDERR "$AbsPath -> $HPath\n";
        #    }
        #}
        
        $RecursiveIncludes{$LVer}{$AbsPath}{$HPath} = $IncType;
        if($IncType>0)
        { # only include <...>, skip include "..." prefixes
            $Header_Include_Prefix{$LVer}{$AbsPath}{$HPath}{getDirname($Include)} = 1;
        }
        foreach my $IncPath (detectRecursiveIncludes($HPath, $LVer))
        {
            if($IncPath eq $AbsPath) {
                next;
            }
            my $RIncType = $RecursiveIncludes{$LVer}{$HPath}{$IncPath};
            if($RIncType==-1)
            { # include "..."
                $RIncType = $IncType;
            }
            elsif($RIncType==2)
            {
                if($IncType!=-1) {
                    $RIncType = $IncType;
                }
            }
            $RecursiveIncludes{$LVer}{$AbsPath}{$IncPath} = $RIncType;
            foreach my $Prefix (keys(%{$Header_Include_Prefix{$LVer}{$HPath}{$IncPath}})) {
                $Header_Include_Prefix{$LVer}{$AbsPath}{$IncPath}{$Prefix} = 1;
            }
        }
        foreach my $Dep (keys(%{$Header_Include_Prefix{$LVer}{$AbsPath}}))
        {
            if($GlibcHeader{getFilename($Dep)} and keys(%{$Header_Include_Prefix{$LVer}{$AbsPath}{$Dep}})>=2
            and defined $Header_Include_Prefix{$LVer}{$AbsPath}{$Dep}{""})
            { # distinguish math.h from glibc and math.h from the tested library
                delete($Header_Include_Prefix{$LVer}{$AbsPath}{$Dep}{""});
                last;
            }
        }
    }
    pop(@RecurInclude);
    return keys(%{$RecursiveIncludes{$LVer}{$AbsPath}});
}

sub findInFramework($$$)
{
    my ($Header, $Framework, $LVer) = @_;
    
    if(defined $Cache{"findInFramework"}{$LVer}{$Framework}{$Header}) {
        return $Cache{"findInFramework"}{$LVer}{$Framework}{$Header};
    }
    foreach my $Dependency (sort {getDepth($a)<=>getDepth($b)} keys(%{$Header_Dependency{$LVer}}))
    {
        if(getFilename($Dependency) eq $Framework
        and -f getDirname($Dependency)."/".$Header) {
            return ($Cache{"findInFramework"}{$LVer}{$Framework}{$Header} = getDirname($Dependency));
        }
    }
    return ($Cache{"findInFramework"}{$LVer}{$Framework}{$Header} = "");
}

sub findInDefaults($)
{
    my $Header = $_[0];
    
    if(defined $Cache{"findInDefaults"}{$Header}) {
        return $Cache{"findInDefaults"}{$Header};
    }
    foreach my $Dir (@DefaultIncPaths,
                     @DefaultGccPaths,
                     @DefaultCppPaths,
                     @UsersIncPath)
    {
        if(not $Dir) {
            next;
        }
        if(-f $Dir."/".$Header) {
            return ($Cache{"findInDefaults"}{$Header}=$Dir);
        }
    }
    return ($Cache{"findInDefaults"}{$Header} = "");
}

sub cmp_paths($$)
{
    my ($Path1, $Path2) = @_;
    my @Parts1 = split(/[\/\\]/, $Path1);
    my @Parts2 = split(/[\/\\]/, $Path2);
    foreach my $Num (0 .. $#Parts1)
    {
        my $Part1 = $Parts1[$Num];
        my $Part2 = $Parts2[$Num];
        if($GlibcDir{$Part1}
        and not $GlibcDir{$Part2}) {
            return 1;
        }
        elsif($GlibcDir{$Part2}
        and not $GlibcDir{$Part1}) {
            return -1;
        }
        elsif($Part1=~/glib/
        and $Part2!~/glib/) {
            return 1;
        }
        elsif($Part1!~/glib/
        and $Part2=~/glib/) {
            return -1;
        }
        elsif(my $CmpRes = ($Part1 cmp $Part2)) {
            return $CmpRes;
        }
    }
    return 0;
}

sub checkRelevance($)
{
    my $Path = $_[0];
    
    if(my $SystemRoot = $In::Opt{"SystemRoot"}) {
        $Path = cutPrefix($Path, $SystemRoot);
    }
    
    my $Name = lc(getFilename($Path));
    my $Dir = lc(getDirname($Path));
    
    $Name=~s/\.\w+\Z//g; # remove extension (.h)
    
    foreach my $Token (split(/[_\d\W]+/, $Name))
    {
        my $Len = length($Token);
        next if($Len<=1);
        if($Dir=~/(\A|lib|[_\d\W])\Q$Token\E([_\d\W]|lib|\Z)/)
        { # include/evolution-data-server-1.4/libebook/e-book.h
            return 1;
        }
        if($Len>=4 and index($Dir, $Token)!=-1)
        { # include/gupnp-1.0/libgupnp/gupnp-context.h
            return 1;
        }
    }
    return 0;
}

sub checkFamily(@)
{
    my @Paths = @_;
    if($#Paths<=0) {
        return 1;
    }
    my %Prefix = ();
    foreach my $Path (@Paths)
    {
        if(my $SystemRoot = $In::Opt{"SystemRoot"}) {
            $Path = cutPrefix($Path, $SystemRoot);
        }
        if(my $Dir = getDirname($Path))
        {
            $Dir=~s/(\/[^\/]+?)[\d\.\-\_]+\Z/$1/g; # remove version suffix
            $Prefix{$Dir} += 1;
            $Prefix{getDirname($Dir)} += 1;
        }
    }
    foreach (sort keys(%Prefix))
    {
        if(getDepth($_)>=3
        and $Prefix{$_}==$#Paths+1) {
            return 1;
        }
    }
    return 0;
}

sub isAcceptable($$$)
{
    my ($Header, $Candidate, $LVer) = @_;
    my $HName = getFilename($Header);
    if(getDirname($Header))
    { # with prefix
        return 1;
    }
    if($HName=~/config|setup/i and $Candidate=~/[\/\\]lib\d*[\/\\]/)
    { # allow to search for glibconfig.h in /usr/lib/glib-2.0/include/
        return 1;
    }
    if(checkRelevance($Candidate))
    { # allow to search for atk.h in /usr/include/atk-1.0/atk/
        return 1;
    }
    if(checkFamily(getSystemHeaders($HName, $LVer)))
    { # /usr/include/qt4/QtNetwork/qsslconfiguration.h
      # /usr/include/qt4/Qt/qsslconfiguration.h
        return 1;
    }
    if($In::Opt{"Target"} eq "symbian")
    {
        if($Candidate=~/[\/\\]stdapis[\/\\]/) {
            return 1;
        }
    }
    return 0;
}

sub isRelevant($$$)
{ # disallow to search for "abstract" headers in too deep directories
    my ($Header, $Candidate, $LVer) = @_;
    my $HName = getFilename($Header);
    if($In::Opt{"Target"} eq "symbian")
    {
        if($Candidate=~/[\/\\](tools|stlportv5)[\/\\]/) {
            return 0;
        }
    }
    if($In::Opt{"Target"} ne "bsd")
    {
        if($Candidate=~/[\/\\]include[\/\\]bsd[\/\\]/)
        { # openssh: skip /usr/lib/bcc/include/bsd/signal.h
            return 0;
        }
    }
    if($In::Opt{"Target"} ne "windows")
    {
        if($Candidate=~/[\/\\](wine|msvcrt|windows)[\/\\]/)
        { # skip /usr/include/wine/msvcrt
            return 0;
        }
    }
    if(not getDirname($Header)
    and $Candidate=~/[\/\\]wx[\/\\]/)
    { # do NOT search in system /wx/ directory
      # for headers without a prefix: sstream.h
        return 0;
    }
    if($Candidate=~/c\+\+[\/\\]\d+/ and $In::Opt{"MainCppDir"}
    and $Candidate!~/\A\Q$In::Opt{"MainCppDir"}\E/)
    { # skip ../c++/3.3.3/ if using ../c++/4.5/
        return 0;
    }
    if($Candidate=~/[\/\\]asm-/
    and (my $Arch = getArch_GCC($LVer)) ne "unknown")
    { # arch-specific header files
        if($Candidate!~/[\/\\]asm-\Q$Arch\E/)
        {# skip ../asm-arm/ if using x86 architecture
            return 0;
        }
    }
    my @Candidates = getSystemHeaders($HName, $LVer);
    if($#Candidates==1)
    { # unique header
        return 1;
    }
    my @SCandidates = getSystemHeaders($Header, $LVer);
    if($#SCandidates==1)
    { # unique name
        return 1;
    }
    my $SystemDepth = 0;
    
    if(my $SystemRoot = $In::Opt{"SystemRoot"}) {
        $SystemDepth = getDepth($SystemRoot);
    }
    
    if(getDepth($Candidate)-$SystemDepth>=5)
    { # abstract headers in too deep directories
      # sstream.h or typeinfo.h in /usr/include/wx-2.9/wx/
        if(not isAcceptable($Header, $Candidate, $LVer)) {
            return 0;
        }
    }
    if($Header eq "parser.h"
    and $Candidate!~/\/libxml2\//)
    { # select parser.h from xml2 library
        return 0;
    }
    if(not getDirname($Header)
    and keys(%{$SystemHeaders{$HName}})>=3)
    { # many headers with the same name
      # like thread.h included without a prefix
        if(not checkFamily(@Candidates)) {
            return 0;
        }
    }
    return 1;
}

sub selectSystemHeader($$)
{ # cache function
    if(defined $Cache{"selectSystemHeader"}{$_[1]}{$_[0]}) {
        return $Cache{"selectSystemHeader"}{$_[1]}{$_[0]};
    }
    return ($Cache{"selectSystemHeader"}{$_[1]}{$_[0]} = selectSystemHeader_I(@_));
}

sub selectSystemHeader_I($$)
{
    my ($Header, $LVer) = @_;
    if(-f $Header) {
        return $Header;
    }
    if(isAbsPath($Header) and not -f $Header)
    { # incorrect absolute path
        return "";
    }
    if(defined $ConfHeaders{lc($Header)})
    { # too abstract configuration headers
        return "";
    }
    my $HName = getFilename($Header);
    if($In::Opt{"OS"} ne "windows")
    {
        if(defined $WinHeaders{lc($HName)}
        or $HName=~/windows|win32|win64/i)
        { # windows headers
            return "";
        }
    }
    if($In::Opt{"OS"} ne "macos")
    {
        if($HName eq "fp.h")
        { # pngconf.h includes fp.h in Mac OS
            return "";
        }
    }
    
    if(defined $ObsoleteHeaders{$HName})
    { # obsolete headers
        return "";
    }
    if($In::Opt{"OS"} eq "linux"
    or $In::Opt{"OS"} eq "bsd")
    {
        if(defined $AlienHeaders{$HName}
        or defined $AlienHeaders{$Header})
        { # alien headers from other systems
            return "";
        }
    }
    
    foreach my $Path (@{$In::Opt{"SysPaths"}{"include"}})
    { # search in default paths
        if(-f $Path."/".$Header) {
            return join_P($Path,$Header);
        }
    }
    
    # register all headers in system include dirs
    checkSystemFiles();
    
    foreach my $Candidate (sort {getDepth($a)<=>getDepth($b)}
    sort {cmp_paths($b, $a)} getSystemHeaders($Header, $LVer))
    {
        if(isRelevant($Header, $Candidate, $LVer)) {
            return $Candidate;
        }
    }
    # error
    return "";
}

sub getSystemHeaders($$)
{
    my ($Header, $LVer) = @_;
    my @Candidates = ();
    foreach my $Candidate (sort keys(%{$SystemHeaders{$Header}}))
    {
        if(skipHeader($Candidate, $LVer)) {
            next;
        }
        push(@Candidates, $Candidate);
    }
    return @Candidates;
}

sub isDefaultIncludeDir($)
{
    my $Dir = $_[0];
    $Dir=~s/[\/\\]+\Z//;
    return grep { $Dir eq $_ } (@DefaultGccPaths, @DefaultCppPaths, @DefaultIncPaths);
}

sub identifyHeader($$)
{ # cache function
    my ($Header, $LVer) = @_;
    if(not $Header) {
        return "";
    }
    $Header=~s/\A(\.\.[\\\/])+//g;
    if(defined $Cache{"identifyHeader"}{$LVer}{$Header}) {
        return $Cache{"identifyHeader"}{$LVer}{$Header};
    }
    return ($Cache{"identifyHeader"}{$LVer}{$Header} = identifyHeader_I($Header, $LVer));
}

sub identifyHeader_I($$)
{ # search for header by absolute path, relative path or name
    my ($Header, $LVer) = @_;
    if(-f $Header)
    { # it's relative or absolute path
        return getAbsPath($Header);
    }
    elsif($GlibcHeader{$Header} and not $In::Opt{"GlibcTesting"}
    and my $HeaderDir = findInDefaults($Header))
    { # search for libc headers in the /usr/include
      # for non-libc target library before searching
      # in the library paths
        return join_P($HeaderDir,$Header);
    }
    elsif(my $Path = $In::Desc{$LVer}{"IncludeNeighbors"}{$Header})
    { # search in the target library paths
        return $Path;
    }
    elsif(defined $DefaultGccHeader{$Header})
    { # search in the internal GCC include paths
        return $DefaultGccHeader{$Header};
    }
    elsif(my $DefaultDir = findInDefaults($Header))
    { # search in the default GCC include paths
        return join_P($DefaultDir,$Header);
    }
    elsif(defined $DefaultCppHeader{$Header})
    { # search in the default G++ include paths
        return $DefaultCppHeader{$Header};
    }
    elsif(my $AnyPath = selectSystemHeader($Header, $LVer))
    { # search everywhere in the system
        return $AnyPath;
    }
    elsif($In::Opt{"OS"} eq "macos")
    { # search in frameworks: "OpenGL/gl.h" is "OpenGL.framework/Headers/gl.h"
        if(my $Dir = getDirname($Header))
        {
            my $RelPath = "Headers\/".getFilename($Header);
            if(my $HeaderDir = findInFramework($RelPath, $Dir.".framework", $LVer)) {
                return join_P($HeaderDir, $RelPath);
            }
        }
    }
    # cannot find anything
    return "";
}

sub cmdFile($)
{
    my $Path = $_[0];
    
    if(my $CmdPath = getCmdPath("file")) {
        return `$CmdPath -b \"$Path\"`;
    }
    return "";
}

sub getHeaderDeps($$)
{
    my ($AbsPath, $LVer) = @_;
    
    if(defined $Cache{"getHeaderDeps"}{$LVer}{$AbsPath}) {
        return @{$Cache{"getHeaderDeps"}{$LVer}{$AbsPath}};
    }
    my %IncDir = ();
    detectRecursiveIncludes($AbsPath, $LVer);
    foreach my $HeaderPath (keys(%{$RecursiveIncludes{$LVer}{$AbsPath}}))
    {
        if(not $HeaderPath) {
            next;
        }
        if($In::Opt{"MainCppDir"} and $HeaderPath=~/\A\Q$In::Opt{"MainCppDir"}\E([\/\\]|\Z)/) {
            next;
        }
        my $Dir = getDirname($HeaderPath);
        foreach my $Prefix (keys(%{$Header_Include_Prefix{$LVer}{$AbsPath}{$HeaderPath}}))
        {
            my $Dep = $Dir;
            if($Prefix)
            {
                if($In::Opt{"OS"} eq "windows")
                { # case insensitive seach on windows
                    if(not $Dep=~s/[\/\\]+\Q$Prefix\E\Z//ig) {
                        next;
                    }
                }
                elsif($In::Opt{"OS"} eq "macos")
                { # seach in frameworks
                    if(not $Dep=~s/[\/\\]+\Q$Prefix\E\Z//g)
                    {
                        if($HeaderPath=~/(.+\.framework)\/Headers\/([^\/]+)/)
                        {# frameworks
                            my ($HFramework, $HName) = ($1, $2);
                            $Dep = $HFramework;
                        }
                        else
                        {# mismatch
                            next;
                        }
                    }
                }
                elsif(not $Dep=~s/[\/\\]+\Q$Prefix\E\Z//g)
                { # Linux, FreeBSD
                    next;
                }
            }
            if(not $Dep)
            { # nothing to include
                next;
            }
            if(isDefaultIncludeDir($Dep))
            { # included by the compiler
                next;
            }
            if(getDepth($Dep)==1)
            { # too short
                next;
            }
            if(isLibcDir($Dep))
            { # do NOT include /usr/include/{sys,bits}
                next;
            }
            $IncDir{$Dep} = 1;
        }
    }
    $Cache{"getHeaderDeps"}{$LVer}{$AbsPath} = sortIncPaths([keys(%IncDir)], $LVer);
    return @{$Cache{"getHeaderDeps"}{$LVer}{$AbsPath}};
}

sub sortIncPaths($$)
{
    my ($ArrRef, $LVer) = @_;
    if(not $ArrRef or $#{$ArrRef}<0) {
        return $ArrRef;
    }
    @{$ArrRef} = sort {$b cmp $a} @{$ArrRef};
    @{$ArrRef} = sort {getDepth($a)<=>getDepth($b)} @{$ArrRef};
    @{$ArrRef} = sort {sortDeps($b, $a, $LVer)} @{$ArrRef};
    return $ArrRef;
}

sub sortDeps($$$)
{
    if($Header_Dependency{$_[2]}{$_[0]}
    and not $Header_Dependency{$_[2]}{$_[1]}) {
        return 1;
    }
    elsif(not $Header_Dependency{$_[2]}{$_[0]}
    and $Header_Dependency{$_[2]}{$_[1]}) {
        return -1;
    }
    return 0;
}

sub registerHeader($$)
{ # input: absolute path of header, relative path or name
    my ($Header, $LVer) = @_;
    if(not $Header) {
        return "";
    }
    if(isAbsPath($Header) and not -f $Header)
    { # incorrect absolute path
        exitStatus("Access_Error", "can't access \'$Header\'");
    }
    if(skipHeader($Header, $LVer))
    { # skip
        return "";
    }
    if(my $Header_Path = identifyHeader($Header, $LVer))
    {
        detectHeaderIncludes($Header_Path, $LVer);
        
        if(defined $In::Opt{"Tolerance"}
        and $In::Opt{"Tolerance"}=~/3/)
        { # 3 - skip headers that include non-Linux headers
            if($In::Opt{"OS"} ne "windows")
            {
                foreach my $Inc (keys(%{$Header_Includes{$LVer}{$Header_Path}}))
                {
                    if(specificHeader($Inc, "windows")) {
                        return "";
                    }
                }
            }
        }
        
        if(my $RHeader_Path = $Header_ErrorRedirect{$LVer}{$Header_Path})
        { # redirect
            if($In::Desc{$LVer}{"RegHeader"}{$RHeader_Path}{"Identity"}
            or skipHeader($RHeader_Path, $LVer))
            { # skip
                return "";
            }
            $Header_Path = $RHeader_Path;
        }
        elsif($Header_ShouldNotBeUsed{$LVer}{$Header_Path})
        { # skip
            return "";
        }
        
        if(my $HName = getFilename($Header_Path))
        { # register
            $In::Desc{$LVer}{"RegHeader"}{$Header_Path}{"Identity"} = $HName;
            $HeaderName_Paths{$LVer}{$HName}{$Header_Path} = 1;
        }
        
        if(($Header=~/\.(\w+)\Z/ and $1 ne "h")
        or $Header!~/\.(\w+)\Z/)
        { # hpp, hh, etc.
            $In::ABI{$LVer}{"Language"} = "C++";
            $In::Opt{"CppHeaders"} = 1;
        }
        
        if($Header=~/(\A|\/)c\+\+(\/|\Z)/)
        { # /usr/include/c++/4.6.1/...
            $In::Opt{"StdcxxTesting"} = 1;
        }
        
        return $Header_Path;
    }
    return "";
}

sub registerDir($$$)
{
    my ($Dir, $WithDeps, $LVer) = @_;
    $Dir=~s/[\/\\]+\Z//g;
    if(not $Dir) {
        return;
    }
    $Dir = getAbsPath($Dir);
    
    my $Mode = "All";
    if($WithDeps)
    {
        if($RegisteredDirs{$LVer}{$Dir}{1}) {
            return;
        }
        elsif($RegisteredDirs{$LVer}{$Dir}{0}) {
            $Mode = "DepsOnly";
        }
    }
    else
    {
        if($RegisteredDirs{$LVer}{$Dir}{1}
        or $RegisteredDirs{$LVer}{$Dir}{0}) {
            return;
        }
    }
    $Header_Dependency{$LVer}{$Dir} = 1;
    $RegisteredDirs{$LVer}{$Dir}{$WithDeps} = 1;
    if($Mode eq "DepsOnly")
    {
        foreach my $Path (cmdFind($Dir,"d")) {
            $Header_Dependency{$LVer}{$Path} = 1;
        }
        return;
    }
    foreach my $Path (sort {length($b)<=>length($a)} cmdFind($Dir,"f"))
    {
        if($WithDeps)
        { 
            my $SubDir = $Path;
            while(($SubDir = getDirname($SubDir)) ne $Dir)
            { # register all sub directories
                $Header_Dependency{$LVer}{$SubDir} = 1;
            }
        }
        if(isNotHeader($Path)) {
            next;
        }
        if(ignorePath($Path)) {
            next;
        }
        # Neighbors
        foreach my $Part (getPrefixes($Path)) {
            $In::Desc{$LVer}{"IncludeNeighbors"}{$Part} = $Path;
        }
    }
    if(getFilename($Dir) eq "include")
    { # search for "lib/include/" directory
        my $LibDir = $Dir;
        if($LibDir=~s/([\/\\])include\Z/$1lib/g and -d $LibDir) {
            registerDir($LibDir, $WithDeps, $LVer);
        }
    }
}

sub getIncString($$)
{
    my ($ArrRef, $Style) = @_;
    if(not $ArrRef or $#{$ArrRef}<0) {
        return "";
    }
    
    my $Str = "";
    foreach (@{$ArrRef}) {
        $Str .= " ".includeOpt($_, $Style);
    }
    return $Str;
}

sub getIncPaths($$)
{
    my ($HRef, $LVer) = @_;
    
    my @IncPaths = @{$Add_Include_Paths{$LVer}};
    if($In::Desc{$LVer}{"AutoIncludePaths"})
    { # auto-detecting dependencies
        my %Includes = ();
        foreach my $HPath (@{$HRef})
        {
            foreach my $Dir (getHeaderDeps($HPath, $LVer))
            {
                if($In::Desc{$LVer}{"SkipIncludePaths"}{$Dir}) {
                    next;
                }
                if(my $SystemRoot = $In::Opt{"SystemRoot"})
                {
                    if($In::Desc{$LVer}{"SkipIncludePaths"}{$SystemRoot.$Dir}) {
                        next;
                    }
                }
                $Includes{$Dir} = 1;
            }
        }
        foreach my $Dir (@{sortIncPaths([keys(%Includes)], $LVer)}) {
            push_U(\@IncPaths, $Dir);
        }
    }
    else
    { # user-defined paths
        @IncPaths = @{$Include_Paths{$LVer}};
    }
    return \@IncPaths;
}

sub searchForHeaders($)
{
    my $LVer = $_[0];
    
    my $DescRef = $In::Desc{$LVer};
    
    # gcc standard include paths
    registerGccHeaders();
    
    if($In::ABI{$LVer}{"Language"} eq "C++" and not $In::Opt{"StdcxxTesting"})
    { # c++ standard include paths
        registerCppHeaders();
    }
    
    # processing header paths
    my @HPaths = ();
    
    if($DescRef->{"IncludePaths"}) {
        @HPaths = @{$DescRef->{"IncludePaths"}};
    }
    
    if($DescRef->{"AddIncludePaths"}) {
        @HPaths = (@HPaths, @{$DescRef->{"AddIncludePaths"}});
    }
    
    foreach my $Path (@HPaths)
    {
        my $IPath = $Path;
        if(my $SystemRoot = $In::Opt{"SystemRoot"})
        {
            if(isAbsPath($Path)) {
                $Path = $SystemRoot.$Path;
            }
        }
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        elsif(-f $Path) {
            exitStatus("Access_Error", "\'$Path\' - not a directory");
        }
        elsif(-d $Path)
        {
            $Path = getAbsPath($Path);
            registerDir($Path, 0, $LVer);
            
            if($DescRef->{"AddIncludePaths"}
            and grep {$IPath eq $_} @{$DescRef->{"AddIncludePaths"}}) {
                push(@{$Add_Include_Paths{$LVer}}, $Path);
            }
            else {
                push(@{$Include_Paths{$LVer}}, $Path);
            }
        }
    }
    
    # registering directories
    my @Headers = keys(%{$DescRef->{"Headers"}});
    @Headers = sort {$DescRef->{"Headers"}{$a}<=>$DescRef->{"Headers"}{$b}} @Headers;
    foreach my $Path (@Headers)
    {
        if(not -e $Path) {
            next;
        }
        $Path = getAbsPath($Path);
        if(-d $Path) {
            registerDir($Path, 1, $LVer);
        }
        elsif(-f $Path)
        {
            my $Dir = getDirname($Path);
            if(not grep { $Dir eq $_ } (@{$In::Opt{"SysPaths"}{"include"}})
            and not $LocalIncludes{$Dir}) {
                registerDir($Dir, 1, $LVer);
            }
        }
    }
    
    # clean memory
    %RegisteredDirs = ();
    
    # registering headers
    my $Position = 0;
    foreach my $Path (@Headers)
    {
        if(isAbsPath($Path) and not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        $Path = pathFmt($Path);
        if(isHeader($Path, 1, $LVer))
        {
            if(my $HPath = registerHeader($Path, $LVer)) {
                $In::Desc{$LVer}{"RegHeader"}{$HPath}{"Pos"} = $Position++;
            }
        }
        elsif(-d $Path)
        {
            my @Registered = ();
            foreach my $P (cmdFind($Path,"f"))
            {
                if(ignorePath($P)) {
                    next;
                }
                if(not isHeader($P, 0, $LVer)) {
                    next;
                }
                if(my $HPath = registerHeader($P, $LVer)) {
                    push(@Registered, $HPath);
                }
            }
            @Registered = sort {sortHeaders($a, $b)} @Registered;
            sortByWord(\@Registered, $In::Opt{"TargetLibShort"});
            foreach my $P (@Registered) {
                $In::Desc{$LVer}{"RegHeader"}{$P}{"Pos"} = $Position++;
            }
        }
        elsif(not defined $In::Opt{"SkipUnidentified"}) {
            exitStatus("Access_Error", "can't identify \'$Path\' as a header file");
        }
    }
    
    if(defined $In::Opt{"Tolerance"}
    and $In::Opt{"Tolerance"}=~/4/)
    { # 4 - skip headers included by others
        foreach my $Path (keys(%{$In::Desc{$LVer}{"RegHeader"}}))
        {
            if(defined $Header_Includes_R{$LVer}{$Path}) {
                delete($In::Desc{$LVer}{"RegHeader"}{$Path});
            }
        }
    }
    
    if(not defined $In::Desc{$LVer}{"Include_Preamble"}) {
        $In::Desc{$LVer}{"Include_Preamble"} = [];
    }
    
    if(my $HList = $DescRef->{"IncludePreamble"})
    { # preparing preamble headers
        foreach my $Header (split(/\s*\n\s*/, $HList))
        {
            if(isAbsPath($Header) and not -f $Header) {
                exitStatus("Access_Error", "can't access file \'$Header\'");
            }
            $Header = pathFmt($Header);
            if(my $Header_Path = isHeader($Header, 1, $LVer))
            {
                if(skipHeader($Header_Path, $LVer)) {
                    next;
                }
                push_U($In::Desc{$LVer}{"Include_Preamble"}, $Header_Path);
            }
            elsif(not defined $In::Opt{"SkipUnidentified"}) {
                exitStatus("Access_Error", "can't identify \'$Header\' as a header file");
            }
        }
    }
    
    foreach my $Header_Name (keys(%{$HeaderName_Paths{$LVer}}))
    { # set relative paths (for duplicates)
        if(keys(%{$HeaderName_Paths{$LVer}{$Header_Name}})>=2)
        { # search for duplicates
            my $FirstPath = (keys(%{$HeaderName_Paths{$LVer}{$Header_Name}}))[0];
            my $Prefix = getDirname($FirstPath);
            while($Prefix=~/\A(.+)[\/\\]+[^\/\\]+\Z/)
            { # detect a shortest distinguishing prefix
                my $NewPrefix = $1;
                my %Identity = ();
                foreach my $Path (keys(%{$HeaderName_Paths{$LVer}{$Header_Name}}))
                {
                    if($Path=~/\A\Q$Prefix\E[\/\\]+(.*)\Z/) {
                        $Identity{$Path} = $1;
                    }
                }
                if(keys(%Identity)==keys(%{$HeaderName_Paths{$LVer}{$Header_Name}}))
                { # all names are different with current prefix
                    foreach my $Path (keys(%{$HeaderName_Paths{$LVer}{$Header_Name}})) {
                        $In::Desc{$LVer}{"RegHeader"}{$Path}{"Identity"} = $Identity{$Path};
                    }
                    last;
                }
                $Prefix = $NewPrefix; # increase prefix
            }
        }
    }
    
    # clean memory
    %HeaderName_Paths = ();
    
    foreach my $HName (keys(%{$In::Desc{$LVer}{"IncludeOrder"}}))
    { # ordering headers according to the descriptor
        my $PairName = $In::Desc{$LVer}{"IncludeOrder"}{$HName};
        my ($Pos, $PairPos, $Path, $PairPath) = (-1, -1, undef, undef);
        
        my @Paths = keys(%{$In::Desc{$LVer}{"RegHeader"}});
        @Paths = sort {$In::Desc{$LVer}{"RegHeader"}{$a}{"Pos"}<=>$In::Desc{$LVer}{"RegHeader"}{$b}{"Pos"}} @Paths;
        
        foreach my $HPath (@Paths) 
        {
            if(getFilename($HPath) eq $PairName)
            {
                $PairPos = $In::Desc{$LVer}{"RegHeader"}{$HPath}{"Pos"};
                $PairPath = $HPath;
            }
            if(getFilename($HPath) eq $HName)
            {
                $Pos = $In::Desc{$LVer}{"RegHeader"}{$HPath}{"Pos"};
                $Path = $HPath;
            }
        }
        if($PairPos!=-1 and $Pos!=-1
        and int($PairPos)<int($Pos))
        {
            my %Tmp = %{$In::Desc{$LVer}{"RegHeader"}{$Path}};
            %{$In::Desc{$LVer}{"RegHeader"}{$Path}} = %{$In::Desc{$LVer}{"RegHeader"}{$PairPath}};
            %{$In::Desc{$LVer}{"RegHeader"}{$PairPath}} = %Tmp;
        }
    }
    if(not keys(%{$In::Desc{$LVer}{"RegHeader"}})) {
        exitStatus("Error", "header files are not found in the ".$DescRef->{"Version"});
    }
}

sub addTargetHeaders($)
{
    my $LVer = $_[0];
    
    foreach my $RegHeader (keys(%{$In::Desc{$LVer}{"RegHeader"}}))
    {
        my $RegDir = getDirname($RegHeader);
        $In::Desc{$LVer}{"TargetHeader"}{getFilename($RegHeader)} = 1;
        
        if(not $In::Desc{$LVer}{"AutoIncludePaths"}) {
            detectRecursiveIncludes($RegHeader, $LVer);
        }
        
        foreach my $RecInc (keys(%{$RecursiveIncludes{$LVer}{$RegHeader}}))
        {
            my $Dir = getDirname($RecInc);
            
            if(($In::Opt{"DumpSystem"} and familiarDirs($RegDir, $Dir))
            or $RecursiveIncludes{$LVer}{$RegHeader}{$RecInc}<1)
            { # in the same directory or included by #include "..."
                $In::Desc{$LVer}{"TargetHeader"}{getFilename($RecInc)} = 1;
            }
        }
    }
}

sub familiarDirs($$)
{
    my ($D1, $D2) = @_;
    if($D1 eq $D2) {
        return 1;
    }
    
    my $U1 = index($D1, "/usr/");
    my $U2 = index($D2, "/usr/");
    
    if($U1==0 and $U2!=0) {
        return 0;
    }
    
    if($U2==0 and $U1!=0) {
        return 0;
    }
    
    if(index($D2, $D1."/")==0) {
        return 1;
    }
    
    # /usr/include/DIR
    # /home/user/DIR
    
    my $DL = getDepth($D1);
    
    my @Dirs1 = ($D1);
    while($DL - getDepth($D1)<=2
    and getDepth($D1)>=4
    and $D1=~s/[\/\\]+[^\/\\]*?\Z//) {
        push(@Dirs1, $D1);
    }
    
    my @Dirs2 = ($D2);
    while(getDepth($D2)>=4
    and $D2=~s/[\/\\]+[^\/\\]*?\Z//) {
        push(@Dirs2, $D2);
    }
    
    foreach my $P1 (@Dirs1)
    {
        foreach my $P2 (@Dirs2)
        {
            if($P1 eq $P2) {
                return 1;
            }
        }
    }
    return 0;
}

sub isHeaderFile($)
{
    if($_[0]=~/\.($HEADER_EXT)\Z/i) {
        return $_[0];
    }
    return 0;
}

sub isNotHeader($)
{
    if($_[0]=~/\.\w+\Z/
    and $_[0]!~/\.($HEADER_EXT)\Z/i) {
        return 1;
    }
    return 0;
}

sub getGccPath()
{
    if(defined $In::Opt{"GccPath"}) {
        return $In::Opt{"GccPath"};
    }
    
    my $Path = undef;
    
    if(my $CrossGcc = $In::Opt{"CrossGcc"})
    { # --cross-gcc=arm-linux-gcc
        if(-e $CrossGcc)
        { # absolute or relative path
            $Path = getAbsPath($CrossGcc);
        }
        elsif($CrossGcc!~/\// and getCmdPath($CrossGcc))
        { # command name
            $Path = $CrossGcc;
        }
        else {
            exitStatus("Access_Error", "can't access \'$CrossGcc\'");
        }
        
        if($Path=~/\s/) {
            $Path = "\"".$Path."\"";
        }
    }
    else
    { # try default gcc
        $Path = getCmdPath("gcc");
        
        if(not $Path)
        { # try to find gcc-X.Y
            foreach my $P (@{$In::Opt{"SysPaths"}{"bin"}})
            {
                if(my @GCCs = cmdFind($P, "", '/gcc-[0-9.]*\Z', 1, 1))
                { # select the latest version
                    @GCCs = sort {$b cmp $a} @GCCs;
                    if(checkGcc("3", $GCCs[0]))
                    {
                        $Path = $GCCs[0];
                        last;
                    }
                }
            }
        }
        if(not $Path) {
            exitStatus("Not_Found", "can't find GCC>=3.0 in PATH");
        }
    }
    
    return ($In::Opt{"GccPath"} = $Path);
}

sub clearSysFilesCache($)
{
    my $LVer = $_[0];
    
    %Cache = ();
    
    delete($RecursiveIncludes{$LVer});
    delete($Header_Include_Prefix{$LVer});
    delete($Header_Includes{$LVer});
    delete($Header_ErrorRedirect{$LVer});
}

sub dumpFilesInfo($)
{ # extra information for other tools
    my $LVer = $_[0];
    my $EInfo = $In::Opt{"ExtraInfo"};
    
    writeFile($EInfo."/recursive-includes", Dumper($RecursiveIncludes{$LVer}));
    writeFile($EInfo."/direct-includes", Dumper($Header_Includes{$LVer}));
    
    if(my @Redirects = keys(%{$Header_ErrorRedirect{$LVer}}))
    {
        my $REDIR = "";
        foreach my $P1 (sort @Redirects) {
            $REDIR .= $P1.";".$Header_ErrorRedirect{$LVer}{$P1}."\n";
        }
        writeFile($EInfo."/include-redirect", $REDIR);
    }
}

sub callPreprocessor($$$)
{
    my ($Path, $Inc, $LVer) = @_;
    
    my $IncludeString=$Inc;
    if(not $Inc) {
        $IncludeString = getIncString(getIncPaths([$Path], $LVer), "GCC");
    }
    
    my $TmpDir = $In::Opt{"Tmp"};
    my $Cmd = getCompileCmd($Path, "-dD -E", $IncludeString, $LVer);
    my $Out = $TmpDir."/preprocessed.h";
    system($Cmd." >\"$Out\" 2>\"$TmpDir/null\"");
    
    return $Out;
}

sub isHeader($$$)
{
    my ($Header, $UserDefined, $LVer) = @_;
    if(-d $Header) {
        return 0;
    }
    if(-f $Header) {
        $Header = getAbsPath($Header);
    }
    else
    {
        if(isAbsPath($Header))
        { # incorrect absolute path
            return 0;
        }
        if(my $HPath = identifyHeader($Header, $LVer)) {
            $Header = $HPath;
        }
        else
        { # can't find header
            return 0;
        }
    }
    if($Header=~/\.\w+\Z/)
    { # have an extension
        return isHeaderFile($Header);
    }
    else
    {
        if($UserDefined==2)
        { # specified on the command line
            if(cmdFile($Header)!~/HTML|XML/i) {
                return $Header;
            }
        }
        elsif($UserDefined)
        { # specified in the XML-descriptor
          # header file without an extension
            return $Header;
        }
        else
        {
            if(index($Header, "/include/")!=-1
            or cmdFile($Header)=~/C[\+]*\s+program/i)
            { # !~/HTML|XML|shared|dynamic/i
                return $Header;
            }
        }
    }
    return 0;
}

return 1;
