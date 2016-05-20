#!/usr/bin/perl
###########################################################################
# ABI Compliance Checker (ABICC) 1.99.21
# A tool for checking backward compatibility of a C/C++ library API
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2011-2012 ROSA Laboratory
# Copyright (C) 2012-2016 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux, FreeBSD, Mac OS X, Haiku, MS Windows, Symbian
#
# REQUIREMENTS
# ============
#  Linux
#    - G++ (3.0-4.7, 4.8.3, 4.9 or newer)
#    - GNU Binutils (readelf, c++filt, objdump)
#    - Perl 5 (5.8 or newer)
#    - Ctags (5.8 or newer)
#    - ABI Dumper (0.99.15 or newer)
#
#  Mac OS X
#    - Xcode (g++, c++filt, otool, nm)
#    - Ctags (5.8 or newer)
#
#  MS Windows
#    - MinGW (3.0-4.7, 4.8.3, 4.9 or newer)
#    - MS Visual C++ (dumpbin, undname, cl)
#    - Active Perl 5 (5.8 or newer)
#    - Sigcheck v1.71 or newer
#    - Info-ZIP 3.0 (zip, unzip)
#    - Ctags (5.8 or newer)
#    - Add tool locations to the PATH environment variable
#    - Run vsvars32.bat (C:\Microsoft Visual Studio 9.0\Common7\Tools\)
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
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Copy qw(copy move);
use Cwd qw(abs_path cwd realpath);
use Storable qw(dclone);
use Data::Dumper;
use Config;

my $TOOL_VERSION = "1.99.21";
my $ABI_DUMP_VERSION = "3.2";
my $XML_REPORT_VERSION = "1.2";
my $XML_ABI_DUMP_VERSION = "1.2";
my $OSgroup = get_OSgroup();
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);
my $LOCALE = "C.UTF-8";

# Internal modules
my $MODULES_DIR = get_Modules();
push(@INC, get_dirname($MODULES_DIR));
# Rules DB
my %RULES_PATH = (
    "Binary" => $MODULES_DIR."/RulesBin.xml",
    "Source" => $MODULES_DIR."/RulesSrc.xml");

my ($Help, $ShowVersion, %Descriptor, $TargetLibraryName,
$TestTool, $DumpAPI, $SymbolsListPath, $CheckHeadersOnly_Opt, $UseDumps,
$AppPath, $StrictCompat, $DumpVersion, $ParamNamesPath,
%RelativeDirectory, $TargetTitle, $TestDump, $LoggingPath,
%TargetVersion, $InfoMsg, $CrossGcc, %OutputLogPath,
$OutputReportPath, $OutputDumpPath, $ShowRetVal, $SystemRoot_Opt, $DumpSystem,
$CmpSystems, $TargetLibsPath, $Debug, $CrossPrefix, $UseStaticLibs, $NoStdInc,
$TargetComponent_Opt, $TargetSysInfo, $TargetHeader, $ExtendedCheck, $Quiet,
$SkipHeadersPath, $CppCompat, $LogMode, $StdOut, $ListAffected, $ReportFormat,
$UserLang, $TargetHeadersPath, $BinaryOnly, $SourceOnly, $BinaryReportPath,
$SourceReportPath, $UseXML, $SortDump, $DumpFormat,
$ExtraInfo, $ExtraDump, $Force, $Tolerance, $Tolerant, $SkipSymbolsListPath,
$CheckInfo, $Quick, $AffectLimit, $AllAffected, $CppIncompat,
$SkipInternalSymbols, $SkipInternalTypes, $TargetArch, $GccOptions,
$TypesListPath, $SkipTypesListPath, $CheckPrivateABI, $CountSymbols);

my $CmdName = get_filename($0);
my %OS_LibExt = (
    "dynamic" => {
        "linux"=>"so",
        "macos"=>"dylib",
        "windows"=>"dll",
        "symbian"=>"dso",
        "default"=>"so"
    },
    "static" => {
        "linux"=>"a",
        "windows"=>"lib",
        "symbian"=>"lib",
        "default"=>"a"
    }
);

my %OS_Archive = (
    "windows"=>"zip",
    "default"=>"tar.gz"
);

my %ERROR_CODE = (
    # Compatible verdict
    "Compatible"=>0,
    "Success"=>0,
    # Incompatible verdict
    "Incompatible"=>1,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot compile header files
    "Cannot_Compile"=>5,
    # Header compiled with errors
    "Compile_Error"=>6,
    # Invalid input ABI dump
    "Invalid_Dump"=>7,
    # Incompatible version of ABI dump
    "Dump_Version"=>8,
    # Cannot find a module
    "Module_Error"=>9,
    # Empty intersection between
    # headers and shared objects
    "Empty_Intersection"=>10,
    # Empty set of symbols in headers
    "Empty_Set"=>11
);

my $HomePage = "http://lvc.github.io/abi-compliance-checker/";

my $ShortUsage = "ABI Compliance Checker (ABICC) $TOOL_VERSION
A tool for checking backward compatibility of a C/C++ library API
Copyright (C) 2015 Andrey Ponomarenko's ABI Laboratory
License: GNU LGPL or GNU GPL

Usage: $CmdName [options]
Example: $CmdName -lib NAME -old OLD.xml -new NEW.xml

OLD.xml and NEW.xml are XML-descriptors:

    <version>
        1.0
    </version>

    <headers>
        /path/to/headers/
    </headers>

    <libs>
        /path/to/libraries/
    </libs>

More info: $CmdName --help\n";

if($#ARGV==-1)
{
    printMsg("INFO", $ShortUsage);
    exit(0);
}

GetOptions("h|help!" => \$Help,
  "i|info!" => \$InfoMsg,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
# general options
  "l|lib|library=s" => \$TargetLibraryName,
  "d1|old|o=s" => \$Descriptor{1}{"Path"},
  "d2|new|n=s" => \$Descriptor{2}{"Path"},
  "dump|dump-abi|dump_abi=s" => \$DumpAPI,
# extra options
  "app|application=s" => \$AppPath,
  "static-libs!" => \$UseStaticLibs,
  "gcc-path|cross-gcc=s" => \$CrossGcc,
  "gcc-prefix|cross-prefix=s" => \$CrossPrefix,
  "gcc-options=s" => \$GccOptions,
  "sysroot=s" => \$SystemRoot_Opt,
  "v1|vnum1|version1|vnum=s" => \$TargetVersion{1},
  "v2|vnum2|version2=s" => \$TargetVersion{2},
  "s|strict!" => \$StrictCompat,
  "symbols-list=s" => \$SymbolsListPath,
  "types-list=s" => \$TypesListPath,
  "skip-symbols=s" => \$SkipSymbolsListPath,
  "skip-types=s" => \$SkipTypesListPath,
  "headers-list=s" => \$TargetHeadersPath,
  "skip-headers=s" => \$SkipHeadersPath,
  "header=s" => \$TargetHeader,
  "headers-only|headers_only!" => \$CheckHeadersOnly_Opt,
  "show-retval!" => \$ShowRetVal,
  "use-dumps!" => \$UseDumps,
  "nostdinc!" => \$NoStdInc,
  "dump-system=s" => \$DumpSystem,
  "sysinfo=s" => \$TargetSysInfo,
  "cmp-systems!" => \$CmpSystems,
  "libs-list=s" => \$TargetLibsPath,
  "ext|extended!" => \$ExtendedCheck,
  "q|quiet!" => \$Quiet,
  "stdout!" => \$StdOut,
  "report-format=s" => \$ReportFormat,
  "dump-format=s" => \$DumpFormat,
  "xml!" => \$UseXML,
  "lang=s" => \$UserLang,
  "arch=s" => \$TargetArch,
  "binary|bin|abi!" => \$BinaryOnly,
  "source|src|api!" => \$SourceOnly,
  "limit-affected|affected-limit=s" => \$AffectLimit,
  "count-symbols=s" => \$CountSymbols,
# other options
  "test!" => \$TestTool,
  "test-dump!" => \$TestDump,
  "debug!" => \$Debug,
  "cpp-compatible!" => \$CppCompat,
  "cpp-incompatible!" => \$CppIncompat,
  "p|params=s" => \$ParamNamesPath,
  "relpath1|relpath=s" => \$RelativeDirectory{1},
  "relpath2=s" => \$RelativeDirectory{2},
  "dump-path=s" => \$OutputDumpPath,
  "sort!" => \$SortDump,
  "report-path=s" => \$OutputReportPath,
  "bin-report-path=s" => \$BinaryReportPath,
  "src-report-path=s" => \$SourceReportPath,
  "log-path=s" => \$LoggingPath,
  "log1-path=s" => \$OutputLogPath{1},
  "log2-path=s" => \$OutputLogPath{2},
  "logging-mode=s" => \$LogMode,
  "list-affected!" => \$ListAffected,
  "title|l-full|lib-full=s" => \$TargetTitle,
  "component=s" => \$TargetComponent_Opt,
  "extra-info=s" => \$ExtraInfo,
  "extra-dump!" => \$ExtraDump,
  "force!" => \$Force,
  "tolerance=s" => \$Tolerance,
  "tolerant!" => \$Tolerant,
  "check!" => \$CheckInfo,
  "quick!" => \$Quick,
  "all-affected!" => \$AllAffected,
  "skip-internal-symbols|skip-internal=s" => \$SkipInternalSymbols,
  "skip-internal-types=s" => \$SkipInternalTypes,
  "check-private-abi!" => \$CheckPrivateABI
) or ERR_MESSAGE();

sub ERR_MESSAGE()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit($ERROR_CODE{"Error"});
}

my $LIB_TYPE = $UseStaticLibs?"static":"dynamic";
my $SLIB_TYPE = $LIB_TYPE;
if($OSgroup!~/macos|windows/ and $SLIB_TYPE eq "dynamic")
{ # show as "shared" library
    $SLIB_TYPE = "shared";
}
my $LIB_EXT = getLIB_EXT($OSgroup);
my $AR_EXT = getAR_EXT($OSgroup);
my $BYTE_SIZE = 8;
my $COMMON_LOG_PATH = "logs/run.log";

my $HelpMessage="
NAME:
  ABI Compliance Checker ($CmdName)
  Check backward compatibility of a C/C++ library API

DESCRIPTION:
  ABI Compliance Checker (ABICC) is a tool for checking backward binary and
  source-level compatibility of a $SLIB_TYPE C/C++ library. The tool checks
  header files and $SLIB_TYPE libraries (*.$LIB_EXT) of old and new versions and
  analyzes changes in API and ABI (ABI=API+compiler ABI) that may break binary
  and/or source-level compatibility: changes in calling stack, v-table changes,
  removed symbols, renamed fields, etc. Binary incompatibility may result in
  crashing or incorrect behavior of applications built with an old version of
  a library if they run on a new one. Source incompatibility may result in
  recompilation errors with a new library version.

  The tool is intended for developers of software libraries and maintainers
  of operating systems who are interested in ensuring backward compatibility,
  i.e. allow old applications to run or to be recompiled with newer library
  versions.

  Also the tool can be used by ISVs for checking applications portability to
  new library versions. Found issues can be taken into account when adapting
  the application to a new library version.

  This tool is free software: you can redistribute it and/or modify it
  under the terms of the GNU LGPL or GNU GPL.

USAGE:
  $CmdName [options]

EXAMPLE:
  $CmdName -lib NAME -old OLD.xml -new NEW.xml

  OLD.xml and NEW.xml are XML-descriptors:

    <version>
        1.0
    </version>

    <headers>
        /path1/to/header(s)/
        /path2/to/header(s)/
         ...
    </headers>

    <libs>
        /path1/to/library(ies)/
        /path2/to/library(ies)/
         ...
    </libs>

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -i|-info
      Print complete info.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -l|-lib|-library NAME
      Library name (without version).

  -d1|-old|-o PATH
      Descriptor of 1st (old) library version.
      It may be one of the following:
      
         1. XML-descriptor (VERSION.xml file):

              <version>
                  1.0
              </version>

              <headers>
                  /path1/to/header(s)/
                  /path2/to/header(s)/
                   ...
              </headers>

              <libs>
                  /path1/to/library(ies)/
                  /path2/to/library(ies)/
                   ...
              </libs>

                 ...
             
         2. ABI dump generated by -dump option
         3. Directory with headers and/or $SLIB_TYPE libraries
         4. Single header file

      If you are using an 2-4 descriptor types then you should
      specify version numbers with -v1 and -v2 options too.

      For more information, please see:
        http://ispras.linuxbase.org/index.php/Library_Descriptor

  -d2|-new|-n PATH
      Descriptor of 2nd (new) library version.

  -dump|-dump-abi PATH
      Create library ABI dump for the input XML descriptor. You can
      transfer it anywhere and pass instead of the descriptor. Also
      it can be used for debugging the tool.
      
      Supported versions of ABI dump: 2.0<=V<=$ABI_DUMP_VERSION\n";

sub HELP_MESSAGE() {
    printMsg("INFO", $HelpMessage."
MORE INFO:
     $CmdName --info\n");
}

sub INFO_MESSAGE()
{
    printMsg("INFO", "$HelpMessage
EXTRA OPTIONS:
  -app|-application PATH
      This option allows to specify the application that should be checked
      for portability to the new library version.

  -static-libs
      Check static libraries instead of the shared ones. The <libs> section
      of the XML-descriptor should point to static libraries location.

  -gcc-path PATH
      Path to the cross GCC compiler to use instead of the usual (host) GCC.

  -gcc-prefix PREFIX
      GCC toolchain prefix.
  
  -gcc-options OPTS
      Additional compiler options.

  -sysroot DIR
      Specify the alternative root directory. The tool will search for include
      paths in the DIR/usr/include and DIR/usr/lib directories.

  -v1|-version1 NUM
      Specify 1st library version outside the descriptor. This option is needed
      if you have preferred an alternative descriptor type (see -d1 option).

      In general case you should specify it in the XML-descriptor:
          <version>
              VERSION
          </version>

  -v2|-version2 NUM
      Specify 2nd library version outside the descriptor.

  -vnum NUM
      Specify the library version in the generated ABI dump. The <version> section
      of the input XML descriptor will be overwritten in this case.

  -s|-strict
      Treat all compatibility warnings as problems. Add a number of \"Low\"
      severity problems to the return value of the tool.

  -headers-only
      Check header files without $SLIB_TYPE libraries. It is easy to run, but may
      provide a low quality compatibility report with false positives and
      without detecting of added/removed symbols.
      
      Alternatively you can write \"none\" word to the <libs> section
      in the XML-descriptor:
          <libs>
              none
          </libs>

  -show-retval
      Show the symbol's return type in the report.

  -symbols-list PATH
      This option allows to specify a file with a list of symbols (mangled
      names in C++) that should be checked. Other symbols will not be checked.
  
  -types-list PATH
      This option allows to specify a file with a list of types that should
      be checked. Other types will not be checked.
      
  -skip-symbols PATH
      The list of symbols that should not be checked.
  
  -skip-types PATH
      The list of types that should not be checked.

  -headers-list PATH
      The file with a list of headers, that should be checked/dumped.
      
  -skip-headers PATH
      The file with the list of header files, that should not be checked.
      
  -header NAME
      Check/Dump ABI of this header only.

  -use-dumps
      Make dumps for two versions of a library and compare dumps. This should
      increase the performance of the tool and decrease the system memory usage.

  -nostdinc
      Do not search in GCC standard system directories for header files.

  -dump-system NAME -sysroot DIR
      Find all the shared libraries and header files in DIR directory,
      create XML descriptors and make ABI dumps for each library. The result
      set of ABI dumps can be compared (--cmp-systems) with the other one
      created for other version of operating system in order to check them for
      compatibility. Do not forget to specify -cross-gcc option if your target
      system requires some specific version of GCC compiler (different from
      the host GCC). The system ABI dump will be generated to:
          sys_dumps/NAME/ARCH
          
  -dump-system DESCRIPTOR.xml
      The same as the previous option but takes an XML descriptor of the target
      system as input, where you should describe it:
          
          /* Primary sections */
          
          <name>
              /* Name of the system */
          </name>
          
          <headers>
              /* The list of paths to header files and/or
                 directories with header files, one per line */
          </headers>
          
          <libs>
              /* The list of paths to shared libraries and/or
                 directories with shared libraries, one per line */
          </libs>
          
          /* Optional sections */
          
          <search_headers>
              /* List of directories to be searched
                 for header files to automatically
                 generate include paths, one per line */
          </search_headers>
          
          <search_libs>
              /* List of directories to be searched
                 for shared libraries to resolve
                 dependencies, one per line */
          </search_libs>
          
          <tools>
              /* List of directories with tools used
                 for analysis (GCC toolchain), one per line */
          </tools>
          
          <cross_prefix>
              /* GCC toolchain prefix.
                 Examples:
                     arm-linux-gnueabi
                     arm-none-symbianelf */
          </cross_prefix>
          
          <gcc_options>
              /* Additional GCC options, one per line */
          </gcc_options>

  -sysinfo DIR
      This option should be used with -dump-system option to dump
      ABI of operating systems and configure the dumping process.

  -cmp-systems -d1 sys_dumps/NAME1/ARCH -d2 sys_dumps/NAME2/ARCH
      Compare two system ABI dumps. Create compatibility reports for each
      library and the common HTML report including the summary of test
      results for all checked libraries. Report will be generated to:
          sys_compat_reports/NAME1_to_NAME2/ARCH

  -libs-list PATH
      The file with a list of libraries, that should be dumped by
      the -dump-system option or should be checked by the -cmp-systems option.

  -ext|-extended
      If your library A is supposed to be used by other library B and you
      want to control the ABI of B, then you should enable this option. The
      tool will check for changes in all data types, even if they are not
      used by any function in the library A. Such data types are not part
      of the A library ABI, but may be a part of the ABI of the B library.
      
      The short scheme is:
        app C (broken) -> lib B (broken ABI) -> lib A (stable ABI)

  -q|-quiet
      Print all messages to the file instead of stdout and stderr.
      Default path (can be changed by -log-path option):
          $COMMON_LOG_PATH

  -stdout
      Print analysis results (compatibility reports and ABI dumps) to stdout
      instead of creating a file. This would allow piping data to other programs.

  -report-format FMT
      Change format of compatibility report.
      Formats:
        htm - HTML format (default)
        xml - XML format

  -dump-format FMT
      Change format of ABI dump.
      Formats:
        perl - Data::Dumper format (default)
        xml - XML format

  -xml
      Alias for: --report-format=xml or --dump-format=xml

  -lang LANG
      Set library language (C or C++). You can use this option if the tool
      cannot auto-detect a language. This option may be useful for checking
      C-library headers (--lang=C) in --headers-only or --extended modes.
  
  -arch ARCH
      Set library architecture (x86, x86_64, ia64, arm, ppc32, ppc64, s390,
      ect.). The option is useful if the tool cannot detect correct architecture
      of the input objects.

  -binary|-bin|-abi
      Show \"Binary\" compatibility problems only.
      Generate report to:
        compat_reports/LIB_NAME/V1_to_V2/abi_compat_report.html
      
  -source|-src|-api
      Show \"Source\" compatibility problems only.
      Generate report to:
        compat_reports/LIB_NAME/V1_to_V2/src_compat_report.html
        
  -limit-affected LIMIT
      The maximum number of affected symbols listed under the description
      of the changed type in the report.
  
  -count-symbols PATH
      Count total public symbols in the ABI dump.

OTHER OPTIONS:
  -test
      Run internal tests. Create two binary incompatible versions of a sample
      library and run the tool to check them for compatibility. This option
      allows to check if the tool works correctly in the current environment.

  -test-dump
      Test ability to create, read and compare ABI dumps.
      
  -debug
      Debugging mode. Print debug info on the screen. Save intermediate
      analysis stages in the debug directory:
          debug/LIB_NAME/VERSION/

      Also consider using --dump option for debugging the tool.

  -cpp-compatible
      If your header files are written in C language and can be compiled
      by the G++ compiler (i.e. don't use C++ keywords), then you can tell
      the tool about this and speedup the analysis.
      
  -cpp-incompatible
      Set this option if input C header files use C++ keywords.

  -p|-params PATH
      Path to file with the function parameter names. It can be used
      for improving report view if the library header files have no
      parameter names. File format:
      
            func1;param1;param2;param3 ...
            func2;param1;param2;param3 ...
             ...

  -relpath PATH
      Replace {RELPATH} macros to PATH in the XML-descriptor used
      for dumping the library ABI (see -dump option).
  
  -relpath1 PATH
      Replace {RELPATH} macros to PATH in the 1st XML-descriptor (-d1).

  -relpath2 PATH
      Replace {RELPATH} macros to PATH in the 2nd XML-descriptor (-d2).

  -dump-path PATH
      Specify a *.abi.$AR_EXT or *.abi file path where to generate an ABI dump.
      Default: 
          abi_dumps/LIB_NAME/LIB_NAME_VERSION.abi.$AR_EXT

  -sort
      Enable sorting of data in ABI dumps.

  -report-path PATH
      Path to compatibility report.
      Default: 
          compat_reports/LIB_NAME/V1_to_V2/compat_report.html

  -bin-report-path PATH
      Path to \"Binary\" compatibility report.
      Default: 
          compat_reports/LIB_NAME/V1_to_V2/abi_compat_report.html

  -src-report-path PATH
      Path to \"Source\" compatibility report.
      Default: 
          compat_reports/LIB_NAME/V1_to_V2/src_compat_report.html

  -log-path PATH
      Log path for all messages.
      Default:
          logs/LIB_NAME/VERSION/log.txt

  -log1-path PATH
      Log path for 1st version of a library.
      Default:
          logs/LIB_NAME/V1/log.txt

  -log2-path PATH
      Log path for 2nd version of a library.
      Default:
          logs/LIB_NAME/V2/log.txt

  -logging-mode MODE
      Change logging mode.
      Modes:
        w - overwrite old logs (default)
        a - append old logs
        n - do not write any logs

  -list-affected
      Generate file with the list of incompatible
      symbols beside the HTML compatibility report.
      Use 'c++filt \@file' command from GNU binutils
      to unmangle C++ symbols in the generated file.
      Default names:
          abi_affected.txt
          src_affected.txt

  -component NAME
      The component name in the title and summary of the HTML report.
      Default:
          library

  -title NAME
      Change library name in the report title to NAME. By default
      will be displayed a name specified by -l option.
      
  -extra-info DIR
      Dump extra info to DIR.
      
  -extra-dump
      Create extended ABI dump containing all symbols
      from the translation unit.
      
  -force
      Try to use this option if the tool doesn't work.
      
  -tolerance LEVEL
      Apply a set of heuristics to successfully compile input
      header files. You can enable several tolerance levels by
      joining them into one string (e.g. 13, 124, etc.).
      Levels:
          1 - skip non-Linux headers (e.g. win32_*.h, etc.)
          2 - skip internal headers (e.g. *_p.h, impl/*.h, etc.)
          3 - skip headers that iclude non-Linux headers
          4 - skip headers included by others
          
  -tolerant
      Enable highest tolerance level [1234].
      
  -check
      Check completeness of the ABI dump.
      
  -quick
      Quick analysis. Disable check of some template instances.
      
  -skip-internal-symbols PATTERN
      Do not check symbols matched by the pattern.
  
  -skip-internal-types PATTERN
      Do not check types matched by the pattern.
  
  -check-private-abi
      Check data types from the private part of the ABI when
      comparing ABI dumps created by the ABI Dumper tool with
      use of the -public-headers option.
      
      Requires ABI Dumper >= 0.99.14

REPORT:
    Compatibility report will be generated to:
        compat_reports/LIB_NAME/V1_to_V2/compat_report.html

    Log will be generated to:
        logs/LIB_NAME/V1/log.txt
        logs/LIB_NAME/V2/log.txt

EXIT CODES:
    0 - Compatible. The tool has run without any errors.
    non-zero - Incompatible or the tool has run with errors.

MORE INFORMATION:
    ".$HomePage."\n");
}

my %Operator_Indication = (
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
    "compound" => "," );

my %UnknownOperator;

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
  "nop_expr" => "Other", #
  "addr_expr" => "Other", #
  "offset_type" => "Other" );

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

# Header file extensions as described by gcc
my $HEADER_EXT = "h|hh|hp|hxx|hpp|h\\+\\+";

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

my %IntrinsicNames = map {$_=>1} keys(%IntrinsicMangling);

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
my %DEFAULT_STD_ARGS = map {$_=>1} ("_Alloc", "_Compare", "_Traits", "_Rx_traits", "_InIter", "_OutIter");

my $ADD_TMPL_INSTANCES = 1;
my $EMERGENCY_MODE_48 = 0;

my %ConstantSuffix = (
    "unsigned int"=>"u",
    "long"=>"l",
    "unsigned long"=>"ul",
    "long long"=>"ll",
    "unsigned long long"=>"ull"
);

my %ConstantSuffixR =
reverse(%ConstantSuffix);

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

my %Intrinsic_Keywords = map {$_=>1} (
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

my %Slash_Type=(
    "default"=>"/",
    "windows"=>"\\"
);

my $SLASH = $Slash_Type{$OSgroup}?$Slash_Type{$OSgroup}:$Slash_Type{"default"};

# Global Variables
my %COMMON_LANGUAGE=(
  1 => "C",
  2 => "C" );

my $MAX_COMMAND_LINE_ARGUMENTS = 4096;
my $MAX_CPPFILT_FILE_SIZE = 50000;
my $CPPFILT_SUPPORT_FILE;

my (%WORD_SIZE, %CPU_ARCH, %GCC_VERSION);

my $STDCXX_TESTING = 0;
my $GLIBC_TESTING = 0;
my $CPP_HEADERS = 0;

my $CheckHeadersOnly = $CheckHeadersOnly_Opt;
my $CheckUndefined = 0;

my $TargetComponent = undef;
if($TargetComponent_Opt) {
    $TargetComponent = lc($TargetComponent_Opt);
}
else
{ # default: library
  # other components: header, system, ...
    $TargetComponent = "library";
}

my $TOP_REF = "<a class='top_ref' href='#Top'>to the top</a>";

my $SystemRoot;

my $MAIN_CPP_DIR;
my %RESULT;
my %LOG_PATH;
my %DEBUG_PATH;
my %Cache;
my %LibInfo;
my $COMPILE_ERRORS = 0;
my %CompilerOptions;
my %CheckedDyLib;
my $TargetLibraryShortName = parse_libname($TargetLibraryName, "shortest", $OSgroup);

# Constants (#defines)
my %Constants;
my %SkipConstants;
my %EnumConstants;

# Extra Info
my %SymbolHeader;
my %KnownLibs;

# Templates
my %TemplateInstance;
my %BasicTemplate;
my %TemplateArg;
my %TemplateDecl;
my %TemplateMap;

# Types
my %TypeInfo;
my %SkipTypes = (
  "1"=>{},
  "2"=>{} );
my %CheckedTypes;
my %TName_Tid;
my %EnumMembName_Id;
my %NestedNameSpaces = (
  "1"=>{},
  "2"=>{} );
my %VirtualTable;
my %VirtualTable_Model;
my %ClassVTable;
my %ClassVTable_Content;
my %VTableClass;
my %AllocableClass;
my %ClassMethods;
my %ClassNames;
my %Class_SubClasses;
my %OverriddenMethods;
my %TypedefToAnon;
my $MAX_ID = 0;

my %CheckedTypeInfo;

# Typedefs
my %Typedef_BaseName;
my %Typedef_Tr;
my %Typedef_Eq;
my %StdCxxTypedef;
my %MissedTypedef;
my %MissedBase;
my %MissedBase_R;
my %TypeTypedef;

# Symbols
my %SymbolInfo;
my %tr_name;
my %mangled_name_gcc;
my %mangled_name;
my %SkipSymbols = (
  "1"=>{},
  "2"=>{} );
my %SkipNameSpaces = (
  "1"=>{},
  "2"=>{} );
my %AddNameSpaces = (
  "1"=>{},
  "2"=>{} );
my %SymbolsList;
my %TypesList;
my %SymbolsList_App;
my %CheckedSymbols;
my %Symbol_Library = (
  "1"=>{},
  "2"=>{} );
my %Library_Symbol = (
  "1"=>{},
  "2"=>{} );
my %DepSymbol_Library = (
  "1"=>{},
  "2"=>{} );
my %DepLibrary_Symbol = (
  "1"=>{},
  "2"=>{} );
my %MangledNames;
my %Func_ShortName;
my %AddIntParams;
my %GlobalDataObject;
my %WeakSymbols;
my %Library_Needed= (
  "1"=>{},
  "2"=>{} );

# Extra Info
my %UndefinedSymbols;
my %PreprocessedHeaders;

# Headers
my %Include_Preamble = (
    "1"=>[],
    "2"=>[] );
my %Registered_Headers;
my %Registered_Sources;
my %HeaderName_Paths;
my %Header_Dependency;
my %Include_Neighbors;
my %Include_Paths = (
    "1"=>[],
    "2"=>[] );
my %INC_PATH_AUTODETECT = (
  "1"=>1,
  "2"=>1 );
my %Add_Include_Paths = (
    "1"=>[],
    "2"=>[] );
my %Skip_Include_Paths;
my %RegisteredDirs;
my %Header_ErrorRedirect;
my %Header_Includes;
my %Header_Includes_R;
my %Header_ShouldNotBeUsed;
my %RecursiveIncludes;
my %Header_Include_Prefix;
my %SkipHeaders;
my %SkipHeadersList=(
  "1"=>{},
  "2"=>{} );
my %SkipLibs;
my %Include_Order;
my %TUnit_NameSpaces;
my %TUnit_Classes;
my %TUnit_Funcs;
my %TUnit_Vars;

my %CppMode = (
  "1"=>0,
  "2"=>0 );
my %AutoPreambleMode = (
  "1"=>0,
  "2"=>0 );
my %MinGWMode = (
  "1"=>0,
  "2"=>0 );
my %Cpp0xMode = (
  "1"=>0,
  "2"=>0 );

# Shared Objects
my %RegisteredObjects;
my %RegisteredObjects_Short;
my %RegisteredSONAMEs;
my %RegisteredObject_Dirs;

my %CheckedArch;

# System Objects
my %SystemObjects;
my @DefaultLibPaths;
my %DyLib_DefaultPath;

# System Headers
my %SystemHeaders;
my @DefaultCppPaths;
my @DefaultGccPaths;
my @DefaultIncPaths;
my %DefaultCppHeader;
my %DefaultGccHeader;
my @UsersIncPath;

# Merging
my %CompleteSignature;
my $Version;
my %AddedInt;
my %RemovedInt;
my %AddedInt_Virt;
my %RemovedInt_Virt;
my %VirtualReplacement;
my %ChangedTypedef;
my %CompatRules;
my %IncompleteRules;
my %UnknownRules;
my %VTableChanged_M;
my %ExtendedSymbols;
my %ReturnedClass;
my %ParamClass;
my %SourceAlternative;
my %SourceAlternative_B;
my %SourceReplacement;
my $CurrentSymbol; # for debugging

#Report
my %TypeChanges;

#Speedup
my %TypeProblemsIndex;

# Calling Conventions
my %UseConv_Real = (
  1=>{ "R"=>0, "P"=>0 },
  2=>{ "R"=>0, "P"=>0 }
);

# ABI Dump
my %UsedDump;

# Filters
my %TargetLibs;
my %TargetHeaders;

# Format of objects
my $OStarget = $OSgroup;
my %TargetTools;

# Recursion locks
my @RecurLib;
my @RecurTypes;
my @RecurTypes_Diff;
my @RecurInclude;
my @RecurConstant;

# System
my %SystemPaths = (
    "include"=>[],
    "lib"=>[],
    "bin"=>[]
);
my @DefaultBinPaths;
my $GCC_PATH;

# Symbols versioning
my %SymVer = (
  "1"=>{},
  "2"=>{} );

# Problem descriptions
my %CompatProblems;
my %CompatProblems_Constants;
my %TotalAffected;

# Reports
my $ContentID = 1;
my $ContentSpanStart = "<span class=\"section\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanStart_Affected = "<span class=\"sect_aff\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanStart_Info = "<span class=\"sect_info\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanEnd = "</span>\n";
my $ContentDivStart = "<div id=\"CONTENT_ID\" style=\"display:none;\">\n";
my $ContentDivEnd = "</div>\n";
my $Content_Counter = 0;

# Modes
my $JoinReport = 1;
my $DoubleReport = 0;

my %Severity_Val=(
    "High"=>3,
    "Medium"=>2,
    "Low"=>1,
    "Safe"=>-1
);

sub get_Modules()
{
    my $TOOL_DIR = get_dirname($0);
    if(not $TOOL_DIR)
    { # patch for MS Windows
        $TOOL_DIR = ".";
    }
    my @SEARCH_DIRS = (
        # tool's directory
        abs_path($TOOL_DIR),
        # relative path to modules
        abs_path($TOOL_DIR)."/../share/abi-compliance-checker",
        # install path
        'MODULES_INSTALL_PATH'
    );
    foreach my $DIR (@SEARCH_DIRS)
    {
        if(not is_abs($DIR))
        { # relative path
            $DIR = abs_path($TOOL_DIR)."/".$DIR;
        }
        if(-d $DIR."/modules") {
            return $DIR."/modules";
        }
    }
    exitStatus("Module_Error", "can't find modules");
}

my %LoadedModules = ();

sub loadModule($)
{
    my $Name = $_[0];
    if(defined $LoadedModules{$Name}) {
        return;
    }
    my $Path = $MODULES_DIR."/Internals/$Name.pm";
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    require $Path;
    $LoadedModules{$Name} = 1;
}

sub readModule($$)
{
    my ($Module, $Name) = @_;
    my $Path = $MODULES_DIR."/Internals/$Module/".$Name;
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    return readFile($Path);
}

sub showPos($)
{
    my $Number = $_[0];
    if(not $Number) {
        $Number = 1;
    }
    else {
        $Number = int($Number)+1;
    }
    if($Number>3) {
        return $Number."th";
    }
    elsif($Number==1) {
        return "1st";
    }
    elsif($Number==2) {
        return "2nd";
    }
    elsif($Number==3) {
        return "3rd";
    }
    else {
        return $Number;
    }
}

sub search_Tools($)
{
    my $Name = $_[0];
    return "" if(not $Name);
    if(my @Paths = keys(%TargetTools))
    {
        foreach my $Path (@Paths)
        {
            if(-f join_P($Path, $Name)) {
                return join_P($Path, $Name);
            }
            if($CrossPrefix)
            { # user-defined prefix (arm-none-symbianelf, ...)
                my $Candidate = join_P($Path, $CrossPrefix."-".$Name);
                if(-f $Candidate) {
                    return $Candidate;
                }
            }
        }
    }
    else {
        return "";
    }
}

sub synch_Cmd($)
{
    my $Name = $_[0];
    if(not $GCC_PATH)
    { # GCC was not found yet
        return "";
    }
    my $Candidate = $GCC_PATH;
    if($Candidate=~s/\bgcc(|\.\w+)\Z/$Name$1/) {
        return $Candidate;
    }
    return "";
}

sub get_CmdPath($)
{
    my $Name = $_[0];
    return "" if(not $Name);
    if(defined $Cache{"get_CmdPath"}{$Name}) {
        return $Cache{"get_CmdPath"}{$Name};
    }
    my %BinUtils = map {$_=>1} (
        "c++filt",
        "objdump",
        "readelf"
    );
    if($BinUtils{$Name} and $GCC_PATH)
    {
        if(my $Dir = get_dirname($GCC_PATH)) {
            $TargetTools{$Dir}=1;
        }
    }
    my $Path = search_Tools($Name);
    if(not $Path and $OSgroup eq "windows") {
        $Path = search_Tools($Name.".exe");
    }
    if(not $Path and $BinUtils{$Name})
    {
        if($CrossPrefix)
        { # user-defined prefix
            $Path = search_Cmd($CrossPrefix."-".$Name);
        }
    }
    if(not $Path and $BinUtils{$Name})
    {
        if(my $Candidate = synch_Cmd($Name))
        { # synch with GCC
            if($Candidate=~/[\/\\]/)
            { # command path
                if(-f $Candidate) {
                    $Path = $Candidate;
                }
            }
            elsif($Candidate = search_Cmd($Candidate))
            { # command name
                $Path = $Candidate;
            }
        }
    }
    if(not $Path) {
        $Path = search_Cmd($Name);
    }
    if(not $Path and $OSgroup eq "windows")
    { # search for *.exe file
        $Path=search_Cmd($Name.".exe");
    }
    if($Path=~/\s/) {
        $Path = "\"".$Path."\"";
    }
    return ($Cache{"get_CmdPath"}{$Name}=$Path);
}

sub search_Cmd($)
{
    my $Name = $_[0];
    return "" if(not $Name);
    if(defined $Cache{"search_Cmd"}{$Name}) {
        return $Cache{"search_Cmd"}{$Name};
    }
    if(my $DefaultPath = get_CmdPath_Default($Name)) {
        return ($Cache{"search_Cmd"}{$Name} = $DefaultPath);
    }
    foreach my $Path (@{$SystemPaths{"bin"}})
    {
        my $CmdPath = join_P($Path,$Name);
        if(-f $CmdPath)
        {
            if($Name=~/gcc/) {
                next if(not check_gcc($CmdPath, "3"));
            }
            return ($Cache{"search_Cmd"}{$Name} = $CmdPath);
        }
    }
    return ($Cache{"search_Cmd"}{$Name} = "");
}

sub get_CmdPath_Default($)
{ # search in PATH
    return "" if(not $_[0]);
    if(defined $Cache{"get_CmdPath_Default"}{$_[0]}) {
        return $Cache{"get_CmdPath_Default"}{$_[0]};
    }
    return ($Cache{"get_CmdPath_Default"}{$_[0]} = get_CmdPath_Default_I($_[0]));
}

sub get_CmdPath_Default_I($)
{ # search in PATH
    my $Name = $_[0];
    if($Name=~/find/)
    { # special case: search for "find" utility
        if(`find \"$TMP_DIR\" -maxdepth 0 2>\"$TMP_DIR/null\"`) {
            return "find";
        }
    }
    elsif($Name=~/gcc/) {
        return check_gcc($Name, "3");
    }
    if(checkCmd($Name)) {
        return $Name;
    }
    if($OSgroup eq "windows")
    {
        if(`$Name /? 2>\"$TMP_DIR/null\"`) {
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

sub classifyPath($)
{
    my $Path = $_[0];
    if($Path=~/[\*\+\(\[\|]/)
    { # pattern
        $Path=~s/\\/\\\\/g;
        return ($Path, "Pattern");
    }
    elsif($Path=~/[\/\\]/)
    { # directory or relative path
        return (path_format($Path, $OSgroup), "Path");
    }
    else {
        return ($Path, "Name");
    }
}

sub readDescriptor($$)
{
    my ($LibVersion, $Content) = @_;
    return if(not $LibVersion);
    my $DName = $DumpAPI?"descriptor":"descriptor \"d$LibVersion\"";
    if(not $Content) {
        exitStatus("Error", "$DName is empty");
    }
    if($Content!~/\</) {
        exitStatus("Error", "incorrect descriptor (see -d1 option)");
    }
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    
    $Descriptor{$LibVersion}{"Version"} = parseTag(\$Content, "version");
    if($TargetVersion{$LibVersion}) {
        $Descriptor{$LibVersion}{"Version"} = $TargetVersion{$LibVersion};
    }
    if(not $Descriptor{$LibVersion}{"Version"}) {
        exitStatus("Error", "version in the $DName is not specified (<version> section)");
    }
    if($Content=~/{RELPATH}/)
    {
        if(my $RelDir = $RelativeDirectory{$LibVersion}) {
            $Content =~ s/{RELPATH}/$RelDir/g;
        }
        else
        {
            my $NeedRelpath = $DumpAPI?"-relpath":"-relpath$LibVersion";
            exitStatus("Error", "you have not specified $NeedRelpath option, but the $DName contains {RELPATH} macro");
        }
    }
    
    my $DHeaders = parseTag(\$Content, "headers");
    if(not $DHeaders) {
        exitStatus("Error", "header files in the $DName are not specified (<headers> section)");
    }
    elsif(lc($DHeaders) ne "none")
    { # append the descriptor headers list
        if($Descriptor{$LibVersion}{"Headers"})
        { # multiple descriptors
            $Descriptor{$LibVersion}{"Headers"} .= "\n".$DHeaders;
        }
        else {
            $Descriptor{$LibVersion}{"Headers"} = $DHeaders;
        }
        foreach my $Path (split(/\s*\n\s*/, $DHeaders))
        {
            if(not -e $Path) {
                exitStatus("Access_Error", "can't access \'$Path\'");
            }
        }
    }
    
    if(not $CheckHeadersOnly_Opt)
    {
        my $DObjects = parseTag(\$Content, "libs");
        if(not $DObjects) {
            exitStatus("Error", "$SLIB_TYPE libraries in the $DName are not specified (<libs> section)");
        }
        elsif(lc($DObjects) ne "none")
        { # append the descriptor libraries list
            if($Descriptor{$LibVersion}{"Libs"})
            { # multiple descriptors
                $Descriptor{$LibVersion}{"Libs"} .= "\n".$DObjects;
            }
            else {
                $Descriptor{$LibVersion}{"Libs"} .= $DObjects;
            }
            foreach my $Path (split(/\s*\n\s*/, $DObjects))
            {
                if(not -e $Path) {
                    exitStatus("Access_Error", "can't access \'$Path\'");
                }
            }
        }
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_headers")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        push_U($SystemPaths{"include"}, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_libs")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        push_U($SystemPaths{"lib"}, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "tools")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        push_U($SystemPaths{"bin"}, $Path);
        $TargetTools{$Path}=1;
    }
    if(my $Prefix = parseTag(\$Content, "cross_prefix")) {
        $CrossPrefix = $Prefix;
    }
    $Descriptor{$LibVersion}{"IncludePaths"} = [] if(not defined $Descriptor{$LibVersion}{"IncludePaths"}); # perl 5.8 doesn't support //=
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "include_paths")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        push(@{$Descriptor{$LibVersion}{"IncludePaths"}}, $Path);
    }
    $Descriptor{$LibVersion}{"AddIncludePaths"} = [] if(not defined $Descriptor{$LibVersion}{"AddIncludePaths"});
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "add_include_paths")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        push(@{$Descriptor{$LibVersion}{"AddIncludePaths"}}, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_include_paths")))
    { # skip some auto-generated include paths
        if(not is_abs($Path))
        {
            if(my $P = abs_path($Path)) {
                $Path = $P;
            }
        }
        $Skip_Include_Paths{$LibVersion}{path_format($Path)} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_including")))
    { # skip direct including of some headers
        my ($CPath, $Type) = classifyPath($Path);
        $SkipHeaders{$LibVersion}{$Type}{$CPath} = 2;
    }
    $Descriptor{$LibVersion}{"GccOptions"} = parseTag(\$Content, "gcc_options");
    foreach my $Option (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"GccOptions"}))
    {
        if($Option!~/\A\-(Wl|l|L)/)
        { # skip linker options
            $CompilerOptions{$LibVersion} .= " ".$Option;
        }
    }
    $Descriptor{$LibVersion}{"SkipHeaders"} = parseTag(\$Content, "skip_headers");
    foreach my $Path (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"SkipHeaders"}))
    {
        $SkipHeadersList{$LibVersion}{$Path} = 1;
        
        my ($CPath, $Type) = classifyPath($Path);
        $SkipHeaders{$LibVersion}{$Type}{$CPath} = 1;
    }
    $Descriptor{$LibVersion}{"SkipLibs"} = parseTag(\$Content, "skip_libs");
    foreach my $Path (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"SkipLibs"}))
    {
        my ($CPath, $Type) = classifyPath($Path);
        $SkipLibs{$LibVersion}{$Type}{$CPath} = 1;
    }
    if(my $DDefines = parseTag(\$Content, "defines"))
    {
        if($Descriptor{$LibVersion}{"Defines"})
        { # multiple descriptors
            $Descriptor{$LibVersion}{"Defines"} .= "\n".$DDefines;
        }
        else {
            $Descriptor{$LibVersion}{"Defines"} = $DDefines;
        }
    }
    foreach my $Order (split(/\s*\n\s*/, parseTag(\$Content, "include_order")))
    {
        if($Order=~/\A(.+):(.+)\Z/) {
            $Include_Order{$LibVersion}{$1} = $2;
        }
    }
    foreach my $Type_Name (split(/\s*\n\s*/, parseTag(\$Content, "opaque_types")),
    split(/\s*\n\s*/, parseTag(\$Content, "skip_types")))
    { # opaque_types renamed to skip_types (1.23.4)
        $SkipTypes{$LibVersion}{$Type_Name} = 1;
    }
    foreach my $Symbol (split(/\s*\n\s*/, parseTag(\$Content, "skip_interfaces")),
    split(/\s*\n\s*/, parseTag(\$Content, "skip_symbols")))
    { # skip_interfaces renamed to skip_symbols (1.22.1)
        $SkipSymbols{$LibVersion}{$Symbol} = 1;
    }
    foreach my $NameSpace (split(/\s*\n\s*/, parseTag(\$Content, "skip_namespaces"))) {
        $SkipNameSpaces{$LibVersion}{$NameSpace} = 1;
    }
    foreach my $NameSpace (split(/\s*\n\s*/, parseTag(\$Content, "add_namespaces"))) {
        $AddNameSpaces{$LibVersion}{$NameSpace} = 1;
    }
    foreach my $Constant (split(/\s*\n\s*/, parseTag(\$Content, "skip_constants"))) {
        $SkipConstants{$LibVersion}{$Constant} = 1;
    }
    if(my $DIncPreamble = parseTag(\$Content, "include_preamble"))
    {
        if($Descriptor{$LibVersion}{"IncludePreamble"})
        { # multiple descriptors
            $Descriptor{$LibVersion}{"IncludePreamble"} .= "\n".$DIncPreamble;
        }
        else {
            $Descriptor{$LibVersion}{"IncludePreamble"} = $DIncPreamble;
        }
    }
}

sub parseTag(@)
{
    my $CodeRef = shift(@_);
    my $Tag = shift(@_);
    if(not $Tag or not $CodeRef) {
        return undef;
    }
    my $Sp = 0;
    if(@_) {
        $Sp = shift(@_);
    }
    my $Start = index(${$CodeRef}, "<$Tag>");
    if($Start!=-1)
    {
        my $End = index(${$CodeRef}, "</$Tag>");
        if($End!=-1)
        {
            my $TS = length($Tag)+3;
            my $Content = substr(${$CodeRef}, $Start, $End-$Start+$TS, "");
            substr($Content, 0, $TS-1, ""); # cut start tag
            substr($Content, -$TS, $TS, ""); # cut end tag
            if(not $Sp)
            {
                $Content=~s/\A\s+//g;
                $Content=~s/\s+\Z//g;
            }
            if(substr($Content, 0, 1) ne "<") {
                $Content = xmlSpecChars_R($Content);
            }
            return $Content;
        }
    }
    return undef;
}

sub getInfo($)
{
    my $DumpPath = $_[0];
    return if(not $DumpPath or not -f $DumpPath);
    
    readTUDump($DumpPath);
    
    # processing info
    setTemplateParams_All();
    
    if($ExtraDump) {
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
    
    if($ExtraDump)
    {
        remove_Unused($Version, "Extra");
    }
    else
    { # remove unused types
        if($BinaryOnly and not $ExtendedCheck)
        { # --binary
            remove_Unused($Version, "All");
        }
        else {
            remove_Unused($Version, "Extended");
        }
    }
    
    if($CheckInfo)
    {
        foreach my $Tid (keys(%{$TypeInfo{$Version}})) {
            check_Completeness($TypeInfo{$Version}{$Tid}, $Version);
        }
        
        foreach my $Sid (keys(%{$SymbolInfo{$Version}})) {
            check_Completeness($SymbolInfo{$Version}{$Sid}, $Version);
        }
    }
    
    if($Debug) {
        # debugMangling($Version);
    }
}

sub readTUDump($)
{
    my $DumpPath = $_[0];
    
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
            $LibInfo{$Version}{"info_type"}{$1}=$2;
            $LibInfo{$Version}{"info"}{$1}=$3." ";
        }
        
        # clean memory
        delete($Lines[$_]);
    }
    
    # clean memory
    undef @Lines;
}

sub simplifyConstants()
{
    foreach my $Constant (keys(%{$Constants{$Version}}))
    {
        if(defined $Constants{$Version}{$Constant}{"Header"})
        {
            my $Value = $Constants{$Version}{$Constant}{"Value"};
            if(defined $EnumConstants{$Version}{$Value}) {
                $Constants{$Version}{$Constant}{"Value"} = $EnumConstants{$Version}{$Value}{"Value"};
            }
        }
    }
}

sub simplifyNames()
{
    foreach my $Base (keys(%{$Typedef_Tr{$Version}}))
    {
        if($Typedef_Eq{$Version}{$Base}) {
            next;
        }
        my @Translations = sort keys(%{$Typedef_Tr{$Version}{$Base}});
        if($#Translations==0)
        {
            if(length($Translations[0])<=length($Base)) {
                $Typedef_Eq{$Version}{$Base} = $Translations[0];
            }
        }
        else
        { # select most appropriate
            foreach my $Tr (@Translations)
            {
                if($Base=~/\A\Q$Tr\E/)
                {
                    $Typedef_Eq{$Version}{$Base} = $Tr;
                    last;
                }
            }
        }
    }
    foreach my $TypeId (keys(%{$TypeInfo{$Version}}))
    {
        my $TypeName = $TypeInfo{$Version}{$TypeId}{"Name"};
        if(not $TypeName) {
            next;
        }
        next if(index($TypeName,"<")==-1);# template instances only
        if($TypeName=~/>(::\w+)+\Z/)
        { # skip unused types
            next;
        }
        foreach my $Base (sort {length($b)<=>length($a)}
        sort {$b cmp $a} keys(%{$Typedef_Eq{$Version}}))
        {
            next if(not $Base);
            next if(index($TypeName,$Base)==-1);
            next if(length($TypeName) - length($Base) <= 3);
            if(my $Typedef = $Typedef_Eq{$Version}{$Base})
            {
                $TypeName=~s/(\<|\,)\Q$Base\E(\W|\Z)/$1$Typedef$2/g;
                $TypeName=~s/(\<|\,)\Q$Base\E(\w|\Z)/$1$Typedef $2/g;
                if(defined $TypeInfo{$Version}{$TypeId}{"TParam"})
                {
                    foreach my $TPos (keys(%{$TypeInfo{$Version}{$TypeId}{"TParam"}}))
                    {
                        if(my $TPName = $TypeInfo{$Version}{$TypeId}{"TParam"}{$TPos}{"name"})
                        {
                            $TPName=~s/\A\Q$Base\E(\W|\Z)/$Typedef$1/g;
                            $TPName=~s/\A\Q$Base\E(\w|\Z)/$Typedef $1/g;
                            $TypeInfo{$Version}{$TypeId}{"TParam"}{$TPos}{"name"} = formatName($TPName, "T");
                        }
                    }
                }
            }
        }
        $TypeName = formatName($TypeName, "T");
        $TypeInfo{$Version}{$TypeId}{"Name"} = $TypeName;
        $TName_Tid{$Version}{$TypeName} = $TypeId;
    }
}

sub setAnonTypedef_All()
{
    foreach my $InfoId (keys(%{$LibInfo{$Version}{"info"}}))
    {
        if($LibInfo{$Version}{"info_type"}{$InfoId} eq "type_decl")
        {
            if(isAnon(getNameByInfo($InfoId))) {
                $TypedefToAnon{getTypeId($InfoId)} = 1;
            }
        }
    }
}

sub setTemplateParams_All()
{
    foreach (keys(%{$LibInfo{$Version}{"info"}}))
    {
        if($LibInfo{$Version}{"info_type"}{$_} eq "template_decl") {
            setTemplateParams($_);
        }
    }
}

sub setTemplateParams($)
{
    my $Tid = getTypeId($_[0]);
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/(inst|spcs)[ ]*:[ ]*@(\d+) /)
        {
            my $TmplInst_Id = $2;
            setTemplateInstParams($_[0], $TmplInst_Id);
            while($TmplInst_Id = getNextElem($TmplInst_Id)) {
                setTemplateInstParams($_[0], $TmplInst_Id);
            }
        }
        
        $BasicTemplate{$Version}{$Tid} = $_[0];
        
        if(my $Prms = getTreeAttr_Prms($_[0]))
        {
            if(my $Valu = getTreeAttr_Valu($Prms))
            {
                my $Vector = getTreeVec($Valu);
                foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$Vector}))
                {
                    if(my $Val = getTreeAttr_Valu($Vector->{$Pos}))
                    {
                        if(my $Name = getNameByInfo($Val))
                        {
                            $TemplateArg{$Version}{$_[0]}{$Pos} = $Name;
                            if($LibInfo{$Version}{"info_type"}{$Val} eq "parm_decl") {
                                $TemplateInstance{$Version}{"Type"}{$Tid}{$Pos} = $Val;
                            }
                            else {
                                $TemplateInstance{$Version}{"Type"}{$Tid}{$Pos} = getTreeAttr_Type($Val);
                            }
                        }
                    }
                }
            }
        }
    }
    if(my $TypeId = getTreeAttr_Type($_[0]))
    {
        if(my $IType = $LibInfo{$Version}{"info_type"}{$TypeId})
        {
            if($IType eq "record_type") {
                $TemplateDecl{$Version}{$TypeId} = 1;
            }
        }
    }
}

sub setTemplateInstParams($$)
{
    my ($Tmpl, $Inst) = @_;
    
    if(my $Info = $LibInfo{$Version}{"info"}{$Inst})
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
            my $Params_Info = $LibInfo{$Version}{"info"}{$Params_InfoId};
            while($Params_Info=~s/ (\d+)[ ]*:[ ]*\@(\d+) / /)
            {
                my ($PPos, $PTypeId) = ($1, $2);
                if(my $PType = $LibInfo{$Version}{"info_type"}{$PTypeId})
                {
                    if($PType eq "template_type_parm") {
                        $TemplateDecl{$Version}{$ElemId} = 1;
                    }
                }
                if($LibInfo{$Version}{"info_type"}{$ElemId} eq "function_decl")
                { # functions
                    $TemplateInstance{$Version}{"Func"}{$ElemId}{$PPos} = $PTypeId;
                    $BasicTemplate{$Version}{$ElemId} = $Tmpl;
                }
                else
                { # types
                    $TemplateInstance{$Version}{"Type"}{$ElemId}{$PPos} = $PTypeId;
                    $BasicTemplate{$Version}{$ElemId} = $Tmpl;
                }
            }
        }
    }
}

sub getTypeDeclId($)
{
    if($_[0])
    {
        if(defined $Cache{"getTypeDeclId"}{$Version}{$_[0]}) {
            return $Cache{"getTypeDeclId"}{$Version}{$_[0]};
        }
        if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
        {
            if($Info=~/name[ ]*:[ ]*@(\d+)/) {
                return ($Cache{"getTypeDeclId"}{$Version}{$_[0]} = $1);
            }
        }
    }
    return ($Cache{"getTypeDeclId"}{$Version}{$_[0]} = 0);
}

sub getTypeInfo_All()
{
    if(not check_gcc($GCC_PATH, "4.5"))
    { # support for GCC < 4.5
      # missed typedefs: QStyle::State is typedef to QFlags<QStyle::StateFlag>
      # but QStyleOption.state is of type QFlags<QStyle::StateFlag> in the TU dump
      # FIXME: check GCC versions
        addMissedTypes_Pre();
    }
    
    foreach (sort {int($a)<=>int($b)} keys(%{$LibInfo{$Version}{"info"}}))
    { # forward order only
        my $IType = $LibInfo{$Version}{"info_type"}{$_};
        if($IType=~/_type\Z/ and $IType ne "function_type"
        and $IType ne "method_type") {
            getTypeInfo("$_");
        }
    }
    
    # add "..." type
    $TypeInfo{$Version}{"-1"} = {
        "Name" => "...",
        "Type" => "Intrinsic",
        "Tid" => "-1"
    };
    $TName_Tid{$Version}{"..."} = "-1";
    
    if(not check_gcc($GCC_PATH, "4.5"))
    { # support for GCC < 4.5
        addMissedTypes_Post();
    }
    
    if($ADD_TMPL_INSTANCES)
    {
        # templates
        foreach my $Tid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$Version}}))
        {
            if(defined $TemplateMap{$Version}{$Tid}
            and not defined $TypeInfo{$Version}{$Tid}{"Template"})
            {
                if(defined $TypeInfo{$Version}{$Tid}{"Memb"})
                {
                    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$Version}{$Tid}{"Memb"}}))
                    {
                        if(my $MembTypeId = $TypeInfo{$Version}{$Tid}{"Memb"}{$Pos}{"type"})
                        {
                            if(my %MAttr = getTypeAttr($MembTypeId))
                            {
                                $TypeInfo{$Version}{$Tid}{"Memb"}{$Pos}{"algn"} = $MAttr{"Algn"};
                                $MembTypeId = $TypeInfo{$Version}{$Tid}{"Memb"}{$Pos}{"type"} = instType($TemplateMap{$Version}{$Tid}, $MembTypeId, $Version);
                            }
                        }
                    }
                }
                if(defined $TypeInfo{$Version}{$Tid}{"Base"})
                {
                    foreach my $Bid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$Version}{$Tid}{"Base"}}))
                    {
                        my $NBid = instType($TemplateMap{$Version}{$Tid}, $Bid, $Version);
                        
                        if($NBid ne $Bid
                        and $NBid ne $Tid)
                        {
                            %{$TypeInfo{$Version}{$Tid}{"Base"}{$NBid}} = %{$TypeInfo{$Version}{$Tid}{"Base"}{$Bid}};
                            delete($TypeInfo{$Version}{$Tid}{"Base"}{$Bid});
                        }
                    }
                }
            }
        }
    }
}

sub createType($$)
{
    my ($Attr, $LibVersion) = @_;
    my $NewId = ++$MAX_ID;
    
    $Attr->{"Tid"} = $NewId;
    $TypeInfo{$Version}{$NewId} = $Attr;
    $TName_Tid{$Version}{formatName($Attr->{"Name"}, "T")} = $NewId;
    
    return "$NewId";
}

sub instType($$$)
{ # create template instances
    my ($Map, $Tid, $LibVersion) = @_;
    
    if(not $TypeInfo{$LibVersion}{$Tid}) {
        return undef;
    }
    my $Attr = dclone($TypeInfo{$LibVersion}{$Tid});
    
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
        foreach (sort {int($a)<=>int($b)} keys(%{$Attr->{"TParam"}}))
        {
            my $PName = $Attr->{"TParam"}{$_}{"name"};
            
            if(my $PTid = $TName_Tid{$LibVersion}{$PName})
            {
                my %Base = get_BaseType($PTid, $LibVersion);
                
                if($Base{"Type"} eq "TemplateParam"
                or defined $Base{"Template"})
                {
                    $Tmpl = 1;
                    last
                }
            }
        }
    }
    
    if(my $Id = getTypeIdByName($Attr->{"Name"}, $LibVersion)) {
        return "$Id";
    }
    else
    {
        if(not $Tmpl) {
            delete($Attr->{"Template"});
        }
        
        my $New = createType($Attr, $LibVersion);
        
        my %EMap = ();
        if(defined $TemplateMap{$LibVersion}{$Tid}) {
            %EMap = %{$TemplateMap{$LibVersion}{$Tid}};
        }
        foreach (keys(%{$Map})) {
            $EMap{$_} = $Map->{$_};
        }
        
        if(defined $TypeInfo{$LibVersion}{$New}{"BaseType"}) {
            $TypeInfo{$LibVersion}{$New}{"BaseType"} = instType(\%EMap, $TypeInfo{$LibVersion}{$New}{"BaseType"}, $LibVersion);
        }
        if(defined $TypeInfo{$LibVersion}{$New}{"Base"})
        {
            foreach my $Bid (keys(%{$TypeInfo{$LibVersion}{$New}{"Base"}}))
            {
                my $NBid = instType(\%EMap, $Bid, $LibVersion);
                
                if($NBid ne $Bid
                and $NBid ne $New)
                {
                    %{$TypeInfo{$LibVersion}{$New}{"Base"}{$NBid}} = %{$TypeInfo{$LibVersion}{$New}{"Base"}{$Bid}};
                    delete($TypeInfo{$LibVersion}{$New}{"Base"}{$Bid});
                }
            }
        }
        
        if(defined $TypeInfo{$LibVersion}{$New}{"Memb"})
        {
            foreach (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}{$New}{"Memb"}}))
            {
                if(defined $TypeInfo{$LibVersion}{$New}{"Memb"}{$_}{"type"}) {
                    $TypeInfo{$LibVersion}{$New}{"Memb"}{$_}{"type"} = instType(\%EMap, $TypeInfo{$LibVersion}{$New}{"Memb"}{$_}{"type"}, $LibVersion);
                }
            }
        }
        
        if(defined $TypeInfo{$LibVersion}{$New}{"Param"})
        {
            foreach (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}{$New}{"Param"}})) {
                $TypeInfo{$LibVersion}{$New}{"Param"}{$_}{"type"} = instType(\%EMap, $TypeInfo{$LibVersion}{$New}{"Param"}{$_}{"type"}, $LibVersion);
            }
        }
        
        if(defined $TypeInfo{$LibVersion}{$New}{"Return"}) {
            $TypeInfo{$LibVersion}{$New}{"Return"} = instType(\%EMap, $TypeInfo{$LibVersion}{$New}{"Return"}, $LibVersion);
        }
        
        return $New;
    }
}

sub addMissedTypes_Pre()
{
    my %MissedTypes = ();
    foreach my $MissedTDid (sort {int($a)<=>int($b)} keys(%{$LibInfo{$Version}{"info"}}))
    { # detecting missed typedefs
        if($LibInfo{$Version}{"info_type"}{$MissedTDid} eq "type_decl")
        {
            my $TypeId = getTreeAttr_Type($MissedTDid);
            next if(not $TypeId);
            my $TypeType = getTypeType($TypeId);
            if($TypeType eq "Unknown")
            { # template_type_parm
                next;
            }
            my $TypeDeclId = getTypeDeclId($TypeId);
            next if($TypeDeclId eq $MissedTDid);#or not $TypeDeclId
            my $TypedefName = getNameByInfo($MissedTDid);
            next if(not $TypedefName);
            next if($TypedefName eq "__float80");
            next if(isAnon($TypedefName));
            if(not $TypeDeclId
            or getNameByInfo($TypeDeclId) ne $TypedefName) {
                $MissedTypes{$Version}{$TypeId}{$MissedTDid} = 1;
            }
        }
    }
    my %AddTypes = ();
    foreach my $Tid (keys(%{$MissedTypes{$Version}}))
    { # add missed typedefs
        my @Missed = keys(%{$MissedTypes{$Version}{$Tid}});
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
            if(get_depth($TypedefName)==0 and get_depth($TName)!=0)
            { # std::_Vector_base and std::vector::_Base
                next;
            }
        }
        
        $AddTypes{$MissedInfo{"Tid"}} = \%MissedInfo;
        
        # register typedef
        $MissedTypedef{$Version}{$Tid}{"Tid"} = $MissedInfo{"Tid"};
        $MissedTypedef{$Version}{$Tid}{"TDid"} = $MissedTDid;
        $TName_Tid{$Version}{$TypedefName} = $MissedInfo{"Tid"};
    }
    
    # add missed & remove other
    $TypeInfo{$Version} = \%AddTypes;
    delete($Cache{"getTypeAttr"}{$Version});
}

sub addMissedTypes_Post()
{
    foreach my $BaseId (keys(%{$MissedTypedef{$Version}}))
    {
        if(my $Tid = $MissedTypedef{$Version}{$BaseId}{"Tid"})
        {
            $TypeInfo{$Version}{$Tid}{"Size"} = $TypeInfo{$Version}{$BaseId}{"Size"};
            if(my $TName = $TypeInfo{$Version}{$Tid}{"Name"}) {
                $Typedef_BaseName{$Version}{$TName} = $TypeInfo{$Version}{$BaseId}{"Name"};
            }
        }
    }
}

sub getTypeInfo($)
{
    my $TypeId = $_[0];
    %{$TypeInfo{$Version}{$TypeId}} = getTypeAttr($TypeId);
    my $TName = $TypeInfo{$Version}{$TypeId}{"Name"};
    if(not $TName) {
        delete($TypeInfo{$Version}{$TypeId});
    }
}

sub getArraySize($$)
{
    my ($TypeId, $BaseName) = @_;
    if(my $Size = getSize($TypeId))
    {
        my $Elems = $Size/$BYTE_SIZE;
        while($BaseName=~s/\s*\[(\d+)\]//) {
            $Elems/=$1;
        }
        if(my $BasicId = $TName_Tid{$Version}{$BaseName})
        {
            if(my $BasicSize = $TypeInfo{$Version}{$BasicId}{"Size"}) {
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
    my @Positions = sort {int($a)<=>int($b)} keys(%{$TemplateInstance{$Version}{$Kind}{$TypeId}});
    foreach my $Pos (@Positions)
    {
        my $Param_TypeId = $TemplateInstance{$Version}{$Kind}{$TypeId}{$Pos};
        my $NodeType = $LibInfo{$Version}{"info_type"}{$Param_TypeId};
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
        my @Params = get_TemplateParam($Pos, $Param_TypeId);
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

sub getTypeAttr($)
{
    my $TypeId = $_[0];
    my %TypeAttr = ();
    if(defined $TypeInfo{$Version}{$TypeId}
    and $TypeInfo{$Version}{$TypeId}{"Name"})
    { # already created
        return %{$TypeInfo{$Version}{$TypeId}};
    }
    elsif($Cache{"getTypeAttr"}{$Version}{$TypeId})
    { # incomplete type
        return ();
    }
    $Cache{"getTypeAttr"}{$Version}{$TypeId} = 1;
    
    my $TypeDeclId = getTypeDeclId($TypeId);
    $TypeAttr{"Tid"} = $TypeId;
    
    if(not $MissedBase{$Version}{$TypeId} and isTypedef($TypeId))
    {
        if(my $Info = $LibInfo{$Version}{"info"}{$TypeId})
        {
            if($Info=~/qual[ ]*:/)
            {
                my $NewId = ++$MAX_ID;
                
                $MissedBase{$Version}{$TypeId} = "$NewId";
                $MissedBase_R{$Version}{$NewId} = $TypeId;
                $LibInfo{$Version}{"info"}{$NewId} = $LibInfo{$Version}{"info"}{$TypeId};
                $LibInfo{$Version}{"info_type"}{$NewId} = $LibInfo{$Version}{"info_type"}{$TypeId};
            }
        }
        $TypeAttr{"Type"} = "Typedef";
    }
    else {
        $TypeAttr{"Type"} = getTypeType($TypeId);
    }
    
    if(my $ScopeId = getTreeAttr_Scpe($TypeDeclId))
    {
        if($LibInfo{$Version}{"info_type"}{$ScopeId} eq "function_decl")
        { # local code
            return ();
        }
    }
    
    if($TypeAttr{"Type"} eq "Unknown") {
        return ();
    }
    elsif($TypeAttr{"Type"}=~/(Func|Method|Field)Ptr/)
    {
        %TypeAttr = getMemPtrAttr(pointTo($TypeId), $TypeId, $TypeAttr{"Type"});
        if(my $TName = $TypeAttr{"Name"})
        {
            %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
            $TName_Tid{$Version}{$TName} = $TypeId;
            return %TypeAttr;
        }
        else {
            return ();
        }
    }
    elsif($TypeAttr{"Type"} eq "Array")
    {
        my ($BTid, $BTSpec) = selectBaseType($TypeId);
        if(not $BTid) {
            return ();
        }
        if(my $Algn = getAlgn($TypeId)) {
            $TypeAttr{"Algn"} = $Algn/$BYTE_SIZE;
        }
        $TypeAttr{"BaseType"} = $BTid;
        if(my %BTAttr = getTypeAttr($BTid))
        {
            if(not $BTAttr{"Name"}) {
                return ();
            }
            if(my $NElems = getArraySize($TypeId, $BTAttr{"Name"}))
            {
                if(my $Size = getSize($TypeId)) {
                    $TypeAttr{"Size"} = $Size/$BYTE_SIZE;
                }
                if($BTAttr{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                    $TypeAttr{"Name"} = $1."[$NElems]".$2;
                }
                else {
                    $TypeAttr{"Name"} = $BTAttr{"Name"}."[$NElems]";
                }
            }
            else
            {
                $TypeAttr{"Size"} = $WORD_SIZE{$Version}; # pointer
                if($BTAttr{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                    $TypeAttr{"Name"} = $1."[]".$2;
                }
                else {
                    $TypeAttr{"Name"} = $BTAttr{"Name"}."[]";
                }
            }
            $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}, "T");
            if($BTAttr{"Header"})  {
                $TypeAttr{"Header"} = $BTAttr{"Header"};
            }
            %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
            $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
            return %TypeAttr;
        }
        return ();
    }
    elsif($TypeAttr{"Type"}=~/\A(Intrinsic|Union|Struct|Enum|Class|Vector)\Z/)
    {
        %TypeAttr = getTrivialTypeAttr($TypeId);
        if($TypeAttr{"Name"})
        {
            %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
            
            if(not defined $IntrinsicNames{$TypeAttr{"Name"}}
            or getTypeDeclId($TypeAttr{"Tid"}))
            { # NOTE: register only one int: with built-in decl
                if(not $TName_Tid{$Version}{$TypeAttr{"Name"}}) {
                    $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
                }
            }
            return %TypeAttr;
        }
        else {
            return ();
        }
    }
    elsif($TypeAttr{"Type"}=~/TemplateParam|TypeName/)
    {
        %TypeAttr = getTrivialTypeAttr($TypeId);
        if($TypeAttr{"Name"})
        {
            %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
            if(not $TName_Tid{$Version}{$TypeAttr{"Name"}}) {
                $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
            }
            return %TypeAttr;
        }
        else {
            return ();
        }
    }
    elsif($TypeAttr{"Type"} eq "SizeOf")
    {
        $TypeAttr{"BaseType"} = getTreeAttr_Type($TypeId);
        my %BTAttr = getTypeAttr($TypeAttr{"BaseType"});
        $TypeAttr{"Name"} = "sizeof(".$BTAttr{"Name"}.")";
        if($TypeAttr{"Name"})
        {
            %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
            return %TypeAttr;
        }
        else {
            return ();
        }
    }
    else
    { # derived types
        my ($BTid, $BTSpec) = selectBaseType($TypeId);
        if(not $BTid) {
            return ();
        }
        $TypeAttr{"BaseType"} = $BTid;
        if(defined $MissedTypedef{$Version}{$BTid})
        {
            if(my $MissedTDid = $MissedTypedef{$Version}{$BTid}{"TDid"})
            {
                if($MissedTDid ne $TypeDeclId) {
                    $TypeAttr{"BaseType"} = $MissedTypedef{$Version}{$BTid}{"Tid"};
                }
            }
        }
        my %BTAttr = getTypeAttr($TypeAttr{"BaseType"});
        if(not $BTAttr{"Name"})
        { # templates
            return ();
        }
        if($BTAttr{"Type"} eq "Typedef")
        { # relinking typedefs
            my %BaseBase = get_Type($BTAttr{"BaseType"}, $Version);
            if($BTAttr{"Name"} eq $BaseBase{"Name"}) {
                $TypeAttr{"BaseType"} = $BaseBase{"Tid"};
            }
        }
        if($BTSpec)
        {
            if($TypeAttr{"Type"} eq "Pointer"
            and $BTAttr{"Name"}=~/\([\*]+\)/)
            {
                $TypeAttr{"Name"} = $BTAttr{"Name"};
                $TypeAttr{"Name"}=~s/\(([*]+)\)/($1*)/g;
            }
            else {
                $TypeAttr{"Name"} = $BTAttr{"Name"}." ".$BTSpec;
            }
        }
        else {
            $TypeAttr{"Name"} = $BTAttr{"Name"};
        }
        if($TypeAttr{"Type"} eq "Typedef")
        {
            $TypeAttr{"Name"} = getNameByInfo($TypeDeclId);
            
            if(index($TypeAttr{"Name"}, "tmp_add_type")==0) {
                return ();
            }
            
            if(isAnon($TypeAttr{"Name"}))
            { # anon typedef to anon type: ._N
                return ();
            }
            
            if($LibInfo{$Version}{"info"}{$TypeDeclId}=~/ artificial /i)
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
                        if($BTAttr{"NameSpace"}
                        and $BTAttr{"NameSpace"}=~/\Astd(::|\Z)/ and $BTAttr{"Name"}=~/</)
                        { # types like "std::fpos<__mbstate_t>" are
                          # not covered by typedefs in the TU dump
                          # so trying to add such typedefs manually
                            $StdCxxTypedef{$Version}{$BTAttr{"Name"}}{$TypeAttr{"Name"}} = 1;
                            if(length($TypeAttr{"Name"})<=length($BTAttr{"Name"}))
                            {
                                if(($BTAttr{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/))
                                { # skip "other" in "std" and "type" in "boost"
                                    $Typedef_Eq{$Version}{$BTAttr{"Name"}} = $TypeAttr{"Name"};
                                }
                            }
                        }
                    }
                }
            }
            if($TypeAttr{"Name"} ne $BTAttr{"Name"} and not $TypeAttr{"Artificial"}
            and $TypeAttr{"Name"}!~/>(::\w+)+\Z/ and $BTAttr{"Name"}!~/>(::\w+)+\Z/)
            {
                if(not defined $Typedef_BaseName{$Version}{$TypeAttr{"Name"}})
                { # typedef int*const TYPEDEF; // first
                  # int foo(TYPEDEF p); // const is optimized out
                    $Typedef_BaseName{$Version}{$TypeAttr{"Name"}} = $BTAttr{"Name"};
                    if($BTAttr{"Name"}=~/</)
                    {
                        if(($BTAttr{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/)) {
                            $Typedef_Tr{$Version}{$BTAttr{"Name"}}{$TypeAttr{"Name"}} = 1;
                        }
                    }
                }
            }
            ($TypeAttr{"Header"}, $TypeAttr{"Line"}) = getLocation($TypeDeclId);
        }
        if(not $TypeAttr{"Size"})
        {
            if($TypeAttr{"Type"} eq "Pointer") {
                $TypeAttr{"Size"} = $WORD_SIZE{$Version};
            }
            elsif($BTAttr{"Size"}) {
                $TypeAttr{"Size"} = $BTAttr{"Size"};
            }
        }
        if(my $Algn = getAlgn($TypeId)) {
            $TypeAttr{"Algn"} = $Algn/$BYTE_SIZE;
        }
        $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}, "T");
        if(not $TypeAttr{"Header"} and $BTAttr{"Header"})  {
            $TypeAttr{"Header"} = $BTAttr{"Header"};
        }
        %{$TypeInfo{$Version}{$TypeId}} = %TypeAttr;
        if($TypeAttr{"Name"} ne $BTAttr{"Name"})
        { # typedef to "class Class"
          # should not be registered in TName_Tid
            if(not $TName_Tid{$Version}{$TypeAttr{"Name"}}) {
                $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
            }
        }
        return %TypeAttr;
    }
}

sub getTreeVec($)
{
    my %Vector = ();
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        while($Info=~s/ (\d+)[ ]*:[ ]*\@(\d+) / /)
        { # string length is N-1 because of the null terminator
            $Vector{$1} = $2;
        }
    }
    return \%Vector;
}

sub get_TemplateParam($$)
{
    my ($Pos, $Type_Id) = @_;
    return () if(not $Type_Id);
    my $NodeType = $LibInfo{$Version}{"info_type"}{$Type_Id};
    return () if(not $NodeType);
    if($NodeType eq "integer_cst")
    { # int (1), unsigned (2u), char ('c' as 99), ...
        my $CstTid = getTreeAttr_Type($Type_Id);
        my %CstType = getTypeAttr($CstTid); # without recursion
        my $Num = getNodeIntCst($Type_Id);
        if(my $CstSuffix = $ConstantSuffix{$CstType{"Name"}}) {
            return ($Num.$CstSuffix);
        }
        else {
            return ("(".$CstType{"Name"}.")".$Num);
        }
    }
    elsif($NodeType eq "string_cst") {
        return (getNodeStrCst($Type_Id));
    }
    elsif($NodeType eq "tree_vec")
    {
        my $Vector = getTreeVec($Type_Id);
        my @Params = ();
        foreach my $P1 (sort {int($a)<=>int($b)} keys(%{$Vector}))
        {
            foreach my $P2 (get_TemplateParam($Pos, $Vector->{$P1})) {
                push(@Params, $P2);
            }
        }
        return @Params;
    }
    elsif($NodeType eq "parm_decl")
    {
        (getNameByInfo($Type_Id));
    }
    else
    {
        my %ParamAttr = getTypeAttr($Type_Id);
        my $PName = $ParamAttr{"Name"};
        if(not $PName) {
            return ();
        }
        if($PName=~/\>/)
        {
            if(my $Cover = cover_stdcxx_typedef($PName)) {
                $PName = $Cover;
            }
        }
        if($Pos>=1 and
        $PName=~/\A$DEFAULT_STD_PARMS\</)
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

sub cover_stdcxx_typedef($)
{
    my $TypeName = $_[0];
    if(my @Covers = sort {length($a)<=>length($b)}
    sort keys(%{$StdCxxTypedef{$Version}{$TypeName}}))
    { # take the shortest typedef
      # FIXME: there may be more than
      # one typedefs to the same type
        return $Covers[0];
    }
    my $Covered = $TypeName;
    while($TypeName=~s/(>)[ ]*(const|volatile|restrict| |\*|\&)\Z/$1/g){};
    if(my @Covers = sort {length($a)<=>length($b)} sort keys(%{$StdCxxTypedef{$Version}{$TypeName}}))
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
    if($EnumMembName_Id{$Version}{$CstId}) {
        return $EnumMembName_Id{$Version}{$CstId};
    }
    elsif((my $Value = getTreeValue($CstId)) ne "")
    {
        if($Value eq "0")
        {
            if($LibInfo{$Version}{"info_type"}{$CstTypeId} eq "boolean_type") {
                return "false";
            }
            else {
                return "0";
            }
        }
        elsif($Value eq "1")
        {
            if($LibInfo{$Version}{"info_type"}{$CstTypeId} eq "boolean_type") {
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/strg[ ]*: (.+) lngt:[ ]*(\d+)/)
        { 
            if($LibInfo{$Version}{"info_type"}{$_[0]} eq "string_cst")
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
    my $MemInfo = $LibInfo{$Version}{"info"}{$PtrId};
    if($Type eq "FieldPtr") {
        $MemInfo = $LibInfo{$Version}{"info"}{$TypeId};
    }
    my $MemInfo_Type = $LibInfo{$Version}{"info_type"}{$PtrId};
    my $MemPtrName = "";
    my %TypeAttr = ("Size"=>$WORD_SIZE{$Version}, "Type"=>$Type, "Tid"=>$TypeId);
    if($Type eq "MethodPtr")
    { # size of "method pointer" may be greater than WORD size
        if(my $Size = getSize($TypeId))
        {
            $Size/=$BYTE_SIZE;
            $TypeAttr{"Size"} = "$Size";
        }
    }
    if(my $Algn = getAlgn($TypeId)) {
        $TypeAttr{"Algn"} = $Algn/$BYTE_SIZE;
    }
    # Return
    if($Type eq "FieldPtr")
    {
        my %ReturnAttr = getTypeAttr($PtrId);
        if($ReturnAttr{"Name"}) {
            $MemPtrName .= $ReturnAttr{"Name"};
        }
        $TypeAttr{"Return"} = $PtrId;
    }
    else
    {
        if($MemInfo=~/retn[ ]*:[ ]*\@(\d+) /)
        {
            my $ReturnTypeId = $1;
            my %ReturnAttr = getTypeAttr($ReturnTypeId);
            if(not $ReturnAttr{"Name"})
            { # templates
                return ();
            }
            $MemPtrName .= $ReturnAttr{"Name"};
            $TypeAttr{"Return"} = $ReturnTypeId;
        }
    }
    # Class
    if($MemInfo=~/(clas|cls)[ ]*:[ ]*@(\d+) /)
    {
        $TypeAttr{"Class"} = $2;
        my %Class = getTypeAttr($TypeAttr{"Class"});
        if($Class{"Name"}) {
            $MemPtrName .= " (".$Class{"Name"}."\:\:*)";
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
                my $PTypeInfo = $LibInfo{$Version}{"info"}{$PTypeInfoId};
                if($PTypeInfo=~/valu[ ]*:[ ]*@(\d+) /)
                {
                    my $PTypeId = $1;
                    my %ParamAttr = getTypeAttr($PTypeId);
                    if(not $ParamAttr{"Name"})
                    { # templates (template_type_parm), etc.
                        return ();
                    }
                    if($ParamAttr{"Name"} eq "void") {
                        last;
                    }
                    if($Pos!=0 or $Type ne "MethodPtr")
                    {
                        $TypeAttr{"Param"}{$PPos++}{"type"} = $PTypeId;
                        push(@ParamTypeName, $ParamAttr{"Name"});
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
    return %TypeAttr;
}

sub getTreeTypeName($)
{
    my $TypeId = $_[0];
    if(my $Info = $LibInfo{$Version}{"info"}{$TypeId})
    {
        if($LibInfo{$Version}{"info_type"}{$_[0]} eq "integer_type")
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
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/unql[ ]*:/ and $Info!~/qual[ ]*:/) {
            return 0;
        }
    }
    if(my $InfoT1 = $LibInfo{$Version}{"info_type"}{$_[0]}
    and my $InfoT2 = $LibInfo{$Version}{"info_type"}{$Ptd})
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
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($LibInfo{$Version}{"info_type"}{$_[0]} eq "record_type"
        and $LibInfo{$Version}{"info_type"}{$Ptd} eq "method_type"
        and $Info=~/ ptrmem /) {
            return 1;
        }
    }
    return 0;
}

sub isFieldPtr($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($LibInfo{$Version}{"info_type"}{$_[0]} eq "offset_type"
        and $Info=~/ ptrmem /) {
            return 1;
        }
    }
    return 0;
}

sub pointTo($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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
    if(my $TType = $LibInfo{$Version}{"info_type"}{$TypeId})
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

my %UnQual = (
    "r"=>"restrict",
    "v"=>"volatile",
    "c"=>"const",
    "cv"=>"const volatile"
);

sub getQual($)
{
    my $TypeId = $_[0];
    if(my $Info = $LibInfo{$Version}{"info"}{$TypeId})
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
    if(defined $MissedTypedef{$Version}{$TypeId})
    { # support for old GCC versions
        if($MissedTypedef{$Version}{$TypeId}{"TDid"} eq $TypeDeclId) {
            return "Typedef";
        }
    }
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    my ($Qual, $To) = getQual($TypeId);
    if(($Qual or $To) and $TypeDeclId
    and (getTypeId($TypeDeclId) ne $TypeId))
    { # qualified types (special)
        return getQualType($Qual);
    }
    elsif(not $MissedBase_R{$Version}{$TypeId}
    and isTypedef($TypeId)) {
        return "Typedef";
    }
    elsif($Qual)
    { # qualified types
        return getQualType($Qual);
    }
    
    if($Info=~/unql[ ]*:[ ]*\@(\d+)/)
    { # typedef struct { ... } name
        $TypeTypedef{$Version}{$TypeId} = $1;
    }
    
    my $TypeType = getTypeTypeByTypeId($TypeId);
    if($TypeType eq "Struct")
    {
        if($TypeDeclId
        and $LibInfo{$Version}{"info_type"}{$TypeDeclId} eq "template_decl") {
            return "Template";
        }
    }
    return $TypeType;
}

sub isTypedef($)
{
    if($_[0])
    {
        if($LibInfo{$Version}{"info_type"}{$_[0]} eq "vector_type")
        { # typedef float La_x86_64_xmm __attribute__ ((__vector_size__ (16)));
            return 0;
        }
        if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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
    if(defined $MissedTypedef{$Version}{$TypeId})
    { # add missed typedefs
        if($MissedTypedef{$Version}{$TypeId}{"TDid"} eq getTypeDeclId($TypeId)) {
            return ($TypeId, "");
        }
    }
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    my $InfoType = $LibInfo{$Version}{"info_type"}{$TypeId};
    
    my $MB_R = $MissedBase_R{$Version}{$TypeId};
    my $MB = $MissedBase{$Version}{$TypeId};
    
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

sub getSymbolInfo_All()
{
    foreach (sort {int($b)<=>int($a)} keys(%{$LibInfo{$Version}{"info"}}))
    { # reverse order
        if($LibInfo{$Version}{"info_type"}{$_} eq "function_decl") {
            getSymbolInfo($_);
        }
    }
    
    if($ADD_TMPL_INSTANCES)
    {
        # templates
        foreach my $Sid (sort {int($a)<=>int($b)} keys(%{$SymbolInfo{$Version}}))
        {
            my %Map = ();
            
            if(my $ClassId = $SymbolInfo{$Version}{$Sid}{"Class"})
            {
                if(defined $TemplateMap{$Version}{$ClassId})
                {
                    foreach (keys(%{$TemplateMap{$Version}{$ClassId}})) {
                        $Map{$_} = $TemplateMap{$Version}{$ClassId}{$_};
                    }
                }
            }
            
            if(defined $TemplateMap{$Version}{$Sid})
            {
                foreach (keys(%{$TemplateMap{$Version}{$Sid}})) {
                    $Map{$_} = $TemplateMap{$Version}{$Sid}{$_};
                }
            }
            
            if(defined $SymbolInfo{$Version}{$Sid}{"Param"})
            {
                foreach (keys(%{$SymbolInfo{$Version}{$Sid}{"Param"}}))
                {
                    my $PTid = $SymbolInfo{$Version}{$Sid}{"Param"}{$_}{"type"};
                    $SymbolInfo{$Version}{$Sid}{"Param"}{$_}{"type"} = instType(\%Map, $PTid, $Version);
                }
            }
            if(my $Return = $SymbolInfo{$Version}{$Sid}{"Return"}) {
                $SymbolInfo{$Version}{$Sid}{"Return"} = instType(\%Map, $Return, $Version);
            }
        }
    }
}

sub getVarInfo_All()
{
    foreach (sort {int($b)<=>int($a)} keys(%{$LibInfo{$Version}{"info"}}))
    { # reverse order
        if($LibInfo{$Version}{"info_type"}{$_} eq "var_decl") {
            getVarInfo($_);
        }
    }
}

sub isBuiltIn($) {
    return ($_[0] and $_[0]=~/\<built\-in\>|\<internal\>|\A\./);
}

sub getVarInfo($)
{
    my $InfoId = $_[0];
    if(my $NSid = getTreeAttr_Scpe($InfoId))
    {
        my $NSInfoType = $LibInfo{$Version}{"info_type"}{$NSid};
        if($NSInfoType and $NSInfoType eq "function_decl") {
            return;
        }
    }
    ($SymbolInfo{$Version}{$InfoId}{"Header"}, $SymbolInfo{$Version}{$InfoId}{"Line"}) = getLocation($InfoId);
    if(not $SymbolInfo{$Version}{$InfoId}{"Header"}
    or isBuiltIn($SymbolInfo{$Version}{$InfoId}{"Header"})) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    my $ShortName = getTreeStr(getTreeAttr_Name($InfoId));
    if(not $ShortName) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if($ShortName=~/\Atmp_add_class_\d+\Z/) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    $SymbolInfo{$Version}{$InfoId}{"ShortName"} = $ShortName;
    if(my $MnglName = getTreeStr(getTreeAttr_Mngl($InfoId)))
    {
        if($OSgroup eq "windows")
        { # cut the offset
            $MnglName=~s/\@\d+\Z//g;
        }
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $MnglName;
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}
    and index($SymbolInfo{$Version}{$InfoId}{"MnglName"}, "_Z")!=0)
    { # validate mangled name
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"}
    and index($ShortName, "_Z")==0)
    { # _ZTS, etc.
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
    }
    if(isPrivateData($SymbolInfo{$Version}{$InfoId}{"MnglName"}))
    { # non-public global data
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    $SymbolInfo{$Version}{$InfoId}{"Data"} = 1;
    if(my $Rid = getTypeId($InfoId))
    {
        if(not defined $TypeInfo{$Version}{$Rid}
        or not $TypeInfo{$Version}{$Rid}{"Name"})
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
        $SymbolInfo{$Version}{$InfoId}{"Return"} = $Rid;
        my $Val = getDataVal($InfoId, $Rid);
        if(defined $Val) {
            $SymbolInfo{$Version}{$InfoId}{"Value"} = $Val;
        }
    }
    set_Class_And_Namespace($InfoId);
    if(my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if(not defined $TypeInfo{$Version}{$ClassId}
        or not $TypeInfo{$Version}{$ClassId}{"Name"})
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if($LibInfo{$Version}{"info"}{$InfoId}=~/ lang:[ ]*C /i)
    { # extern "C"
        $SymbolInfo{$Version}{$InfoId}{"Lang"} = "C";
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
    }
    if($UserLang and $UserLang eq "C")
    { # --lang=C option
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
    }
    if(not $CheckHeadersOnly)
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"Class"})
        {
            if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"}
            or not link_symbol($SymbolInfo{$Version}{$InfoId}{"MnglName"}, $Version, "-Deps"))
            {
                if(link_symbol($ShortName, $Version, "-Deps"))
                { # "const" global data is mangled as _ZL... in the TU dump
                  # but not mangled when compiling a C shared library
                    $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
                }
            }
        }
    }
    if($COMMON_LANGUAGE{$Version} eq "C++")
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
        { # for some symbols (_ZTI) the short name is the mangled name
            if(index($ShortName, "_Z")==0) {
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
            }
        }
        if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
        { # try to mangle symbol (link with libraries)
            $SymbolInfo{$Version}{$InfoId}{"MnglName"} = linkSymbol($InfoId);
        }
        if($OStarget eq "windows")
        {
            if(my $Mangled = $mangled_name{$Version}{modelUnmangled($InfoId, "MSVC")})
            { # link MS C++ symbols from library with GCC symbols from headers
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $Mangled;
            }
        }
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"}) {
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
    }
    if(my $Symbol = $SymbolInfo{$Version}{$InfoId}{"MnglName"})
    {
        if(not selectSymbol($Symbol, $SymbolInfo{$Version}{$InfoId}, "Dump", $Version))
        { # non-target symbols
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if(my $Rid = $SymbolInfo{$Version}{$InfoId}{"Return"})
    {
        if(defined $MissedTypedef{$Version}{$Rid})
        {
            if(my $AddedTid = $MissedTypedef{$Version}{$Rid}{"Tid"}) {
                $SymbolInfo{$Version}{$InfoId}{"Return"} = $AddedTid;
            }
        }
    }
    setFuncAccess($InfoId);
    if(index($SymbolInfo{$Version}{$InfoId}{"MnglName"}, "_ZTV")==0) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    if($ShortName=~/\A(_Z|\?)/) {
        delete($SymbolInfo{$Version}{$InfoId}{"ShortName"});
    }
    
    if($ExtraDump) {
        $SymbolInfo{$Version}{$InfoId}{"Header"} = guessHeader($InfoId);
    }
}

sub isConstType($$)
{
    my ($TypeId, $LibVersion) = @_;
    my %Base = get_Type($TypeId, $LibVersion);
    while(defined $Base{"Type"} and $Base{"Type"} eq "Typedef") {
        %Base = get_OneStep_BaseType($Base{"Tid"}, $TypeInfo{$LibVersion});
    }
    return ($Base{"Type"} eq "Const");
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
    if(defined $TemplateInstance{$Version}{"Type"}{$TypeId}
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
    
    if($TemplateDecl{$Version}{$TypeId})
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
        return ();
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
    
    if(defined $TemplateInstance{$Version}{"Type"}{$TypeId})
    {
        $Tmpl = $BasicTemplate{$Version}{$TypeId};
        
        if(my @TParams = getTParams($TypeId, "Type"))
        {
            foreach my $Pos (0 .. $#TParams)
            {
                my $Val = $TParams[$Pos];
                $TypeAttr{"TParam"}{$Pos}{"name"} = $Val;
                
                if(not defined $TypeAttr{"Template"})
                {
                    my %Base = get_BaseType($TemplateInstance{$Version}{"Type"}{$TypeId}{$Pos}, $Version);
                    
                    if($Base{"Type"} eq "TemplateParam"
                    or defined $Base{"Template"}) {
                        $TypeAttr{"Template"} = 1;
                    }
                }
                
                if($Tmpl)
                {
                    if(my $Arg = $TemplateArg{$Version}{$Tmpl}{$Pos})
                    {
                        $TemplateMap{$Version}{$TypeId}{$Arg} = $Val;
                        
                        if($Val eq $Arg) {
                            $TypeAttr{"Template"} = 1;
                        }
                    }
                }
            }
            
            if($Tmpl)
            {
                foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$TemplateArg{$Version}{$Tmpl}}))
                {
                    if($Pos>$#TParams)
                    {
                        my $Arg = $TemplateArg{$Version}{$Tmpl}{$Pos};
                        $TemplateMap{$Version}{$TypeId}{$Arg} = "";
                    }
                }
            }
        }
        
        if($ADD_TMPL_INSTANCES)
        {
            if($Tmpl)
            {
                if(my $MainInst = getTreeAttr_Type($Tmpl))
                {
                    if(not getTreeAttr_Flds($TypeId))
                    {
                        if(my $Flds = getTreeAttr_Flds($MainInst)) {
                            $LibInfo{$Version}{"info"}{$TypeId} .= " flds: \@$Flds ";
                        }
                    }
                    if(not getTreeAttr_Binf($TypeId))
                    {
                        if(my $Binf = getTreeAttr_Binf($MainInst)) {
                            $LibInfo{$Version}{"info"}{$TypeId} .= " binf: \@$Binf ";
                        }
                    }
                }
            }
        }
    }
    
    my $StaticFields = setTypeMemb($TypeId, \%TypeAttr);
    
    if(my $Size = getSize($TypeId))
    {
        $Size = $Size/$BYTE_SIZE;
        $TypeAttr{"Size"} = "$Size";
    }
    else
    {
        if($ExtraDump)
        {
            if(not defined $TypeAttr{"Memb"}
            and not $Tmpl)
            { # declaration only
                $TypeAttr{"Forward"} = 1;
            }
        }
    }
    
    if($TypeAttr{"Type"} eq "Struct"
    and ($StaticFields or detect_lang($TypeId)))
    {
        $TypeAttr{"Type"} = "Class";
        $TypeAttr{"Copied"} = 1; # default, will be changed in getSymbolInfo()
    }
    if($TypeAttr{"Type"} eq "Struct"
    or $TypeAttr{"Type"} eq "Class")
    {
        my $Skip = setBaseClasses($TypeId, \%TypeAttr);
        if($Skip) {
            return ();
        }
    }
    if(my $Algn = getAlgn($TypeId)) {
        $TypeAttr{"Algn"} = $Algn/$BYTE_SIZE;
    }
    setSpec($TypeId, \%TypeAttr);
    
    if($TypeAttr{"Type"}=~/\A(Struct|Union|Enum)\Z/)
    {
        if(not $TypedefToAnon{$TypeId}
        and not defined $TemplateInstance{$Version}{"Type"}{$TypeId})
        {
            if(not isAnon($TypeAttr{"Name"})) {
                $TypeAttr{"Name"} = lc($TypeAttr{"Type"})." ".$TypeAttr{"Name"};
            }
        }
    }
    
    $TypeAttr{"Tid"} = $TypeId;
    if(my $VTable = $ClassVTable_Content{$Version}{$TypeAttr{"Name"}})
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
                $EnumConstants{$Version}{$MName} = {
                    "Value"=>$MVal,
                    "Header"=>$TypeAttr{"Header"}
                };
                if(isAnon($TypeAttr{"Name"}))
                {
                    if($ExtraDump
                    or is_target_header($TypeAttr{"Header"}, $Version))
                    {
                        %{$Constants{$Version}{$MName}} = (
                            "Value" => $MVal,
                            "Header" => $TypeAttr{"Header"}
                        );
                    }
                }
            }
        }
    }
    if($ExtraDump)
    {
        if(defined $TypedefToAnon{$TypeId}) {
            $TypeAttr{"AnonTypedef"} = 1;
        }
    }
    
    return %TypeAttr;
}

sub simplifyVTable($)
{
    my $Content = $_[0];
    if($Content=~s/ \[with (.+)]//)
    { # std::basic_streambuf<_CharT, _Traits>::imbue [with _CharT = char, _Traits = std::char_traits<char>]
        if(my @Elems = separate_Params($1, 0, 0))
        {
            foreach my $Elem (@Elems)
            {
                if($Elem=~/\A(.+?)\s*=\s*(.+?)\Z/)
                {
                    my ($Arg, $Val) = ($1, $2);
                    
                    if(defined $DEFAULT_STD_ARGS{$Arg}) {
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

sub detect_lang($)
{
    my $TypeId = $_[0];
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if(check_gcc($GCC_PATH, "4"))
    { # GCC 4 fncs-node points to only non-artificial methods
        return ($Info=~/(fncs)[ ]*:[ ]*@(\d+) /);
    }
    else
    { # GCC 3
        my $Fncs = getTreeAttr_Fncs($TypeId);
        while($Fncs)
        {
            if($LibInfo{$Version}{"info"}{$Fncs}!~/artificial/) {
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
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if($Info=~/\s+spec\s+/) {
        $TypeAttr->{"Spec"} = 1;
    }
}

sub setBaseClasses($$)
{
    my ($TypeId, $TypeAttr) = @_;
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if(my $Binf = getTreeAttr_Binf($TypeId))
    {
        my $Info = $LibInfo{$Version}{"info"}{$Binf};
        my $Pos = 0;
        while($Info=~s/(pub|public|prot|protected|priv|private|)[ ]+binf[ ]*:[ ]*@(\d+) //)
        {
            my ($Access, $BInfoId) = ($1, $2);
            my $ClassId = getBinfClassId($BInfoId);
            
            if($ClassId eq $TypeId)
            { # class A<N>:public A<N-1>
                next;
            }
            
            my $CType = $LibInfo{$Version}{"info_type"}{$ClassId};
            if(not $CType or $CType eq "template_type_parm"
            or $CType eq "typename_type")
            { # skip
                # return 1;
            }
            my $BaseInfo = $LibInfo{$Version}{"info"}{$BInfoId};
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
            $Class_SubClasses{$Version}{$ClassId}{$TypeId}=1;
            $Pos += 1;
        }
    }
    return 0;
}

sub getBinfClassId($)
{
    my $Info = $LibInfo{$Version}{"info"}{$_[0]};
    if($Info=~/type[ ]*:[ ]*@(\d+) /) {
        return $1;
    }
    
    return "";
}

sub unmangledFormat($$)
{
    my ($Name, $LibVersion) = @_;
    $Name = uncover_typedefs($Name, $LibVersion);
    while($Name=~s/([^\w>*])(const|volatile)(,|>|\Z)/$1$3/g){};
    $Name=~s/\(\w+\)(\d)/$1/;
    return $Name;
}

sub modelUnmangled($$)
{
    my ($InfoId, $Compiler) = @_;
    if($Cache{"modelUnmangled"}{$Version}{$Compiler}{$InfoId}) {
        return $Cache{"modelUnmangled"}{$Version}{$Compiler}{$InfoId};
    }
    my $PureSignature = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    if($SymbolInfo{$Version}{$InfoId}{"Destructor"}) {
        $PureSignature = "~".$PureSignature;
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Data"})
    {
        my (@Params, @ParamTypes) = ();
        if(defined $SymbolInfo{$Version}{$InfoId}{"Param"}
        and not $SymbolInfo{$Version}{$InfoId}{"Destructor"}) {
            @Params = keys(%{$SymbolInfo{$Version}{$InfoId}{"Param"}});
        }
        foreach my $ParamPos (sort {int($a) <=> int($b)} @Params)
        { # checking parameters
            my $PId = $SymbolInfo{$Version}{$InfoId}{"Param"}{$ParamPos}{"type"};
            my $PName = $SymbolInfo{$Version}{$InfoId}{"Param"}{$ParamPos}{"name"};
            my %PType = get_PureType($PId, $TypeInfo{$Version});
            my $PTName = unmangledFormat($PType{"Name"}, $Version);
            
            if($PName eq "this"
            and $SymbolInfo{$Version}{$InfoId}{"Type"} eq "Method")
            {
                next;
            }
            
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
            if($Compiler eq "MSVC")
            {
                $PureSignature .= "(void)";
            }
            else
            { # GCC
                $PureSignature .= "()";
            }
        }
        $PureSignature = delete_keywords($PureSignature);
    }
    if(my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        my $ClassName = unmangledFormat($TypeInfo{$Version}{$ClassId}{"Name"}, $Version);
        $PureSignature = $ClassName."::".$PureSignature;
    }
    elsif(my $NS = $SymbolInfo{$Version}{$InfoId}{"NameSpace"}) {
        $PureSignature = $NS."::".$PureSignature;
    }
    if($SymbolInfo{$Version}{$InfoId}{"Const"}) {
        $PureSignature .= " const";
    }
    if($SymbolInfo{$Version}{$InfoId}{"Volatile"}) {
        $PureSignature .= " volatile";
    }
    my $ShowReturn = 0;
    if($Compiler eq "MSVC"
    and $SymbolInfo{$Version}{$InfoId}{"Data"})
    {
        $ShowReturn=1;
    }
    elsif(defined $TemplateInstance{$Version}{"Func"}{$InfoId}
    and keys(%{$TemplateInstance{$Version}{"Func"}{$InfoId}}))
    {
        $ShowReturn=1;
    }
    if($ShowReturn)
    { # mangled names for template function specializations include return value
        if(my $ReturnId = $SymbolInfo{$Version}{$InfoId}{"Return"})
        {
            my %RType = get_PureType($ReturnId, $TypeInfo{$Version});
            my $ReturnName = unmangledFormat($RType{"Name"}, $Version);
            $PureSignature = $ReturnName." ".$PureSignature;
        }
    }
    return ($Cache{"modelUnmangled"}{$Version}{$Compiler}{$InfoId} = formatName($PureSignature, "S"));
}

sub mangle_symbol($$$)
{ # mangling for simple methods
  # see gcc-4.6.0/gcc/cp/mangle.c
    my ($InfoId, $LibVersion, $Compiler) = @_;
    if($Cache{"mangle_symbol"}{$LibVersion}{$InfoId}{$Compiler}) {
        return $Cache{"mangle_symbol"}{$LibVersion}{$InfoId}{$Compiler};
    }
    my $Mangled = "";
    if($Compiler eq "GCC") {
        $Mangled = mangle_symbol_GCC($InfoId, $LibVersion);
    }
    elsif($Compiler eq "MSVC") {
        $Mangled = mangle_symbol_MSVC($InfoId, $LibVersion);
    }
    return ($Cache{"mangle_symbol"}{$LibVersion}{$InfoId}{$Compiler} = $Mangled);
}

sub mangle_symbol_MSVC($$)
{ # TODO
    my ($InfoId, $LibVersion) = @_;
    return "";
}

sub mangle_symbol_GCC($$)
{ # see gcc-4.6.0/gcc/cp/mangle.c
    my ($InfoId, $LibVersion) = @_;
    my ($Mangled, $ClassId, $NameSpace) = ("_Z", 0, "");
    my $Return = $SymbolInfo{$LibVersion}{$InfoId}{"Return"};
    my %Repl = ();# SN_ replacements
    if($ClassId = $SymbolInfo{$LibVersion}{$InfoId}{"Class"})
    {
        my $MangledClass = mangle_param($ClassId, $LibVersion, \%Repl);
        if($MangledClass!~/\AN/) {
            $MangledClass = "N".$MangledClass;
        }
        else {
            $MangledClass=~s/E\Z//;
        }
        if($SymbolInfo{$LibVersion}{$InfoId}{"Volatile"}) {
            $MangledClass=~s/\AN/NV/;
        }
        if($SymbolInfo{$LibVersion}{$InfoId}{"Const"}) {
            $MangledClass=~s/\AN/NK/;
        }
        $Mangled .= $MangledClass;
    }
    elsif($NameSpace = $SymbolInfo{$LibVersion}{$InfoId}{"NameSpace"})
    { # mangled by name due to the absence of structured info
        my $MangledNS = mangle_ns($NameSpace, $LibVersion, \%Repl);
        if($MangledNS!~/\AN/) {
            $MangledNS = "N".$MangledNS;
        }
        else {
            $MangledNS=~s/E\Z//;
        }
        $Mangled .= $MangledNS;
    }
    my ($ShortName, $TmplParams) = template_Base($SymbolInfo{$LibVersion}{$InfoId}{"ShortName"});
    my @TParams = ();
    if(my @TPos = keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"TParam"}}))
    { # parsing mode
        foreach (@TPos) {
            push(@TParams, $SymbolInfo{$LibVersion}{$InfoId}{"TParam"}{$_}{"name"});
        }
    }
    elsif($TmplParams)
    { # remangling mode
      # support for old ABI dumps
        @TParams = separate_Params($TmplParams, 0, 0);
    }
    if($SymbolInfo{$LibVersion}{$InfoId}{"Constructor"}) {
        $Mangled .= "C1";
    }
    elsif($SymbolInfo{$LibVersion}{$InfoId}{"Destructor"}) {
        $Mangled .= "D0";
    }
    elsif($ShortName)
    {
        if($SymbolInfo{$LibVersion}{$InfoId}{"Data"})
        {
            if(not $SymbolInfo{$LibVersion}{$InfoId}{"Class"}
            and isConstType($Return, $LibVersion))
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
                $Mangled .= "cv".mangle_param(getTypeIdByName($Op, $LibVersion), $LibVersion, \%Repl);
            }
        }
        else {
            $Mangled .= length($ShortName).$ShortName;
        }
        if(@TParams)
        { # templates
            $Mangled .= "I";
            foreach my $TParam (@TParams) {
                $Mangled .= mangle_template_param($TParam, $LibVersion, \%Repl);
            }
            $Mangled .= "E";
        }
        if(not $ClassId and @TParams) {
            add_substitution($ShortName, \%Repl, 0);
        }
    }
    if($ClassId or $NameSpace) {
        $Mangled .= "E";
    }
    if(@TParams)
    {
        if($Return) {
            $Mangled .= mangle_param($Return, $LibVersion, \%Repl);
        }
    }
    if(not $SymbolInfo{$LibVersion}{$InfoId}{"Data"})
    {
        my @Params = ();
        if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"}
        and not $SymbolInfo{$LibVersion}{$InfoId}{"Destructor"}) {
            @Params = keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}});
        }
        foreach my $ParamPos (sort {int($a) <=> int($b)} @Params)
        { # checking parameters
            my $ParamType_Id = $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$ParamPos}{"type"};
            $Mangled .= mangle_param($ParamType_Id, $LibVersion, \%Repl);
        }
        if(not @Params) {
            $Mangled .= "v";
        }
    }
    $Mangled = correct_incharge($InfoId, $LibVersion, $Mangled);
    $Mangled = write_stdcxx_substitution($Mangled);
    if($Mangled eq "_Z") {
        return "";
    }
    return $Mangled;
}

sub correct_incharge($$$)
{
    my ($InfoId, $LibVersion, $Mangled) = @_;
    if($SymbolInfo{$LibVersion}{$InfoId}{"Constructor"})
    {
        if($MangledNames{$LibVersion}{$Mangled}) {
            $Mangled=~s/C1([EI])/C2$1/;
        }
    }
    elsif($SymbolInfo{$LibVersion}{$InfoId}{"Destructor"})
    {
        if($MangledNames{$LibVersion}{$Mangled}) {
            $Mangled=~s/D0([EI])/D1$1/;
        }
        if($MangledNames{$LibVersion}{$Mangled}) {
            $Mangled=~s/D1([EI])/D2$1/;
        }
    }
    return $Mangled;
}

sub template_Base($)
{ # NOTE: std::_Vector_base<mysqlpp::mysql_type_info>::_Vector_impl
  # NOTE: operators: >>, <<
    my $Name = $_[0];
    if($Name!~/>\Z/ or $Name!~/</) {
        return $Name;
    }
    my $TParams = $Name;
    while(my $CPos = find_center($TParams, "<"))
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

sub get_sub_ns($)
{
    my $Name = $_[0];
    my @NS = ();
    while(my $CPos = find_center($Name, ":"))
    {
        push(@NS, substr($Name, 0, $CPos));
        $Name = substr($Name, $CPos);
        $Name=~s/\A:://;
    }
    return (join("::", @NS), $Name);
}

sub mangle_ns($$$)
{
    my ($Name, $LibVersion, $Repl) = @_;
    if(my $Tid = $TName_Tid{$LibVersion}{$Name})
    {
        my $Mangled = mangle_param($Tid, $LibVersion, $Repl);
        $Mangled=~s/\AN(.+)E\Z/$1/;
        return $Mangled;
        
    }
    else
    {
        my ($MangledNS, $SubNS) = ("", "");
        ($SubNS, $Name) = get_sub_ns($Name);
        if($SubNS) {
            $MangledNS .= mangle_ns($SubNS, $LibVersion, $Repl);
        }
        $MangledNS .= length($Name).$Name;
        add_substitution($MangledNS, $Repl, 0);
        return $MangledNS;
    }
}

sub mangle_param($$$)
{
    my ($PTid, $LibVersion, $Repl) = @_;
    my ($MPrefix, $Mangled) = ("", "");
    my %ReplCopy = %{$Repl};
    my %BaseType = get_BaseType($PTid, $LibVersion);
    my $BaseType_Name = $BaseType{"Name"};
    $BaseType_Name=~s/\A(struct|union|enum) //g;
    if(not $BaseType_Name) {
        return "";
    }
    my ($ShortName, $TmplParams) = template_Base($BaseType_Name);
    my $Suffix = get_BaseTypeQual($PTid, $LibVersion);
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
        if(my @TPos = keys(%{$BaseType{"TParam"}}))
        { # parsing mode
            foreach (@TPos) {
                push(@TParams, $BaseType{"TParam"}{$_}{"name"});
            }
        }
        elsif($TmplParams)
        { # remangling mode
          # support for old ABI dumps
            @TParams = separate_Params($TmplParams, 0, 0);
        }
        my $MangledNS = "";
        my ($SubNS, $SName) = get_sub_ns($ShortName);
        if($SubNS) {
            $MangledNS .= mangle_ns($SubNS, $LibVersion, $Repl);
        }
        $MangledNS .= length($SName).$SName;
        if(@TParams) {
            add_substitution($MangledNS, $Repl, 0);
        }
        $Mangled .= "N".$MangledNS;
        if(@TParams)
        { # templates
            $Mangled .= "I";
            foreach my $TParam (@TParams) {
                $Mangled .= mangle_template_param($TParam, $LibVersion, $Repl);
            }
            $Mangled .= "E";
        }
        $Mangled .= "E";
    }
    elsif($BaseType{"Type"}=~/(FuncPtr|MethodPtr)/)
    {
        if($BaseType{"Type"} eq "MethodPtr") {
            $Mangled .= "M".mangle_param($BaseType{"Class"}, $LibVersion, $Repl)."F";
        }
        else {
            $Mangled .= "PF";
        }
        $Mangled .= mangle_param($BaseType{"Return"}, $LibVersion, $Repl);
        my @Params = keys(%{$BaseType{"Param"}});
        foreach my $Num (sort {int($a)<=>int($b)} @Params) {
            $Mangled .= mangle_param($BaseType{"Param"}{$Num}{"type"}, $LibVersion, $Repl);
        }
        if(not @Params) {
            $Mangled .= "v";
        }
        $Mangled .= "E";
    }
    elsif($BaseType{"Type"} eq "FieldPtr")
    {
        $Mangled .= "M".mangle_param($BaseType{"Class"}, $LibVersion, $Repl);
        $Mangled .= mangle_param($BaseType{"Return"}, $LibVersion, $Repl);
    }
    $Mangled = $MPrefix.$Mangled;# add prefix (RPK)
    if(my $Optimized = write_substitution($Mangled, \%ReplCopy))
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
    add_substitution($Mangled, $Repl, 1);
    return $Mangled;
}

sub mangle_template_param($$$)
{ # types + literals
    my ($TParam, $LibVersion, $Repl) = @_;
    if(my $TPTid = $TName_Tid{$LibVersion}{$TParam}) {
        return mangle_param($TPTid, $LibVersion, $Repl);
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

sub add_substitution($$$)
{
    my ($Value, $Repl, $Rec) = @_;
    if($Rec)
    { # subtypes
        my @Subs = ($Value);
        while($Value=~s/\A(R|P|K)//) {
            push(@Subs, $Value);
        }
        foreach (reverse(@Subs)) {
            add_substitution($_, $Repl, 0);
        }
        return;
    }
    return if($Value=~/\AS(\d*)_\Z/);
    $Value=~s/\AN(.+)E\Z/$1/g;
    return if(defined $Repl->{$Value});
    return if(length($Value)<=1);
    return if($StdcxxMangling{$Value});
    # check for duplicates
    my $Base = $Value;
    foreach my $Type (sort {$Repl->{$a}<=>$Repl->{$b}} sort keys(%{$Repl}))
    {
        my $Num = $Repl->{$Type};
        my $Replace = macro_mangle($Num);
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
        next if($Base eq $Type);
        my $Num = $Repl->{$Type};
        my $Replace = macro_mangle($Num);
        $Base=~s/\Q$Type\E/$Replace/;
        $Repl->{$Base} = $Repl->{$Value};
    }
}

sub macro_mangle($)
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

sub write_stdcxx_substitution($)
{
    my $Mangled = $_[0];
    if($StdcxxMangling{$Mangled}) {
        return $StdcxxMangling{$Mangled};
    }
    else
    {
        my @Repls = keys(%StdcxxMangling);
        @Repls = sort {length($b)<=>length($a)} sort {$b cmp $a} @Repls;
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

sub write_substitution($$)
{
    my ($Mangled, $Repl) = @_;
    if(defined $Repl->{$Mangled}
    and my $MnglNum = $Repl->{$Mangled}) {
        $Mangled = macro_mangle($MnglNum);
    }
    else
    {
        my @Repls = keys(%{$Repl});
        #@Repls = sort {$Repl->{$a}<=>$Repl->{$b}} @Repls;
        # FIXME: how to apply replacements? by num or by pos
        @Repls = sort {length($b)<=>length($a)} sort {$b cmp $a} @Repls;
        foreach my $MangledType (@Repls)
        {
            my $Replace = macro_mangle($Repl->{$MangledType});
            if($Mangled!~/$Replace/) {
                $Mangled=~s/N\Q$MangledType\EE/$Replace/g;
                $Mangled=~s/\Q$MangledType\E/$Replace/g;
            }
        }
    }
    return $Mangled;
}

sub delete_keywords($)
{
    my $TypeName = $_[0];
    $TypeName=~s/\b(enum|struct|union|class) //g;
    return $TypeName;
}

sub uncover_typedefs($$)
{
    my ($TypeName, $LibVersion) = @_;
    return "" if(not $TypeName);
    if(defined $Cache{"uncover_typedefs"}{$LibVersion}{$TypeName}) {
        return $Cache{"uncover_typedefs"}{$LibVersion}{$TypeName};
    }
    my ($TypeName_New, $TypeName_Pre) = (formatName($TypeName, "T"), "");
    while($TypeName_New ne $TypeName_Pre)
    {
        $TypeName_Pre = $TypeName_New;
        my $TypeName_Copy = $TypeName_New;
        my %Words = ();
        while($TypeName_Copy=~s/\b([a-z_]([\w:]*\w|))\b//io)
        {
            if(not $Intrinsic_Keywords{$1}) {
                $Words{$1} = 1;
            }
        }
        foreach my $Word (keys(%Words))
        {
            my $BaseType_Name = $Typedef_BaseName{$LibVersion}{$Word};
            next if(not $BaseType_Name);
            next if($TypeName_New=~/\b(struct|union|enum)\s\Q$Word\E\b/);
            if($BaseType_Name=~/\([\*]+\)/)
            { # FuncPtr
                if($TypeName_New=~/\Q$Word\E(.*)\Z/)
                {
                    my $Type_Suffix = $1;
                    $TypeName_New = $BaseType_Name;
                    if($TypeName_New=~s/\(([\*]+)\)/($1 $Type_Suffix)/) {
                        $TypeName_New = formatName($TypeName_New, "T");
                    }
                }
            }
            else
            {
                if($TypeName_New=~s/\b\Q$Word\E\b/$BaseType_Name/g) {
                    $TypeName_New = formatName($TypeName_New, "T");
                }
            }
        }
    }
    return ($Cache{"uncover_typedefs"}{$LibVersion}{$TypeName} = $TypeName_New);
}

sub isInternal($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/mngl[ ]*:[ ]*@(\d+) /)
        {
            if($LibInfo{$Version}{"info"}{$1}=~/\*[ ]*INTERNAL[ ]*\*/)
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
    if(my $Info = $LibInfo{$Version}{"info"}{$InfoId})
    {
        if($Info=~/init[ ]*:[ ]*@(\d+) /)
        {
            if(defined $LibInfo{$Version}{"info_type"}{$1}
            and $LibInfo{$Version}{"info_type"}{$1} eq "nop_expr")
            {
                if(my $Nop = getTreeAttr_Op($1))
                {
                    if(defined $LibInfo{$Version}{"info_type"}{$Nop}
                    and $LibInfo{$Version}{"info_type"}{$Nop} eq "addr_expr")
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
    if(my $Info = $LibInfo{$Version}{"info"}{$InfoId})
    {
        if(my $InfoType = $LibInfo{$Version}{"info_type"}{$InfoId})
        {
            if($InfoType eq "integer_cst")
            {
                my $Val = getNodeIntCst($InfoId);
                if($TypeId and $TypeInfo{$Version}{$TypeId}{"Name"}=~/\Achar(| const)\Z/)
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

sub set_Class_And_Namespace($)
{
    my $InfoId = $_[0];
    if(my $Info = $LibInfo{$Version}{"info"}{$InfoId})
    {
        if($Info=~/scpe[ ]*:[ ]*@(\d+) /)
        {
            my $NSInfoId = $1;
            if(my $InfoType = $LibInfo{$Version}{"info_type"}{$NSInfoId})
            {
                if($InfoType eq "namespace_decl") {
                    $SymbolInfo{$Version}{$InfoId}{"NameSpace"} = getNameSpace($InfoId);
                }
                elsif($InfoType eq "record_type") {
                    $SymbolInfo{$Version}{$InfoId}{"Class"} = $NSInfoId;
                }
            }
        }
    }
    if($SymbolInfo{$Version}{$InfoId}{"Class"}
    or $SymbolInfo{$Version}{$InfoId}{"NameSpace"})
    {
        if($COMMON_LANGUAGE{$Version} ne "C++")
        { # skip
            return 1;
        }
    }
    
    return 0;
}

sub debugMangling($)
{
    my $LibVersion = $_[0];
    my %Mangled = ();
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        if(my $Mngl = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"})
        {
            if($Mngl=~/\A(_Z|\?)/) {
                $Mangled{$Mngl}=$InfoId;
            }
        }
    }
    translateSymbols(keys(%Mangled), $LibVersion);
    foreach my $Mngl (keys(%Mangled))
    {
        my $U1 = modelUnmangled($Mangled{$Mngl}, "GCC");
        my $U2 = $tr_name{$Mngl};
        if($U1 ne $U2) {
            printMsg("INFO", "INCORRECT MANGLING:\n  $Mngl\n  $U1\n  $U2\n");
        }
    }
}

sub linkSymbol($)
{ # link symbols from shared libraries
  # with the symbols from header files
    my $InfoId = $_[0];
    # try to mangle symbol
    if((not check_gcc($GCC_PATH, "4") and $SymbolInfo{$Version}{$InfoId}{"Class"})
    or (check_gcc($GCC_PATH, "4") and not $SymbolInfo{$Version}{$InfoId}{"Class"})
    or $EMERGENCY_MODE_48)
    { # GCC 3.x doesn't mangle class methods names in the TU dump (only functions and global data)
      # GCC 4.x doesn't mangle C++ functions in the TU dump (only class methods) except extern "C" functions
      # GCC 4.8.[012] doesn't mangle anything
        if(not $CheckHeadersOnly)
        {
            if(my $Mangled = $mangled_name_gcc{modelUnmangled($InfoId, "GCC")}) {
                return correct_incharge($InfoId, $Version, $Mangled);
            }
        }
        if($CheckHeadersOnly
        or not $BinaryOnly
        or $EMERGENCY_MODE_48)
        { # 1. --headers-only mode
          # 2. not mangled src-only symbols
            if(my $Mangled = mangle_symbol($InfoId, $Version, "GCC")) {
                return $Mangled;
            }
        }
    }
    return "";
}

sub setLanguage($$)
{
    my ($LibVersion, $Lang) = @_;
    if(not $UserLang) {
        $COMMON_LANGUAGE{$LibVersion} = $Lang;
    }
}

sub getSymbolInfo($)
{
    my $InfoId = $_[0];
    if(isInternal($InfoId)) { 
        return;
    }
    ($SymbolInfo{$Version}{$InfoId}{"Header"}, $SymbolInfo{$Version}{$InfoId}{"Line"}) = getLocation($InfoId);
    if(not $SymbolInfo{$Version}{$InfoId}{"Header"}
    or isBuiltIn($SymbolInfo{$Version}{$InfoId}{"Header"}))
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    setFuncAccess($InfoId);
    setFuncKind($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"PseudoTemplate"})
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    
    $SymbolInfo{$Version}{$InfoId}{"Type"} = getFuncType($InfoId);
    if(my $Return = getFuncReturn($InfoId))
    {
        if(not defined $TypeInfo{$Version}{$Return}
        or not $TypeInfo{$Version}{$Return}{"Name"})
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
        $SymbolInfo{$Version}{$InfoId}{"Return"} = $Return;
    }
    if(my $Rid = $SymbolInfo{$Version}{$InfoId}{"Return"})
    {
        if(defined $MissedTypedef{$Version}{$Rid})
        {
            if(my $AddedTid = $MissedTypedef{$Version}{$Rid}{"Tid"}) {
                $SymbolInfo{$Version}{$InfoId}{"Return"} = $AddedTid;
            }
        }
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Return"}) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    my $Orig = getFuncOrig($InfoId);
    $SymbolInfo{$Version}{$InfoId}{"ShortName"} = getFuncShortName($Orig);
    if(index($SymbolInfo{$Version}{$InfoId}{"ShortName"}, "\._")!=-1)
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    
    if(index($SymbolInfo{$Version}{$InfoId}{"ShortName"}, "tmp_add_func")==0)
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    
    if(defined $TemplateInstance{$Version}{"Func"}{$Orig})
    {
        my $Tmpl = $BasicTemplate{$Version}{$InfoId};
        
        my @TParams = getTParams($Orig, "Func");
        if(not @TParams)
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
        foreach my $Pos (0 .. $#TParams)
        {
            my $Val = $TParams[$Pos];
            $SymbolInfo{$Version}{$InfoId}{"TParam"}{$Pos}{"name"} = $Val;
            
            if($Tmpl)
            {
                if(my $Arg = $TemplateArg{$Version}{$Tmpl}{$Pos})
                {
                    $TemplateMap{$Version}{$InfoId}{$Arg} = $Val;
                }
            }
        }
        
        if($Tmpl)
        {
            foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$TemplateArg{$Version}{$Tmpl}}))
            {
                if($Pos>$#TParams)
                {
                    my $Arg = $TemplateArg{$Version}{$Tmpl}{$Pos};
                    $TemplateMap{$Version}{$InfoId}{$Arg} = "";
                }
            }
        }
        
        if($SymbolInfo{$Version}{$InfoId}{"ShortName"}=~/\Aoperator\W+\Z/)
        { # operator<< <T>, operator>> <T>
            $SymbolInfo{$Version}{$InfoId}{"ShortName"} .= " ";
        }
        if(@TParams) {
            $SymbolInfo{$Version}{$InfoId}{"ShortName"} .= "<".join(", ", @TParams).">";
        }
        else {
            $SymbolInfo{$Version}{$InfoId}{"ShortName"} .= "<...>";
        }
        $SymbolInfo{$Version}{$InfoId}{"ShortName"} = formatName($SymbolInfo{$Version}{$InfoId}{"ShortName"}, "S");
    }
    else
    { # support for GCC 3.4
        $SymbolInfo{$Version}{$InfoId}{"ShortName"}=~s/<.+>\Z//;
    }
    if(my $MnglName = getTreeStr(getTreeAttr_Mngl($InfoId)))
    {
        if($OSgroup eq "windows")
        { # cut the offset
            $MnglName=~s/\@\d+\Z//g;
        }
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $MnglName;
        
        # NOTE: mangling of some symbols may change depending on GCC version
        # GCC 4.6: _ZN28QExplicitlySharedDataPointerI11QPixmapDataEC2IT_EERKS_IT_E
        # GCC 4.7: _ZN28QExplicitlySharedDataPointerI11QPixmapDataEC2ERKS1_
    }
    
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}
    and index($SymbolInfo{$Version}{$InfoId}{"MnglName"}, "_Z")!=0)
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Destructor"})
    { # destructors have an empty parameter list
        my $Skip = setFuncParams($InfoId);
        if($Skip)
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if($LibInfo{$Version}{"info"}{$InfoId}=~/ artificial /i) {
        $SymbolInfo{$Version}{$InfoId}{"Artificial"} = 1;
    }
    
    if(set_Class_And_Namespace($InfoId))
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    
    if(my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if(not defined $TypeInfo{$Version}{$ClassId}
        or not $TypeInfo{$Version}{$ClassId}{"Name"})
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if($LibInfo{$Version}{"info"}{$InfoId}=~/ lang:[ ]*C /i)
    { # extern "C"
        $SymbolInfo{$Version}{$InfoId}{"Lang"} = "C";
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    }
    if($UserLang and $UserLang eq "C")
    { # --lang=C option
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    }
    if($COMMON_LANGUAGE{$Version} eq "C++")
    { # correct mangled & short names
      # C++ or --headers-only mode
        if($SymbolInfo{$Version}{$InfoId}{"ShortName"}=~/\A__(comp|base|deleting)_(c|d)tor\Z/)
        { # support for old GCC versions: reconstruct real names for constructors and destructors
            $SymbolInfo{$Version}{$InfoId}{"ShortName"} = getNameByInfo(getTypeDeclId($SymbolInfo{$Version}{$InfoId}{"Class"}));
            $SymbolInfo{$Version}{$InfoId}{"ShortName"}=~s/<.+>\Z//;
        }
        if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
        { # try to mangle symbol (link with libraries)
            if(my $Mangled = linkSymbol($InfoId)) {
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $Mangled;
            }
        }
        if($OStarget eq "windows")
        { # link MS C++ symbols from library with GCC symbols from headers
            if(my $Mangled1 = $mangled_name{$Version}{modelUnmangled($InfoId, "MSVC")})
            { # exported symbols
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $Mangled1;
            }
            elsif(my $Mangled2 = mangle_symbol($InfoId, $Version, "MSVC"))
            { # pure virtual symbols
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $Mangled2;
            }
        }
    }
    else
    { # not mangled in C
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    }
    if(not $CheckHeadersOnly
    and $SymbolInfo{$Version}{$InfoId}{"Type"} eq "Function"
    and not $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        my $Incorrect = 0;
        
        if($SymbolInfo{$Version}{$InfoId}{"MnglName"})
        {
            if(index($SymbolInfo{$Version}{$InfoId}{"MnglName"}, "_Z")==0
            and not link_symbol($SymbolInfo{$Version}{$InfoId}{"MnglName"}, $Version, "-Deps"))
            { # mangled in the TU dump, but not mangled in the library
                $Incorrect = 1;
            }
        }
        else
        {
            if($SymbolInfo{$Version}{$InfoId}{"Lang"} ne "C")
            { # all C++ functions are not mangled in the TU dump
                $Incorrect = 1;
            }
        }
        if($Incorrect)
        {
            if(link_symbol($SymbolInfo{$Version}{$InfoId}{"ShortName"}, $Version, "-Deps")) {
                $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
            }
        }
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
    { # can't detect symbol name
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Constructor"}
    and my $Spec = getVirtSpec($Orig))
    { # identify virtual and pure virtual functions
      # NOTE: constructors cannot be virtual
      # NOTE: in GCC 4.7 D1 destructors have no virtual spec
      # in the TU dump, so taking it from the original symbol
        if(not ($SymbolInfo{$Version}{$InfoId}{"Destructor"}
        and $SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/D2E/))
        { # NOTE: D2 destructors are not present in a v-table
            $SymbolInfo{$Version}{$InfoId}{$Spec} = 1;
        }
    }
    if(isInline($InfoId)) {
        $SymbolInfo{$Version}{$InfoId}{"InLine"} = 1;
    }
    if(hasThrow($InfoId)) {
        $SymbolInfo{$Version}{$InfoId}{"Throw"} = 1;
    }
    if($SymbolInfo{$Version}{$InfoId}{"Constructor"}
    and my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"InLine"}
        and not $SymbolInfo{$Version}{$InfoId}{"Artificial"})
        { # inline or auto-generated constructor
            delete($TypeInfo{$Version}{$ClassId}{"Copied"});
        }
    }
    if(my $Symbol = $SymbolInfo{$Version}{$InfoId}{"MnglName"})
    {
        if(not $ExtraDump)
        {
            if(not selectSymbol($Symbol, $SymbolInfo{$Version}{$InfoId}, "Dump", $Version))
            { # non-target symbols
                delete($SymbolInfo{$Version}{$InfoId});
                return;
            }
        }
    }
    if($SymbolInfo{$Version}{$InfoId}{"Type"} eq "Method"
    or $SymbolInfo{$Version}{$InfoId}{"Constructor"}
    or $SymbolInfo{$Version}{$InfoId}{"Destructor"}
    or $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if($SymbolInfo{$Version}{$InfoId}{"MnglName"}!~/\A(_Z|\?)/)
        {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"})
    {
        if($MangledNames{$Version}{$SymbolInfo{$Version}{$InfoId}{"MnglName"}})
        { # one instance for one mangled name only
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
        else {
            $MangledNames{$Version}{$SymbolInfo{$Version}{$InfoId}{"MnglName"}} = 1;
        }
    }
    if($SymbolInfo{$Version}{$InfoId}{"Constructor"}
    or $SymbolInfo{$Version}{$InfoId}{"Destructor"}) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A(_Z|\?)/
    and $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if($SymbolInfo{$Version}{$InfoId}{"Type"} eq "Function")
        { # static methods
            $SymbolInfo{$Version}{$InfoId}{"Static"} = 1;
        }
    }
    if(getFuncLink($InfoId) eq "Static") {
        $SymbolInfo{$Version}{$InfoId}{"Static"} = 1;
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A(_Z|\?)/)
    {
        if(my $Unmangled = $tr_name{$SymbolInfo{$Version}{$InfoId}{"MnglName"}})
        {
            if($Unmangled=~/\.\_\d/)
            {
                delete($SymbolInfo{$Version}{$InfoId});
                return;
            }
        }
    }
    
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A_ZN(V|)K/) {
        $SymbolInfo{$Version}{$InfoId}{"Const"} = 1;
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A_ZN(K|)V/) {
        $SymbolInfo{$Version}{$InfoId}{"Volatile"} = 1;
    }
    
    if($WeakSymbols{$Version}{$SymbolInfo{$Version}{$InfoId}{"MnglName"}}) {
        $SymbolInfo{$Version}{$InfoId}{"Weak"} = 1;
    }
    
    if($ExtraDump) {
        $SymbolInfo{$Version}{$InfoId}{"Header"} = guessHeader($InfoId);
    }
}

sub guessHeader($)
{
    my $InfoId = $_[0];
    my $ShortName = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"};
    my $ClassName = $ClassId?get_ShortClass($ClassId, $Version):"";
    my $Header = $SymbolInfo{$Version}{$InfoId}{"Header"};
    if(my $HPath = $SymbolHeader{$Version}{$ClassName}{$ShortName})
    {
        if(get_filename($HPath) eq $Header)
        {
            my $HDir = get_filename(get_dirname($HPath));
            if($HDir ne "include"
            and $HDir=~/\A[a-z]+\Z/i) {
                return join_P($HDir, $Header);
            }
        }
    }
    return $Header;
}

sub isInline($)
{ # "body: undefined" in the tree
  # -fkeep-inline-functions GCC option should be specified
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/ undefined /i) {
            return 0;
        }
    }
    return 1;
}

sub hasThrow($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return getTreeAttr_Unql($1, "unql");
        }
    }
    return 1;
}

sub getTypeId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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
            $EnumMembName_Id{$Version}{getTreeAttr_Valu($MInfoId)} = ($TypeAttr->{"NameSpace"})?$TypeAttr->{"NameSpace"}."::".$MembName:$MembName;
            $MInfoId = getNextElem($MInfoId);
            $Pos += 1;
        }
    }
    elsif($TypeType=~/\A(Struct|Class|Union)\Z/)
    {
        my $MInfoId = getTreeAttr_Flds($TypeId);
        while($MInfoId)
        {
            my $IType = $LibInfo{$Version}{"info_type"}{$MInfoId};
            my $MInfo = $LibInfo{$Version}{"info"}{$MInfoId};
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
            if(defined $MissedTypedef{$Version}{$MembTypeId})
            {
                if(my $AddedTid = $MissedTypedef{$Version}{$MembTypeId}{"Tid"}) {
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
                    $TypeAttr->{"Memb"}{$Pos}{"algn"} /= $BYTE_SIZE;
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
    
    if($FType eq "Method")
    { # check type of "this" pointer
        my $ObjectTypeId = getTreeAttr_Type($ParamInfoId);
        if(my $ObjectName = $TypeInfo{$Version}{$ObjectTypeId}{"Name"})
        {
            if($ObjectName=~/\bconst(| volatile)\*const\b/) {
                $SymbolInfo{$Version}{$InfoId}{"Const"} = 1;
            }
            if($ObjectName=~/\bvolatile\b/) {
                $SymbolInfo{$Version}{$InfoId}{"Volatile"} = 1;
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
        if(defined $MissedTypedef{$Version}{$ParamTypeId})
        {
            if(my $AddedTid = $MissedTypedef{$Version}{$ParamTypeId}{"Tid"}) {
                $ParamTypeId = $AddedTid;
            }
        }
        my $PType = $TypeInfo{$Version}{$ParamTypeId}{"Type"};
        if(not $PType or $PType eq "Unknown") {
            return 1;
        }
        my $PTName = $TypeInfo{$Version}{$ParamTypeId}{"Name"};
        if(not $PTName) {
            return 1;
        }
        if($PTName eq "void") {
            last;
        }
        if($ParamName eq "__vtt_parm"
        and $TypeInfo{$Version}{$ParamTypeId}{"Name"} eq "void const**")
        {
            $Vtt_Pos = $Pos;
            $ParamInfoId = getNextElem($ParamInfoId);
            next;
        }
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"} = $ParamTypeId;
        
        if(my %Base = get_BaseType($ParamTypeId, $Version))
        {
            if(defined $Base{"Template"}) {
                return 1;
            }
        }
        
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"name"} = $ParamName;
        if(my $Algn = getAlgn($ParamInfoId)) {
            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"algn"} = $Algn/$BYTE_SIZE;
        }
        if($LibInfo{$Version}{"info"}{$ParamInfoId}=~/spec:\s*register /)
        { # foo(register type arg)
            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"reg"} = 1;
        }
        $ParamInfoId = getNextElem($ParamInfoId);
        $Pos += 1;
        if($ParamName ne "this" or $FType ne "Method") {
            $PPos += 1;
        }
    }
    if(setFuncArgs($InfoId, $Vtt_Pos)) {
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"} = "-1";
    }
    return 0;
}

sub setFuncArgs($$)
{
    my ($InfoId, $Vtt_Pos) = @_;
    my $FuncTypeId = getFuncTypeId($InfoId);
    my $ParamListElemId = getTreeAttr_Prms($FuncTypeId);
    my $FType = getFuncType($InfoId);
    
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
        if($TypeInfo{$Version}{$ParamTypeId}{"Name"} eq "void")
        {
            $HaveVoid = 1;
            last;
        }
        else
        {
            if(not defined $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"})
            {
                $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"} = $ParamTypeId;
                if(not $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"name"})
                { # unnamed
                    $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"name"} = "p".($PPos+1);
                }
            }
            elsif(my $OldId = $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"})
            {
                if($Pos>0 or getFuncType($InfoId) ne "Method")
                { # params
                    if($OldId ne $ParamTypeId)
                    {
                        my %Old_Pure = get_PureType($OldId, $TypeInfo{$Version});
                        my %New_Pure = get_PureType($ParamTypeId, $TypeInfo{$Version});
                        
                        if($Old_Pure{"Name"} ne $New_Pure{"Name"}) {
                            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"type"} = $ParamTypeId;
                        }
                    }
                }
            }
        }
        if(my $PurpId = getTreeAttr_Purp($ParamListElemId))
        { # default arguments
            if(my $PurpType = $LibInfo{$Version}{"info_type"}{$PurpId})
            {
                if($PurpType eq "nop_expr")
                { # func ( const char* arg = (const char*)(void*)0 )
                    $PurpId = getTreeAttr_Op($PurpId);
                }
                my $Val = getInitVal($PurpId, $ParamTypeId);
                if(defined $Val) {
                    $SymbolInfo{$Version}{$InfoId}{"Param"}{$Pos}{"default"} = $Val;
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/chan[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Chain($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/chain[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Unql($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/unql[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Scpe($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/scpe[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Type($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Name($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Mngl($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/mngl[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Prms($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/prms[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Fncs($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/fncs[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Csts($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/csts[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Purp($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/purp[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Op($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/op 0[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Valu($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/valu[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Flds($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/flds[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Binf($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/binf[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeAttr_Args($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/args[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeValue($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/(low|int)[ ]*:[ ]*([^ ]+) /) {
            return $2;
        }
    }
    return "";
}

sub getTreeAccess($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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
        $SymbolInfo{$Version}{$_[0]}{"Protected"} = 1;
    }
    elsif($Access eq "private") {
        $SymbolInfo{$Version}{$_[0]}{"Private"} = 1;
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/pseudo tmpl/) {
            $SymbolInfo{$Version}{$_[0]}{"PseudoTemplate"} = 1;
        }
        elsif($Info=~/ constructor /) {
            $SymbolInfo{$Version}{$_[0]}{"Constructor"} = 1;
        }
        elsif($Info=~/ destructor /) {
            $SymbolInfo{$Version}{$_[0]}{"Destructor"} = 1;
        }
    }
}

sub getVirtSpec($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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

sub select_Symbol_NS($$)
{
    my ($Symbol, $LibVersion) = @_;
    return "" if(not $Symbol or not $LibVersion);
    my $NS = $CompleteSignature{$LibVersion}{$Symbol}{"NameSpace"};
    if(not $NS)
    {
        if(my $Class = $CompleteSignature{$LibVersion}{$Symbol}{"Class"}) {
            $NS = $TypeInfo{$LibVersion}{$Class}{"NameSpace"};
        }
    }
    if($NS)
    {
        if(defined $NestedNameSpaces{$LibVersion}{$NS}) {
            return $NS;
        }
        else
        {
            while($NS=~s/::[^:]+\Z//)
            {
                if(defined $NestedNameSpaces{$LibVersion}{$NS}) {
                    return $NS;
                }
            }
        }
    }
    
    return "";
}

sub select_Type_NS($$)
{
    my ($TypeName, $LibVersion) = @_;
    return "" if(not $TypeName or not $LibVersion);
    if(my $NS = $TypeInfo{$LibVersion}{$TName_Tid{$LibVersion}{$TypeName}}{"NameSpace"})
    {
        if(defined $NestedNameSpaces{$LibVersion}{$NS}) {
            return $NS;
        }
        else
        {
            while($NS=~s/::[^:]+\Z//)
            {
                if(defined $NestedNameSpaces{$LibVersion}{$NS}) {
                    return $NS;
                }
            }
        }
    }
    return "";
}

sub getNameSpace($)
{
    my $InfoId = $_[0];
    if(my $NSInfoId = getTreeAttr_Scpe($InfoId))
    {
        if(my $InfoType = $LibInfo{$Version}{"info_type"}{$NSInfoId})
        {
            if($InfoType eq "namespace_decl")
            {
                if($LibInfo{$Version}{"info"}{$NSInfoId}=~/name[ ]*:[ ]*@(\d+) /)
                {
                    my $NameSpace = getTreeStr($1);
                    if($NameSpace eq "::")
                    { # global namespace
                        return "";
                    }
                    if(my $BaseNameSpace = getNameSpace($NSInfoId)) {
                        $NameSpace = $BaseNameSpace."::".$NameSpace;
                    }
                    $NestedNameSpaces{$Version}{$NameSpace} = 1;
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/valu[ ]*:[ ]*\@(\d+)/)
        {
            if(my $VInfo = $LibInfo{$Version}{"info"}{$1})
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/size[ ]*:[ ]*\@(\d+)/) {
            return getTreeValue($1);
        }
    }
    return 0;
}

sub getAlgn($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/algn[ ]*:[ ]*(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getBitField($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
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

sub registerHeader($$)
{ # input: absolute path of header, relative path or name
    my ($Header, $LibVersion) = @_;
    if(not $Header) {
        return "";
    }
    if(is_abs($Header) and not -f $Header)
    { # incorrect absolute path
        exitStatus("Access_Error", "can't access \'$Header\'");
    }
    if(skipHeader($Header, $LibVersion))
    { # skip
        return "";
    }
    if(my $Header_Path = identifyHeader($Header, $LibVersion))
    {
        detect_header_includes($Header_Path, $LibVersion);
        
        if(defined $Tolerance and $Tolerance=~/3/)
        { # 3 - skip headers that include non-Linux headers
            if($OSgroup ne "windows")
            {
                foreach my $Inc (keys(%{$Header_Includes{$LibVersion}{$Header_Path}}))
                {
                    if(specificHeader($Inc, "windows")) {
                        return "";
                    }
                }
            }
        }
        
        if(my $RHeader_Path = $Header_ErrorRedirect{$LibVersion}{$Header_Path})
        { # redirect
            if($Registered_Headers{$LibVersion}{$RHeader_Path}{"Identity"}
            or skipHeader($RHeader_Path, $LibVersion))
            { # skip
                return "";
            }
            $Header_Path = $RHeader_Path;
        }
        elsif($Header_ShouldNotBeUsed{$LibVersion}{$Header_Path})
        { # skip
            return "";
        }
        
        if(my $HName = get_filename($Header_Path))
        { # register
            $Registered_Headers{$LibVersion}{$Header_Path}{"Identity"} = $HName;
            $HeaderName_Paths{$LibVersion}{$HName}{$Header_Path} = 1;
        }
        
        if(($Header=~/\.(\w+)\Z/ and $1 ne "h")
        or $Header!~/\.(\w+)\Z/)
        { # hpp, hh, etc.
            setLanguage($LibVersion, "C++");
            $CPP_HEADERS = 1;
        }
        
        if($CheckHeadersOnly
        and $Header=~/(\A|\/)c\+\+(\/|\Z)/)
        { # /usr/include/c++/4.6.1/...
            $STDCXX_TESTING = 1;
        }
        
        return $Header_Path;
    }
    return "";
}

sub registerDir($$$)
{
    my ($Dir, $WithDeps, $LibVersion) = @_;
    $Dir=~s/[\/\\]+\Z//g;
    return if(not $LibVersion or not $Dir or not -d $Dir);
    $Dir = get_abs_path($Dir);
    
    my $Mode = "All";
    if($WithDeps)
    {
        if($RegisteredDirs{$LibVersion}{$Dir}{1}) {
            return;
        }
        elsif($RegisteredDirs{$LibVersion}{$Dir}{0}) {
            $Mode = "DepsOnly";
        }
    }
    else
    {
        if($RegisteredDirs{$LibVersion}{$Dir}{1}
        or $RegisteredDirs{$LibVersion}{$Dir}{0}) {
            return;
        }
    }
    $Header_Dependency{$LibVersion}{$Dir} = 1;
    $RegisteredDirs{$LibVersion}{$Dir}{$WithDeps} = 1;
    if($Mode eq "DepsOnly")
    {
        foreach my $Path (cmd_find($Dir,"d")) {
            $Header_Dependency{$LibVersion}{$Path} = 1;
        }
        return;
    }
    foreach my $Path (sort {length($b)<=>length($a)} cmd_find($Dir,"f"))
    {
        if($WithDeps)
        { 
            my $SubDir = $Path;
            while(($SubDir = get_dirname($SubDir)) ne $Dir)
            { # register all sub directories
                $Header_Dependency{$LibVersion}{$SubDir} = 1;
            }
        }
        next if(is_not_header($Path));
        next if(ignore_path($Path));
        # Neighbors
        foreach my $Part (get_prefixes($Path)) {
            $Include_Neighbors{$LibVersion}{$Part} = $Path;
        }
    }
    if(get_filename($Dir) eq "include")
    { # search for "lib/include/" directory
        my $LibDir = $Dir;
        if($LibDir=~s/([\/\\])include\Z/$1lib/g and -d $LibDir) {
            registerDir($LibDir, $WithDeps, $LibVersion);
        }
    }
}

sub parse_redirect($$$)
{
    my ($Content, $Path, $LibVersion) = @_;
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
            $Header_ShouldNotBeUsed{$LibVersion}{$Path} = 1;
        }
    }
    if($Redirect)
    {
        $Redirect=~s/\A<//g;
        $Redirect=~s/>\Z//g;
    }
    return $Redirect;
}

sub parse_includes($$)
{
    my ($Content, $Path) = @_;
    my %Includes = ();
    while($Content=~s/^[ \t]*#[ \t]*(include|include_next|import)[ \t]*([<"].+?[">])[ \t]*//m)
    { # C/C++: include, Objective C/C++: import directive
        my $Header = $2;
        my $Method = substr($Header, 0, 1, "");
        substr($Header, length($Header)-1, 1, "");
        $Header = path_format($Header, $OSgroup);
        if($Method eq "\"" or is_abs($Header))
        {
            if(-e join_P(get_dirname($Path), $Header))
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
    if($ExtraInfo)
    {
        while($Content=~s/^[ \t]*#[ \t]*(include|include_next|import)[ \t]+(\w+)[ \t]*//m)
        { # FT_FREETYPE_H
            $Includes{$2} = 0;
        }
    }
    return \%Includes;
}

sub ignore_path($)
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

sub sortByWord($$)
{
    my ($ArrRef, $W) = @_;
    return if(length($W)<2);
    @{$ArrRef} = sort {get_filename($b)=~/\Q$W\E/i<=>get_filename($a)=~/\Q$W\E/i} @{$ArrRef};
}

sub sortHeaders($$)
{
    my ($H1, $H2) = @_;
    
    $H1=~s/\.[a-z]+\Z//ig;
    $H2=~s/\.[a-z]+\Z//ig;
    
    my $Hname1 = get_filename($H1);
    my $Hname2 = get_filename($H2);
    my $HDir1 = get_dirname($H1);
    my $HDir2 = get_dirname($H2);
    my $Dirname1 = get_filename($HDir1);
    my $Dirname2 = get_filename($HDir2);
    
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

sub searchForHeaders($)
{
    my $LibVersion = $_[0];
    
    # gcc standard include paths
    registerGccHeaders();
    
    if($COMMON_LANGUAGE{$LibVersion} eq "C++" and not $STDCXX_TESTING)
    { # c++ standard include paths
        registerCppHeaders();
    }
    
    # processing header paths
    foreach my $Path (@{$Descriptor{$LibVersion}{"IncludePaths"}},
    @{$Descriptor{$LibVersion}{"AddIncludePaths"}})
    {
        my $IPath = $Path;
        if($SystemRoot)
        {
            if(is_abs($Path)) {
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
            $Path = get_abs_path($Path);
            registerDir($Path, 0, $LibVersion);
            if(grep {$IPath eq $_} @{$Descriptor{$LibVersion}{"AddIncludePaths"}}) {
                push(@{$Add_Include_Paths{$LibVersion}}, $Path);
            }
            else {
                push(@{$Include_Paths{$LibVersion}}, $Path);
            }
        }
    }
    if(@{$Include_Paths{$LibVersion}}) {
        $INC_PATH_AUTODETECT{$LibVersion} = 0;
    }
    
    # registering directories
    foreach my $Path (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Headers"}))
    {
        next if(not -e $Path);
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        if(-d $Path) {
            registerDir($Path, 1, $LibVersion);
        }
        elsif(-f $Path)
        {
            my $Dir = get_dirname($Path);
            if(not grep { $Dir eq $_ } (@{$SystemPaths{"include"}})
            and not $LocalIncludes{$Dir})
            {
                registerDir($Dir, 1, $LibVersion);
                # if(my $OutDir = get_dirname($Dir))
                # { # registering the outer directory
                #     if(not grep { $OutDir eq $_ } (@{$SystemPaths{"include"}})
                #     and not $LocalIncludes{$OutDir}) {
                #         registerDir($OutDir, 0, $LibVersion);
                #     }
                # }
            }
        }
    }
    
    # clean memory
    %RegisteredDirs = ();
    
    # registering headers
    my $Position = 0;
    foreach my $Dest (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Headers"}))
    {
        if(is_abs($Dest) and not -e $Dest) {
            exitStatus("Access_Error", "can't access \'$Dest\'");
        }
        $Dest = path_format($Dest, $OSgroup);
        if(is_header($Dest, 1, $LibVersion))
        {
            if(my $HPath = registerHeader($Dest, $LibVersion)) {
                $Registered_Headers{$LibVersion}{$HPath}{"Pos"} = $Position++;
            }
        }
        elsif(-d $Dest)
        {
            my @Registered = ();
            foreach my $Path (cmd_find($Dest,"f"))
            {
                next if(ignore_path($Path));
                next if(not is_header($Path, 0, $LibVersion));
                if(my $HPath = registerHeader($Path, $LibVersion)) {
                    push(@Registered, $HPath);
                }
            }
            @Registered = sort {sortHeaders($a, $b)} @Registered;
            sortByWord(\@Registered, $TargetLibraryShortName);
            foreach my $Path (@Registered) {
                $Registered_Headers{$LibVersion}{$Path}{"Pos"} = $Position++;
            }
        }
        else {
            exitStatus("Access_Error", "can't identify \'$Dest\' as a header file");
        }
    }
    
    if(defined $Tolerance and $Tolerance=~/4/)
    { # 4 - skip headers included by others
        foreach my $Path (keys(%{$Registered_Headers{$LibVersion}}))
        {
            if(defined $Header_Includes_R{$LibVersion}{$Path}) {
                delete($Registered_Headers{$LibVersion}{$Path});
            }
        }
    }
    
    if(my $HList = $Descriptor{$LibVersion}{"IncludePreamble"})
    { # preparing preamble headers
        foreach my $Header (split(/\s*\n\s*/, $HList))
        {
            if(is_abs($Header) and not -f $Header) {
                exitStatus("Access_Error", "can't access file \'$Header\'");
            }
            $Header = path_format($Header, $OSgroup);
            if(my $Header_Path = is_header($Header, 1, $LibVersion))
            {
                next if(skipHeader($Header_Path, $LibVersion));
                push_U($Include_Preamble{$LibVersion}, $Header_Path);
            }
            else {
                exitStatus("Access_Error", "can't identify \'$Header\' as a header file");
            }
        }
    }
    foreach my $Header_Name (keys(%{$HeaderName_Paths{$LibVersion}}))
    { # set relative paths (for duplicates)
        if(keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}})>=2)
        { # search for duplicates
            my $FirstPath = (keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}}))[0];
            my $Prefix = get_dirname($FirstPath);
            while($Prefix=~/\A(.+)[\/\\]+[^\/\\]+\Z/)
            { # detect a shortest distinguishing prefix
                my $NewPrefix = $1;
                my %Identity = ();
                foreach my $Path (keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}}))
                {
                    if($Path=~/\A\Q$Prefix\E[\/\\]+(.*)\Z/) {
                        $Identity{$Path} = $1;
                    }
                }
                if(keys(%Identity)==keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}}))
                { # all names are different with current prefix
                    foreach my $Path (keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}})) {
                        $Registered_Headers{$LibVersion}{$Path}{"Identity"} = $Identity{$Path};
                    }
                    last;
                }
                $Prefix = $NewPrefix; # increase prefix
            }
        }
    }
    
    # clean memory
    %HeaderName_Paths = ();
    
    foreach my $HeaderName (keys(%{$Include_Order{$LibVersion}}))
    { # ordering headers according to descriptor
        my $PairName = $Include_Order{$LibVersion}{$HeaderName};
        my ($Pos, $PairPos) = (-1, -1);
        my ($Path, $PairPath) = ();
        my @Paths = keys(%{$Registered_Headers{$LibVersion}});
        @Paths = sort {int($Registered_Headers{$LibVersion}{$a}{"Pos"})<=>int($Registered_Headers{$LibVersion}{$b}{"Pos"})} @Paths;
        foreach my $Header_Path (@Paths) 
        {
            if(get_filename($Header_Path) eq $PairName)
            {
                $PairPos = $Registered_Headers{$LibVersion}{$Header_Path}{"Pos"};
                $PairPath = $Header_Path;
            }
            if(get_filename($Header_Path) eq $HeaderName)
            {
                $Pos = $Registered_Headers{$LibVersion}{$Header_Path}{"Pos"};
                $Path = $Header_Path;
            }
        }
        if($PairPos!=-1 and $Pos!=-1
        and int($PairPos)<int($Pos))
        {
            my %Tmp = %{$Registered_Headers{$LibVersion}{$Path}};
            %{$Registered_Headers{$LibVersion}{$Path}} = %{$Registered_Headers{$LibVersion}{$PairPath}};
            %{$Registered_Headers{$LibVersion}{$PairPath}} = %Tmp;
        }
    }
    if(not keys(%{$Registered_Headers{$LibVersion}})) {
        exitStatus("Error", "header files are not found in the ".$Descriptor{$LibVersion}{"Version"});
    }
}

sub detect_real_includes($$)
{
    my ($AbsPath, $LibVersion) = @_;
    return () if(not $LibVersion or not $AbsPath or not -e $AbsPath);
    if($Cache{"detect_real_includes"}{$LibVersion}{$AbsPath}
    or keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}})) {
        return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
    }
    $Cache{"detect_real_includes"}{$LibVersion}{$AbsPath}=1;
    
    my $Path = callPreprocessor($AbsPath, "", $LibVersion);
    return () if(not $Path);
    open(PREPROC, $Path);
    while(<PREPROC>)
    {
        if(/#\s+\d+\s+"([^"]+)"[\s\d]*\n/)
        {
            my $Include = path_format($1, $OSgroup);
            if($Include=~/\<(built\-in|internal|command(\-|\s)line)\>|\A\./) {
                next;
            }
            if($Include eq $AbsPath) {
                next;
            }
            $RecursiveIncludes{$LibVersion}{$AbsPath}{$Include} = 1;
        }
    }
    close(PREPROC);
    return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
}

sub detect_header_includes($$)
{
    my ($Path, $LibVersion) = @_;
    return if(not $LibVersion or not $Path);
    if(defined $Cache{"detect_header_includes"}{$LibVersion}{$Path}) {
        return;
    }
    $Cache{"detect_header_includes"}{$LibVersion}{$Path}=1;
    
    if(not -e $Path) {
        return;
    }
    
    my $Content = readFile($Path);
    if(my $Redirect = parse_redirect($Content, $Path, $LibVersion))
    { # detect error directive in headers
        if(my $RedirectPath = identifyHeader($Redirect, $LibVersion))
        {
            if($RedirectPath=~/\/usr\/include\// and $Path!~/\/usr\/include\//) {
                $RedirectPath = identifyHeader(get_filename($Redirect), $LibVersion);
            }
            if($RedirectPath ne $Path) {
                $Header_ErrorRedirect{$LibVersion}{$Path} = $RedirectPath;
            }
        }
        else
        { # can't find
            $Header_ShouldNotBeUsed{$LibVersion}{$Path} = 1;
        }
    }
    if(my $Inc = parse_includes($Content, $Path))
    {
        foreach my $Include (keys(%{$Inc}))
        { # detect includes
            $Header_Includes{$LibVersion}{$Path}{$Include} = $Inc->{$Include};
            
            if(defined $Tolerance and $Tolerance=~/4/)
            {
                if(my $HPath = identifyHeader($Include, $LibVersion))
                {
                    $Header_Includes_R{$LibVersion}{$HPath}{$Path} = 1;
                }
            }
        }
    }
}

sub fromLibc($)
{ # system GLIBC header
    my $Path = $_[0];
    my ($Dir, $Name) = separate_path($Path);
    if($OStarget eq "symbian")
    {
        if(get_filename($Dir) eq "libc" and $GlibcHeader{$Name})
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
    my ($OutDir, $Name) = separate_path($Dir);
    if($OStarget eq "symbian")
    {
        if(get_filename($OutDir) eq "libc"
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

sub detect_recursive_includes($$)
{
    my ($AbsPath, $LibVersion) = @_;
    return () if(not $AbsPath);
    if(isCyclical(\@RecurInclude, $AbsPath)) {
        return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
    }
    my ($AbsDir, $Name) = separate_path($AbsPath);
    if(isLibcDir($AbsDir))
    { # system GLIBC internals
        return () if(not $ExtraInfo);
    }
    if(keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}})) {
        return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
    }
    return () if($OSgroup ne "windows" and $Name=~/windows|win32|win64/i);
    
    if($MAIN_CPP_DIR and $AbsPath=~/\A\Q$MAIN_CPP_DIR\E/ and not $STDCXX_TESTING)
    { # skip /usr/include/c++/*/ headers
        return () if(not $ExtraInfo);
    }
    
    push(@RecurInclude, $AbsPath);
    if(grep { $AbsDir eq $_ } @DefaultGccPaths
    or (grep { $AbsDir eq $_ } @DefaultIncPaths and fromLibc($AbsPath)))
    { # check "real" (non-"model") include paths
        my @Paths = detect_real_includes($AbsPath, $LibVersion);
        pop(@RecurInclude);
        return @Paths;
    }
    if(not keys(%{$Header_Includes{$LibVersion}{$AbsPath}})) {
        detect_header_includes($AbsPath, $LibVersion);
    }
    foreach my $Include (keys(%{$Header_Includes{$LibVersion}{$AbsPath}}))
    {
        my $IncType = $Header_Includes{$LibVersion}{$AbsPath}{$Include};
        my $HPath = "";
        if($IncType<0)
        { # for #include "..."
            my $Candidate = join_P($AbsDir, $Include);
            if(-f $Candidate) {
                $HPath = realpath($Candidate);
            }
        }
        elsif($IncType>0
        and $Include=~/[\/\\]/) # and not find_in_defaults($Include)
        { # search for the nearest header
          # QtCore/qabstractanimation.h includes <QtCore/qobject.h>
            my $Candidate = join_P(get_dirname($AbsDir), $Include);
            if(-f $Candidate) {
                $HPath = $Candidate;
            }
        }
        if(not $HPath) {
            $HPath = identifyHeader($Include, $LibVersion);
        }
        next if(not $HPath);
        if($HPath eq $AbsPath) {
            next;
        }
        
        if($Debug)
        { # boundary headers
#             if($HPath=~/vtk/ and $AbsPath!~/vtk/)
#             {
#                 print STDERR "$AbsPath -> $HPath\n";
#             }
        }
        
        $RecursiveIncludes{$LibVersion}{$AbsPath}{$HPath} = $IncType;
        if($IncType>0)
        { # only include <...>, skip include "..." prefixes
            $Header_Include_Prefix{$LibVersion}{$AbsPath}{$HPath}{get_dirname($Include)} = 1;
        }
        foreach my $IncPath (detect_recursive_includes($HPath, $LibVersion))
        {
            if($IncPath eq $AbsPath) {
                next;
            }
            my $RIncType = $RecursiveIncludes{$LibVersion}{$HPath}{$IncPath};
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
            $RecursiveIncludes{$LibVersion}{$AbsPath}{$IncPath} = $RIncType;
            foreach my $Prefix (keys(%{$Header_Include_Prefix{$LibVersion}{$HPath}{$IncPath}})) {
                $Header_Include_Prefix{$LibVersion}{$AbsPath}{$IncPath}{$Prefix} = 1;
            }
        }
        foreach my $Dep (keys(%{$Header_Include_Prefix{$LibVersion}{$AbsPath}}))
        {
            if($GlibcHeader{get_filename($Dep)} and keys(%{$Header_Include_Prefix{$LibVersion}{$AbsPath}{$Dep}})>=2
            and defined $Header_Include_Prefix{$LibVersion}{$AbsPath}{$Dep}{""})
            { # distinguish math.h from glibc and math.h from the tested library
                delete($Header_Include_Prefix{$LibVersion}{$AbsPath}{$Dep}{""});
                last;
            }
        }
    }
    pop(@RecurInclude);
    return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
}

sub find_in_framework($$$)
{
    my ($Header, $Framework, $LibVersion) = @_;
    return "" if(not $Header or not $Framework or not $LibVersion);
    if(defined $Cache{"find_in_framework"}{$LibVersion}{$Framework}{$Header}) {
        return $Cache{"find_in_framework"}{$LibVersion}{$Framework}{$Header};
    }
    foreach my $Dependency (sort {get_depth($a)<=>get_depth($b)} keys(%{$Header_Dependency{$LibVersion}}))
    {
        if(get_filename($Dependency) eq $Framework
        and -f get_dirname($Dependency)."/".$Header) {
            return ($Cache{"find_in_framework"}{$LibVersion}{$Framework}{$Header} = get_dirname($Dependency));
        }
    }
    return ($Cache{"find_in_framework"}{$LibVersion}{$Framework}{$Header} = "");
}

sub find_in_defaults($)
{
    my $Header = $_[0];
    return "" if(not $Header);
    if(defined $Cache{"find_in_defaults"}{$Header}) {
        return $Cache{"find_in_defaults"}{$Header};
    }
    foreach my $Dir (@DefaultIncPaths,
                     @DefaultGccPaths,
                     @DefaultCppPaths,
                     @UsersIncPath)
    {
        next if(not $Dir);
        if(-f $Dir."/".$Header) {
            return ($Cache{"find_in_defaults"}{$Header}=$Dir);
        }
    }
    return ($Cache{"find_in_defaults"}{$Header}="");
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
    return 0 if(not $Path);
    
    if($SystemRoot) {
        $Path = cut_path_prefix($Path, $SystemRoot);
    }
    
    my $Name = lc(get_filename($Path));
    my $Dir = lc(get_dirname($Path));
    
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
    return 1 if($#Paths<=0);
    my %Prefix = ();
    foreach my $Path (@Paths)
    {
        if($SystemRoot) {
            $Path = cut_path_prefix($Path, $SystemRoot);
        }
        if(my $Dir = get_dirname($Path))
        {
            $Dir=~s/(\/[^\/]+?)[\d\.\-\_]+\Z/$1/g; # remove version suffix
            $Prefix{$Dir} += 1;
            $Prefix{get_dirname($Dir)} += 1;
        }
    }
    foreach (sort keys(%Prefix))
    {
        if(get_depth($_)>=3
        and $Prefix{$_}==$#Paths+1) {
            return 1;
        }
    }
    return 0;
}

sub isAcceptable($$$)
{
    my ($Header, $Candidate, $LibVersion) = @_;
    my $HName = get_filename($Header);
    if(get_dirname($Header))
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
    if(checkFamily(getSystemHeaders($HName, $LibVersion)))
    { # /usr/include/qt4/QtNetwork/qsslconfiguration.h
      # /usr/include/qt4/Qt/qsslconfiguration.h
        return 1;
    }
    if($OStarget eq "symbian")
    {
        if($Candidate=~/[\/\\]stdapis[\/\\]/) {
            return 1;
        }
    }
    return 0;
}

sub isRelevant($$$)
{ # disallow to search for "abstract" headers in too deep directories
    my ($Header, $Candidate, $LibVersion) = @_;
    my $HName = get_filename($Header);
    if($OStarget eq "symbian")
    {
        if($Candidate=~/[\/\\](tools|stlportv5)[\/\\]/) {
            return 0;
        }
    }
    if($OStarget ne "bsd")
    {
        if($Candidate=~/[\/\\]include[\/\\]bsd[\/\\]/)
        { # openssh: skip /usr/lib/bcc/include/bsd/signal.h
            return 0;
        }
    }
    if($OStarget ne "windows")
    {
        if($Candidate=~/[\/\\](wine|msvcrt|windows)[\/\\]/)
        { # skip /usr/include/wine/msvcrt
            return 0;
        }
    }
    if(not get_dirname($Header)
    and $Candidate=~/[\/\\]wx[\/\\]/)
    { # do NOT search in system /wx/ directory
      # for headers without a prefix: sstream.h
        return 0;
    }
    if($Candidate=~/c\+\+[\/\\]\d+/ and $MAIN_CPP_DIR
    and $Candidate!~/\A\Q$MAIN_CPP_DIR\E/)
    { # skip ../c++/3.3.3/ if using ../c++/4.5/
        return 0;
    }
    if($Candidate=~/[\/\\]asm-/
    and (my $Arch = getArch($LibVersion)) ne "unknown")
    { # arch-specific header files
        if($Candidate!~/[\/\\]asm-\Q$Arch\E/)
        {# skip ../asm-arm/ if using x86 architecture
            return 0;
        }
    }
    my @Candidates = getSystemHeaders($HName, $LibVersion);
    if($#Candidates==1)
    { # unique header
        return 1;
    }
    my @SCandidates = getSystemHeaders($Header, $LibVersion);
    if($#SCandidates==1)
    { # unique name
        return 1;
    }
    my $SystemDepth = $SystemRoot?get_depth($SystemRoot):0;
    if(get_depth($Candidate)-$SystemDepth>=5)
    { # abstract headers in too deep directories
      # sstream.h or typeinfo.h in /usr/include/wx-2.9/wx/
        if(not isAcceptable($Header, $Candidate, $LibVersion)) {
            return 0;
        }
    }
    if($Header eq "parser.h"
    and $Candidate!~/\/libxml2\//)
    { # select parser.h from xml2 library
        return 0;
    }
    if(not get_dirname($Header)
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
    my ($Header, $LibVersion) = @_;
    if(-f $Header) {
        return $Header;
    }
    if(is_abs($Header) and not -f $Header)
    { # incorrect absolute path
        return "";
    }
    if(defined $ConfHeaders{lc($Header)})
    { # too abstract configuration headers
        return "";
    }
    my $HName = get_filename($Header);
    if($OSgroup ne "windows")
    {
        if(defined $WinHeaders{lc($HName)}
        or $HName=~/windows|win32|win64/i)
        { # windows headers
            return "";
        }
    }
    if($OSgroup ne "macos")
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
    if($OSgroup eq "linux" or $OSgroup eq "bsd")
    {
        if(defined $AlienHeaders{$HName}
        or defined $AlienHeaders{$Header})
        { # alien headers from other systems
            return "";
        }
    }
    
    foreach my $Path (@{$SystemPaths{"include"}})
    { # search in default paths
        if(-f $Path."/".$Header) {
            return join_P($Path,$Header);
        }
    }
    if(not defined $Cache{"checkSystemFiles"})
    { # register all headers in system include dirs
        checkSystemFiles();
    }
    foreach my $Candidate (sort {get_depth($a)<=>get_depth($b)}
    sort {cmp_paths($b, $a)} getSystemHeaders($Header, $LibVersion))
    {
        if(isRelevant($Header, $Candidate, $LibVersion)) {
            return $Candidate;
        }
    }
    # error
    return "";
}

sub getSystemHeaders($$)
{
    my ($Header, $LibVersion) = @_;
    my @Candidates = ();
    foreach my $Candidate (sort keys(%{$SystemHeaders{$Header}}))
    {
        if(skipHeader($Candidate, $LibVersion)) {
            next;
        }
        push(@Candidates, $Candidate);
    }
    return @Candidates;
}

sub cut_path_prefix($$)
{
    my ($Path, $Prefix) = @_;
    return $Path if(not $Prefix);
    $Prefix=~s/[\/\\]+\Z//;
    $Path=~s/\A\Q$Prefix\E([\/\\]+|\Z)//;
    return $Path;
}

sub is_default_include_dir($)
{
    my $Dir = $_[0];
    $Dir=~s/[\/\\]+\Z//;
    return grep { $Dir eq $_ } (@DefaultGccPaths, @DefaultCppPaths, @DefaultIncPaths);
}

sub identifyHeader($$)
{ # cache function
    my ($Header, $LibVersion) = @_;
    if(not $Header) {
        return "";
    }
    $Header=~s/\A(\.\.[\\\/])+//g;
    if(defined $Cache{"identifyHeader"}{$LibVersion}{$Header}) {
        return $Cache{"identifyHeader"}{$LibVersion}{$Header};
    }
    return ($Cache{"identifyHeader"}{$LibVersion}{$Header} = identifyHeader_I($Header, $LibVersion));
}

sub identifyHeader_I($$)
{ # search for header by absolute path, relative path or name
    my ($Header, $LibVersion) = @_;
    if(-f $Header)
    { # it's relative or absolute path
        return get_abs_path($Header);
    }
    elsif($GlibcHeader{$Header} and not $GLIBC_TESTING
    and my $HeaderDir = find_in_defaults($Header))
    { # search for libc headers in the /usr/include
      # for non-libc target library before searching
      # in the library paths
        return join_P($HeaderDir,$Header);
    }
    elsif(my $Path = $Include_Neighbors{$LibVersion}{$Header})
    { # search in the target library paths
        return $Path;
    }
    elsif(defined $DefaultGccHeader{$Header})
    { # search in the internal GCC include paths
        return $DefaultGccHeader{$Header};
    }
    elsif(my $DefaultDir = find_in_defaults($Header))
    { # search in the default GCC include paths
        return join_P($DefaultDir,$Header);
    }
    elsif(defined $DefaultCppHeader{$Header})
    { # search in the default G++ include paths
        return $DefaultCppHeader{$Header};
    }
    elsif(my $AnyPath = selectSystemHeader($Header, $LibVersion))
    { # search everywhere in the system
        return $AnyPath;
    }
    elsif($OSgroup eq "macos")
    { # search in frameworks: "OpenGL/gl.h" is "OpenGL.framework/Headers/gl.h"
        if(my $Dir = get_dirname($Header))
        {
            my $RelPath = "Headers\/".get_filename($Header);
            if(my $HeaderDir = find_in_framework($RelPath, $Dir.".framework", $LibVersion)) {
                return join_P($HeaderDir, $RelPath);
            }
        }
    }
    # cannot find anything
    return "";
}

sub getLocation($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/srcp[ ]*:[ ]*([\w\-\<\>\.\+\/\\]+):(\d+) /) {
            return (path_format($1, $OSgroup), $2);
        }
    }
    return ();
}

sub getNameByInfo($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /)
        {
            if(my $NInfo = $LibInfo{$Version}{"info"}{$1})
            {
                if($NInfo=~/strg[ ]*:[ ]*(.*?)[ ]+lngt/)
                { # short unsigned int (may include spaces)
                    my $Str = $1;
                    if($CppMode{$Version}
                    and $Str=~/\Ac99_(.+)\Z/)
                    {
                        if($CppKeywords_A{$1}) {
                            $Str=$1;
                        }
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/strg[ ]*:[ ]*([^ ]*)/)
        {
            my $Str = $1;
            if($CppMode{$Version}
            and $Str=~/\Ac99_(.+)\Z/)
            {
                if($CppKeywords_A{$1}) {
                    $Str=$1;
                }
            }
            return $Str;
        }
    }
    return "";
}

sub getFuncShortName($)
{
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if(index($Info, " operator ")!=-1)
        {
            if(index($Info, " conversion ")!=-1)
            {
                if(my $Rid = $SymbolInfo{$Version}{$_[0]}{"Return"})
                {
                    if(my $RName = $TypeInfo{$Version}{$Rid}{"Name"}) {
                        return "operator ".$RName;
                    }
                }
            }
            else
            {
                if($Info=~/ operator[ ]+([a-zA-Z]+) /)
                {
                    if(my $Ind = $Operator_Indication{$1}) {
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /)
        {
            if($LibInfo{$Version}{"info"}{$1}=~/retn[ ]*:[ ]*@(\d+) /) {
                return $1;
            }
        }
    }
    return "";
}

sub getFuncOrig($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/orig[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return $_[0];
}

sub unmangleArray(@)
{
    if($_[0]=~/\A\?/)
    { # MSVC mangling
        my $UndNameCmd = get_CmdPath("undname");
        if(not $UndNameCmd) {
            exitStatus("Not_Found", "can't find \"undname\"");
        }
        writeFile("$TMP_DIR/unmangle", join("\n", @_));
        return split(/\n/, `$UndNameCmd 0x8386 \"$TMP_DIR/unmangle\"`);
    }
    else
    { # GCC mangling
        my $CppFiltCmd = get_CmdPath("c++filt");
        if(not $CppFiltCmd) {
            exitStatus("Not_Found", "can't find c++filt in PATH");
        }
        if(not defined $CPPFILT_SUPPORT_FILE)
        {
            my $Info = `$CppFiltCmd -h 2>&1`;
            $CPPFILT_SUPPORT_FILE = $Info=~/\@<file>/;
        }
        my $NoStrip = ($OSgroup=~/macos|windows/)?"-n":"";
        if($CPPFILT_SUPPORT_FILE)
        { # new versions of c++filt can take a file
            if($#_>$MAX_CPPFILT_FILE_SIZE)
            { # c++filt <= 2.22 may crash on large files (larger than 8mb)
              # this is fixed in the oncoming version of Binutils
                my @Half = splice(@_, 0, ($#_+1)/2);
                return (unmangleArray(@Half), unmangleArray(@_))
            }
            else
            {
                writeFile("$TMP_DIR/unmangle", join("\n", @_));
                my $Res = `$CppFiltCmd $NoStrip \@\"$TMP_DIR/unmangle\"`;
                if($?==139)
                { # segmentation fault
                    printMsg("ERROR", "internal error - c++filt crashed, try to reduce MAX_CPPFILT_FILE_SIZE constant");
                }
                return split(/\n/, $Res);
            }
        }
        else
        { # old-style unmangling
            if($#_>$MAX_COMMAND_LINE_ARGUMENTS)
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

sub get_ChargeLevel($$)
{
    my ($Symbol, $LibVersion) = @_;
    return "" if($Symbol!~/\A(_Z|\?)/);
    if(defined $CompleteSignature{$LibVersion}{$Symbol}
    and $CompleteSignature{$LibVersion}{$Symbol}{"Header"})
    {
        if($CompleteSignature{$LibVersion}{$Symbol}{"Constructor"})
        {
            if($Symbol=~/C1[EI]/) {
                return "[in-charge]";
            }
            elsif($Symbol=~/C2[EI]/) {
                return "[not-in-charge]";
            }
        }
        elsif($CompleteSignature{$LibVersion}{$Symbol}{"Destructor"})
        {
            if($Symbol=~/D1[EI]/) {
                return "[in-charge]";
            }
            elsif($Symbol=~/D2[EI]/) {
                return "[not-in-charge]";
            }
            elsif($Symbol=~/D0[EI]/) {
                return "[in-charge-deleting]";
            }
        }
    }
    else
    {
        if($Symbol=~/C1[EI]/) {
            return "[in-charge]";
        }
        elsif($Symbol=~/C2[EI]/) {
            return "[not-in-charge]";
        }
        elsif($Symbol=~/D1[EI]/) {
            return "[in-charge]";
        }
        elsif($Symbol=~/D2[EI]/) {
            return "[not-in-charge]";
        }
        elsif($Symbol=~/D0[EI]/) {
            return "[in-charge-deleting]";
        }
    }
    return "";
}

sub get_Signature_M($$)
{
    my ($Symbol, $LibVersion) = @_;
    my $Signature_M = $tr_name{$Symbol};
    if(my $RTid = $CompleteSignature{$LibVersion}{$Symbol}{"Return"})
    { # add return type name
        $Signature_M = $TypeInfo{$LibVersion}{$RTid}{"Name"}." ".$Signature_M;
    }
    return $Signature_M;
}

sub get_Signature($$)
{
    my ($Symbol, $LibVersion) = @_;
    if($Cache{"get_Signature"}{$LibVersion}{$Symbol}) {
        return $Cache{"get_Signature"}{$LibVersion}{$Symbol};
    }
    my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Symbol);
    my ($Signature, @Param_Types_FromUnmangledName) = ();
    
    my $ShortName = $CompleteSignature{$LibVersion}{$Symbol}{"ShortName"};
    
    if($Symbol=~/\A(_Z|\?)/)
    {
        if(my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"})
        {
            my $ClassName = $TypeInfo{$LibVersion}{$ClassId}{"Name"};
            $ClassName=~s/\bstruct //g;
            
            if(index($Symbol, "_ZTV")==0) {
                return "vtable for $ClassName [data]";
            }
            
            $Signature .= $ClassName."::";
            if($CompleteSignature{$LibVersion}{$Symbol}{"Destructor"}) {
                $Signature .= "~";
            }
            $Signature .= $ShortName;
        }
        elsif(my $NameSpace = $CompleteSignature{$LibVersion}{$Symbol}{"NameSpace"}) {
            $Signature .= $NameSpace."::".$ShortName;
        }
        else {
            $Signature .= $ShortName;
        }
        my ($Short, $Params) = split_Signature($tr_name{$MnglName});
        @Param_Types_FromUnmangledName = separate_Params($Params, 0, 1);
    }
    else
    {
        $Signature .= $MnglName;
    }
    my @ParamArray = ();
    foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
    {
        if($Pos eq "") {
            next;
        }
        
        my $ParamTypeId = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$Pos}{"type"};
        if(not $ParamTypeId) {
            next;
        }
        
        my $ParamTypeName = $TypeInfo{$LibVersion}{$ParamTypeId}{"Name"};
        if(not $ParamTypeName) {
            $ParamTypeName = $Param_Types_FromUnmangledName[$Pos];
        }
        foreach my $Typedef (keys(%ChangedTypedef))
        {
            if(my $Base = $Typedef_BaseName{$LibVersion}{$Typedef}) {
                $ParamTypeName=~s/\b\Q$Typedef\E\b/$Base/g;
            }
        }
        if(my $ParamName = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$Pos}{"name"})
        {
            if($ParamName eq "this"
            and $Symbol=~/\A(_Z|\?)/)
            { # do NOT show first hidded "this"-parameter
                next;
            }
            push(@ParamArray, create_member_decl($ParamTypeName, $ParamName));
        }
        else {
            push(@ParamArray, $ParamTypeName);
        }
    }
    if($CompleteSignature{$LibVersion}{$Symbol}{"Data"}
    or $GlobalDataObject{$LibVersion}{$Symbol}) {
        $Signature .= " [data]";
    }
    else
    {
        if(my $ChargeLevel = get_ChargeLevel($Symbol, $LibVersion))
        { # add [in-charge]
            $Signature .= " ".$ChargeLevel;
        }
        $Signature .= " (".join(", ", @ParamArray).")";
        if($CompleteSignature{$LibVersion}{$Symbol}{"Const"}
        or $Symbol=~/\A_ZN(V|)K/) {
            $Signature .= " const";
        }
        if($CompleteSignature{$LibVersion}{$Symbol}{"Volatile"}
        or $Symbol=~/\A_ZN(K|)V/) {
            $Signature .= " volatile";
        }
        if($CompleteSignature{$LibVersion}{$Symbol}{"Static"}
        and $Symbol=~/\A(_Z|\?)/)
        { # for static methods
            $Signature .= " [static]";
        }
    }
    if(defined $ShowRetVal
    and my $ReturnTId = $CompleteSignature{$LibVersion}{$Symbol}{"Return"}) {
        $Signature .= ":".$TypeInfo{$LibVersion}{$ReturnTId}{"Name"};
    }
    if($SymbolVersion) {
        $Signature .= $VersionSpec.$SymbolVersion;
    }
    return ($Cache{"get_Signature"}{$LibVersion}{$Symbol} = $Signature);
}

sub create_member_decl($$)
{
    my ($TName, $Member) = @_;
    if($TName=~/\([\*]+\)/)
    {
        $TName=~s/\(([\*]+)\)/\($1$Member\)/;
        return $TName;
    }
    else
    {
        my @ArraySizes = ();
        while($TName=~s/(\[[^\[\]]*\])\Z//) {
            push(@ArraySizes, $1);
        }
        return $TName." ".$Member.join("", @ArraySizes);
    }
}

sub getFuncType($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /)
        {
            if(my $Type = $LibInfo{$Version}{"info_type"}{$1})
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
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+)( |\Z)/) {
            return $1;
        }
    }
    return 0;
}

sub isAnon($)
{ # "._N" or "$_N" in older GCC versions
    return ($_[0] and $_[0]=~/(\.|\$)\_\d+|anon\-/);
}

sub formatName($$)
{ # type name correction
    if(defined $Cache{"formatName"}{$_[1]}{$_[0]}) {
        return $Cache{"formatName"}{$_[1]}{$_[0]};
    }
    
    my $N = $_[0];
    
    if($_[1] ne "S")
    {
        $N=~s/\A[ ]+//g;
        $N=~s/[ ]+\Z//g;
        $N=~s/[ ]{2,}/ /g;
    }
    
    $N=~s/[ ]*(\W)[ ]*/$1/g; # std::basic_string<char> const
    
    $N=~s/\b(const|volatile) ([\w\:]+)([\*&,>]|\Z)/$2 $1$3/g; # "const void" to "void const"
    
    $N=~s/\bvolatile const\b/const volatile/g;
    
    $N=~s/\b(long long|short|long) unsigned\b/unsigned $1/g;
    $N=~s/\b(short|long) int\b/$1/g;
    
    $N=~s/([\)\]])(const|volatile)\b/$1 $2/g;
    
    while($N=~s/>>/> >/g) {};
    
    if($_[1] eq "S")
    {
        if(index($N, "operator")!=-1) {
            $N=~s/\b(operator[ ]*)> >/$1>>/;
        }
    }
    
    $N=~s/,([^ ])/, $1/g;
    
    return ($Cache{"formatName"}{$_[1]}{$_[0]} = $N);
}

sub get_HeaderDeps($$)
{
    my ($AbsPath, $LibVersion) = @_;
    return () if(not $AbsPath or not $LibVersion);
    if(defined $Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath}) {
        return @{$Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath}};
    }
    my %IncDir = ();
    detect_recursive_includes($AbsPath, $LibVersion);
    foreach my $HeaderPath (keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}}))
    {
        next if(not $HeaderPath);
        next if($MAIN_CPP_DIR and $HeaderPath=~/\A\Q$MAIN_CPP_DIR\E([\/\\]|\Z)/);
        my $Dir = get_dirname($HeaderPath);
        foreach my $Prefix (keys(%{$Header_Include_Prefix{$LibVersion}{$AbsPath}{$HeaderPath}}))
        {
            my $Dep = $Dir;
            if($Prefix)
            {
                if($OSgroup eq "windows")
                { # case insensitive seach on windows
                    if(not $Dep=~s/[\/\\]+\Q$Prefix\E\Z//ig) {
                        next;
                    }
                }
                elsif($OSgroup eq "macos")
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
            if(is_default_include_dir($Dep))
            { # included by the compiler
                next;
            }
            if(get_depth($Dep)==1)
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
    $Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath} = sortIncPaths([keys(%IncDir)], $LibVersion);
    return @{$Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath}};
}

sub sortIncPaths($$)
{
    my ($ArrRef, $LibVersion) = @_;
    if(not $ArrRef or $#{$ArrRef}<0) {
        return $ArrRef;
    }
    @{$ArrRef} = sort {$b cmp $a} @{$ArrRef};
    @{$ArrRef} = sort {get_depth($a)<=>get_depth($b)} @{$ArrRef};
    @{$ArrRef} = sort {sortDeps($b, $a, $LibVersion)} @{$ArrRef};
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

sub join_P($$)
{
    my $S = "/";
    if($OSgroup eq "windows") {
        $S = "\\";
    }
    return join($S, @_);
}

sub get_namespace_additions($)
{
    my $NameSpaces = $_[0];
    my ($Additions, $AddNameSpaceId) = ("", 1);
    foreach my $NS (sort {$a=~/_/ <=> $b=~/_/} sort {lc($a) cmp lc($b)} keys(%{$NameSpaces}))
    {
        next if($SkipNameSpaces{$Version}{$NS});
        next if(not $NS or $NameSpaces->{$NS}==-1);
        next if($NS=~/(\A|::)iterator(::|\Z)/i);
        next if($NS=~/\A__/i);
        next if(($NS=~/\Astd::/ or $NS=~/\A(std|tr1|rel_ops|fcntl)\Z/) and not $STDCXX_TESTING);
        $NestedNameSpaces{$Version}{$NS} = 1; # for future use in reports
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
        $Additions.="  $TypeDecl\n  $FuncDecl\n";
        $AddNameSpaceId+=1;
    }
    return $Additions;
}

sub path_format($$)
{
    my ($Path, $Fmt) = @_;
    $Path=~s/[\/\\]+\.?\Z//g;
    if($Fmt eq "windows")
    {
        $Path=~s/\//\\/g;
        $Path=lc($Path);
    }
    else
    { # forward slash to pass into MinGW GCC
        $Path=~s/\\/\//g;
    }
    return $Path;
}

sub inc_opt($$)
{
    my ($Path, $Style) = @_;
    if($Style eq "GCC")
    { # GCC options
        if($OSgroup eq "windows")
        { # to MinGW GCC
            return "-I\"".path_format($Path, "unix")."\"";
        }
        elsif($OSgroup eq "macos"
        and $Path=~/\.framework\Z/)
        { # to Apple's GCC
            return "-F".esc(get_dirname($Path));
        }
        else {
            return "-I".esc($Path);
        }
    }
    elsif($Style eq "CL") {
        return "/I \"".$Path."\"";
    }
    return "";
}

sub platformSpecs($)
{
    my $LibVersion = $_[0];
    my $Arch = getArch($LibVersion);
    if($OStarget eq "symbian")
    { # options for GCCE compiler
        my %Symbian_Opts = map {$_=>1} (
            "-D__GCCE__",
            "-DUNICODE",
            "-fexceptions",
            "-D__SYMBIAN32__",
            "-D__MARM_INTERWORK__",
            "-D_UNICODE",
            "-D__S60_50__",
            "-D__S60_3X__",
            "-D__SERIES60_3X__",
            "-D__EPOC32__",
            "-D__MARM__",
            "-D__EABI__",
            "-D__MARM_ARMV5__",
            "-D__SUPPORT_CPP_EXCEPTIONS__",
            "-march=armv5t",
            "-mapcs",
            "-mthumb-interwork",
            "-DEKA2",
            "-DSYMBIAN_ENABLE_SPLIT_HEADERS"
        );
        return join(" ", keys(%Symbian_Opts));
    }
    elsif($OSgroup eq "windows"
    and get_dumpmachine($GCC_PATH)=~/mingw/i)
    { # add options to MinGW compiler
      # to simulate the MSVC compiler
        my %MinGW_Opts = map {$_=>1} (
            "-D_WIN32",
            "-D_STDCALL_SUPPORTED",
            "-D__int64=\"long long\"",
            "-D__int32=int",
            "-D__int16=short",
            "-D__int8=char",
            "-D__possibly_notnullterminated=\" \"",
            "-D__nullterminated=\" \"",
            "-D__nullnullterminated=\" \"",
            "-D__w64=\" \"",
            "-D__ptr32=\" \"",
            "-D__ptr64=\" \"",
            "-D__forceinline=inline",
            "-D__inline=inline",
            "-D__uuidof(x)=IID()",
            "-D__try=",
            "-D__except(x)=",
            "-D__declspec(x)=__attribute__((x))",
            "-D__pragma(x)=",
            "-D_inline=inline",
            "-D__forceinline=__inline",
            "-D__stdcall=__attribute__((__stdcall__))",
            "-D__cdecl=__attribute__((__cdecl__))",
            "-D__fastcall=__attribute__((__fastcall__))",
            "-D__thiscall=__attribute__((__thiscall__))",
            "-D_stdcall=__attribute__((__stdcall__))",
            "-D_cdecl=__attribute__((__cdecl__))",
            "-D_fastcall=__attribute__((__fastcall__))",
            "-D_thiscall=__attribute__((__thiscall__))",
            "-DSHSTDAPI_(x)=x",
            "-D_MSC_EXTENSIONS",
            "-DSECURITY_WIN32",
            "-D_MSC_VER=1500",
            "-D_USE_DECLSPECS_FOR_SAL",
            "-D__noop=\" \"",
            "-DDECLSPEC_DEPRECATED=\" \"",
            "-D__builtin_alignof(x)=__alignof__(x)",
            "-DSORTPP_PASS");
        if($Arch eq "x86") {
            $MinGW_Opts{"-D_M_IX86=300"}=1;
        }
        elsif($Arch eq "x86_64") {
            $MinGW_Opts{"-D_M_AMD64=300"}=1;
        }
        elsif($Arch eq "ia64") {
            $MinGW_Opts{"-D_M_IA64=300"}=1;
        }
        return join(" ", keys(%MinGW_Opts));
    }
    return "";
}

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

sub getCompileCmd($$$)
{
    my ($Path, $Opt, $Inc) = @_;
    my $GccCall = $GCC_PATH;
    if($Opt) {
        $GccCall .= " ".$Opt;
    }
    $GccCall .= " -x ";
    if($OSgroup eq "macos") {
        $GccCall .= "objective-";
    }
    
    if($EMERGENCY_MODE_48)
    { # workaround for GCC 4.8 (C only)
        $GccCall .= "c++";
    }
    elsif(check_gcc($GCC_PATH, "4"))
    { # compile as "C++" header
      # to obtain complete dump using GCC 4.0
        $GccCall .= "c++-header";
    }
    else
    { # compile as "C++" source
      # GCC 3.3 cannot compile headers
        $GccCall .= "c++";
    }
    if(my $Opts = platformSpecs($Version))
    { # platform-specific options
        $GccCall .= " ".$Opts;
    }
    # allow extra qualifications
    # and other nonconformant code
    $GccCall .= " -fpermissive";
    $GccCall .= " -w";
    if($NoStdInc)
    {
        $GccCall .= " -nostdinc";
        $GccCall .= " -nostdinc++";
    }
    if(my $Opts_GCC = getGCC_Opts($Version))
    { # user-defined options
        $GccCall .= " ".$Opts_GCC;
    }
    $GccCall .= " \"$Path\"";
    if($Inc)
    { # include paths
        $GccCall .= " ".$Inc;
    }
    return $GccCall;
}

sub detectPreamble($$)
{
    my ($Content, $LibVersion) = @_;
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
                if(my $Path = identifyHeader($Header, $LibVersion))
                {
                    if(skipHeader($Path, $LibVersion)) {
                        next;
                    }
                    $Path = path_format($Path, $OSgroup);
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

sub checkCTags($)
{
    my $Path = $_[0];
    if(not $Path) {
        return;
    }
    my $CTags = undef;
    
    if($OSgroup eq "bsd")
    { # use ectags on BSD
        $CTags = get_CmdPath("ectags");
        if(not $CTags) {
            printMsg("WARNING", "can't find \'ectags\' program");
        }
    }
    if(not $CTags) {
        $CTags = get_CmdPath("ctags");
    }
    if(not $CTags)
    {
        printMsg("WARNING", "can't find \'ctags\' program");
        return;
    }
    
    if($OSgroup ne "linux")
    { # macos, freebsd, etc.
        my $Info = `$CTags --version 2>\"$TMP_DIR/null\"`;
        if($Info!~/exuberant/i)
        {
            printMsg("WARNING", "incompatible version of \'ctags\' program");
            return;
        }
    }
    
    my $Out = $TMP_DIR."/ctags.txt";
    system("$CTags --c-kinds=pxn -f \"$Out\" \"$Path\" 2>\"$TMP_DIR/null\"");
    if($Debug) {
        copy($Out, $DEBUG_PATH{$Version}."/ctags.txt");
    }
    open(CTAGS, "<", $Out);
    while(my $Line = <CTAGS>)
    {
        chomp($Line);
        my ($Name, $Header, $Def, $Type, $Scpe) = split(/\t/, $Line);
        if(defined $Intrinsic_Keywords{$Name})
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
            $TUnit_NameSpaces{$Version}{$Name} = 1;
        }
        elsif($Type eq "p")
        {
            if(not $Scpe or index($Scpe, "namespace:")==0) {
                $TUnit_Funcs{$Version}{$Name} = 1;
            }
        }
        elsif($Type eq "x")
        {
            if(not $Scpe or index($Scpe, "namespace:")==0) {
                $TUnit_Vars{$Version}{$Name} = 1;
            }
        }
    }
    close(CTAGS);
}

sub preChange($$)
{
    my ($HeaderPath, $IncStr) = @_;
    
    my $PreprocessCmd = getCompileCmd($HeaderPath, "-E", $IncStr);
    my $Content = undef;
    
    if($OStarget eq "windows"
    and get_dumpmachine($GCC_PATH)=~/mingw/i
    and $MinGWMode{$Version}!=-1)
    { # modify headers to compile by MinGW
        if(not $Content)
        { # preprocessing
            $Content = `$PreprocessCmd 2>\"$TMP_DIR/null\"`;
        }
        if($Content=~s/__asm\s*(\{[^{}]*?\}|[^{};]*)//g)
        { # __asm { ... }
            $MinGWMode{$Version}=1;
        }
        if($Content=~s/\s+(\/ \/.*?)\n/\n/g)
        { # comments after preprocessing
            $MinGWMode{$Version}=1;
        }
        if($Content=~s/(\W)(0x[a-f]+|\d+)(i|ui)(8|16|32|64)(\W)/$1$2$5/g)
        { # 0xffui8
            $MinGWMode{$Version}=1;
        }
        
        if($MinGWMode{$Version}) {
            printMsg("INFO", "Using MinGW compatibility mode");
        }
    }
    
    if(($COMMON_LANGUAGE{$Version} eq "C" or $CheckHeadersOnly)
    and $CppMode{$Version}!=-1 and not $CppCompat and not $CPP_HEADERS)
    { # rename C++ keywords in C code
      # disable this code by -cpp-compatible option
        if(not $Content)
        { # preprocessing
            $Content = `$PreprocessCmd 2>\"$TMP_DIR/null\"`;
        }
        my $RegExp_C = join("|", keys(%CppKeywords_C));
        my $RegExp_F = join("|", keys(%CppKeywords_F));
        my $RegExp_O = join("|", keys(%CppKeywords_O));
        
        my $Detected = undef;
        
        while($Content=~s/(\A|\n[^\#\/\n][^\n]*?|\n)(\*\s*|\s+|\@|\,|\()($RegExp_C|$RegExp_F)(\s*([\,\)\;\.\[]|\-\>|\:\s*\d))/$1$2c99_$3$4/g)
        { # MATCH:
          # int foo(int new, int class, int (*new)(int));
          # int foo(char template[], char*);
          # unsigned private: 8;
          # DO NOT MATCH:
          # #pragma GCC visibility push(default)
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3$4" if(not defined $Detected);
        }
        if($Content=~s/([^\w\s]|\w\s+)(?<!operator )(delete)(\s*\()/$1c99_$2$3/g)
        { # MATCH:
          # int delete(...);
          # int explicit(...);
          # DO NOT MATCH:
          # void operator delete(...)
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\s+)($RegExp_O)(\s*(\;|\:))/$1c99_$2$3/g)
        { # MATCH:
          # int bool;
          # DO NOT MATCH:
          # bool X;
          # return *this;
          # throw;
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\s+)(operator)(\s*(\(\s*\)\s*[^\(\s]|\(\s*[^\)\s]))/$1c99_$2$3/g)
        { # MATCH:
          # int operator(...);
          # DO NOT MATCH:
          # int operator()(...);
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/([^\w\(\,\s]\s*|\s+)(operator)(\s*(\,\s*[^\(\s]|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(int operator);
          # int foo(int operator, int other);
          # DO NOT MATCH:
          # int operator,(...);
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\*\s*|\w\s+)(bool)(\s*(\,|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(gboolean *bool);
          # DO NOT MATCH:
          # void setTabEnabled(int index, bool);
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3" if(not defined $Detected);
        }
        if($Content=~s/(\w)(\s*[^\w\(\,\s]\s*|\s+)(this|throw)(\s*[\,\)])/$1$2c99_$3$4/g)
        { # MATCH:
          # int foo(int* this);
          # int bar(int this);
          # int baz(int throw);
          # DO NOT MATCH:
          # foo(X, this);
            $CppMode{$Version} = 1;
            $Detected = "$1$2$3$4" if(not defined $Detected);
        }
        if($Content=~s/(struct |extern )(template) /$1c99_$2 /g)
        { # MATCH:
          # struct template {...};
          # extern template foo(...);
            $CppMode{$Version} = 1;
            $Detected = "$1$2" if(not defined $Detected);
        }
        
        if($CppMode{$Version} == 1)
        {
            if($Debug)
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
                $CppMode{$Version} = 1;
                
                if($Debug) {
                    printMsg("INFO", "Detected code: \"typedef enum $S $S;\"");
                }
            }
            $N+=2;
        }
        
        if($CppMode{$Version}==1) {
            printMsg("INFO", "Using C++ compatibility mode");
        }
    }
        
    if($CppMode{$Version}==1
    or $MinGWMode{$Version}==1)
    {
        my $IPath = $TMP_DIR."/dump$Version.i";
        writeFile($IPath, $Content);
        return $IPath;
    }
    
    return undef;
}

sub getDump()
{
    if(not $GCC_PATH) {
        exitStatus("Error", "internal error - GCC path is not set");
    }
    
    my @Headers = keys(%{$Registered_Headers{$Version}});
    @Headers = sort {int($Registered_Headers{$Version}{$a}{"Pos"})<=>int($Registered_Headers{$Version}{$b}{"Pos"})} @Headers;
    
    my $IncludeString = getIncString(getIncPaths(@{$Include_Preamble{$Version}}, @Headers), "GCC");
    
    my $TmpHeaderPath = $TMP_DIR."/dump".$Version.".h";
    my $HeaderPath = $TmpHeaderPath;
    
    # write tmp-header
    open(TMP_HEADER, ">", $TmpHeaderPath) || die ("can't open file \'$TmpHeaderPath\': $!\n");
    if(my $AddDefines = $Descriptor{$Version}{"Defines"})
    {
        $AddDefines=~s/\n\s+/\n  /g;
        print TMP_HEADER "\n  // add defines\n  ".$AddDefines."\n";
    }
    print TMP_HEADER "\n  // add includes\n";
    foreach my $HPath (@{$Include_Preamble{$Version}}) {
        print TMP_HEADER "  #include \"".path_format($HPath, "unix")."\"\n";
    }
    foreach my $HPath (@Headers)
    {
        if(not grep {$HPath eq $_} (@{$Include_Preamble{$Version}})) {
            print TMP_HEADER "  #include \"".path_format($HPath, "unix")."\"\n";
        }
    }
    close(TMP_HEADER);
    
    if($ExtraInfo)
    { # extra information for other tools
        if($IncludeString) {
            writeFile($ExtraInfo."/include-string", $IncludeString);
        }
        writeFile($ExtraInfo."/recursive-includes", Dumper($RecursiveIncludes{$Version}));
        writeFile($ExtraInfo."/direct-includes", Dumper($Header_Includes{$Version}));
        
        if(my @Redirects = keys(%{$Header_ErrorRedirect{$Version}}))
        {
            my $REDIR = "";
            foreach my $P1 (sort @Redirects) {
                $REDIR .= $P1.";".$Header_ErrorRedirect{$Version}{$P1}."\n";
            }
            writeFile($ExtraInfo."/include-redirect", $REDIR);
        }
    }
    
    if(not keys(%{$TargetHeaders{$Version}}))
    { # Target headers
        addTargetHeaders($Version);
    }
    
    # clean memory
    %RecursiveIncludes = ();
    %Header_Include_Prefix = ();
    %Header_Includes = ();
    
    # clean cache
    delete($Cache{"identifyHeader"});
    delete($Cache{"detect_header_includes"});
    delete($Cache{"selectSystemHeader"});
    
    # preprocessing stage
    my $Pre = callPreprocessor($TmpHeaderPath, $IncludeString, $Version);
    checkPreprocessedUnit($Pre);
    
    if($ExtraInfo)
    { # extra information for other tools
        writeFile($ExtraInfo."/header-paths", join("\n", sort keys(%{$PreprocessedHeaders{$Version}})));
    }
    
    # clean memory
    delete($Include_Neighbors{$Version});
    delete($PreprocessedHeaders{$Version});
    
    if($COMMON_LANGUAGE{$Version} eq "C++") {
        checkCTags($Pre);
    }
    
    if(my $PrePath = preChange($TmpHeaderPath, $IncludeString))
    { # try to correct the preprocessor output
        $HeaderPath = $PrePath;
    }
    
    if($COMMON_LANGUAGE{$Version} eq "C++")
    { # add classes and namespaces to the dump
        my $CHdump = "-fdump-class-hierarchy -c";
        if($CppMode{$Version}==1
        or $MinGWMode{$Version}==1) {
            $CHdump .= " -fpreprocessed";
        }
        my $ClassHierarchyCmd = getCompileCmd($HeaderPath, $CHdump, $IncludeString);
        chdir($TMP_DIR);
        system($ClassHierarchyCmd." >null 2>&1");
        chdir($ORIG_DIR);
        if(my $ClassDump = (cmd_find($TMP_DIR,"f","*.class",1))[0])
        {
            my $Content = readFile($ClassDump);
            foreach my $ClassInfo (split(/\n\n/, $Content))
            {
                if($ClassInfo=~/\AClass\s+(.+)\s*/i)
                {
                    my $CName = $1;
                    next if($CName=~/\A(__|_objc_|_opaque_)/);
                    $TUnit_NameSpaces{$Version}{$CName} = -1;
                    if($CName=~/\A[\w:]+\Z/)
                    { # classes
                        $TUnit_Classes{$Version}{$CName} = 1;
                    }
                    if($CName=~/(\w[\w:]*)::/)
                    { # namespaces
                        my $NS = $1;
                        if(not defined $TUnit_NameSpaces{$Version}{$NS}) {
                            $TUnit_NameSpaces{$Version}{$NS} = 1;
                        }
                    }
                }
                elsif($ClassInfo=~/\AVtable\s+for\s+(.+)\n((.|\n)+)\Z/i)
                { # read v-tables (advanced approach)
                    my ($CName, $VTable) = ($1, $2);
                    $ClassVTable_Content{$Version}{$CName} = $VTable;
                }
            }
            foreach my $NS (keys(%{$AddNameSpaces{$Version}}))
            { # add user-defined namespaces
                $TUnit_NameSpaces{$Version}{$NS} = 1;
            }
            if($Debug)
            { # debug mode
                mkpath($DEBUG_PATH{$Version});
                copy($ClassDump, $DEBUG_PATH{$Version}."/class-hierarchy-dump.txt");
            }
            unlink($ClassDump);
        }
        
        # add namespaces and classes
        if(my $NS_Add = get_namespace_additions($TUnit_NameSpaces{$Version}))
        { # GCC on all supported platforms does not include namespaces to the dump by default
            appendFile($HeaderPath, "\n  // add namespaces\n".$NS_Add);
        }
        # some GCC versions don't include class methods to the TU dump by default
        my ($AddClass, $ClassNum) = ("", 0);
        my $GCC_44 = check_gcc($GCC_PATH, "4.4"); # support for old GCC versions
        foreach my $CName (sort keys(%{$TUnit_Classes{$Version}}))
        {
            next if($C_Structure{$CName});
            next if(not $STDCXX_TESTING and $CName=~/\Astd::/);
            next if($SkipTypes{$Version}{$CName});
            if(not $Force and $GCC_44
            and $OSgroup eq "linux")
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
                and $TUnit_Classes{$Version}{$1})
                { # classes inside other classes
                    next;
                }
            }
            if(defined $TUnit_Funcs{$Version}{$CName})
            { # the same name for a function and type
                next;
            }
            if(defined $TUnit_Vars{$Version}{$CName})
            { # the same name for a variable and type
                next;
            }
            $AddClass .= "  $CName* tmp_add_class_".($ClassNum++).";\n";
        }
        if($AddClass) {
            appendFile($HeaderPath, "\n  // add classes\n".$AddClass);
        }
    }
    writeLog($Version, "Temporary header file \'$TmpHeaderPath\' with the following content will be compiled to create GCC translation unit dump:\n".readFile($TmpHeaderPath)."\n");
    # create TU dump
    my $TUdump = "-fdump-translation-unit -fkeep-inline-functions -c";
    if($UserLang eq "C") {
        $TUdump .= " -U__cplusplus -D_Bool=\"bool\"";
    }
    if($CppMode{$Version}==1
    or $MinGWMode{$Version}==1) {
        $TUdump .= " -fpreprocessed";
    }
    my $SyntaxTreeCmd = getCompileCmd($HeaderPath, $TUdump, $IncludeString);
    writeLog($Version, "The GCC parameters:\n  $SyntaxTreeCmd\n\n");
    chdir($TMP_DIR);
    system($SyntaxTreeCmd." >\"$TMP_DIR/tu_errors\" 2>&1");
    my $Errors = "";
    if($?)
    { # failed to compile, but the TU dump still can be created
        if($Errors = readFile($TMP_DIR."/tu_errors"))
        { # try to recompile
          # FIXME: handle other errors and try to recompile
            if($CppMode{$Version}==1
            and index($Errors, "c99_")!=-1
            and not defined $CppIncompat)
            { # disable c99 mode and try again
                $CppMode{$Version}=-1;
                
                if($Debug)
                {
                    # printMsg("INFO", $Errors);
                }
                
                printMsg("INFO", "Disabling C++ compatibility mode");
                resetLogging($Version);
                $TMP_DIR = tempdir(CLEANUP=>1);
                return getDump();
            }
            elsif($AutoPreambleMode{$Version}!=-1
            and my $AddHeaders = detectPreamble($Errors, $Version))
            { # add auto preamble headers and try again
                $AutoPreambleMode{$Version}=-1;
                my @Headers = sort {$b cmp $a} keys(%{$AddHeaders}); # sys/types.h should be the first
                foreach my $Num (0 .. $#Headers)
                {
                    my $Path = $Headers[$Num];
                    if(not grep {$Path eq $_} (@{$Include_Preamble{$Version}}))
                    {
                        push_U($Include_Preamble{$Version}, $Path);
                        printMsg("INFO", "Add \'".$AddHeaders->{$Path}{"Header"}."\' preamble header for \'".$AddHeaders->{$Path}{"Type"}."\'");
                    }
                }
                resetLogging($Version);
                $TMP_DIR = tempdir(CLEANUP=>1);
                return getDump();
            }
            elsif($Cpp0xMode{$Version}!=-1
            and ($Errors=~/\Q-std=c++0x\E/
            or $Errors=~/is not a class or namespace/))
            { # c++0x: enum class
                if(check_gcc($GCC_PATH, "4.6"))
                {
                    $Cpp0xMode{$Version}=-1;
                    printMsg("INFO", "Enabling c++0x mode");
                    resetLogging($Version);
                    $TMP_DIR = tempdir(CLEANUP=>1);
                    $CompilerOptions{$Version} .= " -std=c++0x";
                    return getDump();
                }
                else {
                    printMsg("WARNING", "Probably c++0x construction detected");
                }
                
            }
            elsif($MinGWMode{$Version}==1)
            { # disable MinGW mode and try again
                $MinGWMode{$Version}=-1;
                resetLogging($Version);
                $TMP_DIR = tempdir(CLEANUP=>1);
                return getDump();
            }
            writeLog($Version, $Errors);
        }
        else {
            writeLog($Version, "$!: $?\n");
        }
        printMsg("ERROR", "some errors occurred when compiling headers");
        printErrorLog($Version);
        $COMPILE_ERRORS = $ERROR_CODE{"Compile_Error"};
        writeLog($Version, "\n"); # new line
    }
    chdir($ORIG_DIR);
    unlink($TmpHeaderPath);
    unlink($HeaderPath);
    
    if(my @TUs = cmd_find($TMP_DIR,"f","*.tu",1)) {
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

sub cmd_file($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -e $Path);
    if(my $CmdPath = get_CmdPath("file")) {
        return `$CmdPath -b \"$Path\"`;
    }
    return "";
}

sub getIncString($$)
{
    my ($ArrRef, $Style) = @_;
    return "" if(not $ArrRef or $#{$ArrRef}<0);
    my $String = "";
    foreach (@{$ArrRef}) {
        $String .= " ".inc_opt($_, $Style);
    }
    return $String;
}

sub getIncPaths(@)
{
    my @HeaderPaths = @_;
    my @IncPaths = @{$Add_Include_Paths{$Version}};
    if($INC_PATH_AUTODETECT{$Version})
    { # auto-detecting dependencies
        my %Includes = ();
        foreach my $HPath (@HeaderPaths)
        {
            foreach my $Dir (get_HeaderDeps($HPath, $Version))
            {
                if($Skip_Include_Paths{$Version}{$Dir}) {
                    next;
                }
                if($SystemRoot)
                {
                    if($Skip_Include_Paths{$Version}{$SystemRoot.$Dir}) {
                        next;
                    }
                }
                $Includes{$Dir} = 1;
            }
        }
        foreach my $Dir (@{sortIncPaths([keys(%Includes)], $Version)}) {
            push_U(\@IncPaths, $Dir);
        }
    }
    else
    { # user-defined paths
        @IncPaths = @{$Include_Paths{$Version}};
    }
    return \@IncPaths;
}

sub push_U($@)
{ # push unique
    if(my $Array = shift @_)
    {
        if(@_)
        {
            my %Exist = map {$_=>1} @{$Array};
            foreach my $Elem (@_)
            {
                if(not defined $Exist{$Elem})
                {
                    push(@{$Array}, $Elem);
                    $Exist{$Elem} = 1;
                }
            }
        }
    }
}

sub callPreprocessor($$$)
{
    my ($Path, $Inc, $LibVersion) = @_;
    return "" if(not $Path or not -f $Path);
    my $IncludeString=$Inc;
    if(not $Inc) {
        $IncludeString = getIncString(getIncPaths($Path), "GCC");
    }
    my $Cmd = getCompileCmd($Path, "-dD -E", $IncludeString);
    my $Out = $TMP_DIR."/preprocessed.h";
    system($Cmd." >\"$Out\" 2>\"$TMP_DIR/null\"");
    return $Out;
}

sub cmd_find($;$$$$)
{ # native "find" is much faster than File::Find (~6x)
  # also the File::Find doesn't support --maxdepth N option
  # so using the cross-platform wrapper for the native one
    my ($Path, $Type, $Name, $MaxDepth, $UseRegex) = @_;
    return () if(not $Path or not -e $Path);
    if($OSgroup eq "windows")
    {
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        my $Cmd = "dir \"$Path\" /B /O";
        if($MaxDepth!=1) {
            $Cmd .= " /S";
        }
        if($Type eq "d") {
            $Cmd .= " /AD";
        }
        elsif($Type eq "f") {
            $Cmd .= " /A-D";
        }
        my @Files = split(/\n/, `$Cmd 2>\"$TMP_DIR/null\"`);
        if($Name)
        {
            if(not $UseRegex)
            { # FIXME: how to search file names in MS shell?
              # wildcard to regexp
                $Name=~s/\*/.*/g;
                $Name='\A'.$Name.'\Z';
            }
            @Files = grep { /$Name/i } @Files;
        }
        my @AbsPaths = ();
        foreach my $File (@Files)
        {
            if(not is_abs($File)) {
                $File = join_P($Path, $File);
            }
            if($Type eq "f" and not -f $File)
            { # skip dirs
                next;
            }
            push(@AbsPaths, path_format($File, $OSgroup));
        }
        if($Type eq "d") {
            push(@AbsPaths, $Path);
        }
        return @AbsPaths;
    }
    else
    {
        my $FindCmd = get_CmdPath("find");
        if(not $FindCmd) {
            exitStatus("Not_Found", "can't find a \"find\" command");
        }
        $Path = get_abs_path($Path);
        if(-d $Path and -l $Path
        and $Path!~/\/\Z/)
        { # for directories that are symlinks
            $Path.="/";
        }
        my $Cmd = $FindCmd." \"$Path\"";
        if($MaxDepth) {
            $Cmd .= " -maxdepth $MaxDepth";
        }
        if($Type) {
            $Cmd .= " -type $Type";
        }
        if($Name and not $UseRegex)
        { # wildcards
            $Cmd .= " -name \"$Name\"";
        }
        my $Res = `$Cmd 2>\"$TMP_DIR/null\"`;
        if($? and $!) {
            printMsg("ERROR", "problem with \'find\' utility ($?): $!");
        }
        my @Files = split(/\n/, $Res);
        if($Name and $UseRegex)
        { # regex
            @Files = grep { /$Name/ } @Files;
        }
        return @Files;
    }
}

sub unpackDump($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -e $Path);
    
    $Path = get_abs_path($Path);
    $Path = path_format($Path, $OSgroup);
    my ($Dir, $FileName) = separate_path($Path);
    my $UnpackDir = $TMP_DIR."/unpack";
    rmtree($UnpackDir);
    mkpath($UnpackDir);
    
    if($FileName=~s/\Q.zip\E\Z//g)
    { # *.zip
        my $UnzipCmd = get_CmdPath("unzip");
        if(not $UnzipCmd) {
            exitStatus("Not_Found", "can't find \"unzip\" command");
        }
        chdir($UnpackDir);
        system("$UnzipCmd \"$Path\" >\"$TMP_DIR/null\"");
        if($?) {
            exitStatus("Error", "can't extract \'$Path\' ($?): $!");
        }
        chdir($ORIG_DIR);
        my @Contents = cmd_find($UnpackDir, "f");
        if(not @Contents) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        return $Contents[0];
    }
    elsif($FileName=~s/\Q.tar.gz\E(\.\w+|)\Z//g)
    { # *.tar.gz
      # *.tar.gz.amd64 (dh & cdbs)
        if($OSgroup eq "windows")
        { # -xvzf option is not implemented in tar.exe (2003)
          # use "gzip.exe -k -d -f" + "tar.exe -xvf" instead
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            my $GzipCmd = get_CmdPath("gzip");
            if(not $GzipCmd) {
                exitStatus("Not_Found", "can't find \"gzip\" command");
            }
            chdir($UnpackDir);
            system("$GzipCmd -k -d -f \"$Path\""); # keep input files (-k)
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            system("$TarCmd -xvf \"$Dir\\$FileName.tar\" >\"$TMP_DIR/null\"");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\' ($?): $!");
            }
            chdir($ORIG_DIR);
            unlink($Dir."/".$FileName.".tar");
            my @Contents = cmd_find($UnpackDir, "f");
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return $Contents[0];
        }
        else
        { # Unix, Mac
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            chdir($UnpackDir);
            system("$TarCmd -xvzf \"$Path\" >\"$TMP_DIR/null\"");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\' ($?): $!");
            }
            chdir($ORIG_DIR);
            my @Contents = cmd_find($UnpackDir, "f");
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return $Contents[0];
        }
    }
}

sub createArchive($$)
{
    my ($Path, $To) = @_;
    if(not $To) {
        $To = ".";
    }
    if(not $Path or not -e $Path
    or not -d $To) {
        return "";
    }
    my ($From, $Name) = separate_path($Path);
    if($OSgroup eq "windows")
    { # *.zip
        my $ZipCmd = get_CmdPath("zip");
        if(not $ZipCmd) {
            exitStatus("Not_Found", "can't find \"zip\"");
        }
        my $Pkg = $To."/".$Name.".zip";
        unlink($Pkg);
        chdir($To);
        system("$ZipCmd -j \"$Name.zip\" \"$Path\" >\"$TMP_DIR/null\"");
        if($?)
        { # cannot allocate memory (or other problems with "zip")
            unlink($Path);
            exitStatus("Error", "can't pack the ABI dump: ".$!);
        }
        chdir($ORIG_DIR);
        unlink($Path);
        return $Pkg;
    }
    else
    { # *.tar.gz
        my $TarCmd = get_CmdPath("tar");
        if(not $TarCmd) {
            exitStatus("Not_Found", "can't find \"tar\"");
        }
        my $GzipCmd = get_CmdPath("gzip");
        if(not $GzipCmd) {
            exitStatus("Not_Found", "can't find \"gzip\"");
        }
        my $Pkg = abs_path($To)."/".$Name.".tar.gz";
        unlink($Pkg);
        chdir($From);
        system($TarCmd, "-czf", $Pkg, $Name);
        if($?)
        { # cannot allocate memory (or other problems with "tar")
            unlink($Path);
            exitStatus("Error", "can't pack the ABI dump: ".$!);
        }
        chdir($ORIG_DIR);
        unlink($Path);
        return $To."/".$Name.".tar.gz";
    }
}

sub is_header_file($)
{
    if($_[0]=~/\.($HEADER_EXT)\Z/i) {
        return $_[0];
    }
    return 0;
}

sub is_not_header($)
{
    if($_[0]=~/\.\w+\Z/
    and $_[0]!~/\.($HEADER_EXT)\Z/i) {
        return 1;
    }
    return 0;
}

sub is_header($$$)
{
    my ($Header, $UserDefined, $LibVersion) = @_;
    return 0 if(-d $Header);
    if(-f $Header) {
        $Header = get_abs_path($Header);
    }
    else
    {
        if(is_abs($Header))
        { # incorrect absolute path
            return 0;
        }
        if(my $HPath = identifyHeader($Header, $LibVersion)) {
            $Header = $HPath;
        }
        else
        { # can't find header
            return 0;
        }
    }
    if($Header=~/\.\w+\Z/)
    { # have an extension
        return is_header_file($Header);
    }
    else
    {
        if($UserDefined==2)
        { # specified on the command line
            if(cmd_file($Header)!~/HTML|XML/i) {
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
            or cmd_file($Header)=~/C[\+]*\s+program/i)
            { # !~/HTML|XML|shared|dynamic/i
                return $Header;
            }
        }
    }
    return 0;
}

sub addTargetHeaders($)
{
    my $LibVersion = $_[0];
    foreach my $RegHeader (keys(%{$Registered_Headers{$LibVersion}}))
    {
        my $RegDir = get_dirname($RegHeader);
        $TargetHeaders{$LibVersion}{get_filename($RegHeader)} = 1;
        
        if(not $INC_PATH_AUTODETECT{$LibVersion}) {
            detect_recursive_includes($RegHeader, $LibVersion);
        }
        
        foreach my $RecInc (keys(%{$RecursiveIncludes{$LibVersion}{$RegHeader}}))
        {
            my $Dir = get_dirname($RecInc);
            
            if(familiarDirs($RegDir, $Dir) 
            or $RecursiveIncludes{$LibVersion}{$RegHeader}{$RecInc}!=1)
            { # in the same directory or included by #include "..."
                $TargetHeaders{$LibVersion}{get_filename($RecInc)} = 1;
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
    
    my $DL = get_depth($D1);
    
    my @Dirs1 = ($D1);
    while($DL - get_depth($D1)<=2
    and get_depth($D1)>=4
    and $D1=~s/[\/\\]+[^\/\\]*?\Z//) {
        push(@Dirs1, $D1);
    }
    
    my @Dirs2 = ($D2);
    while(get_depth($D2)>=4
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

sub readHeaders($)
{
    $Version = $_[0];
    printMsg("INFO", "checking header(s) ".$Descriptor{$Version}{"Version"}." ...");
    my $DumpPath = getDump();
    if($Debug)
    { # debug mode
        mkpath($DEBUG_PATH{$Version});
        copy($DumpPath, $DEBUG_PATH{$Version}."/translation-unit-dump.txt");
    }
    getInfo($DumpPath);
}

sub prepareTypes($)
{
    my $LibVersion = $_[0];
    if(not checkDump($LibVersion, "2.0"))
    { # support for old ABI dumps
      # type names have been corrected in ACC 1.22 (dump 2.0 format)
        foreach my $TypeId (keys(%{$TypeInfo{$LibVersion}}))
        {
            my $TName = $TypeInfo{$LibVersion}{$TypeId}{"Name"};
            if($TName=~/\A(\w+)::(\w+)/) {
                my ($P1, $P2) = ($1, $2);
                if($P1 eq $P2) {
                    $TName=~s/\A$P1:\:$P1(\W)/$P1$1/;
                }
                else {
                    $TName=~s/\A(\w+:\:)$P2:\:$P2(\W)/$1$P2$2/;
                }
            }
            $TypeInfo{$LibVersion}{$TypeId}{"Name"} = $TName;
        }
    }
    if(not checkDump($LibVersion, "2.5"))
    { # support for old ABI dumps
      # V < 2.5: array size == "number of elements"
      # V >= 2.5: array size in bytes
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            my %Type = get_PureType($TypeId, $TypeInfo{$LibVersion});
            if($Type{"Type"} eq "Array")
            {
                if(my $Size = $Type{"Size"})
                { # array[N]
                    my %Base = get_OneStep_BaseType($Type{"Tid"}, $TypeInfo{$LibVersion});
                    $Size *= $Base{"Size"};
                    $TypeInfo{$LibVersion}{$TypeId}{"Size"} = "$Size";
                }
                else
                { # array[] is a pointer
                    $TypeInfo{$LibVersion}{$TypeId}{"Size"} = $WORD_SIZE{$LibVersion};
                }
            }
        }
    }
    my $V2 = ($LibVersion==1)?2:1;
    if(not checkDump($LibVersion, "2.7"))
    { # support for old ABI dumps
      # size of "method ptr" corrected in 2.7
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            my %PureType = get_PureType($TypeId, $TypeInfo{$LibVersion});
            if($PureType{"Type"} eq "MethodPtr")
            {
                my %Type = get_Type($TypeId, $LibVersion);
                my $TypeId_2 = getTypeIdByName($PureType{"Name"}, $V2);
                my %Type2 = get_Type($TypeId_2, $V2);
                if($Type{"Size"} ne $Type2{"Size"}) {
                    $TypeInfo{$LibVersion}{$TypeId}{"Size"} = $Type2{"Size"};
                }
            }
        }
    }
}

sub prepareSymbols($)
{
    my $LibVersion = $_[0];
    
    if(not keys(%{$SymbolInfo{$LibVersion}}))
    { # check if input is valid
        if(not $ExtendedCheck)
        {
            if($CheckHeadersOnly) {
                exitStatus("Empty_Set", "the set of public symbols is empty (".$Descriptor{$LibVersion}{"Version"}.")");
            }
            else {
                exitStatus("Empty_Intersection", "the sets of public symbols in headers and libraries have empty intersection (".$Descriptor{$LibVersion}{"Version"}.")");
            }
        }
    }
    
    my $Remangle = 0;
    if(not checkDump(1, "2.10")
    or not checkDump(2, "2.10"))
    { # different formats
        $Remangle = 1;
    }
    if($CheckHeadersOnly)
    { # different languages
        if($UserLang)
        { # --lang=LANG for both versions
            if(($UsedDump{1}{"V"} and $UserLang ne $UsedDump{1}{"L"})
            or ($UsedDump{2}{"V"} and $UserLang ne $UsedDump{2}{"L"}))
            {
                if($UserLang eq "C++")
                { # remangle symbols
                    $Remangle = 1;
                }
                elsif($UserLang eq "C")
                { # remove mangling
                    $Remangle = -1;
                }
            }
        }
    }
    
    foreach my $InfoId (sort {int($b)<=>int($a)} keys(%{$SymbolInfo{$LibVersion}}))
    { # reverse order: D0, D1, D2, D0 (artificial, GCC < 4.5), C1, C2
        if(not checkDump($LibVersion, "2.13"))
        { # support for old ABI dumps
            if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"})
            {
                foreach my $P (keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}}))
                {
                    my $TypeId = $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$P}{"type"};
                    my $DVal = $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$P}{"default"};
                    my $TName = $TypeInfo{$LibVersion}{$TypeId}{"Name"};
                    if(defined $DVal and $DVal ne "")
                    {
                        if($TName eq "char") {
                            $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$P}{"default"} = chr($DVal);
                        }
                        elsif($TName eq "bool") {
                            $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$P}{"default"} = $DVal?"true":"false";
                        }
                    }
                }
            }
        }
        if($SymbolInfo{$LibVersion}{$InfoId}{"Destructor"})
        {
            if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"}
            and keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}})
            and $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{0}{"name"} ne "this")
            { # support for old GCC < 4.5: skip artificial ~dtor(int __in_chrg)
              # + support for old ABI dumps
                next;
            }
        }
        my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
        my $ShortName = $SymbolInfo{$LibVersion}{$InfoId}{"ShortName"};
        my $ClassID = $SymbolInfo{$LibVersion}{$InfoId}{"Class"};
        my $Return = $SymbolInfo{$LibVersion}{$InfoId}{"Return"};
        
        my $SRemangle = 0;
        if(not checkDump(1, "2.12")
        or not checkDump(2, "2.12"))
        { # support for old ABI dumps
            if($ShortName eq "operator>>")
            {
                if(not $SymbolInfo{$LibVersion}{$InfoId}{"Class"})
                { # corrected mangling of operator>>
                    $SRemangle = 1;
                }
            }
            if($SymbolInfo{$LibVersion}{$InfoId}{"Data"})
            {
                if(not $SymbolInfo{$LibVersion}{$InfoId}{"Class"}
                and isConstType($Return, $LibVersion) and $MnglName!~/L\d+$ShortName/)
                { # corrected mangling of const global data
                  # some global data is not mangled in the TU dump: qt_sine_table (Qt 4.8)
                  # and incorrectly mangled by old ACC versions
                    $SRemangle = 1;
                }
            }
        }
        if(not $CheckHeadersOnly)
        { # support for old ABI dumps
            if(not checkDump(1, "2.17")
            or not checkDump(2, "2.17"))
            {
                if($SymbolInfo{$LibVersion}{$InfoId}{"Data"})
                {
                    if(not $SymbolInfo{$LibVersion}{$InfoId}{"Class"})
                    {
                        if(link_symbol($ShortName, $LibVersion, "-Deps"))
                        {
                            $MnglName = $ShortName;
                            $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"} = $MnglName;
                        }
                    }
                }
            }
        }
        if($Remangle==1 or $SRemangle==1)
        { # support for old ABI dumps: some symbols are not mangled in old dumps
          # mangle both sets of symbols (old and new)
          # NOTE: remangling all symbols by the same mangler
            if($MnglName=~/\A_ZN(V|)K/)
            { # mangling may be incorrect on old ABI dumps
              # because of absent "Const" attribute
                $SymbolInfo{$LibVersion}{$InfoId}{"Const"} = 1;
            }
            if($MnglName=~/\A_ZN(K|)V/)
            { # mangling may be incorrect on old ABI dumps
              # because of absent "Volatile" attribute
                $SymbolInfo{$LibVersion}{$InfoId}{"Volatile"} = 1;
            }
            if(($ClassID and $MnglName!~/\A(_Z|\?)/)
            or (not $ClassID and $CheckHeadersOnly)
            or (not $ClassID and not link_symbol($MnglName, $LibVersion, "-Deps")))
            { # support for old ABI dumps, GCC >= 4.0
              # remangling all manually mangled symbols
                if($MnglName = mangle_symbol($InfoId, $LibVersion, "GCC"))
                {
                    $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"} = $MnglName;
                    $MangledNames{$LibVersion}{$MnglName} = 1;
                }
            }
        }
        elsif($Remangle==-1)
        { # remove mangling
            $MnglName = "";
            $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"} = "";
        }
        if(not $MnglName) {
            next;
        }
        
        # NOTE: duplicated entries in the ABI Dump
        if(defined $CompleteSignature{$LibVersion}{$MnglName})
        {
            if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"})
            {
                if($SymbolInfo{$LibVersion}{$InfoId}{"Param"}{0}{"name"} eq "p1")
                {
                    next;
                }
            }
        }
        
        if(not $CompleteSignature{$LibVersion}{$MnglName}{"MnglName"})
        { # NOTE: global data may enter here twice
            %{$CompleteSignature{$LibVersion}{$MnglName}} = %{$SymbolInfo{$LibVersion}{$InfoId}};
            
        }
        if(not checkDump($LibVersion, "2.6"))
        { # support for old dumps
          # add "Volatile" attribute
            if($MnglName=~/_Z(K|)V/) {
                $CompleteSignature{$LibVersion}{$MnglName}{"Volatile"}=1;
            }
        }
        # symbol and its symlink have same signatures
        if($SymVer{$LibVersion}{$MnglName}) {
            %{$CompleteSignature{$LibVersion}{$SymVer{$LibVersion}{$MnglName}}} = %{$SymbolInfo{$LibVersion}{$InfoId}};
        }
        
        if(my $Alias = $CompleteSignature{$LibVersion}{$MnglName}{"Alias"})
        {
            %{$CompleteSignature{$LibVersion}{$Alias}} = %{$SymbolInfo{$LibVersion}{$InfoId}};
            
            if($SymVer{$LibVersion}{$Alias}) {
                %{$CompleteSignature{$LibVersion}{$SymVer{$LibVersion}{$Alias}}} = %{$SymbolInfo{$LibVersion}{$InfoId}};
            }
        }
        
        # clean memory
        delete($SymbolInfo{$LibVersion}{$InfoId});
    }
    if($COMMON_LANGUAGE{$LibVersion} eq "C++" or $OSgroup eq "windows") {
        translateSymbols(keys(%{$CompleteSignature{$LibVersion}}), $LibVersion);
    }
    if($ExtendedCheck)
    { # --ext option
        addExtension($LibVersion);
    }
    
    # clean memory
    delete($SymbolInfo{$LibVersion});
    
    foreach my $Symbol (keys(%{$CompleteSignature{$LibVersion}}))
    { # detect allocable classes with public exported constructors
      # or classes with auto-generated or inline-only constructors
      # and other temp info
        if(my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"})
        {
            my $ClassName = $TypeInfo{$LibVersion}{$ClassId}{"Name"};
            if($CompleteSignature{$LibVersion}{$Symbol}{"Constructor"}
            and not $CompleteSignature{$LibVersion}{$Symbol}{"InLine"})
            { # Class() { ... } will not be exported
                if(not $CompleteSignature{$LibVersion}{$Symbol}{"Private"})
                {
                    if($CheckHeadersOnly or link_symbol($Symbol, $LibVersion, "-Deps")) {
                        $AllocableClass{$LibVersion}{$ClassName} = 1;
                    }
                }
            }
            if(not $CompleteSignature{$LibVersion}{$Symbol}{"Private"})
            { # all imported class methods
                if(symbolFilter($Symbol, $LibVersion, "Affected", "Binary"))
                {
                    if($CheckHeadersOnly)
                    {
                        if(not $CompleteSignature{$LibVersion}{$Symbol}{"InLine"}
                        or $CompleteSignature{$LibVersion}{$Symbol}{"Virt"})
                        { # all symbols except non-virtual inline
                            $ClassMethods{"Binary"}{$LibVersion}{$ClassName}{$Symbol} = 1;
                        }
                    }
                    else {
                        $ClassMethods{"Binary"}{$LibVersion}{$ClassName}{$Symbol} = 1;
                    }
                }
                if(symbolFilter($Symbol, $LibVersion, "Affected", "Source")) {
                    $ClassMethods{"Source"}{$LibVersion}{$ClassName}{$Symbol} = 1;
                }
            }
            $ClassNames{$LibVersion}{$ClassName} = 1;
        }
        if(my $RetId = $CompleteSignature{$LibVersion}{$Symbol}{"Return"})
        {
            my %Base = get_BaseType($RetId, $LibVersion);
            if(defined $Base{"Type"}
            and $Base{"Type"}=~/Struct|Class/)
            {
                my $Name = $TypeInfo{$LibVersion}{$Base{"Tid"}}{"Name"};
                if($Name=~/<([^<>\s]+)>/)
                {
                    if(my $Tid = getTypeIdByName($1, $LibVersion)) {
                        $ReturnedClass{$LibVersion}{$Tid} = 1;
                    }
                }
                else {
                    $ReturnedClass{$LibVersion}{$Base{"Tid"}} = 1;
                }
            }
        }
        foreach my $Num (keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
        {
            my $PId = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$Num}{"type"};
            if(get_PLevel($PId, $LibVersion)>=1)
            {
                if(my %Base = get_BaseType($PId, $LibVersion))
                {
                    if($Base{"Type"}=~/Struct|Class/)
                    {
                        $ParamClass{$LibVersion}{$Base{"Tid"}}{$Symbol} = 1;
                        foreach my $SubId (get_sub_classes($Base{"Tid"}, $LibVersion, 1))
                        { # mark all derived classes
                            $ParamClass{$LibVersion}{$SubId}{$Symbol} = 1;
                        }
                    }
                }
            }
        }
        
        # mapping {short name => symbols}
        $Func_ShortName{$LibVersion}{$CompleteSignature{$LibVersion}{$Symbol}{"ShortName"}}{$Symbol} = 1;
    }
    foreach my $MnglName (keys(%VTableClass))
    { # reconstruct attributes of v-tables
        if(index($MnglName, "_ZTV")==0)
        {
            if(my $ClassName = $VTableClass{$MnglName})
            {
                if(my $ClassId = $TName_Tid{$LibVersion}{$ClassName})
                {
                    $CompleteSignature{$LibVersion}{$MnglName}{"Header"} = $TypeInfo{$LibVersion}{$ClassId}{"Header"};
                    $CompleteSignature{$LibVersion}{$MnglName}{"Class"} = $ClassId;
                }
            }
        }
    }
    
    # types
    foreach my $TypeId (keys(%{$TypeInfo{$LibVersion}}))
    {
        if(my $TName = $TypeInfo{$LibVersion}{$TypeId}{"Name"})
        {
            if(defined $TypeInfo{$LibVersion}{$TypeId}{"VTable"}) {
                $ClassNames{$LibVersion}{$TName} = 1;
            }
            if(defined $TypeInfo{$LibVersion}{$TypeId}{"Base"})
            {
                $ClassNames{$LibVersion}{$TName} = 1;
                foreach my $Bid (keys(%{$TypeInfo{$LibVersion}{$TypeId}{"Base"}}))
                {
                    if(my $BName = $TypeInfo{$LibVersion}{$Bid}{"Name"}) {
                        $ClassNames{$LibVersion}{$BName} = 1;
                    }
                }
            }
        }
    }
}

sub getFirst($$)
{
    my ($Tid, $LibVersion) = @_;
    if(not $Tid) {
        return $Tid;
    }
    
    if(my $Name = $TypeInfo{$LibVersion}{$Tid}{"Name"})
    {
        if($TName_Tid{$LibVersion}{$Name}) {
            return $TName_Tid{$LibVersion}{$Name};
        }
    }
    
    return $Tid;
}

sub register_SymbolUsage($$$)
{
    my ($InfoId, $UsedType, $LibVersion) = @_;
    
    my %FuncInfo = %{$SymbolInfo{$LibVersion}{$InfoId}};
    if(my $RTid = getFirst($FuncInfo{"Return"}, $LibVersion))
    {
        register_TypeUsage($RTid, $UsedType, $LibVersion);
        $SymbolInfo{$LibVersion}{$InfoId}{"Return"} = $RTid;
    }
    if(my $FCid = getFirst($FuncInfo{"Class"}, $LibVersion))
    {
        register_TypeUsage($FCid, $UsedType, $LibVersion);
        $SymbolInfo{$LibVersion}{$InfoId}{"Class"} = $FCid;
        
        if(my $ThisId = getTypeIdByName($TypeInfo{$LibVersion}{$FCid}{"Name"}."*const", $LibVersion))
        { # register "this" pointer
            register_TypeUsage($ThisId, $UsedType, $LibVersion);
        }
        if(my $ThisId_C = getTypeIdByName($TypeInfo{$LibVersion}{$FCid}{"Name"}."const*const", $LibVersion))
        { # register "this" pointer (const method)
            register_TypeUsage($ThisId_C, $UsedType, $LibVersion);
        }
    }
    foreach my $PPos (keys(%{$FuncInfo{"Param"}}))
    {
        if(my $PTid = getFirst($FuncInfo{"Param"}{$PPos}{"type"}, $LibVersion))
        {
            register_TypeUsage($PTid, $UsedType, $LibVersion);
            $FuncInfo{"Param"}{$PPos}{"type"} = $PTid;
        }
    }
    foreach my $TPos (keys(%{$FuncInfo{"TParam"}}))
    {
        my $TPName = $FuncInfo{"TParam"}{$TPos}{"name"};
        if(my $TTid = $TName_Tid{$LibVersion}{$TPName}) {
            register_TypeUsage($TTid, $UsedType, $LibVersion);
        }
    }
}

sub register_TypeUsage($$$)
{
    my ($TypeId, $UsedType, $LibVersion) = @_;
    if(not $TypeId) {
        return;
    }
    if($UsedType->{$TypeId})
    { # already registered
        return;
    }
    
    my %TInfo = get_Type($TypeId, $LibVersion);
    if($TInfo{"Type"})
    {
        if(my $NS = $TInfo{"NameSpace"})
        {
            if(my $NSTid = $TName_Tid{$LibVersion}{$NS}) {
                register_TypeUsage($NSTid, $UsedType, $LibVersion);
            }
        }
        
        if($TInfo{"Type"}=~/\A(Struct|Union|Class|FuncPtr|Func|MethodPtr|FieldPtr|Enum)\Z/)
        {
            $UsedType->{$TypeId} = 1;
            if($TInfo{"Type"}=~/\A(Struct|Class)\Z/)
            {
                foreach my $BaseId (keys(%{$TInfo{"Base"}})) {
                    register_TypeUsage($BaseId, $UsedType, $LibVersion);
                }
                foreach my $TPos (keys(%{$TInfo{"TParam"}}))
                {
                    my $TPName = $TInfo{"TParam"}{$TPos}{"name"};
                    if(my $TTid = $TName_Tid{$LibVersion}{$TPName}) {
                        register_TypeUsage($TTid, $UsedType, $LibVersion);
                    }
                }
            }
            foreach my $Memb_Pos (keys(%{$TInfo{"Memb"}}))
            {
                if(my $MTid = getFirst($TInfo{"Memb"}{$Memb_Pos}{"type"}, $LibVersion))
                {
                    register_TypeUsage($MTid, $UsedType, $LibVersion);
                    $TInfo{"Memb"}{$Memb_Pos}{"type"} = $MTid;
                }
            }
            if($TInfo{"Type"} eq "FuncPtr"
            or $TInfo{"Type"} eq "MethodPtr"
            or $TInfo{"Type"} eq "Func")
            {
                if(my $RTid = $TInfo{"Return"}) {
                    register_TypeUsage($RTid, $UsedType, $LibVersion);
                }
                foreach my $PPos (keys(%{$TInfo{"Param"}}))
                {
                    if(my $PTid = $TInfo{"Param"}{$PPos}{"type"}) {
                        register_TypeUsage($PTid, $UsedType, $LibVersion);
                    }
                }
            }
            if($TInfo{"Type"} eq "FieldPtr")
            {
                if(my $RTid = $TInfo{"Return"}) {
                    register_TypeUsage($RTid, $UsedType, $LibVersion);
                }
                if(my $CTid = $TInfo{"Class"}) {
                    register_TypeUsage($CTid, $UsedType, $LibVersion);
                }
            }
            if($TInfo{"Type"} eq "MethodPtr")
            {
                if(my $CTid = $TInfo{"Class"}) {
                    register_TypeUsage($CTid, $UsedType, $LibVersion);
                }
            }
        }
        elsif($TInfo{"Type"}=~/\A(Const|ConstVolatile|Volatile|Pointer|Ref|Restrict|Array|Typedef)\Z/)
        {
            $UsedType->{$TypeId} = 1;
            if(my $BTid = getFirst($TInfo{"BaseType"}, $LibVersion))
            {
                register_TypeUsage($BTid, $UsedType, $LibVersion);
                $TypeInfo{$LibVersion}{$TypeId}{"BaseType"} = $BTid;
            }
        }
        else
        { # Intrinsic, TemplateParam, TypeName, SizeOf, etc.
            $UsedType->{$TypeId} = 1;
        }
    }
}

sub selectSymbol($$$$)
{ # select symbol to check or to dump
    my ($Symbol, $SInfo, $Level, $LibVersion) = @_;
    
    if($Level eq "Dump")
    {
        if($SInfo->{"Virt"} or $SInfo->{"PureVirt"})
        { # TODO: check if this symbol is from
          # base classes of other target symbols
            return 1;
        }
    }
    
    if(not $STDCXX_TESTING and $Symbol=~/\A(_ZS|_ZNS|_ZNKS)/)
    { # stdc++ interfaces
        return 0;
    }
    
    my $Target = 0;
    if(my $Header = $SInfo->{"Header"}) {
        $Target = (is_target_header($Header, 1) or is_target_header($Header, 2));
    }
    if($ExtendedCheck)
    {
        if(index($Symbol, "external_func_")==0) {
            $Target = 1;
        }
    }
    if($CheckHeadersOnly or $Level eq "Source")
    {
        if($Target)
        {
            if($Level eq "Dump")
            { # dumped
                if($BinaryOnly)
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
        if(link_symbol($Symbol, $LibVersion, "-Deps"))
        { # exported symbols
            return 1;
        }
        if($Level eq "Dump")
        { # dumped
            if($BinaryOnly)
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
            or isInLineInst($SInfo, $LibVersion))
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

sub cleanDump($)
{ # clean data
    my $LibVersion = $_[0];
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        if(not keys(%{$SymbolInfo{$LibVersion}{$InfoId}}))
        {
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
        if(not $MnglName)
        {
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        my $ShortName = $SymbolInfo{$LibVersion}{$InfoId}{"ShortName"};
        if(not $ShortName)
        {
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        if($MnglName eq $ShortName)
        { # remove duplicate data
            delete($SymbolInfo{$LibVersion}{$InfoId}{"MnglName"});
        }
        if(not keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}})) {
            delete($SymbolInfo{$LibVersion}{$InfoId}{"Param"});
        }
        if(not keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"TParam"}})) {
            delete($SymbolInfo{$LibVersion}{$InfoId}{"TParam"});
        }
        delete($SymbolInfo{$LibVersion}{$InfoId}{"Type"});
    }
    foreach my $Tid (keys(%{$TypeInfo{$LibVersion}}))
    {
        if(not keys(%{$TypeInfo{$LibVersion}{$Tid}}))
        {
            delete($TypeInfo{$LibVersion}{$Tid});
            next;
        }
        delete($TypeInfo{$LibVersion}{$Tid}{"Tid"});
        foreach my $Attr ("Header", "Line", "Size", "NameSpace")
        {
            if(not $TypeInfo{$LibVersion}{$Tid}{$Attr}) {
                delete($TypeInfo{$LibVersion}{$Tid}{$Attr});
            }
        }
        if(not keys(%{$TypeInfo{$LibVersion}{$Tid}{"TParam"}})) {
            delete($TypeInfo{$LibVersion}{$Tid}{"TParam"});
        }
    }
}

sub pickType($$)
{
    my ($Tid, $LibVersion) = @_;
    
    if(my $Dupl = $TypeTypedef{$LibVersion}{$Tid})
    {
        if(defined $TypeInfo{$LibVersion}{$Dupl})
        {
            if($TypeInfo{$LibVersion}{$Dupl}{"Name"} eq $TypeInfo{$LibVersion}{$Tid}{"Name"})
            { # duplicate
                return 0;
            }
        }
    }
    
    my $THeader = $TypeInfo{$LibVersion}{$Tid}{"Header"};
    
    if(isBuiltIn($THeader)) {
        return 0;
    }
    
    if($TypeInfo{$LibVersion}{$Tid}{"Type"}!~/Class|Struct|Union|Enum|Typedef/) {
        return 0;
    }
    
    if(isAnon($TypeInfo{$LibVersion}{$Tid}{"Name"})) {
        return 0;
    }
    
    if(selfTypedef($Tid, $LibVersion)) {
        return 0;
    }
    
    if(not isTargetType($Tid, $LibVersion)) {
        return 0;
    }
    
    return 0;
}

sub isTargetType($$)
{
    my ($Tid, $LibVersion) = @_;
    
    if($TypeInfo{$LibVersion}{$Tid}{"Type"}!~/Class|Struct|Union|Enum|Typedef/)
    { # derived
        return 1;
    }
    
    if(my $THeader = $TypeInfo{$LibVersion}{$Tid}{"Header"})
    { # NOTE: header is defined to source if undefined (DWARF dumps)
        if(not is_target_header($THeader, $LibVersion))
        { # from target headers
            return 0;
        }
    }
    else
    { # NOTE: if type is defined in source
        if($UsedDump{$LibVersion}{"Public"})
        {
            if(isPrivateABI($Tid, $LibVersion)) {
                return 0;
            }
            else {
                return 1;
            }
        }
        else {
            return 0;
        }
    }
    
    if($SkipInternalTypes)
    {
        if($TypeInfo{$LibVersion}{$Tid}{"Name"}=~/($SkipInternalTypes)/)
        {
            return 0;
        }
    }
    
    return 1;
}

sub remove_Unused($$)
{ # remove unused data types from the ABI dump
    my ($LibVersion, $Kind) = @_;
    
    my %UsedType = ();
    
    foreach my $InfoId (sort {int($a)<=>int($b)} keys(%{$SymbolInfo{$LibVersion}}))
    {
        register_SymbolUsage($InfoId, \%UsedType, $LibVersion);
    }
    foreach my $Tid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
    {
        if($UsedType{$Tid})
        { # All & Extended
            next;
        }
        
        if($Kind eq "Extended")
        {
            if(pickType($Tid, $LibVersion))
            {
                my %Tree = ();
                register_TypeUsage($Tid, \%Tree, $LibVersion);
                
                my $Tmpl = 0;
                foreach (sort {int($a)<=>int($b)} keys(%Tree))
                {
                    if(defined $TypeInfo{$LibVersion}{$_}{"Template"}
                    or $TypeInfo{$LibVersion}{$_}{"Type"} eq "TemplateParam")
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
    
    foreach my $Tid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
    { # remove unused types
        if($UsedType{$Tid})
        { # All & Extended
            next;
        }
        
        if($Kind eq "Extra")
        {
            my %Tree = ();
            register_TypeUsage($Tid, \%Tree, $LibVersion);
            
            foreach (sort {int($a)<=>int($b)} keys(%Tree))
            {
                if(defined $TypeInfo{$LibVersion}{$_}{"Template"}
                or $TypeInfo{$LibVersion}{$_}{"Type"} eq "TemplateParam")
                {
                    $Delete{$Tid} = 1;
                    last;
                }
            }
        }
        else
        {
            # remove type
            delete($TypeInfo{$LibVersion}{$Tid});
        }
    }
    
    if($Kind eq "Extra")
    { # remove duplicates
        foreach my $Tid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            if($UsedType{$Tid})
            { # All & Extended
                next;
            }
            
            my $Name = $TypeInfo{$LibVersion}{$Tid}{"Name"};
            
            if($TName_Tid{$LibVersion}{$Name} ne $Tid) {
                delete($TypeInfo{$LibVersion}{$Tid});
            }
        }
    }
    
    foreach my $Tid (keys(%Delete))
    {
        delete($TypeInfo{$LibVersion}{$Tid});
    }
}

sub check_Completeness($$)
{
    my ($Info, $LibVersion) = @_;
    
    # data types
    if(defined $Info->{"Memb"})
    {
        foreach my $Pos (keys(%{$Info->{"Memb"}}))
        {
            if(defined $Info->{"Memb"}{$Pos}{"type"}) {
                check_TypeInfo($Info->{"Memb"}{$Pos}{"type"}, $LibVersion);
            }
        }
    }
    if(defined $Info->{"Base"})
    {
        foreach my $Bid (keys(%{$Info->{"Base"}})) {
            check_TypeInfo($Bid, $LibVersion);
        }
    }
    if(defined $Info->{"BaseType"}) {
        check_TypeInfo($Info->{"BaseType"}, $LibVersion);
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
            if(my $Tid = $TName_Tid{$LibVersion}{$TName}) {
                check_TypeInfo($Tid, $LibVersion);
            }
            else
            {
                if(defined $Debug) {
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
                check_TypeInfo($Info->{"Param"}{$Pos}{"type"}, $LibVersion);
            }
        }
    }
    if(defined $Info->{"Return"}) {
        check_TypeInfo($Info->{"Return"}, $LibVersion);
    }
    if(defined $Info->{"Class"}) {
        check_TypeInfo($Info->{"Class"}, $LibVersion);
    }
}

sub check_TypeInfo($$)
{
    my ($Tid, $LibVersion) = @_;
    
    if(defined $CheckedTypeInfo{$LibVersion}{$Tid}) {
        return;
    }
    $CheckedTypeInfo{$LibVersion}{$Tid} = 1;
    
    if(defined $TypeInfo{$LibVersion}{$Tid})
    {
        if(not $TypeInfo{$LibVersion}{$Tid}{"Name"}) {
            printMsg("ERROR", "missed type name ($Tid)");
        }
        check_Completeness($TypeInfo{$LibVersion}{$Tid}, $LibVersion);
    }
    else {
        printMsg("ERROR", "missed type id $Tid");
    }
}

sub selfTypedef($$)
{
    my ($TypeId, $LibVersion) = @_;
    my %Type = get_Type($TypeId, $LibVersion);
    if($Type{"Type"} eq "Typedef")
    {
        my %Base = get_OneStep_BaseType($TypeId, $TypeInfo{$LibVersion});
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

sub addExtension($)
{
    my $LibVersion = $_[0];
    foreach my $Tid (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
    {
        if(pickType($Tid, $LibVersion))
        {
            my $TName = $TypeInfo{$LibVersion}{$Tid}{"Name"};
            $TName=~s/\A(struct|union|class|enum) //;
            my $Symbol = "external_func_".$TName;
            
            %{$CompleteSignature{$LibVersion}{$Symbol}} = (
                "Header" => "extended.h",
                "ShortName" => $Symbol,
                "MnglName" => $Symbol,
                "Param" => { 0 => { "type"=>$Tid, "name"=>"p1" } }
            );
            
            $ExtendedSymbols{$Symbol} = 1;
            $CheckedSymbols{"Binary"}{$Symbol} = 1;
            $CheckedSymbols{"Source"}{$Symbol} = 1;
        }
    }
    $ExtendedSymbols{"external_func_0"} = 1;
    $CheckedSymbols{"Binary"}{"external_func_0"} = 1;
    $CheckedSymbols{"Source"}{"external_func_0"} = 1;
}

sub findMethod($$$)
{
    my ($VirtFunc, $ClassId, $LibVersion) = @_;
    foreach my $BaseClass_Id (keys(%{$TypeInfo{$LibVersion}{$ClassId}{"Base"}}))
    {
        if(my $VirtMethodInClass = findMethod_Class($VirtFunc, $BaseClass_Id, $LibVersion)) {
            return $VirtMethodInClass;
        }
        elsif(my $VirtMethodInBaseClasses = findMethod($VirtFunc, $BaseClass_Id, $LibVersion)) {
            return $VirtMethodInBaseClasses;
        }
    }
    return "";
}

sub findMethod_Class($$$)
{
    my ($VirtFunc, $ClassId, $LibVersion) = @_;
    my $ClassName = $TypeInfo{$LibVersion}{$ClassId}{"Name"};
    return "" if(not defined $VirtualTable{$LibVersion}{$ClassName});
    my $TargetSuffix = get_symbol_suffix($VirtFunc, 1);
    my $TargetShortName = $CompleteSignature{$LibVersion}{$VirtFunc}{"ShortName"};
    foreach my $Candidate (keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
    { # search for interface with the same parameters suffix (overridden)
        if($TargetSuffix eq get_symbol_suffix($Candidate, 1))
        {
            if($CompleteSignature{$LibVersion}{$VirtFunc}{"Destructor"})
            {
                if($CompleteSignature{$LibVersion}{$Candidate}{"Destructor"})
                {
                    if(($VirtFunc=~/D0E/ and $Candidate=~/D0E/)
                    or ($VirtFunc=~/D1E/ and $Candidate=~/D1E/)
                    or ($VirtFunc=~/D2E/ and $Candidate=~/D2E/)) {
                        return $Candidate;
                    }
                }
            }
            else
            {
                if($TargetShortName eq $CompleteSignature{$LibVersion}{$Candidate}{"ShortName"}) {
                    return $Candidate;
                }
            }
        }
    }
    return "";
}

sub registerVTable($)
{
    my $LibVersion = $_[0];
    foreach my $Symbol (keys(%{$CompleteSignature{$LibVersion}}))
    {
        if($CompleteSignature{$LibVersion}{$Symbol}{"Virt"}
        or $CompleteSignature{$LibVersion}{$Symbol}{"PureVirt"})
        {
            my $ClassName = $TypeInfo{$LibVersion}{$CompleteSignature{$LibVersion}{$Symbol}{"Class"}}{"Name"};
            next if(not $STDCXX_TESTING and $ClassName=~/\A(std::|__cxxabi)/);
            if($CompleteSignature{$LibVersion}{$Symbol}{"Destructor"}
            and $Symbol=~/D2E/)
            { # pure virtual D2-destructors are marked as "virt" in the dump
              # virtual D2-destructors are NOT marked as "virt" in the dump
              # both destructors are not presented in the v-table
                next;
            }
            my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Symbol);
            $VirtualTable{$LibVersion}{$ClassName}{$MnglName} = 1;
        }
    }
}

sub registerOverriding($)
{
    my $LibVersion = $_[0];
    my @Classes = keys(%{$VirtualTable{$LibVersion}});
    @Classes = sort {int($TName_Tid{$LibVersion}{$a})<=>int($TName_Tid{$LibVersion}{$b})} @Classes;
    foreach my $ClassName (@Classes)
    {
        foreach my $VirtFunc (keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
        {
            if($CompleteSignature{$LibVersion}{$VirtFunc}{"PureVirt"})
            { # pure virtuals
                next;
            }
            my $ClassId = $TName_Tid{$LibVersion}{$ClassName};
            if(my $Overridden = findMethod($VirtFunc, $ClassId, $LibVersion))
            {
                if($CompleteSignature{$LibVersion}{$Overridden}{"Virt"}
                or $CompleteSignature{$LibVersion}{$Overridden}{"PureVirt"})
                { # both overridden virtual methods
                  # and implemented pure virtual methods
                    $CompleteSignature{$LibVersion}{$VirtFunc}{"Override"} = $Overridden;
                    $OverriddenMethods{$LibVersion}{$Overridden}{$VirtFunc} = 1;
                    delete($VirtualTable{$LibVersion}{$ClassName}{$VirtFunc}); # remove from v-table model
                }
            }
        }
        if(not keys(%{$VirtualTable{$LibVersion}{$ClassName}})) {
            delete($VirtualTable{$LibVersion}{$ClassName});
        }
    }
}

sub setVirtFuncPositions($)
{
    my $LibVersion = $_[0];
    foreach my $ClassName (keys(%{$VirtualTable{$LibVersion}}))
    {
        my ($Num, $Rel) = (1, 0);
        
        if(my @Funcs = sort keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
        {
            if($UsedDump{$LibVersion}{"DWARF"}) {
                @Funcs = sort {int($CompleteSignature{$LibVersion}{$a}{"VirtPos"}) <=> int($CompleteSignature{$LibVersion}{$b}{"VirtPos"})} @Funcs;
            }
            else {
                @Funcs = sort {int($CompleteSignature{$LibVersion}{$a}{"Line"}) <=> int($CompleteSignature{$LibVersion}{$b}{"Line"})} @Funcs;
            }
            foreach my $VirtFunc (@Funcs)
            {
                if($UsedDump{$LibVersion}{"DWARF"}) {
                    $VirtualTable{$LibVersion}{$ClassName}{$VirtFunc} = $CompleteSignature{$LibVersion}{$VirtFunc}{"VirtPos"};
                }
                else {
                    $VirtualTable{$LibVersion}{$ClassName}{$VirtFunc} = $Num++;
                }
                
                # set relative positions
                if(defined $VirtualTable{1}{$ClassName} and defined $VirtualTable{1}{$ClassName}{$VirtFunc}
                and defined $VirtualTable{2}{$ClassName} and defined $VirtualTable{2}{$ClassName}{$VirtFunc})
                { # relative position excluding added and removed virtual functions
                    if(not $CompleteSignature{1}{$VirtFunc}{"Override"}
                    and not $CompleteSignature{2}{$VirtFunc}{"Override"}) {
                        $CompleteSignature{$LibVersion}{$VirtFunc}{"RelPos"} = $Rel++;
                    }
                }
            }
        }
    }
    foreach my $ClassName (keys(%{$ClassNames{$LibVersion}}))
    {
        my $AbsNum = 1;
        foreach my $VirtFunc (getVTable_Model($TName_Tid{$LibVersion}{$ClassName}, $LibVersion)) {
            $VirtualTable_Model{$LibVersion}{$ClassName}{$VirtFunc} = $AbsNum++;
        }
    }
}

sub get_sub_classes($$$)
{
    my ($ClassId, $LibVersion, $Recursive) = @_;
    return () if(not defined $Class_SubClasses{$LibVersion}{$ClassId});
    my @Subs = ();
    foreach my $SubId (keys(%{$Class_SubClasses{$LibVersion}{$ClassId}}))
    {
        if($Recursive)
        {
            foreach my $SubSubId (get_sub_classes($SubId, $LibVersion, $Recursive)) {
                push(@Subs, $SubSubId);
            }
        }
        push(@Subs, $SubId);
    }
    return @Subs;
}

sub get_base_classes($$$)
{
    my ($ClassId, $LibVersion, $Recursive) = @_;
    my %ClassType = get_Type($ClassId, $LibVersion);
    return () if(not defined $ClassType{"Base"});
    my @Bases = ();
    foreach my $BaseId (sort {int($ClassType{"Base"}{$a}{"pos"})<=>int($ClassType{"Base"}{$b}{"pos"})}
    keys(%{$ClassType{"Base"}}))
    {
        if($Recursive)
        {
            foreach my $SubBaseId (get_base_classes($BaseId, $LibVersion, $Recursive)) {
                push(@Bases, $SubBaseId);
            }
        }
        push(@Bases, $BaseId);
    }
    return @Bases;
}

sub getVTable_Model($$)
{ # return an ordered list of v-table elements
    my ($ClassId, $LibVersion) = @_;
    my @Bases = get_base_classes($ClassId, $LibVersion, 1);
    my @Elements = ();
    foreach my $BaseId (@Bases, $ClassId)
    {
        if(my $BName = $TypeInfo{$LibVersion}{$BaseId}{"Name"})
        {
            if(defined $VirtualTable{$LibVersion}{$BName})
            {
                my @VFuncs = keys(%{$VirtualTable{$LibVersion}{$BName}});
                if($UsedDump{$LibVersion}{"DWARF"}) {
                    @VFuncs = sort {int($CompleteSignature{$LibVersion}{$a}{"VirtPos"}) <=> int($CompleteSignature{$LibVersion}{$b}{"VirtPos"})} @VFuncs;
                }
                else {
                    @VFuncs = sort {int($CompleteSignature{$LibVersion}{$a}{"Line"}) <=> int($CompleteSignature{$LibVersion}{$b}{"Line"})} @VFuncs;
                }
                foreach my $VFunc (@VFuncs) {
                    push(@Elements, $VFunc);
                }
            }
        }
    }
    return @Elements;
}

sub getVShift($$)
{
    my ($ClassId, $LibVersion) = @_;
    my @Bases = get_base_classes($ClassId, $LibVersion, 1);
    my $VShift = 0;
    foreach my $BaseId (@Bases)
    {
        if(my $BName = $TypeInfo{$LibVersion}{$BaseId}{"Name"})
        {
            if(defined $VirtualTable{$LibVersion}{$BName}) {
                $VShift+=keys(%{$VirtualTable{$LibVersion}{$BName}});
            }
        }
    }
    return $VShift;
}

sub getShift($$)
{
    my ($ClassId, $LibVersion) = @_;
    my @Bases = get_base_classes($ClassId, $LibVersion, 0);
    my $Shift = 0;
    foreach my $BaseId (@Bases)
    {
        if(my $Size = $TypeInfo{$LibVersion}{$BaseId}{"Size"})
        {
            if($Size!=1)
            { # not empty base class
                $Shift+=$Size;
            }
        }
    }
    return $Shift;
}

sub getVTable_Size($$)
{ # number of v-table elements
    my ($ClassName, $LibVersion) = @_;
    my $Size = 0;
    # three approaches
    if(not $Size)
    { # real size
        if(my %VTable = getVTable_Real($ClassName, $LibVersion)) {
            $Size = keys(%VTable);
        }
    }
    if(not $Size)
    { # shared library symbol size
        if($Size = getSymbolSize($ClassVTable{$ClassName}, $LibVersion)) {
            $Size /= $WORD_SIZE{$LibVersion};
        }
    }
    if(not $Size)
    { # model size
        if(defined $VirtualTable_Model{$LibVersion}{$ClassName}) {
            $Size = keys(%{$VirtualTable_Model{$LibVersion}{$ClassName}}) + 2;
        }
    }
    return $Size;
}

sub isCopyingClass($$)
{
    my ($TypeId, $LibVersion) = @_;
    return $TypeInfo{$LibVersion}{$TypeId}{"Copied"};
}

sub isLeafClass($$)
{
    my ($ClassId, $LibVersion) = @_;
    return (not keys(%{$Class_SubClasses{$LibVersion}{$ClassId}}));
}

sub havePubFields($)
{ # check structured type for public fields
    return isAccessible($_[0], {}, 0, -1);
}

sub isAccessible($$$$)
{ # check interval in structured type for public fields
    my ($TypePtr, $Skip, $Start, $End) = @_;
    return 0 if(not $TypePtr);
    if($End==-1) {
        $End = keys(%{$TypePtr->{"Memb"}})-1;
    }
    foreach my $MemPos (sort {int($a)<=>int($b)} keys(%{$TypePtr->{"Memb"}}))
    {
        if($Skip and $Skip->{$MemPos})
        { # skip removed/added fields
            next;
        }
        if(int($MemPos)>=$Start and int($MemPos)<=$End)
        {
            if(isPublic($TypePtr, $MemPos)) {
                return ($MemPos+1);
            }
        }
    }
    return 0;
}

sub isReserved($)
{ # reserved fields == private
    my $MName = $_[0];
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

sub isPublic($$)
{
    my ($TypePtr, $FieldPos) = @_;
    
    return 0 if(not $TypePtr);
    return 0 if(not defined $TypePtr->{"Memb"}{$FieldPos});
    return 0 if(not defined $TypePtr->{"Memb"}{$FieldPos}{"name"});
    
    my $Access = $TypePtr->{"Memb"}{$FieldPos}{"access"};
    if($Access eq "private")
    { # by access in C++ language
        return 0;
    }
    
    # by name in C language
    # TODO: add other methods to detect private members
    my $MName = $TypePtr->{"Memb"}{$FieldPos}{"name"};
    if($MName=~/priv|abidata|parent_object/i)
    { # C-styled private data
        return 0;
    }
    if(lc($MName) eq "abi")
    { # ABI information/reserved field
        return 0;
    }
    if(isReserved($MName))
    { # reserved fields
        return 0;
    }
    
    return 1;
}

sub getVTable_Real($$)
{
    my ($ClassName, $LibVersion) = @_;
    if(my $ClassId = $TName_Tid{$LibVersion}{$ClassName})
    {
        my %Type = get_Type($ClassId, $LibVersion);
        if(defined $Type{"VTable"}) {
            return %{$Type{"VTable"}};
        }
    }
    return ();
}

sub cmpVTables($)
{
    my $ClassName = $_[0];
    my $Res = cmpVTables_Real($ClassName, 1);
    if($Res==-1) {
        $Res = cmpVTables_Model($ClassName);
    }
    return $Res;
}

sub cmpVTables_Model($)
{
    my $ClassName = $_[0];
    foreach my $Symbol (keys(%{$VirtualTable_Model{1}{$ClassName}}))
    {
        if(not defined $VirtualTable_Model{2}{$ClassName}{$Symbol}) {
            return 1;
        }
    }
    return 0;
}

sub cmpVTables_Real($$)
{
    my ($ClassName, $Strong) = @_;
    if(defined $Cache{"cmpVTables_Real"}{$Strong}{$ClassName}) {
        return $Cache{"cmpVTables_Real"}{$Strong}{$ClassName};
    }
    my %VTable_Old = getVTable_Real($ClassName, 1);
    my %VTable_New = getVTable_Real($ClassName, 2);
    if(not %VTable_Old or not %VTable_New)
    { # old ABI dumps
        return ($Cache{"cmpVTables_Real"}{$Strong}{$ClassName} = -1);
    }
    my %Indexes = map {$_=>1} (keys(%VTable_Old), keys(%VTable_New));
    foreach my $Offset (sort {int($a)<=>int($b)} keys(%Indexes))
    {
        if(not defined $VTable_Old{$Offset})
        { # v-table v.1 < v-table v.2
            return ($Cache{"cmpVTables_Real"}{$Strong}{$ClassName} = $Strong);
        }
        my $Entry1 = $VTable_Old{$Offset};
        if(not defined $VTable_New{$Offset})
        { # v-table v.1 > v-table v.2
            return ($Cache{"cmpVTables_Real"}{$Strong}{$ClassName} = ($Strong or $Entry1!~/__cxa_pure_virtual/));
        }
        my $Entry2 = $VTable_New{$Offset};
        
        $Entry1 = simpleVEntry($Entry1);
        $Entry2 = simpleVEntry($Entry2);
        
        if($Entry1=~/ 0x/ or $Entry2=~/ 0x/)
        { # NOTE: problem with vtable-dumper
            next;
        }
        
        if($Entry1 ne $Entry2)
        { # register as changed
            if($Entry1=~/::([^:]+)\Z/)
            {
                my $M1 = $1;
                if($Entry2=~/::([^:]+)\Z/)
                {
                    my $M2 = $1;
                    if($M1 eq $M2)
                    { # overridden
                        next;
                    }
                }
            }
            if(differentDumps("G"))
            { 
                if($Entry1=~/\A\-(0x|\d+)/ and $Entry2=~/\A\-(0x|\d+)/)
                {
                    # GCC 4.6.1: -0x00000000000000010
                    # GCC 4.7.0: -16
                    next;
                }
            }
            return ($Cache{"cmpVTables_Real"}{$Strong}{$ClassName} = 1);
        }
    }
    return ($Cache{"cmpVTables_Real"}{$Strong}{$ClassName} = 0);
}

sub mergeVTables($)
{ # merging v-tables without diagnostics
    my $Level = $_[0];
    foreach my $ClassName (keys(%{$VirtualTable{1}}))
    {
        my $ClassId = $TName_Tid{1}{$ClassName};
        if(isPrivateABI($ClassId, 1)) {
            next;
        }
        
        if($VTableChanged_M{$ClassName})
        { # already registered
            next;
        }
        if(cmpVTables_Real($ClassName, 0)==1)
        {
            my @Affected = (keys(%{$ClassMethods{$Level}{1}{$ClassName}}));
            foreach my $Symbol (@Affected)
            {
                %{$CompatProblems{$Level}{$Symbol}{"Virtual_Table_Changed_Unknown"}{$ClassName}}=(
                    "Type_Name"=>$ClassName,
                    "Target"=>$ClassName);
            }
        }
    }
}

sub mergeBases($)
{
    my $Level = $_[0];
    foreach my $ClassName (keys(%{$ClassNames{1}}))
    { # detect added and removed virtual functions
        my $ClassId = $TName_Tid{1}{$ClassName};
        next if(not $ClassId);
        
        if(isPrivateABI($ClassId, 1)) {
            next;
        }
        
        if(defined $VirtualTable{2}{$ClassName})
        {
            foreach my $Symbol (keys(%{$VirtualTable{2}{$ClassName}}))
            {
                if($TName_Tid{1}{$ClassName}
                and not defined $VirtualTable{1}{$ClassName}{$Symbol})
                { # added to v-table
                    if(defined $CompleteSignature{1}{$Symbol}
                    and $CompleteSignature{1}{$Symbol}{"Virt"})
                    { # override some method in v.1
                        next;
                    }
                    $AddedInt_Virt{$Level}{$ClassName}{$Symbol} = 1;
                }
            }
        }
        if(defined $VirtualTable{1}{$ClassName})
        {
            foreach my $Symbol (keys(%{$VirtualTable{1}{$ClassName}}))
            {
                if($TName_Tid{2}{$ClassName}
                and not defined $VirtualTable{2}{$ClassName}{$Symbol})
                { # removed from v-table
                    if(defined $CompleteSignature{2}{$Symbol}
                    and $CompleteSignature{2}{$Symbol}{"Virt"})
                    { # override some method in v.2
                        next;
                    }
                    $RemovedInt_Virt{$Level}{$ClassName}{$Symbol} = 1;
                }
            }
        }
        if($Level eq "Binary")
        { # Binary-level
            my %Class_Type = get_Type($ClassId, 1);
            foreach my $AddedVFunc (keys(%{$AddedInt_Virt{$Level}{$ClassName}}))
            { # check replacements, including pure virtual methods
                my $AddedPos = $VirtualTable{2}{$ClassName}{$AddedVFunc};
                foreach my $RemovedVFunc (keys(%{$RemovedInt_Virt{$Level}{$ClassName}}))
                {
                    my $RemovedPos = $VirtualTable{1}{$ClassName}{$RemovedVFunc};
                    if($AddedPos==$RemovedPos)
                    {
                        $VirtualReplacement{$AddedVFunc} = $RemovedVFunc;
                        $VirtualReplacement{$RemovedVFunc} = $AddedVFunc;
                        last; # other methods will be reported as "added" or "removed"
                    }
                }
                if(my $RemovedVFunc = $VirtualReplacement{$AddedVFunc})
                {
                    if(lc($AddedVFunc) eq lc($RemovedVFunc))
                    { # skip: DomUi => DomUI parameter (Qt 4.2.3 to 4.3.0)
                        next;
                    }
                    my $ProblemType = "Virtual_Replacement";
                    my @Affected = ($RemovedVFunc);
                    if($CompleteSignature{1}{$RemovedVFunc}{"PureVirt"})
                    { # pure methods
                        if(not isUsedClass($ClassId, 1, $Level))
                        { # not a parameter of some exported method
                            next;
                        }
                        $ProblemType = "Pure_Virtual_Replacement";
                        
                        # affected all methods (both virtual and non-virtual ones)
                        @Affected = (keys(%{$ClassMethods{$Level}{1}{$ClassName}}));
                        push(@Affected, keys(%{$OverriddenMethods{1}{$RemovedVFunc}}));
                    }
                    $VTableChanged_M{$ClassName}=1;
                    foreach my $AffectedInt (@Affected)
                    {
                        if($CompleteSignature{1}{$AffectedInt}{"PureVirt"})
                        { # affected exported methods only
                            next;
                        }
                        if(not symbolFilter($AffectedInt, 1, "Affected", $Level)) {
                            next;
                        }
                        %{$CompatProblems{$Level}{$AffectedInt}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$Class_Type{"Name"},
                            "Target"=>get_Signature($AddedVFunc, 2),
                            "Old_Value"=>get_Signature($RemovedVFunc, 1));
                    }
                }
            }
        }
    }
    if(not checkDump(1, "2.0")
    or not checkDump(2, "2.0"))
    { # support for old ABI dumps
      # "Base" attribute introduced in ACC 1.22 (ABI dump 2.0 format)
        return;
    }
    foreach my $ClassName (sort keys(%{$ClassNames{1}}))
    {
        my $ClassId_Old = $TName_Tid{1}{$ClassName};
        next if(not $ClassId_Old);
        
        if(isPrivateABI($ClassId_Old, 1)) {
            next;
        }
        
        if(not isCreatable($ClassId_Old, 1))
        { # skip classes without public constructors (including auto-generated)
          # example: class has only a private exported or private inline constructor
            next;
        }
        if($ClassName=~/>/)
        { # skip affected template instances
            next;
        }
        my %Class_Old = get_Type($ClassId_Old, 1);
        my $ClassId_New = $TName_Tid{2}{$ClassName};
        if(not $ClassId_New) {
            next;
        }
        my %Class_New = get_Type($ClassId_New, 2);
        if($Class_New{"Type"}!~/Class|Struct/)
        { # became typedef
            if($Level eq "Binary") {
                next;
            }
            if($Level eq "Source")
            {
                %Class_New = get_PureType($ClassId_New, $TypeInfo{2});
                if($Class_New{"Type"}!~/Class|Struct/) {
                    next;
                }
                $ClassId_New = $Class_New{"Tid"};
            }
        }
        
        if(not $Class_New{"Size"} or not $Class_Old{"Size"})
        { # incomplete info in the ABI dump
            next;
        }
        
        
        my @Bases_Old = sort {$Class_Old{"Base"}{$a}{"pos"}<=>$Class_Old{"Base"}{$b}{"pos"}} keys(%{$Class_Old{"Base"}});
        my @Bases_New = sort {$Class_New{"Base"}{$a}{"pos"}<=>$Class_New{"Base"}{$b}{"pos"}} keys(%{$Class_New{"Base"}});
        
        my %Tr_Old = map {$TypeInfo{1}{$_}{"Name"} => uncover_typedefs($TypeInfo{1}{$_}{"Name"}, 1)} @Bases_Old;
        my %Tr_New = map {$TypeInfo{2}{$_}{"Name"} => uncover_typedefs($TypeInfo{2}{$_}{"Name"}, 2)} @Bases_New;
        
        my ($BNum1, $BNum2) = (1, 1);
        my %BasePos_Old = map {$Tr_Old{$TypeInfo{1}{$_}{"Name"}} => $BNum1++} @Bases_Old;
        my %BasePos_New = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $BNum2++} @Bases_New;
        my %ShortBase_Old = map {get_ShortClass($_, 1) => 1} @Bases_Old;
        my %ShortBase_New = map {get_ShortClass($_, 2) => 1} @Bases_New;
        my $Shift_Old = getShift($ClassId_Old, 1);
        my $Shift_New = getShift($ClassId_New, 2);
        my %BaseId_New = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $_} @Bases_New;
        my ($Added, $Removed) = (0, 0);
        my @StableBases_Old = ();
        foreach my $BaseId (@Bases_Old)
        {
            my $BaseName = $TypeInfo{1}{$BaseId}{"Name"};
            if($BasePos_New{$Tr_Old{$BaseName}}) {
                push(@StableBases_Old, $BaseId);
            }
            elsif(not $ShortBase_New{$Tr_Old{$BaseName}}
            and not $ShortBase_New{get_ShortClass($BaseId, 1)})
            { # removed base
              # excluding namespace::SomeClass to SomeClass renaming
                my $ProblemKind = "Removed_Base_Class";
                if($Level eq "Binary")
                { # Binary-level
                    if($Shift_Old ne $Shift_New)
                    { # affected fields
                        if(havePubFields(\%Class_Old)) {
                            $ProblemKind .= "_And_Shift";
                        }
                        elsif($Class_Old{"Size"} ne $Class_New{"Size"}) {
                            $ProblemKind .= "_And_Size";
                        }
                    }
                    if(keys(%{$VirtualTable_Model{1}{$BaseName}})
                    and cmpVTables($ClassName)==1)
                    { # affected v-table
                        $ProblemKind .= "_And_VTable";
                        $VTableChanged_M{$ClassName}=1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (get_sub_classes($ClassId_Old, 1, 1))
                {
                    if(my $SubName = $TypeInfo{1}{$SubId}{"Name"})
                    {
                        push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                        if($ProblemKind=~/VTable/) {
                            $VTableChanged_M{$SubName}=1;
                        }
                    }
                }
                foreach my $Interface (@Affected)
                {
                    if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                        next;
                    }
                    %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                        "Type_Name"=>$ClassName,
                        "Target"=>$BaseName,
                        "Old_Size"=>$Class_Old{"Size"}*$BYTE_SIZE,
                        "New_Size"=>$Class_New{"Size"}*$BYTE_SIZE,
                        "Shift"=>abs($Shift_New-$Shift_Old)  );
                }
                $Removed+=1;
            }
        }
        my @StableBases_New = ();
        foreach my $BaseId (@Bases_New)
        {
            my $BaseName = $TypeInfo{2}{$BaseId}{"Name"};
            if($BasePos_Old{$Tr_New{$BaseName}}) {
                push(@StableBases_New, $BaseId);
            }
            elsif(not $ShortBase_Old{$Tr_New{$BaseName}}
            and not $ShortBase_Old{get_ShortClass($BaseId, 2)})
            { # added base
              # excluding namespace::SomeClass to SomeClass renaming
                my $ProblemKind = "Added_Base_Class";
                if($Level eq "Binary")
                { # Binary-level
                    if($Shift_Old ne $Shift_New)
                    { # affected fields
                        if(havePubFields(\%Class_Old)) {
                            $ProblemKind .= "_And_Shift";
                        }
                        elsif($Class_Old{"Size"} ne $Class_New{"Size"}) {
                            $ProblemKind .= "_And_Size";
                        }
                    }
                    if(keys(%{$VirtualTable_Model{2}{$BaseName}})
                    and cmpVTables($ClassName)==1)
                    { # affected v-table
                        $ProblemKind .= "_And_VTable";
                        $VTableChanged_M{$ClassName}=1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (get_sub_classes($ClassId_Old, 1, 1))
                {
                    if(my $SubName = $TypeInfo{1}{$SubId}{"Name"})
                    {
                        push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                        if($ProblemKind=~/VTable/) {
                            $VTableChanged_M{$SubName}=1;
                        }
                    }
                }
                foreach my $Interface (@Affected)
                {
                    if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                        next;
                    }
                    %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                        "Type_Name"=>$ClassName,
                        "Target"=>$BaseName,
                        "Old_Size"=>$Class_Old{"Size"}*$BYTE_SIZE,
                        "New_Size"=>$Class_New{"Size"}*$BYTE_SIZE,
                        "Shift"=>abs($Shift_New-$Shift_Old)  );
                }
                $Added+=1;
            }
        }
        if($Level eq "Binary")
        { # Binary-level
            ($BNum1, $BNum2) = (1, 1);
            my %BaseRelPos_Old = map {$Tr_Old{$TypeInfo{1}{$_}{"Name"}} => $BNum1++} @StableBases_Old;
            my %BaseRelPos_New = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $BNum2++} @StableBases_New;
            foreach my $BaseId (@Bases_Old)
            {
                my $BaseName = $TypeInfo{1}{$BaseId}{"Name"};
                if(my $NewPos = $BaseRelPos_New{$Tr_Old{$BaseName}})
                {
                    my $BaseNewId = $BaseId_New{$Tr_Old{$BaseName}};
                    my $OldPos = $BaseRelPos_Old{$Tr_Old{$BaseName}};
                    if($NewPos!=$OldPos)
                    { # changed position of the base class
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                                next;
                            }
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Position"}{"this"}}=(
                                "Type_Name"=>$ClassName,
                                "Target"=>$BaseName,
                                "Old_Value"=>$OldPos-1,
                                "New_Value"=>$NewPos-1  );
                        }
                    }
                    if($Class_Old{"Base"}{$BaseId}{"virtual"}
                    and not $Class_New{"Base"}{$BaseNewId}{"virtual"})
                    { # became non-virtual base
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                                next;
                            }
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Became_Non_Virtually_Inherited"}{"this->".$BaseName}}=(
                                "Type_Name"=>$ClassName,
                                "Target"=>$BaseName  );
                        }
                    }
                    elsif(not $Class_Old{"Base"}{$BaseId}{"virtual"}
                    and $Class_New{"Base"}{$BaseNewId}{"virtual"})
                    { # became virtual base
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                                next;
                            }
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Became_Virtually_Inherited"}{"this->".$BaseName}}=(
                                "Type_Name"=>$ClassName,
                                "Target"=>$BaseName  );
                        }
                    }
                }
            }
            # detect size changes in base classes
            if($Shift_Old!=$Shift_New)
            { # size of allocable class
                foreach my $BaseId (@StableBases_Old)
                { # search for changed base
                    my %BaseType = get_Type($BaseId, 1);
                    my $Size_Old = $TypeInfo{1}{$BaseId}{"Size"};
                    my $Size_New = $TypeInfo{2}{$BaseId_New{$Tr_Old{$BaseType{"Name"}}}}{"Size"};
                    if($Size_Old ne $Size_New
                    and $Size_Old and $Size_New)
                    {
                        my $ProblemType = undef;
                        if(isCopyingClass($BaseId, 1)) {
                            $ProblemType = "Size_Of_Copying_Class";
                        }
                        elsif($AllocableClass{1}{$BaseType{"Name"}})
                        {
                            if($Size_New>$Size_Old)
                            { # increased size
                                $ProblemType = "Size_Of_Allocable_Class_Increased";
                            }
                            else
                            { # decreased size
                                $ProblemType = "Size_Of_Allocable_Class_Decreased";
                                if(not havePubFields(\%Class_Old))
                                { # affected class has no public members
                                    next;
                                }
                            }
                        }
                        next if(not $ProblemType);
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        { # base class size changes affecting current class
                            if(not symbolFilter($Interface, 1, "Affected", $Level)) {
                                next;
                            }
                            %{$CompatProblems{$Level}{$Interface}{$ProblemType}{"this->".$BaseType{"Name"}}}=(
                                "Type_Name"=>$BaseType{"Name"},
                                "Target"=>$BaseType{"Name"},
                                "Old_Size"=>$Size_Old*$BYTE_SIZE,
                                "New_Size"=>$Size_New*$BYTE_SIZE  );
                        }
                    }
                }
            }
            if(defined $VirtualTable_Model{1}{$ClassName}
            and cmpVTables_Real($ClassName, 1)==1
            and my @VFunctions = keys(%{$VirtualTable_Model{1}{$ClassName}}))
            { # compare virtual tables size in base classes
                my $VShift_Old = getVShift($ClassId_Old, 1);
                my $VShift_New = getVShift($ClassId_New, 2);
                if($VShift_Old ne $VShift_New)
                { # changes in the base class or changes in the list of base classes
                    my @AllBases_Old = get_base_classes($ClassId_Old, 1, 1);
                    my @AllBases_New = get_base_classes($ClassId_New, 2, 1);
                    ($BNum1, $BNum2) = (1, 1);
                    my %StableBase = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $_} @AllBases_New;
                    foreach my $BaseId (@AllBases_Old)
                    {
                        my %BaseType = get_Type($BaseId, 1);
                        if(not $StableBase{$Tr_Old{$BaseType{"Name"}}})
                        { # lost base
                            next;
                        }
                        my $VSize_Old = getVTable_Size($BaseType{"Name"}, 1);
                        my $VSize_New = getVTable_Size($BaseType{"Name"}, 2);
                        if($VSize_Old!=$VSize_New)
                        {
                            foreach my $Symbol (@VFunctions)
                            { # TODO: affected non-virtual methods?
                                if(not defined $VirtualTable_Model{2}{$ClassName}{$Symbol})
                                { # Removed_Virtual_Method, will be registered in mergeVirtualTables()
                                    next;
                                }
                                if($VirtualTable_Model{2}{$ClassName}{$Symbol}-$VirtualTable_Model{1}{$ClassName}{$Symbol}==0)
                                { # skip interfaces that have not changed the absolute virtual position
                                    next;
                                }
                                if(not symbolFilter($Symbol, 1, "Affected", $Level)) {
                                    next;
                                }
                                $VTableChanged_M{$BaseType{"Name"}} = 1;
                                $VTableChanged_M{$ClassName} = 1;
                                foreach my $VirtFunc (keys(%{$AddedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: added virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Added_Virtual_Method";
                                    if($CompleteSignature{2}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Added_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{get_Signature($VirtFunc, 2)}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Target"=>get_Signature($VirtFunc, 2)  );
                                }
                                foreach my $VirtFunc (keys(%{$RemovedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: removed virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Removed_Virtual_Method";
                                    if($CompleteSignature{1}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Removed_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{get_Signature($VirtFunc, 1)}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Target"=>get_Signature($VirtFunc, 1)  );
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

sub isCreatable($$)
{
    my ($ClassId, $LibVersion) = @_;
    if($AllocableClass{$LibVersion}{$TypeInfo{$LibVersion}{$ClassId}{"Name"}}
    or isCopyingClass($ClassId, $LibVersion)) {
        return 1;
    }
    if(keys(%{$Class_SubClasses{$LibVersion}{$ClassId}}))
    { # Fix for incomplete data: if this class has
      # a base class then it should also has a constructor 
        return 1;
    }
    if($ReturnedClass{$LibVersion}{$ClassId})
    { # returned by some method of this class
      # or any other class
        return 1;
    }
    return 0;
}

sub isUsedClass($$$)
{
    my ($ClassId, $LibVersion, $Level) = @_;
    if(keys(%{$ParamClass{$LibVersion}{$ClassId}}))
    { # parameter of some exported method
        return 1;
    }
    my $CName = $TypeInfo{$LibVersion}{$ClassId}{"Name"};
    if(keys(%{$ClassMethods{$Level}{$LibVersion}{$CName}}))
    { # method from target class
        return 1;
    }
    return 0;
}

sub mergeVirtualTables($$)
{ # check for changes in the virtual table
    my ($Interface, $Level) = @_;
    # affected methods:
    #  - virtual
    #  - pure-virtual
    #  - non-virtual
    if($CompleteSignature{1}{$Interface}{"Data"})
    { # global data is not affected
        return;
    }
    my $Class_Id = $CompleteSignature{1}{$Interface}{"Class"};
    if(not $Class_Id) {
        return;
    }
    my $CName = $TypeInfo{1}{$Class_Id}{"Name"};
    if(cmpVTables_Real($CName, 1)==0)
    { # no changes
        return;
    }
    $CheckedTypes{$Level}{$CName} = 1;
    if($Level eq "Binary")
    { # Binary-level
        if($CompleteSignature{1}{$Interface}{"PureVirt"}
        and not isUsedClass($Class_Id, 1, $Level))
        { # pure virtuals should not be affected
          # if there are no exported methods using this class
            return;
        }
    }
    foreach my $Func (keys(%{$VirtualTable{1}{$CName}}))
    {
        if(defined $VirtualTable{2}{$CName}{$Func}
        and defined $CompleteSignature{2}{$Func})
        {
            if(not $CompleteSignature{1}{$Func}{"PureVirt"}
            and $CompleteSignature{2}{$Func}{"PureVirt"})
            { # became pure virtual
                %{$CompatProblems{$Level}{$Interface}{"Virtual_Method_Became_Pure"}{$tr_name{$Func}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature_M($Func, 1)  );
                $VTableChanged_M{$CName} = 1;
            }
            elsif($CompleteSignature{1}{$Func}{"PureVirt"}
            and not $CompleteSignature{2}{$Func}{"PureVirt"})
            { # became non-pure virtual
                %{$CompatProblems{$Level}{$Interface}{"Virtual_Method_Became_Non_Pure"}{$tr_name{$Func}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature_M($Func, 1)  );
                $VTableChanged_M{$CName} = 1;
            }
        }
    }
    if($Level eq "Binary")
    { # Binary-level
        # check virtual table structure
        foreach my $AddedVFunc (keys(%{$AddedInt_Virt{$Level}{$CName}}))
        {
            next if($Interface eq $AddedVFunc);
            next if($VirtualReplacement{$AddedVFunc});
            my $VPos_Added = $VirtualTable{2}{$CName}{$AddedVFunc};
            if($CompleteSignature{2}{$AddedVFunc}{"PureVirt"})
            { # pure virtual methods affect all others (virtual and non-virtual)
                %{$CompatProblems{$Level}{$Interface}{"Added_Pure_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature($AddedVFunc, 2)  );
                $VTableChanged_M{$CName} = 1;
            }
            elsif(not defined $VirtualTable{1}{$CName}
            or $VPos_Added>keys(%{$VirtualTable{1}{$CName}}))
            { # added virtual function at the end of v-table
                if(not keys(%{$VirtualTable_Model{1}{$CName}}))
                { # became polymorphous class, added v-table pointer
                    %{$CompatProblems{$Level}{$Interface}{"Added_First_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                        "Type_Name"=>$CName,
                        "Target"=>get_Signature($AddedVFunc, 2)  );
                    $VTableChanged_M{$CName} = 1;
                }
                else
                {
                    my $VSize_Old = getVTable_Size($CName, 1);
                    my $VSize_New = getVTable_Size($CName, 2);
                    next if($VSize_Old==$VSize_New); # exception: register as removed and added virtual method
                    if(isCopyingClass($Class_Id, 1))
                    { # class has no constructors and v-table will be copied by applications, this may affect all methods
                        my $ProblemType = "Added_Virtual_Method";
                        if(isLeafClass($Class_Id, 1)) {
                            $ProblemType = "Added_Virtual_Method_At_End_Of_Leaf_Copying_Class";
                        }
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$CName,
                            "Target"=>get_Signature($AddedVFunc, 2)  );
                        $VTableChanged_M{$CName} = 1;
                    }
                    else
                    {
                        my $ProblemType = "Added_Virtual_Method";
                        if(isLeafClass($Class_Id, 1)) {
                            $ProblemType = "Added_Virtual_Method_At_End_Of_Leaf_Allocable_Class";
                        }
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$CName,
                            "Target"=>get_Signature($AddedVFunc, 2)  );
                        $VTableChanged_M{$CName} = 1;
                    }
                }
            }
            elsif($CompleteSignature{1}{$Interface}{"Virt"}
            or $CompleteSignature{1}{$Interface}{"PureVirt"})
            {
                if(defined $VirtualTable{1}{$CName}
                and defined $VirtualTable{2}{$CName})
                {
                    my $VPos_Old = $VirtualTable{1}{$CName}{$Interface};
                    my $VPos_New = $VirtualTable{2}{$CName}{$Interface};
                    
                    if($VPos_Added<=$VPos_Old and $VPos_Old!=$VPos_New)
                    {
                        my @Affected = ($Interface, keys(%{$OverriddenMethods{1}{$Interface}}));
                        foreach my $ASymbol (@Affected)
                        {
                            if(not $CompleteSignature{1}{$ASymbol}{"PureVirt"})
                            {
                                if(not symbolFilter($ASymbol, 1, "Affected", $Level)) {
                                    next;
                                }
                            }
                            $CheckedSymbols{$Level}{$ASymbol} = 1;
                            %{$CompatProblems{$Level}{$ASymbol}{"Added_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                                "Type_Name"=>$CName,
                                "Target"=>get_Signature($AddedVFunc, 2)  );
                            $VTableChanged_M{$TypeInfo{1}{$CompleteSignature{1}{$ASymbol}{"Class"}}{"Name"}} = 1;
                        }
                    }
                }
            }
            else {
                # safe
            }
        }
        foreach my $RemovedVFunc (keys(%{$RemovedInt_Virt{$Level}{$CName}}))
        {
            next if($VirtualReplacement{$RemovedVFunc});
            if($RemovedVFunc eq $Interface
            and $CompleteSignature{1}{$RemovedVFunc}{"PureVirt"})
            { # This case is for removed virtual methods
              # implemented in both versions of a library
                next;
            }
            if(not keys(%{$VirtualTable_Model{2}{$CName}}))
            { # became non-polymorphous class, removed v-table pointer
                %{$CompatProblems{$Level}{$Interface}{"Removed_Last_Virtual_Method"}{$tr_name{$RemovedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature($RemovedVFunc, 1)  );
                $VTableChanged_M{$CName} = 1;
            }
            elsif($CompleteSignature{1}{$Interface}{"Virt"}
            or $CompleteSignature{1}{$Interface}{"PureVirt"})
            {
                if(defined $VirtualTable{1}{$CName} and defined $VirtualTable{2}{$CName})
                {
                    if(not defined $VirtualTable{1}{$CName}{$Interface}) {
                        next;
                    }
                    my $VPos_New = -1;
                    if(defined $VirtualTable{2}{$CName}{$Interface})
                    {
                        $VPos_New = $VirtualTable{2}{$CName}{$Interface};
                    }
                    else
                    {
                        if($Interface ne $RemovedVFunc) {
                            next;
                        }
                    }
                    my $VPos_Removed = $VirtualTable{1}{$CName}{$RemovedVFunc};
                    my $VPos_Old = $VirtualTable{1}{$CName}{$Interface};
                    if($VPos_Removed<=$VPos_Old and $VPos_Old!=$VPos_New)
                    {
                        my @Affected = ($Interface, keys(%{$OverriddenMethods{1}{$Interface}}));
                        foreach my $ASymbol (@Affected)
                        {
                            if(not $CompleteSignature{1}{$ASymbol}{"PureVirt"})
                            {
                                if(not symbolFilter($ASymbol, 1, "Affected", $Level)) {
                                    next;
                                }
                            }
                            my $ProblemType = "Removed_Virtual_Method";
                            if($CompleteSignature{1}{$RemovedVFunc}{"PureVirt"}) {
                                $ProblemType = "Removed_Pure_Virtual_Method";
                            }
                            $CheckedSymbols{$Level}{$ASymbol} = 1;
                            %{$CompatProblems{$Level}{$ASymbol}{$ProblemType}{$tr_name{$RemovedVFunc}}}=(
                                "Type_Name"=>$CName,
                                "Target"=>get_Signature($RemovedVFunc, 1)  );
                            $VTableChanged_M{$TypeInfo{1}{$CompleteSignature{1}{$ASymbol}{"Class"}}{"Name"}} = 1;
                        }
                    }
                }
            }
        }
    }
    else
    { # Source-level
        foreach my $AddedVFunc (keys(%{$AddedInt_Virt{$Level}{$CName}}))
        {
            next if($Interface eq $AddedVFunc);
            if($CompleteSignature{2}{$AddedVFunc}{"PureVirt"})
            {
                %{$CompatProblems{$Level}{$Interface}{"Added_Pure_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature($AddedVFunc, 2)  );
            }
        }
        foreach my $RemovedVFunc (keys(%{$RemovedInt_Virt{$Level}{$CName}}))
        {
            if($CompleteSignature{1}{$RemovedVFunc}{"PureVirt"})
            {
                %{$CompatProblems{$Level}{$Interface}{"Removed_Pure_Virtual_Method"}{$tr_name{$RemovedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Target"=>get_Signature($RemovedVFunc, 1)  );
            }
        }
    }
}

sub find_MemberPair_Pos_byName($$)
{
    my ($Member_Name, $Pair_Type) = @_;
    $Member_Name=~s/\A[_]+|[_]+\Z//g;
    foreach my $MemberPair_Pos (sort {int($a)<=>int($b)} keys(%{$Pair_Type->{"Memb"}}))
    {
        if(defined $Pair_Type->{"Memb"}{$MemberPair_Pos})
        {
            my $Name = $Pair_Type->{"Memb"}{$MemberPair_Pos}{"name"};
            $Name=~s/\A[_]+|[_]+\Z//g;
            if($Name eq $Member_Name) {
                return $MemberPair_Pos;
            }
        }
    }
    return "lost";
}

sub find_MemberPair_Pos_byVal($$)
{
    my ($Member_Value, $Pair_Type) = @_;
    foreach my $MemberPair_Pos (sort {int($a)<=>int($b)} keys(%{$Pair_Type->{"Memb"}}))
    {
        if(defined $Pair_Type->{"Memb"}{$MemberPair_Pos}
        and $Pair_Type->{"Memb"}{$MemberPair_Pos}{"value"} eq $Member_Value) {
            return $MemberPair_Pos;
        }
    }
    return "lost";
}

sub isRecurType($$$)
{
    foreach (@{$_[2]})
    {
        if( $_->{"T1"} eq $_[0]
        and $_->{"T2"} eq $_[1] )
        {
            return 1;
        }
    }
    return 0;
}

sub pushType($$$)
{
    my %IDs = (
        "T1" => $_[0],
        "T2" => $_[1]
    );
    push(@{$_[2]}, \%IDs);
}

sub isRenamed($$$$$)
{
    my ($MemPos, $Type1, $LVersion1, $Type2, $LVersion2) = @_;
    my $Member_Name = $Type1->{"Memb"}{$MemPos}{"name"};
    my $MemberType_Id = $Type1->{"Memb"}{$MemPos}{"type"};
    my %MemberType_Pure = get_PureType($MemberType_Id, $TypeInfo{$LVersion1});
    if(not defined $Type2->{"Memb"}{$MemPos}) {
        return "";
    }
    my $PairType_Id = $Type2->{"Memb"}{$MemPos}{"type"};
    my %PairType_Pure = get_PureType($PairType_Id, $TypeInfo{$LVersion2});
    
    my $Pair_Name = $Type2->{"Memb"}{$MemPos}{"name"};
    my $MemberPair_Pos_Rev = ($Member_Name eq $Pair_Name)?$MemPos:find_MemberPair_Pos_byName($Pair_Name, $Type1);
    if($MemberPair_Pos_Rev eq "lost")
    {
        if($MemberType_Pure{"Name"} eq $PairType_Pure{"Name"})
        { # base type match
            return $Pair_Name;
        }
        if($TypeInfo{$LVersion1}{$MemberType_Id}{"Name"} eq $TypeInfo{$LVersion2}{$PairType_Id}{"Name"})
        { # exact type match
            return $Pair_Name;
        }
        if($MemberType_Pure{"Size"} eq $PairType_Pure{"Size"})
        { # size match
            return $Pair_Name;
        }
        if(isReserved($Pair_Name))
        { # reserved fields
            return $Pair_Name;
        }
    }
    return "";
}

sub isLastElem($$)
{
    my ($Pos, $TypeRef) = @_;
    my $Name = $TypeRef->{"Memb"}{$Pos}{"name"};
    if($Name=~/last|count|max|total/i)
    { # GST_LEVEL_COUNT, GST_RTSP_ELAST
        return 1;
    }
    elsif($Name=~/END|NLIMITS\Z/)
    { # __RLIMIT_NLIMITS
        return 1;
    }
    elsif($Name=~/\AN[A-Z](.+)[a-z]+s\Z/
    and $Pos+1==keys(%{$TypeRef->{"Memb"}}))
    { # NImageFormats, NColorRoles
        return 1;
    }
    return 0;
}

sub nonComparable($$)
{
    my ($T1, $T2) = @_;
    
    my $N1 = $T1->{"Name"};
    my $N2 = $T2->{"Name"};
    
    $N1=~s/\A(struct|union|enum) //;
    $N2=~s/\A(struct|union|enum) //;
    
    if($N1 ne $N2
    and not isAnon($N1)
    and not isAnon($N2))
    { # different names
        if($T1->{"Type"} ne "Pointer"
        or $T2->{"Type"} ne "Pointer")
        { # compare base types
            return 1;
        }
        if($N1!~/\Avoid\s*\*/
        and $N2=~/\Avoid\s*\*/)
        {
            return 1;
        }
    }
    elsif($T1->{"Type"} ne $T2->{"Type"})
    { # different types
        if($T1->{"Type"} eq "Class"
        and $T2->{"Type"} eq "Struct")
        { # "class" to "struct"
            return 0;
        }
        elsif($T2->{"Type"} eq "Class"
        and $T1->{"Type"} eq "Struct")
        { # "struct" to "class"
            return 0;
        }
        else
        { # "class" to "enum"
          # "union" to "class"
          #  ...
            return 1;
        }
    }
    return 0;
}

sub isOpaque($)
{
    my $T = $_[0];
    if(not defined $T->{"Memb"})
    {
        return 1;
    }
    return 0;
}

sub removeVPtr($)
{ # support for old ABI dumps
    my $TPtr = $_[0];
    my @Pos = sort {int($a)<=>int($b)} keys(%{$TPtr->{"Memb"}});
    if($#Pos>=1)
    {
        foreach my $Pos (0 .. $#Pos-1)
        {
            %{$TPtr->{"Memb"}{$Pos}} = %{$TPtr->{"Memb"}{$Pos+1}};
        }
        delete($TPtr->{"Memb"}{$#Pos});
    }
}

sub isPrivateABI($$)
{
    my ($TypeId, $LibVersion) = @_;
    
    if($CheckPrivateABI) {
        return 0;
    }
    
    if(defined $TypeInfo{$LibVersion}{$TypeId}{"PrivateABI"}) {
        return 1;
    }
    
    return 0;
}

sub mergeTypes($$$)
{
    my ($Type1_Id, $Type2_Id, $Level) = @_;
    return {} if(not $Type1_Id or not $Type2_Id);
    
    if(defined $Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id})
    { # already merged
        return $Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id};
    }
    
    my %Type1 = get_Type($Type1_Id, 1);
    my %Type2 = get_Type($Type2_Id, 2);
    if(not $Type1{"Name"} or not $Type2{"Name"}) {
        return {};
    }
    
    my %Type1_Pure = get_PureType($Type1_Id, $TypeInfo{1});
    my %Type2_Pure = get_PureType($Type2_Id, $TypeInfo{2});
    
    if(defined $UsedDump{1}{"DWARF"})
    {
        if($Type1_Pure{"Name"} eq "__unknown__"
        or $Type2_Pure{"Name"} eq "__unknown__")
        { # Error ABI dump
            return ($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id} = {});
        }
    }
    
    if(isPrivateABI($Type1_Id, 1)) {
        return {};
    }
    
    $CheckedTypes{$Level}{$Type1{"Name"}} = 1;
    $CheckedTypes{$Level}{$Type1_Pure{"Name"}} = 1;
    
    my %SubProblems = ();
    
    if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"})
    {
        if($Type1_Pure{"Type"}=~/Struct|Union/
        and $Type2_Pure{"Type"}=~/Struct|Union/)
        {
            if(isOpaque(\%Type2_Pure) and not isOpaque(\%Type1_Pure))
            {
                if(not defined $UsedDump{1}{"DWARF"}
                and not defined $UsedDump{2}{"DWARF"})
                {
                    %{$SubProblems{"Type_Became_Opaque"}{$Type1_Pure{"Name"}}}=(
                        "Target"=>$Type1_Pure{"Name"},
                        "Type_Name"=>$Type1_Pure{"Name"}  );
                }
                
                return ($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id} = \%SubProblems);
            }
        }
    }
    
    if(not $Type1_Pure{"Size"}
    or not $Type2_Pure{"Size"})
    { # including a case when "class Class { ... };" changed to "class Class;"
        if(not defined $Type1_Pure{"Memb"} or not defined $Type2_Pure{"Memb"}
        or index($Type1_Pure{"Name"}, "<")==-1 or index($Type2_Pure{"Name"}, "<")==-1)
        { # NOTE: template instances have no size
            return {};
        }
    }
    if(isRecurType($Type1_Pure{"Tid"}, $Type2_Pure{"Tid"}, \@RecurTypes))
    { # skip recursive declarations
        return {};
    }
    return {} if(not $Type1_Pure{"Name"} or not $Type2_Pure{"Name"});
    return {} if($SkipTypes{1}{$Type1_Pure{"Name"}});
    return {} if($SkipTypes{1}{$Type1{"Name"}});
    
    if(not isTargetType($Type1_Pure{"Tid"}, 1)) {
        return {};
    }
    
    if($Type1_Pure{"Type"}=~/Class|Struct/ and $Type2_Pure{"Type"}=~/Class|Struct/)
    { # support for old ABI dumps
      # _vptr field added in 3.0
        if(not checkDump(1, "3.0") and checkDump(2, "3.0"))
        {
            if(defined $Type2_Pure{"Memb"}
            and $Type2_Pure{"Memb"}{0}{"name"} eq "_vptr")
            {
                if(keys(%{$Type2_Pure{"Memb"}})==1) {
                    delete($Type2_Pure{"Memb"}{0});
                }
                else {
                    removeVPtr(\%Type2_Pure);
                }
            }
        }
        if(checkDump(1, "3.0") and not checkDump(2, "3.0"))
        {
            if(defined $Type1_Pure{"Memb"}
            and $Type1_Pure{"Memb"}{0}{"name"} eq "_vptr")
            {
                if(keys(%{$Type1_Pure{"Memb"}})==1) {
                    delete($Type1_Pure{"Memb"}{0});
                }
                else {
                    removeVPtr(\%Type1_Pure);
                }
            }
        }
    }
    
    my %Typedef_1 = goToFirst($Type1{"Tid"}, 1, "Typedef");
    my %Typedef_2 = goToFirst($Type2{"Tid"}, 2, "Typedef");
    
    if(%Typedef_1 and %Typedef_2
    and $Typedef_1{"Type"} eq "Typedef" and $Typedef_2{"Type"} eq "Typedef"
    and $Typedef_1{"Name"} eq $Typedef_2{"Name"})
    {
        my %Base_1 = get_OneStep_BaseType($Typedef_1{"Tid"}, $TypeInfo{1});
        my %Base_2 = get_OneStep_BaseType($Typedef_2{"Tid"}, $TypeInfo{2});
        if($Base_1{"Name"} ne $Base_2{"Name"})
        {
            if(differentDumps("G")
            or differentDumps("V"))
            { # different GCC versions or different dumps
                $Base_1{"Name"} = uncover_typedefs($Base_1{"Name"}, 1);
                $Base_2{"Name"} = uncover_typedefs($Base_2{"Name"}, 2);
                # std::__va_list and __va_list
                $Base_1{"Name"}=~s/\A(\w+::)+//;
                $Base_2{"Name"}=~s/\A(\w+::)+//;
                $Base_1{"Name"} = formatName($Base_1{"Name"}, "T");
                $Base_2{"Name"} = formatName($Base_2{"Name"}, "T");
            }
        }
        if($Base_1{"Name"}!~/anon\-/ and $Base_2{"Name"}!~/anon\-/
        and $Base_1{"Name"} ne $Base_2{"Name"})
        {
            if($Level eq "Binary"
            and $Type1{"Size"} and $Type2{"Size"}
            and $Type1{"Size"} ne $Type2{"Size"})
            {
                %{$SubProblems{"DataType_Size"}{$Typedef_1{"Name"}}}=(
                    "Target"=>$Typedef_1{"Name"},
                    "Type_Name"=>$Typedef_1{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE  );
            }
            my %Base1_Pure = get_PureType($Base_1{"Tid"}, $TypeInfo{1});
            my %Base2_Pure = get_PureType($Base_2{"Tid"}, $TypeInfo{2});
            
            if(defined $UsedDump{1}{"DWARF"})
            {
                if($Base1_Pure{"Name"}=~/\b__unknown__\b/
                or $Base2_Pure{"Name"}=~/\b__unknown__\b/)
                { # Error ABI dump
                    return ($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id} = {});
                }
            }
            
            if(tNameLock($Base_1{"Tid"}, $Base_2{"Tid"}))
            {
                if(diffTypes($Base1_Pure{"Tid"}, $Base2_Pure{"Tid"}, $Level))
                {
                    %{$SubProblems{"Typedef_BaseType_Format"}{$Typedef_1{"Name"}}}=(
                        "Target"=>$Typedef_1{"Name"},
                        "Type_Name"=>$Typedef_1{"Name"},
                        "Old_Value"=>$Base_1{"Name"},
                        "New_Value"=>$Base_2{"Name"}  );
                }
                else
                {
                    %{$SubProblems{"Typedef_BaseType"}{$Typedef_1{"Name"}}}=(
                        "Target"=>$Typedef_1{"Name"},
                        "Type_Name"=>$Typedef_1{"Name"},
                        "Old_Value"=>$Base_1{"Name"},
                        "New_Value"=>$Base_2{"Name"}  );
                }
            }
        }
    }
    if(nonComparable(\%Type1_Pure, \%Type2_Pure))
    { # different types (reported in detectTypeChange(...))
        my $TT1 = $Type1_Pure{"Type"};
        my $TT2 = $Type2_Pure{"Type"};
        
        if($TT1 ne $TT2
        and $TT1!~/Intrinsic|Pointer|Ref|Typedef/)
        { # different type of the type
            my $Short1 = $Type1_Pure{"Name"};
            my $Short2 = $Type2_Pure{"Name"};
            
            $Short1=~s/\A\Q$TT1\E //ig;
            $Short2=~s/\A\Q$TT2\E //ig;
            
            if($Short1 eq $Short2)
            {
                %{$SubProblems{"DataType_Type"}{$Type1_Pure{"Name"}}}=(
                    "Target"=>$Type1_Pure{"Name"},
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Old_Value"=>lc($Type1_Pure{"Type"}),
                    "New_Value"=>lc($Type2_Pure{"Type"})  );
            }
        }
        return ($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id} = \%SubProblems);
    }
    
    pushType($Type1_Pure{"Tid"}, $Type2_Pure{"Tid"}, \@RecurTypes);
    
    if(($Type1_Pure{"Name"} eq $Type2_Pure{"Name"}
    or (isAnon($Type1_Pure{"Name"}) and isAnon($Type2_Pure{"Name"})))
    and $Type1_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
    { # checking size
        if($Level eq "Binary"
        and $Type1_Pure{"Size"} and $Type2_Pure{"Size"}
        and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
        {
            my $ProblemKind = "DataType_Size";
            if($Type1_Pure{"Type"} eq "Class"
            and keys(%{$ClassMethods{$Level}{1}{$Type1_Pure{"Name"}}}))
            {
                if(isCopyingClass($Type1_Pure{"Tid"}, 1)) {
                    $ProblemKind = "Size_Of_Copying_Class";
                }
                elsif($AllocableClass{1}{$Type1_Pure{"Name"}})
                {
                    if(int($Type2_Pure{"Size"})>int($Type1_Pure{"Size"})) {
                        $ProblemKind = "Size_Of_Allocable_Class_Increased";
                    }
                    else
                    {
                        # descreased size of allocable class
                        # it has no special effects
                    }
                }
            }
            %{$SubProblems{$ProblemKind}{$Type1_Pure{"Name"}}}=(
                "Target"=>$Type1_Pure{"Name"},
                "Type_Name"=>$Type1_Pure{"Name"},
                "Old_Size"=>$Type1_Pure{"Size"}*$BYTE_SIZE,
                "New_Size"=>$Type2_Pure{"Size"}*$BYTE_SIZE);
        }
    }
    if(defined $Type1_Pure{"BaseType"}
    and defined $Type2_Pure{"BaseType"})
    { # checking base types
        my $Sub_SubProblems = mergeTypes($Type1_Pure{"BaseType"}, $Type2_Pure{"BaseType"}, $Level);
        foreach my $Sub_SubProblemType (keys(%{$Sub_SubProblems}))
        {
            foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems->{$Sub_SubProblemType}})) {
                $SubProblems{$Sub_SubProblemType}{$Sub_SubLocation} = $Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation};
            }
        }
    }
    my (%AddedField, %RemovedField, %RenamedField, %RenamedField_Rev, %RelatedField, %RelatedField_Rev) = ();
    my %NameToPosA = map {$Type1_Pure{"Memb"}{$_}{"name"}=>$_} keys(%{$Type1_Pure{"Memb"}});
    my %NameToPosB = map {$Type2_Pure{"Memb"}{$_}{"name"}=>$_} keys(%{$Type2_Pure{"Memb"}});
    foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type1_Pure{"Memb"}}))
    { # detect removed and renamed fields
        my $Member_Name = $Type1_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        my $MemberPair_Pos = (defined $Type2_Pure{"Memb"}{$Member_Pos} and $Type2_Pure{"Memb"}{$Member_Pos}{"name"} eq $Member_Name)?$Member_Pos:find_MemberPair_Pos_byName($Member_Name, \%Type2_Pure);
        if($MemberPair_Pos eq "lost")
        {
            if($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
                if(isUnnamed($Member_Name))
                { # support for old-version dumps
                  # unnamed fields have been introduced in the ACC 1.23 (dump 2.1 format)
                    if(not checkDump(2, "2.1")) {
                        next;
                    }
                }
                if(my $RenamedTo = isRenamed($Member_Pos, \%Type1_Pure, 1, \%Type2_Pure, 2))
                { # renamed
                    $RenamedField{$Member_Pos} = $RenamedTo;
                    $RenamedField_Rev{$NameToPosB{$RenamedTo}} = $Member_Name;
                }
                else
                { # removed
                    $RemovedField{$Member_Pos} = 1;
                }
            }
            elsif($Type1_Pure{"Type"} eq "Enum")
            {
                my $Member_Value1 = $Type1_Pure{"Memb"}{$Member_Pos}{"value"};
                next if($Member_Value1 eq "");
                $MemberPair_Pos = find_MemberPair_Pos_byVal($Member_Value1, \%Type2_Pure);
                if($MemberPair_Pos ne "lost")
                { # renamed
                    my $RenamedTo = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"name"};
                    my $MemberPair_Pos_Rev = find_MemberPair_Pos_byName($RenamedTo, \%Type1_Pure);
                    if($MemberPair_Pos_Rev eq "lost")
                    {
                        $RenamedField{$Member_Pos} = $RenamedTo;
                        $RenamedField_Rev{$NameToPosB{$RenamedTo}} = $Member_Name;
                    }
                    else {
                        $RemovedField{$Member_Pos} = 1;
                    }
                }
                else
                { # removed
                    $RemovedField{$Member_Pos} = 1;
                }
            }
        }
        else
        { # related
            $RelatedField{$Member_Pos} = $MemberPair_Pos;
            $RelatedField_Rev{$MemberPair_Pos} = $Member_Pos;
        }
    }
    foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type2_Pure{"Memb"}}))
    { # detect added fields
        my $Member_Name = $Type2_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        my $MemberPair_Pos = (defined $Type1_Pure{"Memb"}{$Member_Pos} and $Type1_Pure{"Memb"}{$Member_Pos}{"name"} eq $Member_Name)?$Member_Pos:find_MemberPair_Pos_byName($Member_Name, \%Type1_Pure);
        if($MemberPair_Pos eq "lost")
        {
            if(isUnnamed($Member_Name))
            { # support for old-version dumps
            # unnamed fields have been introduced in the ACC 1.23 (dump 2.1 format)
                if(not checkDump(1, "2.1")) {
                    next;
                }
            }
            if($Type2_Pure{"Type"}=~/\A(Struct|Class|Union|Enum)\Z/)
            {
                if(not $RenamedField_Rev{$Member_Pos})
                { # added
                    $AddedField{$Member_Pos}=1;
                }
            }
        }
    }
    if($Type2_Pure{"Type"}=~/\A(Struct|Class)\Z/)
    { # detect moved fields
        my (%RelPos, %RelPosName, %AbsPos) = ();
        my $Pos = 0;
        foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type1_Pure{"Memb"}}))
        { # relative positions in 1st version
            my $Member_Name = $Type1_Pure{"Memb"}{$Member_Pos}{"name"};
            next if(not $Member_Name);
            if(not $RemovedField{$Member_Pos})
            { # old type without removed fields
                $RelPos{1}{$Member_Name} = $Pos;
                $RelPosName{1}{$Pos} = $Member_Name;
                $AbsPos{1}{$Pos++} = $Member_Pos;
            }
        }
        $Pos = 0;
        foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type2_Pure{"Memb"}}))
        { # relative positions in 2nd version
            my $Member_Name = $Type2_Pure{"Memb"}{$Member_Pos}{"name"};
            next if(not $Member_Name);
            if(not $AddedField{$Member_Pos})
            { # new type without added fields
                $RelPos{2}{$Member_Name} = $Pos;
                $RelPosName{2}{$Pos} = $Member_Name;
                $AbsPos{2}{$Pos++} = $Member_Pos;
            }
        }
        foreach my $Member_Name (keys(%{$RelPos{1}}))
        {
            my $RPos1 = $RelPos{1}{$Member_Name};
            my $AbsPos1 = $NameToPosA{$Member_Name};
            my $Member_Name2 = $Member_Name;
            if(my $RenamedTo = $RenamedField{$AbsPos1})
            { # renamed
                $Member_Name2 = $RenamedTo;
            }
            my $RPos2 = $RelPos{2}{$Member_Name2};
            if($RPos2 ne "" and $RPos1 ne $RPos2)
            { # different relative positions
                my $AbsPos2 = $NameToPosB{$Member_Name2};
                if($AbsPos1 ne $AbsPos2)
                { # different absolute positions
                    my $ProblemType = "Moved_Field";
                    if(not isPublic(\%Type1_Pure, $AbsPos1))
                    { # may change layout and size of type
                        if($Level eq "Source") {
                            next;
                        }
                        $ProblemType = "Moved_Private_Field";
                    }
                    if($Level eq "Binary"
                    and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                    { # affected size
                        my $MemSize1 = $TypeInfo{1}{$Type1_Pure{"Memb"}{$AbsPos1}{"type"}}{"Size"};
                        my $MovedAbsPos = $AbsPos{1}{$RPos2};
                        my $MemSize2 = $TypeInfo{1}{$Type1_Pure{"Memb"}{$MovedAbsPos}{"type"}}{"Size"};
                        if($MemSize1 ne $MemSize2) {
                            $ProblemType .= "_And_Size";
                        }
                    }
                    if($ProblemType eq "Moved_Private_Field") {
                        next;
                    }
                    %{$SubProblems{$ProblemType}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Old_Value"=>$RPos1,
                        "New_Value"=>$RPos2 );
                }
            }
        }
    }
    foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type1_Pure{"Memb"}}))
    { # check older fields, public and private
        my $Member_Name = $Type1_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        next if($Member_Name eq "_vptr");
        if(my $RenamedTo = $RenamedField{$Member_Pos})
        { # renamed
            if(defined $Constants{2}{$Member_Name})
            {
                if($Constants{2}{$Member_Name}{"Value"} eq $RenamedTo)
                { # define OLD NEW
                    next; # Safe
                }
            }
            
            if($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
                if(isPublic(\%Type1_Pure, $Member_Pos))
                {
                    %{$SubProblems{"Renamed_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Old_Value"=>$Member_Name,
                        "New_Value"=>$RenamedTo  );
                }
                elsif(isReserved($Member_Name))
                {
                    %{$SubProblems{"Used_Reserved_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Old_Value"=>$Member_Name,
                        "New_Value"=>$RenamedTo  );
                }
            }
            elsif($Type1_Pure{"Type"} eq "Enum")
            {
                %{$SubProblems{"Enum_Member_Name"}{$Type1_Pure{"Memb"}{$Member_Pos}{"value"}}}=(
                    "Target"=>$Type1_Pure{"Memb"}{$Member_Pos}{"value"},
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Old_Value"=>$Member_Name,
                    "New_Value"=>$RenamedTo  );
            }
        }
        elsif($RemovedField{$Member_Pos})
        { # removed
            if($Type2_Pure{"Type"}=~/\A(Struct|Class)\Z/)
            {
                my $ProblemType = "Removed_Field";
                if(not isPublic(\%Type1_Pure, $Member_Pos)
                or isUnnamed($Member_Name))
                {
                    if($Level eq "Source") {
                        next;
                    }
                    $ProblemType = "Removed_Private_Field";
                }
                if($Level eq "Binary"
                and not isMemPadded($Member_Pos, -1, \%Type1_Pure, \%RemovedField, $TypeInfo{1}, getArch(1), $WORD_SIZE{1}))
                {
                    if(my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                    { # affected fields
                        if(getOffset($MNum-1, \%Type1_Pure, $TypeInfo{1}, getArch(1), $WORD_SIZE{1})!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, $TypeInfo{2}, getArch(2), $WORD_SIZE{2}))
                        { # changed offset
                            $ProblemType .= "_And_Layout";
                        }
                    }
                    if($Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                    { # affected size
                        $ProblemType .= "_And_Size";
                    }
                }
                if($ProblemType eq "Removed_Private_Field") {
                    next;
                }
                %{$SubProblems{$ProblemType}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type1_Pure{"Name"}  );
            }
            elsif($Type2_Pure{"Type"} eq "Union")
            {
                if($Level eq "Binary"
                and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                {
                    %{$SubProblems{"Removed_Union_Field_And_Size"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"}  );
                }
                else
                {
                    %{$SubProblems{"Removed_Union_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"}  );
                }
            }
            elsif($Type1_Pure{"Type"} eq "Enum")
            {
                %{$SubProblems{"Enum_Member_Removed"}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Old_Value"=>$Member_Name  );
            }
        }
        else
        { # changed
            my $MemberPair_Pos = $RelatedField{$Member_Pos};
            if($Type1_Pure{"Type"} eq "Enum")
            {
                my $Member_Value1 = $Type1_Pure{"Memb"}{$Member_Pos}{"value"};
                next if($Member_Value1 eq "");
                my $Member_Value2 = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"value"};
                next if($Member_Value2 eq "");
                if($Member_Value1 ne $Member_Value2)
                {
                    my $ProblemType = "Enum_Member_Value";
                    if(isLastElem($Member_Pos, \%Type1_Pure)) {
                        $ProblemType = "Enum_Last_Member_Value";
                    }
                    if($SkipConstants{1}{$Member_Name}) {
                        $ProblemType = "Enum_Private_Member_Value";
                    }
                    %{$SubProblems{$ProblemType}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Old_Value"=>$Member_Value1,
                        "New_Value"=>$Member_Value2  );
                }
            }
            elsif($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
                my $Access1 = $Type1_Pure{"Memb"}{$Member_Pos}{"access"};
                my $Access2 = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"access"};
                
                if($Access1 ne "private"
                and $Access2 eq "private")
                {
                    %{$SubProblems{"Field_Became_Private"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"});
                }
                elsif($Access1 ne "protected"
                and $Access1 ne "private"
                and $Access2 eq "protected")
                {
                    %{$SubProblems{"Field_Became_Protected"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"});
                }
                
                my $MemberType1_Id = $Type1_Pure{"Memb"}{$Member_Pos}{"type"};
                my $MemberType2_Id = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"type"};
                my $SizeV1 = $TypeInfo{1}{$MemberType1_Id}{"Size"}*$BYTE_SIZE;
                if(my $BSize1 = $Type1_Pure{"Memb"}{$Member_Pos}{"bitfield"}) {
                    $SizeV1 = $BSize1;
                }
                my $SizeV2 = $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE_SIZE;
                if(my $BSize2 = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"bitfield"}) {
                    $SizeV2 = $BSize2;
                }
                my $MemberType1_Name = $TypeInfo{1}{$MemberType1_Id}{"Name"};
                my $MemberType2_Name = $TypeInfo{2}{$MemberType2_Id}{"Name"};
                if($Level eq "Binary"
                and $SizeV1 and $SizeV2
                and $SizeV1 ne $SizeV2)
                {
                    if($MemberType1_Name eq $MemberType2_Name or (isAnon($MemberType1_Name) and isAnon($MemberType2_Name))
                    or ($Type1_Pure{"Memb"}{$Member_Pos}{"bitfield"} and $Type2_Pure{"Memb"}{$MemberPair_Pos}{"bitfield"}))
                    { # field size change (including anon-structures and unions)
                      # - same types
                      # - unnamed types
                      # - bitfields
                        my $ProblemType = "Field_Size";
                        if(not isPublic(\%Type1_Pure, $Member_Pos)
                        or isUnnamed($Member_Name))
                        { # should not be accessed by applications, goes to "Low Severity"
                          # example: "abidata" members in GStreamer types
                            $ProblemType = "Private_".$ProblemType;
                        }
                        if(not isMemPadded($Member_Pos, $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE_SIZE, \%Type1_Pure, \%RemovedField, $TypeInfo{1}, getArch(1), $WORD_SIZE{1}))
                        { # check an effect
                            if($Type2_Pure{"Type"} ne "Union"
                            and my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                            { # public fields after the current
                                if(getOffset($MNum-1, \%Type1_Pure, $TypeInfo{1}, getArch(1), $WORD_SIZE{1})!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, $TypeInfo{2}, getArch(2), $WORD_SIZE{2}))
                                { # changed offset
                                    $ProblemType .= "_And_Layout";
                                }
                            }
                            if($Type1_Pure{"Size"} ne $Type2_Pure{"Size"}) {
                                $ProblemType .= "_And_Type_Size";
                            }
                        }
                        if($ProblemType eq "Private_Field_Size")
                        { # private field size with no effect
                        }
                        if($ProblemType eq "Field_Size")
                        {
                            if($Type1_Pure{"Type"}=~/Union|Struct/ and $SizeV1<$SizeV2)
                            { # Low severity
                                $ProblemType = "Struct_Field_Size_Increased";
                            }
                        }
                        if($ProblemType)
                        { # register a problem
                            %{$SubProblems{$ProblemType}{$Member_Name}}=(
                                "Target"=>$Member_Name,
                                "Type_Name"=>$Type1_Pure{"Name"},
                                "Old_Size"=>$SizeV1,
                                "New_Size"=>$SizeV2);
                        }
                    }
                }
                if($Type1_Pure{"Memb"}{$Member_Pos}{"bitfield"}
                or $Type2_Pure{"Memb"}{$MemberPair_Pos}{"bitfield"})
                { # do NOT check bitfield type changes
                    next;
                }
                if(checkDump(1, "2.13") and checkDump(2, "2.13"))
                {
                    if(not $Type1_Pure{"Memb"}{$Member_Pos}{"mutable"}
                    and $Type2_Pure{"Memb"}{$MemberPair_Pos}{"mutable"})
                    {
                        %{$SubProblems{"Field_Became_Mutable"}{$Member_Name}}=(
                            "Target"=>$Member_Name,
                            "Type_Name"=>$Type1_Pure{"Name"});
                    }
                    elsif($Type1_Pure{"Memb"}{$Member_Pos}{"mutable"}
                    and not $Type2_Pure{"Memb"}{$MemberPair_Pos}{"mutable"})
                    {
                        %{$SubProblems{"Field_Became_Non_Mutable"}{$Member_Name}}=(
                            "Target"=>$Member_Name,
                            "Type_Name"=>$Type1_Pure{"Name"});
                    }
                }
                my %Sub_SubChanges = detectTypeChange($MemberType1_Id, $MemberType2_Id, "Field", $Level);
                foreach my $ProblemType (keys(%Sub_SubChanges))
                {
                    my $Old_Value = $Sub_SubChanges{$ProblemType}{"Old_Value"};
                    my $New_Value = $Sub_SubChanges{$ProblemType}{"New_Value"};
                    
                    # quals
                    if($ProblemType eq "Field_Type"
                    or $ProblemType eq "Field_Type_And_Size"
                    or $ProblemType eq "Field_Type_Format")
                    {
                        if(checkDump(1, "2.6") and checkDump(2, "2.6"))
                        {
                            if(addedQual($Old_Value, $New_Value, "volatile")) {
                                %{$Sub_SubChanges{"Field_Became_Volatile"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                            elsif(removedQual($Old_Value, $New_Value, "volatile")) {
                                %{$Sub_SubChanges{"Field_Became_Non_Volatile"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                        }
                        if(my $RA = addedQual($Old_Value, $New_Value, "const"))
                        {
                            if($RA==2) {
                                %{$Sub_SubChanges{"Field_Added_Const"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                            else {
                                %{$Sub_SubChanges{"Field_Became_Const"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                        }
                        elsif(my $RR = removedQual($Old_Value, $New_Value, "const"))
                        {
                            if($RR==2) {
                                %{$Sub_SubChanges{"Field_Removed_Const"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                            else {
                                %{$Sub_SubChanges{"Field_Became_Non_Const"}} = %{$Sub_SubChanges{$ProblemType}};
                            }
                        }
                    }
                }
                
                if($Level eq "Source")
                {
                    foreach my $ProblemType (keys(%Sub_SubChanges))
                    {
                        my $Old_Value = $Sub_SubChanges{$ProblemType}{"Old_Value"};
                        my $New_Value = $Sub_SubChanges{$ProblemType}{"New_Value"};
                        
                        if($ProblemType eq "Field_Type")
                        {
                            if(cmpBTypes($Old_Value, $New_Value, 1, 2)) {
                                delete($Sub_SubChanges{$ProblemType});
                            }
                        }
                    }
                }
                
                foreach my $ProblemType (keys(%Sub_SubChanges))
                {
                    my $ProblemType_Init = $ProblemType;
                    if($ProblemType eq "Field_Type_And_Size")
                    { # Binary
                        if(not isPublic(\%Type1_Pure, $Member_Pos)
                        or isUnnamed($Member_Name)) {
                            $ProblemType = "Private_".$ProblemType;
                        }
                        if(not isMemPadded($Member_Pos, $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE_SIZE, \%Type1_Pure, \%RemovedField, $TypeInfo{1}, getArch(1), $WORD_SIZE{1}))
                        { # check an effect
                            if($Type2_Pure{"Type"} ne "Union"
                            and my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                            { # public fields after the current
                                if(getOffset($MNum-1, \%Type1_Pure, $TypeInfo{1}, getArch(1), $WORD_SIZE{1})!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, $TypeInfo{2}, getArch(2), $WORD_SIZE{2}))
                                { # changed offset
                                    $ProblemType .= "_And_Layout";
                                }
                            }
                            if($Type1_Pure{"Size"} ne $Type2_Pure{"Size"}) {
                                $ProblemType .= "_And_Type_Size";
                            }
                        }
                    }
                    else
                    {
                        # TODO: Private_Field_Type rule?
                        
                        if(not isPublic(\%Type1_Pure, $Member_Pos)
                        or isUnnamed($Member_Name)) {
                            next;
                        }
                    }
                    if($ProblemType eq "Private_Field_Type_And_Size")
                    { # private field change with no effect
                    }
                    %{$SubProblems{$ProblemType}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"});
                    
                    foreach my $Attr (keys(%{$Sub_SubChanges{$ProblemType_Init}}))
                    { # other properties
                        $SubProblems{$ProblemType}{$Member_Name}{$Attr} = $Sub_SubChanges{$ProblemType_Init}{$Attr};
                    }
                }
                if(not isPublic(\%Type1_Pure, $Member_Pos))
                { # do NOT check internal type changes
                    next;
                }
                if($MemberType1_Id and $MemberType2_Id)
                { # checking member type changes
                    my $Sub_SubProblems = mergeTypes($MemberType1_Id, $MemberType2_Id, $Level);
                    
                    my %DupProblems = ();
                    
                    foreach my $Sub_SubProblemType (sort keys(%{$Sub_SubProblems}))
                    {
                        foreach my $Sub_SubLocation (sort {length($a)<=>length($b)} sort keys(%{$Sub_SubProblems->{$Sub_SubProblemType}}))
                        {
                            if(not defined $AllAffected)
                            {
                                if(defined $DupProblems{$Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation}}) {
                                    next;
                                }
                            }
                            
                            my $NewLocation = ($Sub_SubLocation)?$Member_Name."->".$Sub_SubLocation:$Member_Name;
                            $SubProblems{$Sub_SubProblemType}{$NewLocation} = $Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation};
                            
                            if(not defined $AllAffected)
                            {
                                $DupProblems{$Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation}} = 1;
                            }
                        }
                    }
                    
                    %DupProblems = ();
                }
            }
        }
    }
    foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type2_Pure{"Memb"}}))
    { # checking added members, public and private
        my $Member_Name = $Type2_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        next if($Member_Name eq "_vptr");
        if($AddedField{$Member_Pos})
        { # added
            if($Type2_Pure{"Type"}=~/\A(Struct|Class)\Z/)
            {
                my $ProblemType = "Added_Field";
                if(not isPublic(\%Type2_Pure, $Member_Pos)
                or isUnnamed($Member_Name))
                {
                    if($Level eq "Source") {
                        next;
                    }
                    $ProblemType = "Added_Private_Field";
                }
                if($Level eq "Binary"
                and not isMemPadded($Member_Pos, -1, \%Type2_Pure, \%AddedField, $TypeInfo{2}, getArch(2), $WORD_SIZE{2}))
                {
                    if(my $MNum = isAccessible(\%Type2_Pure, \%AddedField, $Member_Pos, -1))
                    { # public fields after the current
                        if(getOffset($MNum-1, \%Type2_Pure, $TypeInfo{2}, getArch(2), $WORD_SIZE{2})!=getOffset($RelatedField_Rev{$MNum-1}, \%Type1_Pure, $TypeInfo{1}, getArch(1), $WORD_SIZE{1}))
                        { # changed offset
                            $ProblemType .= "_And_Layout";
                        }
                    }
                    if($Type1_Pure{"Size"} ne $Type2_Pure{"Size"}) {
                        $ProblemType .= "_And_Size";
                    }
                }
                if($ProblemType eq "Added_Private_Field")
                { # skip added private fields
                    next;
                }
                %{$SubProblems{$ProblemType}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type1_Pure{"Name"});
            }
            elsif($Type2_Pure{"Type"} eq "Union")
            {
                if($Level eq "Binary"
                and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                {
                    %{$SubProblems{"Added_Union_Field_And_Size"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"});
                }
                else
                {
                    %{$SubProblems{"Added_Union_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"});
                }
            }
            elsif($Type2_Pure{"Type"} eq "Enum")
            {
                my $Member_Value = $Type2_Pure{"Memb"}{$Member_Pos}{"value"};
                next if($Member_Value eq "");
                %{$SubProblems{"Added_Enum_Member"}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type2_Pure{"Name"},
                    "New_Value"=>$Member_Value);
            }
        }
    }
    
    if($Type1_Pure{"Type"} eq "FuncPtr")
    {
        foreach my $PPos (sort {int($a) <=> int($b)} keys(%{$Type1_Pure{"Param"}}))
        {
            if(not defined $Type2_Pure{"Param"}{$PPos}) {
                next;
            }
            
            my $PT1 = $Type1_Pure{"Param"}{$PPos}{"type"};
            my $PT2 = $Type2_Pure{"Param"}{$PPos}{"type"};
            
            my $PName = "p".$PPos;
            
            my $FP_SubProblems = mergeTypes($PT1, $PT2, $Level);
            my %DupProblems = ();
            
            foreach my $FP_SubProblemType (keys(%{$FP_SubProblems}))
            {
                foreach my $FP_SubLocation (keys(%{$FP_SubProblems->{$FP_SubProblemType}}))
                {
                    if(not defined $AllAffected)
                    {
                        if(defined $DupProblems{$FP_SubProblems->{$FP_SubProblemType}{$FP_SubLocation}}) {
                            next;
                        }
                    }
                    
                    my $NewLocation = ($FP_SubLocation)?$PName."->".$FP_SubLocation:$PName;
                    $SubProblems{$FP_SubProblemType}{$NewLocation} = $FP_SubProblems->{$FP_SubProblemType}{$FP_SubLocation};
                    
                    if(not defined $AllAffected)
                    {
                        $DupProblems{$FP_SubProblems->{$FP_SubProblemType}{$FP_SubLocation}} = 1;
                    }
                }
            }
            
            %DupProblems = ();
        }
    }
    
    pop(@RecurTypes);
    return ($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id} = \%SubProblems);
}

sub isUnnamed($) {
    return $_[0]=~/\Aunnamed\d+\Z/;
}

sub get_ShortClass($$)
{
    my ($TypeId, $LibVersion) = @_;
    my $TypeName = $TypeInfo{$LibVersion}{$TypeId}{"Name"};
    if($TypeInfo{$LibVersion}{$TypeId}{"Type"}!~/Intrinsic|Class|Struct|Union|Enum/) {
        $TypeName = uncover_typedefs($TypeName, $LibVersion);
    }
    if(my $NameSpace = $TypeInfo{$LibVersion}{$TypeId}{"NameSpace"}) {
        $TypeName=~s/\A(struct |)\Q$NameSpace\E\:\://g;
    }
    return $TypeName;
}

sub goToFirst($$$)
{
    my ($TypeId, $LibVersion, $Type_Type) = @_;
    return () if(not $TypeId);
    if(defined $Cache{"goToFirst"}{$TypeId}{$LibVersion}{$Type_Type}) {
        return %{$Cache{"goToFirst"}{$TypeId}{$LibVersion}{$Type_Type}};
    }
    return () if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return () if(not $Type{"Type"});
    if($Type{"Type"} ne $Type_Type)
    {
        return () if(not $Type{"BaseType"});
        %Type = goToFirst($Type{"BaseType"}, $LibVersion, $Type_Type);
    }
    $Cache{"goToFirst"}{$TypeId}{$LibVersion}{$Type_Type} = \%Type;
    return %Type;
}

my %TypeSpecAttributes = (
    "Const" => 1,
    "Volatile" => 1,
    "ConstVolatile" => 1,
    "Restrict" => 1,
    "Typedef" => 1
);

sub get_PureType($$)
{
    my ($TypeId, $Info) = @_;
    if(not $TypeId or not $Info
    or not $Info->{$TypeId}) {
        return ();
    }
    if(defined $Cache{"get_PureType"}{$TypeId}{$Info}) {
        return %{$Cache{"get_PureType"}{$TypeId}{$Info}};
    }
    my %Type = %{$Info->{$TypeId}};
    return %Type if(not $Type{"BaseType"});
    if($TypeSpecAttributes{$Type{"Type"}}) {
        %Type = get_PureType($Type{"BaseType"}, $Info);
    }
    $Cache{"get_PureType"}{$TypeId}{$Info} = \%Type;
    return %Type;
}

sub get_PLevel($$)
{
    my ($TypeId, $LibVersion) = @_;
    return 0 if(not $TypeId);
    if(defined $Cache{"get_PLevel"}{$TypeId}{$LibVersion}) {
        return $Cache{"get_PLevel"}{$TypeId}{$LibVersion};
    }
    return 0 if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return 1 if($Type{"Type"}=~/FuncPtr|FieldPtr/);
    my $PLevel = 0;
    if($Type{"Type"} =~/Pointer|Ref|FuncPtr|FieldPtr/) {
        $PLevel += 1;
    }
    return $PLevel if(not $Type{"BaseType"});
    $PLevel += get_PLevel($Type{"BaseType"}, $LibVersion);
    $Cache{"get_PLevel"}{$TypeId}{$LibVersion} = $PLevel;
    return $PLevel;
}

sub get_BaseType($$)
{
    my ($TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    if(defined $Cache{"get_BaseType"}{$TypeId}{$LibVersion}) {
        return %{$Cache{"get_BaseType"}{$TypeId}{$LibVersion}};
    }
    return () if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return %Type if(not $Type{"BaseType"});
    %Type = get_BaseType($Type{"BaseType"}, $LibVersion);
    $Cache{"get_BaseType"}{$TypeId}{$LibVersion} = \%Type;
    return %Type;
}

sub get_BaseTypeQual($$)
{
    my ($TypeId, $LibVersion) = @_;
    return "" if(not $TypeId);
    return "" if(not $TypeInfo{$LibVersion}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeId}};
    return "" if(not $Type{"BaseType"});
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
    my $BQual = get_BaseTypeQual($Type{"BaseType"}, $LibVersion);
    return $BQual.$Qual;
}

sub get_OneStep_BaseType($$)
{
    my ($TypeId, $Info) = @_;
    if(not $TypeId or not $Info
    or not $Info->{$TypeId}) {
        return ();
    }
    my %Type = %{$Info->{$TypeId}};
    return %Type if(not $Type{"BaseType"});
    if(my $BTid = $Type{"BaseType"})
    {
        if($Info->{$BTid}) {
            return %{$Info->{$BTid}};
        }
        else { # something is going wrong
            return ();
        }
    }
    else {
        return %Type;
    }
}

sub get_Type($$)
{
    my ($TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    return () if(not $TypeInfo{$LibVersion}{$TypeId});
    return %{$TypeInfo{$LibVersion}{$TypeId}};
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
    my ($SInfo, $LibVersion) = @_;
    
    if(my $ClassId = $SInfo->{"Class"})
    {
        if(my $ClassName = $TypeInfo{$LibVersion}{$ClassId}{"Name"})
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
    my ($SInfo, $LibVersion) = @_;
    if(my $ClassId = $SInfo->{"Class"})
    {
        if($TypeInfo{$LibVersion}{$ClassId}{"Spec"})
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

sub symbolFilter($$$$)
{ # some special cases when the symbol cannot be imported
    my ($Symbol, $LibVersion, $Type, $Level) = @_;
    
    if(isPrivateData($Symbol))
    { # non-public global data
        return 0;
    }
    
    if(defined $SkipInternalSymbols)
    {
        return 0 if($Symbol=~/($SkipInternalSymbols)/);
    }
    
    if($Symbol=~/\A_Z/)
    {
        if($Symbol=~/[CD][3-4]E/) {
            return 0;
        }
    }
    
    if($CheckHeadersOnly and not checkDump($LibVersion, "2.7"))
    { # support for old ABI dumps in --headers-only mode
        foreach my $Pos (keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
        {
            if(my $Pid = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$Pos}{"type"})
            {
                my $PType = $TypeInfo{$LibVersion}{$Pid}{"Type"};
                if(not $PType or $PType eq "Unknown") {
                    return 0;
                }
            }
        }
    }
    if($Type=~/Affected/)
    {
        my $Header = $CompleteSignature{$LibVersion}{$Symbol}{"Header"};
        
        if($SkipSymbols{$LibVersion}{$Symbol})
        { # user defined symbols to ignore
            return 0;
        }
        
        if($SymbolsListPath and not $SymbolsList{$Symbol})
        { # user defined symbols
            if(not $TargetHeadersPath or not $Header
            or not is_target_header($Header, 1))
            { # -symbols-list | -headers-list
                return 0;
            }
        }
        
        if($AppPath and not $SymbolsList_App{$Symbol})
        { # user defined symbols (in application)
            return 0;
        }
        
        my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"};
        
        if($ClassId)
        {
            if(not isTargetType($ClassId, $LibVersion)) {
                return 0;
            }
        }
        
        my $NameSpace = $CompleteSignature{$LibVersion}{$Symbol}{"NameSpace"};
        if(not $NameSpace and $ClassId)
        { # class methods have no "NameSpace" attribute
            $NameSpace = $TypeInfo{$LibVersion}{$ClassId}{"NameSpace"};
        }
        if($NameSpace)
        { # user defined namespaces to ignore
            if($SkipNameSpaces{$LibVersion}{$NameSpace}) {
                return 0;
            }
            foreach my $NS (keys(%{$SkipNameSpaces{$LibVersion}}))
            { # nested namespaces
                if($NameSpace=~/\A\Q$NS\E(\:\:|\Z)/) { 
                    return 0;
                }
            }
        }
        if($Header)
        {
            if(my $Skip = skipHeader($Header, $LibVersion))
            { # --skip-headers or <skip_headers> (not <skip_including>)
                if($Skip==1) {
                    return 0;
                }
            }
        }
        if($TypesListPath and $ClassId)
        { # user defined types
            my $CName = $TypeInfo{$LibVersion}{$ClassId}{"Name"};
            
            if(not $TypesList{$CName})
            {
                if(my $NS = $TypeInfo{$LibVersion}{$ClassId}{"NameSpace"})
                {
                    $CName=~s/\A\Q$NS\E\:\://g;
                }
                
                if(not $TypesList{$CName})
                {
                    my $Found = 0;
                    
                    while($CName=~s/\:\:.+?\Z//)
                    {
                        if($TypesList{$CName})
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
        
        if(not selectSymbol($Symbol, $CompleteSignature{$LibVersion}{$Symbol}, $Level, $LibVersion))
        { # non-target symbols
            return 0;
        }
        if($Level eq "Binary")
        {
            if($CompleteSignature{$LibVersion}{$Symbol}{"InLine"}
            or isInLineInst($CompleteSignature{$LibVersion}{$Symbol}, $LibVersion))
            {
                if($ClassId and $CompleteSignature{$LibVersion}{$Symbol}{"Virt"})
                { # inline virtual methods
                    if($Type=~/InlineVirt/) {
                        return 1;
                    }
                    my $Allocable = (not isCopyingClass($ClassId, $LibVersion));
                    if(not $Allocable)
                    { # check bases
                        foreach my $DCId (get_sub_classes($ClassId, $LibVersion, 1))
                        {
                            if(not isCopyingClass($DCId, $LibVersion))
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

sub detectAdded($)
{
    my $Level = $_[0];
    foreach my $Symbol (keys(%{$Symbol_Library{2}}))
    {
        if(link_symbol($Symbol, 1, "+Deps"))
        { # linker can find a new symbol
          # in the old-version library
          # So, it's not a new symbol
            next;
        }
        if(my $VSym = $SymVer{2}{$Symbol}
        and index($Symbol,"\@")==-1) {
            next;
        }
        $AddedInt{$Level}{$Symbol} = 1;
    }
}

sub detectRemoved($)
{
    my $Level = $_[0];
    foreach my $Symbol (keys(%{$Symbol_Library{1}}))
    {
        if(link_symbol($Symbol, 2, "+Deps"))
        { # linker can find an old symbol
          # in the new-version library
            next;
        }
        if(my $VSym = $SymVer{1}{$Symbol}
        and index($Symbol,"\@")==-1) {
            next;
        }
        $RemovedInt{$Level}{$Symbol} = 1;
    }
}

sub mergeLibs($)
{
    my $Level = $_[0];
    foreach my $Symbol (sort keys(%{$AddedInt{$Level}}))
    { # checking added symbols
        next if($CompleteSignature{2}{$Symbol}{"Private"});
        next if(not $CompleteSignature{2}{$Symbol}{"Header"});
        next if(not symbolFilter($Symbol, 2, "Affected + InlineVirt", $Level));
        %{$CompatProblems{$Level}{$Symbol}{"Added_Symbol"}{""}}=();
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # checking removed symbols
        next if($CompleteSignature{1}{$Symbol}{"Private"});
        next if(not $CompleteSignature{1}{$Symbol}{"Header"});
        if(index($Symbol, "_ZTV")==0)
        { # skip v-tables for templates, that should not be imported by applications
            next if($tr_name{$Symbol}=~/</);
            if(my $CName = $VTableClass{$Symbol})
            {
                if(not keys(%{$ClassMethods{$Level}{1}{$CName}}))
                { # vtables for "private" classes
                  # use case: vtable for QDragManager (Qt 4.5.3 to 4.6.0) became HIDDEN symbol
                    next;
                }
            }
            
            if($SkipSymbols{1}{$Symbol})
            { # user defined symbols to ignore
                next;
            }
        }
        else {
            next if(not symbolFilter($Symbol, 1, "Affected + InlineVirt", $Level));
        }
        if($CompleteSignature{1}{$Symbol}{"PureVirt"})
        { # symbols for pure virtual methods cannot be called by clients
            next;
        }
        %{$CompatProblems{$Level}{$Symbol}{"Removed_Symbol"}{""}}=();
    }
}

sub checkDump($$)
{
    my ($LibVersion, $V) = @_;
    if(defined $Cache{"checkDump"}{$LibVersion}{$V}) {
        return $Cache{"checkDump"}{$LibVersion}{$V};
    }
    return ($Cache{"checkDump"}{$LibVersion}{$V} = (not $UsedDump{$LibVersion}{"V"} or cmpVersions($UsedDump{$LibVersion}{"V"}, $V)>=0));
}

sub detectAdded_H($)
{
    my $Level = $_[0];
    foreach my $Symbol (sort keys(%{$CompleteSignature{2}}))
    {
        if($Level eq "Source")
        { # remove symbol version
            my ($SN, $SS, $SV) = separate_symbol($Symbol);
            $Symbol=$SN;
            
            if($CompleteSignature{2}{$Symbol}{"Artificial"})
            { # skip artificial constructors
                next;
            }
        }
        if(not $CompleteSignature{2}{$Symbol}{"Header"}
        or not $CompleteSignature{2}{$Symbol}{"MnglName"}) {
            next;
        }
        if($ExtendedSymbols{$Symbol}) {
            next;
        }
        if(not defined $CompleteSignature{1}{$Symbol}
        or not $CompleteSignature{1}{$Symbol}{"MnglName"})
        {
            if($UsedDump{2}{"SrcBin"})
            {
                if($UsedDump{1}{"BinOnly"} or not checkDump(1, "2.11"))
                { # support for old and different (!) ABI dumps
                    if(not $CompleteSignature{2}{$Symbol}{"Virt"}
                    and not $CompleteSignature{2}{$Symbol}{"PureVirt"})
                    {
                        if($CheckHeadersOnly)
                        {
                            if(my $Lang = $CompleteSignature{2}{$Symbol}{"Lang"})
                            {
                                if($Lang eq "C")
                                { # support for old ABI dumps: missed extern "C" functions
                                    next;
                                }
                            }
                        }
                        else
                        {
                            if(not link_symbol($Symbol, 2, "-Deps"))
                            { # skip added inline symbols and const global data
                                next;
                            }
                        }
                    }
                }
            }
            $AddedInt{$Level}{$Symbol} = 1;
        }
    }
}

sub detectRemoved_H($)
{
    my $Level = $_[0];
    foreach my $Symbol (sort keys(%{$CompleteSignature{1}}))
    {
        if($Level eq "Source")
        { # remove symbol version
            my ($SN, $SS, $SV) = separate_symbol($Symbol);
            $Symbol=$SN;
        }
        if(not $CompleteSignature{1}{$Symbol}{"Header"}
        or not $CompleteSignature{1}{$Symbol}{"MnglName"}) {
            next;
        }
        if($ExtendedSymbols{$Symbol}) {
            next;
        }
        if(not defined $CompleteSignature{2}{$Symbol}
        or not $CompleteSignature{2}{$Symbol}{"MnglName"})
        {
            if($UsedDump{1}{"SrcBin"})
            {
                if($UsedDump{2}{"BinOnly"} or not checkDump(2, "2.11"))
                { # support for old and different (!) ABI dumps
                    if(not $CompleteSignature{1}{$Symbol}{"Virt"}
                    and not $CompleteSignature{1}{$Symbol}{"PureVirt"})
                    {
                        if($CheckHeadersOnly)
                        { # skip all removed symbols
                            if(my $Lang = $CompleteSignature{1}{$Symbol}{"Lang"})
                            {
                                if($Lang eq "C")
                                { # support for old ABI dumps: missed extern "C" functions
                                    next;
                                }
                            }
                        }
                        else
                        {
                            if(not link_symbol($Symbol, 1, "-Deps"))
                            { # skip removed inline symbols
                                next;
                            }
                        }
                    }
                }
            }
            if(not checkDump(1, "2.15"))
            {
                if($Symbol=~/_IT_E\Z/)
                { # _ZN28QExplicitlySharedDataPointerI22QSslCertificatePrivateEC1IT_EERKS_IT_E
                    next;
                }
            }
            if(not $CompleteSignature{1}{$Symbol}{"Class"})
            {
                if(my $Short = $CompleteSignature{1}{$Symbol}{"ShortName"})
                {
                    if(defined $Constants{2}{$Short})
                    {
                        my $Val = $Constants{2}{$Short}{"Value"};
                        if(defined $Func_ShortName{2}{$Val})
                        { # old name defined to new
                            next;
                        }
                    }
                }
                
            }
            $RemovedInt{$Level}{$Symbol} = 1;
            if($Level eq "Source")
            { # search for a source-compatible equivalent
                setAlternative($Symbol, $Level);
            }
        }
    }
}

sub mergeHeaders($)
{
    my $Level = $_[0];
    foreach my $Symbol (sort keys(%{$AddedInt{$Level}}))
    { # checking added symbols
        next if($CompleteSignature{2}{$Symbol}{"PureVirt"});
        next if($CompleteSignature{2}{$Symbol}{"Private"});
        next if(not symbolFilter($Symbol, 2, "Affected", $Level));
        if($Level eq "Binary")
        {
            if($CompleteSignature{2}{$Symbol}{"InLine"})
            {
                if(not $CompleteSignature{2}{$Symbol}{"Virt"})
                { # skip inline non-virtual functions
                    next;
                }
            }
        }
        else
        { # Source
            if($SourceAlternative_B{$Symbol}) {
                next;
            }
        }
        %{$CompatProblems{$Level}{$Symbol}{"Added_Symbol"}{""}}=();
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # checking removed symbols
        next if($CompleteSignature{1}{$Symbol}{"PureVirt"});
        next if($CompleteSignature{1}{$Symbol}{"Private"});
        next if(not symbolFilter($Symbol, 1, "Affected", $Level));
        if($Level eq "Binary")
        {
            if($CompleteSignature{1}{$Symbol}{"InLine"})
            {
                if(not $CompleteSignature{1}{$Symbol}{"Virt"})
                { # skip inline non-virtual functions
                    next;
                }
            }
        }
        else
        { # Source
            if(my $Alt = $SourceAlternative{$Symbol})
            {
                if(defined $CompleteSignature{1}{$Alt}
                and $CompleteSignature{1}{$Symbol}{"Const"})
                {
                    my $Cid = $CompleteSignature{1}{$Symbol}{"Class"};
                    %{$CompatProblems{$Level}{$Symbol}{"Removed_Const_Overload"}{"this"}}=(
                        "Type_Name"=>$TypeInfo{1}{$Cid}{"Name"},
                        "Target"=>get_Signature($Alt, 1));
                }
                else
                { # do NOT show removed symbol
                    next;
                }
            }
        }
        %{$CompatProblems{$Level}{$Symbol}{"Removed_Symbol"}{""}}=();
    }
}

sub addParamNames($)
{
    my $LibraryVersion = $_[0];
    return if(not keys(%AddIntParams));
    my $SecondVersion = $LibraryVersion==1?2:1;
    foreach my $Interface (sort keys(%{$CompleteSignature{$LibraryVersion}}))
    {
        next if(not keys(%{$AddIntParams{$Interface}}));
        foreach my $ParamPos (sort {int($a)<=>int($b)} keys(%{$CompleteSignature{$LibraryVersion}{$Interface}{"Param"}}))
        { # add absent parameter names
            my $ParamName = $CompleteSignature{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"};
            if($ParamName=~/\Ap\d+\Z/ and my $NewParamName = $AddIntParams{$Interface}{$ParamPos})
            { # names from the external file
                if(defined $CompleteSignature{$SecondVersion}{$Interface}
                and defined $CompleteSignature{$SecondVersion}{$Interface}{"Param"}{$ParamPos})
                {
                    if($CompleteSignature{$SecondVersion}{$Interface}{"Param"}{$ParamPos}{"name"}=~/\Ap\d+\Z/) {
                        $CompleteSignature{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"} = $NewParamName;
                    }
                }
                else {
                    $CompleteSignature{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"} = $NewParamName;
                }
            }
        }
    }
}

sub detectChangedTypedefs()
{ # detect changed typedefs to show
  # correct function signatures
    foreach my $Typedef (keys(%{$Typedef_BaseName{1}}))
    {
        next if(not $Typedef);
        my $BName1 = $Typedef_BaseName{1}{$Typedef};
        if(not $BName1 or isAnon($BName1)) {
            next;
        }
        my $BName2 = $Typedef_BaseName{2}{$Typedef};
        if(not $BName2 or isAnon($BName2)) {
            next;
        }
        if($BName1 ne $BName2) {
            $ChangedTypedef{$Typedef} = 1;
        }
    }
}

sub get_symbol_suffix($$)
{
    my ($Symbol, $Full) = @_;
    my ($SN, $SO, $SV) = separate_symbol($Symbol);
    $Symbol=$SN; # remove version
    my $Signature = $tr_name{$Symbol};
    my $Suffix = substr($Signature, find_center($Signature, "("));
    if(not $Full) {
        $Suffix=~s/(\))\s*(const volatile|volatile const|const|volatile)\Z/$1/g;
    }
    return $Suffix;
}

sub get_symbol_prefix($$)
{
    my ($Symbol, $LibVersion) = @_;
    my $ShortName = $CompleteSignature{$LibVersion}{$Symbol}{"ShortName"};
    if(my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"})
    { # methods
        $ShortName = $TypeInfo{$LibVersion}{$ClassId}{"Name"}."::".$ShortName;
    }
    return $ShortName;
}

sub setAlternative($)
{
    my $Symbol = $_[0];
    my $PSymbol = $Symbol;
    if(not defined $CompleteSignature{2}{$PSymbol}
    or (not $CompleteSignature{2}{$PSymbol}{"MnglName"}
    and not $CompleteSignature{2}{$PSymbol}{"ShortName"}))
    { # search for a pair
        if(my $ShortName = $CompleteSignature{1}{$PSymbol}{"ShortName"})
        {
            if($CompleteSignature{1}{$PSymbol}{"Data"})
            {
                if($PSymbol=~s/L(\d+$ShortName(E)\Z)/$1/
                or $PSymbol=~s/(\d+$ShortName(E)\Z)/L$1/)
                {
                    if(defined $CompleteSignature{2}{$PSymbol}
                    and $CompleteSignature{2}{$PSymbol}{"MnglName"})
                    {
                        $SourceAlternative{$Symbol} = $PSymbol;
                        $SourceAlternative_B{$PSymbol} = $Symbol;
                        if(not defined $CompleteSignature{1}{$PSymbol}
                        or not $CompleteSignature{1}{$PSymbol}{"MnglName"}) {
                            $SourceReplacement{$Symbol} = $PSymbol;
                        }
                    }
                }
            }
            else
            {
                foreach my $Sp ("KV", "VK", "K", "V")
                {
                    if($PSymbol=~s/\A_ZN$Sp/_ZN/
                    or $PSymbol=~s/\A_ZN/_ZN$Sp/)
                    {
                        if(defined $CompleteSignature{2}{$PSymbol}
                        and $CompleteSignature{2}{$PSymbol}{"MnglName"})
                        {
                            $SourceAlternative{$Symbol} = $PSymbol;
                            $SourceAlternative_B{$PSymbol} = $Symbol;
                            if(not defined $CompleteSignature{1}{$PSymbol}
                            or not $CompleteSignature{1}{$PSymbol}{"MnglName"}) {
                                $SourceReplacement{$Symbol} = $PSymbol;
                            }
                        }
                    }
                    $PSymbol = $Symbol;
                }
            }
        }
    }
    return "";
}

sub getSymKind($$)
{
    my ($Symbol, $LibVersion) = @_;
    if($CompleteSignature{$LibVersion}{$Symbol}{"Data"})
    {
        return "Global_Data";
    }
    elsif($CompleteSignature{$LibVersion}{$Symbol}{"Class"})
    {
        return "Method";
    }
    return "Function";
}

sub mergeSymbols($)
{
    my $Level = $_[0];
    my %SubProblems = ();
    
    mergeBases($Level);
    
    my %AddedOverloads = ();
    foreach my $Symbol (sort keys(%{$AddedInt{$Level}}))
    { # check all added exported symbols
        if(not $CompleteSignature{2}{$Symbol}{"Header"}) {
            next;
        }
        if(defined $CompleteSignature{1}{$Symbol}
        and $CompleteSignature{1}{$Symbol}{"Header"})
        { # double-check added symbol
            next;
        }
        if(not symbolFilter($Symbol, 2, "Affected", $Level)) {
            next;
        }
        if($Symbol=~/\A(_Z|\?)/)
        { # C++
            $AddedOverloads{get_symbol_prefix($Symbol, 2)}{get_symbol_suffix($Symbol, 1)} = $Symbol;
        }
        if(my $OverriddenMethod = $CompleteSignature{2}{$Symbol}{"Override"})
        { # register virtual overridings
            my $Cid = $CompleteSignature{2}{$Symbol}{"Class"};
            my $AffectedClass_Name = $TypeInfo{2}{$Cid}{"Name"};
            if(defined $CompleteSignature{1}{$OverriddenMethod} and $CompleteSignature{1}{$OverriddenMethod}{"Virt"}
            and not $CompleteSignature{1}{$OverriddenMethod}{"Private"})
            {
                if($TName_Tid{1}{$AffectedClass_Name})
                { # class should exist in previous version
                    if(not isCopyingClass($TName_Tid{1}{$AffectedClass_Name}, 1))
                    { # old v-table is NOT copied by old applications
                        %{$CompatProblems{$Level}{$OverriddenMethod}{"Overridden_Virtual_Method"}{$tr_name{$Symbol}}}=(
                            "Type_Name"=>$AffectedClass_Name,
                            "Target"=>get_Signature($Symbol, 2),
                            "Old_Value"=>get_Signature($OverriddenMethod, 2),
                            "New_Value"=>get_Signature($Symbol, 2));
                    }
                }
            }
        }
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # check all removed exported symbols
        if(not $CompleteSignature{1}{$Symbol}{"Header"}) {
            next;
        }
        if(defined $CompleteSignature{2}{$Symbol}
        and $CompleteSignature{2}{$Symbol}{"Header"})
        { # double-check removed symbol
            next;
        }
        if($CompleteSignature{1}{$Symbol}{"Private"})
        { # skip private methods
            next;
        }
        if(not symbolFilter($Symbol, 1, "Affected", $Level)) {
            next;
        }
        $CheckedSymbols{$Level}{$Symbol} = 1;
        if(my $OverriddenMethod = $CompleteSignature{1}{$Symbol}{"Override"})
        { # register virtual overridings
            my $Cid = $CompleteSignature{1}{$Symbol}{"Class"};
            my $AffectedClass_Name = $TypeInfo{1}{$Cid}{"Name"};
            if(defined $CompleteSignature{2}{$OverriddenMethod}
            and $CompleteSignature{2}{$OverriddenMethod}{"Virt"})
            {
                if($TName_Tid{2}{$AffectedClass_Name})
                { # class should exist in newer version
                    if(not isCopyingClass($CompleteSignature{1}{$Symbol}{"Class"}, 1))
                    { # old v-table is NOT copied by old applications
                        %{$CompatProblems{$Level}{$Symbol}{"Overridden_Virtual_Method_B"}{$tr_name{$OverriddenMethod}}}=(
                            "Type_Name"=>$AffectedClass_Name,
                            "Target"=>get_Signature($OverriddenMethod, 1),
                            "Old_Value"=>get_Signature($Symbol, 1),
                            "New_Value"=>get_Signature($OverriddenMethod, 1));
                    }
                }
            }
        }
        if($Level eq "Binary"
        and $OStarget eq "windows")
        { # register the reason of symbol name change
            if(my $NewSym = $mangled_name{2}{$tr_name{$Symbol}})
            {
                if($AddedInt{$Level}{$NewSym})
                {
                    if($CompleteSignature{1}{$Symbol}{"Static"} ne $CompleteSignature{2}{$NewSym}{"Static"})
                    {
                        if($CompleteSignature{2}{$NewSym}{"Static"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Static"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Non_Static"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                    }
                    if($CompleteSignature{1}{$Symbol}{"Virt"} ne $CompleteSignature{2}{$NewSym}{"Virt"})
                    {
                        if($CompleteSignature{2}{$NewSym}{"Virt"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Virtual"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Non_Virtual"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                    }
                    my $RTId1 = $CompleteSignature{1}{$Symbol}{"Return"};
                    my $RTId2 = $CompleteSignature{2}{$NewSym}{"Return"};
                    my $RTName1 = $TypeInfo{1}{$RTId1}{"Name"};
                    my $RTName2 = $TypeInfo{2}{$RTId2}{"Name"};
                    if($RTName1 ne $RTName2)
                    {
                        my $ProblemType = "Symbol_Changed_Return";
                        if($CompleteSignature{1}{$Symbol}{"Data"}) {
                            $ProblemType = "Global_Data_Symbol_Changed_Type";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "Old_Type"=>$RTName1,
                            "New_Type"=>$RTName2,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                }
            }
        }
        if($Symbol=~/\A(_Z|\?)/)
        { # C++
            my $Prefix = get_symbol_prefix($Symbol, 1);
            if(my @Overloads = sort keys(%{$AddedOverloads{$Prefix}})
            and not $AddedOverloads{$Prefix}{get_symbol_suffix($Symbol, 1)})
            { # changed signature: params, "const"-qualifier
                my $NewSym = $AddedOverloads{$Prefix}{$Overloads[0]};
                if($CompleteSignature{1}{$Symbol}{"Constructor"})
                {
                    if($Symbol=~/(C[1-2][EI])/)
                    {
                        my $CtorType = $1;
                        $NewSym=~s/(C[1-2][EI])/$CtorType/g;
                    }
                }
                elsif($CompleteSignature{1}{$Symbol}{"Destructor"})
                {
                    if($Symbol=~/(D[0-2][EI])/)
                    {
                        my $DtorType = $1;
                        $NewSym=~s/(D[0-2][EI])/$DtorType/g;
                    }
                }
                my $NS1 = $CompleteSignature{1}{$Symbol}{"NameSpace"};
                my $NS2 = $CompleteSignature{2}{$NewSym}{"NameSpace"};
                if((not $NS1 and not $NS2) or ($NS1 and $NS2 and $NS1 eq $NS2))
                { # from the same class and namespace
                    if($CompleteSignature{1}{$Symbol}{"Const"}
                    and not $CompleteSignature{2}{$NewSym}{"Const"})
                    { # "const" to non-"const"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Const"}{$tr_name{$Symbol}}}=(
                            "Type_Name"=>$TypeInfo{1}{$CompleteSignature{1}{$Symbol}{"Class"}}{"Name"},
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSym, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    elsif(not $CompleteSignature{1}{$Symbol}{"Const"}
                    and $CompleteSignature{2}{$NewSym}{"Const"})
                    { # non-"const" to "const"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Const"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSym, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    if($CompleteSignature{1}{$Symbol}{"Volatile"}
                    and not $CompleteSignature{2}{$NewSym}{"Volatile"})
                    { # "volatile" to non-"volatile"
                        
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Volatile"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSym, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    elsif(not $CompleteSignature{1}{$Symbol}{"Volatile"}
                    and $CompleteSignature{2}{$NewSym}{"Volatile"})
                    { # non-"volatile" to "volatile"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Volatile"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSym, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    if(get_symbol_suffix($Symbol, 0) ne get_symbol_suffix($NewSym, 0))
                    { # params list
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Changed_Parameters"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSym, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                }
            }
        }
    }
    foreach my $Symbol (sort keys(%{$CompleteSignature{1}}))
    { # checking symbols
        $CurrentSymbol = $Symbol;
        
        my ($SN, $SS, $SV) = separate_symbol($Symbol);
        if($Level eq "Source")
        { # remove symbol version
            $Symbol=$SN;
        }
        else
        { # Binary
            if(not $SV)
            { # symbol without version
                if(my $VSym = $SymVer{1}{$Symbol})
                { # the symbol is linked with versioned symbol
                    if($CompleteSignature{2}{$VSym}{"MnglName"})
                    { # show report for symbol@ver only
                        next;
                    }
                    elsif(not link_symbol($VSym, 2, "-Deps"))
                    { # changed version: sym@v1 to sym@v2
                      # do NOT show report for symbol
                        next;
                    }
                }
            }
        }
        my $PSymbol = $Symbol;
        if($Level eq "Source"
        and my $S = $SourceReplacement{$Symbol})
        { # take a source-compatible replacement function
            $PSymbol = $S;
        }
        if($CompleteSignature{1}{$Symbol}{"Private"})
        { # private symbols
            next;
        }
        if(not defined $CompleteSignature{1}{$Symbol}
        or not defined $CompleteSignature{2}{$PSymbol})
        { # no info
            next;
        }
        if(not $CompleteSignature{1}{$Symbol}{"MnglName"}
        or not $CompleteSignature{2}{$PSymbol}{"MnglName"})
        { # no mangled name
            next;
        }
        if(not $CompleteSignature{1}{$Symbol}{"Header"}
        or not $CompleteSignature{2}{$PSymbol}{"Header"})
        { # without a header
            next;
        }
        
        if(not $CompleteSignature{1}{$Symbol}{"PureVirt"}
        and $CompleteSignature{2}{$PSymbol}{"PureVirt"})
        { # became pure
            next;
        }
        if($CompleteSignature{1}{$Symbol}{"PureVirt"}
        and not $CompleteSignature{2}{$PSymbol}{"PureVirt"})
        { # became non-pure
            next;
        }
        
        if(not symbolFilter($Symbol, 1, "Affected + InlineVirt", $Level))
        { # exported, target, inline virtual and pure virtual
            next;
        }
        if(not symbolFilter($PSymbol, 2, "Affected + InlineVirt", $Level))
        { # exported, target, inline virtual and pure virtual
            next;
        }
        
        if(checkDump(1, "2.13") and checkDump(2, "2.13"))
        {
            if($CompleteSignature{1}{$Symbol}{"Data"}
            and $CompleteSignature{2}{$PSymbol}{"Data"})
            {
                my $Value1 = $CompleteSignature{1}{$Symbol}{"Value"};
                my $Value2 = $CompleteSignature{2}{$PSymbol}{"Value"};
                if(defined $Value1)
                {
                    $Value1 = showVal($Value1, $CompleteSignature{1}{$Symbol}{"Return"}, 1);
                    if(defined $Value2)
                    {
                        $Value2 = showVal($Value2, $CompleteSignature{2}{$PSymbol}{"Return"}, 2);
                        if($Value1 ne $Value2)
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Global_Data_Value_Changed"}{""}}=(
                                "Old_Value"=>$Value1,
                                "New_Value"=>$Value2,
                                "Target"=>get_Signature($Symbol, 1)  );
                        }
                    }
                }
            }
        }
        
        if($CompleteSignature{2}{$PSymbol}{"Private"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Private"}{""}}=(
                "Target"=>get_Signature_M($PSymbol, 2)  );
        }
        elsif(not $CompleteSignature{1}{$Symbol}{"Protected"}
        and $CompleteSignature{2}{$PSymbol}{"Protected"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Protected"}{""}}=(
                "Target"=>get_Signature_M($PSymbol, 2)  );
        }
        elsif($CompleteSignature{1}{$Symbol}{"Protected"}
        and not $CompleteSignature{2}{$PSymbol}{"Protected"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Public"}{""}}=(
                "Target"=>get_Signature_M($PSymbol, 2)  );
        }
        
        # checking virtual table
        mergeVirtualTables($Symbol, $Level);
        
        if($COMPILE_ERRORS)
        { # if some errors occurred at the compiling stage
          # then some false positives can be skipped here
            if(not $CompleteSignature{1}{$Symbol}{"Data"} and $CompleteSignature{2}{$PSymbol}{"Data"}
            and not $GlobalDataObject{2}{$Symbol})
            { # missed information about parameters in newer version
                next;
            }
            if($CompleteSignature{1}{$Symbol}{"Data"} and not $GlobalDataObject{1}{$Symbol}
            and not $CompleteSignature{2}{$PSymbol}{"Data"})
            { # missed information about parameters in older version
                next;
            }
        }
        my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Symbol);
        # checking attributes
        if($CompleteSignature{2}{$PSymbol}{"Static"}
        and not $CompleteSignature{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/)
        {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Static"}{""}}=(
                "Target"=>get_Signature($Symbol, 1)
            );
        }
        elsif(not $CompleteSignature{2}{$PSymbol}{"Static"}
        and $CompleteSignature{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/)
        {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Static"}{""}}=(
                "Target"=>get_Signature($Symbol, 1)
            );
        }
        if(($CompleteSignature{1}{$Symbol}{"Virt"} and $CompleteSignature{2}{$PSymbol}{"Virt"})
        or ($CompleteSignature{1}{$Symbol}{"PureVirt"} and $CompleteSignature{2}{$PSymbol}{"PureVirt"}))
        { # relative position of virtual and pure virtual methods
            if($Level eq "Binary")
            {
                if(defined $CompleteSignature{1}{$Symbol}{"RelPos"} and defined $CompleteSignature{2}{$PSymbol}{"RelPos"}
                and $CompleteSignature{1}{$Symbol}{"RelPos"}!=$CompleteSignature{2}{$PSymbol}{"RelPos"})
                { # top-level virtual methods only
                    my $Class_Id = $CompleteSignature{1}{$Symbol}{"Class"};
                    my $Class_Name = $TypeInfo{1}{$Class_Id}{"Name"};
                    if(defined $VirtualTable{1}{$Class_Name} and defined $VirtualTable{2}{$Class_Name}
                    and $VirtualTable{1}{$Class_Name}{$Symbol}!=$VirtualTable{2}{$Class_Name}{$Symbol})
                    { # check the absolute position of virtual method (including added and removed methods)
                        my %Class_Type = get_Type($Class_Id, 1);
                        my $ProblemType = "Virtual_Method_Position";
                        if($CompleteSignature{1}{$Symbol}{"PureVirt"}) {
                            $ProblemType = "Pure_Virtual_Method_Position";
                        }
                        if(isUsedClass($Class_Id, 1, $Level))
                        {
                            my @Affected = ($Symbol, keys(%{$OverriddenMethods{1}{$Symbol}}));
                            foreach my $ASymbol (@Affected)
                            {
                                if(not symbolFilter($ASymbol, 1, "Affected", $Level)) {
                                    next;
                                }
                                %{$CompatProblems{$Level}{$ASymbol}{$ProblemType}{$tr_name{$MnglName}}}=(
                                    "Type_Name"=>$Class_Type{"Name"},
                                    "Old_Value"=>$CompleteSignature{1}{$Symbol}{"RelPos"},
                                    "New_Value"=>$CompleteSignature{2}{$PSymbol}{"RelPos"},
                                    "Target"=>get_Signature($Symbol, 1));
                            }
                            $VTableChanged_M{$Class_Type{"Name"}} = 1;
                        }
                    }
                }
            }
        }
        if($CompleteSignature{1}{$Symbol}{"PureVirt"}
        or $CompleteSignature{2}{$PSymbol}{"PureVirt"})
        { # do NOT check type changes in pure virtuals
            next;
        }
        $CheckedSymbols{$Level}{$Symbol} = 1;
        if($Symbol=~/\A(_Z|\?)/
        or keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})==keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}}))
        { # C/C++: changes in parameters
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # checking parameters
                mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level, 1);
            }
        }
        else
        { # C: added/removed parameters
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}}))
            { # checking added parameters
                my $PType2_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                my $PType2_Name = $TypeInfo{2}{$PType2_Id}{"Name"};
                last if($PType2_Name eq "...");
                my $PName = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"name"};
                my $PName_Old = (defined $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos})?$CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_Prev = "-1";
                if($PName=~/\Ap\d+\Z/i)
                { # added unnamed parameter ( pN )
                    my @Positions1 = find_ParamPair_Pos_byTypeAndPos($PType2_Name, $ParamPos, "backward", $Symbol, 1);
                    my @Positions2 = find_ParamPair_Pos_byTypeAndPos($PType2_Name, $ParamPos, "backward", $Symbol, 2);
                    if($#Positions1==-1 or $#Positions2>$#Positions1) {
                        $ParamPos_Prev = "lost";
                    }
                }
                else {
                    $ParamPos_Prev = find_ParamPair_Pos_byName($PName, $Symbol, 1);
                }
                if($ParamPos_Prev eq "lost")
                {
                    if($ParamPos>keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Added_Parameter";
                        if($PName=~/\Ap\d+\Z/) {
                            $ProblemType = "Added_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                            "Target"=>$PName,
                            "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                            "Param_Type"=>$PType2_Name,
                            "New_Signature"=>get_Signature($Symbol, 2)  );
                    }
                    else
                    {
                        my %ParamType_Pure = get_PureType($PType2_Id, $TypeInfo{2});
                        my $PairType_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                        my %PairType_Pure = get_PureType($PairType_Id, $TypeInfo{1});
                        if(($ParamType_Pure{"Name"} eq $PairType_Pure{"Name"} or $PType2_Name eq $TypeInfo{1}{$PairType_Id}{"Name"})
                        and find_ParamPair_Pos_byName($PName_Old, $Symbol, 2) eq "lost")
                        {
                            if($PName_Old!~/\Ap\d+\Z/ and $PName!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos)." Parameter"}}=(
                                    "Target"=>$PName_Old,
                                    "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                    "Param_Type"=>$PType2_Name,
                                    "Old_Value"=>$PName_Old,
                                    "New_Value"=>$PName,
                                    "New_Signature"=>get_Signature($Symbol, 2)  );
                            }
                        }
                        else
                        {
                            my $ProblemType = "Added_Middle_Parameter";
                            if($PName=~/\Ap\d+\Z/) {
                                $ProblemType = "Added_Middle_Unnamed_Parameter";
                            }
                            %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                                "Target"=>$PName,
                                "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                "Param_Type"=>$PType2_Name,
                                "New_Signature"=>get_Signature($Symbol, 2)  );
                        }
                    }
                }
            }
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # check relevant parameters
                my $PType1_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                my $ParamName1 = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"name"};
                # FIXME: find relevant parameter by name
                if(defined $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos})
                {
                    my $PType2_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                    my $ParamName2 = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"name"};
                    if($TypeInfo{1}{$PType1_Id}{"Name"} eq $TypeInfo{2}{$PType2_Id}{"Name"}
                    or ($ParamName1!~/\Ap\d+\Z/i and $ParamName1 eq $ParamName2)) {
                        mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level, 0);
                    }
                }
            }
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # checking removed parameters
                my $PType1_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                my $PType1_Name = $TypeInfo{1}{$PType1_Id}{"Name"};
                last if($PType1_Name eq "...");
                my $PName = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"name"};
                my $PName_New = (defined $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos})?$CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_New = "-1";
                if($PName=~/\Ap\d+\Z/i)
                { # removed unnamed parameter ( pN )
                    my @Positions1 = find_ParamPair_Pos_byTypeAndPos($PType1_Name, $ParamPos, "forward", $Symbol, 1);
                    my @Positions2 = find_ParamPair_Pos_byTypeAndPos($PType1_Name, $ParamPos, "forward", $Symbol, 2);
                    if($#Positions2==-1 or $#Positions2<$#Positions1) {
                        $ParamPos_New = "lost";
                    }
                }
                else {
                    $ParamPos_New = find_ParamPair_Pos_byName($PName, $Symbol, 2);
                }
                if($ParamPos_New eq "lost")
                {
                    if($ParamPos>keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Removed_Parameter";
                        if($PName=~/\Ap\d+\Z/) {
                            $ProblemType = "Removed_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                            "Target"=>$PName,
                            "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                            "Param_Type"=>$PType1_Name,
                            "New_Signature"=>get_Signature($Symbol, 2)  );
                    }
                    elsif($ParamPos<keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})-1)
                    {
                        my %ParamType_Pure = get_PureType($PType1_Id, $TypeInfo{1});
                        my $PairType_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                        my %PairType_Pure = get_PureType($PairType_Id, $TypeInfo{2});
                        if(($ParamType_Pure{"Name"} eq $PairType_Pure{"Name"} or $PType1_Name eq $TypeInfo{2}{$PairType_Id}{"Name"})
                        and find_ParamPair_Pos_byName($PName_New, $Symbol, 1) eq "lost")
                        {
                            if($PName_New!~/\Ap\d+\Z/ and $PName!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos)." Parameter"}}=(
                                    "Target"=>$PName,
                                    "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                    "Param_Type"=>$PType1_Name,
                                    "Old_Value"=>$PName,
                                    "New_Value"=>$PName_New,
                                    "New_Signature"=>get_Signature($Symbol, 2)  );
                            }
                        }
                        else
                        {
                            my $ProblemType = "Removed_Middle_Parameter";
                            if($PName=~/\Ap\d+\Z/) {
                                $ProblemType = "Removed_Middle_Unnamed_Parameter";
                            }
                            %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                                "Target"=>$PName,
                                "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                "Param_Type"=>$PType1_Name,
                                "New_Signature"=>get_Signature($Symbol, 2)  );
                        }
                    }
                }
            }
        }
        # checking return type
        my $ReturnType1_Id = $CompleteSignature{1}{$Symbol}{"Return"};
        my $ReturnType2_Id = $CompleteSignature{2}{$PSymbol}{"Return"};
        my %RC_SubProblems = detectTypeChange($ReturnType1_Id, $ReturnType2_Id, "Return", $Level);
        
        foreach my $SubProblemType (keys(%RC_SubProblems))
        {
            my $New_Value = $RC_SubProblems{$SubProblemType}{"New_Value"};
            my $Old_Value = $RC_SubProblems{$SubProblemType}{"Old_Value"};
            my %ProblemTypes = ();
            
            if($CompleteSignature{1}{$Symbol}{"Data"})
            {
                if($SubProblemType eq "Return_Type_And_Size") {
                    $ProblemTypes{"Global_Data_Type_And_Size"} = 1;
                }
                elsif($SubProblemType eq "Return_Type_Format") {
                    $ProblemTypes{"Global_Data_Type_Format"} = 1;
                }
                else {
                    $ProblemTypes{"Global_Data_Type"} = 1;
                }
                
                # quals
                if($SubProblemType eq "Return_Type"
                or $SubProblemType eq "Return_Type_And_Size"
                or $SubProblemType eq "Return_Type_Format")
                {
                    if(my $RR = removedQual($Old_Value, $New_Value, "const"))
                    { # const to non-const
                        if($RR==2) {
                            $ProblemTypes{"Global_Data_Removed_Const"} = 1;
                        }
                        else {
                            $ProblemTypes{"Global_Data_Became_Non_Const"} = 1;
                        }
                        $ProblemTypes{"Global_Data_Type"} = 1;
                    }
                    elsif(my $RA = addedQual($Old_Value, $New_Value, "const"))
                    { # non-const to const
                        if($RA==2) {
                            $ProblemTypes{"Global_Data_Added_Const"} = 1;
                        }
                        else {
                            $ProblemTypes{"Global_Data_Became_Const"} = 1;
                        }
                        $ProblemTypes{"Global_Data_Type"} = 1;
                    }
                }
            }
            else
            {
                # quals
                if($SubProblemType eq "Return_Type"
                or $SubProblemType eq "Return_Type_And_Size"
                or $SubProblemType eq "Return_Type_Format")
                {
                    if(checkDump(1, "2.6") and checkDump(2, "2.6"))
                    {
                        if(addedQual($Old_Value, $New_Value, "volatile"))
                        {
                            $ProblemTypes{"Return_Value_Became_Volatile"} = 1;
                            if($Level ne "Source"
                            or not cmpBTypes($Old_Value, $New_Value, 1, 2)) {
                                $ProblemTypes{"Return_Type"} = 1;
                            }
                        }
                    }
                    if(my $RA = addedQual($Old_Value, $New_Value, "const"))
                    {
                        if($RA==2) {
                            $ProblemTypes{"Return_Type_Added_Const"} = 1;
                        }
                        else {
                            $ProblemTypes{"Return_Type_Became_Const"} = 1;
                        }
                        if($Level ne "Source"
                        or not cmpBTypes($Old_Value, $New_Value, 1, 2)) {
                            $ProblemTypes{"Return_Type"} = 1;
                        }
                    }
                }
            }
            if($Level eq "Binary"
            and not $CompleteSignature{1}{$Symbol}{"Data"})
            {
                my ($Arch1, $Arch2) = (getArch(1), getArch(2));
                if($Arch1 eq "unknown" or $Arch2 eq "unknown")
                { # if one of the architectures is unknown
                    # then set other arhitecture to unknown too
                    ($Arch1, $Arch2) = ("unknown", "unknown");
                }
                my (%Conv1, %Conv2) = ();
                if($UseConv_Real{1}{"R"} and $UseConv_Real{2}{"R"})
                {
                    %Conv1 = callingConvention_R_Real($CompleteSignature{1}{$Symbol});
                    %Conv2 = callingConvention_R_Real($CompleteSignature{2}{$PSymbol});
                }
                else
                {
                    %Conv1 = callingConvention_R_Model($CompleteSignature{1}{$Symbol}, $TypeInfo{1}, $Arch1, $OStarget, $WORD_SIZE{1});
                    %Conv2 = callingConvention_R_Model($CompleteSignature{2}{$PSymbol}, $TypeInfo{2}, $Arch2, $OStarget, $WORD_SIZE{2});
                }
                
                if($SubProblemType eq "Return_Type_Became_Void")
                {
                    if(keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
                    { # parameters stack has been affected
                        if($Conv1{"Method"} eq "stack") {
                            $ProblemTypes{"Return_Type_Became_Void_And_Stack_Layout"} = 1;
                        }
                        elsif($Conv1{"Hidden"}) {
                            $ProblemTypes{"Return_Type_Became_Void_And_Register"} = 1;
                        }
                    }
                }
                elsif($SubProblemType eq "Return_Type_From_Void")
                {
                    if(keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
                    { # parameters stack has been affected
                        if($Conv2{"Method"} eq "stack") {
                            $ProblemTypes{"Return_Type_From_Void_And_Stack_Layout"} = 1;
                        }
                        elsif($Conv2{"Hidden"}) {
                            $ProblemTypes{"Return_Type_From_Void_And_Register"} = 1;
                        }
                    }
                }
                elsif($SubProblemType eq "Return_Type"
                or $SubProblemType eq "Return_Type_And_Size"
                or $SubProblemType eq "Return_Type_Format")
                {
                    if($Conv1{"Method"} ne $Conv2{"Method"})
                    {
                        if($Conv1{"Method"} eq "stack")
                        { # returns in a register instead of a hidden first parameter
                            $ProblemTypes{"Return_Type_From_Stack_To_Register"} = 1;
                        }
                        else {
                            $ProblemTypes{"Return_Type_From_Register_To_Stack"} = 1;
                        }
                    }
                    else
                    {
                        if($Conv1{"Method"} eq "reg")
                        {
                            if($Conv1{"Registers"} ne $Conv2{"Registers"})
                            {
                                if($Conv1{"Hidden"}) {
                                    $ProblemTypes{"Return_Type_And_Register_Was_Hidden_Parameter"} = 1;
                                }
                                elsif($Conv2{"Hidden"}) {
                                    $ProblemTypes{"Return_Type_And_Register_Became_Hidden_Parameter"} = 1;
                                }
                                else {
                                    $ProblemTypes{"Return_Type_And_Register"} = 1;
                                }
                            }
                        }
                    }
                }
            }
            
            if(not keys(%ProblemTypes))
            { # default
                $ProblemTypes{$SubProblemType} = 1;
            }
            
            foreach my $ProblemType (keys(%ProblemTypes))
            { # additional
                $CompatProblems{$Level}{$Symbol}{$ProblemType}{"retval"} = $RC_SubProblems{$SubProblemType};
            }
        }
        if($ReturnType1_Id and $ReturnType2_Id)
        {
            @RecurTypes = ();
            my $Sub_SubProblems = mergeTypes($ReturnType1_Id, $ReturnType2_Id, $Level);
            
            my $AddProblems = {};
            
            if($CompleteSignature{1}{$Symbol}{"Data"})
            {
                if($Level eq "Binary")
                {
                    if(get_PLevel($ReturnType1_Id, 1)==0)
                    {
                        if(defined $Sub_SubProblems->{"DataType_Size"})
                        { # add "Global_Data_Size" problem
                            
                            foreach my $Loc (keys(%{$Sub_SubProblems->{"DataType_Size"}}))
                            {
                                if(index($Loc,"->")==-1)
                                { 
                                    if($Loc eq $Sub_SubProblems->{"DataType_Size"}{$Loc}{"Type_Name"})
                                    {
                                        $AddProblems->{"Global_Data_Size"}{$Loc} = $Sub_SubProblems->{"DataType_Size"}{$Loc}; # add a new problem
                                        last;
                                    }
                                }
                            }
                        }
                    }
                    if(not defined $AddProblems->{"Global_Data_Size"})
                    {
                        if(defined $GlobalDataObject{1}{$Symbol}
                        and defined $GlobalDataObject{2}{$Symbol})
                        {
                            my $Old_Size = $GlobalDataObject{1}{$Symbol};
                            my $New_Size = $GlobalDataObject{2}{$Symbol};
                            if($Old_Size!=$New_Size)
                            {
                                $AddProblems->{"Global_Data_Size"}{"retval"} = {
                                    "Old_Size"=>$Old_Size*$BYTE_SIZE,
                                    "New_Size"=>$New_Size*$BYTE_SIZE };
                            }
                        }
                    }
                }
            }
            
            foreach my $SubProblemType (keys(%{$AddProblems}))
            {
                foreach my $SubLocation (keys(%{$AddProblems->{$SubProblemType}}))
                {
                    my $NewLocation = "retval";
                    if($SubLocation and $SubLocation ne "retval") {
                        $NewLocation = "retval->".$SubLocation;
                    }
                    $CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation} = $AddProblems->{$SubProblemType}{$SubLocation};
                }
            }
            
            foreach my $SubProblemType (keys(%{$Sub_SubProblems}))
            {
                foreach my $SubLocation (keys(%{$Sub_SubProblems->{$SubProblemType}}))
                {
                    my $NewLocation = "retval";
                    if($SubLocation and $SubLocation ne "retval") {
                        $NewLocation = "retval->".$SubLocation;
                    }
                    $CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation} = $Sub_SubProblems->{$SubProblemType}{$SubLocation};
                }
            }
        }
        
        # checking object type
        my $ObjTId1 = $CompleteSignature{1}{$Symbol}{"Class"};
        my $ObjTId2 = $CompleteSignature{2}{$PSymbol}{"Class"};
        if($ObjTId1 and $ObjTId2
        and not $CompleteSignature{1}{$Symbol}{"Static"})
        {
            my $ThisPtr1_Id = getTypeIdByName($TypeInfo{1}{$ObjTId1}{"Name"}."*const", 1);
            my $ThisPtr2_Id = getTypeIdByName($TypeInfo{2}{$ObjTId2}{"Name"}."*const", 2);
            if($ThisPtr1_Id and $ThisPtr2_Id)
            {
                @RecurTypes = ();
                my $Sub_SubProblems = mergeTypes($ThisPtr1_Id, $ThisPtr2_Id, $Level);
                foreach my $SubProblemType (keys(%{$Sub_SubProblems}))
                {
                    foreach my $SubLocation (keys(%{$Sub_SubProblems->{$SubProblemType}}))
                    {
                        my $NewLocation = ($SubLocation)?"this->".$SubLocation:"this";
                        $CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation} = $Sub_SubProblems->{$SubProblemType}{$SubLocation};
                    }
                }
            }
        }
    }
    if($Level eq "Binary") {
        mergeVTables($Level);
    }
    foreach my $Symbol (keys(%{$CompatProblems{$Level}})) {
        $CheckedSymbols{$Level}{$Symbol} = 1;
    }
}

sub rmQuals($$)
{
    my ($Value, $Qual) = @_;
    if(not $Qual) {
        return $Value;
    }
    if($Qual eq "all")
    { # all quals
        $Qual = "const|volatile|restrict";
    }
    while($Value=~s/\b$Qual\b//) {
        $Value = formatName($Value, "T");
    }
    return $Value;
}

sub cmpBTypes($$$$)
{
    my ($T1, $T2, $V1, $V2) = @_;
    $T1 = uncover_typedefs($T1, $V1);
    $T2 = uncover_typedefs($T2, $V2);
    return (rmQuals($T1, "all") eq rmQuals($T2, "all"));
}

sub addedQual($$$)
{
    my ($Old_Value, $New_Value, $Qual) = @_;
    return removedQual_I($New_Value, $Old_Value, 2, 1, $Qual);
}

sub removedQual($$$)
{
    my ($Old_Value, $New_Value, $Qual) = @_;
    return removedQual_I($Old_Value, $New_Value, 1, 2, $Qual);
}

sub removedQual_I($$$$$)
{
    my ($Old_Value, $New_Value, $V1, $V2, $Qual) = @_;
    $Old_Value = uncover_typedefs($Old_Value, $V1);
    $New_Value = uncover_typedefs($New_Value, $V2);
    
    if($Old_Value eq $New_Value)
    { # equal types
        return 0;
    }
    if($Old_Value!~/\b$Qual\b/)
    { # without a qual
        return 0;
    }
    elsif($New_Value!~/\b$Qual\b/)
    { # became non-qual
        return 1;
    }
    else
    {
        my @BQ1 = getQualModel($Old_Value, $Qual);
        my @BQ2 = getQualModel($New_Value, $Qual);
        foreach (0 .. $#BQ1)
        { # removed qual
            if($BQ1[$_]==1
            and $BQ2[$_]!=1)
            {
                return 2;
            }
        }
    }
    return 0;
}

sub getQualModel($$)
{
    my ($Value, $Qual) = @_;
    if(not $Qual) {
        return $Value;
    }
    
    # cleaning
    while($Value=~/(\w+)/)
    {
        my $W = $1;
        
        if($W eq $Qual) {
            $Value=~s/\b$W\b/\@/g;
        }
        else {
            $Value=~s/\b$W\b//g;
        }
    }
    
    $Value=~s/\@/$Qual/g;
    $Value=~s/[^\*\&\w]+//g;
    
    # modeling
    # int*const*const == 011
    # int**const == 001
    my @Model = ();
    my @Elems = split(/[\*\&]/, $Value);
    if(not @Elems) {
        return (0);
    }
    foreach (@Elems)
    {
        if($_ eq $Qual) {
            push(@Model, 1);
        }
        else {
            push(@Model, 0);
        }
    }
    
    return @Model;
}

my %StringTypes = map {$_=>1} (
    "char*",
    "char const*"
);

my %CharTypes = map {$_=>1} (
    "char",
    "char const"
);

sub showVal($$$)
{
    my ($Value, $TypeId, $LibVersion) = @_;
    my %PureType = get_PureType($TypeId, $TypeInfo{$LibVersion});
    my $TName = uncover_typedefs($PureType{"Name"}, $LibVersion);
    if(substr($Value, 0, 2) eq "_Z")
    {
        if(my $Unmangled = $tr_name{$Value}) {
            return $Unmangled;
        }
    }
    elsif(defined $StringTypes{$TName} or $TName=~/string/i)
    { # strings
        return "\"$Value\"";
    }
    elsif(defined $CharTypes{$TName})
    { # characters
        return "\'$Value\'";
    }
    if($Value eq "")
    { # other
        return "\'\'";
    }
    return $Value;
}

sub getRegs($$$)
{
    my ($LibVersion, $Symbol, $Pos) = @_;
    
    if(defined $CompleteSignature{$LibVersion}{$Symbol}{"Reg"})
    {
        my %Regs = ();
        foreach my $Elem (sort keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Reg"}}))
        {
            if($Elem=~/\A$Pos([\.\+]|\Z)/) {
                $Regs{$CompleteSignature{$LibVersion}{$Symbol}{"Reg"}{$Elem}} = 1;
            }
        }
        
        return join(", ", sort keys(%Regs));
    }
    elsif(defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"}
    and defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{0}
    and not defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{0}{"offset"})
    {
        return "unknown";
    }
    
    return undef;
}

sub mergeParameters($$$$$$)
{
    my ($Symbol, $PSymbol, $ParamPos1, $ParamPos2, $Level, $ChkRnmd) = @_;
    if(not $Symbol) {
        return;
    }
    my $PType1_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"type"};
    my $PName1 = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"name"};
    my $PType2_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"type"};
    my $PName2 = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"name"};
    if(not $PType1_Id
    or not $PType2_Id) {
        return;
    }
    
    if($Symbol=~/\A(_Z|\?)/) 
    { # do not merge "this" 
        if($PName1 eq "this" or $PName2 eq "this") { 
            return; 
        } 
    }
    
    my %Type1 = get_Type($PType1_Id, 1);
    my %Type2 = get_Type($PType2_Id, 2);
    
    my %PureType1 = get_PureType($PType1_Id, $TypeInfo{1});
    
    my %BaseType1 = get_BaseType($PType1_Id, 1);
    my %BaseType2 = get_BaseType($PType2_Id, 2);
    
    my $Parameter_Location = ($PName1)?$PName1:showPos($ParamPos1)." Parameter";
    
    if($Level eq "Binary")
    {
        if(checkDump(1, "2.6.1") and checkDump(2, "2.6.1"))
        { # "reg" attribute added in ACC 1.95.1 (dump 2.6.1 format)
            if($CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
            and not $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Non_Register"}{$Parameter_Location}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1)  );
            }
            elsif(not $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
            and $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Register"}{$Parameter_Location}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1)  );
            }
        }
        
        if(defined $UsedDump{1}{"DWARF"}
        and defined $UsedDump{2}{"DWARF"})
        {
            if(checkDump(1, "3.0") and checkDump(2, "3.0"))
            {
                my $Old_Regs = getRegs(1, $Symbol, $ParamPos1);
                my $New_Regs = getRegs(2, $PSymbol, $ParamPos2);
                
                if($Old_Regs ne "unknown"
                and $New_Regs ne "unknown")
                {
                    if($Old_Regs and $New_Regs)
                    {
                        if($Old_Regs ne $New_Regs)
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Changed_Register"}{$Parameter_Location}}=(
                                "Target"=>$PName1,
                                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                                "Old_Value"=>$Old_Regs,
                                "New_Value"=>$New_Regs  );
                        }
                    }
                    elsif($Old_Regs and not $New_Regs)
                    {
                        %{$CompatProblems{$Level}{$Symbol}{"Parameter_From_Register"}{$Parameter_Location}}=(
                            "Target"=>$PName1,
                            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                            "Old_Value"=>$Old_Regs  );
                    }
                    elsif(not $Old_Regs and $New_Regs)
                    {
                        %{$CompatProblems{$Level}{$Symbol}{"Parameter_To_Register"}{$Parameter_Location}}=(
                            "Target"=>$PName1,
                            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                            "New_Value"=>$New_Regs  );
                    }
                }
                
                if((my $Old_Offset = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"offset"}) ne ""
                and (my $New_Offset = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"offset"}) ne "")
                {
                    if($Old_Offset ne $New_Offset)
                    {
                        my $Start1 = $CompleteSignature{1}{$Symbol}{"Param"}{0}{"offset"};
                        my $Start2 = $CompleteSignature{2}{$Symbol}{"Param"}{0}{"offset"};
                        
                        $Old_Offset = $Old_Offset - $Start1;
                        $New_Offset = $New_Offset - $Start2;
                        
                        if($Old_Offset ne $New_Offset)
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Changed_Offset"}{$Parameter_Location}}=(
                                "Target"=>$PName1,
                                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                                "Old_Value"=>$Old_Offset,
                                "New_Value"=>$New_Offset  );
                        }
                    }
                }
            }
        }
    }
    if(checkDump(1, "2.0") and checkDump(2, "2.0")
    and $UsedDump{1}{"V"} ne "3.1" and $UsedDump{2}{"V"} ne "3.1")
    { # "default" attribute added in ACC 1.22 (dump 2.0 format)
      # broken in 3.1, fixed in 3.2
        my $Value_Old = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"default"};
        my $Value_New = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"default"};
        if(not checkDump(1, "2.13")
        and checkDump(2, "2.13"))
        { # support for old ABI dumps
            if(defined $Value_Old and defined $Value_New)
            {
                if($PureType1{"Name"} eq "bool"
                and $Value_Old eq "false" and $Value_New eq "0")
                { # int class::method ( bool p = 0 );
                  # old ABI dumps: "false"
                  # new ABI dumps: "0"
                    $Value_Old = "0";
                }
            }
        }
        if(not checkDump(1, "2.18")
        and checkDump(2, "2.18"))
        { # support for old ABI dumps
            if(not defined $Value_Old
            and substr($Value_New, 0, 2) eq "_Z") {
                $Value_Old = $Value_New;
            }
        }
        if(defined $Value_Old)
        {
            $Value_Old = showVal($Value_Old, $PType1_Id, 1);
            if(defined $Value_New)
            {
                $Value_New = showVal($Value_New, $PType2_Id, 2);
                if($Value_Old ne $Value_New)
                { # FIXME: how to distinguish "0" and 0 (NULL)
                    %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Changed"}{$Parameter_Location}}=(
                        "Target"=>$PName1,
                        "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                        "Old_Value"=>$Value_Old,
                        "New_Value"=>$Value_New  );
                }
            }
            else
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Removed"}{$Parameter_Location}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                    "Old_Value"=>$Value_Old  );
            }
        }
        elsif(defined $Value_New)
        {
            $Value_New = showVal($Value_New, $PType2_Id, 2);
            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Added"}{$Parameter_Location}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                "New_Value"=>$Value_New  );
        }
    }
    
    if($ChkRnmd)
    {
        if($PName1 and $PName2 and $PName1 ne $PName2
        and $PType1_Id!=-1 and $PType2_Id!=-1
        and $PName1!~/\Ap\d+\Z/ and $PName2!~/\Ap\d+\Z/)
        { # except unnamed "..." value list (Id=-1)
            %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos1)." Parameter"}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                "Param_Type"=>$TypeInfo{1}{$PType1_Id}{"Name"},
                "Old_Value"=>$PName1,
                "New_Value"=>$PName2,
                "New_Signature"=>get_Signature($Symbol, 2)  );
        }
    }
    
    # checking type change (replace)
    my %SubProblems = detectTypeChange($PType1_Id, $PType2_Id, "Parameter", $Level);
    
    foreach my $SubProblemType (keys(%SubProblems))
    { # add new problems, remove false alarms
        my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
        my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
        
        # quals
        if($SubProblemType eq "Parameter_Type"
        or $SubProblemType eq "Parameter_Type_And_Size"
        or $SubProblemType eq "Parameter_Type_Format")
        {
            if(checkDump(1, "2.6") and checkDump(2, "2.6"))
            {
                if(addedQual($Old_Value, $New_Value, "restrict")) {
                    %{$SubProblems{"Parameter_Became_Restrict"}} = %{$SubProblems{$SubProblemType}};
                }
                elsif(removedQual($Old_Value, $New_Value, "restrict")) {
                    %{$SubProblems{"Parameter_Became_Non_Restrict"}} = %{$SubProblems{$SubProblemType}};
                }
            }
            if(checkDump(1, "2.6") and checkDump(2, "2.6"))
            {
                if(removedQual($Old_Value, $New_Value, "volatile")) {
                    %{$SubProblems{"Parameter_Became_Non_Volatile"}} = %{$SubProblems{$SubProblemType}};
                }
            }
            if($Type2{"Type"} eq "Const" and $BaseType2{"Name"} eq $Type1{"Name"}
            and $Type1{"Type"}=~/Intrinsic|Class|Struct|Union|Enum/)
            { # int to "int const"
                delete($SubProblems{$SubProblemType});
            }
            elsif($Type1{"Type"} eq "Const" and $BaseType1{"Name"} eq $Type2{"Name"}
            and $Type2{"Type"}=~/Intrinsic|Class|Struct|Union|Enum/)
            { # "int const" to int
                delete($SubProblems{$SubProblemType});
            }
            elsif(my $RR = removedQual($Old_Value, $New_Value, "const"))
            { # "const" to non-"const"
                if($RR==2) {
                    %{$SubProblems{"Parameter_Removed_Const"}} = %{$SubProblems{$SubProblemType}};
                }
                else {
                    %{$SubProblems{"Parameter_Became_Non_Const"}} = %{$SubProblems{$SubProblemType}};
                }
            }
        }
    }
    
    if($Level eq "Source")
    {
        foreach my $SubProblemType (keys(%SubProblems))
        {
            my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
            my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
            
            if($SubProblemType eq "Parameter_Type")
            {
                if(cmpBTypes($Old_Value, $New_Value, 1, 2)) {
                    delete($SubProblems{$SubProblemType});
                }
            }
        }
    }
    
    foreach my $SubProblemType (keys(%SubProblems))
    { # modify/register problems
        my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
        my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
        my $New_Size = $SubProblems{$SubProblemType}{"New_Size"};
        my $Old_Size = $SubProblems{$SubProblemType}{"Old_Size"};
        
        my $NewProblemType = $SubProblemType;
        if($Old_Value eq "..." and $New_Value ne "...")
        { # change from "..." to "int"
            if($ParamPos1==0)
            { # ISO C requires a named argument before "..."
                next;
            }
            $NewProblemType = "Parameter_Became_Non_VaList";
        }
        elsif($New_Value eq "..." and $Old_Value ne "...")
        { # change from "int" to "..."
            if($ParamPos2==0)
            { # ISO C requires a named argument before "..."
                next;
            }
            $NewProblemType = "Parameter_Became_VaList";
        }
        elsif($Level eq "Binary" and ($SubProblemType eq "Parameter_Type_And_Size"
        or $SubProblemType eq "Parameter_Type" or $SubProblemType eq "Parameter_Type_Format"))
        {
            my ($Arch1, $Arch2) = (getArch(1), getArch(2));
            if($Arch1 eq "unknown"
            or $Arch2 eq "unknown")
            { # if one of the architectures is unknown
              # then set other arhitecture to unknown too
                ($Arch1, $Arch2) = ("unknown", "unknown");
            }
            my (%Conv1, %Conv2) = ();
            if($UseConv_Real{1}{"P"} and $UseConv_Real{2}{"P"})
            { # real
                %Conv1 = callingConvention_P_Real($CompleteSignature{1}{$Symbol}, $ParamPos1);
                %Conv2 = callingConvention_P_Real($CompleteSignature{2}{$Symbol}, $ParamPos2);
            }
            else
            { # model
                %Conv1 = callingConvention_P_Model($CompleteSignature{1}{$Symbol}, $ParamPos1, $TypeInfo{1}, $Arch1, $OStarget, $WORD_SIZE{1});
                %Conv2 = callingConvention_P_Model($CompleteSignature{2}{$Symbol}, $ParamPos2, $TypeInfo{2}, $Arch2, $OStarget, $WORD_SIZE{2});
            }
            if($Conv1{"Method"} eq $Conv2{"Method"})
            {
                if($Conv1{"Method"} eq "stack")
                {
                    if($Old_Size ne $New_Size) { # FIXME: isMemPadded, getOffset
                        $NewProblemType = "Parameter_Type_And_Stack";
                    }
                }
                elsif($Conv1{"Method"} eq "reg")
                {
                    if($Conv1{"Registers"} ne $Conv2{"Registers"}) {
                        $NewProblemType = "Parameter_Type_And_Register";
                    }
                }
            }
            elsif($Conv1{"Method"} ne "unknown"
            and $Conv2{"Method"} ne "unknown")
            {
                if($Conv1{"Method"} eq "stack") {
                    $NewProblemType = "Parameter_Type_From_Stack_To_Register";
                }
                elsif($Conv1{"Method"} eq "register") {
                    $NewProblemType = "Parameter_Type_From_Register_To_Stack";
                }
            }
            $SubProblems{$SubProblemType}{"Old_Reg"} = $Conv1{"Registers"};
            $SubProblems{$SubProblemType}{"New_Reg"} = $Conv2{"Registers"};
        }
        %{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$Parameter_Location}}=(
            "Target"=>$PName1,
            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
            "New_Signature"=>get_Signature($Symbol, 2) );
        @{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$Parameter_Location}}{keys(%{$SubProblems{$SubProblemType}})} = values %{$SubProblems{$SubProblemType}};
    }
    
    @RecurTypes = ();
    
    # checking type definition changes
    my $Sub_SubProblems = mergeTypes($PType1_Id, $PType2_Id, $Level);
    foreach my $SubProblemType (keys(%{$Sub_SubProblems}))
    {
        foreach my $SubLocation (keys(%{$Sub_SubProblems->{$SubProblemType}}))
        {
            my $NewProblemType = $SubProblemType;
            if($SubProblemType eq "DataType_Size")
            {
                if($PureType1{"Type"}!~/\A(Pointer|Ref)\Z/ and $SubLocation!~/\-\>/)
                { # stack has been affected
                    $NewProblemType = "DataType_Size_And_Stack";
                }
            }
            my $NewLocation = ($SubLocation)?$Parameter_Location."->".$SubLocation:$Parameter_Location;
            $CompatProblems{$Level}{$Symbol}{$NewProblemType}{$NewLocation} = $Sub_SubProblems->{$SubProblemType}{$SubLocation};
        }
    }
}

sub find_ParamPair_Pos_byName($$$)
{
    my ($Name, $Symbol, $LibVersion) = @_;
    foreach my $ParamPos (sort {int($a)<=>int($b)} keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
    {
        next if(not defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$ParamPos});
        if($CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$ParamPos}{"name"} eq $Name)
        {
            return $ParamPos;
        }
    }
    return "lost";
}

sub find_ParamPair_Pos_byTypeAndPos($$$$$)
{
    my ($TypeName, $MediumPos, $Order, $Symbol, $LibVersion) = @_;
    my @Positions = ();
    foreach my $ParamPos (sort {int($a)<=>int($b)} keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
    {
        next if($Order eq "backward" and $ParamPos>$MediumPos);
        next if($Order eq "forward" and $ParamPos<$MediumPos);
        next if(not defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$ParamPos});
        my $PTypeId = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$ParamPos}{"type"};
        if($TypeInfo{$LibVersion}{$PTypeId}{"Name"} eq $TypeName) {
            push(@Positions, $ParamPos);
        }
    }
    return @Positions;
}

sub getTypeIdByName($$)
{
    my ($TypeName, $LibVersion) = @_;
    return $TName_Tid{$LibVersion}{formatName($TypeName, "T")};
}

sub diffTypes($$$)
{
    if(defined $Cache{"diffTypes"}{$_[2]}{$_[0]}{$_[1]}) {
        return $Cache{"diffTypes"}{$_[2]}{$_[0]}{$_[1]};
    }
    if(isRecurType($_[0], $_[1], \@RecurTypes_Diff))
    { # skip recursive declarations
        return 0;
    }
    
    pushType($_[0], $_[1], \@RecurTypes_Diff);
    my $Diff = diffTypes_I(@_);
    pop(@RecurTypes_Diff);
    
    return ($Cache{"diffTypes"}{$_[2]}{$_[0]}{$_[1]} = $Diff);
}

sub diffTypes_I($$$)
{
    my ($Type1_Id, $Type2_Id, $Level) = @_;
    
    my %Type1_Pure = get_PureType($Type1_Id, $TypeInfo{1});
    my %Type2_Pure = get_PureType($Type2_Id, $TypeInfo{2});
    
    if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"})
    { # equal types
        return 0;
    }
    if($Type1_Pure{"Name"} eq "void")
    { # from void* to something
        return 0;
    }
    if($Type1_Pure{"Name"}=~/\*/
    or $Type2_Pure{"Name"}=~/\*/)
    { # compared in detectTypeChange()
        return 0;
    }
    
    my %FloatType = map {$_=>1} (
        "float",
        "double",
        "long double"
    );
    
    my $T1 = $Type1_Pure{"Type"};
    my $T2 = $Type2_Pure{"Type"};
    
    if($T1 eq "Struct"
    and $T2 eq "Class")
    { # compare as data structures
        $T2 = "Struct";
    }
    
    if($T1 eq "Class"
    and $T2 eq "Struct")
    { # compare as data structures
        $T1 = "Struct";
    }
    
    if($T1 ne $T2)
    { # different types
        if($T1 eq "Intrinsic"
        and $T2 eq "Enum")
        { # "int" to "enum"
            return 0;
        }
        elsif($T2 eq "Intrinsic"
        and $T1 eq "Enum")
        { # "enum" to "int"
            return 0;
        }
        else
        { # union to struct
          #  ...
            return 1;
        }
    }
    else
    {
        if($T1 eq "Intrinsic")
        {
            if($FloatType{$Type1_Pure{"Name"}}
            or $FloatType{$Type2_Pure{"Name"}})
            { # "float" to "double"
              # "float" to "int"
                if($Level eq "Source")
                { # Safe
                    return 0;
                }
                else {
                    return 1;
                }
            }
        }
        elsif($T1=~/Class|Struct|Union|Enum/)
        {
            my @Membs1 = keys(%{$Type1_Pure{"Memb"}});
            my @Membs2 = keys(%{$Type2_Pure{"Memb"}});
            if(not @Membs1
            or not @Membs2)
            { # private
                return 0;
            }
            if($#Membs1!=$#Membs2)
            { # different number of elements
                return 1;
            }
            if($T1 eq "Enum")
            {
                foreach my $Pos (@Membs1)
                { # compare elements by name and value
                    if($Type1_Pure{"Memb"}{$Pos}{"name"} ne $Type2_Pure{"Memb"}{$Pos}{"name"}
                    or $Type1_Pure{"Memb"}{$Pos}{"value"} ne $Type2_Pure{"Memb"}{$Pos}{"value"})
                    { # different names
                        return 1;
                    }
                }
            }
            else
            {
                foreach my $Pos (@Membs1)
                {
                    if($Level eq "Source")
                    {
                        if($Type1_Pure{"Memb"}{$Pos}{"name"} ne $Type2_Pure{"Memb"}{$Pos}{"name"})
                        { # different names
                            return 1;
                        }
                    }
                    
                    my %MT1 = %{$TypeInfo{1}{$Type1_Pure{"Memb"}{$Pos}{"type"}}};
                    my %MT2 = %{$TypeInfo{2}{$Type2_Pure{"Memb"}{$Pos}{"type"}}};
                    
                    if($MT1{"Name"} ne $MT2{"Name"}
                    or isAnon($MT1{"Name"}) or isAnon($MT2{"Name"}))
                    {
                        my $PL1 = get_PLevel($MT1{"Tid"}, 1);
                        my $PL2 = get_PLevel($MT2{"Tid"}, 2);
                        
                        if($PL1 ne $PL2)
                        { # different pointer level
                            return 1;
                        }
                        
                        # compare base types
                        my %BT1 = get_BaseType($MT1{"Tid"}, 1);
                        my %BT2 = get_BaseType($MT2{"Tid"}, 2);
                        
                        if(diffTypes($BT1{"Tid"}, $BT2{"Tid"}, $Level))
                        { # different types
                            return 1;
                        }
                    }
                }
            }
        }
        else
        {
            # TODO: arrays, etc.
        }
    }
    return 0;
}

sub detectTypeChange($$$$)
{
    my ($Type1_Id, $Type2_Id, $Prefix, $Level) = @_;
    if(not $Type1_Id or not $Type2_Id) {
        return ();
    }
    my %LocalProblems = ();
    my %Type1 = get_Type($Type1_Id, 1);
    my %Type2 = get_Type($Type2_Id, 2);
    my %Type1_Pure = get_PureType($Type1_Id, $TypeInfo{1});
    my %Type2_Pure = get_PureType($Type2_Id, $TypeInfo{2});
    
    my %Type1_Base = ($Type1_Pure{"Type"} eq "Array")?get_OneStep_BaseType($Type1_Pure{"Tid"}, $TypeInfo{1}):get_BaseType($Type1_Id, 1);
    my %Type2_Base = ($Type2_Pure{"Type"} eq "Array")?get_OneStep_BaseType($Type2_Pure{"Tid"}, $TypeInfo{2}):get_BaseType($Type2_Id, 2);
    
    if(defined $UsedDump{1}{"DWARF"})
    {
        if($Type1_Pure{"Name"} eq "__unknown__"
        or $Type2_Pure{"Name"} eq "__unknown__"
        or $Type1_Base{"Name"} eq "__unknown__"
        or $Type2_Base{"Name"} eq "__unknown__")
        { # Error ABI dump
            return ();
        }
    }
    
    my $Type1_PLevel = get_PLevel($Type1_Id, 1);
    my $Type2_PLevel = get_PLevel($Type2_Id, 2);
    return () if(not $Type1{"Name"} or not $Type2{"Name"});
    return () if(not $Type1_Base{"Name"} or not $Type2_Base{"Name"});
    return () if($Type1_PLevel eq "" or $Type2_PLevel eq "");
    if($Type1_Base{"Name"} ne $Type2_Base{"Name"}
    and ($Type1{"Name"} eq $Type2{"Name"} or ($Type1_PLevel>=1 and $Type1_PLevel==$Type2_PLevel
    and $Type1_Base{"Name"} ne "void" and $Type2_Base{"Name"} ne "void")))
    { # base type change
        if($Type1{"Name"} eq $Type2{"Name"})
        {
            if($Type1{"Type"} eq "Typedef" and $Type2{"Type"} eq "Typedef")
            { # will be reported in mergeTypes() as typedef problem
                return ();
            }
            my %Typedef_1 = goToFirst($Type1{"Tid"}, 1, "Typedef");
            my %Typedef_2 = goToFirst($Type2{"Tid"}, 2, "Typedef");
            if(%Typedef_1 and %Typedef_2)
            {
                if($Typedef_1{"Name"} eq $Typedef_2{"Name"}
                and $Typedef_1{"Type"} eq "Typedef" and $Typedef_2{"Type"} eq "Typedef")
                { # const Typedef
                    return ();
                }
            }
        }
        if($Type1_Base{"Name"}!~/anon\-/ and $Type2_Base{"Name"}!~/anon\-/)
        {
            if($Level eq "Binary"
            and $Type1_Base{"Size"} and $Type2_Base{"Size"}
            and $Type1_Base{"Size"} ne $Type2_Base{"Size"})
            {
                %{$LocalProblems{$Prefix."_BaseType_And_Size"}}=(
                    "Old_Value"=>$Type1_Base{"Name"},
                    "New_Value"=>$Type2_Base{"Name"},
                    "Old_Size"=>$Type1_Base{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2_Base{"Size"}*$BYTE_SIZE);
            }
            else
            {
                if(diffTypes($Type1_Base{"Tid"}, $Type2_Base{"Tid"}, $Level))
                { # format change
                    %{$LocalProblems{$Prefix."_BaseType_Format"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "Old_Size"=>$Type1_Base{"Size"}*$BYTE_SIZE,
                        "New_Size"=>$Type2_Base{"Size"}*$BYTE_SIZE);
                }
                elsif(tNameLock($Type1_Base{"Tid"}, $Type2_Base{"Tid"}))
                {
                    %{$LocalProblems{$Prefix."_BaseType"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "Old_Size"=>$Type1_Base{"Size"}*$BYTE_SIZE,
                        "New_Size"=>$Type2_Base{"Size"}*$BYTE_SIZE);
                }
            }
        }
    }
    elsif($Type1{"Name"} ne $Type2{"Name"})
    { # type change
        if($Type1{"Name"}!~/anon\-/ and $Type2{"Name"}!~/anon\-/)
        {
            if($Prefix eq "Return"
            and $Type1_Pure{"Name"} eq "void")
            {
                %{$LocalProblems{"Return_Type_From_Void"}}=(
                    "New_Value"=>$Type2{"Name"},
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE);
            }
            elsif($Prefix eq "Return"
            and $Type2_Pure{"Name"} eq "void")
            {
                %{$LocalProblems{"Return_Type_Became_Void"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE);
            }
            else
            {
                if($Level eq "Binary"
                and $Type1{"Size"} and $Type2{"Size"}
                and $Type1{"Size"} ne $Type2{"Size"})
                {
                    %{$LocalProblems{$Prefix."_Type_And_Size"}}=(
                        "Old_Value"=>$Type1{"Name"},
                        "New_Value"=>$Type2{"Name"},
                        "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                        "New_Size"=>$Type2{"Size"}*$BYTE_SIZE);
                }
                else
                {
                    if(diffTypes($Type1_Id, $Type2_Id, $Level))
                    { # format change
                        %{$LocalProblems{$Prefix."_Type_Format"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                            "New_Size"=>$Type2{"Size"}*$BYTE_SIZE);
                    }
                    elsif(tNameLock($Type1_Id, $Type2_Id))
                    { # FIXME: correct this condition
                        %{$LocalProblems{$Prefix."_Type"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                            "New_Size"=>$Type2{"Size"}*$BYTE_SIZE);
                    }
                }
            }
        }
    }
    if($Type1_PLevel!=$Type2_PLevel)
    {
        if($Type1{"Name"} ne "void" and $Type1{"Name"} ne "..."
        and $Type2{"Name"} ne "void" and $Type2{"Name"} ne "...")
        {
            if($Level eq "Source")
            {
                %{$LocalProblems{$Prefix."_PointerLevel"}}=(
                    "Old_Value"=>$Type1_PLevel,
                    "New_Value"=>$Type2_PLevel);
            }
            else
            {
                if($Type2_PLevel>$Type1_PLevel)
                {
                    %{$LocalProblems{$Prefix."_PointerLevel_Increased"}}=(
                        "Old_Value"=>$Type1_PLevel,
                        "New_Value"=>$Type2_PLevel);
                }
                else
                {
                    %{$LocalProblems{$Prefix."_PointerLevel_Decreased"}}=(
                        "Old_Value"=>$Type1_PLevel,
                        "New_Value"=>$Type2_PLevel);
                }
            }
        }
    }
    if($Type1_Pure{"Type"} eq "Array"
    and $Type1_Pure{"BaseType"})
    { # base_type[N] -> base_type[N]
      # base_type: older_structure -> typedef to newer_structure
        my %SubProblems = detectTypeChange($Type1_Base{"Tid"}, $Type2_Base{"Tid"}, $Prefix, $Level);
        foreach my $SubProblemType (keys(%SubProblems))
        {
            $SubProblemType=~s/_Type/_BaseType/g;
            next if(defined $LocalProblems{$SubProblemType});
            foreach my $Attr (keys(%{$SubProblems{$SubProblemType}})) {
                $LocalProblems{$SubProblemType}{$Attr} = $SubProblems{$SubProblemType}{$Attr};
            }
        }
    }
    return %LocalProblems;
}

sub tNameLock($$)
{
    my ($Tid1, $Tid2) = @_;
    my $Changed = 0;
    if(differentDumps("G"))
    { # different GCC versions
        $Changed = 1;
    }
    elsif(differentDumps("V"))
    { # different versions of ABI dumps
        if(not checkDump(1, "2.20")
        or not checkDump(2, "2.20"))
        { # latest names update
          # 2.6: added restrict qualifier
          # 2.13: added missed typedefs to qualified types
          # 2.20: prefix for struct, union and enum types
            $Changed = 1;
        }
    }
    
    my $TN1 = $TypeInfo{1}{$Tid1}{"Name"};
    my $TN2 = $TypeInfo{2}{$Tid2}{"Name"};
    
    my $TT1 = $TypeInfo{1}{$Tid1}{"Type"};
    my $TT2 = $TypeInfo{2}{$Tid2}{"Type"};
    
    if($Changed)
    { # different formats
        my %Base1 = get_Type($Tid1, 1);
        while(defined $Base1{"Type"} and $Base1{"Type"} eq "Typedef") {
            %Base1 = get_OneStep_BaseType($Base1{"Tid"}, $TypeInfo{1});
        }
        my %Base2 = get_Type($Tid2, 2);
        while(defined $Base2{"Type"} and $Base2{"Type"} eq "Typedef") {
            %Base2 = get_OneStep_BaseType($Base2{"Tid"}, $TypeInfo{2});
        }
        my $BName1 = uncover_typedefs($Base1{"Name"}, 1);
        my $BName2 = uncover_typedefs($Base2{"Name"}, 2);
        if($BName1 eq $BName2)
        { # equal base types
            return 0;
        }
        
        if(not checkDump(1, "2.13")
        or not checkDump(2, "2.13"))
        { # broken array names in ABI dumps < 2.13
            if($TT1 eq "Array"
            and $TT2 eq "Array") {
                return 0;
            }
        }
        
        if(not checkDump(1, "2.6")
        or not checkDump(2, "2.6"))
        { # added restrict attribute in 2.6
            if($TN1!~/\brestrict\b/
            and $TN2=~/\brestrict\b/) {
                return 0;
            }
        }
        
        if(not checkDump(1, "2.20")
        or not checkDump(2, "2.20"))
        { # added type prefix in 2.20
            if($TN1=~/\A(struct|union|enum) \Q$TN2\E\Z/
            or $TN2=~/\A(struct|union|enum) \Q$TN1\E\Z/) {
                return 0;
            }
        }
    }
    else
    {
        # typedef struct {...} type_t
        # typedef struct type_t {...} type_t
        if(index($TN1, " ".$TN2)!=-1)
        {
            if($TN1=~/\A(struct|union|enum) \Q$TN2\E\Z/) {
                return 0;
            }
        }
        if(index($TN2, " ".$TN1)!=-1)
        {
            if($TN2=~/\A(struct|union|enum) \Q$TN1\E\Z/) {
                return 0;
            }
        }
        
        if($TT1 eq "FuncPtr"
        and $TT2 eq "FuncPtr")
        {
            my $TN1_C = $TN1;
            my $TN2_C = $TN2;
            
            $TN1_C=~s/\b(struct|union) //g;
            $TN2_C=~s/\b(struct|union) //g;
            
            if($TN1_C eq $TN2_C) {
                return 0;
            }
        }
    }
    
    my ($N1, $N2) = ($TN1, $TN2);
    $N1=~s/\b(struct|union) //g;
    $N2=~s/\b(struct|union) //g;

    if($N1 eq $N2)
    { # QList<struct QUrl> and QList<QUrl>
        return 0;
    }
    
    return 1;
}

sub differentDumps($)
{
    my $Check = $_[0];
    if(defined $Cache{"differentDumps"}{$Check}) {
        return $Cache{"differentDumps"}{$Check};
    }
    if($UsedDump{1}{"V"} and $UsedDump{2}{"V"})
    {
        if($Check eq "G")
        {
            if(getGccVersion(1) ne getGccVersion(2))
            { # different GCC versions
                return ($Cache{"differentDumps"}{$Check}=1);
            }
        }
        if($Check eq "V")
        {
            if(cmpVersions(formatVersion($UsedDump{1}{"V"}, 2),
            formatVersion($UsedDump{2}{"V"}, 2))!=0)
            { # different dump versions (skip micro version)
                return ($Cache{"differentDumps"}{$Check}=1);
            }
        }
    }
    return ($Cache{"differentDumps"}{$Check}=0);
}

sub formatVersion($$)
{ # cut off version digits
    my ($V, $Digits) = @_;
    my @Elems = split(/\./, $V);
    return join(".", splice(@Elems, 0, $Digits));
} 

sub htmlSpecChars($)
{
    my $Str = $_[0];
    if(not $Str) {
        return $Str;
    }
    $Str=~s/\&([^#]|\Z)/&amp;$1/g;
    $Str=~s/</&lt;/g;
    $Str=~s/\-\>/&#45;&gt;/g; # &minus;
    $Str=~s/>/&gt;/g;
    $Str=~s/([^ ]) ([^ ])/$1\@SP\@$2/g;
    $Str=~s/([^ ]) ([^ ])/$1\@SP\@$2/g;
    $Str=~s/ /&#160;/g; # &nbsp;
    $Str=~s/\@SP\@/ /g;
    $Str=~s/\n/<br\/>/g;
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    return $Str;
}

sub xmlSpecChars($)
{
    my $Str = $_[0];
    if(not $Str) {
        return $Str;
    }
    
    $Str=~s/\&([^#]|\Z)/&amp;$1/g;
    $Str=~s/</&lt;/g;
    $Str=~s/>/&gt;/g;
    
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    
    return $Str;
}

sub xmlSpecChars_R($)
{
    my $Str = $_[0];
    if(not $Str) {
        return $Str;
    }
    
    $Str=~s/&amp;/&/g;
    $Str=~s/&lt;/</g;
    $Str=~s/&gt;/>/g;
    
    $Str=~s/&quot;/"/g;
    $Str=~s/&#39;/'/g;
    
    return $Str;
}

sub black_name($)
{
    my $Name = $_[0];
    return "<span class='iname_b'>".highLight_Signature($Name)."</span>";
}

sub highLight_Signature($)
{
    my $Signature = $_[0];
    return highLight_Signature_PPos_Italic($Signature, "", 0, 0, 0);
}

sub highLight_Signature_Italic_Color($)
{
    my $Signature = $_[0];
    return highLight_Signature_PPos_Italic($Signature, "", 1, 1, 1);
}

sub separate_symbol($)
{
    my $Symbol = $_[0];
    my ($Name, $Spec, $Ver) = ($Symbol, "", "");
    if($Symbol=~/\A([^\@\$\?]+)([\@\$]+)([^\@\$]+)\Z/) {
        ($Name, $Spec, $Ver) = ($1, $2, $3);
    }
    return ($Name, $Spec, $Ver);
}

sub cut_f_attrs($)
{
    if($_[0]=~s/(\))((| (const volatile|const|volatile))(| \[static\]))\Z/$1/) {
        return $2;
    }
    return "";
}

sub highLight_Signature_PPos_Italic($$$$$)
{
    my ($FullSignature, $Param_Pos, $ItalicParams, $ColorParams, $ShowReturn) = @_;
    $Param_Pos = "" if(not defined $Param_Pos);
    my ($Signature, $VersionSpec, $SymbolVersion) = separate_symbol($FullSignature);
    my $Return = "";
    if($ShowRetVal and $Signature=~s/([^:]):([^:].+?)\Z/$1/g) {
        $Return = $2;
    }
    my $SCenter = find_center($Signature, "(");
    if(not $SCenter)
    { # global data
        $Signature = htmlSpecChars($Signature);
        $Signature=~s!(\[data\])!<span class='attr'>$1</span>!g;
        $Signature .= (($SymbolVersion)?"<span class='sym_ver'>&#160;$VersionSpec&#160;$SymbolVersion</span>":"");
        if($Return and $ShowReturn) {
            $Signature .= "<span class='sym_p nowrap'> &#160;<b>:</b>&#160;&#160;".htmlSpecChars($Return)."</span>";
        }
        return $Signature;
    }
    my ($Begin, $End) = (substr($Signature, 0, $SCenter), "");
    $Begin.=" " if($Begin!~/ \Z/);
    $End = cut_f_attrs($Signature);
    my @Parts = ();
    my ($Short, $Params) = split_Signature($Signature);
    my @SParts = separate_Params($Params, 1, 1);
    foreach my $Pos (0 .. $#SParts)
    {
        my $Part = $SParts[$Pos];
        $Part=~s/\A\s+|\s+\Z//g;
        my ($Part_Styled, $ParamName) = (htmlSpecChars($Part), "");
        if($Part=~/\([\*]+(\w+)\)/i) {
            $ParamName = $1;#func-ptr
        }
        elsif($Part=~/(\w+)[\,\)]*\Z/i) {
            $ParamName = $1;
        }
        if(not $ParamName)
        {
            push(@Parts, $Part_Styled);
            next;
        }
        if($ItalicParams and not $TName_Tid{1}{$Part}
        and not $TName_Tid{2}{$Part})
        {
            my $Style = "<i>$ParamName</i>";
            
            if($Param_Pos ne ""
            and $Pos==$Param_Pos) {
                $Style = "<span class=\'fp\'>$ParamName</span>";
            }
            elsif($ColorParams) {
                $Style = "<span class=\'color_p\'>$ParamName</span>";
            }
            
            $Part_Styled=~s!(\W)$ParamName([\,\)]|\Z)!$1$Style$2!ig;
        }
        $Part_Styled=~s/,(\w)/, $1/g;
        push(@Parts, $Part_Styled);
    }
    if(@Parts)
    {
        foreach my $Num (0 .. $#Parts)
        {
            if($Num==$#Parts)
            { # add ")" to the last parameter
                $Parts[$Num] = "<span class='nowrap'>".$Parts[$Num]." )</span>";
            }
            elsif(length($Parts[$Num])<=45) {
                $Parts[$Num] = "<span class='nowrap'>".$Parts[$Num]."</span>";
            }
        }
        $Signature = htmlSpecChars($Begin)."<span class='sym_p'>(&#160;".join(" ", @Parts)."</span>".$End;
    }
    else {
        $Signature = htmlSpecChars($Begin)."<span class='sym_p'>(&#160;)</span>".$End;
    }
    if($Return and $ShowReturn) {
        $Signature .= "<span class='sym_p nowrap'> &#160;<b>:</b>&#160;&#160;".htmlSpecChars($Return)."</span>";
    }
    $Signature=~s!\[\]![&#160;]!g;
    $Signature=~s!operator=!operator&#160;=!g;
    $Signature=~s!(\[in-charge\]|\[not-in-charge\]|\[in-charge-deleting\]|\[static\])!<span class='attr'>$1</span>!g;
    if($SymbolVersion) {
        $Signature .= "<span class='sym_ver'>&#160;$VersionSpec&#160;$SymbolVersion</span>";
    }
    return $Signature;
}

sub split_Signature($)
{
    my $Signature = $_[0];
    if(my $ShortName = substr($Signature, 0, find_center($Signature, "(")))
    {
        $Signature=~s/\A\Q$ShortName\E\(//g;
        cut_f_attrs($Signature);
        $Signature=~s/\)\Z//;
        return ($ShortName, $Signature);
    }
    
    # error
    return ($Signature, "");
}

sub separate_Params($$$)
{
    my ($Params, $Comma, $Sp) = @_;
    my @Parts = ();
    my %B = ( "("=>0, "<"=>0, ")"=>0, ">"=>0 );
    my $Part = 0;
    foreach my $Pos (0 .. length($Params) - 1)
    {
        my $S = substr($Params, $Pos, 1);
        if(defined $B{$S}) {
            $B{$S} += 1;
        }
        if($S eq "," and
        $B{"("}==$B{")"} and $B{"<"}==$B{">"})
        {
            if($Comma)
            { # include comma
                $Parts[$Part] .= $S;
            }
            $Part += 1;
        }
        else {
            $Parts[$Part] .= $S;
        }
    }
    if(not $Sp)
    { # remove spaces
        foreach (@Parts)
        {
            s/\A //g;
            s/ \Z//g;
        }
    }
    return @Parts;
}

sub find_center($$)
{
    my ($Sign, $Target) = @_;
    my %B = ( "("=>0, "<"=>0, ")"=>0, ">"=>0 );
    my $Center = 0;
    if($Sign=~s/(operator([^\w\s\(\)]+|\(\)))//g)
    { # operators
        $Center+=length($1);
    }
    foreach my $Pos (0 .. length($Sign)-1)
    {
        my $S = substr($Sign, $Pos, 1);
        if($S eq $Target)
        {
            if($B{"("}==$B{")"}
            and $B{"<"}==$B{">"}) {
                return $Center;
            }
        }
        if(defined $B{$S}) {
            $B{$S}+=1;
        }
        $Center+=1;
    }
    return 0;
}

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">>", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open(FILE, $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    if($Path!~/\.(tu|class|abi)\Z/) {
        $Content=~s/\r/\n/g;
    }
    return $Content;
}

sub get_filename($)
{ # much faster than basename() from File::Basename module
    if(defined $Cache{"get_filename"}{$_[0]}) {
        return $Cache{"get_filename"}{$_[0]};
    }
    if($_[0] and $_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return ($Cache{"get_filename"}{$_[0]}=$1);
    }
    return ($Cache{"get_filename"}{$_[0]}="");
}

sub get_dirname($)
{ # much faster than dirname() from File::Basename module
    if(defined $Cache{"get_dirname"}{$_[0]}) {
        return $Cache{"get_dirname"}{$_[0]};
    }
    if($_[0] and $_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return ($Cache{"get_dirname"}{$_[0]}=$1);
    }
    return ($Cache{"get_dirname"}{$_[0]}="");
}

sub separate_path($) {
    return (get_dirname($_[0]), get_filename($_[0]));
}

sub esc($)
{
    my $Str = $_[0];
    $Str=~s/([()\[\]{}$ &'"`;,<>\+])/\\$1/g;
    return $Str;
}

sub readLineNum($$)
{
    my ($Path, $Num) = @_;
    return "" if(not $Path or not -f $Path);
    open(FILE, $Path);
    foreach (1 ... $Num) {
        <FILE>;
    }
    my $Line = <FILE>;
    close(FILE);
    return $Line;
}

sub readAttributes($$)
{
    my ($Path, $Num) = @_;
    return () if(not $Path or not -f $Path);
    my %Attributes = ();
    if(readLineNum($Path, $Num)=~/<!--\s+(.+)\s+-->/)
    {
        foreach my $AttrVal (split(/;/, $1))
        {
            if($AttrVal=~/(.+):(.+)/)
            {
                my ($Name, $Value) = ($1, $2);
                $Attributes{$Name} = $Value;
            }
        }
    }
    return \%Attributes;
}

sub is_abs($) {
    return ($_[0]=~/\A(\/|\w+:[\/\\])/);
}

sub get_abs_path($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them
    my $Path = $_[0];
    if(not is_abs($Path)) {
        $Path = abs_path($Path);
    }
    return $Path;
}

sub get_OSgroup()
{
    my $N = $Config{"osname"};
    if($N=~/macos|darwin|rhapsody/i) {
        return "macos";
    }
    elsif($N=~/freebsd|openbsd|netbsd/i) {
        return "bsd";
    }
    elsif($N=~/haiku|beos/i) {
        return "beos";
    }
    elsif($N=~/symbian|epoc/i) {
        return "symbian";
    }
    elsif($N=~/win/i) {
        return "windows";
    }
    else {
        return $N;
    }
}

sub getGccVersion($)
{
    my $LibVersion = $_[0];
    if($GCC_VERSION{$LibVersion})
    { # dump version
        return $GCC_VERSION{$LibVersion};
    }
    elsif($UsedDump{$LibVersion}{"V"})
    { # old-version dumps
        return "unknown";
    }
    my $GccVersion = get_dumpversion($GCC_PATH); # host version
    if(not $GccVersion) {
        return "unknown";
    }
    return $GccVersion;
}

sub showArch($)
{
    my $Arch = $_[0];
    if($Arch eq "arm"
    or $Arch eq "mips") {
        return uc($Arch);
    }
    return $Arch;
}

sub getArch($)
{
    my $LibVersion = $_[0];
    
    if($TargetArch) {
        return $TargetArch;
    }
    elsif($CPU_ARCH{$LibVersion})
    { # dump
        return $CPU_ARCH{$LibVersion};
    }
    elsif($UsedDump{$LibVersion}{"V"})
    { # old-version dumps
        return "unknown";
    }
    
    return getArch_GCC($LibVersion);
}

sub get_Report_Title($)
{
    my $Level = $_[0];
    
    my $ArchInfo = " on <span style='color:Blue;'>".showArch(getArch(1))."</span>";
    if(getArch(1) ne getArch(2)
    or getArch(1) eq "unknown"
    or $Level eq "Source")
    { # don't show architecture in the header
        $ArchInfo="";
    }
    my $Title = "";
    if($Level eq "Source") {
        $Title .= "Source compatibility";
    }
    elsif($Level eq "Binary") {
        $Title .= "Binary compatibility";
    }
    else {
        $Title .= "API compatibility";
    }
    
    my $V1 = $Descriptor{1}{"Version"};
    my $V2 = $Descriptor{2}{"Version"};
    
    if($UsedDump{1}{"DWARF"} and $UsedDump{2}{"DWARF"})
    {
        my $M1 = $UsedDump{1}{"M"};
        my $M2 = $UsedDump{2}{"M"};
        
        my $M1S = $M1;
        my $M2S = $M2;
        
        $M1S=~s/(\.so|\.ko)\..+/$1/ig;
        $M2S=~s/(\.so|\.ko)\..+/$1/ig;
        
        if($M1S eq $M2S
        and $V1 ne "X" and $V2 ne "Y")
        {
            $Title .= " report for the <span style='color:Blue;'>$M1S</span> $TargetComponent";
            $Title .= " between <span style='color:Red;'>".$V1."</span> and <span style='color:Red;'>".$V2."</span> versions";
        }
        else
        {
            $Title .= " report between <span style='color:Blue;'>$M1</span> (<span style='color:Red;'>".$V1."</span>)";
            $Title .= " and <span style='color:Blue;'>$M2</span> (<span style='color:Red;'>".$V2."</span>) objects";
        }
    }
    else
    {
        $Title .= " report for the <span style='color:Blue;'>$TargetTitle</span> $TargetComponent";
        $Title .= " between <span style='color:Red;'>".$V1."</span> and <span style='color:Red;'>".$V2."</span> versions";
    }
    
    $Title .= $ArchInfo;
    
    if($AppPath) {
        $Title .= " (relating to the portability of application <span style='color:Blue;'>".get_filename($AppPath)."</span>)";
    }
    $Title = "<h1>".$Title."</h1>\n";
    return $Title;
}

sub get_CheckedHeaders($)
{
    my $LibVersion = $_[0];
    
    my @Headers = ();
    
    foreach my $Path (keys(%{$Registered_Headers{$LibVersion}}))
    {
        my $File = get_filename($Path);
        
        if(not is_target_header($File, $LibVersion)) {
            next;
        }
        
        if(skipHeader($File, $LibVersion)) {
            next;
        }
        
        push(@Headers, $Path);
    }
    
    return @Headers;
}

sub get_SourceInfo()
{
    my ($CheckedHeaders, $CheckedSources, $CheckedLibs) = ("", "");
    
    if(my @Headers = get_CheckedHeaders(1))
    {
        $CheckedHeaders = "<a name='Headers'></a><h2>Header Files <span class='gray'>&nbsp;".($#Headers+1)."&nbsp;</span></h2><hr/>\n";
        $CheckedHeaders .= "<div class='h_list'>\n";
        foreach my $Header_Path (sort {lc($Registered_Headers{1}{$a}{"Identity"}) cmp lc($Registered_Headers{1}{$b}{"Identity"})} @Headers)
        {
            my $Identity = $Registered_Headers{1}{$Header_Path}{"Identity"};
            my $Name = get_filename($Identity);
            my $Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
            $CheckedHeaders .= $Name.$Comment."<br/>\n";
        }
        $CheckedHeaders .= "</div>\n";
        $CheckedHeaders .= "<br/>$TOP_REF<br/>\n";
    }
    
    if(my @Sources = keys(%{$Registered_Sources{1}}))
    {
        $CheckedSources = "<a name='Sources'></a><h2>Source Files <span class='gray'>&nbsp;".($#Sources+1)."&nbsp;</span></h2><hr/>\n";
        $CheckedSources .= "<div class='h_list'>\n";
        foreach my $Header_Path (sort {lc($Registered_Sources{1}{$a}{"Identity"}) cmp lc($Registered_Sources{1}{$b}{"Identity"})} @Sources)
        {
            my $Identity = $Registered_Sources{1}{$Header_Path}{"Identity"};
            my $Name = get_filename($Identity);
            my $Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
            $CheckedSources .= $Name.$Comment."<br/>\n";
        }
        $CheckedSources .= "</div>\n";
        $CheckedSources .= "<br/>$TOP_REF<br/>\n";
    }
    
    if(not $CheckHeadersOnly)
    {
        $CheckedLibs = "<a name='Libs'></a><h2>".get_ObjTitle()." <span class='gray'>&nbsp;".keys(%{$Library_Symbol{1}})."&nbsp;</span></h2><hr/>\n";
        $CheckedLibs .= "<div class='lib_list'>\n";
        foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$Library_Symbol{1}}))
        {
            # $Library .= " (.$LIB_EXT)" if($Library!~/\.\w+\Z/);
            $CheckedLibs .= $Library."<br/>\n";
        }
        $CheckedLibs .= "</div>\n";
        $CheckedLibs .= "<br/>$TOP_REF<br/>\n";
    }
    
    return $CheckedHeaders.$CheckedSources.$CheckedLibs;
}

sub get_ObjTitle()
{
    if(defined $UsedDump{1}{"DWARF"}) {
        return "Objects";
    }
    else {
        return ucfirst($SLIB_TYPE)." Libraries";
    }
}

sub get_TypeProblems_Count($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $Type_Problems_Count = 0;
    
    foreach my $Type_Name (sort keys(%{$TypeChanges{$Level}}))
    {
        my %Kinds_Target = ();
        foreach my $Kind (keys(%{$TypeChanges{$Level}{$Type_Name}}))
        {
            foreach my $Location (keys(%{$TypeChanges{$Level}{$Type_Name}{$Kind}}))
            {
                my $Target = $TypeChanges{$Level}{$Type_Name}{$Kind}{$Location}{"Target"};
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                
                if($Severity ne $TargetSeverity) {
                    next;
                }
                
                if($Kinds_Target{$Kind}{$Target}) {
                    next;
                }
                
                $Kinds_Target{$Kind}{$Target} = 1;
                $Type_Problems_Count += 1;
            }
        }
    }
    return $Type_Problems_Count;
}

sub get_Summary($)
{
    my $Level = $_[0];
    my ($Added, $Removed, $I_Problems_High, $I_Problems_Medium, $I_Problems_Low, $T_Problems_High,
    $C_Problems_Low, $T_Problems_Medium, $T_Problems_Low, $I_Other, $T_Other, $C_Other) = (0,0,0,0,0,0,0,0,0,0,0,0);
    %{$RESULT{$Level}} = (
        "Problems"=>0,
        "Warnings"=>0,
        "Affected"=>0 );
    # check rules
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if(not defined $CompatRules{$Level}{$Kind})
            { # unknown rule
                if(not $UnknownRules{$Level}{$Kind})
                { # only one warning
                    printMsg("WARNING", "unknown rule \"$Kind\" (\"$Level\")");
                    $UnknownRules{$Level}{$Kind}=1;
                }
                delete($CompatProblems{$Level}{$Interface}{$Kind});
            }
        }
    }
    foreach my $Constant (sort keys(%{$CompatProblems_Constants{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems_Constants{$Level}{$Constant}}))
        {
            if(not defined $CompatRules{$Level}{$Kind})
            { # unknown rule
                if(not $UnknownRules{$Level}{$Kind})
                { # only one warning
                    printMsg("WARNING", "unknown rule \"$Kind\" (\"$Level\")");
                    $UnknownRules{$Level}{$Kind}=1;
                }
                delete($CompatProblems_Constants{$Level}{$Constant}{$Kind});
            }
        }
    }
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols")
            {
                foreach my $Location (sort keys(%{$CompatProblems{$Level}{$Interface}{$Kind}}))
                {
                    my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                    if($Kind eq "Added_Symbol") {
                        $Added += 1;
                    }
                    elsif($Kind eq "Removed_Symbol")
                    {
                        $Removed += 1;
                        $TotalAffected{$Level}{$Interface} = $Severity;
                    }
                    else
                    {
                        if($Severity eq "Safe") {
                            $I_Other += 1;
                        }
                        elsif($Severity eq "High") {
                            $I_Problems_High += 1;
                        }
                        elsif($Severity eq "Medium") {
                            $I_Problems_Medium += 1;
                        }
                        elsif($Severity eq "Low") {
                            $I_Problems_Low += 1;
                        }
                        if(($Severity ne "Low" or $StrictCompat)
                        and $Severity ne "Safe") {
                            $TotalAffected{$Level}{$Interface} = $Severity;
                        }
                    }
                }
            }
        }
    }
    
    my %MethodTypeIndex = ();
    
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        my @Kinds = sort keys(%{$CompatProblems{$Level}{$Interface}});
        foreach my $Kind (@Kinds)
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
            {
                my @Locs = sort {cmpLocations($b, $a)} sort keys(%{$CompatProblems{$Level}{$Interface}{$Kind}});
                foreach my $Location (@Locs)
                {
                    my $Type_Name = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Name"};
                    my $Target = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Target"};
                    
                    if(defined $MethodTypeIndex{$Interface}{$Type_Name}{$Kind}{$Target})
                    { # one location for one type and target
                        next;
                    }
                    $MethodTypeIndex{$Interface}{$Type_Name}{$Kind}{$Target} = 1;
                    $TypeChanges{$Level}{$Type_Name}{$Kind}{$Location} = $CompatProblems{$Level}{$Interface}{$Kind}{$Location};
                    
                    my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                    
                    if(($Severity ne "Low" or $StrictCompat)
                    and $Severity ne "Safe")
                    {
                        if(my $Sev = $TotalAffected{$Level}{$Interface})
                        {
                            if($Severity_Val{$Severity}>$Severity_Val{$Sev}) {
                                $TotalAffected{$Level}{$Interface} = $Severity;
                            }
                        }
                        else {
                            $TotalAffected{$Level}{$Interface} = $Severity;
                        }
                    }
                }
            }
        }
    }
    
    $T_Problems_High = get_TypeProblems_Count("High", $Level);
    $T_Problems_Medium = get_TypeProblems_Count("Medium", $Level);
    $T_Problems_Low = get_TypeProblems_Count("Low", $Level);
    $T_Other = get_TypeProblems_Count("Safe", $Level);
    
    # changed and removed public symbols
    my $SCount = keys(%{$CheckedSymbols{$Level}});
    if($ExtendedCheck)
    { # don't count external_func_0 for constants
        $SCount-=1;
    }
    if($SCount)
    {
        my %Weight = (
            "High" => 100,
            "Medium" => 50,
            "Low" => 25
        );
        foreach (keys(%{$TotalAffected{$Level}})) {
            $RESULT{$Level}{"Affected"}+=$Weight{$TotalAffected{$Level}{$_}};
        }
        $RESULT{$Level}{"Affected"} = $RESULT{$Level}{"Affected"}/$SCount;
    }
    else {
        $RESULT{$Level}{"Affected"} = 0;
    }
    
    $RESULT{$Level}{"Affected"} = show_number($RESULT{$Level}{"Affected"});
    if($RESULT{$Level}{"Affected"}>=100) {
        $RESULT{$Level}{"Affected"} = 100;
    }
    
    $RESULT{$Level}{"Problems"} += $Removed;
    $RESULT{$Level}{"Problems"} += $T_Problems_High + $I_Problems_High;
    $RESULT{$Level}{"Problems"} += $T_Problems_Medium + $I_Problems_Medium;
    if($StrictCompat) {
        $RESULT{$Level}{"Problems"} += $T_Problems_Low + $I_Problems_Low;
    }
    else {
        $RESULT{$Level}{"Warnings"} += $T_Problems_Low + $I_Problems_Low;
    }
    
    foreach my $Constant (keys(%{$CompatProblems_Constants{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems_Constants{$Level}{$Constant}}))
        {
            my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
            if($Severity eq "Safe")
            {
                $C_Other+=1;
            }
            elsif($Severity eq "Low")
            {
                $C_Problems_Low+=1;
            }
        }
    }
    
    if($C_Problems_Low)
    {
        if($StrictCompat) {
            $RESULT{$Level}{"Problems"} += $C_Problems_Low;
        }
        else {
            $RESULT{$Level}{"Warnings"} += $C_Problems_Low;
        }
    }
    if($RESULT{$Level}{"Problems"}
    and $RESULT{$Level}{"Affected"}) {
        $RESULT{$Level}{"Verdict"} = "incompatible";
    }
    else {
        $RESULT{$Level}{"Verdict"} = "compatible";
    }
    
    my $TotalTypes = keys(%{$CheckedTypes{$Level}});
    if(not $TotalTypes)
    { # list all the types
        $TotalTypes = keys(%{$TName_Tid{1}});
    }
    
    my ($Arch1, $Arch2) = (getArch(1), getArch(2));
    my ($GccV1, $GccV2) = (getGccVersion(1), getGccVersion(2));
    
    my ($TestInfo, $TestResults, $Problem_Summary) = ();
    
    if($ReportFormat eq "xml")
    { # XML
        # test info
        $TestInfo .= "  <library>$TargetLibraryName</library>\n";
        $TestInfo .= "  <version1>\n";
        $TestInfo .= "    <number>".$Descriptor{1}{"Version"}."</number>\n";
        $TestInfo .= "    <arch>$Arch1</arch>\n";
        $TestInfo .= "    <gcc>$GccV1</gcc>\n";
        $TestInfo .= "  </version1>\n";
        
        $TestInfo .= "  <version2>\n";
        $TestInfo .= "    <number>".$Descriptor{2}{"Version"}."</number>\n";
        $TestInfo .= "    <arch>$Arch2</arch>\n";
        $TestInfo .= "    <gcc>$GccV2</gcc>\n";
        $TestInfo .= "  </version2>\n";
        $TestInfo = "<test_info>\n".$TestInfo."</test_info>\n\n";
        
        # test results
        if(my @Headers = keys(%{$Registered_Headers{1}}))
        {
            $TestResults .= "  <headers>\n";
            foreach my $Name (sort {lc($Registered_Headers{1}{$a}{"Identity"}) cmp lc($Registered_Headers{1}{$b}{"Identity"})} @Headers)
            {
                my $Identity = $Registered_Headers{1}{$Name}{"Identity"};
                my $Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
                $TestResults .= "    <name>".get_filename($Name).$Comment."</name>\n";
            }
            $TestResults .= "  </headers>\n";
        }
        
        if(my @Sources = keys(%{$Registered_Sources{1}}))
        {
            $TestResults .= "  <sources>\n";
            foreach my $Name (sort {lc($Registered_Sources{1}{$a}{"Identity"}) cmp lc($Registered_Sources{1}{$b}{"Identity"})} @Sources)
            {
                my $Identity = $Registered_Sources{1}{$Name}{"Identity"};
                my $Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
                $TestResults .= "    <name>".get_filename($Name).$Comment."</name>\n";
            }
            $TestResults .= "  </sources>\n";
        }
        
        $TestResults .= "  <libs>\n";
        foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$Library_Symbol{1}}))
        {
            # $Library .= " (.$LIB_EXT)" if($Library!~/\.\w+\Z/);
            $TestResults .= "    <name>$Library</name>\n";
        }
        $TestResults .= "  </libs>\n";
        
        $TestResults .= "  <symbols>".(keys(%{$CheckedSymbols{$Level}}) - keys(%ExtendedSymbols))."</symbols>\n";
        $TestResults .= "  <types>".$TotalTypes."</types>\n";
        
        $TestResults .= "  <verdict>".$RESULT{$Level}{"Verdict"}."</verdict>\n";
        $TestResults .= "  <affected>".$RESULT{$Level}{"Affected"}."</affected>\n";
        $TestResults = "<test_results>\n".$TestResults."</test_results>\n\n";
        
        # problem summary
        $Problem_Summary .= "  <added_symbols>".$Added."</added_symbols>\n";
        $Problem_Summary .= "  <removed_symbols>".$Removed."</removed_symbols>\n";
        
        $Problem_Summary .= "  <problems_with_types>\n";
        $Problem_Summary .= "    <high>$T_Problems_High</high>\n";
        $Problem_Summary .= "    <medium>$T_Problems_Medium</medium>\n";
        $Problem_Summary .= "    <low>$T_Problems_Low</low>\n";
        $Problem_Summary .= "    <safe>$T_Other</safe>\n";
        $Problem_Summary .= "  </problems_with_types>\n";
        
        $Problem_Summary .= "  <problems_with_symbols>\n";
        $Problem_Summary .= "    <high>$I_Problems_High</high>\n";
        $Problem_Summary .= "    <medium>$I_Problems_Medium</medium>\n";
        $Problem_Summary .= "    <low>$I_Problems_Low</low>\n";
        $Problem_Summary .= "    <safe>$I_Other</safe>\n";
        $Problem_Summary .= "  </problems_with_symbols>\n";
        
        $Problem_Summary .= "  <problems_with_constants>\n";
        $Problem_Summary .= "    <low>$C_Problems_Low</low>\n";
        $Problem_Summary .= "  </problems_with_constants>\n";
        
        $Problem_Summary = "<problem_summary>\n".$Problem_Summary."</problem_summary>\n\n";
        
        return ($TestInfo.$TestResults.$Problem_Summary, "");
    }
    else
    { # HTML
        # test info
        $TestInfo = "<h2>Test Info</h2><hr/>\n";
        $TestInfo .= "<table class='summary'>\n";
        
        if($TargetComponent eq "library") { 
            $TestInfo .= "<tr><th>Library Name</th><td>$TargetTitle</td></tr>\n";
        }
        else {
            $TestInfo .= "<tr><th>Module Name</th><td>$TargetTitle</td></tr>\n";
        }
        
        my (@VInf1, @VInf2, $AddTestInfo) = ();
        if($Arch1 ne "unknown"
        and $Arch2 ne "unknown")
        { # CPU arch
            if($Arch1 eq $Arch2)
            { # go to the separate section
                $AddTestInfo .= "<tr><th>CPU Type</th><td>".showArch($Arch1)."</td></tr>\n";
            }
            else
            { # go to the version number
                push(@VInf1, showArch($Arch1));
                push(@VInf2, showArch($Arch2));
            }
        }
        if($GccV1 ne "unknown"
        and $GccV2 ne "unknown"
        and $OStarget ne "windows")
        { # GCC version
            if($GccV1 eq $GccV2)
            { # go to the separate section
                $AddTestInfo .= "<tr><th>GCC Version</th><td>$GccV1</td></tr>\n";
            }
            else
            { # go to the version number
                push(@VInf1, "gcc ".$GccV1);
                push(@VInf2, "gcc ".$GccV2);
            }
        }
        # show long version names with GCC version and CPU architecture name (if different)
        $TestInfo .= "<tr><th>Version #1</th><td>".$Descriptor{1}{"Version"}.(@VInf1?" (".join(", ", reverse(@VInf1)).")":"")."</td></tr>\n";
        $TestInfo .= "<tr><th>Version #2</th><td>".$Descriptor{2}{"Version"}.(@VInf2?" (".join(", ", reverse(@VInf2)).")":"")."</td></tr>\n";
        $TestInfo .= $AddTestInfo;
        #if($COMMON_LANGUAGE{1}) {
        #    $TestInfo .= "<tr><th>Language</th><td>".$COMMON_LANGUAGE{1}."</td></tr>\n";
        #}
        if($ExtendedCheck) {
            $TestInfo .= "<tr><th>Mode</th><td>Extended</td></tr>\n";
        }
        if($JoinReport)
        {
            if($Level eq "Binary") {
                $TestInfo .= "<tr><th>Subject</th><td width='150px'>Binary Compatibility</td></tr>\n"; # Run-time
            }
            if($Level eq "Source") {
                $TestInfo .= "<tr><th>Subject</th><td width='150px'>Source Compatibility</td></tr>\n"; # Build-time
            }
        }
        $TestInfo .= "</table>\n";
        
        # test results
        $TestResults = "<h2>Test Results</h2><hr/>\n";
        $TestResults .= "<table class='summary'>";
        
        if(my @Headers = get_CheckedHeaders(1))
        {
            my $Headers_Link = "<a href='#Headers' style='color:Blue;'>".($#Headers + 1)."</a>";
            $TestResults .= "<tr><th>Total Header Files</th><td>".$Headers_Link."</td></tr>\n";
        }
        
        if(my @Sources = keys(%{$Registered_Sources{1}}))
        {
            my $Src_Link = "<a href='#Sources' style='color:Blue;'>".($#Sources + 1)."</a>";
            $TestResults .= "<tr><th>Total Source Files</th><td>".$Src_Link."</td></tr>\n";
        }
        
        if(not $ExtendedCheck)
        {
            my $Libs_Link = "0";
            $Libs_Link = "<a href='#Libs' style='color:Blue;'>".keys(%{$Library_Symbol{1}})."</a>" if(keys(%{$Library_Symbol{1}})>0);
            $TestResults .= "<tr><th>Total ".get_ObjTitle()."</th><td>".($CheckHeadersOnly?"0&#160;(not&#160;analyzed)":$Libs_Link)."</td></tr>\n";
        }
        
        $TestResults .= "<tr><th>Total Symbols / Types</th><td>".(keys(%{$CheckedSymbols{$Level}}) - keys(%ExtendedSymbols))." / ".$TotalTypes."</td></tr>\n";
        
        my $META_DATA = "verdict:".$RESULT{$Level}{"Verdict"}.";";
        if($JoinReport) {
            $META_DATA = "kind:".lc($Level).";".$META_DATA;
        }
        
        my $BC_Rate = 100 - $RESULT{$Level}{"Affected"};
        
        $TestResults .= "<tr><th>Compatibility</th>\n";
        if($RESULT{$Level}{"Verdict"} eq "incompatible")
        {
            my $Cl = "incompatible";
            if($BC_Rate>=90) {
                $Cl = "warning";
            }
            elsif($BC_Rate>=80) {
                $Cl = "almost_compatible";
            }
            
            $TestResults .= "<td class=\'$Cl\'>".$BC_Rate."%</td>\n";
        }
        else {
            $TestResults .= "<td class=\'compatible\'>100%</td>\n";
        }
        $TestResults .= "</tr>\n";
        $TestResults .= "</table>\n";
        
        $META_DATA .= "affected:".$RESULT{$Level}{"Affected"}.";";# in percents
        # problem summary
        $Problem_Summary = "<h2>Problem Summary</h2><hr/>\n";
        $Problem_Summary .= "<table class='summary'>";
        $Problem_Summary .= "<tr><th></th><th style='text-align:center;'>Severity</th><th style='text-align:center;'>Count</th></tr>";
        
        my $Added_Link = "0";
        if($Added>0)
        {
            if($JoinReport) {
                $Added_Link = "<a href='#".$Level."_Added' style='color:Blue;'>$Added</a>";
            }
            else {
                $Added_Link = "<a href='#Added' style='color:Blue;'>$Added</a>";
            }
        }
        $META_DATA .= "added:$Added;";
        $Problem_Summary .= "<tr><th>Added Symbols</th><td>-</td><td".getStyle("I", "Added", $Added).">$Added_Link</td></tr>\n";
        
        my $Removed_Link = "0";
        if($Removed>0)
        {
            if($JoinReport) {
                $Removed_Link = "<a href='#".$Level."_Removed' style='color:Blue;'>$Removed</a>"
            }
            else {
                $Removed_Link = "<a href='#Removed' style='color:Blue;'>$Removed</a>"
            }
        }
        $META_DATA .= "removed:$Removed;";
        $Problem_Summary .= "<tr><th>Removed Symbols</th>";
        $Problem_Summary .= "<td>High</td><td".getStyle("I", "Removed", $Removed).">$Removed_Link</td></tr>\n";
        
        my $TH_Link = "0";
        $TH_Link = "<a href='#".get_Anchor("Type", $Level, "High")."' style='color:Blue;'>$T_Problems_High</a>" if($T_Problems_High>0);
        $META_DATA .= "type_problems_high:$T_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Data Types</th>";
        $Problem_Summary .= "<td>High</td><td".getStyle("T", "High", $T_Problems_High).">$TH_Link</td></tr>\n";
        
        my $TM_Link = "0";
        $TM_Link = "<a href='#".get_Anchor("Type", $Level, "Medium")."' style='color:Blue;'>$T_Problems_Medium</a>" if($T_Problems_Medium>0);
        $META_DATA .= "type_problems_medium:$T_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("T", "Medium", $T_Problems_Medium).">$TM_Link</td></tr>\n";
        
        my $TL_Link = "0";
        $TL_Link = "<a href='#".get_Anchor("Type", $Level, "Low")."' style='color:Blue;'>$T_Problems_Low</a>" if($T_Problems_Low>0);
        $META_DATA .= "type_problems_low:$T_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td".getStyle("T", "Low", $T_Problems_Low).">$TL_Link</td></tr>\n";
        
        my $IH_Link = "0";
        $IH_Link = "<a href='#".get_Anchor("Symbol", $Level, "High")."' style='color:Blue;'>$I_Problems_High</a>" if($I_Problems_High>0);
        $META_DATA .= "interface_problems_high:$I_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Symbols</th>";
        $Problem_Summary .= "<td>High</td><td".getStyle("I", "High", $I_Problems_High).">$IH_Link</td></tr>\n";
        
        my $IM_Link = "0";
        $IM_Link = "<a href='#".get_Anchor("Symbol", $Level, "Medium")."' style='color:Blue;'>$I_Problems_Medium</a>" if($I_Problems_Medium>0);
        $META_DATA .= "interface_problems_medium:$I_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("I", "Medium", $I_Problems_Medium).">$IM_Link</td></tr>\n";
        
        my $IL_Link = "0";
        $IL_Link = "<a href='#".get_Anchor("Symbol", $Level, "Low")."' style='color:Blue;'>$I_Problems_Low</a>" if($I_Problems_Low>0);
        $META_DATA .= "interface_problems_low:$I_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td".getStyle("I", "Low", $I_Problems_Low).">$IL_Link</td></tr>\n";
        
        my $ChangedConstants_Link = "0";
        if(keys(%{$CheckedSymbols{$Level}}) and $C_Problems_Low) {
            $ChangedConstants_Link = "<a href='#".get_Anchor("Constant", $Level, "Low")."' style='color:Blue;'>$C_Problems_Low</a>";
        }
        $META_DATA .= "changed_constants:$C_Problems_Low;";
        $Problem_Summary .= "<tr><th>Problems with<br/>Constants</th><td>Low</td><td".getStyle("C", "Low", $C_Problems_Low).">$ChangedConstants_Link</td></tr>\n";
        
        # Safe Changes
        if($T_Other)
        {
            my $TS_Link = "<a href='#".get_Anchor("Type", $Level, "Safe")."' style='color:Blue;'>$T_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Data Types</th><td>-</td><td".getStyle("T", "Safe", $T_Other).">$TS_Link</td></tr>\n";
            $META_DATA .= "type_changes_other:$T_Other;";
        }
        
        if($I_Other)
        {
            my $IS_Link = "<a href='#".get_Anchor("Symbol", $Level, "Safe")."' style='color:Blue;'>$I_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Symbols</th><td>-</td><td".getStyle("I", "Safe", $I_Other).">$IS_Link</td></tr>\n";
            $META_DATA .= "interface_changes_other:$I_Other;";
        }
        
        if($C_Other)
        {
            my $CS_Link = "<a href='#".get_Anchor("Constant", $Level, "Safe")."' style='color:Blue;'>$C_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Constants</th><td>-</td><td".getStyle("C", "Safe", $C_Other).">$CS_Link</td></tr>\n";
            $META_DATA .= "constant_changes_other:$C_Other;";
        }
        
        $META_DATA .= "tool_version:$TOOL_VERSION";
        $Problem_Summary .= "</table>\n";
        
        return ($TestInfo.$TestResults.$Problem_Summary, $META_DATA);
    }
}

sub getStyle($$$)
{
    my ($Subj, $Act, $Num) = @_;
    my %Style = (
        "Added"=>"new",
        "Removed"=>"failed",
        "Safe"=>"passed",
        "Low"=>"warning",
        "Medium"=>"failed",
        "High"=>"failed"
    );
    
    if($Num>0) {
        return " class='".$Style{$Act}."'";
    }
    
    return "";
}

sub show_number($)
{
    if($_[0])
    {
        my $Num = cut_off_number($_[0], 2, 0);
        if($Num eq "0")
        {
            foreach my $P (3 .. 7)
            {
                $Num = cut_off_number($_[0], $P, 1);
                if($Num ne "0") {
                    last;
                }
            }
        }
        if($Num eq "0") {
            $Num = $_[0];
        }
        return $Num;
    }
    return $_[0];
}

sub cut_off_number($$$)
{
    my ($num, $digs_to_cut, $z) = @_;
    if($num!~/\./)
    {
        $num .= ".";
        foreach (1 .. $digs_to_cut-1) {
            $num .= "0";
        }
    }
    elsif($num=~/\.(.+)\Z/ and length($1)<$digs_to_cut-1)
    {
        foreach (1 .. $digs_to_cut - 1 - length($1)) {
            $num .= "0";
        }
    }
    elsif($num=~/\d+\.(\d){$digs_to_cut,}/) {
      $num=sprintf("%.".($digs_to_cut-1)."f", $num);
    }
    $num=~s/\.[0]+\Z//g;
    if($z) {
        $num=~s/(\.[1-9]+)[0]+\Z/$1/g;
    }
    return $num;
}

sub get_Report_ChangedConstants($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $CHANGED_CONSTANTS = "";
    
    my %ReportMap = ();
    foreach my $Constant (keys(%{$CompatProblems_Constants{$Level}}))
    {
        my $Header = $Constants{1}{$Constant}{"Header"};
        if(not $Header)
        { # added
            $Header = $Constants{2}{$Constant}{"Header"}
        }
        
        foreach my $Kind (sort {lc($a) cmp lc($b)} keys(%{$CompatProblems_Constants{$Level}{$Constant}}))
        {
            if(not defined $CompatRules{$Level}{$Kind}) {
                next;
            }
            if($TargetSeverity ne $CompatRules{$Level}{$Kind}{"Severity"}) {
                next;
            }
            $ReportMap{$Header}{$Constant}{$Kind} = 1;
        }
    }
    
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $CHANGED_CONSTANTS .= "  <header name=\"$HeaderName\">\n";
            foreach my $Constant (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $CHANGED_CONSTANTS .= "    <constant name=\"$Constant\">\n";
                foreach my $Kind (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}{$Constant}}))
                {
                    my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                    my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                    my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"};
                    
                    $CHANGED_CONSTANTS .= "      <problem id=\"$Kind\">\n";
                    $CHANGED_CONSTANTS .= "        <change".getXmlParams($Change, $CompatProblems_Constants{$Level}{$Constant}{$Kind}).">$Change</change>\n";
                    $CHANGED_CONSTANTS .= "        <effect".getXmlParams($Effect, $CompatProblems_Constants{$Level}{$Constant}{$Kind}).">$Effect</effect>\n";
                    if($Overcome) {
                        $CHANGED_CONSTANTS .= "        <overcome".getXmlParams($Overcome, $CompatProblems_Constants{$Level}{$Constant}{$Kind}).">$Overcome</overcome>\n";
                    }
                    $CHANGED_CONSTANTS .= "      </problem>\n";
                }
                $CHANGED_CONSTANTS .= "    </constant>\n";
            }
            $CHANGED_CONSTANTS .= "    </header>\n";
        }
        $CHANGED_CONSTANTS = "<problems_with_constants severity=\"Low\">\n".$CHANGED_CONSTANTS."</problems_with_constants>\n\n";
    }
    else
    { # HTML
        my $ProblemsNum = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $CHANGED_CONSTANTS .= "<span class='h_name'>$HeaderName</span><br/>\n";
            foreach my $Constant (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                my $Report = "";
                
                foreach my $Kind (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}{$Constant}}))
                {
                    my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, $CompatProblems_Constants{$Level}{$Constant}{$Kind});
                    my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                    $Report .= "<tr>\n<th>1</th>\n<td>".$Change."</td>\n<td>$Effect</td>\n</tr>\n";
                    $ProblemsNum += 1;
                }
                if($Report)
                {
                    $Report = $ContentDivStart."<table class='ptable'>\n<tr>\n<th width='2%'></th>\n<th width='47%'>Change</th>\n<th>Effect</th>\n</tr>\n".$Report."</table>\n<br/>\n$ContentDivEnd\n";
                    $Report = $ContentSpanStart."<span class='ext'>[+]</span> ".$Constant.$ContentSpanEnd."<br/>\n".$Report;
                    $Report = insertIDs($Report);
                }
                $CHANGED_CONSTANTS .= $Report;
            }
            $CHANGED_CONSTANTS .= "<br/>\n";
        }
        if($CHANGED_CONSTANTS)
        {
            my $Title = "Problems with Constants, $TargetSeverity Severity";
            if($TargetSeverity eq "Safe")
            { # Safe Changes
                $Title = "Other Changes in Constants";
            }
            $CHANGED_CONSTANTS = "<a name='".get_Anchor("Constant", $Level, $TargetSeverity)."'></a><h2>$Title <span".getStyle("C", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$CHANGED_CONSTANTS.$TOP_REF."<br/>\n";
        }
    }
    return $CHANGED_CONSTANTS;
}

sub getTitle($$$)
{
    my ($Header, $Library, $NameSpace) = @_;
    my $Title = "";
    
    # if($Library and $Library!~/\.\w+\Z/) {
    #     $Library .= " (.$LIB_EXT)";
    # }
    
    if($Header and $Library)
    {
        $Title .= "<span class='h_name'>$Header</span>";
        $Title .= ", <span class='lib_name'>$Library</span><br/>\n";
    }
    elsif($Library) {
        $Title .= "<span class='lib_name'>$Library</span><br/>\n";
    }
    elsif($Header) {
        $Title .= "<span class='h_name'>$Header</span><br/>\n";
    }
    
    if($NameSpace) {
        $Title .= "<span class='ns'>namespace <b>$NameSpace</b></span><br/>\n";
    }
    
    return $Title;
}

sub get_Report_Added($)
{
    my $Level = $_[0];
    my $ADDED_INTERFACES = "";
    my %ReportMap = ();
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($Kind eq "Added_Symbol")
            {
                my $HeaderName = $CompleteSignature{2}{$Interface}{"Header"};
                my $DyLib = $Symbol_Library{2}{$Interface};
                if($Level eq "Source" and $ReportFormat eq "html")
                { # do not show library name in HTML report
                    $DyLib = "";
                }
                $ReportMap{$HeaderName}{$DyLib}{$Interface} = 1;
            }
        }
    }
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $ADDED_INTERFACES .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $ADDED_INTERFACES .= "    <library name=\"$DyLib\">\n";
                foreach my $Interface (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $ADDED_INTERFACES .= "      <name>$Interface</name>\n";
                }
                $ADDED_INTERFACES .= "    </library>\n";
            }
            $ADDED_INTERFACES .= "  </header>\n";
        }
        $ADDED_INTERFACES = "<added_symbols>\n".$ADDED_INTERFACES."</added_symbols>\n\n";
    }
    else
    { # HTML
        my $Added_Number = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                my %NameSpaceSymbols = ();
                foreach my $Interface (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $NameSpaceSymbols{select_Symbol_NS($Interface, 2)}{$Interface} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $ADDED_INTERFACES .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc(get_Signature($a, 2)) cmp lc(get_Signature($b, 2))} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Interface (@SortedInterfaces)
                    {
                        $Added_Number += 1;
                        my $Signature = get_Signature($Interface, 2);
                        if($NameSpace) {
                            $Signature=~s/\b\Q$NameSpace\E::\b//g;
                        }
                        if($Interface=~/\A(_Z|\?)/)
                        {
                            if($Signature) {
                                $ADDED_INTERFACES .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Interface</b>]</span>\n<br/>\n<br/>\n".$ContentDivEnd."\n");
                            }
                            else {
                                $ADDED_INTERFACES .= "<span class=\"iname\">".$Interface."</span><br/>\n";
                            }
                        }
                        else
                        {
                            if($Signature) {
                                $ADDED_INTERFACES .= "<span class=\"iname\">".highLight_Signature_Italic_Color($Signature)."</span><br/>\n";
                            }
                            else {
                                $ADDED_INTERFACES .= "<span class=\"iname\">".$Interface."</span><br/>\n";
                            }
                        }
                    }
                    $ADDED_INTERFACES .= "<br/>\n";
                }
            }
        }
        if($ADDED_INTERFACES)
        {
            my $Anchor = "<a name='Added'></a>";
            if($JoinReport) {
                $Anchor = "<a name='".$Level."_Added'></a>";
            }
            $ADDED_INTERFACES = $Anchor."<h2>Added Symbols <span".getStyle("I", "Added", $Added_Number).">&nbsp;$Added_Number&nbsp;</span></h2><hr/>\n".$ADDED_INTERFACES.$TOP_REF."<br/>\n";
        }
    }
    return $ADDED_INTERFACES;
}

sub get_Report_Removed($)
{
    my $Level = $_[0];
    my $REMOVED_INTERFACES = "";
    my %ReportMap = ();
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($Kind eq "Removed_Symbol")
            {
                my $HeaderName = $CompleteSignature{1}{$Symbol}{"Header"};
                my $DyLib = $Symbol_Library{1}{$Symbol};
                if($Level eq "Source" and $ReportFormat eq "html")
                { # do not show library name in HTML report
                    $DyLib = "";
                }
                $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
            }
        }
    }
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $REMOVED_INTERFACES .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $REMOVED_INTERFACES .= "    <library name=\"$DyLib\">\n";
                foreach my $Symbol (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $REMOVED_INTERFACES .= "      <name>$Symbol</name>\n";
                }
                $REMOVED_INTERFACES .= "    </library>\n";
            }
            $REMOVED_INTERFACES .= "  </header>\n";
        }
        $REMOVED_INTERFACES = "<removed_symbols>\n".$REMOVED_INTERFACES."</removed_symbols>\n\n";
    }
    else
    { # HTML
        my $Removed_Number = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                my %NameSpaceSymbols = ();
                foreach my $Interface (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $NameSpaceSymbols{select_Symbol_NS($Interface, 1)}{$Interface} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $REMOVED_INTERFACES .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc(get_Signature($a, 1)) cmp lc(get_Signature($b, 1))} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        $Removed_Number += 1;
                        my $SubReport = "";
                        my $Signature = get_Signature($Symbol, 1);
                        if($NameSpace) {
                            $Signature=~s/\b\Q$NameSpace\E::\b//g;
                        }
                        if($Symbol=~/\A(_Z|\?)/)
                        {
                            if($Signature) {
                                $REMOVED_INTERFACES .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Symbol</b>]</span>\n<br/>\n<br/>\n".$ContentDivEnd."\n");
                            }
                            else {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".$Symbol."</span><br/>\n";
                            }
                        }
                        else
                        {
                            if($Signature) {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".highLight_Signature_Italic_Color($Signature)."</span><br/>\n";
                            }
                            else {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".$Symbol."</span><br/>\n";
                            }
                        }
                    }
                }
                $REMOVED_INTERFACES .= "<br/>\n";
            }
        }
        if($REMOVED_INTERFACES)
        {
            my $Anchor = "<a name='Removed'></a><a name='Withdrawn'></a>";
            if($JoinReport) {
                $Anchor = "<a name='".$Level."_Removed'></a><a name='".$Level."_Withdrawn'></a>";
            }
            $REMOVED_INTERFACES = $Anchor."<h2>Removed Symbols <span".getStyle("I", "Removed", $Removed_Number).">&nbsp;$Removed_Number&nbsp;</span></h2><hr/>\n".$REMOVED_INTERFACES.$TOP_REF."<br/>\n";
        }
    }
    return $REMOVED_INTERFACES;
}

sub getXmlParams($$)
{
    my ($Content, $Problem) = @_;
    return "" if(not $Content or not $Problem);
    my %XMLparams = ();
    foreach my $Attr (sort {$b cmp $a} keys(%{$Problem}))
    {
        my $Macro = "\@".lc($Attr);
        if($Content=~/\Q$Macro\E/) {
            $XMLparams{lc($Attr)} = $Problem->{$Attr};
        }
    }
    my @PString = ();
    foreach my $P (sort {$b cmp $a} keys(%XMLparams)) {
        push(@PString, $P."=\"".xmlSpecChars($XMLparams{$P})."\"");
    }
    if(@PString) {
        return " ".join(" ", @PString);
    }
    else {
        return "";
    }
}

sub addMarkup($)
{
    my $Content = $_[0];
    # auto-markup
    $Content=~s/\n[ ]*//; # spaces
    $Content=~s!(\@\w+\s*\(\@\w+\))!<nowrap>$1</nowrap>!g; # @old_type (@old_size)
    $Content=~s!(... \(\w+\))!<nowrap><b>$1</b></nowrap>!g; # ... (va_list)
    $Content=~s!<nowrap>(.+?)</nowrap>!<span class='nowrap'>$1</span>!g;
    $Content=~s!([2-9]\))!<br/>$1!g; # 1), 2), ...
    if($Content=~/\ANOTE:/)
    { # notes
        $Content=~s!(NOTE):!<b>$1</b>:!g;
    }
    else {
        $Content=~s!(NOTE):!<br/><b>$1</b>:!g;
    }
    $Content=~s! (out)-! <b>$1</b>-!g; # out-parameters
    my @Keywords = (
        "void",
        "const",
        "static",
        "restrict",
        "volatile",
        "register",
        "virtual"
    );
    my $MKeys = join("|", @Keywords);
    foreach (@Keywords) {
        $MKeys .= "|non-".$_;
    }
    $Content=~s!(added\s*|to\s*|from\s*|became\s*)($MKeys)([^\w-]|\Z)!$1<b>$2</b>$3!ig; # intrinsic types, modifiers
    
    # Markdown
    $Content=~s!\*\*([\w\-]+)\*\*!<b>$1</b>!ig;
    $Content=~s!\*([\w\-]+)\*!<i>$1</i>!ig;
    return $Content;
}

sub applyMacroses($$$$)
{
    my ($Level, $Kind, $Content, $Problem) = @_;
    return "" if(not $Content or not $Problem);
    $Problem->{"Word_Size"} = $WORD_SIZE{2};
    $Content = addMarkup($Content);
    # macros
    foreach my $Attr (sort {$b cmp $a} keys(%{$Problem}))
    {
        my $Macro = "\@".lc($Attr);
        my $Value = $Problem->{$Attr};
        if(not defined $Value
        or $Value eq "") {
            next;
        }
        
        if(index($Content, $Macro)==-1) {
            next;
        }
        
        if($Kind!~/\A(Changed|Added|Removed)_Constant\Z/
        and $Kind!~/_Type_/
        and $Value=~/\s\(/ and $Value!~/['"]/)
        { # functions
            $Value=~s/\s*\[[\w\-]+\]//g; # remove quals
            $Value=~s/\s[a-z]\w*(\)|,)/$1/ig; # remove parameter names
            $Value = black_name($Value);
        }
        elsif($Value=~/\s/) {
            $Value = "<span class='value'>".htmlSpecChars($Value)."</span>";
        }
        elsif($Value=~/\A\d+\Z/
        and ($Attr eq "Old_Size" or $Attr eq "New_Size"))
        { # bits to bytes
            if($Value % $BYTE_SIZE)
            { # bits
                if($Value==1) {
                    $Value = "<b>".$Value."</b> bit";
                }
                else {
                    $Value = "<b>".$Value."</b> bits";
                }
            }
            else
            { # bytes
                $Value /= $BYTE_SIZE;
                if($Value==1) {
                    $Value = "<b>".$Value."</b> byte";
                }
                else {
                    $Value = "<b>".$Value."</b> bytes";
                }
            }
        }
        else
        {
            $Value = "<b>".htmlSpecChars($Value)."</b>";
        }
        $Content=~s/\Q$Macro\E/$Value/g;
    }
    
    if($Content=~/(\A|[^\@\w])\@\w/)
    {
        if(not $IncompleteRules{$Level}{$Kind})
        { # only one warning
            printMsg("WARNING", "incomplete rule \"$Kind\" (\"$Level\")");
            $IncompleteRules{$Level}{$Kind} = 1;
        }
    }
    return $Content;
}

sub get_Report_SymbolProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $INTERFACE_PROBLEMS = "";
    my (%ReportMap, %SymbolChanges) = ();
    
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        my ($SN, $SS, $SV) = separate_symbol($Symbol);
        if($SV and defined $CompatProblems{$Level}{$SN}) {
            next;
        }
        my $HeaderName = $CompleteSignature{1}{$Symbol}{"Header"};
        my $DyLib = $Symbol_Library{1}{$Symbol};
        if(not $DyLib and my $VSym = $SymVer{1}{$Symbol})
        { # Symbol with Version
            $DyLib = $Symbol_Library{1}{$VSym};
        }
        if(not $DyLib)
        { # const global data
            $DyLib = "";
        }
        if($Level eq "Source" and $ReportFormat eq "html")
        { # do not show library name in HTML report
            $DyLib = "";
        }
        
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols"
            and $Kind ne "Added_Symbol" and $Kind ne "Removed_Symbol")
            {
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                foreach my $Location (sort keys(%{$CompatProblems{$Level}{$Symbol}{$Kind}}))
                {
                    if($Severity eq $TargetSeverity)
                    {
                        $SymbolChanges{$Symbol}{$Kind} = $CompatProblems{$Level}{$Symbol}{$Kind};
                        $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
                    }
                }
            }
        }
    }
    
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $INTERFACE_PROBLEMS .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $INTERFACE_PROBLEMS .= "    <library name=\"$DyLib\">\n";
                my @SortedInterfaces = sort {lc($tr_name{$a}?$tr_name{$a}:$a) cmp lc($tr_name{$b}?$tr_name{$b}:$b)} keys(%{$ReportMap{$HeaderName}{$DyLib}});
                foreach my $Symbol (@SortedInterfaces)
                {
                    $INTERFACE_PROBLEMS .= "      <symbol name=\"$Symbol\">\n";
                    foreach my $Kind (sort keys(%{$SymbolChanges{$Symbol}}))
                    {
                        foreach my $Location (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                        {
                            my %Problem = %{$SymbolChanges{$Symbol}{$Kind}{$Location}};
                            $Problem{"Param_Pos"} = showPos($Problem{"Param_Pos"});
                            
                            $INTERFACE_PROBLEMS .= "        <problem id=\"$Kind\">\n";
                            my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                            $INTERFACE_PROBLEMS .= "          <change".getXmlParams($Change, \%Problem).">$Change</change>\n";
                            my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                            $INTERFACE_PROBLEMS .= "          <effect".getXmlParams($Effect, \%Problem).">$Effect</effect>\n";
                            if(my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"}) {
                                $INTERFACE_PROBLEMS .= "          <overcome".getXmlParams($Overcome, \%Problem).">$Overcome</overcome>\n";
                            }
                            $INTERFACE_PROBLEMS .= "        </problem>\n";
                        }
                    }
                    $INTERFACE_PROBLEMS .= "      </symbol>\n";
                }
                $INTERFACE_PROBLEMS .= "    </library>\n";
            }
            $INTERFACE_PROBLEMS .= "  </header>\n";
        }
        $INTERFACE_PROBLEMS = "<problems_with_symbols severity=\"$TargetSeverity\">\n".$INTERFACE_PROBLEMS."</problems_with_symbols>\n\n";
    }
    else
    { # HTML
        my $ProblemsNum = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                my (%NameSpaceSymbols, %NewSignature) = ();
                foreach my $Symbol (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $NameSpaceSymbols{select_Symbol_NS($Symbol, 1)}{$Symbol} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $INTERFACE_PROBLEMS .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc($tr_name{$a}?$tr_name{$a}:$a) cmp lc($tr_name{$b}?$tr_name{$b}:$b)} sort keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        my $Signature = get_Signature($Symbol, 1);
                        my $SYMBOL_REPORT = "";
                        my $ProblemNum = 1;
                        foreach my $Kind (sort keys(%{$SymbolChanges{$Symbol}}))
                        {
                            foreach my $Location (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                            {
                                my %Problem = %{$SymbolChanges{$Symbol}{$Kind}{$Location}};
                                $Problem{"Param_Pos"} = showPos($Problem{"Param_Pos"});
                                if($Problem{"New_Signature"}) {
                                    $NewSignature{$Symbol} = $Problem{"New_Signature"};
                                }
                                if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, \%Problem))
                                {
                                    my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, \%Problem);
                                    $SYMBOL_REPORT .= "<tr>\n<th>$ProblemNum</th>\n<td>".$Change."</td>\n<td>".$Effect."</td>\n</tr>\n";
                                    $ProblemNum += 1;
                                    $ProblemsNum += 1;
                                }
                            }
                        }
                        $ProblemNum -= 1;
                        if($SYMBOL_REPORT)
                        {
                            my $ShowSymbol = $Symbol;
                            if($Signature) {
                                $ShowSymbol = highLight_Signature_Italic_Color($Signature);
                            }
                            
                            if($NameSpace)
                            {
                                $SYMBOL_REPORT = cut_Namespace($SYMBOL_REPORT, $NameSpace);
                                $ShowSymbol = cut_Namespace($ShowSymbol, $NameSpace);
                            }
                            
                            $INTERFACE_PROBLEMS .= $ContentSpanStart."<span class='ext'>[+]</span> ".$ShowSymbol." <span".getStyle("I", $TargetSeverity, $ProblemNum).">&nbsp;$ProblemNum&nbsp;</span>".$ContentSpanEnd."<br/>\n";
                            $INTERFACE_PROBLEMS .= $ContentDivStart."\n";
                            
                            if(my $NSign = $NewSignature{$Symbol})
                            { # argument list changed to
                                if($NameSpace) {
                                    $NSign = cut_Namespace($NSign, $NameSpace);
                                }
                                $INTERFACE_PROBLEMS .= "\n<span class='new_sign_lbl'>changed to:</span>\n<br/>\n<span class='new_sign'>".highLight_Signature_Italic_Color($NSign)."</span><br/>\n";
                            }
                            
                            if($Symbol=~/\A(_Z|\?)/) {
                                $INTERFACE_PROBLEMS .= "<span class='mangled'>&#160;&#160;&#160;&#160;[symbol: <b>$Symbol</b>]</span><br/>\n";
                            }
                            
                            $INTERFACE_PROBLEMS .= "<table class='ptable'>\n<tr>\n<th width='2%'></th>\n<th width='47%'>Change</th>\n<th>Effect</th>\n</tr>\n$SYMBOL_REPORT</table>\n<br/>\n";
                            $INTERFACE_PROBLEMS .= $ContentDivEnd;
                        }
                    }
                    $INTERFACE_PROBLEMS .= "<br/>\n";
                }
            }
        }
        
        if($INTERFACE_PROBLEMS)
        {
            $INTERFACE_PROBLEMS = insertIDs($INTERFACE_PROBLEMS);
            my $Title = "Problems with Symbols, $TargetSeverity Severity";
            if($TargetSeverity eq "Safe")
            { # Safe Changes
                $Title = "Other Changes in Symbols";
            }
            $INTERFACE_PROBLEMS = "<a name=\'".get_Anchor("Symbol", $Level, $TargetSeverity)."\'></a><a name=\'".get_Anchor("Interface", $Level, $TargetSeverity)."\'></a>\n<h2>$Title <span".getStyle("I", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$INTERFACE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $INTERFACE_PROBLEMS;
}

sub cut_Namespace($$)
{
    my ($N, $Ns) = @_;
    $N=~s/\b\Q$Ns\E:://g;
    return $N;
}

sub get_Report_TypeProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $TYPE_PROBLEMS = "";
    
    my %ReportMap = ();
    my %TypeChanges_Sev = ();
    
    foreach my $TypeName (keys(%{$TypeChanges{$Level}}))
    {
        my $HeaderName = $TypeInfo{1}{$TName_Tid{1}{$TypeName}}{"Header"};
        
        foreach my $Kind (keys(%{$TypeChanges{$Level}{$TypeName}}))
        {
            foreach my $Location (keys(%{$TypeChanges{$Level}{$TypeName}{$Kind}}))
            {
                my $Target = $TypeChanges{$Level}{$TypeName}{$Kind}{$Location}{"Target"};
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                
                if($Severity eq $TargetSeverity)
                {
                    $ReportMap{$HeaderName}{$TypeName} = 1;
                    $TypeChanges_Sev{$TypeName}{$Kind}{$Location} = $TypeChanges{$Level}{$TypeName}{$Kind}{$Location};
                }
            }
        }
    }
    
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $TYPE_PROBLEMS .= "  <header name=\"$HeaderName\">\n";
            foreach my $TypeName (keys(%{$ReportMap{$HeaderName}}))
            {
                my (%Kinds_Locations, %Kinds_Target) = ();
                $TYPE_PROBLEMS .= "    <type name=\"".xmlSpecChars($TypeName)."\">\n";
                foreach my $Kind (sort {$b=~/Size/ <=> $a=~/Size/} sort keys(%{$TypeChanges_Sev{$TypeName}}))
                {
                    foreach my $Location (sort {cmpLocations($b, $a)} sort keys(%{$TypeChanges_Sev{$TypeName}{$Kind}}))
                    {
                        $Kinds_Locations{$Kind}{$Location} = 1;
                        
                        my $Target = $TypeChanges_Sev{$TypeName}{$Kind}{$Location}{"Target"};
                        if($Kinds_Target{$Kind}{$Target}) {
                            next;
                        }
                        $Kinds_Target{$Kind}{$Target} = 1;
                        
                        my %Problem = %{$TypeChanges_Sev{$TypeName}{$Kind}{$Location}};
                        $TYPE_PROBLEMS .= "      <problem id=\"$Kind\">\n";
                        my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                        $TYPE_PROBLEMS .= "        <change".getXmlParams($Change, \%Problem).">$Change</change>\n";
                        my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                        $TYPE_PROBLEMS .= "        <effect".getXmlParams($Effect, \%Problem).">$Effect</effect>\n";
                        if(my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"}) {
                            $TYPE_PROBLEMS .= "        <overcome".getXmlParams($Overcome, \%Problem).">$Overcome</overcome>\n";
                        }
                        $TYPE_PROBLEMS .= "      </problem>\n";
                    }
                }
                $TYPE_PROBLEMS .= getAffectedSymbols($Level, $TypeName, $Kinds_Locations{$TypeName});
                if($Level eq "Binary" and grep {$_=~/Virtual|Base_Class/} keys(%{$Kinds_Locations{$TypeName}})) {
                    $TYPE_PROBLEMS .= showVTables($TypeName);
                }
                $TYPE_PROBLEMS .= "    </type>\n";
            }
            $TYPE_PROBLEMS .= "  </header>\n";
        }
        $TYPE_PROBLEMS = "<problems_with_types severity=\"$TargetSeverity\">\n".$TYPE_PROBLEMS."</problems_with_types>\n\n";
    }
    else
    { # HTML
        my $ProblemsNum = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            my (%NameSpace_Type) = ();
            foreach my $TypeName (keys(%{$ReportMap{$HeaderName}})) {
                $NameSpace_Type{select_Type_NS($TypeName, 1)}{$TypeName} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Type))
            {
                $TYPE_PROBLEMS .= getTitle($HeaderName, "", $NameSpace);
                my @SortedTypes = sort {lc(show_Type($a, 0, 1)) cmp lc(show_Type($b, 0, 1))} keys(%{$NameSpace_Type{$NameSpace}});
                foreach my $TypeName (@SortedTypes)
                {
                    my $ProblemNum = 1;
                    my $TYPE_REPORT = "";
                    my (%Kinds_Locations, %Kinds_Target) = ();
                    
                    foreach my $Kind (sort {$b=~/Size/ <=> $a=~/Size/} sort keys(%{$TypeChanges_Sev{$TypeName}}))
                    {
                        foreach my $Location (sort {cmpLocations($b, $a)} sort keys(%{$TypeChanges_Sev{$TypeName}{$Kind}}))
                        {
                            $Kinds_Locations{$Kind}{$Location} = 1;
                            
                            my $Target = $TypeChanges_Sev{$TypeName}{$Kind}{$Location}{"Target"};
                            if($Kinds_Target{$Kind}{$Target}) {
                                next;
                            }
                            $Kinds_Target{$Kind}{$Target} = 1;
                            
                            my %Problem = %{$TypeChanges_Sev{$TypeName}{$Kind}{$Location}};
                            if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, \%Problem))
                            {
                                my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, \%Problem);
                                $TYPE_REPORT .= "<tr>\n<th>$ProblemNum</th>\n<td>".$Change."</td>\n<td>$Effect</td>\n</tr>\n";
                                $ProblemNum += 1;
                                $ProblemsNum += 1;
                            }
                        }
                    }
                    $ProblemNum -= 1;
                    if($TYPE_REPORT)
                    {
                        my $Affected = getAffectedSymbols($Level, $TypeName, \%Kinds_Locations);
                        my $ShowVTables = "";
                        if($Level eq "Binary" and grep {$_=~/Virtual|Base_Class/} keys(%Kinds_Locations)) {
                            $ShowVTables = showVTables($TypeName);
                        }
                        
                        my $ShowType = show_Type($TypeName, 1, 1);
                        
                        if($NameSpace)
                        {
                            $TYPE_REPORT = cut_Namespace($TYPE_REPORT, $NameSpace);
                            $ShowType = cut_Namespace($ShowType, $NameSpace);
                            $Affected = cut_Namespace($Affected, $NameSpace);
                            $ShowVTables = cut_Namespace($ShowVTables, $NameSpace);
                        }
                        
                        $TYPE_PROBLEMS .= $ContentSpanStart."<span class='ext'>[+]</span> ".$ShowType." <span".getStyle("T", $TargetSeverity, $ProblemNum).">&nbsp;$ProblemNum&nbsp;</span>".$ContentSpanEnd;
                        $TYPE_PROBLEMS .= "<br/>\n".$ContentDivStart."<table class='ptable'><tr>\n";
                        $TYPE_PROBLEMS .= "<th width='2%'></th><th width='47%'>Change</th>\n";
                        $TYPE_PROBLEMS .= "<th>Effect</th></tr>".$TYPE_REPORT."</table>\n";
                        $TYPE_PROBLEMS .= $ShowVTables.$Affected."<br/><br/>".$ContentDivEnd."\n";
                    }
                }
                $TYPE_PROBLEMS .= "<br/>\n";
            }
        }
        
        if($TYPE_PROBLEMS)
        {
            $TYPE_PROBLEMS = insertIDs($TYPE_PROBLEMS);
            my $Title = "Problems with Data Types, $TargetSeverity Severity";
            if($TargetSeverity eq "Safe")
            { # Safe Changes
                $Title = "Other Changes in Data Types";
            }
            $TYPE_PROBLEMS = "<a name=\'".get_Anchor("Type", $Level, $TargetSeverity)."\'></a>\n<h2>$Title <span".getStyle("T", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$TYPE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $TYPE_PROBLEMS;
}

sub show_Type($$$)
{
    my ($Name, $Html, $LibVersion) = @_;
    my $TType = $TypeInfo{$LibVersion}{$TName_Tid{$LibVersion}{$Name}}{"Type"};
    $TType = lc($TType);
    if($TType=~/struct|union|enum/) {
        $Name=~s/\A\Q$TType\E //g;
    }
    if($Html) {
        $Name = "<span class='ttype'>".$TType."</span> ".htmlSpecChars($Name);
    }
    else {
        $Name = $TType." ".$Name;
    }
    return $Name;
}

sub get_Anchor($$$)
{
    my ($Kind, $Level, $Severity) = @_;
    if($JoinReport)
    {
        if($Severity eq "Safe") {
            return "Other_".$Level."_Changes_In_".$Kind."s";
        }
        else {
            return $Kind."_".$Level."_Problems_".$Severity;
        }
    }
    else
    {
        if($Severity eq "Safe") {
            return "Other_Changes_In_".$Kind."s";
        }
        else {
            return $Kind."_Problems_".$Severity;
        }
    }
}

sub showVTables($)
{
    my $TypeName = $_[0];
    my $TypeId1 = $TName_Tid{1}{$TypeName};
    my %Type1 = get_Type($TypeId1, 1);
    if(defined $Type1{"VTable"}
    and keys(%{$Type1{"VTable"}}))
    {
        my $TypeId2 = $TName_Tid{2}{$TypeName};
        my %Type2 = get_Type($TypeId2, 2);
        if(defined $Type2{"VTable"}
        and keys(%{$Type2{"VTable"}}))
        {
            my %Indexes = map {$_=>1} (keys(%{$Type1{"VTable"}}), keys(%{$Type2{"VTable"}}));
            my %Entries = ();
            foreach my $Index (sort {int($a)<=>int($b)} (keys(%Indexes)))
            {
                $Entries{$Index}{"E1"} = simpleVEntry($Type1{"VTable"}{$Index});
                $Entries{$Index}{"E2"} = simpleVEntry($Type2{"VTable"}{$Index});
            }
            my $VTABLES = "";
            if($ReportFormat eq "xml")
            { # XML
                $VTABLES .= "      <vtable>\n";
                foreach my $Index (sort {int($a)<=>int($b)} (keys(%Entries)))
                {
                    $VTABLES .= "        <entry offset=\"".$Index."\">\n";
                    $VTABLES .= "          <old>".xmlSpecChars($Entries{$Index}{"E1"})."</old>\n";
                    $VTABLES .= "          <new>".xmlSpecChars($Entries{$Index}{"E2"})."</new>\n";
                    $VTABLES .= "        </entry>\n";
                }
                $VTABLES .= "      </vtable>\n\n";
            }
            else
            { # HTML
                $VTABLES .= "<table class='vtable'>";
                $VTABLES .= "<tr><th>Offset</th>";
                $VTABLES .= "<th>Virtual Table (Old) - ".(keys(%{$Type1{"VTable"}}))." entries</th>";
                $VTABLES .= "<th>Virtual Table (New) - ".(keys(%{$Type2{"VTable"}}))." entries</th></tr>";
                foreach my $Index (sort {int($a)<=>int($b)} (keys(%Entries)))
                {
                    my ($Color1, $Color2) = ("", "");
                    
                    my $E1 = $Entries{$Index}{"E1"};
                    my $E2 = $Entries{$Index}{"E2"};
                    
                    if($E1 ne $E2
                    and $E1!~/ 0x/
                    and $E2!~/ 0x/)
                    {
                        if($Entries{$Index}{"E1"})
                        {
                            $Color1 = " class='failed'";
                            $Color2 = " class='failed'";
                        }
                        else {
                            $Color2 = " class='warning'";
                        }
                    }
                    $VTABLES .= "<tr><th>".$Index."</th>\n";
                    $VTABLES .= "<td$Color1>".htmlSpecChars($Entries{$Index}{"E1"})."</td>\n";
                    $VTABLES .= "<td$Color2>".htmlSpecChars($Entries{$Index}{"E2"})."</td></tr>\n";
                }
                $VTABLES .= "</table><br/>\n";
                $VTABLES = $ContentDivStart.$VTABLES.$ContentDivEnd;
                $VTABLES = $ContentSpanStart_Info."[+] show v-table (old and new)".$ContentSpanEnd."<br/>\n".$VTABLES;
            }
            return $VTABLES;
        }
    }
    return "";
}

sub simpleVEntry($)
{
    my $VEntry = $_[0];
    if(not defined $VEntry
    or $VEntry eq "") {
        return "";
    }
    
    $VEntry=~s/ \[.+?\]\Z//; # support for ABI Dumper
    $VEntry=~s/\A(.+)::(_ZThn.+)\Z/$2/; # thunks
    $VEntry=~s/_ZTI\w+/typeinfo/g; # typeinfo
    if($VEntry=~/\A_ZThn.+\Z/) {
        $VEntry = "non-virtual thunk";
    }
    $VEntry=~s/\A\(int \(\*\)\(...\)\)\s*([a-z_])/$1/i;
    # support for old GCC versions
    $VEntry=~s/\A0u\Z/(int (*)(...))0/;
    $VEntry=~s/\A4294967268u\Z/(int (*)(...))-0x000000004/;
    $VEntry=~s/\A&_Z\Z/& _Z/;
    $VEntry=~s/([^:]+)::\~([^:]+)\Z/~$1/; # destructors
    return $VEntry;
}

sub adjustParamPos($$$)
{
    my ($Pos, $Symbol, $LibVersion) = @_;
    if(defined $CompleteSignature{$LibVersion}{$Symbol})
    {
        if(not $CompleteSignature{$LibVersion}{$Symbol}{"Static"}
        and $CompleteSignature{$LibVersion}{$Symbol}{"Class"})
        {
            return $Pos-1;
        }
        
        return $Pos;
    }
    
    return undef;
}

sub getParamPos($$$)
{
    my ($Name, $Symbol, $LibVersion) = @_;
    
    if(defined $CompleteSignature{$LibVersion}{$Symbol}
    and defined $CompleteSignature{$LibVersion}{$Symbol}{"Param"})
    {
        my $Info = $CompleteSignature{$LibVersion}{$Symbol};
        foreach (keys(%{$Info->{"Param"}}))
        {
            if($Info->{"Param"}{$_}{"name"} eq $Name)
            {
                return $_;
            }
        }
    }
    
    return undef;
}

sub getParamName($)
{
    my $Loc = $_[0];
    $Loc=~s/\->.*//g;
    return $Loc;
}

sub getAffectedSymbols($$$)
{
    my ($Level, $Target_TypeName, $Kinds_Locations) = @_;
    
    my $LIMIT = 10;
    if(defined $AffectLimit) {
        $LIMIT = $AffectLimit;
    }
    
    my @Kinds = sort keys(%{$Kinds_Locations});
    my %KLocs = ();
    foreach my $Kind (@Kinds)
    {
        my @Locs = sort {$a=~/retval/ cmp $b=~/retval/} sort {length($a)<=>length($b)} sort keys(%{$Kinds_Locations->{$Kind}});
        $KLocs{$Kind} = \@Locs;
    }
    
    my %SymLocKind = ();
    foreach my $Symbol (sort keys(%{$TypeProblemsIndex{$Level}{$Target_TypeName}}))
    {
        if(index($Symbol, "_Z")==0
        and $Symbol=~/(C2|D2|D0)[EI]/)
        { # duplicated problems for C2 constructors, D2 and D0 destructors
            next;
        }
        
        foreach my $Kind (@Kinds)
        {
            foreach my $Loc (@{$KLocs{$Kind}})
            {
                if(not defined $CompatProblems{$Level}{$Symbol}{$Kind}{$Loc}) {
                    next;
                }
                
                if(index($Symbol, "\@")!=-1
                or index($Symbol, "\$")!=-1)
                {
                    my ($SN, $SS, $SV) = separate_symbol($Symbol);
                    
                    if($Level eq "Source")
                    { # remove symbol version
                        $Symbol = $SN;
                    }
                    
                    if($SV and defined $CompatProblems{$Level}{$SN}
                    and defined $CompatProblems{$Level}{$SN}{$Kind}{$Loc})
                    { # duplicated problems for versioned symbols
                        next;
                    }
                }
                
                my $Type_Name = $CompatProblems{$Level}{$Symbol}{$Kind}{$Loc}{"Type_Name"};
                if($Type_Name ne $Target_TypeName) {
                    next;
                }
                
                $SymLocKind{$Symbol}{$Loc}{$Kind} = 1;
                last;
            }
        }
    }
    
    %KLocs = (); # clear
    
    my %SymSel = ();
    my $Num = 0;
    foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%SymLocKind))
    {
        LOOP: foreach my $Loc (sort {$a=~/retval/ cmp $b=~/retval/} sort {length($a)<=>length($b)} sort keys(%{$SymLocKind{$Symbol}}))
        {
            foreach my $Kind (sort keys(%{$SymLocKind{$Symbol}{$Loc}}))
            {
                $SymSel{$Symbol}{"Loc"} = $Loc;
                $SymSel{$Symbol}{"Kind"} = $Kind;
                last LOOP;
            }
        }
        
        $Num += 1;
        
        if($Num>=$LIMIT) {
            last;
        }
    }
    
    my $Affected = "";
    
    if($ReportFormat eq "xml")
    { # XML
        $Affected .= "      <affected>\n";
        
        foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%SymSel))
        {
            my $Loc = $SymSel{$Symbol}{"Loc"};
            my $PName = getParamName($Loc);
            my $Desc = getAffectDesc($Level, $Symbol, $SymSel{$Symbol}{"Kind"}, $Loc);
            
            my $Target = "";
            if($PName)
            {
                $Target .= " param=\"$PName\"";
                $Desc=~s/parameter $PName /parameter \@param /;
            }
            elsif($Loc=~/\Aretval(\-|\Z)/i) {
                $Target .= " affected=\"retval\"";
            }
            elsif($Loc=~/\Athis(\-|\Z)/i) {
                $Target .= " affected=\"this\"";
            }
            
            if($Desc=~s/\AField ([^\s]+) /Field \@field /) {
                $Target .= " field=\"$1\"";
            }
            
            $Affected .= "        <symbol name=\"$Symbol\"$Target>\n";
            $Affected .= "          <comment>".xmlSpecChars($Desc)."</comment>\n";
            $Affected .= "        </symbol>\n";
        }
        $Affected .= "      </affected>\n";
    }
    else
    { # HTML
        foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%SymSel))
        {
            my $Kind = $SymSel{$Symbol}{"Kind"};
            my $Loc = $SymSel{$Symbol}{"Loc"};
            
            my $Desc = getAffectDesc($Level, $Symbol, $Kind, $Loc);
            my $S = get_Signature($Symbol, 1);
            my $PName = getParamName($Loc);
            my $Pos = adjustParamPos(getParamPos($PName, $Symbol, 1), $Symbol, 1);
            
            $Affected .= "<span class='iname_a'>".highLight_Signature_PPos_Italic($S, $Pos, 1, 0, 0)."</span><br/>\n";
            $Affected .= "<div class='affect'>".htmlSpecChars($Desc)."</div>\n";
        }
        
        if(keys(%SymLocKind)>$LIMIT) {
            $Affected .= " <b>...</b>\n<br/>\n"; # and others ...
        }
        
        $Affected = "<div class='affected'>".$Affected."</div>\n";
        if($Affected)
        {
            my $Num = keys(%SymLocKind);
            my $Per = show_number($Num*100/keys(%{$CheckedSymbols{$Level}}));
            $Affected = $ContentDivStart.$Affected.$ContentDivEnd;
            $Affected = $ContentSpanStart_Affected."[+] affected symbols: $Num ($Per\%)".$ContentSpanEnd.$Affected;
        }
    }
    
    return $Affected;
}

sub cmpLocations($$)
{
    my ($L1, $L2) = @_;
    if($L2=~/\A(retval|this)\b/
    and $L1!~/\A(retval|this)\b/)
    {
        if($L1!~/\-\>/) {
            return 1;
        }
        elsif($L2=~/\-\>/) {
            return 1;
        }
    }
    return 0;
}

sub getAffectDesc($$$$)
{
    my ($Level, $Symbol, $Kind, $Location) = @_;
    
    my %Problem = %{$CompatProblems{$Level}{$Symbol}{$Kind}{$Location}};
    
    my $Location_I = $Location;
    $Location=~s/\A(.*)\-\>(.+?)\Z/$1/; # without the latest affected field
    
    my @Sentence = ();
    
    if($Kind eq "Overridden_Virtual_Method"
    or $Kind eq "Overridden_Virtual_Method_B") {
        push(@Sentence, "The method '".$Problem{"New_Value"}."' will be called instead of this method.");
    }
    elsif($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
    {
        my %SymInfo = %{$CompleteSignature{1}{$Symbol}};
        
        if($Location eq "this" or $Kind=~/(\A|_)Virtual(_|\Z)/)
        {
            my $METHOD_TYPE = $SymInfo{"Constructor"}?"constructor":"method";
            my $ClassName = $TypeInfo{1}{$SymInfo{"Class"}}{"Name"};
            
            if($ClassName eq $Problem{"Type_Name"}) {
                push(@Sentence, "This $METHOD_TYPE is from \'".$Problem{"Type_Name"}."\' class.");
            }
            else {
                push(@Sentence, "This $METHOD_TYPE is from derived class \'".$ClassName."\'.");
            }
        }
        else
        {
            my $TypeID = undef;
            
            if($Location=~/retval/)
            { # return value
                if(index($Location, "->")!=-1) {
                    push(@Sentence, "Field \'".$Location."\' in return value");
                }
                else {
                    push(@Sentence, "Return value");
                }
                
                $TypeID = $SymInfo{"Return"};
            }
            elsif($Location=~/this/)
            { # "this" pointer
                if(index($Location, "->")!=-1) {
                    push(@Sentence, "Field \'".$Location."\' in the object of this method");
                }
                else {
                    push(@Sentence, "\'this\' pointer");
                }
                
                $TypeID = $SymInfo{"Class"};
            }
            else
            { # parameters
            
                my $PName = getParamName($Location);
                my $PPos = getParamPos($PName, $Symbol, 1);
            
                if(index($Location, "->")!=-1) {
                    push(@Sentence, "Field \'".$Location."\' in ".showPos(adjustParamPos($PPos, $Symbol, 1))." parameter");
                }
                else {
                    push(@Sentence, showPos(adjustParamPos($PPos, $Symbol, 1))." parameter");
                }
                if($PName) {
                    push(@Sentence, "\'".$PName."\'");
                }
                
                $TypeID = $SymInfo{"Param"}{$PPos}{"type"};
            }
            
            if($Location!~/this/)
            {
                if(my %PureType = get_PureType($TypeID, $TypeInfo{1}))
                {
                    if($PureType{"Type"} eq "Pointer") {
                        push(@Sentence, "(pointer)");
                    }
                    elsif($PureType{"Type"} eq "Ref") {
                        push(@Sentence, "(reference)");
                    }
                }
            }
            
            if($Location eq "this") {
                push(@Sentence, "has base type \'".$Problem{"Type_Name"}."\'.");
            }
            else
            {
                my $Location_T = $Location;
                $Location_T=~s/\A\w+(\->|\Z)//; # location in type
                
                my $TypeID_Problem = $TypeID;
                if($Location_T) {
                    $TypeID_Problem = getFieldType($Location_T, $TypeID, 1);
                }
                
                if($TypeInfo{1}{$TypeID_Problem}{"Name"} eq $Problem{"Type_Name"}) {
                    push(@Sentence, "has type \'".$Problem{"Type_Name"}."\'.");
                }
                else {
                    push(@Sentence, "has base type \'".$Problem{"Type_Name"}."\'.");
                }
            }
        }
    }
    if($ExtendedSymbols{$Symbol}) {
        push(@Sentence, " This is a symbol from an external library that may use the \'$TargetLibraryName\' library and change the ABI after recompiling.");
    }
    
    my $Sent = join(" ", @Sentence);
    
    $Sent=~s/->/./g;
    
    if($ReportFormat eq "xml")
    {
        $Sent=~s/'//g;
    }
    
    return $Sent;
}

sub getFieldType($$$)
{
    my ($Location, $TypeId, $LibVersion) = @_;
    
    my @Fields = split(/\->/, $Location);
    
    foreach my $Name (@Fields)
    {
        my %Info = get_BaseType($TypeId, $LibVersion);
        
        foreach my $Pos (keys(%{$Info{"Memb"}}))
        {
            if($Info{"Memb"}{$Pos}{"name"} eq $Name)
            {
                $TypeId = $Info{"Memb"}{$Pos}{"type"};
                last;
            }
        }
    }
    
    return $TypeId;
}

sub get_XmlSign($$)
{
    my ($Symbol, $LibVersion) = @_;
    my $Info = $CompleteSignature{$LibVersion}{$Symbol};
    my $Report = "";
    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$Info->{"Param"}}))
    {
        my $Name = $Info->{"Param"}{$Pos}{"name"};
        my $Type = $Info->{"Param"}{$Pos}{"type"};
        my $TypeName = $TypeInfo{$LibVersion}{$Type}{"Name"};
        foreach my $Typedef (keys(%ChangedTypedef))
        {
            if(my $Base = $Typedef_BaseName{$LibVersion}{$Typedef}) {
                $TypeName=~s/\b\Q$Typedef\E\b/$Base/g;
            }
        }
        $Report .= "    <param pos=\"$Pos\">\n";
        $Report .= "      <name>".$Name."</name>\n";
        $Report .= "      <type>".xmlSpecChars($TypeName)."</type>\n";
        $Report .= "    </param>\n";
    }
    if(my $Return = $Info->{"Return"})
    {
        my $RTName = $TypeInfo{$LibVersion}{$Return}{"Name"};
        $Report .= "    <retval>\n";
        $Report .= "      <type>".xmlSpecChars($RTName)."</type>\n";
        $Report .= "    </retval>\n";
    }
    return $Report;
}

sub get_Report_SymbolsInfo($)
{
    my $Level = $_[0];
    my $Report = "<symbols_info>\n";
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        my ($SN, $SS, $SV) = separate_symbol($Symbol);
        if($SV and defined $CompatProblems{$Level}{$SN}) {
            next;
        }
        $Report .= "  <symbol name=\"$Symbol\">\n";
        my ($S1, $P1, $S2, $P2) = ();
        if(not $AddedInt{$Level}{$Symbol})
        {
            if(defined $CompleteSignature{1}{$Symbol}
            and defined $CompleteSignature{1}{$Symbol}{"Header"})
            {
                $P1 = get_XmlSign($Symbol, 1);
                $S1 = get_Signature($Symbol, 1);
            }
            elsif($Symbol=~/\A(_Z|\?)/) {
                $S1 = $tr_name{$Symbol};
            }
        }
        if(not $RemovedInt{$Level}{$Symbol})
        {
            if(defined $CompleteSignature{2}{$Symbol}
            and defined $CompleteSignature{2}{$Symbol}{"Header"})
            {
                $P2 = get_XmlSign($Symbol, 2);
                $S2 = get_Signature($Symbol, 2);
            }
            elsif($Symbol=~/\A(_Z|\?)/) {
                $S2 = $tr_name{$Symbol};
            }
        }
        if($S1)
        {
            $Report .= "    <old signature=\"".xmlSpecChars($S1)."\">\n";
            $Report .= $P1;
            $Report .= "    </old>\n";
        }
        if($S2 and $S2 ne $S1)
        {
            $Report .= "    <new signature=\"".xmlSpecChars($S2)."\">\n";
            $Report .= $P2;
            $Report .= "    </new>\n";
        }
        $Report .= "  </symbol>\n";
    }
    $Report .= "</symbols_info>\n";
    return $Report;
}

sub writeReport($$)
{
    my ($Level, $Report) = @_;
    if($ReportFormat eq "xml") {
        $Report = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n".$Report;
    }
    if($StdOut)
    { # --stdout option
        print STDOUT $Report;
    }
    else
    {
        my $RPath = getReportPath($Level);
        mkpath(get_dirname($RPath));
        
        open(REPORT, ">", $RPath) || die ("can't open file \'$RPath\': $!\n");
        print REPORT $Report;
        close(REPORT);
    }
}

sub getReport($)
{
    my $Level = $_[0];
    if($ReportFormat eq "xml")
    { # XML
        if($Level eq "Join")
        {
            my $Report = "<reports>\n";
            $Report .= getReport("Binary");
            $Report .= getReport("Source");
            $Report .= "</reports>\n";
            return $Report;
        }
        else
        {
            my $Report = "<report kind=\"".lc($Level)."\" version=\"$XML_REPORT_VERSION\">\n\n";
            my ($Summary, $MetaData) = get_Summary($Level);
            $Report .= $Summary."\n";
            $Report .= get_Report_Added($Level).get_Report_Removed($Level);
            $Report .= get_Report_Problems("High", $Level).get_Report_Problems("Medium", $Level).get_Report_Problems("Low", $Level).get_Report_Problems("Safe", $Level);
            
            # additional symbols info (if needed)
            # $Report .= get_Report_SymbolsInfo($Level);
            
            $Report .= "</report>\n";
            return $Report;
        }
    }
    else
    { # HTML
        my $CssStyles = readModule("Styles", "Report.css");
        my $JScripts = readModule("Scripts", "Sections.js");
        if($Level eq "Join")
        {
            $CssStyles .= "\n".readModule("Styles", "Tabs.css");
            $JScripts .= "\n".readModule("Scripts", "Tabs.js");
            my $Title = $TargetTitle.": ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." compatibility report";
            my $Keywords = $TargetTitle.", compatibility, API, ABI, report";
            my $Description = "API/ABI compatibility report for the $TargetTitle $TargetComponent between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
            my ($BSummary, $BMetaData) = get_Summary("Binary");
            my ($SSummary, $SMetaData) = get_Summary("Source");
            my $Report = "<!-\- $BMetaData -\->\n<!-\- $SMetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."<body><a name='Source'></a><a name='Binary'></a><a name='Top'></a>";
            $Report .= get_Report_Title("Join")."
            <br/>
            <div class='tabset'>
            <a id='BinaryID' href='#BinaryTab' class='tab active'>Binary<br/>Compatibility</a>
            <a id='SourceID' href='#SourceTab' style='margin-left:3px' class='tab disabled'>Source<br/>Compatibility</a>
            </div>";
            $Report .= "<div id='BinaryTab' class='tab'>\n$BSummary\n".get_Report_Added("Binary").get_Report_Removed("Binary").get_Report_Problems("High", "Binary").get_Report_Problems("Medium", "Binary").get_Report_Problems("Low", "Binary").get_Report_Problems("Safe", "Binary").get_SourceInfo()."<br/><br/><br/></div>";
            $Report .= "<div id='SourceTab' class='tab'>\n$SSummary\n".get_Report_Added("Source").get_Report_Removed("Source").get_Report_Problems("High", "Source").get_Report_Problems("Medium", "Source").get_Report_Problems("Low", "Source").get_Report_Problems("Safe", "Source").get_SourceInfo()."<br/><br/><br/></div>";
            $Report .= getReportFooter();
            $Report .= "\n</body></html>\n";
            return $Report;
        }
        else
        {
            my ($Summary, $MetaData) = get_Summary($Level);
            my $Title = $TargetTitle.": ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." ".lc($Level)." compatibility report";
            my $Keywords = $TargetTitle.", ".lc($Level)." compatibility, API, report";
            my $Description = "$Level compatibility report for the ".$TargetTitle." ".$TargetComponent." between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
            if($Level eq "Binary")
            {
                if(getArch(1) eq getArch(2)
                and getArch(1) ne "unknown") {
                    $Description .= " on ".showArch(getArch(1));
                }
            }
            my $Report = "<!-\- $MetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."\n<body>\n<div><a name='Top'></a>\n";
            $Report .= get_Report_Title($Level)."\n".$Summary."\n";
            $Report .= get_Report_Added($Level).get_Report_Removed($Level);
            $Report .= get_Report_Problems("High", $Level).get_Report_Problems("Medium", $Level).get_Report_Problems("Low", $Level).get_Report_Problems("Safe", $Level);
            $Report .= get_SourceInfo();
            $Report .= "</div>\n<br/><br/><br/>\n";
            $Report .= getReportFooter();
            $Report .= "\n</body></html>\n";
            return $Report;
        }
    }
}

sub createReport()
{
    if($JoinReport)
    { # --stdout
        writeReport("Join", getReport("Join"));
    }
    elsif($DoubleReport)
    { # default
        writeReport("Binary", getReport("Binary"));
        writeReport("Source", getReport("Source"));
    }
    elsif($BinaryOnly)
    { # --binary
        writeReport("Binary", getReport("Binary"));
    }
    elsif($SourceOnly)
    { # --source
        writeReport("Source", getReport("Source"));
    }
}

sub getReportFooter()
{
    my $Footer = "";
    
    $Footer .= "<hr/>\n";
    $Footer .= "<div class='footer' align='right'>";
    $Footer .= "<i>Generated by <a href='".$HomePage."'>ABI Compliance Checker</a> $TOOL_VERSION &#160;</i>\n";
    $Footer .= "</div>\n";
    $Footer .= "<br/>\n";
    
    return $Footer;
}

sub get_Report_Problems($$)
{
    my ($Severity, $Level) = @_;
    
    my $Report = get_Report_TypeProblems($Severity, $Level);
    if(my $SProblems = get_Report_SymbolProblems($Severity, $Level)) {
        $Report .= $SProblems;
    }
    
    if($Severity eq "Low" or $Severity eq "Safe") {
        $Report .= get_Report_ChangedConstants($Severity, $Level);
    }
    
    if($ReportFormat eq "html")
    {
        if($Report)
        { # add anchor
            if($JoinReport)
            {
                if($Severity eq "Safe") {
                    $Report = "<a name=\'Other_".$Level."_Changes\'></a>".$Report;
                }
                else {
                    $Report = "<a name=\'".$Severity."_Risk_".$Level."_Problems\'></a>".$Report;
                }
            }
            else
            {
                if($Severity eq "Safe") {
                    $Report = "<a name=\'Other_Changes\'></a>".$Report;
                }
                else {
                    $Report = "<a name=\'".$Severity."_Risk_Problems\'></a>".$Report;
                }
            }
        }
    }
    return $Report;
}

sub composeHTML_Head($$$$$)
{
    my ($Title, $Keywords, $Description, $Styles, $Scripts) = @_;
    
    my $Head = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n";
    $Head .= "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n";
    $Head .= "<head>\n";
    $Head .= "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
    $Head .= "<meta name=\"keywords\" content=\"$Keywords\" />\n";
    $Head .= "<meta name=\"description\" content=\"$Description\" />\n";
    $Head .= "<title>$Title</title>\n";
    $Head .= "<style type=\"text/css\">\n$Styles</style>\n";
    $Head .= "<script type=\"text/javascript\" language=\"JavaScript\">\n<!--\n$Scripts\n-->\n</script>\n";
    $Head .= "</head>\n";
    
    return $Head;
}

sub insertIDs($)
{
    my $Text = $_[0];
    while($Text=~/CONTENT_ID/)
    {
        if(int($Content_Counter)%2) {
            $ContentID -= 1;
        }
        $Text=~s/CONTENT_ID/c_$ContentID/;
        $ContentID += 1;
        $Content_Counter += 1;
    }
    return $Text;
}

sub checkPreprocessedUnit($)
{
    my $Path = $_[0];
    my ($CurHeader, $CurHeaderName) = ("", "");
    my $CurClass = ""; # extra info
    open(PREPROC, $Path) || die ("can't open file \'$Path\': $!\n");
    
    while(my $Line = <PREPROC>)
    { # detecting public and private constants
        if(substr($Line, 0, 1) eq "#")
        {
            chomp($Line);
            if($Line=~/\A\#\s+\d+\s+\"(.+)\"/)
            {
                $CurHeader = path_format($1, $OSgroup);
                $CurHeaderName = get_filename($CurHeader);
                $CurClass = "";
                
                if(index($CurHeader, $TMP_DIR)==0) {
                    next;
                }
                
                if(substr($CurHeaderName, 0, 1) eq "<")
                { # <built-in>, <command-line>, etc.
                    $CurHeaderName = "";
                    $CurHeader = "";
                }
                
                if($ExtraInfo)
                {
                    if($CurHeaderName) {
                        $PreprocessedHeaders{$Version}{$CurHeader} = 1;
                    }
                }
            }
            if(not $ExtraDump)
            {
                if($CurHeaderName)
                {
                    if(not $Include_Neighbors{$Version}{$CurHeaderName}
                    and not $Registered_Headers{$Version}{$CurHeader})
                    { # not a target
                        next;
                    }
                    if(not is_target_header($CurHeaderName, 1)
                    and not is_target_header($CurHeaderName, 2))
                    { # user-defined header
                        next;
                    }
                }
            }
            
            if($Line=~/\A\#\s*define\s+(\w+)\s+(.+)\s*\Z/)
            {
                my ($Name, $Value) = ($1, $2);
                if(not $Constants{$Version}{$Name}{"Access"})
                {
                    $Constants{$Version}{$Name}{"Access"} = "public";
                    $Constants{$Version}{$Name}{"Value"} = $Value;
                    if($CurHeaderName) {
                        $Constants{$Version}{$Name}{"Header"} = $CurHeaderName;
                    }
                }
            }
            elsif($Line=~/\A\#[ \t]*undef[ \t]+([_A-Z]+)[ \t]*/) {
                $Constants{$Version}{$1}{"Access"} = "private";
            }
        }
        else
        {
            if(defined $ExtraDump)
            {
                if($Line=~/(\w+)\s*\(/)
                { # functions
                    $SymbolHeader{$Version}{$CurClass}{$1} = $CurHeader;
                }
                #elsif($Line=~/(\w+)\s*;/)
                #{ # data
                #    $SymbolHeader{$Version}{$CurClass}{$1} = $CurHeader;
                #}
                elsif($Line=~/(\A|\s)class\s+(\w+)/) {
                    $CurClass = $2;
                }
            }
        }
    }
    close(PREPROC);
    foreach my $Constant (keys(%{$Constants{$Version}}))
    {
        if($Constants{$Version}{$Constant}{"Access"} eq "private")
        {
            delete($Constants{$Version}{$Constant});
            next;
        }
        if(not $ExtraDump and ($Constant=~/_h\Z/i
        or isBuiltIn($Constants{$Version}{$Constant}{"Header"})))
        { # skip
            delete($Constants{$Version}{$Constant});
        }
        else {
            delete($Constants{$Version}{$Constant}{"Access"});
        }
    }
    if($Debug)
    {
        mkpath($DEBUG_PATH{$Version});
        copy($Path, $DEBUG_PATH{$Version}."/preprocessor.txt");
    }
}

sub uncoverConstant($$)
{
    my ($LibVersion, $Constant) = @_;
    return "" if(not $LibVersion or not $Constant);
    return $Constant if(isCyclical(\@RecurConstant, $Constant));
    if(defined $Cache{"uncoverConstant"}{$LibVersion}{$Constant}) {
        return $Cache{"uncoverConstant"}{$LibVersion}{$Constant};
    }
    
    if(defined $Constants{$LibVersion}{$Constant})
    {
        my $Value = $Constants{$LibVersion}{$Constant}{"Value"};
        if(defined $Constants{$LibVersion}{$Value})
        {
            push(@RecurConstant, $Constant);
            my $Uncovered = uncoverConstant($LibVersion, $Value);
            if($Uncovered ne "") {
                $Value = $Uncovered;
            }
            pop(@RecurConstant);
        }
        
        # FIXME: uncover $Value using all the enum constants
        # USE CASE: change of define NC_LONG from NC_INT (enum value) to NC_INT (define)
        return ($Cache{"uncoverConstant"}{$LibVersion}{$Constant} = $Value);
    }
    return ($Cache{"uncoverConstant"}{$LibVersion}{$Constant} = "");
}

sub simpleConstant($$)
{
    my ($LibVersion, $Value) = @_;
    if($Value=~/\W/)
    {
        my $Value_Copy = $Value;
        while($Value_Copy=~s/([a-z_]\w+)/\@/i)
        {
            my $Word = $1;
            if($Value!~/$Word\s*\(/)
            {
                my $Val = uncoverConstant($LibVersion, $Word);
                if($Val ne "")
                {
                    $Value=~s/\b$Word\b/$Val/g;
                }
            }
        }
    }
    return $Value;
}

sub computeValue($)
{
    my $Value = $_[0];
    
    if($Value=~/\A\((-?[\d]+)\)\Z/) {
        return $1;
    }
    
    if($Value=~/\A[\d\-\+()]+\Z/) {
        return eval($Value);
    }
    
    return $Value;
}

my %IgnoreConstant = map {$_=>1} (
    "VERSION",
    "VERSIONCODE",
    "VERNUM",
    "VERS_INFO",
    "PATCHLEVEL",
    "INSTALLPREFIX",
    "VBUILD",
    "VPATCH",
    "VMINOR",
    "BUILD_STRING",
    "BUILD_TIME",
    "PACKAGE_STRING",
    "PRODUCTION",
    "CONFIGURE_COMMAND",
    "INSTALLDIR",
    "BINDIR",
    "CONFIG_FILE_PATH",
    "DATADIR",
    "EXTENSION_DIR",
    "INCLUDE_PATH",
    "LIBDIR",
    "LOCALSTATEDIR",
    "SBINDIR",
    "SYSCONFDIR",
    "RELEASE",
    "SOURCE_ID",
    "SUBMINOR",
    "MINOR",
    "MINNOR",
    "MINORVERSION",
    "MAJOR",
    "MAJORVERSION",
    "MICRO",
    "MICROVERSION",
    "BINARY_AGE",
    "INTERFACE_AGE",
    "CORE_ABI",
    "PATCH",
    "COPYRIGHT",
    "TIMESTAMP",
    "REVISION",
    "PACKAGE_TAG",
    "PACKAGEDATE",
    "NUMVERSION",
    "Release",
    "Version"
);

sub constantFilter($$$)
{
    my ($Name, $Value, $Level) = @_;
    
    if($Level eq "Binary")
    {
        if($Name=~/_t\Z/)
        { # __malloc_ptr_t
            return 1;
        }
        foreach (keys(%IgnoreConstant))
        {
            if($Name=~/(\A|_)$_(_|\Z)/)
            { # version
                return 1;
            }
            if(/\A[A-Z].*[a-z]\Z/)
            {
                if($Name=~/(\A|[a-z])$_([A-Z]|\Z)/)
                { # version
                    return 1;
                }
            }
        }
        if($Name=~/(\A|_)(lib|open|)$TargetLibraryShortName(_|)(VERSION|VER|DATE|API|PREFIX)(_|\Z)/i)
        { # version
            return 1;
        }
        if($Value=~/\A('|"|)[\/\\]\w+([\/\\]|:|('|"|)\Z)/ or $Value=~/[\/\\]\w+[\/\\]\w+/)
        { # /lib64:/usr/lib64:/lib:/usr/lib:/usr/X11R6/lib/Xaw3d ...
            return 1;
        }
        
        if($Value=~/\A["'].*['"]/i)
        { # string
            return 0;
        }
        
        if($Value=~/\A[({]*\s*[a-z_]+\w*(\s+|[\|,])/i)
        { # static int gcry_pth_init
          # extern ABC
          # (RE_BACKSLASH_ESCAPE_IN_LISTS | RE...
          # { H5FD_MEM_SUPER, H5FD_MEM_SUPER, ...
            return 1;
        }
        if($Value=~/\w+\s*\(/i)
        { # foo(p)
            return 1;
        }
        if($Value=~/\A[a-z_]+\w*\Z/i)
        { # asn1_node_st
          # __SMTH_P
            return 1;
        }
    }
    
    return 0;
}

sub mergeConstants($)
{
    my $Level = $_[0];
    foreach my $Constant (keys(%{$Constants{1}}))
    {
        if($SkipConstants{1}{$Constant})
        { # skipped by the user
            next;
        }
        
        if(my $Header = $Constants{1}{$Constant}{"Header"})
        {
            if(not is_target_header($Header, 1)
            and not is_target_header($Header, 2))
            { # user-defined header
                next;
            }
        }
        else {
            next;
        }
        
        my $Old_Value = uncoverConstant(1, $Constant);
        
        if(constantFilter($Constant, $Old_Value, $Level))
        { # separate binary and source problems
            next;
        }
        
        if(not defined $Constants{2}{$Constant}{"Value"})
        { # removed
            %{$CompatProblems_Constants{$Level}{$Constant}{"Removed_Constant"}} = (
                "Target"=>$Constant,
                "Old_Value"=>$Old_Value  );
            next;
        }
        
        if($Constants{2}{$Constant}{"Value"} eq "")
        { # empty value
          # TODO: implement a rule
            next;
        }
        
        my $New_Value = uncoverConstant(2, $Constant);
        
        my $Old_Value_Pure = $Old_Value;
        my $New_Value_Pure = $New_Value;
        
        $Old_Value_Pure=~s/(\W)\s+/$1/g;
        $Old_Value_Pure=~s/\s+(\W)/$1/g;
        $New_Value_Pure=~s/(\W)\s+/$1/g;
        $New_Value_Pure=~s/\s+(\W)/$1/g;
        
        next if($New_Value_Pure eq "" or $Old_Value_Pure eq "");
        
        if($New_Value_Pure ne $Old_Value_Pure)
        { # different values
            if(simpleConstant(1, $Old_Value) eq simpleConstant(2, $New_Value))
            { # complex values
                next;
            }
            if(computeValue($Old_Value) eq computeValue($New_Value))
            { # expressions
                next;
            }
            if(convert_integer($Old_Value) eq convert_integer($New_Value))
            { # 0x0001 and 0x1, 0x1 and 1 equal constants
                next;
            }
            if($Old_Value eq "0" and $New_Value eq "NULL")
            { # 0 => NULL
                next;
            }
            if($Old_Value eq "NULL" and $New_Value eq "0")
            { # NULL => 0
                next;
            }
            %{$CompatProblems_Constants{$Level}{$Constant}{"Changed_Constant"}} = (
                "Target"=>$Constant,
                "Old_Value"=>$Old_Value,
                "New_Value"=>$New_Value  );
        }
    }
    
    foreach my $Constant (keys(%{$Constants{2}}))
    {
        if(not defined $Constants{1}{$Constant}{"Value"})
        {
            if($SkipConstants{2}{$Constant})
            { # skipped by the user
                next;
            }
            
            if(my $Header = $Constants{2}{$Constant}{"Header"})
            {
                if(not is_target_header($Header, 1)
                and not is_target_header($Header, 2))
                { # user-defined header
                    next;
                }
            }
            else {
                next;
            }
            
            my $New_Value = uncoverConstant(2, $Constant);
            if(not defined $New_Value or $New_Value eq "") {
                next;
            }
            
            if(constantFilter($Constant, $New_Value, $Level))
            { # separate binary and source problems
                next;
            }
            
            %{$CompatProblems_Constants{$Level}{$Constant}{"Added_Constant"}} = (
                "Target"=>$Constant,
                "New_Value"=>$New_Value  );
        }
    }
}

sub convert_integer($)
{
    my $Value = $_[0];
    if($Value=~/\A0x[a-f0-9]+\Z/)
    { # hexadecimal
        return hex($Value);
    }
    elsif($Value=~/\A0[0-7]+\Z/)
    { # octal
        return oct($Value);
    }
    elsif($Value=~/\A0b[0-1]+\Z/)
    { # binary
        return oct($Value);
    }
    else {
        return $Value;
    }
}

sub readSymbols($)
{
    my $LibVersion = $_[0];
    my @LibPaths = getSOPaths($LibVersion);
    if($#LibPaths==-1 and not $CheckHeadersOnly)
    {
        if($LibVersion==1)
        {
            printMsg("WARNING", "checking headers only");
            $CheckHeadersOnly = 1;
        }
        else {
            exitStatus("Error", "$SLIB_TYPE libraries are not found in ".$Descriptor{$LibVersion}{"Version"});
        }
    }
    
    foreach my $LibPath (@LibPaths) {
        readSymbols_Lib($LibVersion, $LibPath, 0, "+Weak", 1, 1);
    }
    
    if($CheckUndefined)
    {
        my %UndefinedLibs = ();
        
        my @Libs = (keys(%{$Library_Symbol{$LibVersion}}), keys(%{$DepLibrary_Symbol{$LibVersion}}));
        
        foreach my $LibName (sort @Libs)
        {
            if(defined $UndefinedSymbols{$LibVersion}{$LibName})
            {
                foreach my $Symbol (keys(%{$UndefinedSymbols{$LibVersion}{$LibName}}))
                {
                    if($Symbol_Library{$LibVersion}{$Symbol}
                    or $DepSymbol_Library{$LibVersion}{$Symbol})
                    { # exported by target library
                        next;
                    }
                    if(index($Symbol, '@')!=-1)
                    { # exported default symbol version (@@)
                        $Symbol=~s/\@/\@\@/;
                        if($Symbol_Library{$LibVersion}{$Symbol}
                        or $DepSymbol_Library{$LibVersion}{$Symbol}) {
                            next;
                        }
                    }
                    foreach my $Path (find_SymbolLibs($LibVersion, $Symbol)) {
                        $UndefinedLibs{$Path} = 1;
                    }
                }
            }
        }
        if($ExtraInfo)
        { # extra information for other tools
            if(my @Paths = sort keys(%UndefinedLibs))
            {
                my $LibString = "";
                my %Dirs = ();
                foreach (@Paths)
                {
                    $KnownLibs{$_} = 1;
                    my ($Dir, $Name) = separate_path($_);
                    
                    if(not grep {$Dir eq $_} (@{$SystemPaths{"lib"}})) {
                        $Dirs{esc($Dir)} = 1;
                    }
                    
                    $Name = parse_libname($Name, "name", $OStarget);
                    $Name=~s/\Alib//;
                    
                    $LibString .= " -l$Name";
                }
                
                foreach my $Dir (sort {$b cmp $a} keys(%Dirs))
                {
                    $LibString = " -L".esc($Dir).$LibString;
                }
                
                writeFile($ExtraInfo."/libs-string", $LibString);
            }
        }
    }
    
    if($ExtraInfo) {
        writeFile($ExtraInfo."/lib-paths", join("\n", sort keys(%KnownLibs)));
    }
    
    if(not $CheckHeadersOnly)
    {
        if($#LibPaths!=-1)
        {
            if(not keys(%{$Symbol_Library{$LibVersion}}))
            {
                printMsg("WARNING", "the set of public symbols in library(ies) is empty ($LibVersion)");
                printMsg("WARNING", "checking headers only");
                $CheckHeadersOnly = 1;
            }
        }
    }
    
   # clean memory
   %SystemObjects = ();
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
    my ($LibVersion, $Symbol) = @_;
    
    if(index($Symbol, "g_")==0 and $Symbol=~/[A-Z]/)
    { # debug symbols
        return ();
    }
    
    my %Paths = ();
    
    if(my $LibName = $Symbol_Lib_Map{$Symbol})
    {
        if(my $Path = get_LibPath($LibVersion, $LibName.".".$LIB_EXT)) {
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
                    if(my $Path = get_LibPath($LibVersion, $LibName.".".$LIB_EXT)) {
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
                        if(my $Path = get_LibPath($LibVersion, $LibName.".".$LIB_EXT)) {
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
                    if(my $Path = get_LibPath($LibVersion, "libc.$LIB_EXT")) {
                        $Paths{$Path} = 1;
                    }
                }
                else
                {
                    if(my $Path = get_LibPath_Prefix($LibVersion, $SymbolPrefix)) {
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

sub get_LibPath_Prefix($$)
{
    my ($LibVersion, $Prefix) = @_;
    
    $Prefix = lc($Prefix);
    $Prefix=~s/[_]+\Z//g;
    
    foreach ("-2", "2", "-1", "1", "")
    { # libgnome-2.so
      # libxml2.so
      # libdbus-1.so
        if(my $Path = get_LibPath($LibVersion, "lib".$Prefix.$_.".".$LIB_EXT)) {
            return $Path;
        }
    }
    return "";
}

sub getPrefix($)
{
    my $Str = $_[0];
    if($Str=~/\A([_]*[A-Z][a-z]{1,5})[A-Z]/)
    { # XmuValidArea: Xmu
        return $1;
    }
    elsif($Str=~/\A([_]*[a-z]+)[A-Z]/)
    { # snfReadFont: snf
        return $1;
    }
    elsif($Str=~/\A([_]*[A-Z]{2,})[A-Z][a-z]+([A-Z][a-z]+|\Z)/)
    { # XRRTimes: XRR
        return $1;
    }
    elsif($Str=~/\A([_]*[a-z]{1,2}\d+)[a-z\d]*_[a-z]+/i)
    { # H5HF_delete: H5
        return $1;
    }
    elsif($Str=~/\A([_]*[a-z0-9]{2,}_)[a-z]+/i)
    { # alarm_event_add: alarm_
        return $1;
    }
    elsif($Str=~/\A(([a-z])\2{1,})/i)
    { # ffopen
        return $1;
    }
    return "";
}

sub getSymbolSize($$)
{ # size from the shared library
    my ($Symbol, $LibVersion) = @_;
    return 0 if(not $Symbol);
    if(defined $Symbol_Library{$LibVersion}{$Symbol}
    and my $LibName = $Symbol_Library{$LibVersion}{$Symbol})
    {
        if(defined $Library_Symbol{$LibVersion}{$LibName}{$Symbol}
        and my $Size = $Library_Symbol{$LibVersion}{$LibName}{$Symbol})
        {
            if($Size<0) {
                return -$Size;
            }
        }
    }
    return 0;
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
            my ($ShortName, $FuncParams) = split_Signature($Name);
            
            foreach my $FParam (separate_Params($FuncParams, 0, 0))
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
            my ($ShortTmpl, $TmplParams) = template_Base($Name);
            
            my @TParams = separate_Params($TmplParams, 0, 0);
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

sub translateSymbols(@)
{
    my $LibVersion = pop(@_);
    my (@MnglNames1, @MnglNames2, @UnmangledNames) = ();
    foreach my $Symbol (sort @_)
    {
        if(index($Symbol, "_Z")==0)
        {
            next if($tr_name{$Symbol});
            $Symbol=~s/[\@\$]+(.*)\Z//;
            push(@MnglNames1, $Symbol);
        }
        elsif(index($Symbol, "?")==0)
        {
            next if($tr_name{$Symbol});
            push(@MnglNames2, $Symbol);
        }
        else
        { # not mangled
            $tr_name{$Symbol} = $Symbol;
            $mangled_name_gcc{$Symbol} = $Symbol;
            $mangled_name{$LibVersion}{$Symbol} = $Symbol;
        }
    }
    if($#MnglNames1 > -1)
    { # GCC names
        @UnmangledNames = reverse(unmangleArray(@MnglNames1));
        foreach my $MnglName (@MnglNames1)
        {
            if(my $Unmangled = pop(@UnmangledNames))
            {
                $tr_name{$MnglName} = canonifyName($Unmangled, "S");
                if(not $mangled_name_gcc{$tr_name{$MnglName}}) {
                    $mangled_name_gcc{$tr_name{$MnglName}} = $MnglName;
                }
                if(index($MnglName, "_ZTV")==0
                and $tr_name{$MnglName}=~/vtable for (.+)/)
                { # bind class name and v-table symbol
                    my $ClassName = $1;
                    $ClassVTable{$ClassName} = $MnglName;
                    $VTableClass{$MnglName} = $ClassName;
                }
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
                $tr_name{$MnglName} = formatName($Unmangled, "S");
                $mangled_name{$LibVersion}{$tr_name{$MnglName}} = $MnglName;
            }
        }
    }
    return \%tr_name;
}

sub link_symbol($$$)
{
    my ($Symbol, $RunWith, $Deps) = @_;
    if(link_symbol_internal($Symbol, $RunWith, \%Symbol_Library)) {
        return 1;
    }
    if($Deps eq "+Deps")
    { # check the dependencies
        if(link_symbol_internal($Symbol, $RunWith, \%DepSymbol_Library)) {
            return 1;
        }
    }
    return 0;
}

sub link_symbol_internal($$$)
{
    my ($Symbol, $RunWith, $Where) = @_;
    return 0 if(not $Where or not $Symbol);
    if($Where->{$RunWith}{$Symbol})
    { # the exact match by symbol name
        return 1;
    }
    if(my $VSym = $SymVer{$RunWith}{$Symbol})
    { # indirect symbol version, i.e.
      # foo_old and its symlink foo@v (or foo@@v)
      # foo_old may be in symtab table
        if($Where->{$RunWith}{$VSym}) {
            return 1;
        }
    }
    my ($Sym, $Spec, $Ver) = separate_symbol($Symbol);
    if($Sym and $Ver)
    { # search for the symbol with the same version
      # or without version
        if($Where->{$RunWith}{$Sym})
        { # old: foo@v|foo@@v
          # new: foo
            return 1;
        }
        if($Where->{$RunWith}{$Sym."\@".$Ver})
        { # old: foo|foo@@v
          # new: foo@v
            return 1;
        }
        if($Where->{$RunWith}{$Sym."\@\@".$Ver})
        { # old: foo|foo@v
          # new: foo@@v
            return 1;
        }
    }
    return 0;
}

sub readSymbols_App($)
{
    my $Path = $_[0];
    return () if(not $Path);
    my @Imported = ();
    if($OStarget eq "macos")
    {
        my $NM = get_CmdPath("nm");
        if(not $NM) {
            exitStatus("Not_Found", "can't find \"nm\"");
        }
        open(APP, "$NM -g \"$Path\" 2>\"$TMP_DIR/null\" |");
        while(<APP>)
        {
            if(/ U _([\w\$]+)\s*\Z/) {
                push(@Imported, $1);
            }
        }
        close(APP);
    }
    elsif($OStarget eq "windows")
    {
        my $DumpBinCmd = get_CmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin.exe\"");
        }
        open(APP, "$DumpBinCmd /IMPORTS \"$Path\" 2>\"$TMP_DIR/null\" |");
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
        my $ReadelfCmd = get_CmdPath("readelf");
        if(not $ReadelfCmd) {
            exitStatus("Not_Found", "can't find \"readelf\"");
        }
        open(APP, "$ReadelfCmd -Ws \"$Path\" 2>\"$TMP_DIR/null\" |");
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

my %ELF_BIND = map {$_=>1} (
    "WEAK",
    "GLOBAL"
);

my %ELF_TYPE = map {$_=>1} (
    "FUNC",
    "IFUNC",
    "OBJECT",
    "COMMON"
);

my %ELF_VIS = map {$_=>1} (
    "DEFAULT",
    "PROTECTED"
);

sub readline_ELF($)
{ # read the line of 'readelf' output corresponding to the symbol
    my @Info = split(/\s+/, $_[0]);
    #  Num:   Value      Size Type   Bind   Vis       Ndx  Name
    #  3629:  000b09c0   32   FUNC   GLOBAL DEFAULT   13   _ZNSt12__basic_fileIcED1Ev@@GLIBCXX_3.4
    #  135:   00000000    0   FUNC   GLOBAL DEFAULT   UND  av_image_fill_pointers@LIBAVUTIL_52 (3)
    shift(@Info); # spaces
    shift(@Info); # num
    
    if($#Info==7)
    { # UND SYMBOL (N)
        if($Info[7]=~/\(\d+\)/) {
            pop(@Info);
        }
    }
    
    if($#Info!=6)
    { # other lines
        return ();
    }
    return () if(not defined $ELF_TYPE{$Info[2]} and $Info[5] ne "UND");
    return () if(not defined $ELF_BIND{$Info[3]});
    return () if(not defined $ELF_VIS{$Info[4]});
    if($Info[5] eq "ABS" and $Info[0]=~/\A0+\Z/)
    { # 1272: 00000000     0 OBJECT  GLOBAL DEFAULT  ABS CXXABI_1.3
        return ();
    }
    if($OStarget eq "symbian")
    { # _ZN12CCTTokenType4NewLE4TUid3RFs@@ctfinder{000a0000}[102020e5].dll
        if(index($Info[6], "_._.absent_export_")!=-1)
        { # "_._.absent_export_111"@@libstdcpp{00010001}[10282872].dll
            return ();
        }
        $Info[6]=~s/\@.+//g; # remove version
    }
    if(index($Info[2], "0x") == 0)
    { # size == 0x3d158
        $Info[2] = hex($Info[2]);
    }
    return @Info;
}

sub get_LibPath($$)
{
    my ($LibVersion, $Name) = @_;
    return "" if(not $LibVersion or not $Name);
    if(defined $Cache{"get_LibPath"}{$LibVersion}{$Name}) {
        return $Cache{"get_LibPath"}{$LibVersion}{$Name};
    }
    return ($Cache{"get_LibPath"}{$LibVersion}{$Name} = get_LibPath_I($LibVersion, $Name));
}

sub get_LibPath_I($$)
{
    my ($LibVersion, $Name) = @_;
    if(is_abs($Name))
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
    if(defined $RegisteredObjects{$LibVersion}{$Name})
    { # registered paths
        return $RegisteredObjects{$LibVersion}{$Name};
    }
    if(defined $RegisteredSONAMEs{$LibVersion}{$Name})
    { # registered paths
        return $RegisteredSONAMEs{$LibVersion}{$Name};
    }
    if(my $DefaultPath = $DyLib_DefaultPath{$Name})
    { # ldconfig default paths
        return $DefaultPath;
    }
    foreach my $Dir (@DefaultLibPaths, @{$SystemPaths{"lib"}})
    { # search in default linker directories
      # and then in all system paths
        if(-f $Dir."/".$Name) {
            return join_P($Dir,$Name);
        }
    }
    if(not defined $Cache{"checkSystemFiles"}) {
        checkSystemFiles();
    }
    if(my @AllObjects = keys(%{$SystemObjects{$Name}})) {
        return $AllObjects[0];
    }
    if(my $ShortName = parse_libname($Name, "name+ext", $OStarget))
    {
        if($ShortName ne $Name)
        { # FIXME: check this case
            if(my $Path = get_LibPath($LibVersion, $ShortName)) {
                return $Path;
            }
        }
    }
    # can't find
    return "";
}

sub readSymbols_Lib($$$$$$)
{
    my ($LibVersion, $Lib_Path, $IsNeededLib, $Weak, $Deps, $Vers) = @_;
    return () if(not $LibVersion or not $Lib_Path);
    
    my $Real_Path = realpath($Lib_Path);
    
    if(not $Real_Path)
    { # broken link
        return ();
    }
    
    my $Lib_Name = get_filename($Real_Path);
    
    if($ExtraInfo)
    {
        $KnownLibs{$Real_Path} = 1;
        $KnownLibs{$Lib_Path} = 1; # links
    }
    
    if($IsNeededLib)
    {
        if($CheckedDyLib{$LibVersion}{$Lib_Name}) {
            return ();
        }
    }
    return () if(isCyclical(\@RecurLib, $Lib_Name) or $#RecurLib>=1);
    $CheckedDyLib{$LibVersion}{$Lib_Name} = 1;
    
    push(@RecurLib, $Lib_Name);
    my (%Value_Interface, %Interface_Value, %NeededLib) = ();
    my $Lib_ShortName = parse_libname($Lib_Name, "name+ext", $OStarget);
    
    if(not $IsNeededLib)
    { # special cases: libstdc++ and libc
        if(my $ShortName = parse_libname($Lib_Name, "short", $OStarget))
        {
            if($ShortName eq "libstdc++")
            { # libstdc++.so.6
                $STDCXX_TESTING = 1;
            }
            elsif($ShortName eq "libc")
            { # libc-2.11.3.so
                $GLIBC_TESTING = 1;
            }
        }
    }
    my $DebugPath = "";
    if($Debug and not $DumpSystem)
    { # debug mode
        $DebugPath = $DEBUG_PATH{$LibVersion}."/libs/".get_filename($Lib_Path).".txt";
        mkpath(get_dirname($DebugPath));
    }
    if($OStarget eq "macos")
    { # Mac OS X: *.dylib, *.a
        my $NM = get_CmdPath("nm");
        if(not $NM) {
            exitStatus("Not_Found", "can't find \"nm\"");
        }
        $NM .= " -g \"$Lib_Path\" 2>\"$TMP_DIR/null\"";
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
            if($CheckUndefined)
            {
                if(not $IsNeededLib)
                {
                    if(/ U _([\w\$]+)\s*\Z/)
                    {
                        $UndefinedSymbols{$LibVersion}{$Lib_Name}{$1} = 0;
                        next;
                    }
                }
            }
            
            if(/ [STD] _([\w\$]+)\s*\Z/)
            {
                my $Symbol = $1;
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObjects_Short{$LibVersion}{$Lib_ShortName})
                    {
                        $DepSymbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
                        $DepLibrary_Symbol{$LibVersion}{$Lib_Name}{$Symbol} = 1;
                    }
                }
                else
                {
                    $Symbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$Symbol} = 1;
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++")
                    {
                        if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                            setLanguage($LibVersion, "C++");
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps)
        {
            if($LIB_TYPE eq "dynamic")
            { # dependencies
                
                my $OtoolCmd = get_CmdPath("otool");
                if(not $OtoolCmd) {
                    exitStatus("Not_Found", "can't find \"otool\"");
                }
                
                open(LIB, "$OtoolCmd -L \"$Lib_Path\" 2>\"$TMP_DIR/null\" |");
                while(<LIB>)
                {
                    if(/\s*([\/\\].+\.$LIB_EXT)\s*/
                    and $1 ne $Lib_Path) {
                        $NeededLib{$1} = 1;
                    }
                }
                close(LIB);
            }
        }
    }
    elsif($OStarget eq "windows")
    { # Windows *.dll, *.lib
        my $DumpBinCmd = get_CmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin\"");
        }
        $DumpBinCmd .= " /EXPORTS \"".$Lib_Path."\" 2>$TMP_DIR/null";
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
        { # 1197 4AC 0000A620 SetThreadStackGuarantee
          # 1198 4AD          SetThreadToken (forwarded to ...)
          # 3368 _o2i_ECPublicKey
          # 1 0 00005B30 ??0?N = ... (with pdb)
            if(/\A\s*\d+\s+[a-f\d]+\s+[a-f\d]+\s+([\w\?\@]+)\s*(?:=.+)?\Z/i
            or /\A\s*\d+\s+[a-f\d]+\s+([\w\?\@]+)\s*\(\s*forwarded\s+/
            or /\A\s*\d+\s+_([\w\?\@]+)\s*(?:=.+)?\Z/)
            { # dynamic, static and forwarded symbols
                my $realname = $1;
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObjects_Short{$LibVersion}{$Lib_ShortName})
                    {
                        $DepSymbol_Library{$LibVersion}{$realname} = $Lib_Name;
                        $DepLibrary_Symbol{$LibVersion}{$Lib_Name}{$realname} = 1;
                    }
                }
                else
                {
                    $Symbol_Library{$LibVersion}{$realname} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$realname} = 1;
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++")
                    {
                        if(index($realname, "_Z")==0 or index($realname, "?")==0) {
                            setLanguage($LibVersion, "C++");
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps)
        {
            if($LIB_TYPE eq "dynamic")
            { # dependencies
                open(LIB, "$DumpBinCmd /DEPENDENTS \"$Lib_Path\" 2>\"$TMP_DIR/null\" |");
                while(<LIB>)
                {
                    if(/\s*([^\s]+?\.$LIB_EXT)\s*/i
                    and $1 ne $Lib_Path) {
                        $NeededLib{path_format($1, $OSgroup)} = 1;
                    }
                }
                close(LIB);
            }
        }
    }
    else
    { # Unix; *.so, *.a
      # Symbian: *.dso, *.lib
        my $ReadelfCmd = get_CmdPath("readelf");
        if(not $ReadelfCmd) {
            exitStatus("Not_Found", "can't find \"readelf\"");
        }
        my $Cmd = $ReadelfCmd." -Ws \"$Lib_Path\" 2>\"$TMP_DIR/null\"";
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
            if($LIB_TYPE eq "dynamic")
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
                    if($CheckUndefined)
                    {
                        if(not $IsNeededLib) {
                            $UndefinedSymbols{$LibVersion}{$Lib_Name}{$Symbol} = 0;
                        }
                    }
                    next;
                }
                if($Bind eq "WEAK")
                {
                    $WeakSymbols{$LibVersion}{$Symbol} = 1;
                    if($Weak eq "-Weak")
                    { # skip WEAK symbols
                        next;
                    }
                }
                my $Short = $Symbol;
                $Short=~s/\@.+//g;
                if($Type eq "OBJECT")
                { # global data
                    $GlobalDataObject{$LibVersion}{$Symbol} = $Size;
                    $GlobalDataObject{$LibVersion}{$Short} = $Size;
                }
                if($IsNeededLib)
                {
                    if(not defined $RegisteredObjects_Short{$LibVersion}{$Lib_ShortName})
                    {
                        $DepSymbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
                        $DepLibrary_Symbol{$LibVersion}{$Lib_Name}{$Symbol} = ($Type eq "OBJECT")?-$Size:1;
                    }
                }
                else
                {
                    $Symbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$Symbol} = ($Type eq "OBJECT")?-$Size:1;
                    if($Vers)
                    {
                        if($LIB_EXT eq "so")
                        { # value
                            $Interface_Value{$LibVersion}{$Symbol} = $Value;
                            $Value_Interface{$LibVersion}{$Value}{$Symbol} = 1;
                        }
                    }
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++")
                    {
                        if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                            setLanguage($LibVersion, "C++");
                        }
                    }
                }
            }
        }
        close(LIB);
        
        if($Deps and $LIB_TYPE eq "dynamic")
        { # dynamic library specifics
            $Cmd = $ReadelfCmd." -Wd \"$Lib_Path\" 2>\"$TMP_DIR/null\"";
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
        if(not $IsNeededLib and $LIB_EXT eq "so")
        { # get symbol versions
            my %Found = ();
            
            # by value
            foreach my $Symbol (keys(%{$Library_Symbol{$LibVersion}{$Lib_Name}}))
            {
                next if(index($Symbol,"\@")==-1);
                if(my $Value = $Interface_Value{$LibVersion}{$Symbol})
                {
                    foreach my $Symbol_SameValue (keys(%{$Value_Interface{$LibVersion}{$Value}}))
                    {
                        if($Symbol_SameValue ne $Symbol
                        and index($Symbol_SameValue,"\@")==-1)
                        {
                            $SymVer{$LibVersion}{$Symbol_SameValue} = $Symbol;
                            $Found{$Symbol} = 1;
                            last;
                        }
                    }
                }
            }
            
            # default
            foreach my $Symbol (keys(%{$Library_Symbol{$LibVersion}{$Lib_Name}}))
            {
                next if(defined $Found{$Symbol});
                next if(index($Symbol,"\@\@")==-1);
                
                if($Symbol=~/\A([^\@]*)\@\@/
                and not $SymVer{$LibVersion}{$1})
                {
                    $SymVer{$LibVersion}{$1} = $Symbol;
                    $Found{$Symbol} = 1;
                }
            }
            
            # non-default
            foreach my $Symbol (keys(%{$Library_Symbol{$LibVersion}{$Lib_Name}}))
            {
                next if(defined $Found{$Symbol});
                next if(index($Symbol,"\@")==-1);
                
                if($Symbol=~/\A([^\@]*)\@([^\@]*)/
                and not $SymVer{$LibVersion}{$1})
                {
                    $SymVer{$LibVersion}{$1} = $Symbol;
                    $Found{$Symbol} = 1;
                }
            }
        }
    }
    if($Deps)
    {
        foreach my $DyLib (sort keys(%NeededLib))
        {
            $Library_Needed{$LibVersion}{$Lib_Name}{get_filename($DyLib)} = 1;
            
            if(my $DepPath = get_LibPath($LibVersion, $DyLib))
            {
                if(not $CheckedDyLib{$LibVersion}{get_filename($DepPath)}) {
                    readSymbols_Lib($LibVersion, $DepPath, 1, "+Weak", $Deps, $Vers);
                }
            }
        }
    }
    pop(@RecurLib);
    return $Library_Symbol{$LibVersion};
}

sub get_prefixes($)
{
    my %Prefixes = ();
    get_prefixes_I([$_[0]], \%Prefixes);
    return keys(%Prefixes);
}

sub get_prefixes_I($$)
{
    foreach my $P (@{$_[0]})
    {
        my @Parts = reverse(split(/[\/\\]+/, $P));
        my $Name = $Parts[0];
        foreach (1 .. $#Parts)
        {
            $_[1]->{$Name}{$P} = 1;
            last if($_>4 or $Parts[$_] eq "include");
            $Name = $Parts[$_].$SLASH.$Name;
        }
    }
}

sub checkSystemFiles()
{
    $Cache{"checkSystemFiles"} = 1;
    
    my @SysHeaders = ();
    
    foreach my $DevelPath (@{$SystemPaths{"lib"}})
    {
        next if(not -d $DevelPath);
        
        my @Files = cmd_find($DevelPath,"f");
        foreach my $Link (cmd_find($DevelPath,"l"))
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
        my @Libs = grep { /\.$LIB_EXT[0-9.]*\Z/ } @Files;
        foreach my $Path (@Libs)
        {
            my $N = get_filename($Path);
            $SystemObjects{$N}{$Path} = 1;
            $SystemObjects{parse_libname($N, "name+ext", $OStarget)}{$Path} = 1;
        }
    }
    
    foreach my $DevelPath (@{$SystemPaths{"include"}})
    {
        next if(not -d $DevelPath);
        # search for all header files in the /usr/include
        # with or without extension (ncurses.h, QtCore, ...)
        push(@SysHeaders, cmd_find($DevelPath,"f"));
        foreach my $Link (cmd_find($DevelPath,"l"))
        { # add symbolic links
            if(-f $Link) {
                push(@SysHeaders, $Link);
            }
        }
    }
    get_prefixes_I(\@SysHeaders, \%SystemHeaders);
}

sub getSOPaths($)
{
    my $LibVersion = $_[0];
    my @Paths = ();
    foreach my $Dest (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Libs"}))
    {
        if(not -e $Dest) {
            exitStatus("Access_Error", "can't access \'$Dest\'");
        }
        $Dest = get_abs_path($Dest);
        my @SoPaths_Dest = getSOPaths_Dest($Dest, $LibVersion);
        foreach (@SoPaths_Dest) {
            push(@Paths, $_);
        }
    }
    return sort @Paths;
}

sub skipLib($$)
{
    my ($Path, $LibVersion) = @_;
    return 1 if(not $Path or not $LibVersion);
    my $Name = get_filename($Path);
    if($SkipLibs{$LibVersion}{"Name"}{$Name}) {
        return 1;
    }
    my $ShortName = parse_libname($Name, "name+ext", $OStarget);
    if($SkipLibs{$LibVersion}{"Name"}{$ShortName}) {
        return 1;
    }
    foreach my $Dir (keys(%{$SkipLibs{$LibVersion}{"Path"}}))
    {
        if($Path=~/\Q$Dir\E([\/\\]|\Z)/) {
            return 1;
        }
    }
    foreach my $P (keys(%{$SkipLibs{$LibVersion}{"Pattern"}}))
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

sub specificHeader($$)
{
    my ($Header, $Spec) = @_;
    my $Name = get_filename($Header);
    
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
    my $Name = get_filename($Path);
    my $Dir = get_dirname($Path);
    
    if($Tolerance=~/2/)
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
    
    if($Tolerance=~/1/)
    { # 1 - skip non-Linux headers
        if($OSgroup ne "windows")
        {
            if(specificHeader($Path, "windows")) {
                return 1;
            }
        }
        if($OSgroup ne "macos")
        {
            if(specificHeader($Path, "macos")) {
                return 1;
            }
        }
    }
    
    # valid
    return 0;
}

sub skipHeader($$)
{
    my ($Path, $LibVersion) = @_;
    return 1 if(not $Path or not $LibVersion);
    if(defined $Cache{"skipHeader"}{$Path}) {
        return $Cache{"skipHeader"}{$Path};
    }
    if(defined $Tolerance and $Tolerance=~/1|2/)
    { # --tolerant
        if(skipAlienHeader($Path)) {
            return ($Cache{"skipHeader"}{$Path} = 1);
        }
    }
    if(not keys(%{$SkipHeaders{$LibVersion}})) {
        return 0;
    }
    return ($Cache{"skipHeader"}{$Path} = skipHeader_I(@_));
}

sub skipHeader_I($$)
{ # returns:
  #  1 - if header should NOT be included and checked
  #  2 - if header should NOT be included, but should be checked
    my ($Path, $LibVersion) = @_;
    my $Name = get_filename($Path);
    if(my $Kind = $SkipHeaders{$LibVersion}{"Name"}{$Name}) {
        return $Kind;
    }
    foreach my $D (sort {$SkipHeaders{$LibVersion}{"Path"}{$a} cmp $SkipHeaders{$LibVersion}{"Path"}{$b}}
    keys(%{$SkipHeaders{$LibVersion}{"Path"}}))
    {
        if(index($Path, $D)!=-1)
        {
            if($Path=~/\Q$D\E([\/\\]|\Z)/) {
                return $SkipHeaders{$LibVersion}{"Path"}{$D};
            }
        }
    }
    foreach my $P (sort {$SkipHeaders{$LibVersion}{"Pattern"}{$a} cmp $SkipHeaders{$LibVersion}{"Pattern"}{$b}}
    keys(%{$SkipHeaders{$LibVersion}{"Pattern"}}))
    {
        if(my $Kind = $SkipHeaders{$LibVersion}{"Pattern"}{$P})
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

sub registerObject_Dir($$)
{
    my ($Dir, $LibVersion) = @_;
    if(grep {$_ eq $Dir} @{$SystemPaths{"lib"}})
    { # system directory
        return;
    }
    if($RegisteredObject_Dirs{$LibVersion}{$Dir})
    { # already registered
        return;
    }
    foreach my $Path (find_libs($Dir,"",1))
    {
        next if(ignore_path($Path));
        next if(skipLib($Path, $LibVersion));
        registerObject($Path, $LibVersion);
    }
    $RegisteredObject_Dirs{$LibVersion}{$Dir} = 1;
}

sub registerObject($$)
{
    my ($Path, $LibVersion) = @_;
    
    my $Name = get_filename($Path);
    $RegisteredObjects{$LibVersion}{$Name} = $Path;
    if($OStarget=~/linux|bsd|gnu/i)
    {
        if(my $SONAME = getSONAME($Path)) {
            $RegisteredSONAMEs{$LibVersion}{$SONAME} = $Path;
        }
    }
    if(my $Short = parse_libname($Name, "name+ext", $OStarget)) {
        $RegisteredObjects_Short{$LibVersion}{$Short} = $Path;
    }
    
    if(not $CheckedArch{$LibVersion} and -f $Path)
    {
        if(my $ObjArch = getArch_Object($Path))
        {
            if($ObjArch ne getArch_GCC($LibVersion))
            { # translation unit dump generated by the GCC compiler should correspond to the input objects
                $CheckedArch{$LibVersion} = 1;
                printMsg("WARNING", "the architectures of input objects and the used GCC compiler are not equal, please change the compiler by --gcc-path=PATH option.");
            }
        }
    }
}

sub getArch_Object($)
{
    my $Path = $_[0];
    
    my %MachineType = (
        "14C" => "x86",
        "8664" => "x86_64",
        "1C0" => "arm",
        "200" => "ia64"
    );
    
    my %ArchName = (
        "s390:31-bit" => "s390",
        "s390:64-bit" => "s390x",
        "powerpc:common" => "ppc32",
        "powerpc:common64" => "ppc64",
        "i386:x86-64" => "x86_64",
        "mips:3000" => "mips",
        "sparc:v8plus" => "sparcv9"
    );
    
    if($OStarget eq "windows")
    {
        my $DumpbinCmd = get_CmdPath("dumpbin");
        if(not $DumpbinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin\"");
        }
        
        my $Cmd = $DumpbinCmd." /headers \"$Path\"";
        my $Out = `$Cmd`;
        
        if($Out=~/(\w+)\smachine/)
        {
            if(my $Type = $MachineType{uc($1)})
            {
                return $Type;
            }
        }
    }
    elsif($OStarget=~/linux|bsd|gnu/)
    {
        my $ObjdumpCmd = get_CmdPath("objdump");
        if(not $ObjdumpCmd) {
            exitStatus("Not_Found", "can't find \"objdump\"");
        }
        
        my $Cmd = $ObjdumpCmd." -f \"$Path\"";
        
        if($OSgroup eq "windows") {
            $Cmd = "set LANG=$LOCALE & ".$Cmd;
        }
        else {
            $Cmd = "LANG=$LOCALE ".$Cmd;
        }
        my $Out = `$Cmd`;
        
        if($Out=~/architecture:\s+([\w\-\:]+)/)
        {
            my $Arch = $1;
            if($Arch=~s/\:(.+)//)
            {
                my $Suffix = $1;
                
                if(my $Name = $ArchName{$Arch.":".$Suffix})
                {
                    $Arch = $Name;
                }
            }
            
            if($Arch=~/i[3-6]86/) {
                $Arch = "x86";
            }
            
            if($Arch eq "x86-64") {
                $Arch = "x86_64";
            }
            
            if($Arch eq "ia64-elf64") {
                $Arch = "ia64";
            }
            
            return $Arch;
        }
    }
    elsif($OStarget=~/macos/)
    {
        my $OtoolCmd = get_CmdPath("otool");
        if(not $OtoolCmd) {
            exitStatus("Not_Found", "can't find \"otool\"");
        }
        
        my $Cmd = $OtoolCmd." -hv -arch all \"$Path\"";
        my $Out = qx/$Cmd/;
        
        if($Out=~/X86_64/i) {
            return "x86_64";
        }
        elsif($Out=~/X86/i) {
            return "x86";
        }
    }
    else
    {
        exitStatus("Error", "Not implemented yet");
        # TODO
    }
    
    return undef;
}

sub getSONAME($)
{
    my $Path = $_[0];
    return if(not $Path);
    if(defined $Cache{"getSONAME"}{$Path}) {
        return $Cache{"getSONAME"}{$Path};
    }
    my $ObjdumpCmd = get_CmdPath("objdump");
    if(not $ObjdumpCmd) {
        exitStatus("Not_Found", "can't find \"objdump\"");
    }
    my $SonameCmd = "$ObjdumpCmd -x \"$Path\" 2>$TMP_DIR/null";
    if($OSgroup eq "windows") {
        $SonameCmd .= " | find \"SONAME\"";
    }
    else {
        $SonameCmd .= " | grep SONAME";
    }
    if(my $SonameInfo = `$SonameCmd`)
    {
        if($SonameInfo=~/SONAME\s+([^\s]+)/) {
            return ($Cache{"getSONAME"}{$Path} = $1);
        }
    }
    return ($Cache{"getSONAME"}{$Path}="");
}

sub getSOPaths_Dest($$)
{
    my ($Dest, $LibVersion) = @_;
    if(skipLib($Dest, $LibVersion)) {
        return ();
    }
    if(-f $Dest)
    {
        if(not parse_libname($Dest, "name", $OStarget)) {
            exitStatus("Error", "incorrect format of library (should be *.$LIB_EXT): \'$Dest\'");
        }
        registerObject($Dest, $LibVersion);
        registerObject_Dir(get_dirname($Dest), $LibVersion);
        return ($Dest);
    }
    elsif(-d $Dest)
    {
        $Dest=~s/[\/\\]+\Z//g;
        my %Libs = ();
        if(grep { $Dest eq $_ } @{$SystemPaths{"lib"}})
        { # you have specified /usr/lib as the search directory (<libs>) in the XML descriptor
          # and the real name of the library by -l option (bz2, stdc++, Xaw, ...)
            foreach my $Path (cmd_find($Dest,"","*".esc($TargetLibraryName)."*.$LIB_EXT*",2))
            { # all files and symlinks that match the name of a library
                if(get_filename($Path)=~/\A(|lib)\Q$TargetLibraryName\E[\d\-]*\.$LIB_EXT[\d\.]*\Z/i)
                {
                    registerObject($Path, $LibVersion);
                    $Libs{realpath($Path)}=1;
                }
            }
        }
        else
        { # search for all files and symlinks
            foreach my $Path (find_libs($Dest,"",""))
            {
                next if(ignore_path($Path));
                next if(skipLib($Path, $LibVersion));
                registerObject($Path, $LibVersion);
                $Libs{realpath($Path)}=1;
            }
            if($OSgroup eq "macos")
            { # shared libraries on MacOS X may have no extension
                foreach my $Path (cmd_find($Dest,"f"))
                {
                    next if(ignore_path($Path));
                    next if(skipLib($Path, $LibVersion));
                    if(get_filename($Path)!~/\./
                    and cmd_file($Path)=~/(shared|dynamic)\s+library/i)
                    {
                        registerObject($Path, $LibVersion);
                        $Libs{realpath($Path)}=1;
                    }
                }
            }
        }
        return keys(%Libs);
    }
    else {
        return ();
    }
}

sub isCyclical($$)
{
    my ($Stack, $Value) = @_;
    return (grep {$_ eq $Value} @{$Stack});
}

sub getGCC_Opts($)
{ # to use in module
    my $LibVersion = $_[0];
    
    my @Opts = ();
    
    if($CompilerOptions{$LibVersion})
    { # user-defined options
        push(@Opts, $CompilerOptions{$LibVersion});
    }
    if($GccOptions)
    { # additional
        push(@Opts, $GccOptions);
    }
    
    if(@Opts) {
        return join(" ", @Opts);
    }
    
    return undef;
}

sub getArch_GCC($)
{
    my $LibVersion = $_[0];
    
    if(defined $Cache{"getArch_GCC"}{$LibVersion}) {
        return $Cache{"getArch_GCC"}{$LibVersion};
    }
    
    if(not $GCC_PATH) {
        return undef;
    }
    
    my $Arch = undef;
    
    if(my $Target = get_dumpmachine($GCC_PATH))
    {
        if($Target=~/x86_64/) {
            $Arch = "x86_64";
        }
        elsif($Target=~/i[3-6]86/) {
            $Arch = "x86";
        }
        elsif($Target=~/\Aarm/i) {
            $Arch = "arm";
        }
    }
    
    if(not $Arch)
    {
        writeFile("$TMP_DIR/test.c", "int main(){return 0;}\n");
        
        my $Cmd = $GCC_PATH." test.c -o test";
        if(my $Opts = getGCC_Opts($LibVersion))
        { # user-defined options
            $Cmd .= " ".$Opts;
        }
        
        chdir($TMP_DIR);
        system($Cmd);
        chdir($ORIG_DIR);
        
        $Arch = getArch_Object("$TMP_DIR/test");
        
        unlink("$TMP_DIR/test.c");
        unlink("$TMP_DIR/test");
    }
    
    if(not $Arch) {
        exitStatus("Error", "can't check ARCH type");
    }
    
    return ($Cache{"getArch_GCC"}{$LibVersion} = $Arch);
}

sub detectWordSize($)
{
    my $LibVersion = $_[0];
    
    my $Size = undef;
    
    # speed up detection
    if(my $Arch = getArch($LibVersion))
    {
        if($Arch=~/\A(x86_64|s390x|ppc64|ia64|alpha)\Z/) {
            $Size = "8";
        }
        elsif($Arch=~/\A(x86|s390|ppc32)\Z/) {
            $Size = "4";
        }
    }
    
    if($GCC_PATH)
    {
        writeFile("$TMP_DIR/empty.h", "");
        
        my $Cmd = $GCC_PATH." -E -dD empty.h";
        if(my $Opts = getGCC_Opts($LibVersion))
        { # user-defined options
            $Cmd .= " ".$Opts;
        }
        
        chdir($TMP_DIR);
        my $Defines = `$Cmd`;
        chdir($ORIG_DIR);
        
        unlink("$TMP_DIR/empty.h");
        
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

sub getWordSize($)
{ # to use in module
    return $WORD_SIZE{$_[0]};
}

sub majorVersion($)
{
    my $V = $_[0];
    return 0 if(not $V);
    my @VParts = split(/\./, $V);
    return $VParts[0];
}

sub cmpVersions($$)
{ # compare two versions in dotted-numeric format
    my ($V1, $V2) = @_;
    return 0 if($V1 eq $V2);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++)
    {
        return -1 if(int($V1Parts[$i]) < int($V2Parts[$i]));
        return 1 if(int($V1Parts[$i]) > int($V2Parts[$i]));
    }
    return -1 if($#V1Parts < $#V2Parts);
    return 1 if($#V1Parts > $#V2Parts);
    return 0;
}

sub read_ABI_Dump($$)
{
    my ($LibVersion, $Path) = @_;
    return if(not $LibVersion or not -e $Path);
    my $FilePath = "";
    if(isDump_U($Path))
    { # input *.abi
        $FilePath = $Path;
    }
    else
    { # input *.abi.tar.gz
        $FilePath = unpackDump($Path);
        if(not isDump_U($FilePath)) {
            exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
        }
    }
    
    my $ABI = {};
    
    my $Line = readLineNum($FilePath, 0);
    if($Line=~/xml/)
    { # XML format
        loadModule("XmlDump");
        $ABI = readXmlDump($FilePath);
    }
    else
    { # Perl Data::Dumper format (default)
        open(DUMP, $FilePath);
        local $/ = undef;
        my $Content = <DUMP>;
        close(DUMP);
        
        if(get_dirname($FilePath) eq $TMP_DIR."/unpack")
        { # remove temp file
            unlink($FilePath);
        }
        if($Content!~/};\s*\Z/) {
            exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
        }
        $ABI = eval($Content);
        if(not $ABI) {
            exitStatus("Error", "internal error - eval() procedure seem to not working correctly, try to remove 'use strict' and try again");
        }
    }
    # new dumps (>=1.22) have a personal versioning
    my $DVersion = $ABI->{"ABI_DUMP_VERSION"};
    my $ToolVersion = $ABI->{"ABI_COMPLIANCE_CHECKER_VERSION"};
    if(not $DVersion)
    { # old dumps (<=1.21.6) have been marked by the tool version
        $DVersion = $ToolVersion;
    }
    $UsedDump{$LibVersion}{"V"} = $DVersion;
    $UsedDump{$LibVersion}{"M"} = $ABI->{"LibraryName"};
    
    if($ABI->{"PublicABI"}) {
        $UsedDump{$LibVersion}{"Public"} = 1;
    }
    
    if($ABI->{"ABI_DUMP_VERSION"})
    {
        if(cmpVersions($DVersion, $ABI_DUMP_VERSION)>0)
        { # Don't know how to parse future dump formats
            exitStatus("Dump_Version", "incompatible version \'$DVersion\' of specified ABI dump (newer than $ABI_DUMP_VERSION)");
        }
    }
    else
    { # support for old ABI dumps
        if(cmpVersions($DVersion, $TOOL_VERSION)>0)
        { # Don't know how to parse future dump formats
            exitStatus("Dump_Version", "incompatible version \'$DVersion\' of specified ABI dump (newer than $TOOL_VERSION)");
        }
    }
    
    if(majorVersion($DVersion)<2)
    {
        exitStatus("Dump_Version", "incompatible version \'$DVersion\' of specified ABI dump (allowed only 2.0<=V<=$ABI_DUMP_VERSION)");
    }
    
    if(defined $ABI->{"ABI_DUMPER_VERSION"})
    { # DWARF ABI Dump
        $UseConv_Real{$LibVersion}{"P"} = 1;
        $UseConv_Real{$LibVersion}{"R"} = 0; # not implemented yet
        
        $UsedDump{$LibVersion}{"DWARF"} = 1;
        
        if(not $TargetComponent_Opt)
        {
            if($ABI->{"LibraryName"}=~/\.ko[\.\d]*\Z/) {
                $TargetComponent = "module";
            }
            else {
                $TargetComponent = "object";
            }
        }
    }
    
    if(not checkDump($LibVersion, "2.11"))
    { # old ABI dumps
        $UsedDump{$LibVersion}{"BinOnly"} = 1;
    }
    elsif($ABI->{"BinOnly"})
    { # ABI dump created with --binary option
        $UsedDump{$LibVersion}{"BinOnly"} = 1;
    }
    else
    { # default
        $UsedDump{$LibVersion}{"SrcBin"} = 1;
    }
    
    if(defined $ABI->{"Mode"}
    and $ABI->{"Mode"} eq "Extended")
    { # --ext option
        $ExtendedCheck = 1;
    }
    if($ABI->{"Extra"}) {
        $ExtraDump = 1;
    }
    
    if(my $Lang = $ABI->{"Language"})
    {
        $UsedDump{$LibVersion}{"L"} = $Lang;
        setLanguage($LibVersion, $Lang);
    }
    if(checkDump($LibVersion, "2.15")) {
        $TypeInfo{$LibVersion} = $ABI->{"TypeInfo"};
    }
    else
    { # support for old ABI dumps
        my $TInfo = $ABI->{"TypeInfo"};
        if(not $TInfo)
        { # support for older ABI dumps
            $TInfo = $ABI->{"TypeDescr"};
        }
        my %Tid_TDid = ();
        foreach my $TDid (keys(%{$TInfo}))
        {
            foreach my $Tid (keys(%{$TInfo->{$TDid}}))
            {
                $MAX_ID = $Tid if($Tid>$MAX_ID);
                $MAX_ID = $TDid if($TDid and $TDid>$MAX_ID);
                $Tid_TDid{$Tid}{$TDid} = 1;
            }
        }
        my %NewID = ();
        foreach my $Tid (keys(%Tid_TDid))
        {
            my @TDids = keys(%{$Tid_TDid{$Tid}});
            if($#TDids>=1)
            {
                foreach my $TDid (@TDids)
                {
                    if($TDid) {
                        %{$TypeInfo{$LibVersion}{$Tid}} = %{$TInfo->{$TDid}{$Tid}};
                    }
                    else
                    {
                        my $ID = ++$MAX_ID;
                        
                        $NewID{$TDid}{$Tid} = $ID;
                        %{$TypeInfo{$LibVersion}{$ID}} = %{$TInfo->{$TDid}{$Tid}};
                        $TypeInfo{$LibVersion}{$ID}{"Tid"} = $ID;
                    }
                }
            }
            else
            {
                my $TDid = $TDids[0];
                %{$TypeInfo{$LibVersion}{$Tid}} = %{$TInfo->{$TDid}{$Tid}};
            }
        }
        foreach my $Tid (keys(%{$TypeInfo{$LibVersion}}))
        {
            my %Info = %{$TypeInfo{$LibVersion}{$Tid}};
            if(defined $Info{"BaseType"})
            {
                my $Bid = $Info{"BaseType"}{"Tid"};
                my $BDid = $Info{"BaseType"}{"TDid"};
                $BDid="" if(not defined $BDid);
                delete($TypeInfo{$LibVersion}{$Tid}{"BaseType"}{"TDid"});
                if(defined $NewID{$BDid} and my $ID = $NewID{$BDid}{$Bid}) {
                    $TypeInfo{$LibVersion}{$Tid}{"BaseType"} = $ID;
                }
            }
            delete($TypeInfo{$LibVersion}{$Tid}{"TDid"});
        }
    }
    read_Machine_DumpInfo($ABI, $LibVersion);
    $SymbolInfo{$LibVersion} = $ABI->{"SymbolInfo"};
    if(not $SymbolInfo{$LibVersion})
    { # support for old dumps
        $SymbolInfo{$LibVersion} = $ABI->{"FuncDescr"};
    }
    if(not keys(%{$SymbolInfo{$LibVersion}}))
    { # validation of old-version dumps
        if(not $ExtendedCheck) {
            exitStatus("Invalid_Dump", "the input dump d$LibVersion is invalid");
        }
    }
    if(checkDump($LibVersion, "2.15")) {
        $DepLibrary_Symbol{$LibVersion} = $ABI->{"DepSymbols"};
    }
    else
    { # support for old ABI dumps
        my $DepSymbols = $ABI->{"DepSymbols"};
        if(not $DepSymbols) {
            $DepSymbols = $ABI->{"DepInterfaces"};
        }
        if(not $DepSymbols)
        { # Cannot reconstruct DepSymbols. This may result in false
          # positives if the old dump is for library 2. Not a problem if
          # old dumps are only from old libraries.
            $DepSymbols = {};
        }
        foreach my $Symbol (keys(%{$DepSymbols})) {
            $DepSymbol_Library{$LibVersion}{$Symbol} = 1;
        }
    }
    $SymVer{$LibVersion} = $ABI->{"SymbolVersion"};
    
    if(my $V = $TargetVersion{$LibVersion}) {
        $Descriptor{$LibVersion}{"Version"} = $V;
    }
    else {
        $Descriptor{$LibVersion}{"Version"} = $ABI->{"LibraryVersion"};
    }
    
    if(not $SkipTypes{$LibVersion})
    { # if not defined by -skip-types option
        if(defined $ABI->{"SkipTypes"})
        {
            foreach my $TName (keys(%{$ABI->{"SkipTypes"}}))
            {
                $SkipTypes{$LibVersion}{$TName} = 1;
            }
        }
        if(defined $ABI->{"OpaqueTypes"})
        { # support for old dumps
            foreach my $TName (keys(%{$ABI->{"OpaqueTypes"}}))
            {
                $SkipTypes{$LibVersion}{$TName} = 1;
            }
        }
    }
    
    if(not $SkipSymbols{$LibVersion})
    { # if not defined by -skip-symbols option
        $SkipSymbols{$LibVersion} = $ABI->{"SkipSymbols"};
        if(not $SkipSymbols{$LibVersion})
        { # support for old dumps
            $SkipSymbols{$LibVersion} = $ABI->{"SkipInterfaces"};
        }
        if(not $SkipSymbols{$LibVersion})
        { # support for old dumps
            $SkipSymbols{$LibVersion} = $ABI->{"InternalInterfaces"};
        }
    }
    $SkipNameSpaces{$LibVersion} = $ABI->{"SkipNameSpaces"};
    
    if(not $TargetHeaders{$LibVersion})
    { # if not defined by -headers-list option
        $TargetHeaders{$LibVersion} = $ABI->{"TargetHeaders"};
    }
    
    foreach my $Path (keys(%{$ABI->{"SkipHeaders"}}))
    {
        $SkipHeadersList{$LibVersion}{$Path} = $ABI->{"SkipHeaders"}{$Path};
        
        my ($CPath, $Type) = classifyPath($Path);
        $SkipHeaders{$LibVersion}{$Type}{$CPath} = $ABI->{"SkipHeaders"}{$Path};
    }
    
    read_Source_DumpInfo($ABI, $LibVersion);
    read_Libs_DumpInfo($ABI, $LibVersion);
    
    if(not checkDump($LibVersion, "2.10.1")
    or not $TargetHeaders{$LibVersion})
    { # support for old ABI dumps: added target headers
        foreach (keys(%{$Registered_Headers{$LibVersion}})) {
            $TargetHeaders{$LibVersion}{get_filename($_)} = 1;
        }
        
        if(not $ABI->{"PublicABI"})
        {
            foreach (keys(%{$Registered_Sources{$LibVersion}})) {
                $TargetHeaders{$LibVersion}{get_filename($_)} = 1;
            }
        }
    }
    $Constants{$LibVersion} = $ABI->{"Constants"};
    if(defined $ABI->{"GccConstants"})
    { # 3.0
        foreach my $Name (keys(%{$ABI->{"GccConstants"}})) {
            $Constants{$LibVersion}{$Name}{"Value"} = $ABI->{"GccConstants"}{$Name};
        }
    }
    
    $NestedNameSpaces{$LibVersion} = $ABI->{"NameSpaces"};
    if(not $NestedNameSpaces{$LibVersion})
    { # support for old dumps
      # Cannot reconstruct NameSpaces. This may affect design
      # of the compatibility report.
        $NestedNameSpaces{$LibVersion} = {};
    }
    # target system type
    # needed to adopt HTML report
    if(not $DumpSystem)
    { # to use in createSymbolsList(...)
        $OStarget = $ABI->{"Target"};
    }
    # recreate environment
    foreach my $Lib_Name (keys(%{$Library_Symbol{$LibVersion}}))
    {
        foreach my $Symbol (keys(%{$Library_Symbol{$LibVersion}{$Lib_Name}}))
        {
            $Symbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
            if($Library_Symbol{$LibVersion}{$Lib_Name}{$Symbol}<=-1)
            { # data marked as -size in the dump
                $GlobalDataObject{$LibVersion}{$Symbol} = -$Library_Symbol{$LibVersion}{$Lib_Name}{$Symbol};
            }
            if($COMMON_LANGUAGE{$LibVersion} ne "C++")
            {
                if(index($Symbol, "_Z")==0 or index($Symbol, "?")==0) {
                    setLanguage($LibVersion, "C++");
                }
            }
        }
    }
    foreach my $Lib_Name (keys(%{$DepLibrary_Symbol{$LibVersion}}))
    {
        foreach my $Symbol (keys(%{$DepLibrary_Symbol{$LibVersion}{$Lib_Name}})) {
            $DepSymbol_Library{$LibVersion}{$Symbol} = $Lib_Name;
        }
    }
    
    my @VFunc = ();
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        if(my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"})
        {
            if(not $Symbol_Library{$LibVersion}{$MnglName}
            and not $DepSymbol_Library{$LibVersion}{$MnglName}) {
                push(@VFunc, $MnglName);
            }
        }
    }
    translateSymbols(@VFunc, $LibVersion);
    translateSymbols(keys(%{$Symbol_Library{$LibVersion}}), $LibVersion);
    translateSymbols(keys(%{$DepSymbol_Library{$LibVersion}}), $LibVersion);
    
    if(not checkDump($LibVersion, "3.0"))
    { # support for old ABI dumps
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            if(my $BaseType = $TypeInfo{$LibVersion}{$TypeId}{"BaseType"})
            {
                if(ref($BaseType) eq "HASH") {
                    $TypeInfo{$LibVersion}{$TypeId}{"BaseType"} = $TypeInfo{$LibVersion}{$TypeId}{"BaseType"}{"Tid"};
                }
            }
        }
    }
    
    if(not checkDump($LibVersion, "3.2"))
    { # support for old ABI dumps
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            if(defined $TypeInfo{$LibVersion}{$TypeId}{"VTable"})
            {
                foreach my $Offset (keys(%{$TypeInfo{$LibVersion}{$TypeId}{"VTable"}})) {
                    $TypeInfo{$LibVersion}{$TypeId}{"VTable"}{$Offset} = simplifyVTable($TypeInfo{$LibVersion}{$TypeId}{"VTable"}{$Offset});
                }
            }
        }
        
        # repair target headers list
        delete($TargetHeaders{$LibVersion});
        foreach (keys(%{$Registered_Headers{$LibVersion}})) {
            $TargetHeaders{$LibVersion}{get_filename($_)} = 1;
        }
        foreach (keys(%{$Registered_Sources{$LibVersion}})) {
            $TargetHeaders{$LibVersion}{get_filename($_)} = 1;
        }
        
        # non-target constants from anon enums
        foreach my $Name (keys(%{$Constants{$LibVersion}}))
        {
            if(not $ExtraDump
            and not is_target_header($Constants{$LibVersion}{$Name}{"Header"}, $LibVersion))
            {
                delete($Constants{$LibVersion}{$Name});
            }
        }
    }
    
    if(not checkDump($LibVersion, "2.20"))
    { # support for old ABI dumps
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            my $TType = $TypeInfo{$LibVersion}{$TypeId}{"Type"};
            
            if($TType=~/Struct|Union|Enum|Typedef/)
            { # repair complex types first
                next;
            }
            
            if(my $BaseId = $TypeInfo{$LibVersion}{$TypeId}{"BaseType"})
            {
                my $BType = lc($TypeInfo{$LibVersion}{$BaseId}{"Type"});
                if($BType=~/Struct|Union|Enum/i)
                {
                    my $BName = $TypeInfo{$LibVersion}{$BaseId}{"Name"};
                    $TypeInfo{$LibVersion}{$TypeId}{"Name"}=~s/\A\Q$BName\E\b/$BType $BName/g;
                }
            }
        }
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            my $TType = $TypeInfo{$LibVersion}{$TypeId}{"Type"};
            my $TName = $TypeInfo{$LibVersion}{$TypeId}{"Name"};
            if($TType=~/Struct|Union|Enum/) {
                $TypeInfo{$LibVersion}{$TypeId}{"Name"} = lc($TType)." ".$TName;
            }
        }
    }
    
    foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
    { # NOTE: order is important
        if(defined $TypeInfo{$LibVersion}{$TypeId}{"BaseClass"})
        { # support for old ABI dumps < 2.0 (ACC 1.22)
            foreach my $BId (keys(%{$TypeInfo{$LibVersion}{$TypeId}{"BaseClass"}}))
            {
                if(my $Access = $TypeInfo{$LibVersion}{$TypeId}{"BaseClass"}{$BId})
                {
                    if($Access ne "public") {
                        $TypeInfo{$LibVersion}{$TypeId}{"Base"}{$BId}{"access"} = $Access;
                    }
                }
                $TypeInfo{$LibVersion}{$TypeId}{"Base"}{$BId} = {};
            }
            delete($TypeInfo{$LibVersion}{$TypeId}{"BaseClass"});
        }
        if(my $Header = $TypeInfo{$LibVersion}{$TypeId}{"Header"})
        { # support for old ABI dumps
            $TypeInfo{$LibVersion}{$TypeId}{"Header"} = path_format($Header, $OSgroup);
        }
        elsif(my $Source = $TypeInfo{$LibVersion}{$TypeId}{"Source"})
        { # DWARF ABI Dumps
            $TypeInfo{$LibVersion}{$TypeId}{"Header"} = $Source;
        }
        if(not defined $TypeInfo{$LibVersion}{$TypeId}{"Tid"}) {
            $TypeInfo{$LibVersion}{$TypeId}{"Tid"} = $TypeId;
        }
        
        # support for old formatting of type names
        $TypeInfo{$LibVersion}{$TypeId}{"Name"} = formatName($TypeInfo{$LibVersion}{$TypeId}{"Name"}, "T");
        
        my %TInfo = %{$TypeInfo{$LibVersion}{$TypeId}};
        if(defined $TInfo{"Base"})
        {
            foreach my $SubId (keys(%{$TInfo{"Base"}}))
            {
                if($SubId eq $TypeId)
                { # Fix erroneus ABI dump
                    delete($TypeInfo{$LibVersion}{$TypeId}{"Base"}{$SubId});
                    next;
                }
                
                $Class_SubClasses{$LibVersion}{$SubId}{$TypeId} = 1;
            }
        }
        if($TInfo{"Type"} eq "MethodPtr")
        {
            if(defined $TInfo{"Param"})
            { # support for old ABI dumps <= 1.17
                if(not defined $TInfo{"Param"}{"0"})
                {
                    my $Max = keys(%{$TInfo{"Param"}});
                    foreach my $Pos (1 .. $Max) {
                        $TInfo{"Param"}{$Pos-1} = $TInfo{"Param"}{$Pos};
                    }
                    delete($TInfo{"Param"}{$Max});
                    %{$TypeInfo{$LibVersion}{$TypeId}} = %TInfo;
                }
            }
        }
        if($TInfo{"BaseType"} eq $TypeId)
        { # fix ABI dump
            delete($TypeInfo{$LibVersion}{$TypeId}{"BaseType"});
        }
        
        if($TInfo{"Type"} eq "Typedef" and not $TInfo{"Artificial"})
        {
            if(my $BTid = $TInfo{"BaseType"})
            {
                my $BName = $TypeInfo{$LibVersion}{$BTid}{"Name"};
                if(not $BName)
                { # broken type
                    next;
                }
                if($TInfo{"Name"} eq $BName)
                { # typedef to "class Class"
                  # should not be registered in TName_Tid
                    next;
                }
                if(not $Typedef_BaseName{$LibVersion}{$TInfo{"Name"}}) {
                    $Typedef_BaseName{$LibVersion}{$TInfo{"Name"}} = $BName;
                }
            }
        }
        if(not $TName_Tid{$LibVersion}{$TInfo{"Name"}})
        { # classes: class (id1), typedef (artificial, id2 > id1)
            $TName_Tid{$LibVersion}{$TInfo{"Name"}} = $TypeId;
        }
    }
    
    if(not checkDump($LibVersion, "2.15"))
    { # support for old ABI dumps
        my %Dups = ();
        foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
        {
            if(my $ClassId = $SymbolInfo{$LibVersion}{$InfoId}{"Class"})
            {
                if(not defined $TypeInfo{$LibVersion}{$ClassId})
                { # remove template decls
                    delete($SymbolInfo{$LibVersion}{$InfoId});
                    next;
                }
            }
            my $MName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
            if(not $MName and $SymbolInfo{$LibVersion}{$InfoId}{"Class"})
            { # templates
                delete($SymbolInfo{$LibVersion}{$InfoId});
            }
        }
    }
    
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        if(my $Class = $SymbolInfo{$LibVersion}{$InfoId}{"Class"}
        and not $SymbolInfo{$LibVersion}{$InfoId}{"Static"}
        and not $SymbolInfo{$LibVersion}{$InfoId}{"Data"})
        { # support for old ABI dumps (< 3.1)
            if(not defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"}
            or $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{0}{"name"} ne "this")
            { # add "this" first parameter
                my $ThisTid = getTypeIdByName($TypeInfo{$LibVersion}{$Class}{"Name"}."*const", $LibVersion);
                my %PInfo = ("name"=>"this", "type"=>"$ThisTid");
                
                if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"})
                {
                    my @Pos = sort {int($a)<=>int($b)} keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}});
                    foreach my $Pos (reverse(0 .. $#Pos)) {
                        %{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$Pos+1}} = %{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}{$Pos}};
                    }
                }
                $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{"0"} = \%PInfo;
            }
        }
        
        if(not $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"})
        { # ABI dumps have no mangled names for C-functions
            $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"} = $SymbolInfo{$LibVersion}{$InfoId}{"ShortName"};
        }
        if(my $Header = $SymbolInfo{$LibVersion}{$InfoId}{"Header"})
        { # support for old ABI dumps
            $SymbolInfo{$LibVersion}{$InfoId}{"Header"} = path_format($Header, $OSgroup);
        }
        elsif(my $Source = $SymbolInfo{$LibVersion}{$InfoId}{"Source"})
        { # DWARF ABI Dumps
            $SymbolInfo{$LibVersion}{$InfoId}{"Header"} = $Source;
        }
    }
    
    $Descriptor{$LibVersion}{"Dump"} = 1;
}

sub read_Machine_DumpInfo($$)
{
    my ($ABI, $LibVersion) = @_;
    if($ABI->{"Arch"}) {
        $CPU_ARCH{$LibVersion} = $ABI->{"Arch"};
    }
    if($ABI->{"WordSize"}) {
        $WORD_SIZE{$LibVersion} = $ABI->{"WordSize"};
    }
    else
    { # support for old dumps
        $WORD_SIZE{$LibVersion} = $ABI->{"SizeOfPointer"};
    }
    if(not $WORD_SIZE{$LibVersion})
    { # support for old dumps (<1.23)
        if(my $Tid = getTypeIdByName("char*", $LibVersion))
        { # size of char*
            $WORD_SIZE{$LibVersion} = $TypeInfo{$LibVersion}{$Tid}{"Size"};
        }
        else
        {
            my $PSize = 0;
            foreach my $Tid (keys(%{$TypeInfo{$LibVersion}}))
            {
                if($TypeInfo{$LibVersion}{$Tid}{"Type"} eq "Pointer")
                { # any "pointer"-type
                    $PSize = $TypeInfo{$LibVersion}{$Tid}{"Size"};
                    last;
                }
            }
            if($PSize)
            { # a pointer type size
                $WORD_SIZE{$LibVersion} = $PSize;
            }
            else {
                printMsg("WARNING", "cannot identify a WORD size in the ABI dump (too old format)");
            }
        }
    }
    if($ABI->{"GccVersion"}) {
        $GCC_VERSION{$LibVersion} = $ABI->{"GccVersion"};
    }
}

sub read_Libs_DumpInfo($$)
{
    my ($ABI, $LibVersion) = @_;
    $Library_Symbol{$LibVersion} = $ABI->{"Symbols"};
    if(not $Library_Symbol{$LibVersion})
    { # support for old dumps
        $Library_Symbol{$LibVersion} = $ABI->{"Interfaces"};
    }
    if(keys(%{$Library_Symbol{$LibVersion}})
    and not $DumpAPI) {
        $Descriptor{$LibVersion}{"Libs"} = "OK";
    }
}

sub read_Source_DumpInfo($$)
{
    my ($ABI, $LibVersion) = @_;
    
    if(keys(%{$ABI->{"Headers"}})
    and not $DumpAPI) {
        $Descriptor{$LibVersion}{"Headers"} = "OK";
    }
    foreach my $Identity (sort {$ABI->{"Headers"}{$a}<=>$ABI->{"Headers"}{$b}} keys(%{$ABI->{"Headers"}}))
    {
        $Registered_Headers{$LibVersion}{$Identity}{"Identity"} = $Identity;
        $Registered_Headers{$LibVersion}{$Identity}{"Pos"} = $ABI->{"Headers"}{$Identity};
    }
    
    if(keys(%{$ABI->{"Sources"}})
    and not $DumpAPI) {
        $Descriptor{$LibVersion}{"Sources"} = "OK";
    }
    foreach my $Name (sort {$ABI->{"Sources"}{$a}<=>$ABI->{"Sources"}{$b}} keys(%{$ABI->{"Sources"}}))
    {
        $Registered_Sources{$LibVersion}{$Name}{"Identity"} = $Name;
        $Registered_Sources{$LibVersion}{$Name}{"Pos"} = $ABI->{"Headers"}{$Name};
    }
}

sub find_libs($$$)
{
    my ($Path, $Type, $MaxDepth) = @_;
    # FIXME: correct the search pattern
    return cmd_find($Path, $Type, '\.'.$LIB_EXT.'[0-9.]*\Z', $MaxDepth, 1);
}

sub createDescriptor($$)
{
    my ($LibVersion, $Path) = @_;
    if(not $LibVersion or not $Path
    or not -e $Path) {
        return "";
    }
    if(-d $Path)
    { # directory with headers files and shared objects
        return "
            <version>
                ".$TargetVersion{$LibVersion}."
            </version>

            <headers>
                $Path
            </headers>

            <libs>
                $Path
            </libs>";
    }
    else
    { # files
        if($Path=~/\.(xml|desc)\Z/i)
        { # standard XML-descriptor
            return readFile($Path);
        }
        elsif(is_header($Path, 2, $LibVersion))
        { # header file
            $CheckHeadersOnly = 1;
            
            if($LibVersion==1) {
                $TargetVersion{$LibVersion} = "X";
            }
            
            if($LibVersion==2) {
                $TargetVersion{$LibVersion} = "Y";
            }
            
            return "
                <version>
                    ".$TargetVersion{$LibVersion}."
                </version>

                <headers>
                    $Path
                </headers>

                <libs>
                    none
                </libs>";
        }
        else
        { # standard XML-descriptor
            return readFile($Path);
        }
    }
}

sub detect_lib_default_paths()
{
    my %LPaths = ();
    if($OSgroup eq "bsd")
    {
        if(my $LdConfig = get_CmdPath("ldconfig"))
        {
            foreach my $Line (split(/\n/, `$LdConfig -r 2>\"$TMP_DIR/null\"`))
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
        if(my $LdConfig = get_CmdPath("ldconfig"))
        {
            if($SystemRoot and $OSgroup eq "linux")
            { # use host (x86) ldconfig with the target (arm) ld.so.conf
                if(-e $SystemRoot."/etc/ld.so.conf") {
                    $LdConfig .= " -f ".$SystemRoot."/etc/ld.so.conf";
                }
            }
            foreach my $Line (split(/\n/, `$LdConfig -p 2>\"$TMP_DIR/null\"`))
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
        elsif($OSgroup eq "linux") {
            printMsg("WARNING", "can't find ldconfig");
        }
    }
    return \%LPaths;
}

sub detect_bin_default_paths()
{
    my $EnvPaths = $ENV{"PATH"};
    if($OSgroup eq "beos") {
        $EnvPaths.=":".$ENV{"BETOOLS"};
    }
    my $Sep = ($OSgroup eq "windows")?";":":|;";
    foreach my $Path (split(/$Sep/, $EnvPaths))
    {
        $Path = path_format($Path, $OSgroup);
        next if(not $Path);
        if($SystemRoot
        and $Path=~/\A\Q$SystemRoot\E\//)
        { # do NOT use binaries from target system
            next;
        }
        push_U(\@DefaultBinPaths, $Path);
    }
}

sub detect_inc_default_paths()
{
    my %DPaths = ("Cpp"=>[],"Gcc"=>[],"Inc"=>[]);
    writeFile("$TMP_DIR/empty.h", "");
    foreach my $Line (split(/\n/, `$GCC_PATH -v -x c++ -E \"$TMP_DIR/empty.h\" 2>&1`))
    { # detecting GCC default include paths
        next if(index($Line, "/cc1plus ")!=-1);
        
        if($Line=~/\A[ \t]*((\/|\w+:\\).+)[ \t]*\Z/)
        {
            my $Path = realpath($1);
            $Path = path_format($Path, $OSgroup);
            if(index($Path, "c++")!=-1
            or index($Path, "/g++/")!=-1)
            {
                push_U($DPaths{"Cpp"}, $Path);
                if(not defined $MAIN_CPP_DIR
                or get_depth($MAIN_CPP_DIR)>get_depth($Path)) {
                    $MAIN_CPP_DIR = $Path;
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
                if($SystemRoot
                and $Path!~/\A\Q$SystemRoot\E(\/|\Z)/)
                { # The GCC include path for user headers is not a part of the system root
                  # The reason: you are not specified the --cross-gcc option or selected a wrong compiler
                  # or it is the internal cross-GCC path like arm-linux-gnueabi/include
                    next;
                }
                push_U($DPaths{"Inc"}, $Path);
            }
        }
    }
    unlink("$TMP_DIR/empty.h");
    return %DPaths;
}

sub detect_default_paths($)
{
    my ($HSearch, $LSearch, $BSearch, $GSearch) = (1, 1, 1, 1);
    my $Search = $_[0];
    if($Search!~/inc/) {
        $HSearch = 0;
    }
    if($Search!~/lib/) {
        $LSearch = 0;
    }
    if($Search!~/bin/) {
        $BSearch = 0;
    }
    if($Search!~/gcc/) {
        $GSearch = 0;
    }
    if(@{$SystemPaths{"include"}})
    { # <search_headers> section of the XML descriptor
      # do NOT search for systems headers
        $HSearch = 0;
    }
    if(@{$SystemPaths{"lib"}})
    { # <search_libs> section of the XML descriptor
      # do NOT search for systems libraries
        $LSearch = 0;
    }
    foreach my $Type (keys(%{$OS_AddPath{$OSgroup}}))
    { # additional search paths
        next if($Type eq "include" and not $HSearch);
        next if($Type eq "lib" and not $LSearch);
        next if($Type eq "bin" and not $BSearch);
        push_U($SystemPaths{$Type}, grep { -d $_ } @{$OS_AddPath{$OSgroup}{$Type}});
    }
    if($OSgroup ne "windows")
    { # unix-like
        foreach my $Type ("include", "lib", "bin")
        { # automatic detection of system "devel" directories
            next if($Type eq "include" and not $HSearch);
            next if($Type eq "lib" and not $LSearch);
            next if($Type eq "bin" and not $BSearch);
            my ($UsrDir, $RootDir) = ("/usr", "/");
            if($SystemRoot and $Type ne "bin")
            { # 1. search for target headers and libraries
              # 2. use host commands: ldconfig, readelf, etc.
                ($UsrDir, $RootDir) = ("$SystemRoot/usr", $SystemRoot);
            }
            push_U($SystemPaths{$Type}, cmd_find($RootDir,"d","*$Type*",1));
            if(-d $RootDir."/".$Type)
            { # if "/lib" is symbolic link
                if($RootDir eq "/") {
                    push_U($SystemPaths{$Type}, "/".$Type);
                }
                else {
                    push_U($SystemPaths{$Type}, $RootDir."/".$Type);
                }
            }
            if(-d $UsrDir)
            {
                push_U($SystemPaths{$Type}, cmd_find($UsrDir,"d","*$Type*",1));
                if(-d $UsrDir."/".$Type)
                { # if "/usr/lib" is symbolic link
                    push_U($SystemPaths{$Type}, $UsrDir."/".$Type);
                }
            }
        }
    }
    if($BSearch)
    {
        detect_bin_default_paths();
        push_U($SystemPaths{"bin"}, @DefaultBinPaths);
    }
    # check environment variables
    if($OSgroup eq "beos")
    {
        foreach (my @Paths = @{$SystemPaths{"bin"}})
        {
            if($_ eq ".") {
                next;
            }
            # search for /boot/develop/abi/x86/gcc4/tools/gcc-4.4.4-haiku-101111/bin/
            if(my @Dirs = sort cmd_find($_, "d", "bin")) {
                push_U($SystemPaths{"bin"}, sort {get_depth($a)<=>get_depth($b)} @Dirs);
            }
        }
        if($HSearch)
        {
            push_U(\@DefaultIncPaths, grep { is_abs($_) } (
                split(/:|;/, $ENV{"BEINCLUDES"})
                ));
        }
        if($LSearch)
        {
            push_U(\@DefaultLibPaths, grep { is_abs($_) } (
                split(/:|;/, $ENV{"BELIBRARIES"}),
                split(/:|;/, $ENV{"LIBRARY_PATH"})
                ));
        }
    }
    if($LSearch)
    { # using linker to get system paths
        if(my $LPaths = detect_lib_default_paths())
        { # unix-like
            my %Dirs = ();
            foreach my $Name (keys(%{$LPaths}))
            {
                if($SystemRoot
                and $LPaths->{$Name}!~/\A\Q$SystemRoot\E\//)
                { # wrong ldconfig configuration
                  # check your <sysroot>/etc/ld.so.conf
                    next;
                }
                $DyLib_DefaultPath{$Name} = $LPaths->{$Name};
                if(my $Dir = get_dirname($LPaths->{$Name})) {
                    $Dirs{$Dir} = 1;
                }
            }
            push_U(\@DefaultLibPaths, sort {get_depth($a)<=>get_depth($b)} sort keys(%Dirs));
        }
        push_U($SystemPaths{"lib"}, @DefaultLibPaths);
    }
    if($BSearch)
    {
        if($CrossGcc)
        { # --cross-gcc=arm-linux-gcc
            if(-e $CrossGcc)
            { # absolute or relative path
                $GCC_PATH = get_abs_path($CrossGcc);
            }
            elsif($CrossGcc!~/\// and get_CmdPath($CrossGcc))
            { # command name
                $GCC_PATH = $CrossGcc;
            }
            else {
                exitStatus("Access_Error", "can't access \'$CrossGcc\'");
            }
            if($GCC_PATH=~/\s/) {
                $GCC_PATH = "\"".$GCC_PATH."\"";
            }
        }
    }
    if($GSearch)
    { # GCC path and default include dirs
        if(not $CrossGcc)
        { # try default gcc
            $GCC_PATH = get_CmdPath("gcc");
        }
        if(not $GCC_PATH)
        { # try to find gcc-X.Y
            foreach my $Path (@{$SystemPaths{"bin"}})
            {
                if(my @GCCs = cmd_find($Path, "", '/gcc-[0-9.]*\Z', 1, 1))
                { # select the latest version
                    @GCCs = sort {$b cmp $a} @GCCs;
                    if(check_gcc($GCCs[0], "3"))
                    {
                        $GCC_PATH = $GCCs[0];
                        last;
                    }
                }
            }
        }
        if(not $GCC_PATH) {
            exitStatus("Not_Found", "can't find GCC>=3.0 in PATH");
        }
        
        my $GCC_Ver = get_dumpversion($GCC_PATH);
        if($GCC_Ver eq "4.8")
        { # on Ubuntu -dumpversion returns 4.8 for gcc 4.8.4
            my $Info = `$GCC_PATH --version`;
            
            if($Info=~/gcc\s+(|\([^()]+\)\s+)(\d+\.\d+\.\d+)/)
            { # gcc (Ubuntu 4.8.4-2ubuntu1~14.04) 4.8.4
              # gcc (GCC) 4.9.2 20150212 (Red Hat 4.9.2-6)
                $GCC_Ver = $2;
            }
        }
        
        if($OStarget=~/macos/)
        {
            my $Info = `$GCC_PATH --version`;
            
            if($Info=~/clang/i) {
                printMsg("WARNING", "doesn't work with clang, please install GCC instead (and select it by -gcc-path option)");
            }
        }
        
        if($GCC_Ver)
        {
            my $GccTarget = get_dumpmachine($GCC_PATH);
            
            if($GccTarget=~/linux/)
            {
                $OStarget = "linux";
                $LIB_EXT = $OS_LibExt{$LIB_TYPE}{$OStarget};
            }
            elsif($GccTarget=~/symbian/)
            {
                $OStarget = "symbian";
                $LIB_EXT = $OS_LibExt{$LIB_TYPE}{$OStarget};
            }
            
            printMsg("INFO", "Using GCC $GCC_Ver ($GccTarget, target: ".getArch_GCC(1).")");
            
            # check GCC version
            if($GCC_Ver=~/\A4\.8(|\.[012])\Z/)
            { # bug http://gcc.gnu.org/bugzilla/show_bug.cgi?id=57850
              # introduced in 4.8 and fixed in 4.8.3
                printMsg("WARNING", "Not working properly with GCC $GCC_Ver. Please update GCC to 4.8.3 or downgrade it to 4.7. You can use a local GCC installation by --gcc-path=PATH option.");
                
                $EMERGENCY_MODE_48 = 1;
            }
        }
        else {
            exitStatus("Error", "something is going wrong with the GCC compiler");
        }
    }
    if($HSearch)
    {
        # GCC standard paths
        if($GCC_PATH and not $NoStdInc)
        {
            my %DPaths = detect_inc_default_paths();
            @DefaultCppPaths = @{$DPaths{"Cpp"}};
            @DefaultGccPaths = @{$DPaths{"Gcc"}};
            @DefaultIncPaths = @{$DPaths{"Inc"}};
            push_U($SystemPaths{"include"}, @DefaultIncPaths);
        }
        
        # users include paths
        my $IncPath = "/usr/include";
        if($SystemRoot) {
            $IncPath = $SystemRoot.$IncPath;
        }
        if(-d $IncPath) {
            push_U(\@UsersIncPath, $IncPath);
        }
    }
    
    if($ExtraInfo)
    {
        writeFile($ExtraInfo."/default-libs", join("\n", @DefaultLibPaths));
        writeFile($ExtraInfo."/default-includes", join("\n", (@DefaultCppPaths, @DefaultGccPaths, @DefaultIncPaths)));
    }
}

sub getLIB_EXT($)
{
    my $Target = $_[0];
    if(my $Ext = $OS_LibExt{$LIB_TYPE}{$Target}) {
        return $Ext;
    }
    return $OS_LibExt{$LIB_TYPE}{"default"};
}

sub getAR_EXT($)
{
    my $Target = $_[0];
    if(my $Ext = $OS_Archive{$Target}) {
        return $Ext;
    }
    return $OS_Archive{"default"};
}

sub get_dumpversion($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    if($Cache{"get_dumpversion"}{$Cmd}) {
        return $Cache{"get_dumpversion"}{$Cmd};
    }
    my $V = `$Cmd -dumpversion 2>\"$TMP_DIR/null\"`;
    chomp($V);
    return ($Cache{"get_dumpversion"}{$Cmd} = $V);
}

sub get_dumpmachine($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    if($Cache{"get_dumpmachine"}{$Cmd}) {
        return $Cache{"get_dumpmachine"}{$Cmd};
    }
    my $Machine = `$Cmd -dumpmachine 2>\"$TMP_DIR/null\"`;
    chomp($Machine);
    return ($Cache{"get_dumpmachine"}{$Cmd} = $Machine);
}

sub checkCmd($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    my @Options = (
        "--version",
        "-help"
    );
    foreach my $Opt (@Options)
    {
        my $Info = `$Cmd $Opt 2>\"$TMP_DIR/null\"`;
        if($Info) {
            return 1;
        }
    }
    return 0;
}

sub check_gcc($$)
{
    my ($Cmd, $ReqVer) = @_;
    return 0 if(not $Cmd or not $ReqVer);
    if(defined $Cache{"check_gcc"}{$Cmd}{$ReqVer}) {
        return $Cache{"check_gcc"}{$Cmd}{$ReqVer};
    }
    if(my $GccVer = get_dumpversion($Cmd))
    {
        $GccVer=~s/(-|_)[a-z_]+.*\Z//; # remove suffix (like "-haiku-100818")
        if(cmpVersions($GccVer, $ReqVer)>=0) {
            return ($Cache{"check_gcc"}{$Cmd}{$ReqVer} = $Cmd);
        }
    }
    return ($Cache{"check_gcc"}{$Cmd}{$ReqVer} = "");
}

sub get_depth($)
{
    if(defined $Cache{"get_depth"}{$_[0]}) {
        return $Cache{"get_depth"}{$_[0]};
    }
    return ($Cache{"get_depth"}{$_[0]} = ($_[0]=~tr![\/\\]|\:\:!!));
}

sub registerGccHeaders()
{
    return if($Cache{"registerGccHeaders"}); # this function should be called once
    
    foreach my $Path (@DefaultGccPaths)
    {
        my @Headers = cmd_find($Path,"f");
        @Headers = sort {get_depth($a)<=>get_depth($b)} @Headers;
        foreach my $HPath (@Headers)
        {
            my $FileName = get_filename($HPath);
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
    return if($Cache{"registerCppHeaders"}); # this function should be called once
    
    foreach my $CppDir (@DefaultCppPaths)
    {
        my @Headers = cmd_find($CppDir,"f");
        @Headers = sort {get_depth($a)<=>get_depth($b)} @Headers;
        foreach my $Path (@Headers)
        {
            my $FileName = get_filename($Path);
            if(not defined $DefaultCppHeader{$FileName})
            { # skip duplicated
                $DefaultCppHeader{$FileName} = $Path;
            }
        }
    }
    $Cache{"registerCppHeaders"} = 1;
}

sub parse_libname($$$)
{
    return "" if(not $_[0]);
    if(defined $Cache{"parse_libname"}{$_[2]}{$_[1]}{$_[0]}) {
        return $Cache{"parse_libname"}{$_[2]}{$_[1]}{$_[0]};
    }
    return ($Cache{"parse_libname"}{$_[2]}{$_[1]}{$_[0]} = parse_libname_I(@_));
}

sub parse_libname_I($$$)
{
    my ($Name, $Type, $Target) = @_;
    
    if($Target eq "symbian") {
        return parse_libname_symbian($Name, $Type);
    }
    elsif($Target eq "windows") {
        return parse_libname_windows($Name, $Type);
    }
    
    # unix
    my $Ext = getLIB_EXT($Target);
    if($Name=~/((((lib|).+?)([\-\_][\d\-\.\_]+.*?|))\.$Ext)(\.(.+)|)\Z/)
    { # libSDL-1.2.so.0.7.1
      # libwbxml2.so.0.0.18
      # libopcodes-2.21.53-system.20110810.so
        if($Type eq "name")
        { # libSDL-1.2
          # libwbxml2
            return $2;
        }
        elsif($Type eq "name+ext")
        { # libSDL-1.2.so
          # libwbxml2.so
            return $1;
        }
        elsif($Type eq "version")
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
        elsif($Type eq "short")
        { # libSDL
          # libwbxml2
            return $3;
        }
        elsif($Type eq "shortest")
        { # SDL
          # wbxml
            return shortest_name($3);
        }
    }
    return "";# error
}

sub parse_libname_symbian($$)
{
    my ($Name, $Type) = @_;
    my $Ext = getLIB_EXT("symbian");
    if($Name=~/(((.+?)(\{.+\}|))\.$Ext)\Z/)
    { # libpthread{00010001}.dso
        if($Type eq "name")
        { # libpthread{00010001}
            return $2;
        }
        elsif($Type eq "name+ext")
        { # libpthread{00010001}.dso
            return $1;
        }
        elsif($Type eq "version")
        { # 00010001
            my $V = $4;
            $V=~s/\{(.+)\}/$1/;
            return $V;
        }
        elsif($Type eq "short")
        { # libpthread
            return $3;
        }
        elsif($Type eq "shortest")
        { # pthread
            return shortest_name($3);
        }
    }
    return "";# error
}

sub parse_libname_windows($$)
{
    my ($Name, $Type) = @_;
    my $Ext = getLIB_EXT("windows");
    if($Name=~/((.+?)\.$Ext)\Z/)
    { # netapi32.dll
        if($Type eq "name")
        { # netapi32
            return $2;
        }
        elsif($Type eq "name+ext")
        { # netapi32.dll
            return $1;
        }
        elsif($Type eq "version")
        { # DLL version embedded
          # at binary-level
            return "";
        }
        elsif($Type eq "short")
        { # netapi32
            return $2;
        }
        elsif($Type eq "shortest")
        { # netapi
            return shortest_name($2);
        }
    }
    return "";# error
}

sub shortest_name($)
{
    my $Name = $_[0];
    # remove prefix
    $Name=~s/\A(lib|open)//;
    # remove suffix
    $Name=~s/[\W\d_]+\Z//i;
    $Name=~s/([a-z]{2,})(lib)\Z/$1/i;
    return $Name;
}

sub createSymbolsList($$$$$)
{
    my ($DPath, $SaveTo, $LName, $LVersion, $ArchName) = @_;
    
    read_ABI_Dump(1, $DPath);
    prepareSymbols(1);
    
    my %SymbolHeaderLib = ();
    my $Total = 0;
    
    # Get List
    foreach my $Symbol (sort keys(%{$CompleteSignature{1}}))
    {
        if(not link_symbol($Symbol, 1, "-Deps"))
        { # skip src only and all external functions
            next;
        }
        if(not symbolFilter($Symbol, 1, "Public", "Binary"))
        { # skip other symbols
            next;
        }
        my $HeaderName = $CompleteSignature{1}{$Symbol}{"Header"};
        if(not $HeaderName)
        { # skip src only and all external functions
            next;
        }
        my $DyLib = $Symbol_Library{1}{$Symbol};
        if(not $DyLib)
        { # skip src only and all external functions
            next;
        }
        $SymbolHeaderLib{$HeaderName}{$DyLib}{$Symbol} = 1;
        $Total+=1;
    }
    # Draw List
    my $SYMBOLS_LIST = "<h1>Public symbols in <span style='color:Blue;'>$LName</span> (<span style='color:Red;'>$LVersion</span>)";
    $SYMBOLS_LIST .= " on <span style='color:Blue;'>".showArch($ArchName)."</span><br/>Total: $Total</h1><br/>";
    foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%SymbolHeaderLib))
    {
        foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$SymbolHeaderLib{$HeaderName}}))
        {
            my %NS_Symbol = ();
            foreach my $Symbol (keys(%{$SymbolHeaderLib{$HeaderName}{$DyLib}})) {
                $NS_Symbol{select_Symbol_NS($Symbol, 1)}{$Symbol} = 1;
            }
            foreach my $NameSpace (sort keys(%NS_Symbol))
            {
                $SYMBOLS_LIST .= getTitle($HeaderName, $DyLib, $NameSpace);
                my @SortedInterfaces = sort {lc(get_Signature($a, 1)) cmp lc(get_Signature($b, 1))} keys(%{$NS_Symbol{$NameSpace}});
                foreach my $Symbol (@SortedInterfaces)
                {
                    my $SubReport = "";
                    my $Signature = get_Signature($Symbol, 1);
                    if($NameSpace) {
                        $Signature=~s/\b\Q$NameSpace\E::\b//g;
                    }
                    if($Symbol=~/\A(_Z|\?)/)
                    {
                        if($Signature) {
                            $SubReport = insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Symbol</b>]</span><br/><br/>".$ContentDivEnd."\n");
                        }
                        else {
                            $SubReport = "<span class='iname'>".$Symbol."</span><br/>\n";
                        }
                    }
                    else
                    {
                        if($Signature) {
                            $SubReport = "<span class='iname'>".highLight_Signature_Italic_Color($Signature)."</span><br/>\n";
                        }
                        else {
                            $SubReport = "<span class='iname'>".$Symbol."</span><br/>\n";
                        }
                    }
                    $SYMBOLS_LIST .= $SubReport;
                }
            }
            $SYMBOLS_LIST .= "<br/>\n";
        }
    }
    # clear info
    (%TypeInfo, %SymbolInfo, %Library_Symbol, %DepSymbol_Library,
    %DepLibrary_Symbol, %SymVer, %SkipTypes, %SkipSymbols,
    %NestedNameSpaces, %ClassMethods, %AllocableClass, %ClassNames,
    %CompleteSignature, %SkipNameSpaces, %Symbol_Library, %Library_Symbol) = ();
    ($Content_Counter, $ContentID) = (0, 0);
    # print report
    my $CssStyles = readModule("Styles", "SymbolsList.css");
    my $JScripts = readModule("Scripts", "Sections.js");
    $SYMBOLS_LIST = "<a name='Top'></a>".$SYMBOLS_LIST.$TOP_REF."<br/>\n";
    my $Title = "$LName: public symbols";
    my $Keywords = "$LName, API, symbols";
    my $Description = "List of symbols in $LName ($LVersion) on ".showArch($ArchName);
    $SYMBOLS_LIST = composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."
    <body><div>\n$SYMBOLS_LIST</div>
    <br/><br/>\n".getReportFooter()."
    </body></html>";
    writeFile($SaveTo, $SYMBOLS_LIST);
}

sub add_target_libs($)
{
    foreach (@{$_[0]}) {
        $TargetLibs{$_} = 1;
    }
}

sub is_target_lib($)
{
    my $LName = $_[0];
    if(not $LName) {
        return 0;
    }
    if($TargetLibraryName
    and $LName!~/\Q$TargetLibraryName\E/) {
        return 0;
    }
    if(keys(%TargetLibs)
    and not $TargetLibs{$LName}
    and not $TargetLibs{parse_libname($LName, "name+ext", $OStarget)}) {
        return 0;
    }
    return 1;
}

sub is_target_header($$)
{ # --header, --headers-list
    my ($H, $V) = @_;
    if(keys(%{$TargetHeaders{$V}}))
    {
        if($TargetHeaders{$V}{$H}) {
            return 1;
        }
    }
    return 0;
}

sub readLibs($)
{
    my $LibVersion = $_[0];
    if($OStarget eq "windows")
    { # dumpbin.exe will crash
        # without VS Environment
        check_win32_env();
    }
    readSymbols($LibVersion);
    translateSymbols(keys(%{$Symbol_Library{$LibVersion}}), $LibVersion);
    translateSymbols(keys(%{$DepSymbol_Library{$LibVersion}}), $LibVersion);
}

sub dump_sorting($)
{
    my $Hash = $_[0];
    return [] if(not $Hash);
    my @Keys = keys(%{$Hash});
    return [] if($#Keys<0);
    if($Keys[0]=~/\A\d+\Z/)
    { # numbers
        return [sort {int($a)<=>int($b)} @Keys];
    }
    else
    { # strings
        return [sort {$a cmp $b} @Keys];
    }
}

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($Quiet)
    { # --quiet option
        appendFile($COMMON_LOG_PATH, $Msg);
    }
    else
    {
        if($Type eq "ERROR") {
            print STDERR $Msg;
        }
        else {
            print $Msg;
        }
    }
}

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    printMsg("ERROR", $Msg);
    exit($ERROR_CODE{$Code});
}

sub exitReport()
{ # the tool has run without any errors
    printReport();
    if($COMPILE_ERRORS)
    { # errors in headers may add false positives/negatives
        exit($ERROR_CODE{"Compile_Error"});
    }
    if($BinaryOnly and $RESULT{"Binary"}{"Problems"})
    { # --binary
        exit($ERROR_CODE{"Incompatible"});
    }
    elsif($SourceOnly and $RESULT{"Source"}{"Problems"})
    { # --source
        exit($ERROR_CODE{"Incompatible"});
    }
    elsif($RESULT{"Source"}{"Problems"}
    or $RESULT{"Binary"}{"Problems"})
    { # default
        exit($ERROR_CODE{"Incompatible"});
    }
    else {
        exit($ERROR_CODE{"Compatible"});
    }
}

sub readRules($)
{
    my $Kind = $_[0];
    if(not -f $RULES_PATH{$Kind}) {
        exitStatus("Module_Error", "can't access \'".$RULES_PATH{$Kind}."\'");
    }
    my $Content = readFile($RULES_PATH{$Kind});
    while(my $Rule = parseTag(\$Content, "rule"))
    {
        my $RId = parseTag(\$Rule, "id");
        my @Properties = ("Severity", "Change", "Effect", "Overcome", "Kind");
        foreach my $Prop (@Properties) {
            if(my $Value = parseTag(\$Rule, lc($Prop)))
            {
                $Value=~s/\n[ ]*//;
                $CompatRules{$Kind}{$RId}{$Prop} = $Value;
            }
        }
        if($CompatRules{$Kind}{$RId}{"Kind"}=~/\A(Symbols|Parameters)\Z/) {
            $CompatRules{$Kind}{$RId}{"Kind"} = "Symbols";
        }
        else {
            $CompatRules{$Kind}{$RId}{"Kind"} = "Types";
        }
    }
}

sub getReportPath($)
{
    my $Level = $_[0];
    my $Dir = "compat_reports/$TargetLibraryName/".$Descriptor{1}{"Version"}."_to_".$Descriptor{2}{"Version"};
    if($Level eq "Binary")
    {
        if($BinaryReportPath)
        { # --bin-report-path
            return $BinaryReportPath;
        }
        elsif($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/abi_compat_report.$ReportFormat";
        }
    }
    elsif($Level eq "Source")
    {
        if($SourceReportPath)
        { # --src-report-path
            return $SourceReportPath;
        }
        elsif($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/src_compat_report.$ReportFormat";
        }
    }
    else
    {
        if($OutputReportPath)
        { # --report-path
            return $OutputReportPath;
        }
        else
        { # default
            return $Dir."/compat_report.$ReportFormat";
        }
    }
}

sub printStatMsg($)
{
    my $Level = $_[0];
    printMsg("INFO", "total \"$Level\" compatibility problems: ".$RESULT{$Level}{"Problems"}.", warnings: ".$RESULT{$Level}{"Warnings"});
}

sub listAffected($)
{
    my $Level = $_[0];
    my $List = "";
    foreach (keys(%{$TotalAffected{$Level}}))
    {
        if($StrictCompat and $TotalAffected{$Level}{$_} eq "Low")
        { # skip "Low"-severity problems
            next;
        }
        $List .= "$_\n";
    }
    my $Dir = get_dirname(getReportPath($Level));
    if($Level eq "Binary") {
        writeFile($Dir."/abi_affected.txt", $List);
    }
    elsif($Level eq "Source") {
        writeFile($Dir."/src_affected.txt", $List);
    }
}

sub printReport()
{
    printMsg("INFO", "creating compatibility report ...");
    createReport();
    if($JoinReport or $DoubleReport)
    {
        if($RESULT{"Binary"}{"Problems"}
        or $RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (Binary: ".$RESULT{"Binary"}{"Affected"}."\%, Source: ".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Binary");
        printStatMsg("Source");
        if($ListAffected)
        { # --list-affected
            listAffected("Binary");
            listAffected("Source");
        }
    }
    elsif($BinaryOnly)
    {
        if($RESULT{"Binary"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (".$RESULT{"Binary"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Binary");
        if($ListAffected)
        { # --list-affected
            listAffected("Binary");
        }
    }
    elsif($SourceOnly)
    {
        if($RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "result: INCOMPATIBLE (".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "result: COMPATIBLE");
        }
        printStatMsg("Source");
        if($ListAffected)
        { # --list-affected
            listAffected("Source");
        }
    }
    if($StdOut)
    {
        if($JoinReport or not $DoubleReport)
        { # --binary or --source
            printMsg("INFO", "compatibility report has been generated to stdout");
        }
        else
        { # default
            printMsg("INFO", "compatibility reports have been generated to stdout");
        }
    }
    else
    {
        if($JoinReport)
        {
            printMsg("INFO", "see detailed report:\n  ".getReportPath("Join"));
        }
        elsif($DoubleReport)
        { # default
            printMsg("INFO", "see detailed reports:\n  ".getReportPath("Binary")."\n  ".getReportPath("Source"));
        }
        elsif($BinaryOnly)
        { # --binary
            printMsg("INFO", "see detailed report:\n  ".getReportPath("Binary"));
        }
        elsif($SourceOnly)
        { # --source
            printMsg("INFO", "see detailed report:\n  ".getReportPath("Source"));
        }
    }
}

sub check_win32_env()
{
    if(not $ENV{"DevEnvDir"}
    or not $ENV{"LIB"}) {
        exitStatus("Error", "can't start without VS environment (vsvars32.bat)");
    }
}

sub diffSets($$)
{
    my ($S1, $S2) = @_;
    my @SK1 = keys(%{$S1});
    my @SK2 = keys(%{$S2});
    if($#SK1!=$#SK2) {
        return 1;
    }
    foreach my $K1 (@SK1)
    {
        if(not defined $S2->{$K1}) {
            return 1;
        }
    }
    return 0;
}

sub defaultDumpPath($$)
{
    my ($N, $V) = @_;
    return "abi_dumps/".$N."/".$N."_".$V.".abi.".$AR_EXT; # gzipped by default
}

sub create_ABI_Dump()
{
    if(not -e $DumpAPI) {
        exitStatus("Access_Error", "can't access \'$DumpAPI\'");
    }
    
    if(isDump($DumpAPI)) {
        read_ABI_Dump(1, $DumpAPI);
    }
    else {
        readDescriptor(1, createDescriptor(1, $DumpAPI));
    }
    
    if(not $Descriptor{1}{"Version"})
    { # set to default: N
        $Descriptor{1}{"Version"} = "N";
    }
    
    initLogging(1);
    detect_default_paths("inc|lib|bin|gcc"); # complete analysis
    
    my $DumpPath = defaultDumpPath($TargetLibraryName, $Descriptor{1}{"Version"});
    if($OutputDumpPath)
    { # user defined path
        $DumpPath = $OutputDumpPath;
    }
    my $Archive = ($DumpPath=~s/\Q.$AR_EXT\E\Z//g);
    
    if(not $Archive and not $StdOut)
    { # check archive utilities
        if($OSgroup eq "windows")
        { # using zip
            my $ZipCmd = get_CmdPath("zip");
            if(not $ZipCmd) {
                exitStatus("Not_Found", "can't find \"zip\"");
            }
        }
        else
        { # using tar and gzip
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\"");
            }
            my $GzipCmd = get_CmdPath("gzip");
            if(not $GzipCmd) {
                exitStatus("Not_Found", "can't find \"gzip\"");
            }
        }
    }
    
    if(not $Descriptor{1}{"Dump"})
    {
        if(not $CheckHeadersOnly) {
            readLibs(1);
        }
        if($CheckHeadersOnly) {
            setLanguage(1, "C++");
        }
        searchForHeaders(1);
        $WORD_SIZE{1} = detectWordSize(1);
    }
    if(not $Descriptor{1}{"Dump"})
    {
        if($Descriptor{1}{"Headers"}) {
            readHeaders(1);
        }
    }
    cleanDump(1);
    if(not keys(%{$SymbolInfo{1}}))
    { # check if created dump is valid
        if(not $ExtendedCheck)
        {
            if($CheckHeadersOnly) {
                exitStatus("Empty_Set", "the set of public symbols is empty");
            }
            else {
                exitStatus("Empty_Intersection", "the sets of public symbols in headers and libraries have empty intersection");
            }
        }
    }
    my %HeadersInfo = ();
    foreach my $HPath (keys(%{$Registered_Headers{1}})) {
        $HeadersInfo{$Registered_Headers{1}{$HPath}{"Identity"}} = $Registered_Headers{1}{$HPath}{"Pos"};
    }
    if($ExtraDump)
    { # add unmangled names to the ABI dump
        my @Names = ();
        foreach my $InfoId (keys(%{$SymbolInfo{1}}))
        {
            if(my $MnglName = $SymbolInfo{1}{$InfoId}{"MnglName"}) {
                push(@Names, $MnglName);
            }
        }
        translateSymbols(@Names, 1);
        foreach my $InfoId (keys(%{$SymbolInfo{1}}))
        {
            if(my $MnglName = $SymbolInfo{1}{$InfoId}{"MnglName"})
            {
                if(my $Unmangled = $tr_name{$MnglName})
                {
                    if($MnglName ne $Unmangled) {
                        $SymbolInfo{1}{$InfoId}{"Unmangled"} = $Unmangled;
                    }
                }
            }
        }
    }
    
    my %GccConstants = (); # built-in GCC constants
    foreach my $Name (keys(%{$Constants{1}}))
    {
        if(not defined $Constants{1}{$Name}{"Header"})
        {
            $GccConstants{$Name} = $Constants{1}{$Name}{"Value"};
            delete($Constants{1}{$Name});
        }
    }
    
    printMsg("INFO", "creating library ABI dump ...");
    my %ABI = (
        "TypeInfo" => $TypeInfo{1},
        "SymbolInfo" => $SymbolInfo{1},
        "Symbols" => $Library_Symbol{1},
        "DepSymbols" => $DepLibrary_Symbol{1},
        "SymbolVersion" => $SymVer{1},
        "LibraryVersion" => $Descriptor{1}{"Version"},
        "LibraryName" => $TargetLibraryName,
        "Language" => $COMMON_LANGUAGE{1},
        "SkipTypes" => $SkipTypes{1},
        "SkipSymbols" => $SkipSymbols{1},
        "SkipNameSpaces" => $SkipNameSpaces{1},
        "SkipHeaders" => $SkipHeadersList{1},
        "Headers" => \%HeadersInfo,
        "Constants" => $Constants{1},
        "GccConstants" => \%GccConstants,
        "NameSpaces" => $NestedNameSpaces{1},
        "Target" => $OStarget,
        "Arch" => getArch(1),
        "WordSize" => $WORD_SIZE{1},
        "GccVersion" => get_dumpversion($GCC_PATH),
        "ABI_DUMP_VERSION" => $ABI_DUMP_VERSION,
        "ABI_COMPLIANCE_CHECKER_VERSION" => $TOOL_VERSION
    );
    if(diffSets($TargetHeaders{1}, \%HeadersInfo)) {
        $ABI{"TargetHeaders"} = $TargetHeaders{1};
    }
    if($UseXML) {
        $ABI{"XML_ABI_DUMP_VERSION"} = $XML_ABI_DUMP_VERSION;
    }
    if($ExtendedCheck)
    { # --ext option
        $ABI{"Mode"} = "Extended";
    }
    if($BinaryOnly)
    { # --binary
        $ABI{"BinOnly"} = 1;
    }
    if($ExtraDump)
    { # --extra-dump
        $ABI{"Extra"} = 1;
        $ABI{"UndefinedSymbols"} = $UndefinedSymbols{1};
        $ABI{"Needed"} = $Library_Needed{1};
    }
    
    my $ABI_DUMP = "";
    if($UseXML)
    {
        loadModule("XmlDump");
        $ABI_DUMP = createXmlDump(\%ABI);
    }
    else
    { # default
        $ABI_DUMP = Dumper(\%ABI);
    }
    if($StdOut)
    { # --stdout option
        print STDOUT $ABI_DUMP;
        printMsg("INFO", "ABI dump has been generated to stdout");
        return;
    }
    else
    { # write to gzipped file
        my ($DDir, $DName) = separate_path($DumpPath);
        my $DPath = $TMP_DIR."/".$DName;
        if(not $Archive) {
            $DPath = $DumpPath;
        }
        
        mkpath($DDir);
        
        open(DUMP, ">", $DPath) || die ("can't open file \'$DPath\': $!\n");
        print DUMP $ABI_DUMP;
        close(DUMP);
        
        if(not -s $DPath) {
            exitStatus("Error", "can't create ABI dump because something is going wrong with the Data::Dumper module");
        }
        if($Archive) {
            $DumpPath = createArchive($DPath, $DDir);
        }
        
        if($OutputDumpPath) {
            printMsg("INFO", "dump path: $OutputDumpPath");
        }
        else {
            printMsg("INFO", "dump path: $DumpPath");
        }
        # printMsg("INFO", "you can transfer this dump everywhere and use instead of the ".$Descriptor{1}{"Version"}." version descriptor");
    }
}

sub quickEmptyReports()
{ # Quick "empty" reports
  # 4 times faster than merging equal dumps
  # NOTE: the dump contains the "LibraryVersion" attribute
  # if you change the version, then your dump will be different
  # OVERCOME: use -v1 and v2 options for comparing dumps
  # and don't change version in the XML descriptor (and dumps)
  # OVERCOME 2: separate meta info from the dumps in ACC 2.0
    if(-s $Descriptor{1}{"Path"} == -s $Descriptor{2}{"Path"})
    {
        my $FilePath1 = $Descriptor{1}{"Path"};
        my $FilePath2 = $Descriptor{2}{"Path"};
        
        if(not isDump_U($FilePath1)) {
            $FilePath1 = unpackDump($FilePath1);
        }
        
        if(not isDump_U($FilePath2)) {
            $FilePath2 = unpackDump($FilePath2);
        }
        
        if($FilePath1 and $FilePath2)
        {
            my $Line = readLineNum($FilePath1, 0);
            if($Line=~/xml/)
            { # XML format
                # is not supported yet
                return;
            }
            
            local $/ = undef;
            
            open(DUMP1, $FilePath1);
            my $Content1 = <DUMP1>;
            close(DUMP1);
            
            open(DUMP2, $FilePath2);
            my $Content2 = <DUMP2>;
            close(DUMP2);
            
            if($Content1 eq $Content2)
            {
                # clean memory
                undef $Content2;
                
                # read a number of headers, libs, symbols and types
                my $ABIdump = eval($Content1);
                
                # clean memory
                undef $Content1;
                
                if(not $ABIdump) {
                    exitStatus("Error", "internal error - eval() procedure seem to not working correctly, try to remove 'use strict' and try again");
                }
                if(not $ABIdump->{"TypeInfo"})
                { # support for old dumps
                    $ABIdump->{"TypeInfo"} = $ABIdump->{"TypeDescr"};
                }
                if(not $ABIdump->{"SymbolInfo"})
                { # support for old dumps
                    $ABIdump->{"SymbolInfo"} = $ABIdump->{"FuncDescr"};
                }
                read_Source_DumpInfo($ABIdump, 1);
                read_Libs_DumpInfo($ABIdump, 1);
                read_Machine_DumpInfo($ABIdump, 1);
                read_Machine_DumpInfo($ABIdump, 2);
                
                %{$CheckedTypes{"Binary"}} = %{$ABIdump->{"TypeInfo"}};
                %{$CheckedTypes{"Source"}} = %{$ABIdump->{"TypeInfo"}};
                
                foreach my $S (keys(%{$ABIdump->{"SymbolInfo"}}))
                {
                    if(my $Class = $ABIdump->{"SymbolInfo"}{$S}{"Class"})
                    {
                        if(defined $ABIdump->{"TypeInfo"}{$Class}{"PrivateABI"}) {
                            next;
                        }
                    }
                    
                    my $Access = $ABIdump->{"SymbolInfo"}{$S}{"Access"};
                    if($Access ne "private")
                    {
                        $CheckedSymbols{"Binary"}{$S} = 1;
                        $CheckedSymbols{"Source"}{$S} = 1;
                    }
                }
                
                $Descriptor{1}{"Version"} = $TargetVersion{1}?$TargetVersion{1}:$ABIdump->{"LibraryVersion"};
                $Descriptor{2}{"Version"} = $TargetVersion{2}?$TargetVersion{2}:$ABIdump->{"LibraryVersion"};
                exitReport();
            }
        }
    }
}

sub initLogging($)
{
    my $LibVersion = $_[0];
    # create log directory
    my ($LOG_DIR, $LOG_FILE) = ("logs/$TargetLibraryName/".$Descriptor{$LibVersion}{"Version"}, "log.txt");
    if($OutputLogPath{$LibVersion})
    { # user-defined by -log-path option
        ($LOG_DIR, $LOG_FILE) = separate_path($OutputLogPath{$LibVersion});
    }
    if($LogMode ne "n") {
        mkpath($LOG_DIR);
    }
    $LOG_PATH{$LibVersion} = get_abs_path($LOG_DIR)."/".$LOG_FILE;
    if($Debug)
    { # debug directory
        $DEBUG_PATH{$LibVersion} = "debug/$TargetLibraryName/".$Descriptor{$LibVersion}{"Version"};
        
        if(not $ExtraInfo)
        { # enable --extra-info
            $ExtraInfo = $DEBUG_PATH{$LibVersion}."/extra-info";
        }
    }
    resetLogging($LibVersion);
}

sub writeLog($$)
{
    my ($LibVersion, $Msg) = @_;
    if($LogMode ne "n") {
        appendFile($LOG_PATH{$LibVersion}, $Msg);
    }
}

sub resetLogging($)
{
    my $LibVersion = $_[0];
    if($LogMode!~/a|n/)
    { # remove old log
        unlink($LOG_PATH{$LibVersion});
        if($Debug) {
            rmtree($DEBUG_PATH{$LibVersion});
        }
    }
}

sub printErrorLog($)
{
    my $LibVersion = $_[0];
    if($LogMode ne "n") {
        printMsg("ERROR", "see log for details:\n  ".$LOG_PATH{$LibVersion}."\n");
    }
}

sub isDump($)
{
    if(get_filename($_[0])=~/\A(.+)\.(abi|abidump|dump)(\.tar\.gz(\.\w+|)|\.zip|\.xml|)\Z/)
    { # NOTE: name.abi.tar.gz.amd64 (dh & cdbs)
        return $1;
    }
    return 0;
}

sub isDump_U($)
{
    if(get_filename($_[0])=~/\A(.+)\.(abi|abidump|dump)(\.xml|)\Z/) {
        return $1;
    }
    return 0;
}

sub compareInit()
{
    # read input XML descriptors or ABI dumps
    if(not $Descriptor{1}{"Path"}) {
        exitStatus("Error", "-old option is not specified");
    }
    if(not -e $Descriptor{1}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$Descriptor{1}{"Path"}."\'");
    }
    
    if(not $Descriptor{2}{"Path"}) {
        exitStatus("Error", "-new option is not specified");
    }
    if(not -e $Descriptor{2}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$Descriptor{2}{"Path"}."\'");
    }
    
    detect_default_paths("bin"); # to extract dumps
    if(isDump($Descriptor{1}{"Path"})
    and isDump($Descriptor{2}{"Path"}))
    { # optimization: equal ABI dumps
        quickEmptyReports();
    }
    
    printMsg("INFO", "preparation, please wait ...");
    
    if(isDump($Descriptor{1}{"Path"})) {
        read_ABI_Dump(1, $Descriptor{1}{"Path"});
    }
    else {
        readDescriptor(1, createDescriptor(1, $Descriptor{1}{"Path"}));
    }
    
    if(isDump($Descriptor{2}{"Path"})) {
        read_ABI_Dump(2, $Descriptor{2}{"Path"});
    }
    else {
        readDescriptor(2, createDescriptor(2, $Descriptor{2}{"Path"}));
    }
    
    if(not $Descriptor{1}{"Version"})
    { # set to default: X
        $Descriptor{1}{"Version"} = "X";
        print STDERR "WARNING: version number #1 is not set (use --v1=NUM option)\n";
    }
    
    if(not $Descriptor{2}{"Version"})
    { # set to default: Y
        $Descriptor{2}{"Version"} = "Y";
        print STDERR "WARNING: version number #2 is not set (use --v2=NUM option)\n";
    }
    
    if(not $UsedDump{1}{"V"}) {
        initLogging(1);
    }
    
    if(not $UsedDump{2}{"V"}) {
        initLogging(2);
    }
    
    # check input data
    if(not $Descriptor{1}{"Headers"}) {
        exitStatus("Error", "can't find header files info in descriptor d1");
    }
    if(not $Descriptor{2}{"Headers"}) {
        exitStatus("Error", "can't find header files info in descriptor d2");
    }
    
    if(not $CheckHeadersOnly)
    {
        if(not $Descriptor{1}{"Libs"}) {
            exitStatus("Error", "can't find libraries info in descriptor d1");
        }
        if(not $Descriptor{2}{"Libs"}) {
            exitStatus("Error", "can't find libraries info in descriptor d2");
        }
    }
    
    if($UseDumps)
    { # --use-dumps
      # parallel processing
        my $DumpPath1 = defaultDumpPath($TargetLibraryName, $Descriptor{1}{"Version"});
        my $DumpPath2 = defaultDumpPath($TargetLibraryName, $Descriptor{2}{"Version"});
        
        unlink($DumpPath1);
        unlink($DumpPath2);
        
        my $pid = fork();
        if($pid)
        { # dump on two CPU cores
            my @PARAMS = ("-dump", $Descriptor{1}{"Path"}, "-l", $TargetLibraryName);
            if($RelativeDirectory{1}) {
                @PARAMS = (@PARAMS, "-relpath", $RelativeDirectory{1});
            }
            if($OutputLogPath{1}) {
                @PARAMS = (@PARAMS, "-log-path", $OutputLogPath{1});
            }
            if($CrossGcc) {
                @PARAMS = (@PARAMS, "-cross-gcc", $CrossGcc);
            }
            if($Quiet)
            {
                @PARAMS = (@PARAMS, "-quiet");
                @PARAMS = (@PARAMS, "-logging-mode", "a");
            }
            elsif($LogMode and $LogMode ne "w")
            { # "w" is default
                @PARAMS = (@PARAMS, "-logging-mode", $LogMode);
            }
            if($ExtendedCheck) {
                @PARAMS = (@PARAMS, "-extended");
            }
            if($UserLang) {
                @PARAMS = (@PARAMS, "-lang", $UserLang);
            }
            if($TargetVersion{1}) {
                @PARAMS = (@PARAMS, "-vnum", $TargetVersion{1});
            }
            if($BinaryOnly) {
                @PARAMS = (@PARAMS, "-binary");
            }
            if($SourceOnly) {
                @PARAMS = (@PARAMS, "-source");
            }
            if($SortDump) {
                @PARAMS = (@PARAMS, "-sort");
            }
            if($DumpFormat and $DumpFormat ne "perl") {
                @PARAMS = (@PARAMS, "-dump-format", $DumpFormat);
            }
            if($CheckHeadersOnly) {
                @PARAMS = (@PARAMS, "-headers-only");
            }
            if($Debug)
            {
                @PARAMS = (@PARAMS, "-debug");
                printMsg("INFO", "running perl $0 @PARAMS");
            }
            system("perl", $0, @PARAMS);
            if(not -f $DumpPath1) {
                exit(1);
            }
        }
        else
        { # child
            my @PARAMS = ("-dump", $Descriptor{2}{"Path"}, "-l", $TargetLibraryName);
            if($RelativeDirectory{2}) {
                @PARAMS = (@PARAMS, "-relpath", $RelativeDirectory{2});
            }
            if($OutputLogPath{2}) {
                @PARAMS = (@PARAMS, "-log-path", $OutputLogPath{2});
            }
            if($CrossGcc) {
                @PARAMS = (@PARAMS, "-cross-gcc", $CrossGcc);
            }
            if($Quiet)
            {
                @PARAMS = (@PARAMS, "-quiet");
                @PARAMS = (@PARAMS, "-logging-mode", "a");
            }
            elsif($LogMode and $LogMode ne "w")
            { # "w" is default
                @PARAMS = (@PARAMS, "-logging-mode", $LogMode);
            }
            if($ExtendedCheck) {
                @PARAMS = (@PARAMS, "-extended");
            }
            if($UserLang) {
                @PARAMS = (@PARAMS, "-lang", $UserLang);
            }
            if($TargetVersion{2}) {
                @PARAMS = (@PARAMS, "-vnum", $TargetVersion{2});
            }
            if($BinaryOnly) {
                @PARAMS = (@PARAMS, "-binary");
            }
            if($SourceOnly) {
                @PARAMS = (@PARAMS, "-source");
            }
            if($SortDump) {
                @PARAMS = (@PARAMS, "-sort");
            }
            if($DumpFormat and $DumpFormat ne "perl") {
                @PARAMS = (@PARAMS, "-dump-format", $DumpFormat);
            }
            if($CheckHeadersOnly) {
                @PARAMS = (@PARAMS, "-headers-only");
            }
            if($Debug)
            {
                @PARAMS = (@PARAMS, "-debug");
                printMsg("INFO", "running perl $0 @PARAMS");
            }
            system("perl", $0, @PARAMS);
            if(not -f $DumpPath2) {
                exit(1);
            }
            else {
                exit(0);
            }
        }
        waitpid($pid, 0);
        
        my @CMP_PARAMS = ("-l", $TargetLibraryName);
        @CMP_PARAMS = (@CMP_PARAMS, "-d1", $DumpPath1);
        @CMP_PARAMS = (@CMP_PARAMS, "-d2", $DumpPath2);
        if($TargetTitle ne $TargetLibraryName) {
            @CMP_PARAMS = (@CMP_PARAMS, "-title", $TargetTitle);
        }
        if($ShowRetVal) {
            @CMP_PARAMS = (@CMP_PARAMS, "-show-retval");
        }
        if($CrossGcc) {
            @CMP_PARAMS = (@CMP_PARAMS, "-cross-gcc", $CrossGcc);
        }
        @CMP_PARAMS = (@CMP_PARAMS, "-logging-mode", "a");
        if($Quiet) {
            @CMP_PARAMS = (@CMP_PARAMS, "-quiet");
        }
        if($ReportFormat and $ReportFormat ne "html")
        { # HTML is default format
            @CMP_PARAMS = (@CMP_PARAMS, "-report-format", $ReportFormat);
        }
        if($OutputReportPath) {
            @CMP_PARAMS = (@CMP_PARAMS, "-report-path", $OutputReportPath);
        }
        if($BinaryReportPath) {
            @CMP_PARAMS = (@CMP_PARAMS, "-bin-report-path", $BinaryReportPath);
        }
        if($SourceReportPath) {
            @CMP_PARAMS = (@CMP_PARAMS, "-src-report-path", $SourceReportPath);
        }
        if($LoggingPath) {
            @CMP_PARAMS = (@CMP_PARAMS, "-log-path", $LoggingPath);
        }
        if($CheckHeadersOnly) {
            @CMP_PARAMS = (@CMP_PARAMS, "-headers-only");
        }
        if($BinaryOnly) {
            @CMP_PARAMS = (@CMP_PARAMS, "-binary");
        }
        if($SourceOnly) {
            @CMP_PARAMS = (@CMP_PARAMS, "-source");
        }
        if($Debug)
        {
            @CMP_PARAMS = (@CMP_PARAMS, "-debug");
            printMsg("INFO", "running perl $0 @CMP_PARAMS");
        }
        system("perl", $0, @CMP_PARAMS);
        exit($?>>8);
    }
    if(not $Descriptor{1}{"Dump"}
    or not $Descriptor{2}{"Dump"})
    { # need GCC toolchain to analyze
      # header files and libraries
        detect_default_paths("inc|lib|gcc");
    }
    if(not $Descriptor{1}{"Dump"})
    {
        if(not $CheckHeadersOnly) {
            readLibs(1);
        }
        if($CheckHeadersOnly) {
            setLanguage(1, "C++");
        }
        searchForHeaders(1);
        $WORD_SIZE{1} = detectWordSize(1);
    }
    if(not $Descriptor{2}{"Dump"})
    {
        if(not $CheckHeadersOnly) {
            readLibs(2);
        }
        if($CheckHeadersOnly) {
            setLanguage(2, "C++");
        }
        searchForHeaders(2);
        $WORD_SIZE{2} = detectWordSize(2);
    }
    if($WORD_SIZE{1} ne $WORD_SIZE{2})
    { # support for old ABI dumps
      # try to synch different WORD sizes
        if(not checkDump(1, "2.1"))
        {
            $WORD_SIZE{1} = $WORD_SIZE{2};
            printMsg("WARNING", "set WORD size to ".$WORD_SIZE{2}." bytes");
        }
        elsif(not checkDump(2, "2.1"))
        {
            $WORD_SIZE{2} = $WORD_SIZE{1};
            printMsg("WARNING", "set WORD size to ".$WORD_SIZE{1}." bytes");
        }
    }
    elsif(not $WORD_SIZE{1}
    and not $WORD_SIZE{2})
    { # support for old ABI dumps
        $WORD_SIZE{1} = "4";
        $WORD_SIZE{2} = "4";
    }
    if($Descriptor{1}{"Dump"})
    { # support for old ABI dumps
        prepareTypes(1);
    }
    if($Descriptor{2}{"Dump"})
    { # support for old ABI dumps
        prepareTypes(2);
    }
    if($AppPath and not keys(%{$Symbol_Library{1}})) {
        printMsg("WARNING", "the application ".get_filename($AppPath)." has no symbols imported from the $SLIB_TYPE libraries");
    }
    # process input data
    if($Descriptor{1}{"Headers"}
    and not $Descriptor{1}{"Dump"}) {
        readHeaders(1);
    }
    if($Descriptor{2}{"Headers"}
    and not $Descriptor{2}{"Dump"}) {
        readHeaders(2);
    }
    
    # clean memory
    %SystemHeaders = ();
    %mangled_name_gcc = ();
    
    prepareSymbols(1);
    prepareSymbols(2);
    
    # clean memory
    %SymbolInfo = ();
    
    # Virtual Tables
    registerVTable(1);
    registerVTable(2);

    if(not checkDump(1, "1.22")
    and checkDump(2, "1.22"))
    { # support for old ABI dumps
        foreach my $ClassName (keys(%{$VirtualTable{2}}))
        {
            if($ClassName=~/</)
            { # templates
                if(not defined $VirtualTable{1}{$ClassName})
                { # synchronize
                    delete($VirtualTable{2}{$ClassName});
                }
            }
        }
    }
    
    registerOverriding(1);
    registerOverriding(2);
    
    setVirtFuncPositions(1);
    setVirtFuncPositions(2);
    
    # Other
    addParamNames(1);
    addParamNames(2);
    
    detectChangedTypedefs();
}

sub compareAPIs($)
{
    my $Level = $_[0];
    
    readRules($Level);
    loadModule("CallConv");
    
    if($Level eq "Binary") {
        printMsg("INFO", "comparing ABIs ...");
    }
    else {
        printMsg("INFO", "comparing APIs ...");
    }
    
    if($CheckHeadersOnly
    or $Level eq "Source")
    { # added/removed in headers
        detectAdded_H($Level);
        detectRemoved_H($Level);
    }
    else
    { # added/removed in libs
        detectAdded($Level);
        detectRemoved($Level);
    }
    
    mergeSymbols($Level);
    if(keys(%{$CheckedSymbols{$Level}})) {
        mergeConstants($Level);
    }
    
    $Cache{"mergeTypes"} = (); # free memory
    
    if($CheckHeadersOnly
    or $Level eq "Source")
    { # added/removed in headers
        mergeHeaders($Level);
    }
    else
    { # added/removed in libs
        mergeLibs($Level);
    }
    
    foreach my $S (keys(%{$CompatProblems{$Level}}))
    {
        foreach my $K (keys(%{$CompatProblems{$Level}{$S}}))
        {
            foreach my $L (keys(%{$CompatProblems{$Level}{$S}{$K}}))
            {
                if(my $T = $CompatProblems{$Level}{$S}{$K}{$L}{"Type_Name"}) {
                    $TypeProblemsIndex{$Level}{$T}{$S} = 1;
                }
            }
        }
    }
}

sub getSysOpts()
{
    my %Opts = (
    "OStarget"=>$OStarget,
    "Debug"=>$Debug,
    "Quiet"=>$Quiet,
    "LogMode"=>$LogMode,
    "CheckHeadersOnly"=>$CheckHeadersOnly,
    
    "SystemRoot"=>$SystemRoot,
    "GCC_PATH"=>$GCC_PATH,
    "TargetSysInfo"=>$TargetSysInfo,
    "CrossPrefix"=>$CrossPrefix,
    "TargetLibraryName"=>$TargetLibraryName,
    "CrossGcc"=>$CrossGcc,
    "UseStaticLibs"=>$UseStaticLibs,
    "NoStdInc"=>$NoStdInc,
    
    "BinaryOnly" => $BinaryOnly,
    "SourceOnly" => $SourceOnly
    );
    return \%Opts;
}

sub get_CodeError($)
{
    my %CODE_ERROR = reverse(%ERROR_CODE);
    return $CODE_ERROR{$_[0]};
}

sub scenario()
{
    if($StdOut)
    { # enable quiet mode
        $Quiet = 1;
        $JoinReport = 1;
    }
    if(not $LogMode)
    { # default
        $LogMode = "w";
    }
    if($UserLang)
    { # --lang=C++
        $UserLang = uc($UserLang);
        $COMMON_LANGUAGE{1}=$UserLang;
        $COMMON_LANGUAGE{2}=$UserLang;
    }
    if($LoggingPath)
    {
        $OutputLogPath{1} = $LoggingPath;
        $OutputLogPath{2} = $LoggingPath;
        if($Quiet) {
            $COMMON_LOG_PATH = $LoggingPath;
        }
    }
    
    if($Quick) {
        $ADD_TMPL_INSTANCES = 0;
    }
    if($OutputDumpPath)
    { # validate
        if(not isDump($OutputDumpPath)) {
            exitStatus("Error", "the dump path should be a path to *.abi.$AR_EXT or *.abi file");
        }
    }
    if($BinaryOnly and $SourceOnly)
    { # both --binary and --source
      # is the default mode
        if(not $CmpSystems)
        {
            $BinaryOnly = 0;
            $SourceOnly = 0;
        }
        
        $DoubleReport = 1;
        $JoinReport = 0;
        
        if($OutputReportPath)
        { # --report-path
            $DoubleReport = 0;
            $JoinReport = 1;
        }
    }
    elsif($BinaryOnly or $SourceOnly)
    { # --binary or --source
        $DoubleReport = 0;
        $JoinReport = 0;
    }
    if($UseXML)
    { # --xml option
        $ReportFormat = "xml";
        $DumpFormat = "xml";
    }
    if($ReportFormat)
    { # validate
        $ReportFormat = lc($ReportFormat);
        if($ReportFormat!~/\A(xml|html|htm)\Z/) {
            exitStatus("Error", "unknown report format \'$ReportFormat\'");
        }
        if($ReportFormat eq "htm")
        { # HTM == HTML
            $ReportFormat = "html";
        }
        elsif($ReportFormat eq "xml")
        { # --report-format=XML equal to --xml
            $UseXML = 1;
        }
    }
    else
    { # default: HTML
        $ReportFormat = "html";
    }
    if($DumpFormat)
    { # validate
        $DumpFormat = lc($DumpFormat);
        if($DumpFormat!~/\A(xml|perl)\Z/) {
            exitStatus("Error", "unknown ABI dump format \'$DumpFormat\'");
        }
        if($DumpFormat eq "xml")
        { # --dump-format=XML equal to --xml
            $UseXML = 1;
        }
    }
    else
    { # default: Perl Data::Dumper
        $DumpFormat = "perl";
    }
    if($Quiet and $LogMode!~/a|n/)
    { # --quiet log
        if(-f $COMMON_LOG_PATH) {
            unlink($COMMON_LOG_PATH);
        }
    }
    if($ExtraInfo) {
        $CheckUndefined = 1;
    }
    if($TestTool and $UseDumps)
    { # --test && --use-dumps == --test-dump
        $TestDump = 1;
    }
    if($Tolerant)
    { # enable all
        $Tolerance = 1234;
    }
    if($Help)
    {
        HELP_MESSAGE();
        exit(0);
    }
    if($InfoMsg)
    {
        INFO_MESSAGE();
        exit(0);
    }
    if($ShowVersion)
    {
        printMsg("INFO", "ABI Compliance Checker (ABICC) $TOOL_VERSION\nCopyright (C) 2015 Andrey Ponomarenko's ABI Laboratory\nLicense: LGPL or GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion)
    {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    if($ExtendedCheck) {
        $CheckHeadersOnly = 1;
    }
    if($SystemRoot_Opt)
    { # user defined root
        if(not -e $SystemRoot_Opt) {
            exitStatus("Access_Error", "can't access \'$SystemRoot\'");
        }
        $SystemRoot = $SystemRoot_Opt;
        $SystemRoot=~s/[\/]+\Z//g;
        if($SystemRoot) {
            $SystemRoot = get_abs_path($SystemRoot);
        }
    }
    $Data::Dumper::Sortkeys = 1;
    
    if($SortDump)
    {
        $Data::Dumper::Useperl = 1;
        $Data::Dumper::Sortkeys = \&dump_sorting;
    }
    
    if($TargetLibsPath)
    {
        if(not -f $TargetLibsPath) {
            exitStatus("Access_Error", "can't access file \'$TargetLibsPath\'");
        }
        foreach my $Lib (split(/\s*\n\s*/, readFile($TargetLibsPath))) {
            $TargetLibs{$Lib} = 1;
        }
    }
    if($TargetHeadersPath)
    { # --headers-list
        if(not -f $TargetHeadersPath) {
            exitStatus("Access_Error", "can't access file \'$TargetHeadersPath\'");
        }
        foreach my $Header (split(/\s*\n\s*/, readFile($TargetHeadersPath)))
        {
            $TargetHeaders{1}{get_filename($Header)} = 1;
            $TargetHeaders{2}{get_filename($Header)} = 1;
        }
    }
    if($TargetHeader)
    { # --header
        $TargetHeaders{1}{get_filename($TargetHeader)} = 1;
        $TargetHeaders{2}{get_filename($TargetHeader)} = 1;
    }
    if($TestTool
    or $TestDump)
    { # --test, --test-dump
        detect_default_paths("bin|gcc"); # to compile libs
        loadModule("RegTests");
        testTool($TestDump, $Debug, $Quiet, $ExtendedCheck, $LogMode, $ReportFormat, $DumpFormat,
        $LIB_EXT, $GCC_PATH, $SortDump, $CheckHeadersOnly);
        exit(0);
    }
    if($DumpSystem)
    { # --dump-system
        
        if(not $TargetSysInfo) {
            exitStatus("Error", "-sysinfo option should be specified to dump system ABI");
        }
        
        if(not -d $TargetSysInfo) {
            exitStatus("Access_Error", "can't access \'$TargetSysInfo\'");
        }
        
        loadModule("SysCheck");
        if($DumpSystem=~/\.(xml|desc)\Z/)
        { # system XML descriptor
            if(not -f $DumpSystem) {
                exitStatus("Access_Error", "can't access file \'$DumpSystem\'");
            }
            
            my $SDesc = readFile($DumpSystem);
            if(my $RelDir = $RelativeDirectory{1}) {
                $SDesc =~ s/{RELPATH}/$RelDir/g;
            }
            
            my $Ret = readSystemDescriptor($SDesc);
            foreach (@{$Ret->{"Tools"}})
            {
                push_U($SystemPaths{"bin"}, $_);
                $TargetTools{$_} = 1;
            }
            if($Ret->{"CrossPrefix"}) {
                $CrossPrefix = $Ret->{"CrossPrefix"};
            }
        }
        elsif($SystemRoot_Opt)
        { # -sysroot "/" option
          # default target: /usr/lib, /usr/include
          # search libs: /usr/lib and /lib
            if(not -e $SystemRoot."/usr/lib") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/usr/lib'");
            }
            if(not -e $SystemRoot."/lib") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/lib'");
            }
            if(not -e $SystemRoot."/usr/include") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/usr/include'");
            }
            readSystemDescriptor("
                <name>
                    $DumpSystem
                </name>
                <headers>
                    $SystemRoot/usr/include
                </headers>
                <libs>
                    $SystemRoot/usr/lib
                </libs>
                <search_libs>
                    $SystemRoot/lib
                </search_libs>");
        }
        else {
            exitStatus("Error", "-sysroot <dirpath> option should be specified, usually it's \"/\"");
        }
        detect_default_paths("bin|gcc"); # to check symbols
        if($OStarget eq "windows")
        { # to run dumpbin.exe
          # and undname.exe
            check_win32_env();
        }
        dumpSystem(getSysOpts());
        exit(0);
    }
    
    if($CmpSystems)
    { # --cmp-systems
        detect_default_paths("bin"); # to extract dumps
        loadModule("SysCheck");
        cmpSystems($Descriptor{1}{"Path"}, $Descriptor{2}{"Path"}, getSysOpts());
        exit(0);
    }
    
    if(not $CountSymbols)
    {
        if(not $TargetLibraryName) {
            exitStatus("Error", "library name is not selected (-l option)");
        }
        else
        { # validate library name
            if($TargetLibraryName=~/[\*\/\\]/) {
                exitStatus("Error", "\"\\\", \"\/\" and \"*\" symbols are not allowed in the library name");
            }
        }
    }
    
    if(not $TargetTitle) {
        $TargetTitle = $TargetLibraryName;
    }
    
    if($SymbolsListPath)
    {
        if(not -f $SymbolsListPath) {
            exitStatus("Access_Error", "can't access file \'$SymbolsListPath\'");
        }
        foreach my $Interface (split(/\s*\n\s*/, readFile($SymbolsListPath))) {
            $SymbolsList{$Interface} = 1;
        }
    }
    if($TypesListPath)
    {
        if(not -f $TypesListPath) {
            exitStatus("Access_Error", "can't access file \'$TypesListPath\'");
        }
        foreach my $Type (split(/\s*\n\s*/, readFile($TypesListPath))) {
            $TypesList{$Type} = 1;
        }
    }
    if($SkipSymbolsListPath)
    {
        if(not -f $SkipSymbolsListPath) {
            exitStatus("Access_Error", "can't access file \'$SkipSymbolsListPath\'");
        }
        foreach my $Interface (split(/\s*\n\s*/, readFile($SkipSymbolsListPath)))
        {
            $SkipSymbols{1}{$Interface} = 1;
            $SkipSymbols{2}{$Interface} = 1;
        }
    }
    if($SkipTypesListPath)
    {
        if(not -f $SkipTypesListPath) {
            exitStatus("Access_Error", "can't access file \'$SkipTypesListPath\'");
        }
        foreach my $Type (split(/\s*\n\s*/, readFile($SkipTypesListPath)))
        {
            $SkipTypes{1}{$Type} = 1;
            $SkipTypes{2}{$Type} = 1;
        }
    }
    if($SkipHeadersPath)
    {
        if(not -f $SkipHeadersPath) {
            exitStatus("Access_Error", "can't access file \'$SkipHeadersPath\'");
        }
        foreach my $Path (split(/\s*\n\s*/, readFile($SkipHeadersPath)))
        { # register for both versions
            $SkipHeadersList{1}{$Path} = 1;
            $SkipHeadersList{2}{$Path} = 1;
            
            my ($CPath, $Type) = classifyPath($Path);
            $SkipHeaders{1}{$Type}{$CPath} = 1;
            $SkipHeaders{2}{$Type}{$CPath} = 1;
        }
    }
    if($ParamNamesPath)
    {
        if(not -f $ParamNamesPath) {
            exitStatus("Access_Error", "can't access file \'$ParamNamesPath\'");
        }
        foreach my $Line (split(/\n/, readFile($ParamNamesPath)))
        {
            if($Line=~s/\A(\w+)\;//)
            {
                my $Interface = $1;
                if($Line=~/;(\d+);/)
                {
                    while($Line=~s/(\d+);(\w+)//) {
                        $AddIntParams{$Interface}{$1}=$2;
                    }
                }
                else
                {
                    my $Num = 0;
                    foreach my $Name (split(/;/, $Line)) {
                        $AddIntParams{$Interface}{$Num++}=$Name;
                    }
                }
            }
        }
    }
    
    if($AppPath)
    {
        if(not -f $AppPath) {
            exitStatus("Access_Error", "can't access file \'$AppPath\'");
        }
        
        detect_default_paths("bin|gcc");
        foreach my $Interface (readSymbols_App($AppPath)) {
            $SymbolsList_App{$Interface} = 1;
        }
    }
    
    if($CountSymbols)
    {
        if(not -e $CountSymbols) {
            exitStatus("Access_Error", "can't access \'$CountSymbols\'");
        }
        
        read_ABI_Dump(1, $CountSymbols);
        
        foreach my $Id (keys(%{$SymbolInfo{1}}))
        {
            my $MnglName = $SymbolInfo{1}{$Id}{"MnglName"};
            if(not $MnglName) {
                $MnglName = $SymbolInfo{1}{$Id}{"ShortName"}
            }
            
            if(my $SV = $SymVer{1}{$MnglName}) {
                $CompleteSignature{1}{$SV} = $SymbolInfo{1}{$Id};
            }
            else {
                $CompleteSignature{1}{$MnglName} = $SymbolInfo{1}{$Id};
            }
            
            if(my $Alias = $CompleteSignature{1}{$MnglName}{"Alias"}) {
                $CompleteSignature{1}{$Alias} = $SymbolInfo{1}{$Id};
            }
        }
        
        my $Count = 0;
        foreach my $Symbol (sort keys(%{$CompleteSignature{1}}))
        {
            if($CompleteSignature{1}{$Symbol}{"PureVirt"}) {
                next;
            }
            if($CompleteSignature{1}{$Symbol}{"Private"}) {
                next;
            }
            if(not $CompleteSignature{1}{$Symbol}{"Header"}) {
                next;
            }
            
            $Count += symbolFilter($Symbol, 1, "Affected + InlineVirt", "Binary");
        }
        
        printMsg("INFO", $Count);
        exit(0);
    }
    
    if($DumpAPI)
    { # --dump-abi
      # make an API dump
        create_ABI_Dump();
        exit($COMPILE_ERRORS);
    }
    # default: compare APIs
    #  -d1 <path>
    #  -d2 <path>
    compareInit();
    if($JoinReport or $DoubleReport)
    {
        compareAPIs("Binary");
        compareAPIs("Source");
    }
    elsif($BinaryOnly) {
        compareAPIs("Binary");
    }
    elsif($SourceOnly) {
        compareAPIs("Source");
    }
    exitReport();
}

scenario();
