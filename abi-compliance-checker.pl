#!/usr/bin/perl
###########################################################################
# ABI Compliance Checker (ABICC) 2.0 Beta
# A tool for checking backward compatibility of a C/C++ library API
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2012-2016 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux, FreeBSD, Solaris, Mac OS X, MS Windows, Symbian, Haiku
#
# REQUIREMENTS
# ============
#  Linux
#    - G++ (3.0-4.7, 4.8.3, 4.9 or newer)
#    - GNU Binutils (readelf, c++filt, objdump)
#    - Perl 5
#    - Ctags
#    - ABI Dumper >= 0.99.15
#
#  Mac OS X
#    - Xcode (g++, c++filt, otool, nm)
#    - Ctags
#
#  MS Windows
#    - MinGW (3.0-4.7, 4.8.3, 4.9 or newer)
#    - MS Visual C++ (dumpbin, undname, cl)
#    - Active Perl 5 (5.8 or newer)
#    - Sigcheck v2.52 or newer
#    - GnuWin Zip and UnZip
#    - Ctags (Exuberant or Universal)
#    - Add tool locations to the PATH environment variable
#    - Run vcvars64.bat (C:\Microsoft Visual Studio 9.0\VC\bin\)
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
use File::Copy qw(copy);
use File::Basename qw(dirname);
use Cwd qw(abs_path cwd);
use Data::Dumper;

my $TOOL_VERSION = "2.0";
my $XML_REPORT_VERSION = "1.2";
my $ABI_DUMP_VERSION = "3.4";
my $ABI_DUMP_VERSION_MIN = "3.2";
my $XML_ABI_DUMP_VERSION = "1.2";

# Internal modules
my $MODULES_DIR = getModules();
push(@INC, dirname($MODULES_DIR));

# Basic modules
my %LoadedModules = ();
loadModule("Basic");
loadModule("Input");
loadModule("Utils");
loadModule("Logging");
loadModule("TypeAttr");
loadModule("Filter");
loadModule("SysFiles");
loadModule("Descriptor");
loadModule("Mangling");

# Rules DB
my %RULES_PATH = (
    "Binary" => $MODULES_DIR."/RulesBin.xml",
    "Source" => $MODULES_DIR."/RulesSrc.xml");

my $BYTE = 8;
my $CmdName = getFilename($0);

my %HomePage = (
    "Dev"=>"https://github.com/lvc/abi-compliance-checker",
    "Doc"=>"https://lvc.github.io/abi-compliance-checker/"
);

my $ShortUsage = "ABI Compliance Checker (ABICC) $TOOL_VERSION
A tool for checking backward compatibility of a C/C++ library API
Copyright (C) 2016 Andrey Ponomarenko's ABI Laboratory
License: GNU LGPL or GNU GPL

Usage: $CmdName [options]
Example: $CmdName -l NAME -old ABI-0.dump -new ABI-1.dump

ABI-0.dump and ABI-1.dump are ABI dumps generated
by the ABI Dumper or ABICC tools.

More info: $CmdName --help\n";

if($#ARGV==-1)
{
    printMsg("INFO", $ShortUsage);
    exit(0);
}

GetOptions(
  "h|help!" => \$In::Opt{"Help"},
  "i|info!" => \$In::Opt{"InfoMsg"},
  "v|version!" => \$In::Opt{"ShowVersion"},
  "dumpversion!" => \$In::Opt{"DumpVersion"},
# General
  "l|lib|library=s" => \$In::Opt{"TargetLib"},
  "d1|old|o=s" => \$In::Desc{1}{"Path"},
  "d2|new|n=s" => \$In::Desc{2}{"Path"},
  "dump|dump-abi|dump_abi=s" => \$In::Opt{"DumpABI"},
  "d|f|filter=s" => \$In::Opt{"FilterPath"},
# Extra
  "debug!" => \$In::Opt{"Debug"},
  "debug-mangling!" => \$In::Opt{"DebugMangling"},
  "ext|extended!" => \$In::Opt{"ExtendedCheck"},
  "static|static-libs!" => \$In::Opt{"UseStaticLibs"},
  "gcc-path|cross-gcc=s" => \$In::Opt{"CrossGcc"},
  "gcc-prefix|cross-prefix=s" => \$In::Opt{"CrossPrefix"},
  "gcc-options=s" => \$In::Opt{"GccOptions"},
  "count-symbols=s" => \$In::Opt{"CountSymbols"},
  "use-dumps!" => \$In::Opt{"UseDumps"},
  "xml!" => \$In::Opt{"UseXML"},
  "app|application=s" => \$In::Opt{"AppPath"},
  "headers-only!" => \$In::Opt{"CheckHeadersOnly"},
  "v1|vnum1|version1=s" => \$In::Desc{1}{"TargetVersion"},
  "v2|vnum2|version2=s" => \$In::Desc{2}{"TargetVersion"},
  "relpath1=s" => \$In::Desc{1}{"RelativeDirectory"},
  "relpath2=s" => \$In::Desc{2}{"RelativeDirectory"},
# Test
  "test!" => \$In::Opt{"TestTool"},
  "test-dump!" => \$In::Opt{"TestDump"},
  "test-abi-dumper!" => \$In::Opt{"TestABIDumper"},
# Report
  "s|strict!" => \$In::Opt{"StrictCompat"},
  "binary|bin|abi!" => \$In::Opt{"BinOnly"},
  "source|src|api!" => \$In::Opt{"SrcOnly"},
# Report path
  "report-path=s" => \$In::Opt{"OutputReportPath"},
  "bin-report-path=s" => \$In::Opt{"BinReportPath"},
  "src-report-path=s" => \$In::Opt{"SrcReportPath"},
# Report format
  "show-retval!" => \$In::Opt{"ShowRetVal"},
  "stdout!" => \$In::Opt{"StdOut"},
  "report-format=s" => \$In::Opt{"ReportFormat"},
  "old-style!" => \$In::Opt{"OldStyle"},
  "title=s" => \$In::Opt{"TargetTitle"},
  "component=s" => \$In::Opt{"TargetComponent"},
  "p|params=s" => \$In::Opt{"ParamNamesPath"},
  "limit-affected|affected-limit=s" => \$In::Opt{"AffectLimit"},
  "all-affected!" => \$In::Opt{"AllAffected"},
  "list-affected!" => \$In::Opt{"ListAffected"},
# ABI dump
  "dump-path=s" => \$In::Opt{"OutputDumpPath"},
  "dump-format=s" => \$In::Opt{"DumpFormat"},
  "check!" => \$In::Opt{"CheckInfo"},
  "extra-info=s" => \$In::Opt{"ExtraInfo"},
  "extra-dump!" => \$In::Opt{"ExtraDump"},
  "relpath=s" => \$In::Desc{1}{"RelativeDirectory"},
  "vnum=s" => \$In::Desc{1}{"TargetVersion"},
  "sort!" => \$In::Opt{"SortDump"},
# Filter symbols and types
  "symbols-list=s" => \$In::Opt{"SymbolsListPath"},
  "types-list=s" => \$In::Opt{"TypesListPath"},
  "skip-symbols=s" => \$In::Opt{"SkipSymbolsListPath"},
  "skip-types=s" => \$In::Opt{"SkipTypesListPath"},
  "skip-internal-symbols|skip-internal=s" => \$In::Opt{"SkipInternalSymbols"},
  "skip-internal-types=s" => \$In::Opt{"SkipInternalTypes"},
  "keep-cxx!" => \$In::Opt{"KeepCxx"},
# Filter header files
  "skip-headers=s" => \$In::Opt{"SkipHeadersPath"},
  "headers-list=s" => \$In::Opt{"TargetHeadersPath"},
  "header=s" => \$In::Opt{"TargetHeader"},
  "nostdinc!" => \$In::Opt{"NoStdInc"},
  "tolerance=s" => \$In::Opt{"Tolerance"},
  "tolerant!" => \$In::Opt{"Tolerant"},
  "skip-unidentified!" => \$In::Opt{"SkipUnidentified"},
# Filter rules
  "skip-typedef-uncover!" => \$In::Opt{"SkipTypedefUncover"},
  "check-private-abi!" => \$In::Opt{"CheckPrivateABI"},
  "disable-constants-check!" => \$In::Opt{"DisableConstantsCheck"},
  "skip-added-constants!" => \$In::Opt{"SkipAddedConstants"},
  "skip-removed-constants!" => \$In::Opt{"SkipRemovedConstants"},
# Other
  "lang=s" => \$In::Opt{"UserLang"},
  "arch=s" => \$In::Opt{"TargetArch"},
  "mingw-compatible!" => \$In::Opt{"MinGWCompat"},
  "cxx-incompatible|cpp-incompatible!" => \$In::Opt{"CxxIncompat"},
  "cpp-compatible!" => \$In::Opt{"CxxCompat"},
  "quick!" => \$In::Opt{"Quick"},
  "force!" => \$In::Opt{"Force"},
# OS analysis
  "dump-system=s" => \$In::Opt{"DumpSystem"},
  "cmp-systems!" => \$In::Opt{"CmpSystems"},
  "sysroot=s" => \$In::Opt{"SystemRoot"},
  "sysinfo=s" => \$In::Opt{"TargetSysInfo"},
  "libs-list=s" => \$In::Opt{"TargetLibsPath"},
# Logging
  "log-path=s" => \$In::Opt{"LoggingPath"},
  "log1-path=s" => \$In::Desc{1}{"OutputLogPath"},
  "log2-path=s" => \$In::Desc{2}{"OutputLogPath"},
  "logging-mode=s" => \$In::Opt{"LogMode"},
  "q|quiet!" => \$In::Opt{"Quiet"}
) or errMsg();

sub errMsg()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit(getErrorCode("Error"));
}

# Default log path
$In::Opt{"DefaultLog"} = "logs/run.log";

my $HelpMessage = "
NAME:
  ABI Compliance Checker ($CmdName)
  Check backward compatibility of a C/C++ library API

DESCRIPTION:
  ABI Compliance Checker (ABICC) is a tool for checking backward binary
  compatibility and backward source compatibility of a C/C++ library API.

  The tool analyzes changes in API and ABI (ABI=API+compiler ABI) that may
  break binary compatibility and/or source compatibility: changes in calling
  stack, v-table changes, removed symbols, renamed fields, etc.

  Binary incompatibility may result in crashing or incorrect behavior of
  applications built with an old version of a library if they run on a new
  one. Source incompatibility may result in recompilation errors with a new
  library version.

  The tool can create and compare ABI dumps for header files and shared
  objects of a library. The ABI dump for a library can also be created by
  the ABI Dumper tool (https://github.com/lvc/abi-dumper) if shared objects
  include debug-info.

  The tool is intended for developers of software libraries and maintainers
  of operating systems who are interested in ensuring backward compatibility,
  i.e. allow old applications to run or to be recompiled with newer library
  versions.

  Also the tool can be used by ISVs for checking applications portability to
  new library versions. Found issues can be taken into account when adapting
  the application to a new library version.

  This tool is free software: you can redistribute it and/or modify it
  under the terms of the GNU LGPL or GNU GPL.

USAGE #1 (WITH ABI DUMPER):

  1. Library should be compiled with \"-g -Og\" GCC options
     to contain DWARF debug info

  2. Create ABI dumps for both library versions
     using the ABI Dumper (https://github.com/lvc/abi-dumper) tool:

       abi-dumper OLD.so -o ABI-0.dump -lver 0
       abi-dumper NEW.so -o ABI-1.dump -lver 1

  3. You can filter public ABI with the help of
     additional -public-headers option of the ABI Dumper tool.

  4. Compare ABI dumps to create report:

       abi-compliance-checker -l NAME -old ABI-0.dump -new ABI-1.dump

USAGE #2 (ORIGINAL):

  1. Create XML-descriptors for two versions
     of a library (OLD.xml and NEW.xml):

       <version>
           1.0
       </version>

       <headers>
           /path/to/headers/
       </headers>

       <libs>
           /path/to/libraries/
       </libs>

  2. Compare Xml-descriptors to create report:

       abi-compliance-checker -lib NAME -old OLD.xml -new NEW.xml

USAGE #3 (CREATE ABI DUMPS):

  1. Create XML-descriptors for two versions
     of a library (OLD.xml and NEW.xml):

       <version>
           1.0
       </version>

       <headers>
           /path/to/headers/
       </headers>

       <libs>
           /path/to/libraries/
       </libs>

  2. Create ABI dumps:
  
       abi-compliance-checker -lib NAME -dump OLD.xml -dump-path ./ABI-0.dump
       abi-compliance-checker -lib NAME -dump NEW.xml -dump-path ./ABI-1.dump

  3. Compare ABI dumps to create report:

       abi-compliance-checker -l NAME -old ABI-0.dump -new ABI-1.dump

INFO OPTIONS:
  -h|-help
      Print this help.

  -i|-info
      Print complete info including all options.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -l|-library NAME
      Any name of the library.

  -old|-d1 PATH
      Descriptor of the 1st (old) library version.
      It may be one of the following:
      
         1. ABI dump generated by the ABI Dumper tool
         2. XML-descriptor (*.xml file):

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
             
         3. ABI dump generated by -dump option
         4. Directory with headers and libraries
         5. Single header file

      If you are using 4-5 descriptor types then you should
      specify version numbers with -v1 and -v2 options.

      For more information, please see:
        https://lvc.github.io/abi-compliance-checker/Xml-Descriptor.html

  -new|-d2 PATH
      Descriptor of the 2nd (new) library version.

  -dump PATH
      Create library ABI dump for the input XML descriptor. You can
      transfer it anywhere and pass instead of the descriptor. Also
      it can be used for debugging the tool.
  
  -filter PATH
      A path to XML descriptor with skip_* rules to filter
      analyzed symbols in the report.
";

sub helpMsg() {
    printMsg("INFO", $HelpMessage."
MORE OPTIONS:
     $CmdName --info\n");
}

sub infoMsg()
{
    printMsg("INFO", "$HelpMessage
EXTRA OPTIONS:
  -debug
      Debugging mode. Print debug info on the screen. Save intermediate
      analysis stages in the debug directory:
          debug/LIB_NAME/VERSION/

      Also consider using -dump option for debugging the tool.

  -ext|-extended
      If your library A is supposed to be used by other library B and you
      want to control the ABI of B, then you should enable this option. The
      tool will check for changes in all data types, even if they are not
      used by any function in the library A. Such data types are not part
      of the A library ABI, but may be a part of the ABI of the B library.
      
      The short scheme is:
        app C (broken) -> lib B (broken ABI) -> lib A (stable ABI)

  -static
      Check static libraries instead of the shared ones. The <libs> section
      of the XML-descriptor should point to static libraries location.

  -gcc-path PATH
      Path to the cross GCC compiler to use instead of the usual (host) GCC.

  -gcc-prefix PREFIX
      GCC toolchain prefix.

  -gcc-options OPTS
      Additional compiler options.

  -count-symbols PATH
      Count total public symbols in the ABI dump.

  -use-dumps
      Make dumps for two versions of a library and compare dumps. This should
      increase the performance of the tool and decrease the system memory usage.

  -xml
      Alias for: --report-format=xml or --dump-format=xml

  -app|-application PATH
      This option allows to specify the application that should be checked
      for portability to the new library version.

  -headers-only
      Check header files without libraries. It is easy to run, but may
      provide a low quality compatibility report with false positives and
      without detecting of added/removed symbols.

  -v1|-vnum1 NUM
      Specify 1st library version outside the descriptor. This option is needed
      if you have preferred an alternative descriptor type (see -d1 option).

      In general case you should specify it in the XML-descriptor:
          <version>
              VERSION
          </version>

  -v2|-vnum2 NUM
      Specify 2nd library version outside the descriptor.

  -relpath1 PATH
      Replace {RELPATH} macros to PATH in the 1st XML-descriptor (-d1).

  -relpath2 PATH
      Replace {RELPATH} macros to PATH in the 2nd XML-descriptor (-d2).

TEST OPTIONS:
  -test
      Run internal tests. Create two binary incompatible versions of a sample
      library and run the tool to check them for compatibility. This option
      allows to check if the tool works correctly in the current environment.

  -test-dump
      Test ability to create, read and compare ABI dumps.

  -test-abi-dumper
      Compare ABI dumps created by the ABI Dumper tool.

REPORT OPTIONS:
  -binary|-bin|-abi
      Show \"Binary\" compatibility problems only.
      Generate report to:
        compat_reports/LIB_NAME/V1_to_V2/abi_compat_report.html

  -source|-src|-api
      Show \"Source\" compatibility problems only.
      Generate report to:
        compat_reports/LIB_NAME/V1_to_V2/src_compat_report.html

  -s|-strict
      Treat all compatibility warnings as problems. Add a number of \"Low\"
      severity problems to the return value of the tool.

REPORT PATH OPTIONS:
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

REPORT FORMAT OPTIONS:
  -show-retval
      Show the symbol's return type in the report.

  -stdout
      Print analysis results (compatibility reports and ABI dumps) to stdout
      instead of creating a file. This would allow piping data to other programs.

  -report-format FMT
      Change format of compatibility report.
      Formats:
        htm - HTML format (default)
        xml - XML format

  -old-style
      Generate old-style report.

  -title NAME
      Change library name in the report title to NAME. By default
      will be displayed a name specified by -l option.

  -component NAME
      The component name in the title and summary of the HTML report.
      Default:
          library

  -p|-params PATH
      Path to file with the function parameter names. It can be used
      for improving report view if the library header files have no
      parameter names. File format:
      
            func1;param1;param2;param3 ...
            func2;param1;param2;param3 ...
             ...

  -limit-affected LIMIT
      The maximum number of affected symbols listed under the description
      of the changed type in the report.

  -list-affected
      Generate file with the list of incompatible
      symbols beside the HTML compatibility report.
      Use 'c++filt \@file' command from GNU binutils
      to unmangle C++ symbols in the generated file.
      Default names:
          abi_affected.txt
          src_affected.txt

ABI DUMP OPTIONS:
  -dump-path PATH
      Specify a *.dump file path where to generate an ABI dump.
      Default: 
          abi_dumps/LIB_NAME/VERSION/ABI.dump

  -dump-format FMT
      Change format of ABI dump.
      Formats:
        perl - Data::Dumper format (default)
        xml - XML format

  -check
      Check completeness of the ABI dump.

  -extra-info DIR
      Dump extra info to DIR.

  -extra-dump
      Create extended ABI dump containing all symbols
      from the translation unit.

  -relpath PATH
      Replace {RELPATH} macros to PATH in the XML-descriptor used
      for dumping the library ABI (see -dump option).

  -vnum NUM
      Specify the library version in the generated ABI dump. The <version> section
      of the input XML descriptor will be overwritten in this case.

  -sort
      Enable sorting of data in ABI dumps.

FILTER SYMBOLS OPTIONS:
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

  -skip-internal-symbols PATTERN
      Do not check symbols matched by the pattern.

  -skip-internal-types PATTERN
      Do not check types matched by the pattern.

  -keep-cxx
      Check _ZS*, _ZNS* and _ZNKS* symbols.

FILTER HEADERS OPTIONS:
  -skip-headers PATH
      The file with the list of header files, that should not be checked.

  -headers-list PATH
      The file with a list of headers, that should be checked/dumped.

  -header NAME
      Check/Dump ABI of this header only.

  -nostdinc
      Do not search in GCC standard system directories for header files.

      -tolerance LEVEL
      Apply a set of heuristics to successfully compile input
      header files. You can enable several tolerance levels by
      joining them into one string (e.g. 13, 124, etc.).
      Levels:
          1 - skip non-Linux headers (e.g. win32_*.h, etc.)
          2 - skip internal headers (e.g. *_p.h, impl/*.h, etc.)
          3 - skip headers that include non-Linux headers
          4 - skip headers included by others

  -tolerant
      Enable highest tolerance level [1234].

  -skip-unidentified
      Skip header files in 'headers' and 'include_preamble' sections
      of the XML descriptor that cannot be found. This is useful if
      you are trying to use the same descriptor for different targets.

FILTER RULES OPTIONS:
  -skip-typedef-uncover
      Do not report a problem if type is covered or
      uncovered by typedef (useful for broken debug info).

  -check-private-abi
      Check data types from the private part of the ABI when
      comparing ABI dumps created by the ABI Dumper tool with
      use of the -public-headers option.

      Requires ABI Dumper >= 0.99.14

  -disable-constants-check
      Do not check for changes in constants.

  -skip-added-constants
      Do not detect added constants.

  -skip-removed-constants
      Do not detect removed constants.

OTHER OPTIONS:
  -lang LANG
      Set library language (C or C++). You can use this option if the tool
      cannot auto-detect a language. This option may be useful for checking
      C-library headers (--lang=C) in --headers-only or --extended modes.

  -arch ARCH
      Set library architecture (x86, x86_64, ia64, arm, ppc32, ppc64, s390,
      ect.). The option is useful if the tool cannot detect correct architecture
      of the input objects.

  -mingw-compatible
      If input header files are compatible with the MinGW GCC compiler,
      then you can tell the tool about this and speedup the analysis.

  -cxx-incompatible
      Set this option if input C header files use C++ keywords. The tool
      will try to replace such keywords at preprocessor stage and replace
      them back in the final TU dump.

  -cpp-compatible
      Do nothing.

  -quick
      Quick analysis. Disable check of some template instances.

  -force
      Try to enable this option if the tool checked not all
      types and symbols in header files.

OS ANALYSIS OPTIONS:
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

  -cmp-systems -d1 sys_dumps/NAME1/ARCH -d2 sys_dumps/NAME2/ARCH
      Compare two ABI dumps of a system. Create compatibility reports for
      each system library and the common HTML report including the summary
      of test results for all checked libraries.
      
      Summary report will be generated to:
          sys_compat_reports/NAME1_to_NAME2/ARCH

  -sysroot DIR
      Specify the alternative root directory. The tool will search for include
      paths in the DIR/usr/include and DIR/usr/lib directories.

  -sysinfo DIR
      This option should be used with -dump-system option to dump
      ABI of operating systems and configure the dumping process.

  -libs-list PATH
      The file with a list of libraries, that should be dumped by
      the -dump-system option or should be checked by the -cmp-systems option.

LOGGING OPTIONS:
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

  -q|-quiet
      Print all messages to the file instead of stdout and stderr.
      Default path (can be changed by -log-path option):
          ".$In::Opt{"DefaultLog"}."

REPORT PATH:
    Compatibility report will be generated to:
        compat_reports/LIB_NAME/V1_to_V2/compat_report.html

LOG PATH:
    Log will be generated to:
        logs/LIB_NAME/V1/log.txt
        logs/LIB_NAME/V2/log.txt

EXIT CODES:
    0 - Compatible. The tool has run without any errors.
    non-zero - Incompatible or the tool has run with errors.

MORE INFO:
    ".$HomePage{"Doc"}."
    ".$HomePage{"Dev"}."\n\n");
}

# Aliases
my (%SymbolInfo, %TypeInfo, %TName_Tid, %Constants) = ();

# Global
my %Cache;
my $TOP_REF = "<a class='top_ref' href='#Top'>to the top</a>";
my %RESULT;

# Counter
my %CheckedTypes;
my %CheckedSymbols;

# Classes
my %VirtualTable;
my %VirtualTable_Model;
my %VTableClass;
my %AllocableClass;
my %ClassMethods;
my %ClassNames;
my %OverriddenMethods;

# Symbols
my %Func_ShortName;
my %AddSymbolParams;
my %GlobalDataObject;

# Merging
my %CompSign;
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

# Recursion locks
my @RecurTypes;
my @RecurTypes_Diff;
my @RecurConstant;

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

my %Severity_Val=(
    "High"=>3,
    "Medium"=>2,
    "Low"=>1,
    "Safe"=>-1
);

sub getModules()
{
    my $TOOL_DIR = dirname($0);
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
        if($DIR!~/\A(\/|\w+:[\/\\])/)
        { # relative path
            $DIR = abs_path($TOOL_DIR)."/".$DIR;
        }
        if(-d $DIR."/modules") {
            return $DIR."/modules";
        }
    }
    exitStatus("Module_Error", "can't find modules");
}

sub loadModule($)
{
    my $Name = $_[0];
    if(defined $LoadedModules{$Name}) {
        return;
    }
    my $Path = $MODULES_DIR."/Internals/$Name.pm";
    if(not -f $Path)
    {
        print STDERR "can't access \'$Path\'\n";
        exit(2);
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

sub selectSymbolNs($$)
{
    my ($Symbol, $LVer) = @_;
    
    my $NS = $CompSign{$LVer}{$Symbol}{"NameSpace"};
    if(not $NS)
    {
        if(my $Class = $CompSign{$LVer}{$Symbol}{"Class"}) {
            $NS = $TypeInfo{$LVer}{$Class}{"NameSpace"};
        }
    }
    if($NS)
    {
        if(defined $In::ABI{$LVer}{"NameSpaces"}{$NS}) {
            return $NS;
        }
        else
        {
            while($NS=~s/::[^:]+\Z//)
            {
                if(defined $In::ABI{$LVer}{"NameSpaces"}{$NS}) {
                    return $NS;
                }
            }
        }
    }
    
    return "";
}

sub selectTypeNs($$)
{
    my ($TypeName, $LVer) = @_;
    
    my $Tid = $TName_Tid{$LVer}{$TypeName};
    
    if(my $NS = $TypeInfo{$LVer}{$Tid}{"NameSpace"})
    {
        if(defined $In::ABI{$LVer}{"NameSpaces"}{$NS}) {
            return $NS;
        }
        else
        {
            while($NS=~s/::[^:]+\Z//)
            {
                if(defined $In::ABI{$LVer}{"NameSpaces"}{$NS}) {
                    return $NS;
                }
            }
        }
    }
    return "";
}

sub getChargeLevel($$)
{
    my ($Symbol, $LVer) = @_;
    
    if(defined $CompSign{$LVer}{$Symbol}
    and $CompSign{$LVer}{$Symbol}{"ShortName"})
    {
        if($CompSign{$LVer}{$Symbol}{"Constructor"})
        {
            if($Symbol=~/C([1-4])[EI]/)
            { # [in-charge]
              # [not-in-charge]
                return "[C".$1."]";
            }
        }
        elsif($CompSign{$LVer}{$Symbol}{"Destructor"})
        {
            if($Symbol=~/D([0-4])[EI]/)
            { # [in-charge]
              # [not-in-charge]
              # [in-charge-deleting]
                return "[D".$1."]";
            }
        }
    }
    
    return undef;
}

sub blackName($)
{
    my $N = $_[0];
    return "<span class='iname_b'>".$N."</span>";
}

sub highLight_ItalicColor($$)
{
    my ($Symbol, $LVer) = @_;
    return getSignature($Symbol, $LVer, "Full|HTML|Italic|Color");
}

sub getSignature($$$)
{
    my ($Symbol, $LVer, $Kind) = @_;
    if($Cache{"getSignature"}{$LVer}{$Symbol}{$Kind}) {
        return $Cache{"getSignature"}{$LVer}{$Symbol}{$Kind};
    }
    
    # settings
    my ($Html, $Simple, $Italic, $Color, $Full, $ShowClass, $ShowName,
    $ShowParams, $ShowQuals, $ShowAttr, $Desc, $Target) = ();
    
    if($Kind=~/HTML/) {
        $Html = 1;
    }
    if($Kind=~/Simple/) {
        $Simple = 1;
    }
    if($Kind=~/Italic/) {
        $Italic = 1;
    }
    if($Kind=~/Color/) {
        $Color = 1;
    }
    
    if($Kind=~/Full/) {
        $Full = 1;
    }
    if($Kind=~/Class/) {
        $ShowClass = 1;
    }
    if($Kind=~/Name/) {
        $ShowName = 1;
    }
    if($Kind=~/Param/) {
        $ShowParams = 1;
    }
    if($Kind=~/Qual/) {
        $ShowQuals = 1;
    }
    if($Kind=~/Attr/) {
        $ShowAttr = 1;
    }
    if($Kind=~/Desc/) {
        $Desc = 1;
    }
    
    if($Kind=~/Target=(\d+)/) {
        $Target = $1;
    }
    
    if($Full)
    {
        $ShowName = 1;
        $ShowClass = 1;
    }
    
    my ($MnglName, $VSpec, $SVer) = symbolParts($Symbol);
    
    if(index($Symbol, "_ZTV")==0)
    {
        if(my $ClassId = $CompSign{$LVer}{$Symbol}{"Class"})
        {
            my $ClassName = $TypeInfo{$LVer}{$ClassId}{"Name"};
            $ClassName=~s/\bstruct //g;
            
            if($Html) {
                return "vtable for ".specChars($ClassName)." <span class='attr'>[data]</span>";
            }
            
            return "vtable for $ClassName [data]";
        }
        else
        { # failure
            return undef;
        }
    }
    
    my $Mngl = (index($Symbol, "_Z")==0 or index($Symbol, "?")==0);
    
    my $Signature = "";
    if($ShowName)
    {
        my $ShortName = $CompSign{$LVer}{$Symbol}{"ShortName"};
        
        if($Html) {
            $ShortName = specChars($ShortName);
        }
        
        $Signature .= $ShortName;
        
        if($Mngl)
        {
            if($CompSign{$LVer}{$Symbol}{"Destructor"}) {
                $Signature = "~".$Signature;
            }
            
            if($ShowClass)
            {
                if(my $ClassId = $CompSign{$LVer}{$Symbol}{"Class"})
                {
                    my $Class = $TypeInfo{$LVer}{$ClassId}{"Name"};
                    $Class=~s/\bstruct //g;
                    
                    if($Html) {
                        $Class = specChars($Class);
                    }
                    
                    $Signature = $Class."::".$Signature;
                }
                elsif(my $NameSpace = $CompSign{$LVer}{$Symbol}{"NameSpace"}) {
                    $Signature = $NameSpace."::".$Signature;
                }
            }
        }
    }
    
    my @Params = ();
    if(defined $CompSign{$LVer}{$Symbol}{"Param"})
    {
        foreach my $PPos (sort {$a<=>$b} keys(%{$CompSign{$LVer}{$Symbol}{"Param"}}))
        {
            my $PTid = $CompSign{$LVer}{$Symbol}{"Param"}{$PPos}{"type"};
            if(not $PTid) {
                next;
            }
            
            if(my $PTName = $TypeInfo{$LVer}{$PTid}{"Name"})
            {
                foreach my $Typedef (keys(%ChangedTypedef))
                {
                    if(index($PTName, $Typedef)!=-1)
                    {
                        if(my $Base = $In::ABI{$LVer}{"TypedefBase"}{$Typedef}) {
                            $PTName=~s/\b\Q$Typedef\E\b/$Base/g;
                        }
                    }
                }
                
                if($Html) {
                    $PTName = specChars($PTName);
                }
                
                my $PName = $CompSign{$LVer}{$Symbol}{"Param"}{$PPos}{"name"};
                if($Mngl and ($PName eq "this" or $PName eq "__in_chrg" or $PName eq "__vtt_parm"))
                { # do NOT show first hidded "this"-parameter
                    next;
                }
                
                if($PName and ($Full or $ShowParams))
                {
                    if($Simple) {
                        $PName = "<i>$PName</i>";
                    }
                    elsif($Html)
                    {
                        if(defined $Target
                        and $Target==adjustParamPos($PPos, $Symbol, $LVer)) {
                            $PName = "<span class='fp'>$PName</span>";
                        }
                        elsif($Color) {
                            $PName = "<span class='color_p'>$PName</span>";
                        }
                        elsif($Italic) {
                            $PName = "<i>$PName</i>";
                        }
                    }
                    
                    push(@Params, createMemDecl($PTName, $PName));
                }
                else {
                    push(@Params, $PTName);
                }
            }
        }
    }
    
    if($Simple) {
        $Signature = "<b>".$Signature."</b>";
    }
    
    if($CompSign{$LVer}{$Symbol}{"Data"})
    {
        $Signature .= " [data]";
    }
    else
    {
        if($Full or $ShowAttr)
        {
            if($Mngl)
            {
                if(my $ChargeLevel = getChargeLevel($Symbol, $LVer)) {
                    $Signature .= " ".$ChargeLevel;
                }
            }
        }
        
        if($Html and not $Simple)
        {
            $Signature .= "&#160;";
            
            if($Desc) {
                $Signature .= "<span class='sym_pd'>";
            }
            else {
                $Signature .= "<span class='sym_p'>";
            }
            if(@Params)
            {
                foreach my $Pos (0 .. $#Params)
                {
                    my $Name = "";
                    
                    if($Pos==0) {
                        $Name .= "(&#160;";
                    }
                    
                    $Name .= $Params[$Pos];
                    
                    $Name = "<span>".$Name."</span>";
                    
                    if($Pos==$#Params) {
                        $Name .= "&#160;)";
                    }
                    else {
                        $Name .= ", ";
                    }
                    
                    $Signature .= $Name;
                }
            }
            else {
                $Signature .= "(&#160;)";
            }
            $Signature .= "</span>";
        }
        else
        {
            if(@Params) {
                $Signature .= " ( ".join(", ", @Params)." )";
            }
            else {
                $Signature .= " ( )";
            }
        }
        
        
        if($Full or $ShowQuals)
        {
            if($CompSign{$LVer}{$Symbol}{"Const"}
            or $Symbol=~/\A_ZN(V|)K/) {
                $Signature .= " const";
            }
            
            if($CompSign{$LVer}{$Symbol}{"Volatile"}
            or $Symbol=~/\A_ZN(K|)V/) {
                $Signature .= " volatile";
            }
        }
        
        if($Full or $ShowAttr)
        {
            if($CompSign{$LVer}{$Symbol}{"Static"}
            and $Mngl) {
                $Signature .= " [static]";
            }
        }
    }
    
    if($Full)
    {
        if(defined $In::Opt{"ShowRetVal"})
        {
            if(my $ReturnId = $CompSign{$LVer}{$Symbol}{"Return"})
            {
                my $RName = $TypeInfo{$LVer}{$ReturnId}{"Name"};
                if($Simple) {
                    $Signature .= " <b>:</b> ".specChars($RName);
                }
                elsif($Html) {
                    $Signature .= "<span class='sym_p nowrap'> &#160;<b>:</b>&#160;&#160;".specChars($RName)."</span>";
                }
                else {
                    $Signature .= " : ".$RName;
                }
            }
        }
        
        if($SVer)
        {
            if($Html) {
                $Signature .= "<span class='sym_ver'>&#160;$VSpec&#160;$SVer</span>";
            }
            else {
                $Signature .= $VSpec.$SVer;
            }
        }
    }
    
    if($Html) {
        $Signature=~s!(\[C\d\]|\[D\d\]|\[static\]|\[data\])!<span class='attr'>$1</span>!g;
    }
    
    if($Simple) {
        $Signature=~s/\[\]/\[ \]/g;
    }
    elsif($Html)
    {
        $Signature=~s!\[\]![&#160;]!g;
        $Signature=~s!operator=!operator&#160;=!g;
    }
    
    return ($Cache{"getSignature"}{$LVer}{$Symbol}{$Kind} = $Signature);
}

sub createMemDecl($$)
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

sub prepareSymbols($)
{
    my $LVer = $_[0];
    
    if(not keys(%{$SymbolInfo{$LVer}}))
    { # check if input is valid
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
    
    foreach my $InfoId (sort {$b<=>$a} keys(%{$SymbolInfo{$LVer}}))
    {
        my $MnglName = $SymbolInfo{$LVer}{$InfoId}{"MnglName"};
        my $ShortName = $SymbolInfo{$LVer}{$InfoId}{"ShortName"};
        
        if(not $MnglName)
        {
            $SymbolInfo{$LVer}{$InfoId}{"MnglName"} = $ShortName;
            $MnglName = $ShortName;
        }
        
        if(defined $CompSign{$LVer}{$MnglName})
        { # NOTE: duplicated entries in the ABI Dump
            if(defined $SymbolInfo{$LVer}{$InfoId}{"Param"})
            {
                if($SymbolInfo{$LVer}{$InfoId}{"Param"}{0}{"name"} eq "p1") {
                    next;
                }
            }
        }
        
        if(not $CompSign{$LVer}{$MnglName}{"MnglName"})
        { # NOTE: global data may enter here twice
            $CompSign{$LVer}{$MnglName} = $SymbolInfo{$LVer}{$InfoId};
        }
        
        if(not defined $SymbolInfo{$LVer}{$InfoId}{"Unmangled"})
        {
            if($MnglName eq $ShortName) {
                $SymbolInfo{$LVer}{$InfoId}{"Unmangled"} = $ShortName;
            }
            else {
                $SymbolInfo{$LVer}{$InfoId}{"Unmangled"} = getSignature($MnglName, $LVer, "Class|Name|Qual");
            }
        }
        
        # symbol and its symlink have same signatures
        if(my $SVer = $In::ABI{$LVer}{"SymbolVersion"}{$MnglName}) {
            $CompSign{$LVer}{$SVer} = $SymbolInfo{$LVer}{$InfoId};
        }
        
        if(my $Alias = $CompSign{$LVer}{$MnglName}{"Alias"})
        {
            $CompSign{$LVer}{$Alias} = $SymbolInfo{$LVer}{$InfoId};
            
            if(my $SAVer = $In::ABI{$LVer}{"SymbolVersion"}{$Alias}) {
                $CompSign{$LVer}{$SAVer} = $SymbolInfo{$LVer}{$InfoId};
            }
        }
    }
    
    if($In::ABI{$LVer}{"Language"} eq "C++"
    and getCmdPath("c++filt"))
    {
        my @VTables = ();
        foreach my $S (keys(%{$In::ABI{$LVer}{"SymLib"}}))
        {
            if(index($S, "_ZTV")==0) {
                push(@VTables, $S);
            }
        }
        translateSymbols(@VTables, $LVer);
    }
    
    if($In::Opt{"ExtendedCheck"}) {
        addExtension($LVer);
    }
    
    foreach my $Symbol (keys(%{$CompSign{$LVer}}))
    { # detect allocable classes with public exported constructors
      # or classes with auto-generated or inline-only constructors
      # and other temp info
        if(my $ClassId = $CompSign{$LVer}{$Symbol}{"Class"})
        {
            my $ClassName = $TypeInfo{$LVer}{$ClassId}{"Name"};
            if($CompSign{$LVer}{$Symbol}{"Constructor"}
            and not $CompSign{$LVer}{$Symbol}{"InLine"})
            { # Class() { ... } will not be exported
                if(not $CompSign{$LVer}{$Symbol}{"Private"})
                {
                    if($In::Opt{"CheckHeadersOnly"} or linkSymbol($Symbol, $LVer, "-Deps")) {
                        $AllocableClass{$LVer}{$ClassName} = 1;
                    }
                }
            }
            if(not $CompSign{$LVer}{$Symbol}{"Private"})
            { # all imported class methods
                if(symbolFilter($Symbol, $CompSign{$LVer}{$Symbol}, "Affected", "Binary", $LVer))
                {
                    if($In::Opt{"CheckHeadersOnly"})
                    {
                        if(not $CompSign{$LVer}{$Symbol}{"InLine"}
                        or $CompSign{$LVer}{$Symbol}{"Virt"})
                        { # all symbols except non-virtual inline
                            $ClassMethods{"Binary"}{$LVer}{$ClassName}{$Symbol} = 1;
                        }
                    }
                    else {
                        $ClassMethods{"Binary"}{$LVer}{$ClassName}{$Symbol} = 1;
                    }
                }
                if(symbolFilter($Symbol, $CompSign{$LVer}{$Symbol}, "Affected", "Source", $LVer)) {
                    $ClassMethods{"Source"}{$LVer}{$ClassName}{$Symbol} = 1;
                }
            }
            $ClassNames{$LVer}{$ClassName} = 1;
        }
        if(my $RetId = $CompSign{$LVer}{$Symbol}{"Return"})
        {
            my %Base = getBaseType($RetId, $LVer);
            if(defined $Base{"Type"}
            and $Base{"Type"}=~/Struct|Class/)
            {
                my $Name = $TypeInfo{$LVer}{$Base{"Tid"}}{"Name"};
                if($Name=~/<([^<>\s]+)>/)
                {
                    if(my $Tid = getTypeIdByName($1, $LVer)) {
                        $ReturnedClass{$LVer}{$Tid} = 1;
                    }
                }
                else {
                    $ReturnedClass{$LVer}{$Base{"Tid"}} = 1;
                }
            }
        }
        foreach my $Num (keys(%{$CompSign{$LVer}{$Symbol}{"Param"}}))
        {
            my $PId = $CompSign{$LVer}{$Symbol}{"Param"}{$Num}{"type"};
            if(getPLevel($PId, $LVer)>=1)
            {
                if(my %Base = getBaseType($PId, $LVer))
                {
                    if($Base{"Type"}=~/Struct|Class/)
                    {
                        $ParamClass{$LVer}{$Base{"Tid"}}{$Symbol} = 1;
                        foreach my $SubId (getSubClasses($Base{"Tid"}, $LVer, 1))
                        { # mark all derived classes
                            $ParamClass{$LVer}{$SubId}{$Symbol} = 1;
                        }
                    }
                }
            }
        }
        
        # mapping {short name => symbols}
        $Func_ShortName{$LVer}{$CompSign{$LVer}{$Symbol}{"ShortName"}}{$Symbol} = 1;
    }
    
    foreach my $ClassName (keys(%{$In::ABI{$LVer}{"ClassVTable"}}))
    {
        my $MnglName = $In::ABI{$LVer}{"ClassVTable"}{$ClassName};
        
        if(my $ClassId = $TName_Tid{$LVer}{$ClassName})
        {
            if(my $H = $TypeInfo{$LVer}{$ClassId}{"Header"}) {
                $CompSign{$LVer}{$MnglName}{"Header"} = $H;
            }
            if(my $S = $TypeInfo{$LVer}{$ClassId}{"Source"}) {
                $CompSign{$LVer}{$MnglName}{"Source"} = $S;
            }
            $CompSign{$LVer}{$MnglName}{"Class"} = $ClassId;
            $CompSign{$LVer}{$MnglName}{"Unmangled"} = getSignature($MnglName, $LVer, "Class|Name");
        }
        
        $VTableClass{$LVer}{$MnglName} = $ClassName;
    }
    
    # types
    foreach my $TypeId (keys(%{$TypeInfo{$LVer}}))
    {
        if(my $TName = $TypeInfo{$LVer}{$TypeId}{"Name"})
        {
            if(defined $TypeInfo{$LVer}{$TypeId}{"VTable"}) {
                $ClassNames{$LVer}{$TName} = 1;
            }
            if(defined $TypeInfo{$LVer}{$TypeId}{"Base"})
            {
                $ClassNames{$LVer}{$TName} = 1;
                foreach my $Bid (keys(%{$TypeInfo{$LVer}{$TypeId}{"Base"}}))
                {
                    if(my $BName = $TypeInfo{$LVer}{$Bid}{"Name"}) {
                        $ClassNames{$LVer}{$BName} = 1;
                    }
                }
            }
        }
    }
}

sub addExtension($)
{
    my $LVer = $_[0];
    foreach my $Tid (sort {$a<=>$b} keys(%{$TypeInfo{$LVer}}))
    {
        if(pickType($Tid, $LVer))
        {
            my $TName = $TypeInfo{$LVer}{$Tid}{"Name"};
            $TName=~s/\A(struct|union|class|enum) //;
            my $Symbol = "external_func_".$TName;
            
            %{$CompSign{$LVer}{$Symbol}} = (
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
    my ($VirtFunc, $ClassId, $LVer) = @_;
    foreach my $BaseClass_Id (keys(%{$TypeInfo{$LVer}{$ClassId}{"Base"}}))
    {
        if(my $VirtMethodInClass = findMethod_Class($VirtFunc, $BaseClass_Id, $LVer)) {
            return $VirtMethodInClass;
        }
        elsif(my $VirtMethodInBaseClasses = findMethod($VirtFunc, $BaseClass_Id, $LVer)) {
            return $VirtMethodInBaseClasses;
        }
    }
    return undef;
}

sub findMethod_Class($$$)
{
    my ($VirtFunc, $ClassId, $LVer) = @_;
    
    my $ClassName = $TypeInfo{$LVer}{$ClassId}{"Name"};
    if(not defined $VirtualTable{$LVer}{$ClassName}) {
        return undef;
    }
    my $TargetSuffix = getSignature($VirtFunc, $LVer, "Qual");
    my $TargetShortName = $CompSign{$LVer}{$VirtFunc}{"ShortName"};
    
    foreach my $Candidate (keys(%{$VirtualTable{$LVer}{$ClassName}}))
    { # search for interface with the same parameters suffix (overridden)
        if($TargetSuffix eq getSignature($Candidate, $LVer, "Qual"))
        {
            if($CompSign{$LVer}{$VirtFunc}{"Destructor"})
            {
                if($CompSign{$LVer}{$Candidate}{"Destructor"})
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
                if($TargetShortName eq $CompSign{$LVer}{$Candidate}{"ShortName"}) {
                    return $Candidate;
                }
            }
        }
    }
    return undef;
}

sub registerVTable($)
{
    my $LVer = $_[0];
    foreach my $Symbol (keys(%{$CompSign{$LVer}}))
    {
        if($CompSign{$LVer}{$Symbol}{"Virt"}
        or $CompSign{$LVer}{$Symbol}{"PureVirt"})
        {
            my $ClassName = $TypeInfo{$LVer}{$CompSign{$LVer}{$Symbol}{"Class"}}{"Name"};
            if(not $In::Opt{"StdcxxTesting"} and $ClassName=~/\A(std::|__cxxabi)/) {
                next;
            }
            if($CompSign{$LVer}{$Symbol}{"Destructor"}
            and $Symbol=~/D2E/)
            { # pure virtual D2-destructors are marked as "virt" in the dump
              # virtual D2-destructors are NOT marked as "virt" in the dump
              # both destructors are not presented in the v-table
                next;
            }
            my ($MnglName, $VersionSpec, $SymbolVersion) = symbolParts($Symbol);
            $VirtualTable{$LVer}{$ClassName}{$MnglName} = 1;
        }
    }
}

sub registerOverriding($)
{
    my $LVer = $_[0];
    my @Classes = keys(%{$VirtualTable{$LVer}});
    @Classes = sort {$TName_Tid{$LVer}{$a}<=>$TName_Tid{$LVer}{$b}} @Classes;
    foreach my $ClassName (@Classes)
    {
        foreach my $VirtFunc (keys(%{$VirtualTable{$LVer}{$ClassName}}))
        {
            if($CompSign{$LVer}{$VirtFunc}{"PureVirt"})
            { # pure virtuals
                next;
            }
            my $ClassId = $TName_Tid{$LVer}{$ClassName};
            if(my $Overridden = findMethod($VirtFunc, $ClassId, $LVer))
            {
                if($CompSign{$LVer}{$Overridden}{"Virt"}
                or $CompSign{$LVer}{$Overridden}{"PureVirt"})
                { # both overridden virtual methods
                  # and implemented pure virtual methods
                    $CompSign{$LVer}{$VirtFunc}{"Override"} = $Overridden;
                    $OverriddenMethods{$LVer}{$Overridden}{$VirtFunc} = 1;
                    
                    # remove from v-table model
                    delete($VirtualTable{$LVer}{$ClassName}{$VirtFunc});
                }
            }
        }
        if(not keys(%{$VirtualTable{$LVer}{$ClassName}})) {
            delete($VirtualTable{$LVer}{$ClassName});
        }
    }
}

sub setVirtFuncPositions($)
{
    my $LVer = $_[0];
    foreach my $ClassName (keys(%{$VirtualTable{$LVer}}))
    {
        my ($Num, $Rel) = (1, 0);
        
        if(my @Funcs = sort keys(%{$VirtualTable{$LVer}{$ClassName}}))
        {
            if($UsedDump{$LVer}{"DWARF"}) {
                @Funcs = sort {$CompSign{$LVer}{$a}{"VirtPos"}<=>$CompSign{$LVer}{$b}{"VirtPos"}} @Funcs;
            }
            else {
                @Funcs = sort {$CompSign{$LVer}{$a}{"Line"}<=>$CompSign{$LVer}{$b}{"Line"}} @Funcs;
            }
            foreach my $VirtFunc (@Funcs)
            {
                if($UsedDump{$LVer}{"DWARF"}) {
                    $VirtualTable{$LVer}{$ClassName}{$VirtFunc} = $CompSign{$LVer}{$VirtFunc}{"VirtPos"};
                }
                else {
                    $VirtualTable{$LVer}{$ClassName}{$VirtFunc} = $Num++;
                }
                
                # set relative positions
                if(defined $VirtualTable{1}{$ClassName} and defined $VirtualTable{1}{$ClassName}{$VirtFunc}
                and defined $VirtualTable{2}{$ClassName} and defined $VirtualTable{2}{$ClassName}{$VirtFunc})
                { # relative position excluding added and removed virtual functions
                    if(not $CompSign{1}{$VirtFunc}{"Override"}
                    and not $CompSign{2}{$VirtFunc}{"Override"}) {
                        $CompSign{$LVer}{$VirtFunc}{"RelPos"} = $Rel++;
                    }
                }
            }
        }
    }
    foreach my $ClassName (keys(%{$ClassNames{$LVer}}))
    {
        my $AbsNum = 1;
        foreach my $VirtFunc (getVTable_Model($ClassName, $LVer)) {
            $VirtualTable_Model{$LVer}{$ClassName}{$VirtFunc} = $AbsNum++;
        }
    }
}

sub getVTable_Model($$)
{ # return an ordered list of v-table elements
    my ($ClassName, $LVer) = @_;
    
    my $ClassId = $TName_Tid{$LVer}{$ClassName};
    my @Bases = getBaseClasses($ClassId, $LVer, 1);
    my @Elements = ();
    foreach my $BaseId (@Bases, $ClassId)
    {
        if(my $BName = $TypeInfo{$LVer}{$BaseId}{"Name"})
        {
            if(defined $VirtualTable{$LVer}{$BName})
            {
                my @VFuncs = sort keys(%{$VirtualTable{$LVer}{$BName}});
                if($UsedDump{$LVer}{"DWARF"}) {
                    @VFuncs = sort {$CompSign{$LVer}{$a}{"VirtPos"} <=> $CompSign{$LVer}{$b}{"VirtPos"}} @VFuncs;
                }
                else {
                    @VFuncs = sort {$CompSign{$LVer}{$a}{"Line"} <=> $CompSign{$LVer}{$b}{"Line"}} @VFuncs;
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
    my ($ClassId, $LVer) = @_;
    my @Bases = getBaseClasses($ClassId, $LVer, 1);
    my $VShift = 0;
    foreach my $BaseId (@Bases)
    {
        if(my $BName = $TypeInfo{$LVer}{$BaseId}{"Name"})
        {
            if(defined $VirtualTable{$LVer}{$BName}) {
                $VShift+=keys(%{$VirtualTable{$LVer}{$BName}});
            }
        }
    }
    return $VShift;
}

sub getShift($$)
{
    my ($ClassId, $LVer) = @_;
    my @Bases = getBaseClasses($ClassId, $LVer, 0);
    my $Shift = 0;
    foreach my $BaseId (@Bases)
    {
        if(my $Size = $TypeInfo{$LVer}{$BaseId}{"Size"})
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
    my ($ClassName, $LVer) = @_;
    my $Size = 0;
    # three approaches
    if(not $Size)
    { # real size
        if(my %VTable = getVTable_Real($ClassName, $LVer)) {
            $Size = keys(%VTable);
        }
    }
    if(not $Size)
    { # shared library symbol size
        if(my $VTSym = $In::ABI{$LVer}{"ClassVTable"}{$ClassName})
        {
            if($Size = getSymbolSize($VTSym, $LVer)) {
                $Size /= $In::ABI{$LVer}{"WordSize"};
            }
        }
    }
    if(not $Size)
    { # model size
        if(defined $VirtualTable_Model{$LVer}{$ClassName}) {
            $Size = keys(%{$VirtualTable_Model{$LVer}{$ClassName}}) + 2;
        }
    }
    return $Size;
}

sub isLeafClass($$)
{
    my ($ClassId, $LVer) = @_;
    if(not defined $In::ABI{$LVer}{"Class_SubClasses"}{$ClassId}
    or not keys(%{$In::ABI{$LVer}{"Class_SubClasses"}{$ClassId}})) {
        return 1;
    }
    
    return 0;
}

sub havePubFields($)
{ # check structured type for public fields
    return isAccessible($_[0], {}, 0, -1);
}

sub isAccessible($$$$)
{ # check interval in structured type for public fields
    my ($TypePtr, $Skip, $Start, $End) = @_;
    if(not $TypePtr) {
        return 0;
    }
    if($End==-1) {
        $End = keys(%{$TypePtr->{"Memb"}})-1;
    }
    foreach my $MemPos (sort {$a<=>$b} keys(%{$TypePtr->{"Memb"}}))
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
    if($MName=~/priv|abidata|parent_object|impl/i)
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
    my ($ClassName, $LVer) = @_;
    if(my $ClassId = $TName_Tid{$LVer}{$ClassName})
    {
        my %Type = getType($ClassId, $LVer);
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
    foreach my $Offset (sort {$a<=>$b} keys(%Indexes))
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
            if($In::ABI{1}{"GccVersion"} ne $In::ABI{2}{"GccVersion"})
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
    foreach my $ClassName (sort keys(%{$ClassNames{1}}))
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
                    if(defined $CompSign{1}{$Symbol})
                    {
                        if($CompSign{1}{$Symbol}{"Virt"})
                        { # override some method in v.1
                            next;
                        }
                    }
                    else
                    {
                        if(linkSymbol($Symbol, 1, "+Deps")) {
                            next;
                        }
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
                    if(defined $CompSign{2}{$Symbol})
                    {
                        if($CompSign{2}{$Symbol}{"Virt"})
                        { # override some method in v.2
                            next;
                        }
                    }
                    else
                    {
                        if(linkSymbol($Symbol, 2, "+Deps")) {
                            next;
                        }
                    }
                    
                    $RemovedInt_Virt{$Level}{$ClassName}{$Symbol} = 1;
                }
            }
        }
        
        if($Level eq "Binary")
        { # Binary-level
            my %Class_Type = getType($ClassId, 1);
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
                    my @Affected = ();
                    
                    if($CompSign{1}{$RemovedVFunc}{"PureVirt"})
                    { # pure methods
                        if(not isUsedClass($ClassId, 1, $Level))
                        { # not a parameter of some exported method
                            next;
                        }
                        $ProblemType = "Pure_Virtual_Replacement";
                        
                        # affected all methods (both virtual and non-virtual ones)
                        @Affected = (keys(%{$ClassMethods{$Level}{1}{$ClassName}}));
                    }
                    else {
                        @Affected = ($RemovedVFunc);
                    }
                    
                    push(@Affected, keys(%{$OverriddenMethods{1}{$RemovedVFunc}}));
                    
                    $VTableChanged_M{$ClassName} = 1;
                    
                    foreach my $AffectedInt (@Affected)
                    {
                        if($CompSign{1}{$AffectedInt}{"PureVirt"})
                        { # affected exported methods only
                            next;
                        }
                        if(not symbolFilter($AffectedInt, $CompSign{1}{$AffectedInt}, "Affected", $Level, 1)) {
                            next;
                        }
                        %{$CompatProblems{$Level}{$AffectedInt}{$ProblemType}{$AddedVFunc}}=(
                            "Type_Name"=>$Class_Type{"Name"},
                            "Target"=>$AddedVFunc,
                            "Old_Value"=>$RemovedVFunc);
                    }
                }
            }
        }
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
        
        my %Class_Old = getType($ClassId_Old, 1);
        my $ClassId_New = $TName_Tid{2}{$ClassName};
        if(not $ClassId_New) {
            next;
        }
        my %Class_New = getType($ClassId_New, 2);
        if($Class_New{"Type"}!~/Class|Struct/)
        { # became typedef
            if($Level eq "Binary") {
                next;
            }
            if($Level eq "Source")
            {
                %Class_New = getPureType($ClassId_New, 2);
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
        
        if($Level eq "Binary" and cmpVTables_Real($ClassName, 1)!=0)
        {
            foreach my $Symbol (sort keys(%{$RemovedInt_Virt{$Level}{$ClassName}}))
            {
                if($VirtualReplacement{$Symbol}) {
                    next;
                }
                
                if(symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected", $Level, 1))
                {
                    my $ProblemType = "Removed_Virtual_Method";
                    if($CompSign{1}{$Symbol}{"PureVirt"}) {
                        $ProblemType = "Removed_Pure_Virtual_Method";
                    }
                    
                    %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{getSignature($Symbol, 1, "Class|Name|Qual")}}=(
                        "Type_Name"=>$ClassName,
                        "Target"=>$Symbol);
                }
                
                $VTableChanged_M{$ClassName} = 1;
                foreach my $SubId (getSubClasses($ClassId_Old, 1, 1))
                {
                    if(my $SubName = $TypeInfo{1}{$SubId}{"Name"}) {
                        $VTableChanged_M{$SubName} = 1;
                    }
                }
            }
        }
        
        if(index($ClassName, ">")!=-1)
        { # skip affected template instances
            next;
        }
        
        my @Bases_Old = sort {$Class_Old{"Base"}{$a}{"pos"}<=>$Class_Old{"Base"}{$b}{"pos"}} keys(%{$Class_Old{"Base"}});
        my @Bases_New = sort {$Class_New{"Base"}{$a}{"pos"}<=>$Class_New{"Base"}{$b}{"pos"}} keys(%{$Class_New{"Base"}});
        
        my %Tr_Old = map {$TypeInfo{1}{$_}{"Name"} => uncoverTypedefs($TypeInfo{1}{$_}{"Name"}, 1)} @Bases_Old;
        my %Tr_New = map {$TypeInfo{2}{$_}{"Name"} => uncoverTypedefs($TypeInfo{2}{$_}{"Name"}, 2)} @Bases_New;
        
        my ($BNum1, $BNum2) = (1, 1);
        my %BasePos_Old = map {$Tr_Old{$TypeInfo{1}{$_}{"Name"}} => $BNum1++} @Bases_Old;
        my %BasePos_New = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $BNum2++} @Bases_New;
        my %ShortBase_Old = map {getShortClass($_, 1) => 1} @Bases_Old;
        my %ShortBase_New = map {getShortClass($_, 2) => 1} @Bases_New;
        my $Shift_Old = getShift($ClassId_Old, 1);
        my $Shift_New = getShift($ClassId_New, 2);
        my %BaseId_New = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $_} @Bases_New;
        my @StableBases_Old = ();
        foreach my $BaseId (@Bases_Old)
        {
            my $BaseName = $TypeInfo{1}{$BaseId}{"Name"};
            if($BasePos_New{$Tr_Old{$BaseName}}) {
                push(@StableBases_Old, $BaseId);
            }
            elsif(not $ShortBase_New{$Tr_Old{$BaseName}}
            and not $ShortBase_New{getShortClass($BaseId, 1)})
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
                        $VTableChanged_M{$ClassName} = 1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (getSubClasses($ClassId_Old, 1, 1))
                {
                    if(my $SubName = $TypeInfo{1}{$SubId}{"Name"})
                    {
                        push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                        if($ProblemKind=~/VTable/) {
                            $VTableChanged_M{$SubName} = 1;
                        }
                    }
                }
                foreach my $Interface (@Affected)
                {
                    if(symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1))
                    {
                        %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                            "Type_Name"=>$ClassName,
                            "Target"=>$BaseName,
                            "Old_Size"=>$Class_Old{"Size"}*$BYTE,
                            "New_Size"=>$Class_New{"Size"}*$BYTE,
                            "Shift"=>abs($Shift_New-$Shift_Old));
                    }
                }
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
            and not $ShortBase_Old{getShortClass($BaseId, 2)})
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
                        $VTableChanged_M{$ClassName} = 1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (getSubClasses($ClassId_Old, 1, 1))
                {
                    if(my $SubName = $TypeInfo{1}{$SubId}{"Name"})
                    {
                        push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                        if($ProblemKind=~/VTable/) {
                            $VTableChanged_M{$SubName} = 1;
                        }
                    }
                }
                foreach my $Interface (@Affected)
                {
                    if(symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1))
                    {
                        %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                            "Type_Name"=>$ClassName,
                            "Target"=>$BaseName,
                            "Old_Size"=>$Class_Old{"Size"}*$BYTE,
                            "New_Size"=>$Class_New{"Size"}*$BYTE,
                            "Shift"=>abs($Shift_New-$Shift_Old));
                    }
                }
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
                            if(symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1))
                            {
                                %{$CompatProblems{$Level}{$Interface}{"Base_Class_Position"}{"this"}}=(
                                    "Type_Name"=>$ClassName,
                                    "Target"=>$BaseName,
                                    "Old_Value"=>$OldPos-1,
                                    "New_Value"=>$NewPos-1);
                            }
                        }
                    }
                    if($Class_Old{"Base"}{$BaseId}{"virtual"}
                    and not $Class_New{"Base"}{$BaseNewId}{"virtual"})
                    { # became non-virtual base
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            if(symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1))
                            {
                                %{$CompatProblems{$Level}{$Interface}{"Base_Class_Became_Non_Virtually_Inherited"}{"this->".$BaseName}}=(
                                    "Type_Name"=>$ClassName,
                                    "Target"=>$BaseName  );
                            }
                        }
                    }
                    elsif(not $Class_Old{"Base"}{$BaseId}{"virtual"}
                    and $Class_New{"Base"}{$BaseNewId}{"virtual"})
                    { # became virtual base
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            if(not symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1)) {
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
                    my %BaseType = getType($BaseId, 1);
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
                            if(not symbolFilter($Interface, $CompSign{1}{$Interface}, "Affected", $Level, 1)) {
                                next;
                            }
                            %{$CompatProblems{$Level}{$Interface}{$ProblemType}{"this->".$BaseType{"Name"}}}=(
                                "Type_Name"=>$BaseType{"Name"},
                                "Target"=>$BaseType{"Name"},
                                "Old_Size"=>$Size_Old*$BYTE,
                                "New_Size"=>$Size_New*$BYTE  );
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
                    my @AllBases_Old = getBaseClasses($ClassId_Old, 1, 1);
                    my @AllBases_New = getBaseClasses($ClassId_New, 2, 1);
                    ($BNum1, $BNum2) = (1, 1);
                    my %StableBase = map {$Tr_New{$TypeInfo{2}{$_}{"Name"}} => $_} @AllBases_New;
                    foreach my $BaseId (@AllBases_Old)
                    {
                        my %BaseType = getType($BaseId, 1);
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
                                
                                if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected", $Level, 1)) {
                                    next;
                                }
                                
                                $VTableChanged_M{$BaseType{"Name"}} = 1;
                                $VTableChanged_M{$ClassName} = 1;
                                
                                foreach my $VirtFunc (keys(%{$AddedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: added virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Added_Virtual_Method";
                                    if($CompSign{2}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Added_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{getSignature($VirtFunc, 2, "Class|Name|Qual")}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Target"=>$VirtFunc  );
                                }
                                
                                foreach my $VirtFunc (keys(%{$RemovedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: removed virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Removed_Virtual_Method";
                                    if($CompSign{1}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Removed_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{getSignature($VirtFunc, 1, "Class|Name|Qual")}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Target"=>$VirtFunc  );
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
    my ($ClassId, $LVer) = @_;
    if($AllocableClass{$LVer}{$TypeInfo{$LVer}{$ClassId}{"Name"}}
    or isCopyingClass($ClassId, $LVer)) {
        return 1;
    }
    if(keys(%{$In::ABI{$LVer}{"Class_SubClasses"}{$ClassId}}))
    { # Fix for incomplete data: if this class has
      # a base class then it should also has a constructor 
        return 1;
    }
    if($ReturnedClass{$LVer}{$ClassId})
    { # returned by some method of this class
      # or any other class
        return 1;
    }
    return 0;
}

sub isUsedClass($$$)
{
    my ($ClassId, $LVer, $Level) = @_;
    if(keys(%{$ParamClass{$LVer}{$ClassId}}))
    { # parameter of some exported method
        return 1;
    }
    my $CName = $TypeInfo{$LVer}{$ClassId}{"Name"};
    if(keys(%{$ClassMethods{$Level}{$LVer}{$CName}}))
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
    if($CompSign{1}{$Interface}{"Data"})
    { # global data is not affected
        return;
    }
    my $Class_Id = $CompSign{1}{$Interface}{"Class"};
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
        if($CompSign{1}{$Interface}{"PureVirt"}
        and not isUsedClass($Class_Id, 1, $Level))
        { # pure virtuals should not be affected
          # if there are no exported methods using this class
            return;
        }
    }
    foreach my $Func (keys(%{$VirtualTable{1}{$CName}}))
    {
        if(defined $VirtualTable{2}{$CName}{$Func}
        and defined $CompSign{2}{$Func})
        {
            if(not $CompSign{1}{$Func}{"PureVirt"}
            and $CompSign{2}{$Func}{"PureVirt"})
            { # became pure virtual
                %{$CompatProblems{$Level}{$Interface}{"Virtual_Method_Became_Pure"}{$Func}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$Func  );
                $VTableChanged_M{$CName} = 1;
            }
            elsif($CompSign{1}{$Func}{"PureVirt"}
            and not $CompSign{2}{$Func}{"PureVirt"})
            { # became non-pure virtual
                %{$CompatProblems{$Level}{$Interface}{"Virtual_Method_Became_Non_Pure"}{$Func}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$Func  );
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
            if($CompSign{2}{$AddedVFunc}{"PureVirt"})
            { # pure virtual methods affect all others (virtual and non-virtual)
                %{$CompatProblems{$Level}{$Interface}{"Added_Pure_Virtual_Method"}{$AddedVFunc}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$AddedVFunc  );
                $VTableChanged_M{$CName} = 1;
            }
            elsif(not defined $VirtualTable{1}{$CName}
            or $VPos_Added>keys(%{$VirtualTable{1}{$CName}}))
            { # added virtual function at the end of v-table
                if(not keys(%{$VirtualTable_Model{1}{$CName}}))
                { # became polymorphous class, added v-table pointer
                    %{$CompatProblems{$Level}{$Interface}{"Added_First_Virtual_Method"}{$AddedVFunc}}=(
                        "Type_Name"=>$CName,
                        "Target"=>$AddedVFunc  );
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
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{getSignature($AddedVFunc, 2, "Class|Name|Qual")}}=(
                            "Type_Name"=>$CName,
                            "Target"=>$AddedVFunc  );
                        $VTableChanged_M{$CName} = 1;
                    }
                    else
                    {
                        my $ProblemType = "Added_Virtual_Method";
                        if(isLeafClass($Class_Id, 1)) {
                            $ProblemType = "Added_Virtual_Method_At_End_Of_Leaf_Allocable_Class";
                        }
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{getSignature($AddedVFunc, 2, "Class|Name|Qual")}}=(
                            "Type_Name"=>$CName,
                            "Target"=>$AddedVFunc  );
                        $VTableChanged_M{$CName} = 1;
                    }
                }
            }
            elsif($CompSign{1}{$Interface}{"Virt"}
            or $CompSign{1}{$Interface}{"PureVirt"})
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
                            if(not $CompSign{1}{$ASymbol}{"PureVirt"})
                            {
                                if(not symbolFilter($ASymbol, $CompSign{1}{$ASymbol}, "Affected", $Level, 1)) {
                                    next;
                                }
                            }
                            %{$CompatProblems{$Level}{$ASymbol}{"Added_Virtual_Method"}{getSignature($AddedVFunc, 2, "Class|Name|Qual")}}=(
                                "Type_Name"=>$CName,
                                "Target"=>$AddedVFunc  );
                            $VTableChanged_M{$TypeInfo{1}{$CompSign{1}{$ASymbol}{"Class"}}{"Name"}} = 1;
                        }
                    }
                }
            }
            else {
                # safe
            }
        }
        
        foreach my $RemovedVFunc (sort keys(%{$RemovedInt_Virt{$Level}{$CName}}))
        {
            next if($VirtualReplacement{$RemovedVFunc});
            if($RemovedVFunc eq $Interface
            and $CompSign{1}{$RemovedVFunc}{"PureVirt"})
            { # This case is for removed virtual methods
              # implemented in both versions of a library
                next;
            }
            
            if(not keys(%{$VirtualTable_Model{2}{$CName}}))
            { # became non-polymorphous class, removed v-table pointer
                %{$CompatProblems{$Level}{$Interface}{"Removed_Last_Virtual_Method"}{getSignature($RemovedVFunc, 1, "Class|Name|Qual")}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$RemovedVFunc);
                $VTableChanged_M{$CName} = 1;
            }
            elsif($CompSign{1}{$Interface}{"Virt"}
            or $CompSign{1}{$Interface}{"PureVirt"})
            {
                if(defined $VirtualTable{1}{$CName}
                and defined $VirtualTable{2}{$CName})
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
                            if(not $CompSign{1}{$ASymbol}{"PureVirt"})
                            {
                                if(not symbolFilter($ASymbol, $CompSign{1}{$ASymbol}, "Affected", $Level, 1)) {
                                    next;
                                }
                            }
                            my $ProblemType = "Removed_Virtual_Method";
                            if($CompSign{1}{$RemovedVFunc}{"PureVirt"}) {
                                $ProblemType = "Removed_Pure_Virtual_Method";
                            }
                            
                            %{$CompatProblems{$Level}{$ASymbol}{$ProblemType}{getSignature($RemovedVFunc, 1, "Class|Name|Qual")}}=(
                                "Type_Name"=>$CName,
                                "Target"=>$RemovedVFunc);
                            $VTableChanged_M{$TypeInfo{1}{$CompSign{1}{$ASymbol}{"Class"}}{"Name"}} = 1;
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
            if($CompSign{2}{$AddedVFunc}{"PureVirt"})
            {
                %{$CompatProblems{$Level}{$Interface}{"Added_Pure_Virtual_Method"}{$AddedVFunc}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$AddedVFunc  );
            }
        }
        foreach my $RemovedVFunc (keys(%{$RemovedInt_Virt{$Level}{$CName}}))
        {
            if($CompSign{1}{$RemovedVFunc}{"PureVirt"})
            {
                %{$CompatProblems{$Level}{$Interface}{"Removed_Pure_Virtual_Method"}{$RemovedVFunc}}=(
                    "Type_Name"=>$CName,
                    "Target"=>$RemovedVFunc  );
            }
        }
    }
}

sub findMemPairByName($$)
{
    my ($Mem, $PairType) = @_;
    $Mem=~s/\A[_]+|[_]+\Z//g;
    foreach my $Pair (sort {$a<=>$b} keys(%{$PairType->{"Memb"}}))
    {
        if(defined $PairType->{"Memb"}{$Pair})
        {
            my $Name = $PairType->{"Memb"}{$Pair}{"name"};
            
            if(index($Name, "_")!=-1) {
                $Name=~s/\A[_]+|[_]+\Z//g;
            }
            
            if($Name eq $Mem) {
                return $Pair;
            }
        }
    }
    return "lost";
}

sub findMemPairByVal($$)
{
    my ($Member_Value, $Pair_Type) = @_;
    foreach my $MemberPair_Pos (sort {$a<=>$b} keys(%{$Pair_Type->{"Memb"}}))
    {
        if(defined $Pair_Type->{"Memb"}{$MemberPair_Pos}
        and $Pair_Type->{"Memb"}{$MemberPair_Pos}{"value"} eq $Member_Value) {
            return $MemberPair_Pos;
        }
    }
    return "lost";
}

sub isRenamed($$$$$)
{
    my ($MemPos, $Type1, $V1, $Type2, $V2) = @_;
    my $Member_Name = $Type1->{"Memb"}{$MemPos}{"name"};
    my $MemberType_Id = $Type1->{"Memb"}{$MemPos}{"type"};
    my %MemberType_Pure = getPureType($MemberType_Id, $V1);
    if(not defined $Type2->{"Memb"}{$MemPos}) {
        return "";
    }
    my $PairType_Id = $Type2->{"Memb"}{$MemPos}{"type"};
    my %PairType_Pure = getPureType($PairType_Id, $V2);
    
    my $Pair_Name = $Type2->{"Memb"}{$MemPos}{"name"};
    my $MemberPair_Pos_Rev = ($Member_Name eq $Pair_Name)?$MemPos:findMemPairByName($Pair_Name, $Type1);
    if($MemberPair_Pos_Rev eq "lost")
    {
        if($MemberType_Pure{"Name"} eq $PairType_Pure{"Name"})
        { # base type match
            return $Pair_Name;
        }
        if($TypeInfo{$V1}{$MemberType_Id}{"Name"} eq $TypeInfo{$V2}{$PairType_Id}{"Name"})
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
    if($Name=~/last|count|max|total|num/i)
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

sub mergeTypes($$$)
{
    my ($Type1_Id, $Type2_Id, $Level) = @_;
    return {} if(not $Type1_Id or not $Type2_Id);
    
    if(defined $Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id})
    { # already merged
        return $Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type2_Id};
    }
    
    my %Type1 = getType($Type1_Id, 1);
    my %Type2 = getType($Type2_Id, 2);
    if(not $Type1{"Name"} or not $Type2{"Name"}) {
        return {};
    }
    
    my %Type1_Pure = getPureType($Type1_Id, 1);
    my %Type2_Pure = getPureType($Type2_Id, 2);
    
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
    
    if($Type1{"Type"}=~/Intrinsic|Class|Struct|Union|Enum|Ptr|Typedef/) {
        $CheckedTypes{$Level}{$Type1{"Name"}} = 1;
    }
    
    if($Type1_Pure{"Type"}=~/Intrinsic|Class|Struct|Union|Enum|Ptr|Typedef/) {
        $CheckedTypes{$Level}{$Type1_Pure{"Name"}} = 1;
    }
    
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
    return {} if($In::Desc{1}{"SkipTypes"}{$Type1_Pure{"Name"}});
    return {} if($In::Desc{1}{"SkipTypes"}{$Type1{"Name"}});
    
    if($Type1_Pure{"Type"}=~/Class|Struct|Union|Enum|Typedef/
    and not isTargetType($Type1_Pure{"Tid"}, 1)) {
        return {};
    }
    
    my %Typedef_1 = goToFirst($Type1{"Tid"}, 1, "Typedef");
    my %Typedef_2 = goToFirst($Type2{"Tid"}, 2, "Typedef");
    
    if(%Typedef_1 and %Typedef_2
    and $Typedef_1{"Type"} eq "Typedef" and $Typedef_2{"Type"} eq "Typedef"
    and $Typedef_1{"Name"} eq $Typedef_2{"Name"})
    {
        my %Base_1 = getOneStepBaseType($Typedef_1{"Tid"}, 1);
        my %Base_2 = getOneStepBaseType($Typedef_2{"Tid"}, 2);
        if($Base_1{"Name"} ne $Base_2{"Name"})
        {
            if($In::ABI{1}{"GccVersion"} ne $In::ABI{2}{"GccVersion"}
            or $In::Opt{"SkipTypedefUncover"})
            { # different GCC versions or different dumps
                $Base_1{"Name"} = uncoverTypedefs($Base_1{"Name"}, 1);
                $Base_2{"Name"} = uncoverTypedefs($Base_2{"Name"}, 2);
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
                    "Old_Size"=>$Type1{"Size"}*$BYTE,
                    "New_Size"=>$Type2{"Size"}*$BYTE  );
            }
            my %Base1_Pure = getPureType($Base_1{"Tid"}, 1);
            my %Base2_Pure = getPureType($Base_2{"Tid"}, 2);
            
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
                "Old_Size"=>$Type1_Pure{"Size"}*$BYTE,
                "New_Size"=>$Type2_Pure{"Size"}*$BYTE);
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
    foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type1_Pure{"Memb"}}))
    { # detect removed and renamed fields
        my $Member_Name = $Type1_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        my $MemberPair_Pos = (defined $Type2_Pure{"Memb"}{$Member_Pos} and $Type2_Pure{"Memb"}{$Member_Pos}{"name"} eq $Member_Name)?$Member_Pos:findMemPairByName($Member_Name, \%Type2_Pure);
        if($MemberPair_Pos eq "lost")
        {
            if($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
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
                $MemberPair_Pos = findMemPairByVal($Member_Value1, \%Type2_Pure);
                if($MemberPair_Pos ne "lost")
                { # renamed
                    my $RenamedTo = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"name"};
                    my $MemberPair_Pos_Rev = findMemPairByName($RenamedTo, \%Type1_Pure);
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
    foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type2_Pure{"Memb"}}))
    { # detect added fields
        my $Member_Name = $Type2_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
        my $MemberPair_Pos = (defined $Type1_Pure{"Memb"}{$Member_Pos} and $Type1_Pure{"Memb"}{$Member_Pos}{"name"} eq $Member_Name)?$Member_Pos:findMemPairByName($Member_Name, \%Type1_Pure);
        if($MemberPair_Pos eq "lost")
        {
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
        foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type1_Pure{"Memb"}}))
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
        foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type2_Pure{"Memb"}}))
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
    foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type1_Pure{"Memb"}}))
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
                and not isMemPadded($Member_Pos, -1, \%Type1_Pure, \%RemovedField, 1))
                {
                    if(my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                    { # affected fields
                        if(getOffset($MNum-1, \%Type1_Pure, 1)!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, 2))
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
                    if($In::Desc{1}{"SkipConstants"}{$Member_Name}) {
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
                my $SizeV1 = $TypeInfo{1}{$MemberType1_Id}{"Size"}*$BYTE;
                if(my $BSize1 = $Type1_Pure{"Memb"}{$Member_Pos}{"bitfield"}) {
                    $SizeV1 = $BSize1;
                }
                my $SizeV2 = $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE;
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
                        if(not isMemPadded($Member_Pos, $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE, \%Type1_Pure, \%RemovedField, 1))
                        { # check an effect
                            if($Type2_Pure{"Type"} ne "Union"
                            and my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                            { # public fields after the current
                                if(getOffset($MNum-1, \%Type1_Pure, 1)!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, 2))
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
                        if(addedQual($Old_Value, $New_Value, "volatile")) {
                            %{$Sub_SubChanges{"Field_Became_Volatile"}} = %{$Sub_SubChanges{$ProblemType}};
                        }
                        elsif(removedQual($Old_Value, $New_Value, "volatile")) {
                            %{$Sub_SubChanges{"Field_Became_Non_Volatile"}} = %{$Sub_SubChanges{$ProblemType}};
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
                        if(not isMemPadded($Member_Pos, $TypeInfo{2}{$MemberType2_Id}{"Size"}*$BYTE, \%Type1_Pure, \%RemovedField, 1))
                        { # check an effect
                            if($Type2_Pure{"Type"} ne "Union"
                            and my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
                            { # public fields after the current
                                if(getOffset($MNum-1, \%Type1_Pure, 1)!=getOffset($RelatedField{$MNum-1}, \%Type2_Pure, 2))
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
                            if(not defined $In::Opt{"AllAffected"})
                            {
                                if(defined $DupProblems{$Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation}}) {
                                    next;
                                }
                            }
                            
                            my $NewLocation = ($Sub_SubLocation)?$Member_Name."->".$Sub_SubLocation:$Member_Name;
                            $SubProblems{$Sub_SubProblemType}{$NewLocation} = $Sub_SubProblems->{$Sub_SubProblemType}{$Sub_SubLocation};
                            
                            if(not defined $In::Opt{"AllAffected"})
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
    foreach my $Member_Pos (sort {$a<=>$b} keys(%{$Type2_Pure{"Memb"}}))
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
                and not isMemPadded($Member_Pos, -1, \%Type2_Pure, \%AddedField, 2))
                {
                    if(my $MNum = isAccessible(\%Type2_Pure, \%AddedField, $Member_Pos, -1))
                    { # public fields after the current
                        if(getOffset($MNum-1, \%Type2_Pure, 2)!=getOffset($RelatedField_Rev{$MNum-1}, \%Type1_Pure, 1))
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
        foreach my $PPos (sort {$a<=>$b} keys(%{$Type1_Pure{"Param"}}))
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
                    if(not defined $In::Opt{"AllAffected"})
                    {
                        if(defined $DupProblems{$FP_SubProblems->{$FP_SubProblemType}{$FP_SubLocation}}) {
                            next;
                        }
                    }
                    
                    my $NewLocation = ($FP_SubLocation)?$PName."->".$FP_SubLocation:$PName;
                    $SubProblems{$FP_SubProblemType}{$NewLocation} = $FP_SubProblems->{$FP_SubProblemType}{$FP_SubLocation};
                    
                    if(not defined $In::Opt{"AllAffected"})
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

sub detectAdded($)
{
    my $Level = $_[0];
    foreach my $Symbol (keys(%{$In::ABI{2}{"SymLib"}}))
    {
        if(linkSymbol($Symbol, 1, "+Deps"))
        { # linker can find a new symbol
          # in the old-version library
          # So, it's not a new symbol
            next;
        }
        if(my $VSym = $In::ABI{2}{"SymbolVersion"}{$Symbol}
        and index($Symbol,"\@")==-1) {
            next;
        }
        $AddedInt{$Level}{$Symbol} = 1;
    }
}

sub detectRemoved($)
{
    my $Level = $_[0];
    foreach my $Symbol (keys(%{$In::ABI{1}{"SymLib"}}))
    {
        if(linkSymbol($Symbol, 2, "+Deps"))
        { # linker can find an old symbol
          # in the new-version library
            next;
        }
        if(my $VSym = $In::ABI{1}{"SymbolVersion"}{$Symbol}
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
        next if(not $CompSign{2}{$Symbol}{"Header"} and not $CompSign{2}{$Symbol}{"Source"});
        next if(not symbolFilter($Symbol, $CompSign{2}{$Symbol}, "Affected + InlineVirt", $Level, 2));
        %{$CompatProblems{$Level}{$Symbol}{"Added_Symbol"}{""}} = ();
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # checking removed symbols
        next if(not $CompSign{1}{$Symbol}{"Header"} and not $CompSign{1}{$Symbol}{"Source"});
        
        if(index($Symbol, "_ZTV")==0)
        { # skip v-tables for templates, that should not be imported by applications
            if(my $CName = $VTableClass{1}{$Symbol})
            {
                if(index($CName, "<")!=-1) {
                    next;
                }
                
                if(not keys(%{$ClassMethods{$Level}{1}{$CName}}))
                { # vtables for "private" classes
                  # use case: vtable for QDragManager (Qt 4.5.3 to 4.6.0) became HIDDEN symbol
                    next;
                }
            }
            
            if($In::Desc{1}{"SkipSymbols"}{$Symbol})
            { # user defined symbols to ignore
                next;
            }
        }
        else {
            next if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected + InlineVirt", $Level, 1));
        }
        
        if($CompSign{1}{$Symbol}{"PureVirt"})
        { # symbols for pure virtual methods cannot be called by clients
            next;
        }
        
        %{$CompatProblems{$Level}{$Symbol}{"Removed_Symbol"}{""}} = ();
    }
}

sub detectAdded_H($)
{
    my $Level = $_[0];
    foreach my $Symbol (sort keys(%{$CompSign{2}}))
    {
        if($Level eq "Source")
        { # remove symbol version
            my ($SN, $SS, $SV) = symbolParts($Symbol);
            $Symbol=$SN;
            
            if($CompSign{2}{$Symbol}{"Artificial"})
            { # skip artificial constructors
                next;
            }
        }
        
        if(not $CompSign{2}{$Symbol}{"Header"}
        and not $CompSign{2}{$Symbol}{"Source"}) {
            next;
        }
        
        if(not $CompSign{2}{$Symbol}{"MnglName"}) {
            next;
        }
        
        if($ExtendedSymbols{$Symbol}) {
            next;
        }
        
        if(not defined $CompSign{1}{$Symbol}
        or not $CompSign{1}{$Symbol}{"MnglName"})
        {
            if($UsedDump{2}{"SrcBin"})
            {
                if($UsedDump{1}{"BinOnly"})
                { # support for different ABI dumps
                    if(not $CompSign{2}{$Symbol}{"Virt"}
                    and not $CompSign{2}{$Symbol}{"PureVirt"})
                    {
                        if($In::Opt{"CheckHeadersOnly"})
                        {
                            if(my $Lang = $CompSign{2}{$Symbol}{"Lang"})
                            {
                                if($Lang eq "C")
                                { # support for old ABI dumps: missed extern "C" functions
                                    next;
                                }
                            }
                        }
                        else
                        {
                            if(not linkSymbol($Symbol, 2, "-Deps"))
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
    foreach my $Symbol (sort keys(%{$CompSign{1}}))
    {
        my $ISymbol = $Symbol;
        
        if($Level eq "Source")
        { # remove symbol version
            my ($SN, $SS, $SV) = symbolParts($Symbol);
            $Symbol = $SN;
        }
        
        if(not $CompSign{1}{$Symbol}{"Header"}
        and not $CompSign{1}{$Symbol}{"Source"}) {
            next;
        }
        
        if(not $CompSign{1}{$Symbol}{"MnglName"}) {
            next;
        }
        
        if($ExtendedSymbols{$Symbol}) {
            next;
        }
        
        if(not defined $CompSign{2}{$Symbol}
        or not $CompSign{2}{$Symbol}{"MnglName"})
        {
            if(defined $UsedDump{1}{"DWARF"}
            and defined $UsedDump{2}{"DWARF"}
            and $Level eq "Source")
            { # not present in debug-info,
              # but present in dynsym
                if(linkSymbol($Symbol, 2, "-Deps")) {
                    next;
                }
                
                if($ISymbol ne $Symbol)
                {
                    if(linkSymbol($ISymbol, 2, "-Deps")) {
                        next;
                    }
                }
                
                if(my $SVer = $In::ABI{2}{"SymbolVersion"}{$Symbol})
                {
                    if(linkSymbol($SVer, 2, "-Deps")) {
                        next;
                    }
                }
                
                if(my $Alias = $CompSign{1}{$ISymbol}{"Alias"})
                {
                    if(linkSymbol($Alias, 2, "-Deps")) {
                        next;
                    }
                    
                    if(my $SAVer = $In::ABI{2}{"SymbolVersion"}{$Alias})
                    {
                        if(linkSymbol($SAVer, 2, "-Deps")) {
                            next;
                        }
                    }
                }
            }
            if($UsedDump{1}{"SrcBin"})
            {
                if($UsedDump{2}{"BinOnly"})
                { # support for different ABI dumps
                    if(not $CompSign{1}{$Symbol}{"Virt"}
                    and not $CompSign{1}{$Symbol}{"PureVirt"})
                    {
                        if($In::Opt{"CheckHeadersOnly"})
                        { # skip all removed symbols
                            if(my $Lang = $CompSign{1}{$Symbol}{"Lang"})
                            {
                                if($Lang eq "C")
                                { # support for old ABI dumps: missed extern "C" functions
                                    next;
                                }
                            }
                        }
                        else
                        {
                            if(not linkSymbol($Symbol, 1, "-Deps"))
                            { # skip removed inline symbols
                                next;
                            }
                        }
                    }
                }
            }
            
            if(not $CompSign{1}{$Symbol}{"Class"})
            {
                if(my $Short = $CompSign{1}{$Symbol}{"ShortName"})
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
        next if($CompSign{2}{$Symbol}{"PureVirt"});
        next if(not symbolFilter($Symbol, $CompSign{2}{$Symbol}, "Affected", $Level, 2));
        if($Level eq "Binary")
        {
            if($CompSign{2}{$Symbol}{"InLine"})
            {
                if(not $CompSign{2}{$Symbol}{"Virt"})
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
        next if($CompSign{1}{$Symbol}{"PureVirt"});
        next if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected", $Level, 1));
        if($Level eq "Binary")
        {
            if($CompSign{1}{$Symbol}{"InLine"})
            {
                if(not $CompSign{1}{$Symbol}{"Virt"})
                { # skip inline non-virtual functions
                    next;
                }
            }
        }
        else
        { # Source
            if(my $Alt = $SourceAlternative{$Symbol})
            {
                if(defined $CompSign{1}{$Alt}
                and $CompSign{1}{$Symbol}{"Const"})
                {
                    my $Cid = $CompSign{1}{$Symbol}{"Class"};
                    %{$CompatProblems{$Level}{$Symbol}{"Removed_Const_Overload"}{"this"}}=(
                        "Type_Name"=>$TypeInfo{1}{$Cid}{"Name"},
                        "Target"=>$Alt);
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
    
    if(not keys(%AddSymbolParams)) {
        return;
    }
    
    my $SecondVersion = $LibraryVersion==1?2:1;
    foreach my $Interface (sort keys(%{$CompSign{$LibraryVersion}}))
    {
        if(not keys(%{$AddSymbolParams{$Interface}})) {
            next;
        }
        
        foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{$LibraryVersion}{$Interface}{"Param"}}))
        { # add absent parameter names
            my $ParamName = $CompSign{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"};
            if($ParamName=~/\Ap\d+\Z/ and my $NewParamName = $AddSymbolParams{$Interface}{$ParamPos})
            { # names from the external file
                if(defined $CompSign{$SecondVersion}{$Interface}
                and defined $CompSign{$SecondVersion}{$Interface}{"Param"}{$ParamPos})
                {
                    if($CompSign{$SecondVersion}{$Interface}{"Param"}{$ParamPos}{"name"}=~/\Ap\d+\Z/) {
                        $CompSign{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"} = $NewParamName;
                    }
                }
                else {
                    $CompSign{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"} = $NewParamName;
                }
            }
        }
    }
}

sub detectChangedTypedefs()
{ # detect changed typedefs to show
  # correct function signatures
    foreach my $Typedef (keys(%{$In::ABI{1}{"TypedefBase"}}))
    {
        if(not $Typedef) {
            next;
        }
        
        my $BName1 = $In::ABI{1}{"TypedefBase"}{$Typedef};
        if(not $BName1 or isAnon($BName1)) {
            next;
        }
        my $BName2 = $In::ABI{2}{"TypedefBase"}{$Typedef};
        if(not $BName2 or isAnon($BName2)) {
            next;
        }
        if($BName1 ne $BName2) {
            $ChangedTypedef{$Typedef} = 1;
        }
    }
}

sub symbolPrefix($$)
{
    my ($Symbol, $LVer) = @_;
    my $ShortName = $CompSign{$LVer}{$Symbol}{"ShortName"};
    if(my $ClassId = $CompSign{$LVer}{$Symbol}{"Class"})
    { # methods
        $ShortName = $TypeInfo{$LVer}{$ClassId}{"Name"}."::".$ShortName;
    }
    return $ShortName;
}

sub setAlternative($)
{
    my $Symbol = $_[0];
    my $PSymbol = $Symbol;
    if(not defined $CompSign{2}{$PSymbol}
    or (not $CompSign{2}{$PSymbol}{"MnglName"}
    and not $CompSign{2}{$PSymbol}{"ShortName"}))
    { # search for a pair
        if(my $ShortName = $CompSign{1}{$PSymbol}{"ShortName"})
        {
            if($CompSign{1}{$PSymbol}{"Data"})
            {
                if($PSymbol=~s/L(\d+$ShortName(E)\Z)/$1/
                or $PSymbol=~s/(\d+$ShortName(E)\Z)/L$1/)
                {
                    if(defined $CompSign{2}{$PSymbol}
                    and $CompSign{2}{$PSymbol}{"MnglName"})
                    {
                        $SourceAlternative{$Symbol} = $PSymbol;
                        $SourceAlternative_B{$PSymbol} = $Symbol;
                        if(not defined $CompSign{1}{$PSymbol}
                        or not $CompSign{1}{$PSymbol}{"MnglName"}) {
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
                        if(defined $CompSign{2}{$PSymbol}
                        and $CompSign{2}{$PSymbol}{"MnglName"})
                        {
                            $SourceAlternative{$Symbol} = $PSymbol;
                            $SourceAlternative_B{$PSymbol} = $Symbol;
                            if(not defined $CompSign{1}{$PSymbol}
                            or not $CompSign{1}{$PSymbol}{"MnglName"}) {
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
    my ($Symbol, $LVer) = @_;
    if($CompSign{$LVer}{$Symbol}{"Data"})
    {
        return "Global_Data";
    }
    elsif($CompSign{$LVer}{$Symbol}{"Class"})
    {
        return "Method";
    }
    return "Function";
}

sub isConstData($$)
{
    my ($Symbol, $LVer) = @_;
    
    my $Return = $CompSign{$LVer}{$Symbol}{"Return"};
    my $RTName = uncoverTypedefs($TypeInfo{$LVer}{$Return}{"Name"}, $LVer);
    
    return ($RTName=~/\bconst\Z/);
}

sub getConstDataSym($$)
{
    my ($Symbol, $LVer) = @_;
    
    my $Short = $CompSign{$LVer}{$Symbol}{"ShortName"};
    $Symbol=~s/(\d+$Short)/L$1/;
    return $Symbol;
}

sub getNonConstDataSym($$)
{
    my ($Symbol, $LVer) = @_;
    
    my $Short = $CompSign{$LVer}{$Symbol}{"ShortName"};
    $Symbol=~s/L(\d+$Short)/$1/;
    return $Symbol;
}

sub mergeSymbols($)
{
    my $Level = $_[0];
    my %SubProblems = ();
    
    mergeBases($Level);
    
    my %AddedOverloads = ();
    foreach my $Symbol (sort keys(%{$AddedInt{$Level}}))
    { # check all added exported symbols
        if(not $CompSign{2}{$Symbol}{"Header"}
        and not $CompSign{2}{$Symbol}{"Source"}) {
            next;
        }
        if(defined $CompSign{1}{$Symbol}
        and ($CompSign{1}{$Symbol}{"Header"} or $CompSign{1}{$Symbol}{"Source"}))
        { # double-check added symbol
            next;
        }
        if($Symbol=~/\A(_Z|\?)/)
        { # C++
            $AddedOverloads{symbolPrefix($Symbol, 2)}{getSignature($Symbol, 2, "Qual")} = $Symbol;
        }
        if(my $OverriddenMethod = $CompSign{2}{$Symbol}{"Override"})
        { # register virtual overridings
            my $Cid = $CompSign{2}{$Symbol}{"Class"};
            my $AffectedClass_Name = $TypeInfo{2}{$Cid}{"Name"};
            if(defined $CompSign{1}{$OverriddenMethod} and $CompSign{1}{$OverriddenMethod}{"Virt"}
            and not $CompSign{1}{$OverriddenMethod}{"Private"})
            {
                if($TName_Tid{1}{$AffectedClass_Name})
                { # class should exist in previous version
                    if(not isCopyingClass($TName_Tid{1}{$AffectedClass_Name}, 1))
                    { # old v-table is NOT copied by old applications
                        if(symbolFilter($OverriddenMethod, $CompSign{1}{$OverriddenMethod}, "Affected", $Level, 1))
                        {
                            %{$CompatProblems{$Level}{$OverriddenMethod}{"Overridden_Virtual_Method"}{$Symbol}}=(
                                "Type_Name"=>$AffectedClass_Name,
                                "Target"=>$Symbol,
                                "Old_Value"=>$OverriddenMethod,
                                "New_Value"=>$Symbol);
                        }
                    }
                }
            }
        }
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # check all removed exported symbols
        if(not $CompSign{1}{$Symbol}{"Header"}
        and not $CompSign{1}{$Symbol}{"Source"}) {
            next;
        }
        if(defined $CompSign{2}{$Symbol}
        and ($CompSign{2}{$Symbol}{"Header"} or $CompSign{2}{$Symbol}{"Source"}))
        { # double-check removed symbol
            next;
        }
        if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected", $Level, 1)) {
            next;
        }
        
        $CheckedSymbols{$Level}{$Symbol} = 1;
        
        if(my $OverriddenMethod = $CompSign{1}{$Symbol}{"Override"})
        { # register virtual overridings
            my $Cid = $CompSign{1}{$Symbol}{"Class"};
            my $AffectedClass_Name = $TypeInfo{1}{$Cid}{"Name"};
            if(defined $CompSign{2}{$OverriddenMethod}
            and $CompSign{2}{$OverriddenMethod}{"Virt"})
            {
                if($TName_Tid{2}{$AffectedClass_Name})
                { # class should exist in newer version
                    if(not isCopyingClass($CompSign{1}{$Symbol}{"Class"}, 1))
                    { # old v-table is NOT copied by old applications
                        %{$CompatProblems{$Level}{$Symbol}{"Overridden_Virtual_Method_B"}{$OverriddenMethod}}=(
                            "Type_Name"=>$AffectedClass_Name,
                            "Target"=>$OverriddenMethod,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$OverriddenMethod);
                    }
                }
            }
        }
        
        if($Level eq "Binary"
        and $In::Opt{"Target"} eq "windows")
        { # register the reason of symbol name change
            if(defined $CompSign{1}{$Symbol}{"Unmangled"}
            and my $NewSym = getMangled_MSVC($CompSign{1}{$Symbol}{"Unmangled"}, 2))
            {
                if($AddedInt{$Level}{$NewSym})
                {
                    if($CompSign{1}{$Symbol}{"Static"} ne $CompSign{2}{$NewSym}{"Static"})
                    {
                        if($CompSign{2}{$NewSym}{"Static"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Static"}{$Symbol}}=(
                                "Target"=>$Symbol,
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Non_Static"}{$Symbol}}=(
                                "Target"=>$Symbol,
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                    }
                    if($CompSign{1}{$Symbol}{"Virt"} ne $CompSign{2}{$NewSym}{"Virt"})
                    {
                        if($CompSign{2}{$NewSym}{"Virt"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Virtual"}{$Symbol}}=(
                                "Target"=>$Symbol,
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Non_Virtual"}{$Symbol}}=(
                                "Target"=>$Symbol,
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSym  );
                        }
                    }
                    my $RTId1 = $CompSign{1}{$Symbol}{"Return"};
                    my $RTId2 = $CompSign{2}{$NewSym}{"Return"};
                    my $RTName1 = $TypeInfo{1}{$RTId1}{"Name"};
                    my $RTName2 = $TypeInfo{2}{$RTId2}{"Name"};
                    if($RTName1 ne $RTName2)
                    {
                        my $ProblemType = "Symbol_Changed_Return";
                        if($CompSign{1}{$Symbol}{"Data"}) {
                            $ProblemType = "Global_Data_Symbol_Changed_Type";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{$Symbol}}=(
                            "Target"=>$Symbol,
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
            my $Prefix = symbolPrefix($Symbol, 1);
            if(my @Overloads = sort keys(%{$AddedOverloads{$Prefix}})
            and not $AddedOverloads{$Prefix}{getSignature($Symbol, 1, "Qual")})
            { # changed signature: params, "const"-qualifier
                my $NewSym = $AddedOverloads{$Prefix}{$Overloads[0]};
                if($CompSign{1}{$Symbol}{"Constructor"})
                {
                    if($Symbol=~/(C[1-2][EI])/)
                    {
                        my $CtorType = $1;
                        $NewSym=~s/(C[1-2][EI])/$CtorType/g;
                    }
                }
                elsif($CompSign{1}{$Symbol}{"Destructor"})
                {
                    if($Symbol=~/(D[0-2][EI])/)
                    {
                        my $DtorType = $1;
                        $NewSym=~s/(D[0-2][EI])/$DtorType/g;
                    }
                }
                my $NS1 = $CompSign{1}{$Symbol}{"NameSpace"};
                my $NS2 = $CompSign{2}{$NewSym}{"NameSpace"};
                if((not $NS1 and not $NS2) or ($NS1 and $NS2 and $NS1 eq $NS2))
                { # from the same class and namespace
                    if($CompSign{1}{$Symbol}{"Const"}
                    and not $CompSign{2}{$NewSym}{"Const"})
                    { # "const" to non-"const"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Const"}{$Symbol}}=(
                            "Type_Name"=>$TypeInfo{1}{$CompSign{1}{$Symbol}{"Class"}}{"Name"},
                            "Target"=>$Symbol,
                            "New_Signature"=>$NewSym,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    elsif(not $CompSign{1}{$Symbol}{"Const"}
                    and $CompSign{2}{$NewSym}{"Const"})
                    { # non-"const" to "const"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Const"}{$Symbol}}=(
                            "Target"=>$Symbol,
                            "New_Signature"=>$NewSym,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    if($CompSign{1}{$Symbol}{"Volatile"}
                    and not $CompSign{2}{$NewSym}{"Volatile"})
                    { # "volatile" to non-"volatile"
                        
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Volatile"}{$Symbol}}=(
                            "Target"=>$Symbol,
                            "New_Signature"=>$NewSym,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    elsif(not $CompSign{1}{$Symbol}{"Volatile"}
                    and $CompSign{2}{$NewSym}{"Volatile"})
                    { # non-"volatile" to "volatile"
                        %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Volatile"}{$Symbol}}=(
                            "Target"=>$Symbol,
                            "New_Signature"=>$NewSym,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                    if(getSignature($Symbol, 1, "Param") ne getSignature($NewSym, 2, "Param"))
                    { # params list
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Changed_Parameters"}{$Symbol}}=(
                            "Target"=>$Symbol,
                            "New_Signature"=>$NewSym,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSym  );
                    }
                }
            }
        }
    }
    
    foreach my $Symbol (sort keys(%{$CompSign{1}}))
    { # checking symbols
        my ($SN, $SS, $SV) = symbolParts($Symbol);
        if($Level eq "Source")
        { # remove symbol version
            $Symbol = $SN;
        }
        else
        { # Binary
            if(not $SV)
            { # symbol without version
                if(my $VSym = $In::ABI{1}{"SymbolVersion"}{$Symbol})
                { # the symbol is linked with versioned symbol
                    if($CompSign{2}{$VSym}{"MnglName"})
                    { # show report for symbol@ver only
                        next;
                    }
                    elsif(not linkSymbol($VSym, 2, "-Deps"))
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
        if($CompSign{1}{$Symbol}{"Data"}
        and not defined $CompSign{2}{$Symbol})
        {
            if(isConstData($Symbol, 1))
            {
                if(my $NonConstSymbol = getNonConstDataSym($Symbol, 1))
                {
                    if($CompSign{2}{$NonConstSymbol}) {
                        $PSymbol = $NonConstSymbol;
                    }
                }
            }
            else
            {
                if(my $ConstSymbol = getConstDataSym($Symbol, 1))
                {
                    if($CompSign{2}{$ConstSymbol}) {
                        $PSymbol = $ConstSymbol;
                    }
                }
            }
        }
        
        if($CompSign{1}{$Symbol}{"Private"})
        { # private symbols
            next;
        }
        if(not defined $CompSign{1}{$Symbol}
        or not defined $CompSign{2}{$PSymbol})
        { # no info
            next;
        }
        if(not $CompSign{1}{$Symbol}{"MnglName"}
        or not $CompSign{2}{$PSymbol}{"MnglName"})
        { # no mangled name
            next;
        }
        if((not $CompSign{1}{$Symbol}{"Header"} and not $CompSign{1}{$Symbol}{"Source"})
        or (not $CompSign{2}{$PSymbol}{"Header"} and not $CompSign{2}{$PSymbol}{"Source"}))
        { # without a header or source
            next;
        }
        
        if(not $CompSign{1}{$Symbol}{"PureVirt"}
        and $CompSign{2}{$PSymbol}{"PureVirt"})
        { # became pure
            next;
        }
        if($CompSign{1}{$Symbol}{"PureVirt"}
        and not $CompSign{2}{$PSymbol}{"PureVirt"})
        { # became non-pure
            next;
        }
        
        if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected + InlineVirt", $Level, 1))
        { # exported, target, inline virtual and pure virtual
            next;
        }
        
        if($CompSign{1}{$Symbol}{"Data"}
        and $CompSign{2}{$PSymbol}{"Data"})
        {
            my $Value1 = $CompSign{1}{$Symbol}{"Value"};
            my $Value2 = $CompSign{2}{$PSymbol}{"Value"};
            if(defined $Value1)
            {
                $Value1 = showVal($Value1, $CompSign{1}{$Symbol}{"Return"}, 1);
                if(defined $Value2)
                {
                    $Value2 = showVal($Value2, $CompSign{2}{$PSymbol}{"Return"}, 2);
                    if($Value1 ne $Value2)
                    {
                        %{$CompatProblems{$Level}{$Symbol}{"Global_Data_Value_Changed"}{""}}=(
                            "Old_Value"=>$Value1,
                            "New_Value"=>$Value2,
                            "Target"=>$Symbol  );
                    }
                }
            }
        }
        
        if($CompSign{2}{$PSymbol}{"Private"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Private"}{""}}=(
                "Target"=>$PSymbol  );
        }
        elsif(not $CompSign{1}{$Symbol}{"Protected"}
        and $CompSign{2}{$PSymbol}{"Protected"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Protected"}{""}}=(
                "Target"=>$PSymbol  );
        }
        elsif($CompSign{1}{$Symbol}{"Protected"}
        and not $CompSign{2}{$PSymbol}{"Protected"})
        {
            %{$CompatProblems{$Level}{$Symbol}{getSymKind($Symbol, 1)."_Became_Public"}{""}}=(
                "Target"=>$PSymbol  );
        }
        
        # checking virtual table
        mergeVirtualTables($Symbol, $Level);
        
        if($In::Opt{"CompileError"})
        { # if some errors occurred at the compiling stage
          # then some false positives can be skipped here
            if(not $CompSign{1}{$Symbol}{"Data"} and $CompSign{2}{$PSymbol}{"Data"}
            and not $GlobalDataObject{2}{$Symbol})
            { # missed information about parameters in newer version
                next;
            }
            if($CompSign{1}{$Symbol}{"Data"} and not $GlobalDataObject{1}{$Symbol}
            and not $CompSign{2}{$PSymbol}{"Data"})
            { # missed information about parameters in older version
                next;
            }
        }
        my ($MnglName, $VersionSpec, $SymbolVersion) = symbolParts($Symbol);
        
        # check attributes
        if($CompSign{2}{$PSymbol}{"Static"}
        and not $CompSign{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/)
        {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Static"}{""}}=(
                "Target"=>$Symbol
            );
        }
        elsif(not $CompSign{2}{$PSymbol}{"Static"}
        and $CompSign{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/)
        {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Non_Static"}{""}}=(
                "Target"=>$Symbol
            );
        }
        if(($CompSign{1}{$Symbol}{"Virt"} and $CompSign{2}{$PSymbol}{"Virt"})
        or ($CompSign{1}{$Symbol}{"PureVirt"} and $CompSign{2}{$PSymbol}{"PureVirt"}))
        { # relative position of virtual and pure virtual methods
            if($Level eq "Binary")
            {
                if(defined $CompSign{1}{$Symbol}{"RelPos"} and defined $CompSign{2}{$PSymbol}{"RelPos"}
                and $CompSign{1}{$Symbol}{"RelPos"}!=$CompSign{2}{$PSymbol}{"RelPos"})
                { # top-level virtual methods only
                    my $Class_Id = $CompSign{1}{$Symbol}{"Class"};
                    my $Class_Name = $TypeInfo{1}{$Class_Id}{"Name"};
                    if(defined $VirtualTable{1}{$Class_Name} and defined $VirtualTable{2}{$Class_Name}
                    and $VirtualTable{1}{$Class_Name}{$Symbol}!=$VirtualTable{2}{$Class_Name}{$Symbol})
                    { # check absolute position of a virtual method (including added and removed methods)
                        my %Class_Type = getType($Class_Id, 1);
                        my $ProblemType = "Virtual_Method_Position";
                        if($CompSign{1}{$Symbol}{"PureVirt"}) {
                            $ProblemType = "Pure_Virtual_Method_Position";
                        }
                        if(isUsedClass($Class_Id, 1, $Level))
                        {
                            my @Affected = ($Symbol, keys(%{$OverriddenMethods{1}{$Symbol}}));
                            foreach my $ASymbol (@Affected)
                            {
                                if(not symbolFilter($ASymbol, $CompSign{1}{$ASymbol}, "Affected", $Level, 1)) {
                                    next;
                                }
                                %{$CompatProblems{$Level}{$ASymbol}{$ProblemType}{$Symbol}}=(
                                    "Type_Name"=>$Class_Type{"Name"},
                                    "Old_Value"=>$CompSign{1}{$Symbol}{"RelPos"},
                                    "New_Value"=>$CompSign{2}{$PSymbol}{"RelPos"},
                                    "Target"=>$Symbol);
                            }
                            $VTableChanged_M{$Class_Type{"Name"}} = 1;
                        }
                    }
                }
            }
        }
        if($CompSign{1}{$Symbol}{"PureVirt"}
        or $CompSign{2}{$PSymbol}{"PureVirt"})
        { # do NOT check type changes in pure virtuals
            next;
        }
        
        $CheckedSymbols{$Level}{$Symbol} = 1;
        
        if($Symbol=~/\A(_Z|\?)/
        or keys(%{$CompSign{1}{$Symbol}{"Param"}})==keys(%{$CompSign{2}{$PSymbol}{"Param"}}))
        { # C/C++: changes in parameters
            foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{1}{$Symbol}{"Param"}}))
            { # checking parameters
                mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level, 1);
            }
        }
        else
        { # C: added/removed parameters
            foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{2}{$PSymbol}{"Param"}}))
            { # checking added parameters
                my $PType2_Id = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                my $PType2_Name = $TypeInfo{2}{$PType2_Id}{"Name"};
                last if($PType2_Name eq "...");
                my $PName = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"name"};
                my $PName_Old = (defined $CompSign{1}{$Symbol}{"Param"}{$ParamPos})?$CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_Prev = "-1";
                if($PName=~/\Ap\d+\Z/i)
                { # added unnamed parameter ( pN )
                    my @Positions1 = findParamPairByTypeAndPos($PType2_Name, $ParamPos, "backward", $Symbol, 1);
                    my @Positions2 = findParamPairByTypeAndPos($PType2_Name, $ParamPos, "backward", $Symbol, 2);
                    if($#Positions1==-1 or $#Positions2>$#Positions1) {
                        $ParamPos_Prev = "lost";
                    }
                }
                else {
                    $ParamPos_Prev = findParamPairByName($PName, $Symbol, 1);
                }
                if($ParamPos_Prev eq "lost")
                {
                    if($ParamPos>keys(%{$CompSign{1}{$Symbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Added_Parameter";
                        if($PName=~/\Ap\d+\Z/) {
                            $ProblemType = "Added_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                            "Target"=>$PName,
                            "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                            "Param_Type"=>$PType2_Name,
                            "New_Signature"=>$Symbol  );
                    }
                    else
                    {
                        my %ParamType_Pure = getPureType($PType2_Id, 2);
                        my $PairType_Id = $CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                        my %PairType_Pure = getPureType($PairType_Id, 1);
                        if(($ParamType_Pure{"Name"} eq $PairType_Pure{"Name"} or $PType2_Name eq $TypeInfo{1}{$PairType_Id}{"Name"})
                        and findParamPairByName($PName_Old, $Symbol, 2) eq "lost")
                        {
                            if($PName_Old!~/\Ap\d+\Z/ and $PName!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos)." Parameter"}}=(
                                    "Target"=>$PName_Old,
                                    "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                    "Param_Type"=>$PType2_Name,
                                    "Old_Value"=>$PName_Old,
                                    "New_Value"=>$PName,
                                    "New_Signature"=>$Symbol  );
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
                                "New_Signature"=>$Symbol  );
                        }
                    }
                }
            }
            foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{1}{$Symbol}{"Param"}}))
            { # check relevant parameters
                my $PType1_Id = $CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                my $ParamName1 = $CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"name"};
                # FIXME: find relevant parameter by name
                if(defined $CompSign{2}{$PSymbol}{"Param"}{$ParamPos})
                {
                    my $PType2_Id = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                    my $ParamName2 = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"name"};
                    if($TypeInfo{1}{$PType1_Id}{"Name"} eq $TypeInfo{2}{$PType2_Id}{"Name"}
                    or ($ParamName1!~/\Ap\d+\Z/i and $ParamName1 eq $ParamName2)) {
                        mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level, 0);
                    }
                }
            }
            foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{1}{$Symbol}{"Param"}}))
            { # checking removed parameters
                my $PType1_Id = $CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                my $PType1_Name = $TypeInfo{1}{$PType1_Id}{"Name"};
                last if($PType1_Name eq "...");
                my $PName = $CompSign{1}{$Symbol}{"Param"}{$ParamPos}{"name"};
                my $PName_New = (defined $CompSign{2}{$PSymbol}{"Param"}{$ParamPos})?$CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_New = "-1";
                if($PName=~/\Ap\d+\Z/i)
                { # removed unnamed parameter ( pN )
                    my @Positions1 = findParamPairByTypeAndPos($PType1_Name, $ParamPos, "forward", $Symbol, 1);
                    my @Positions2 = findParamPairByTypeAndPos($PType1_Name, $ParamPos, "forward", $Symbol, 2);
                    if($#Positions2==-1 or $#Positions2<$#Positions1) {
                        $ParamPos_New = "lost";
                    }
                }
                else {
                    $ParamPos_New = findParamPairByName($PName, $Symbol, 2);
                }
                if($ParamPos_New eq "lost")
                {
                    if($ParamPos>keys(%{$CompSign{2}{$PSymbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Removed_Parameter";
                        if($PName=~/\Ap\d+\Z/) {
                            $ProblemType = "Removed_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showPos($ParamPos)." Parameter"}}=(
                            "Target"=>$PName,
                            "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                            "Param_Type"=>$PType1_Name,
                            "New_Signature"=>$Symbol);
                    }
                    elsif($ParamPos<keys(%{$CompSign{1}{$Symbol}{"Param"}})-1)
                    {
                        my %ParamType_Pure = getPureType($PType1_Id, 1);
                        my $PairType_Id = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                        my %PairType_Pure = getPureType($PairType_Id, 2);
                        if(($ParamType_Pure{"Name"} eq $PairType_Pure{"Name"} or $PType1_Name eq $TypeInfo{2}{$PairType_Id}{"Name"})
                        and findParamPairByName($PName_New, $Symbol, 1) eq "lost")
                        {
                            if($PName_New!~/\Ap\d+\Z/ and $PName!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos)." Parameter"}}=(
                                    "Target"=>$PName,
                                    "Param_Pos"=>adjustParamPos($ParamPos, $Symbol, 2),
                                    "Param_Type"=>$PType1_Name,
                                    "Old_Value"=>$PName,
                                    "New_Value"=>$PName_New,
                                    "New_Signature"=>$Symbol);
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
                                "New_Signature"=>$Symbol);
                        }
                    }
                }
            }
        }
        # checking return type
        my $ReturnType1_Id = $CompSign{1}{$Symbol}{"Return"};
        my $ReturnType2_Id = $CompSign{2}{$PSymbol}{"Return"};
        my %RC_SubProblems = detectTypeChange($ReturnType1_Id, $ReturnType2_Id, "Return", $Level);
        
        foreach my $SubProblemType (keys(%RC_SubProblems))
        {
            my $New_Value = $RC_SubProblems{$SubProblemType}{"New_Value"};
            my $Old_Value = $RC_SubProblems{$SubProblemType}{"Old_Value"};
            my %ProblemTypes = ();
            
            if($CompSign{1}{$Symbol}{"Data"})
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
                    if(addedQual($Old_Value, $New_Value, "volatile"))
                    {
                        $ProblemTypes{"Return_Value_Became_Volatile"} = 1;
                        if($Level ne "Source"
                        or not cmpBTypes($Old_Value, $New_Value, 1, 2)) {
                            $ProblemTypes{"Return_Type"} = 1;
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
            and not $CompSign{1}{$Symbol}{"Data"})
            {
                my (%Conv1, %Conv2) = ();
                
                if($UseConv_Real{1}{"R"} and $UseConv_Real{2}{"R"})
                {
                    %Conv1 = callingConvention_R_Real($CompSign{1}{$Symbol});
                    %Conv2 = callingConvention_R_Real($CompSign{2}{$PSymbol});
                }
                else
                {
                    %Conv1 = callingConvention_R_Model($CompSign{1}{$Symbol}, 1);
                    %Conv2 = callingConvention_R_Model($CompSign{2}{$PSymbol}, 2);
                }
                
                if($SubProblemType eq "Return_Type_Became_Void")
                {
                    if(keys(%{$CompSign{1}{$Symbol}{"Param"}}))
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
                    if(keys(%{$CompSign{1}{$Symbol}{"Param"}}))
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
            
            if($CompSign{1}{$Symbol}{"Data"})
            {
                if($Level eq "Binary")
                {
                    if(getPLevel($ReturnType1_Id, 1)==0)
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
                                    "Old_Size"=>$Old_Size*$BYTE,
                                    "New_Size"=>$New_Size*$BYTE };
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
        my $ObjTId1 = $CompSign{1}{$Symbol}{"Class"};
        my $ObjTId2 = $CompSign{2}{$PSymbol}{"Class"};
        if($ObjTId1 and $ObjTId2
        and not $CompSign{1}{$Symbol}{"Static"}
        and not $CompSign{1}{$Symbol}{"Data"})
        {
            my ($ThisPtr1, $ThisPtr2) = (undef, undef);
            if($CompSign{1}{$Symbol}{"Const"})
            {
                $ThisPtr1 = getTypeIdByName($TypeInfo{1}{$ObjTId1}{"Name"}." const*const", 1);
                $ThisPtr2 = getTypeIdByName($TypeInfo{2}{$ObjTId2}{"Name"}." const*const", 2);
            }
            else
            {
                $ThisPtr1 = getTypeIdByName($TypeInfo{1}{$ObjTId1}{"Name"}."*const", 1);
                $ThisPtr2 = getTypeIdByName($TypeInfo{2}{$ObjTId2}{"Name"}."*const", 2);
            }
            
            if($ThisPtr1 and $ThisPtr2)
            {
                @RecurTypes = ();
                my $Sub_SubProblems = mergeTypes($ThisPtr1, $ThisPtr2, $Level);
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
    
    # mark all affected symbols as "checked"
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
    $T1 = uncoverTypedefs($T1, $V1);
    $T2 = uncoverTypedefs($T2, $V2);
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
    $Old_Value = uncoverTypedefs($Old_Value, $V1);
    $New_Value = uncoverTypedefs($New_Value, $V2);
    
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
    my ($Value, $TypeId, $LVer) = @_;
    my %PureType = getPureType($TypeId, $LVer);
    my $TName = uncoverTypedefs($PureType{"Name"}, $LVer);
    
    if(defined $StringTypes{$TName} or $TName=~/string/i)
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
    my ($LVer, $Symbol, $Pos) = @_;
    
    if(defined $CompSign{$LVer}{$Symbol}{"Reg"})
    {
        my %Regs = ();
        foreach my $Elem (sort keys(%{$CompSign{$LVer}{$Symbol}{"Reg"}}))
        {
            if(index($Elem, $Pos)==0
            and $Elem=~/\A$Pos([\.\+]|\Z)/) {
                $Regs{$CompSign{$LVer}{$Symbol}{"Reg"}{$Elem}} = 1;
            }
        }
        
        return join(", ", sort keys(%Regs));
    }
    elsif(defined $CompSign{$LVer}{$Symbol}{"Param"}
    and defined $CompSign{$LVer}{$Symbol}{"Param"}{0}
    and not defined $CompSign{$LVer}{$Symbol}{"Param"}{0}{"offset"})
    {
        return "unknown";
    }
    
    return undef;
}

sub mergeParameters($$$$$$)
{
    my ($Symbol, $PSymbol, $ParamPos1, $ParamPos2, $Level, $CheckRenamed) = @_;
    
    my $PTid1 = $CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"type"};
    my $PTid2 = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"type"};
    
    if(not $PTid1
    or not $PTid2) {
        return;
    }
    
    my $PName1 = $CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"name"};
    my $PName2 = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"name"};
    
    if(index($Symbol, "_Z")==0
    or index($Symbol, "?")==0) 
    { # do not merge "this" 
        if($PName1 eq "this" or $PName2 eq "this") { 
            return; 
        } 
    }
    
    my %Type1 = getType($PTid1, 1);
    my %Type2 = getType($PTid2, 2);
    
    my %PureType1 = getPureType($PTid1, 1);
    
    my %BaseType1 = getBaseType($PTid1, 1);
    my %BaseType2 = getBaseType($PTid2, 2);
    
    my $ParamLoc = ($PName1)?$PName1:showPos($ParamPos1)." Parameter";
    
    if($Level eq "Binary")
    {
        if($CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
        and not $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
        {
            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Non_Register"}{$ParamLoc}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1)  );
        }
        elsif(not $CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
        and $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
        {
            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Register"}{$ParamLoc}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1)  );
        }
        
        if(defined $UsedDump{1}{"DWARF"}
        and defined $UsedDump{2}{"DWARF"})
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
                        %{$CompatProblems{$Level}{$Symbol}{"Parameter_Changed_Register"}{$ParamLoc}}=(
                            "Target"=>$PName1,
                            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                            "Old_Value"=>$Old_Regs,
                            "New_Value"=>$New_Regs  );
                    }
                }
                elsif($Old_Regs and not $New_Regs)
                {
                    %{$CompatProblems{$Level}{$Symbol}{"Parameter_From_Register"}{$ParamLoc}}=(
                        "Target"=>$PName1,
                        "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                        "Old_Value"=>$Old_Regs  );
                }
                elsif(not $Old_Regs and $New_Regs)
                {
                    %{$CompatProblems{$Level}{$Symbol}{"Parameter_To_Register"}{$ParamLoc}}=(
                        "Target"=>$PName1,
                        "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                        "New_Value"=>$New_Regs  );
                }
            }
            
            if((my $Old_Offset = $CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"offset"}) ne ""
            and (my $New_Offset = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"offset"}) ne "")
            {
                if($Old_Offset ne $New_Offset)
                {
                    my $Start1 = $CompSign{1}{$Symbol}{"Param"}{0}{"offset"};
                    my $Start2 = $CompSign{2}{$PSymbol}{"Param"}{0}{"offset"};
                    
                    $Old_Offset = $Old_Offset - $Start1;
                    $New_Offset = $New_Offset - $Start2;
                    
                    if($Old_Offset ne $New_Offset)
                    {
                        %{$CompatProblems{$Level}{$Symbol}{"Parameter_Changed_Offset"}{$ParamLoc}}=(
                            "Target"=>$PName1,
                            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                            "Old_Value"=>$Old_Offset,
                            "New_Value"=>$New_Offset  );
                    }
                }
            }
        }
    }
    
    my $Value_Old = $CompSign{1}{$Symbol}{"Param"}{$ParamPos1}{"default"};
    my $Value_New = $CompSign{2}{$PSymbol}{"Param"}{$ParamPos2}{"default"};
    
    if(defined $Value_Old)
    {
        $Value_Old = showVal($Value_Old, $PTid1, 1);
        if(defined $Value_New)
        {
            $Value_New = showVal($Value_New, $PTid2, 2);
            if($Value_Old ne $Value_New)
            { # FIXME: how to distinguish "0" and 0 (NULL)
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Changed"}{$ParamLoc}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                    "Old_Value"=>$Value_Old,
                    "New_Value"=>$Value_New  );
            }
        }
        else
        {
            %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Removed"}{$ParamLoc}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                "Old_Value"=>$Value_Old  );
        }
    }
    elsif(defined $Value_New)
    {
        $Value_New = showVal($Value_New, $PTid2, 2);
        %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Added"}{$ParamLoc}}=(
            "Target"=>$PName1,
            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
            "New_Value"=>$Value_New  );
    }
    
    if($CheckRenamed)
    {
        if($PName1 and $PName2 and $PName1 ne $PName2
        and $PTid1!=-1 and $PTid2!=-1
        and $PName1!~/\Ap\d+\Z/ and $PName2!~/\Ap\d+\Z/)
        { # except unnamed "..." value list (Id=-1)
            %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showPos($ParamPos1)." Parameter"}}=(
                "Target"=>$PName1,
                "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
                "Param_Type"=>$TypeInfo{1}{$PTid1}{"Name"},
                "Old_Value"=>$PName1,
                "New_Value"=>$PName2,
                "New_Signature"=>$Symbol);
        }
    }
    
    # checking type change (replace)
    my %SubProblems = detectTypeChange($PTid1, $PTid2, "Parameter", $Level);
    
    foreach my $SubProblemType (keys(%SubProblems))
    { # add new problems, remove false alarms
        my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
        my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
        
        # quals
        if($SubProblemType eq "Parameter_Type"
        or $SubProblemType eq "Parameter_Type_And_Size"
        or $SubProblemType eq "Parameter_Type_Format")
        {
            if(addedQual($Old_Value, $New_Value, "restrict")) {
                %{$SubProblems{"Parameter_Became_Restrict"}} = %{$SubProblems{$SubProblemType}};
            }
            elsif(removedQual($Old_Value, $New_Value, "restrict")) {
                %{$SubProblems{"Parameter_Became_Non_Restrict"}} = %{$SubProblems{$SubProblemType}};
            }
            
            if(removedQual($Old_Value, $New_Value, "volatile")) {
                %{$SubProblems{"Parameter_Became_Non_Volatile"}} = %{$SubProblems{$SubProblemType}};
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
            my (%Conv1, %Conv2) = ();
            
            if($UseConv_Real{1}{"P"} and $UseConv_Real{2}{"P"})
            { # real
                %Conv1 = callingConvention_P_Real($CompSign{1}{$Symbol}, $ParamPos1);
                %Conv2 = callingConvention_P_Real($CompSign{2}{$PSymbol}, $ParamPos2);
            }
            else
            { # model
                %Conv1 = callingConvention_P_Model($CompSign{1}{$Symbol}, $ParamPos1, 1);
                %Conv2 = callingConvention_P_Model($CompSign{2}{$PSymbol}, $ParamPos2, 2);
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
        %{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$ParamLoc}}=(
            "Target"=>$PName1,
            "Param_Pos"=>adjustParamPos($ParamPos1, $Symbol, 1),
            "New_Signature"=>$Symbol);
        @{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$ParamLoc}}{keys(%{$SubProblems{$SubProblemType}})} = values %{$SubProblems{$SubProblemType}};
    }
    
    @RecurTypes = ();
    
    # checking type definition changes
    my $Sub_SubProblems = mergeTypes($PTid1, $PTid2, $Level);
    foreach my $SubProblemType (keys(%{$Sub_SubProblems}))
    {
        foreach my $SubLoc (keys(%{$Sub_SubProblems->{$SubProblemType}}))
        {
            my $NewProblemType = $SubProblemType;
            if($SubProblemType eq "DataType_Size")
            {
                if($PureType1{"Type"} ne "Pointer"
                and $PureType1{"Type"} ne "Ref"
                and index($SubLoc, "->")==-1)
                { # stack has been affected
                    $NewProblemType = "DataType_Size_And_Stack";
                }
            }
            my $NewLoc = $ParamLoc;
            if($SubLoc) {
                $NewLoc .= "->".$SubLoc;
            }
            $CompatProblems{$Level}{$Symbol}{$NewProblemType}{$NewLoc} = $Sub_SubProblems->{$SubProblemType}{$SubLoc};
        }
    }
}

sub findParamPairByName($$$)
{
    my ($Name, $Symbol, $LVer) = @_;
    foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{$LVer}{$Symbol}{"Param"}}))
    {
        next if(not defined $CompSign{$LVer}{$Symbol}{"Param"}{$ParamPos});
        if($CompSign{$LVer}{$Symbol}{"Param"}{$ParamPos}{"name"} eq $Name)
        {
            return $ParamPos;
        }
    }
    return "lost";
}

sub findParamPairByTypeAndPos($$$$$)
{
    my ($TypeName, $MediumPos, $Order, $Symbol, $LVer) = @_;
    my @Positions = ();
    foreach my $ParamPos (sort {$a<=>$b} keys(%{$CompSign{$LVer}{$Symbol}{"Param"}}))
    {
        next if($Order eq "backward" and $ParamPos>$MediumPos);
        next if($Order eq "forward" and $ParamPos<$MediumPos);
        next if(not defined $CompSign{$LVer}{$Symbol}{"Param"}{$ParamPos});
        my $PTypeId = $CompSign{$LVer}{$Symbol}{"Param"}{$ParamPos}{"type"};
        if($TypeInfo{$LVer}{$PTypeId}{"Name"} eq $TypeName) {
            push(@Positions, $ParamPos);
        }
    }
    return @Positions;
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
    
    my %Type1_Pure = getPureType($Type1_Id, 1);
    my %Type2_Pure = getPureType($Type2_Id, 2);
    
    if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"})
    { # equal types
        return 0;
    }
    if($Type1_Pure{"Name"} eq "void")
    { # from void* to something
        return 0;
    }
    if($Type2_Pure{"Name"} eq "void")
    { # from something to void*
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
                        my $PL1 = getPLevel($MT1{"Tid"}, 1);
                        my $PL2 = getPLevel($MT2{"Tid"}, 2);
                        
                        if($PL1 ne $PL2)
                        { # different pointer level
                            return 1;
                        }
                        
                        # compare base types
                        my %BT1 = getBaseType($MT1{"Tid"}, 1);
                        my %BT2 = getBaseType($MT2{"Tid"}, 2);
                        
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
    
    my %Type1 = getType($Type1_Id, 1);
    my %Type2 = getType($Type2_Id, 2);
    
    if(not $Type1{"Name"} or not $Type2{"Name"}) {
        return ();
    }
    
    my %Type1_Pure = getPureType($Type1_Id, 1);
    my %Type2_Pure = getPureType($Type2_Id, 2);
    
    if(defined $In::Opt{"SkipTypedefUncover"})
    {
        if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"}) {
            return ();
        }
        
        if(cmpBTypes($Type1_Pure{"Name"}, $Type2_Pure{"Name"}, 1, 2)) {
            return ();
        }
    }
    
    my %Type1_Base = ($Type1_Pure{"Type"} eq "Array")?getOneStepBaseType($Type1_Pure{"Tid"}, 1):getBaseType($Type1_Id, 1);
    my %Type2_Base = ($Type2_Pure{"Type"} eq "Array")?getOneStepBaseType($Type2_Pure{"Tid"}, 2):getBaseType($Type2_Id, 2);
    
    if(not $Type1_Base{"Name"} or not $Type2_Base{"Name"}) {
        return ();
    }
    
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
    
    my $Type1_PLevel = getPLevel($Type1_Id, 1);
    my $Type2_PLevel = getPLevel($Type2_Id, 2);
    
    if($Type1_PLevel eq "" or $Type2_PLevel eq "") {
        return ();
    }
    
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
                    "Old_Size"=>$Type1_Base{"Size"}*$BYTE,
                    "New_Size"=>$Type2_Base{"Size"}*$BYTE);
            }
            else
            {
                if(diffTypes($Type1_Base{"Tid"}, $Type2_Base{"Tid"}, $Level))
                { # format change
                    %{$LocalProblems{$Prefix."_BaseType_Format"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "Old_Size"=>$Type1_Base{"Size"}*$BYTE,
                        "New_Size"=>$Type2_Base{"Size"}*$BYTE);
                }
                elsif(tNameLock($Type1_Base{"Tid"}, $Type2_Base{"Tid"}))
                {
                    %{$LocalProblems{$Prefix."_BaseType"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "Old_Size"=>$Type1_Base{"Size"}*$BYTE,
                        "New_Size"=>$Type2_Base{"Size"}*$BYTE);
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
                    "New_Size"=>$Type2{"Size"}*$BYTE);
            }
            elsif($Prefix eq "Return"
            and $Type2_Pure{"Name"} eq "void")
            {
                %{$LocalProblems{"Return_Type_Became_Void"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE);
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
                        "Old_Size"=>$Type1{"Size"}*$BYTE,
                        "New_Size"=>$Type2{"Size"}*$BYTE);
                }
                else
                {
                    if(diffTypes($Type1_Id, $Type2_Id, $Level))
                    { # format change
                        %{$LocalProblems{$Prefix."_Type_Format"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "Old_Size"=>$Type1{"Size"}*$BYTE,
                            "New_Size"=>$Type2{"Size"}*$BYTE);
                    }
                    elsif(tNameLock($Type1_Id, $Type2_Id))
                    { # FIXME: correct this condition
                        %{$LocalProblems{$Prefix."_Type"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "Old_Size"=>$Type1{"Size"}*$BYTE,
                            "New_Size"=>$Type2{"Size"}*$BYTE);
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
    
    my $TN1 = $TypeInfo{1}{$Tid1}{"Name"};
    my $TN2 = $TypeInfo{2}{$Tid2}{"Name"};
    
    my $TT1 = $TypeInfo{1}{$Tid1}{"Type"};
    my $TT2 = $TypeInfo{2}{$Tid2}{"Type"};
    
    if($In::ABI{1}{"GccVersion"} ne $In::ABI{2}{"GccVersion"})
    { # different formats
        my %Base1 = getType($Tid1, 1);
        while(defined $Base1{"Type"} and $Base1{"Type"} eq "Typedef") {
            %Base1 = getOneStepBaseType($Base1{"Tid"}, 1);
        }
        my %Base2 = getType($Tid2, 2);
        while(defined $Base2{"Type"} and $Base2{"Type"} eq "Typedef") {
            %Base2 = getOneStepBaseType($Base2{"Tid"}, 2);
        }
        my $BName1 = uncoverTypedefs($Base1{"Name"}, 1);
        my $BName2 = uncoverTypedefs($Base2{"Name"}, 2);
        
        if($BName1 eq $BName2)
        { # equal base types
            return 0;
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

sub showArch($)
{
    my $Arch = $_[0];
    if($Arch eq "arm"
    or $Arch eq "mips") {
        return uc($Arch);
    }
    return $Arch;
}

sub getReportTitle($)
{
    my $Level = $_[0];
    
    my $ArchInfo = " on <span style='color:Blue;'>".showArch($In::ABI{1}{"Arch"})."</span>";
    if($In::ABI{1}{"Arch"} ne $In::ABI{2}{"Arch"}
    or $Level eq "Source")
    { # don't show architecture in the header
        $ArchInfo = "";
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
    
    my $V1 = $In::Desc{1}{"Version"};
    my $V2 = $In::Desc{2}{"Version"};
    
    if($UsedDump{1}{"DWARF"} and $UsedDump{2}{"DWARF"})
    {
        my $M1 = $In::ABI{1}{"LibraryName"};
        my $M2 = $In::ABI{2}{"LibraryName"};
        
        my $M1S = $M1;
        my $M2S = $M2;
        
        $M1S=~s/(\.so|\.ko)\..+/$1/ig;
        $M2S=~s/(\.so|\.ko)\..+/$1/ig;
        
        if($M1S eq $M2S
        and $V1 ne "X" and $V2 ne "Y")
        {
            $Title .= " report for the <span style='color:Blue;'>$M1S</span> ".$In::Opt{"TargetComponent"};
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
        $Title .= " report for the <span style='color:Blue;'>".$In::Opt{"TargetTitle"}."</span> ".$In::Opt{"TargetComponent"};
        $Title .= " between <span style='color:Red;'>".$V1."</span> and <span style='color:Red;'>".$V2."</span> versions";
    }
    
    $Title .= $ArchInfo;
    
    if($In::Opt{"AppPath"}) {
        $Title .= " (relating to the portability of application <span style='color:Blue;'>".getFilename($In::Opt{"AppPath"})."</span>)";
    }
    $Title = "<h1>".$Title."</h1>\n";
    return $Title;
}

sub getCheckedHeaders($)
{
    my $LVer = $_[0];
    
    my @Headers = ();
    
    foreach my $Path (keys(%{$In::ABI{$LVer}{"Headers"}}))
    {
        my $Name = getFilename($Path);
        
        if(not isTargetHeader($Name, $LVer)) {
            next;
        }
        
        if(skipHeader($Name, $LVer)) {
            next;
        }
        
        push(@Headers, $Path);
    }
    
    return @Headers;
}

sub getSourceInfo()
{
    my ($CheckedHeaders, $CheckedSources, $CheckedLibs) = ("", "");
    
    if(my @Headers = getCheckedHeaders(1))
    {
        $CheckedHeaders = "<a name='Headers'></a>";
        if($In::Opt{"OldStyle"}) {
            $CheckedHeaders .= "<h2>Header Files (".($#Headers+1).")</h2>";
        }
        else {
            $CheckedHeaders .= "<h2>Header Files <span class='gray'>&nbsp;".($#Headers+1)."&nbsp;</span></h2>";
        }
        $CheckedHeaders .= "<hr/>\n";
        $CheckedHeaders .= "<div class='h_list'>\n";
        foreach my $Path (sort {lc($a) cmp lc($b)} @Headers) {
            $CheckedHeaders .= getFilename($Path)."<br/>\n";
        }
        $CheckedHeaders .= "</div>\n";
        $CheckedHeaders .= "<br/>$TOP_REF<br/>\n";
    }
    
    if(my @Sources = keys(%{$In::ABI{1}{"Sources"}}))
    {
        $CheckedSources = "<a name='Sources'></a>";
        if($In::Opt{"OldStyle"}) {
            $CheckedSources .= "<h2>Source Files (".($#Sources+1).")</h2>";
        }
        else {
            $CheckedSources .= "<h2>Source Files <span class='gray'>&nbsp;".($#Sources+1)."&nbsp;</span></h2>";
        }
        $CheckedSources .= "<hr/>\n";
        $CheckedSources .= "<div class='h_list'>\n";
        foreach my $Path (sort {lc($a) cmp lc($b)} @Sources) {
            $CheckedSources .= getFilename($Path)."<br/>\n";
        }
        $CheckedSources .= "</div>\n";
        $CheckedSources .= "<br/>$TOP_REF<br/>\n";
    }
    
    if(not $In::Opt{"CheckHeadersOnly"})
    {
        $CheckedLibs = "<a name='Libs'></a>";
        if($In::Opt{"OldStyle"}) {
            $CheckedLibs .= "<h2>".getObjTitle()." (".keys(%{$In::ABI{1}{"Symbols"}}).")</h2>";
        }
        else {
            $CheckedLibs .= "<h2>".getObjTitle()." <span class='gray'>&nbsp;".keys(%{$In::ABI{1}{"Symbols"}})."&nbsp;</span></h2>";
        }
        $CheckedLibs .= "<hr/>\n";
        $CheckedLibs .= "<div class='lib_list'>\n";
        foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$In::ABI{1}{"Symbols"}})) {
            $CheckedLibs .= $Library."<br/>\n";
        }
        $CheckedLibs .= "</div>\n";
        $CheckedLibs .= "<br/>$TOP_REF<br/>\n";
    }
    
    return $CheckedHeaders.$CheckedSources.$CheckedLibs;
}

sub getObjTitle()
{
    if(defined $UsedDump{1}{"DWARF"}) {
        return "Objects";
    }
    
    return "Libraries";
}

sub getTypeProblemsCount($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $Count = 0;
    
    foreach my $Type_Name (sort keys(%{$TypeChanges{$Level}}))
    {
        my %Kinds_Target = ();
        foreach my $Kind (keys(%{$TypeChanges{$Level}{$Type_Name}}))
        {
            if($CompatRules{$Level}{$Kind}{"Severity"} ne $TargetSeverity) {
                next;
            }
            
            foreach my $Loc (keys(%{$TypeChanges{$Level}{$Type_Name}{$Kind}}))
            {
                my $Target = $TypeChanges{$Level}{$Type_Name}{$Kind}{$Loc}{"Target"};
                
                if($Kinds_Target{$Kind}{$Target}) {
                    next;
                }
                
                $Kinds_Target{$Kind}{$Target} = 1;
                $Count += 1;
            }
        }
    }
    return $Count;
}

sub getSummary($)
{
    my $Level = $_[0];
    my ($Added, $Removed, $I_Problems_High, $I_Problems_Medium, $I_Problems_Low, $T_Problems_High,
    $C_Problems_Low, $T_Problems_Medium, $T_Problems_Low, $I_Other, $T_Other, $C_Other) = (0,0,0,0,0,0,0,0,0,0,0,0);
    %{$RESULT{$Level}} = (
        "Problems"=>0,
        "Warnings"=>0,
        "Affected"=>0);
    # check rules
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if(not defined $CompatRules{$Level}{$Kind})
            { # unknown rule
                if(not $UnknownRules{$Level}{$Kind})
                { # only one warning
                    printMsg("WARNING", "unknown rule \"$Kind\" (\"$Level\")");
                    $UnknownRules{$Level}{$Kind}=1;
                }
                delete($CompatProblems{$Level}{$Symbol}{$Kind});
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
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols")
            {
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                foreach my $Loc (sort keys(%{$CompatProblems{$Level}{$Symbol}{$Kind}}))
                {
                    if($Kind eq "Added_Symbol") {
                        $Added += 1;
                    }
                    elsif($Kind eq "Removed_Symbol")
                    {
                        $Removed += 1;
                        $TotalAffected{$Level}{$Symbol} = $Severity;
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
                        if(($Severity ne "Low" or $In::Opt{"StrictCompat"})
                        and $Severity ne "Safe") {
                            $TotalAffected{$Level}{$Symbol} = $Severity;
                        }
                    }
                }
            }
        }
    }
    
    my %MethodTypeIndex = ();
    
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
            {
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                if(($Severity ne "Low" or $In::Opt{"StrictCompat"})
                and $Severity ne "Safe")
                {
                    if(my $Sev = $TotalAffected{$Level}{$Symbol})
                    {
                        if($Severity_Val{$Severity}>$Severity_Val{$Sev}) {
                            $TotalAffected{$Level}{$Symbol} = $Severity;
                        }
                    }
                    else {
                        $TotalAffected{$Level}{$Symbol} = $Severity;
                    }
                }
                
                my $LSK = $CompatProblems{$Level}{$Symbol}{$Kind};
                my (@Locs1, @Locs2) = ();
                foreach my $Loc (sort keys(%{$LSK}))
                {
                    if(index($Loc, "retval")==0 or index($Loc, "this")==0) {
                        push(@Locs2, $Loc);
                    }
                    else {
                        push(@Locs1, $Loc);
                    }
                }
                
                foreach my $Loc (@Locs1, @Locs2)
                {
                    my $Type = $LSK->{$Loc}{"Type_Name"};
                    my $Target = $LSK->{$Loc}{"Target"};
                    
                    if(defined $MethodTypeIndex{$Symbol}{$Type}{$Kind}{$Target})
                    { # one location for one type and target
                        next;
                    }
                    $MethodTypeIndex{$Symbol}{$Type}{$Kind}{$Target} = 1;
                    
                    $TypeChanges{$Level}{$Type}{$Kind}{$Loc} = $LSK->{$Loc};
                    $TypeProblemsIndex{$Level}{$Type}{$Kind}{$Loc}{$Symbol} = 1;
                }
            }
        }
    }
    
    # clean memory
    %MethodTypeIndex = ();
    
    $T_Problems_High = getTypeProblemsCount("High", $Level);
    $T_Problems_Medium = getTypeProblemsCount("Medium", $Level);
    $T_Problems_Low = getTypeProblemsCount("Low", $Level);
    $T_Other = getTypeProblemsCount("Safe", $Level);
    
    # changed and removed public symbols
    my $SCount = keys(%{$CheckedSymbols{$Level}});
    if($In::Opt{"ExtendedCheck"})
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
    
    $RESULT{$Level}{"Affected"} = showNum($RESULT{$Level}{"Affected"});
    if($RESULT{$Level}{"Affected"}>=100) {
        $RESULT{$Level}{"Affected"} = 100;
    }
    
    $RESULT{$Level}{"Problems"} += $Removed;
    $RESULT{$Level}{"Problems"} += $T_Problems_High + $I_Problems_High;
    $RESULT{$Level}{"Problems"} += $T_Problems_Medium + $I_Problems_Medium;
    if($In::Opt{"StrictCompat"}) {
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
        if($In::Opt{"StrictCompat"}) {
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
    
    my ($Arch1, $Arch2) = ($In::ABI{1}{"Arch"}, $In::ABI{2}{"Arch"});
    my ($GccV1, $GccV2) = ($In::ABI{1}{"GccVersion"}, $In::ABI{2}{"GccVersion"});
    my ($ClangV1, $ClangV2) = ($In::ABI{1}{"ClangVersion"}, $In::ABI{2}{"ClangVersion"});
    
    my ($TestInfo, $TestResults, $Problem_Summary) = ();
    
    if($In::Opt{"ReportFormat"} eq "xml")
    { # XML
        # test info
        $TestInfo .= "  <library>".$In::Opt{"TargetLib"}."</library>\n";
        $TestInfo .= "  <version1>\n";
        $TestInfo .= "    <number>".$In::Desc{1}{"Version"}."</number>\n";
        $TestInfo .= "    <arch>$Arch1</arch>\n";
        if($GccV1) {
            $TestInfo .= "    <gcc>$GccV1</gcc>\n";
        }
        elsif($ClangV1) {
            $TestInfo .= "    <clang>$ClangV1</clang>\n";
        }
        $TestInfo .= "  </version1>\n";
        
        $TestInfo .= "  <version2>\n";
        $TestInfo .= "    <number>".$In::Desc{2}{"Version"}."</number>\n";
        $TestInfo .= "    <arch>$Arch2</arch>\n";
        if($GccV2) {
            $TestInfo .= "    <gcc>$GccV2</gcc>\n";
        }
        elsif($ClangV2) {
            $TestInfo .= "    <clang>$ClangV2</clang>\n";
        }
        $TestInfo .= "  </version2>\n";
        $TestInfo = "<test_info>\n".$TestInfo."</test_info>\n\n";
        
        # test results
        if(my @Headers = keys(%{$In::ABI{1}{"Headers"}}))
        {
            $TestResults .= "  <headers>\n";
            foreach my $Name (sort {lc($a) cmp lc($b)} @Headers) {
                $TestResults .= "    <name>".getFilename($Name)."</name>\n";
            }
            $TestResults .= "  </headers>\n";
        }
        
        if(my @Sources = keys(%{$In::ABI{1}{"Sources"}}))
        {
            $TestResults .= "  <sources>\n";
            foreach my $Name (sort {lc($a) cmp lc($b)} @Sources) {
                $TestResults .= "    <name>".getFilename($Name)."</name>\n";
            }
            $TestResults .= "  </sources>\n";
        }
        
        $TestResults .= "  <libs>\n";
        foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$In::ABI{1}{"Symbols"}}))
        {
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
        
        if($In::Opt{"TargetComponent"} eq "library") { 
            $TestInfo .= "<tr><th>Library Name</th><td>".$In::Opt{"TargetTitle"}."</td></tr>\n";
        }
        else {
            $TestInfo .= "<tr><th>Module Name</th><td>".$In::Opt{"TargetTitle"}."</td></tr>\n";
        }
        
        my (@VInf1, @VInf2, $AddTestInfo) = ();
        
        # CPU arch
        if($Arch1 eq $Arch2)
        { # go to the separate section
            $AddTestInfo .= "<tr><th>Arch</th><td>".showArch($Arch1)."</td></tr>\n";
        }
        else
        { # go to the version number
            push(@VInf1, showArch($Arch1));
            push(@VInf2, showArch($Arch2));
        }
        
        if($Level eq "Binary"
        and $In::Opt{"Target"} ne "windows")
        {
            if($GccV1 and $GccV2)
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
            elsif($ClangV1 and $ClangV2)
            { # Clang version
                if($ClangV1 eq $ClangV2)
                { # go to the separate section
                    $AddTestInfo .= "<tr><th>Clang Version</th><td>$ClangV1</td></tr>\n";
                }
                else
                { # go to the version number
                    push(@VInf1, "clang ".$ClangV1);
                    push(@VInf2, "clang ".$ClangV2);
                }
            }
            elsif($GccV1 and $ClangV2)
            {
                push(@VInf1, "gcc ".$GccV1);
                push(@VInf2, "clang ".$ClangV2);
            }
            elsif($ClangV1 and $GccV2)
            {
                push(@VInf1, "clang ".$ClangV1);
                push(@VInf2, "gcc ".$GccV2);
            }
        }
        # show long version names with GCC version and CPU architecture name (if different)
        $TestInfo .= "<tr><th>Version #1</th><td>".$In::Desc{1}{"Version"}.(@VInf1?" (".join(", ", reverse(@VInf1)).")":"")."</td></tr>\n";
        $TestInfo .= "<tr><th>Version #2</th><td>".$In::Desc{2}{"Version"}.(@VInf2?" (".join(", ", reverse(@VInf2)).")":"")."</td></tr>\n";
        $TestInfo .= $AddTestInfo;
        
        if($In::Opt{"ExtendedCheck"}) {
            $TestInfo .= "<tr><th>Mode</th><td>Extended</td></tr>\n";
        }
        if($In::Opt{"JoinReport"})
        {
            if($Level eq "Binary") {
                $TestInfo .= "<tr><th>Subject</th><td width='150px'>Binary Compatibility</td></tr>\n"; # Run-time
            }
            elsif($Level eq "Source") {
                $TestInfo .= "<tr><th>Subject</th><td width='150px'>Source Compatibility</td></tr>\n"; # Build-time
            }
        }
        $TestInfo .= "</table>\n";
        
        # test results
        $TestResults = "<h2>Test Results</h2><hr/>\n";
        $TestResults .= "<table class='summary'>";
        
        if(my @Headers = getCheckedHeaders(1))
        {
            my $Headers_Link = "<a href='#Headers' style='color:Blue;'>".($#Headers + 1)."</a>";
            $TestResults .= "<tr><th>Total Header Files</th><td>".$Headers_Link."</td></tr>\n";
        }
        
        if(my @Sources = keys(%{$In::ABI{1}{"Sources"}}))
        {
            my $Src_Link = "<a href='#Sources' style='color:Blue;'>".($#Sources + 1)."</a>";
            $TestResults .= "<tr><th>Total Source Files</th><td>".$Src_Link."</td></tr>\n";
        }
        
        if(not $In::Opt{"ExtendedCheck"})
        {
            my $Libs_Link = "0";
            $Libs_Link = "<a href='#Libs' style='color:Blue;'>".keys(%{$In::ABI{1}{"Symbols"}})."</a>" if(keys(%{$In::ABI{1}{"Symbols"}})>0);
            $TestResults .= "<tr><th>Total ".getObjTitle()."</th><td>".($In::Opt{"CheckHeadersOnly"}?"0&#160;(not&#160;analyzed)":$Libs_Link)."</td></tr>\n";
        }
        
        $TestResults .= "<tr><th>Total Symbols / Types</th><td>".(keys(%{$CheckedSymbols{$Level}}) - keys(%ExtendedSymbols))." / ".$TotalTypes."</td></tr>\n";
        
        my $META_DATA = "verdict:".$RESULT{$Level}{"Verdict"}.";";
        if($In::Opt{"JoinReport"}) {
            $META_DATA = "kind:".lc($Level).";".$META_DATA;
        }
        
        my $BC_Rate = showNum(100 - $RESULT{$Level}{"Affected"});
        
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
            if($In::Opt{"JoinReport"}) {
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
            if($In::Opt{"JoinReport"}) {
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
        $TH_Link = "<a href='#".getAnchor("Type", $Level, "High")."' style='color:Blue;'>$T_Problems_High</a>" if($T_Problems_High>0);
        $META_DATA .= "type_problems_high:$T_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Data Types</th>";
        $Problem_Summary .= "<td>High</td><td".getStyle("T", "High", $T_Problems_High).">$TH_Link</td></tr>\n";
        
        my $TM_Link = "0";
        $TM_Link = "<a href='#".getAnchor("Type", $Level, "Medium")."' style='color:Blue;'>$T_Problems_Medium</a>" if($T_Problems_Medium>0);
        $META_DATA .= "type_problems_medium:$T_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("T", "Medium", $T_Problems_Medium).">$TM_Link</td></tr>\n";
        
        my $TL_Link = "0";
        $TL_Link = "<a href='#".getAnchor("Type", $Level, "Low")."' style='color:Blue;'>$T_Problems_Low</a>" if($T_Problems_Low>0);
        $META_DATA .= "type_problems_low:$T_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td".getStyle("T", "Low", $T_Problems_Low).">$TL_Link</td></tr>\n";
        
        my $IH_Link = "0";
        $IH_Link = "<a href='#".getAnchor("Symbol", $Level, "High")."' style='color:Blue;'>$I_Problems_High</a>" if($I_Problems_High>0);
        $META_DATA .= "interface_problems_high:$I_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Symbols</th>";
        $Problem_Summary .= "<td>High</td><td".getStyle("I", "High", $I_Problems_High).">$IH_Link</td></tr>\n";
        
        my $IM_Link = "0";
        $IM_Link = "<a href='#".getAnchor("Symbol", $Level, "Medium")."' style='color:Blue;'>$I_Problems_Medium</a>" if($I_Problems_Medium>0);
        $META_DATA .= "interface_problems_medium:$I_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td".getStyle("I", "Medium", $I_Problems_Medium).">$IM_Link</td></tr>\n";
        
        my $IL_Link = "0";
        $IL_Link = "<a href='#".getAnchor("Symbol", $Level, "Low")."' style='color:Blue;'>$I_Problems_Low</a>" if($I_Problems_Low>0);
        $META_DATA .= "interface_problems_low:$I_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td".getStyle("I", "Low", $I_Problems_Low).">$IL_Link</td></tr>\n";
        
        my $ChangedConstants_Link = "0";
        if(keys(%{$CheckedSymbols{$Level}}) and $C_Problems_Low) {
            $ChangedConstants_Link = "<a href='#".getAnchor("Constant", $Level, "Low")."' style='color:Blue;'>$C_Problems_Low</a>";
        }
        $META_DATA .= "changed_constants:$C_Problems_Low;";
        $Problem_Summary .= "<tr><th>Problems with<br/>Constants</th><td>Low</td><td".getStyle("C", "Low", $C_Problems_Low).">$ChangedConstants_Link</td></tr>\n";
        
        # Safe Changes
        if($T_Other)
        {
            my $TS_Link = "<a href='#".getAnchor("Type", $Level, "Safe")."' style='color:Blue;'>$T_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Data Types</th><td>-</td><td".getStyle("T", "Safe", $T_Other).">$TS_Link</td></tr>\n";
            $META_DATA .= "type_changes_other:$T_Other;";
        }
        
        if($I_Other)
        {
            my $IS_Link = "<a href='#".getAnchor("Symbol", $Level, "Safe")."' style='color:Blue;'>$I_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Symbols</th><td>-</td><td".getStyle("I", "Safe", $I_Other).">$IS_Link</td></tr>\n";
            $META_DATA .= "interface_changes_other:$I_Other;";
        }
        
        if($C_Other)
        {
            my $CS_Link = "<a href='#".getAnchor("Constant", $Level, "Safe")."' style='color:Blue;'>$C_Other</a>";
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

sub getReportChangedConstants($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $CHANGED_CONSTANTS = "";
    
    my %ReportMap = ();
    foreach my $Constant (keys(%{$CompatProblems_Constants{$Level}}))
    {
        my $Header = $Constants{1}{$Constant}{"Header"};
        if(not $Header) {
            $Header = $Constants{1}{$Constant}{"Source"};
        }
        if(not $Header)
        { # added
            $Header = $Constants{2}{$Constant}{"Header"};
            if(not $Header) {
                $Header = $Constants{2}{$Constant}{"Source"}
            }
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
    
    if($In::Opt{"ReportFormat"} eq "xml")
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
            if($In::Opt{"OldStyle"}) {
                $CHANGED_CONSTANTS = "<h2>$Title ($ProblemsNum)</h2><hr/>\n".$CHANGED_CONSTANTS;
            }
            else {
                $CHANGED_CONSTANTS = "<h2>$Title <span".getStyle("C", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$CHANGED_CONSTANTS;
            }
            $CHANGED_CONSTANTS = "<a name='".getAnchor("Constant", $Level, $TargetSeverity)."'></a>\n".$CHANGED_CONSTANTS.$TOP_REF."<br/>\n";
        }
    }
    return $CHANGED_CONSTANTS;
}

sub getTitle($$$)
{
    my ($Header, $Library, $NameSpace) = @_;
    my $Title = "";
    
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

sub getReportAdded($)
{
    my $Level = $_[0];
    my $ADDED_INTERFACES = "";
    my %ReportMap = ();
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($Kind eq "Added_Symbol")
            {
                my $HeaderName = $CompSign{2}{$Symbol}{"Header"};
                if(not $HeaderName) {
                    $HeaderName = $CompSign{2}{$Symbol}{"Source"};
                }
                
                my $DyLib = $In::ABI{2}{"SymLib"}{$Symbol};
                if($Level eq "Source" and $In::Opt{"ReportFormat"} eq "html")
                { # do not show library name in the HTML report
                    $DyLib = "";
                }
                $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
            }
        }
    }
    if($In::Opt{"ReportFormat"} eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $ADDED_INTERFACES .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $ADDED_INTERFACES .= "    <library name=\"$DyLib\">\n";
                foreach my $Symbol (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $ADDED_INTERFACES .= "      <name>$Symbol</name>\n";
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
                foreach my $Symbol (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $NameSpaceSymbols{selectSymbolNs($Symbol, 2)}{$Symbol} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $ADDED_INTERFACES .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc($CompSign{2}{$a}{"Unmangled"}) cmp lc($CompSign{2}{$b}{"Unmangled"})} sort {lc($a) cmp lc($b)} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        $Added_Number += 1;
                        my $Signature = highLight_ItalicColor($Symbol, 2);
                        if($NameSpace) {
                            $Signature = cutNs($Signature, $NameSpace);
                        }
                        
                        if($Symbol=~/\A(_Z|\?)/) {
                            $ADDED_INTERFACES .= insertIDs($ContentSpanStart.$Signature.$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mngl'>$Symbol</span>\n<br/>\n<br/>\n".$ContentDivEnd."\n");
                        }
                        else {
                            $ADDED_INTERFACES .= "<span class=\"iname\">".$Signature."</span><br/>\n";
                        }
                    }
                    $ADDED_INTERFACES .= "<br/>\n";
                }
            }
        }
        if($ADDED_INTERFACES)
        {
            my $Anchor = "<a name='Added'></a>";
            if($In::Opt{"JoinReport"}) {
                $Anchor = "<a name='".$Level."_Added'></a>";
            }
            if($In::Opt{"OldStyle"}) {
                $ADDED_INTERFACES = "<h2>Added Symbols ($Added_Number)</h2><hr/>\n".$ADDED_INTERFACES;
            }
            else {
                $ADDED_INTERFACES = "<h2>Added Symbols <span".getStyle("I", "Added", $Added_Number).">&nbsp;$Added_Number&nbsp;</span></h2><hr/>\n".$ADDED_INTERFACES;
            }
            $ADDED_INTERFACES = $Anchor.$ADDED_INTERFACES.$TOP_REF."<br/>\n";
        }
    }
    return $ADDED_INTERFACES;
}

sub getReportRemoved($)
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
                my $HeaderName = $CompSign{1}{$Symbol}{"Header"};
                if(not $HeaderName) {
                    $HeaderName = $CompSign{1}{$Symbol}{"Source"};
                }
                
                my $DyLib = $In::ABI{1}{"SymLib"}{$Symbol};
                if($Level eq "Source" and $In::Opt{"ReportFormat"} eq "html")
                { # do not show library name in HTML report
                    $DyLib = "";
                }
                $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
            }
        }
    }
    if($In::Opt{"ReportFormat"} eq "xml")
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
                    $NameSpaceSymbols{selectSymbolNs($Interface, 1)}{$Interface} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $REMOVED_INTERFACES .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc($CompSign{1}{$a}{"Unmangled"}) cmp lc($CompSign{1}{$b}{"Unmangled"})} sort {lc($a) cmp lc($b)} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        $Removed_Number += 1;
                        my $Signature = highLight_ItalicColor($Symbol, 1);
                        if($NameSpace) {
                            $Signature = cutNs($Signature, $NameSpace);
                        }
                        if($Symbol=~/\A(_Z|\?)/) {
                            $REMOVED_INTERFACES .= insertIDs($ContentSpanStart.$Signature.$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mngl'>$Symbol</span>\n<br/>\n<br/>\n".$ContentDivEnd."\n");
                        }
                        else {
                            $REMOVED_INTERFACES .= "<span class=\"iname\">".$Signature."</span><br/>\n";
                        }
                    }
                }
                $REMOVED_INTERFACES .= "<br/>\n";
            }
        }
        if($REMOVED_INTERFACES)
        {
            my $Anchor = "<a name='Removed'></a><a name='Withdrawn'></a>";
            if($In::Opt{"JoinReport"}) {
                $Anchor = "<a name='".$Level."_Removed'></a><a name='".$Level."_Withdrawn'></a>";
            }
            if($In::Opt{"OldStyle"}) {
                $REMOVED_INTERFACES = "<h2>Removed Symbols ($Removed_Number)</h2><hr/>\n".$REMOVED_INTERFACES;
            }
            else {
                $REMOVED_INTERFACES = "<h2>Removed Symbols <span".getStyle("I", "Removed", $Removed_Number).">&nbsp;$Removed_Number&nbsp;</span></h2><hr/>\n".$REMOVED_INTERFACES;
            }
            
            $REMOVED_INTERFACES = $Anchor.$REMOVED_INTERFACES.$TOP_REF."<br/>\n";
        }
    }
    return $REMOVED_INTERFACES;
}

sub getXmlParams($$)
{
    my ($Content, $Problem) = @_;
    
    my %XMLparams = ();
    foreach my $Attr (sort {$b cmp $a} keys(%{$Problem}))
    {
        my $Macro = "\@".lc($Attr);
        if($Content=~/\Q$Macro\E/)
        {
            my $Value = $Problem->{$Attr};
            
            if($Attr eq "Param_Pos") {
                $Value = showPos($Value);
            }
            
            $XMLparams{lc($Attr)} = $Value;
        }
    }
    my @PString = ();
    foreach my $P (sort {$b cmp $a} keys(%XMLparams)) {
        push(@PString, $P."=\"".xmlSpecChars($XMLparams{$P})."\"");
    }
    if(@PString) {
        return " ".join(" ", @PString);
    }
    return "";
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
        $Content=~s!(NOTE):!<br/><br/><b>$1</b>:!g;
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
    $Content=~s!\*\*([\w\-]+?)\*\*!<b>$1</b>!ig;
    $Content=~s!\*([\w\-]+?)\*!<i>$1</i>!ig;
    
    return $Content;
}

sub applyMacroses($$$$)
{
    my ($Level, $Kind, $Content, $Problem) = @_;
    
    $Problem->{"Word_Size"} = $In::ABI{2}{"WordSize"};
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
        
        if($Attr eq "Param_Pos") {
            $Value = showPos($Value);
        }
        
        if($Value=~/\s/) {
            $Value = "<span class='value'>".specChars($Value)."</span>";
        }
        elsif($Value=~/\A\d+\Z/
        and ($Attr eq "Old_Size" or $Attr eq "New_Size"))
        { # bits to bytes
            if($Value % $BYTE)
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
                $Value /= $BYTE;
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
            my $Fmt = "Class|Name|Qual|HTML|Desc";
            if($Kind!~/Overridden/) {
                $Fmt = "Name|Qual|HTML|Desc";
            }
            
            my $V1 = (defined $CompSign{1}{$Value} and defined $CompSign{1}{$Value}{"ShortName"});
            my $V2 = (defined $CompSign{2}{$Value} and defined $CompSign{2}{$Value}{"ShortName"});
            
            if($Kind!~/Symbol_Became|Symbol_Changed|Method_Became/
            and ($V1 or $V2))
            { # symbols
                if($V1) {
                    $Value = blackName(getSignature($Value, 1, $Fmt));
                }
                else {
                    $Value = blackName(getSignature($Value, 2, $Fmt));
                }
            }
            else
            {
                $Value = "<b>".specChars($Value)."</b>";
            }
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

sub getReportSymbolProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $INTERFACE_PROBLEMS = "";
    my (%ReportMap, %SymbolChanges) = ();
    
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        my ($SN, $SS, $SV) = symbolParts($Symbol);
        if($SV and defined $CompatProblems{$Level}{$SN}) {
            next;
        }
        
        if(not defined $CompSign{1}{$Symbol})
        { # added symbols
            next;
        }
        
        my $HeaderName = $CompSign{1}{$Symbol}{"Header"};
        if(not $HeaderName) {
            $HeaderName = $CompSign{1}{$Symbol}{"Source"};
        }
        
        my $DyLib = $In::ABI{1}{"SymLib"}{$Symbol};
        if(not $DyLib and my $VSym = $In::ABI{1}{"SymbolVersion"}{$Symbol})
        { # Symbol with Version
            $DyLib = $In::ABI{1}{"SymLib"}{$VSym};
        }
        if(not $DyLib)
        { # const global data
            $DyLib = "";
        }
        if($Level eq "Source" and $In::Opt{"ReportFormat"} eq "html")
        { # do not show library name in HTML report
            $DyLib = "";
        }
        
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols"
            and $Kind ne "Added_Symbol" and $Kind ne "Removed_Symbol")
            {
                my $Severity = $CompatRules{$Level}{$Kind}{"Severity"};
                if($Severity eq $TargetSeverity)
                {
                    $SymbolChanges{$Symbol}{$Kind} = $CompatProblems{$Level}{$Symbol}{$Kind};
                    $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
                }
            }
        }
    }
    
    if($In::Opt{"ReportFormat"} eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $INTERFACE_PROBLEMS .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $INTERFACE_PROBLEMS .= "    <library name=\"$DyLib\">\n";
                
                my @SortedInterfaces = sort {lc($CompSign{1}{$a}{"Unmangled"}) cmp lc($CompSign{1}{$b}{"Unmangled"})} sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}{$DyLib}});
                foreach my $Symbol (@SortedInterfaces)
                {
                    $INTERFACE_PROBLEMS .= "      <symbol name=\"$Symbol\">\n";
                    foreach my $Kind (sort keys(%{$SymbolChanges{$Symbol}}))
                    {
                        foreach my $Loc (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                        {
                            my $ProblemAttr = $SymbolChanges{$Symbol}{$Kind}{$Loc};
                            
                            $INTERFACE_PROBLEMS .= "        <problem id=\"$Kind\">\n";
                            my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                            $INTERFACE_PROBLEMS .= "          <change".getXmlParams($Change, $ProblemAttr).">$Change</change>\n";
                            my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                            $INTERFACE_PROBLEMS .= "          <effect".getXmlParams($Effect, $ProblemAttr).">$Effect</effect>\n";
                            if(my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"}) {
                                $INTERFACE_PROBLEMS .= "          <overcome".getXmlParams($Overcome, $ProblemAttr).">$Overcome</overcome>\n";
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
                    $NameSpaceSymbols{selectSymbolNs($Symbol, 1)}{$Symbol} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $INTERFACE_PROBLEMS .= getTitle($HeaderName, $DyLib, $NameSpace);
                    
                    my @SortedInterfaces = sort {lc($CompSign{1}{$a}{"Unmangled"}) cmp lc($CompSign{1}{$b}{"Unmangled"})} sort {lc($a) cmp lc($b)} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        my $SYMBOL_REPORT = "";
                        my $ProblemNum = 1;
                        foreach my $Kind (sort keys(%{$SymbolChanges{$Symbol}}))
                        {
                            foreach my $Loc (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                            {
                                my $ProblemAttr = $SymbolChanges{$Symbol}{$Kind}{$Loc};
                                
                                if(my $NSign = $ProblemAttr->{"New_Signature"}) {
                                    $NewSignature{$Symbol} = $NSign;
                                }
                                
                                if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, $ProblemAttr))
                                {
                                    my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, $ProblemAttr);
                                    $SYMBOL_REPORT .= "<tr>\n<th>$ProblemNum</th>\n<td>".$Change."</td>\n<td>".$Effect."</td>\n</tr>\n";
                                    $ProblemNum += 1;
                                    $ProblemsNum += 1;
                                }
                            }
                        }
                        $ProblemNum -= 1;
                        if($SYMBOL_REPORT)
                        {
                            my $ShowSymbol = highLight_ItalicColor($Symbol, 1);
                            
                            if($NameSpace)
                            {
                                $SYMBOL_REPORT = cutNs($SYMBOL_REPORT, $NameSpace);
                                $ShowSymbol = cutNs($ShowSymbol, $NameSpace);
                            }
                            
                            $INTERFACE_PROBLEMS .= $ContentSpanStart."<span class='ext'>[+]</span> ".$ShowSymbol;
                            if($In::Opt{"OldStyle"}) {
                                $INTERFACE_PROBLEMS .= " ($ProblemNum)";
                            }
                            else {
                                $INTERFACE_PROBLEMS .= " <span".getStyle("I", $TargetSeverity, $ProblemNum).">&nbsp;$ProblemNum&nbsp;</span>";
                            }
                            $INTERFACE_PROBLEMS .= $ContentSpanEnd."<br/>\n";
                            $INTERFACE_PROBLEMS .= $ContentDivStart."\n";
                            
                            if(my $NSign = $NewSignature{$Symbol})
                            { # argument list changed to
                                $NSign = highLight_ItalicColor($NSign, 2);
                                if($NameSpace) {
                                    $NSign = cutNs($NSign, $NameSpace);
                                }
                                $INTERFACE_PROBLEMS .= "\n<span class='new_sign_lbl'>&#8675;</span>\n<br/>\n<span class='new_sign'>".$NSign."</span><br/>\n";
                            }
                            
                            if($Symbol=~/\A(_Z|\?)/) {
                                $INTERFACE_PROBLEMS .= "<span class='mngl pleft'>$Symbol</span><br/>\n";
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
            if($In::Opt{"OldStyle"}) {
                $INTERFACE_PROBLEMS = "<h2>$Title ($ProblemsNum)</h2><hr/>\n".$INTERFACE_PROBLEMS;
            }
            else {
                $INTERFACE_PROBLEMS = "<h2>$Title <span".getStyle("I", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$INTERFACE_PROBLEMS;
            }
            $INTERFACE_PROBLEMS = "<a name=\'".getAnchor("Symbol", $Level, $TargetSeverity)."\'></a><a name=\'".getAnchor("Interface", $Level, $TargetSeverity)."\'></a>\n".$INTERFACE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $INTERFACE_PROBLEMS;
}

sub cutNs($$)
{
    my ($N, $Ns) = @_;
    $N=~s/\b\Q$Ns\E:://g;
    return $N;
}

sub getReportTypeProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my $TYPE_PROBLEMS = "";
    
    my %ReportMap = ();
    my %TypeChanges_Sev = ();
    
    foreach my $TypeName (keys(%{$TypeChanges{$Level}}))
    {
        my $Tid = $TName_Tid{1}{$TypeName};
        my $HeaderName = $TypeInfo{1}{$Tid}{"Header"};
        if(not $HeaderName) {
            $HeaderName = $TypeInfo{1}{$Tid}{"Source"};
        }
        
        foreach my $Kind (keys(%{$TypeChanges{$Level}{$TypeName}}))
        {
            if($CompatRules{$Level}{$Kind}{"Severity"} ne $TargetSeverity) {
                next;
            }
            
            foreach my $Loc (keys(%{$TypeChanges{$Level}{$TypeName}{$Kind}}))
            {
                $ReportMap{$HeaderName}{$TypeName} = 1;
                $TypeChanges_Sev{$TypeName}{$Kind}{$Loc} = $TypeChanges{$Level}{$TypeName}{$Kind}{$Loc};
            }
        }
    }
    
    if($In::Opt{"ReportFormat"} eq "xml")
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
                    foreach my $Loc (sort {cmpLocations($b, $a)} sort keys(%{$TypeChanges_Sev{$TypeName}{$Kind}}))
                    {
                        $Kinds_Locations{$Kind}{$Loc} = 1;
                        
                        my $Target = $TypeChanges_Sev{$TypeName}{$Kind}{$Loc}{"Target"};
                        if($Kinds_Target{$Kind}{$Target}) {
                            next;
                        }
                        $Kinds_Target{$Kind}{$Target} = 1;
                        
                        my $ProblemAttr = $TypeChanges_Sev{$TypeName}{$Kind}{$Loc};
                        $TYPE_PROBLEMS .= "      <problem id=\"$Kind\">\n";
                        my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                        $TYPE_PROBLEMS .= "        <change".getXmlParams($Change, $ProblemAttr).">$Change</change>\n";
                        my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                        $TYPE_PROBLEMS .= "        <effect".getXmlParams($Effect, $ProblemAttr).">$Effect</effect>\n";
                        if(my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"}) {
                            $TYPE_PROBLEMS .= "        <overcome".getXmlParams($Overcome, $ProblemAttr).">$Overcome</overcome>\n";
                        }
                        $TYPE_PROBLEMS .= "      </problem>\n";
                    }
                }
                $TYPE_PROBLEMS .= getAffectedSymbols($Level, $TypeName, \%Kinds_Locations);
                if($Level eq "Binary" and grep {$_=~/Virtual|Base_Class/} keys(%Kinds_Locations)) {
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
                $NameSpace_Type{selectTypeNs($TypeName, 1)}{$TypeName} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Type))
            {
                $TYPE_PROBLEMS .= getTitle($HeaderName, "", $NameSpace);
                my @SortedTypes = sort {lc(showType($a, 0, 1)) cmp lc(showType($b, 0, 1))} keys(%{$NameSpace_Type{$NameSpace}});
                foreach my $TypeName (@SortedTypes)
                {
                    my $ProblemNum = 1;
                    my $TYPE_REPORT = "";
                    my (%Kinds_Locations, %Kinds_Target) = ();
                    
                    foreach my $Kind (sort {(index($b, "Size")!=-1) cmp (index($a, "Size")!=-1)} sort keys(%{$TypeChanges_Sev{$TypeName}}))
                    {
                        foreach my $Loc (sort {cmpLocations($b, $a)} sort keys(%{$TypeChanges_Sev{$TypeName}{$Kind}}))
                        {
                            $Kinds_Locations{$Kind}{$Loc} = 1;
                            
                            my $Target = $TypeChanges_Sev{$TypeName}{$Kind}{$Loc}{"Target"};
                            if($Kinds_Target{$Kind}{$Target}) {
                                next;
                            }
                            $Kinds_Target{$Kind}{$Target} = 1;
                            
                            my $ProblemAttr = $TypeChanges_Sev{$TypeName}{$Kind}{$Loc};
                            if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, $ProblemAttr))
                            {
                                my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, $ProblemAttr);
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
                        
                        my $ShowType = showType($TypeName, 1, 1);
                        
                        if($NameSpace)
                        {
                            $TYPE_REPORT = cutNs($TYPE_REPORT, $NameSpace);
                            $ShowType = cutNs($ShowType, $NameSpace);
                            $Affected = cutNs($Affected, $NameSpace);
                            $ShowVTables = cutNs($ShowVTables, $NameSpace);
                        }
                        
                        $TYPE_PROBLEMS .= $ContentSpanStart."<span class='ext'>[+]</span> ".$ShowType;
                        if($In::Opt{"OldStyle"}) {
                            $TYPE_PROBLEMS .= " ($ProblemNum)";
                        }
                        else {
                            $TYPE_PROBLEMS .= " <span".getStyle("T", $TargetSeverity, $ProblemNum).">&nbsp;$ProblemNum&nbsp;</span>";
                        }
                        $TYPE_PROBLEMS .= $ContentSpanEnd;
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
            if($In::Opt{"OldStyle"}) {
                $TYPE_PROBLEMS = "<h2>$Title ($ProblemsNum)</h2><hr/>\n".$TYPE_PROBLEMS;
            }
            else {
                $TYPE_PROBLEMS = "<h2>$Title <span".getStyle("T", $TargetSeverity, $ProblemsNum).">&nbsp;$ProblemsNum&nbsp;</span></h2><hr/>\n".$TYPE_PROBLEMS;
            }
            $TYPE_PROBLEMS = "<a name=\'".getAnchor("Type", $Level, $TargetSeverity)."\'></a>\n".$TYPE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $TYPE_PROBLEMS;
}

sub showType($$$)
{
    my ($Name, $Html, $LVer) = @_;
    my $TType = $TypeInfo{$LVer}{$TName_Tid{$LVer}{$Name}}{"Type"};
    $TType = lc($TType);
    if($TType=~/struct|union|enum/) {
        $Name=~s/\A\Q$TType\E //g;
    }
    if($Html) {
        $Name = "<span class='ttype'>".$TType."</span> ".specChars($Name);
    }
    else {
        $Name = $TType." ".$Name;
    }
    return $Name;
}

sub getAnchor($$$)
{
    my ($Kind, $Level, $Severity) = @_;
    if($In::Opt{"JoinReport"})
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
    my %Type1 = getType($TypeId1, 1);
    if(defined $Type1{"VTable"}
    and keys(%{$Type1{"VTable"}}))
    {
        my $TypeId2 = $TName_Tid{2}{$TypeName};
        my %Type2 = getType($TypeId2, 2);
        if(defined $Type2{"VTable"}
        and keys(%{$Type2{"VTable"}}))
        {
            my %Indexes = map {$_=>1} (keys(%{$Type1{"VTable"}}), keys(%{$Type2{"VTable"}}));
            my %Entries = ();
            foreach my $Index (sort {$a<=>$b} (keys(%Indexes)))
            {
                $Entries{$Index}{"E1"} = simpleVEntry($Type1{"VTable"}{$Index});
                $Entries{$Index}{"E2"} = simpleVEntry($Type2{"VTable"}{$Index});
            }
            my $VTABLES = "";
            if($In::Opt{"ReportFormat"} eq "xml")
            { # XML
                $VTABLES .= "      <vtable>\n";
                foreach my $Index (sort {$a<=>$b} (keys(%Entries)))
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
                foreach my $Index (sort {$a<=>$b} (keys(%Entries)))
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
                    $VTABLES .= "<td$Color1>".specChars($Entries{$Index}{"E1"})."</td>\n";
                    $VTABLES .= "<td$Color2>".specChars($Entries{$Index}{"E2"})."</td></tr>\n";
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
    my ($Pos, $Symbol, $LVer) = @_;
    if(defined $CompSign{$LVer}{$Symbol})
    {
        if(not $CompSign{$LVer}{$Symbol}{"Static"}
        and $CompSign{$LVer}{$Symbol}{"Class"})
        {
            return $Pos-1;
        }
        
        return $Pos;
    }
    
    return undef;
}

sub getParamPos($$$)
{
    my ($Name, $Symbol, $LVer) = @_;
    
    if(defined $CompSign{$LVer}{$Symbol}
    and defined $CompSign{$LVer}{$Symbol}{"Param"})
    {
        my $Info = $CompSign{$LVer}{$Symbol};
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
    if(defined $In::Opt{"AffectLimit"}) {
        $LIMIT = $In::Opt{"AffectLimit"};
    }
    
    my %SymSel = ();
    
    foreach my $Kind (sort keys(%{$Kinds_Locations}))
    {
        my @Locs = sort {(index($a, "retval")!=-1) cmp (index($b, "retval")!=-1)} sort {length($a)<=>length($b)} sort keys(%{$Kinds_Locations->{$Kind}});
        
        foreach my $Loc (@Locs)
        {
            foreach my $Symbol (keys(%{$TypeProblemsIndex{$Level}{$Target_TypeName}{$Kind}{$Loc}}))
            {
                if(index($Symbol, "_Z")==0
                and $Symbol=~/(C4|C2|D4|D2|D0)[EI]/)
                { # duplicated problems for C2/C4 constructors, D2/D4 and D0 destructors
                    next;
                }
                
                if(index($Symbol, "\@")!=-1
                or index($Symbol, "\$")!=-1)
                {
                    my ($SN, $SS, $SV) = symbolParts($Symbol);
                    
                    if($Level eq "Source")
                    { # remove symbol version
                        $Symbol = $SN;
                    }
                    
                    if($SV and defined $CompatProblems{$Level}{$SN})
                    { # duplicated problems for versioned symbols
                        next;
                    }
                }
                
                if(not defined $SymSel{$Symbol})
                {
                    $SymSel{$Symbol}{"Kind"} = $Kind;
                    $SymSel{$Symbol}{"Loc"} = $Loc;
                }
            }
        }
    }
    
    my $Affected = "";
    my $SNum = 0;
    
    if($In::Opt{"ReportFormat"} eq "xml")
    { # XML
        $Affected .= "      <affected>\n";
        
        foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%SymSel))
        {
            my $Kind = $SymSel{$Symbol}{"Kind"};
            my $Loc = $SymSel{$Symbol}{"Loc"};
            
            my $PName = getParamName($Loc);
            my $Des = getAffectDesc($Level, $Symbol, $Kind, $Loc);
            
            my $Target = "";
            if($PName)
            {
                $Target .= " param=\"$PName\"";
                $Des=~s/parameter $PName /parameter \@param /;
            }
            elsif($Loc=~/\Aretval(\-|\Z)/i) {
                $Target .= " affected=\"retval\"";
            }
            elsif($Loc=~/\Athis(\-|\Z)/i) {
                $Target .= " affected=\"this\"";
            }
            
            if($Des=~s/\AField ([^\s]+) /Field \@field /) {
                $Target .= " field=\"$1\"";
            }
            
            $Affected .= "        <symbol name=\"$Symbol\"$Target>\n";
            $Affected .= "          <comment>".xmlSpecChars($Des)."</comment>\n";
            $Affected .= "        </symbol>\n";

            if(++$SNum>=$LIMIT) {
                last;
            }
        }
        $Affected .= "      </affected>\n";
    }
    else
    { # HTML
        foreach my $Symbol (sort {lc($a) cmp lc($b)} keys(%SymSel))
        {
            my $Kind = $SymSel{$Symbol}{"Kind"};
            my $Loc = $SymSel{$Symbol}{"Loc"};
            
            my $Des = getAffectDesc($Level, $Symbol, $Kind, $Loc);
            my $PName = getParamName($Loc);
            my $Pos = adjustParamPos(getParamPos($PName, $Symbol, 1), $Symbol, 1);
            
            $Affected .= "<span class='iname_a'>".getSignature($Symbol, 1, "Class|Name|Param|HTML|Italic|Target=".$Pos)."</span><br/>\n";
            $Affected .= "<div class='affect'>".specChars($Des)."</div>\n";
            
            if(++$SNum>=$LIMIT) {
                last;
            }
        }
        
        my $Total = keys(%SymSel);
        
        if($Total>$LIMIT) {
            $Affected .= " <b>...</b>\n<br/>\n"; # and others ...
        }
        
        $Affected = "<div class='affected'>".$Affected."</div>\n";
        if($Affected)
        {
            
            my $Per = showNum($Total*100/keys(%{$CheckedSymbols{$Level}}));
            $Affected = $ContentDivStart.$Affected.$ContentDivEnd;
            $Affected = $ContentSpanStart_Affected."[+] affected symbols: $Total ($Per\%)".$ContentSpanEnd.$Affected;
        }
    }
    
    return $Affected;
}

sub cmpLocations($$)
{
    my ($L1, $L2) = @_;
    if((index($L2, "retval")==0 or index($L2, "this")==0)
    and (index($L1, "retval")!=0 and index($L1, "this")!=0))
    {
        if(index($L1, "->")==-1) {
            return 1;
        }
        elsif(index($L2, "->")!=-1) {
            return 1;
        }
    }
    return 0;
}

sub getAffectDesc($$$$)
{
    my ($Level, $Symbol, $Kind, $Loc) = @_;
    
    my $PAttr = $CompatProblems{$Level}{$Symbol}{$Kind}{$Loc};
    
    $Loc=~s/\A(.*)\-\>(.+?)\Z/$1/; # without the latest affected field
    
    my @Sentence = ();
    
    if($Kind eq "Overridden_Virtual_Method"
    or $Kind eq "Overridden_Virtual_Method_B") {
        push(@Sentence, "The method '".$PAttr->{"New_Value"}."' will be called instead of this method.");
    }
    elsif($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
    {
        my %SymInfo = %{$CompSign{1}{$Symbol}};
        
        if($Loc eq "this" or $Kind=~/(\A|_)Virtual(_|\Z)/)
        {
            my $MType = "method";
            if($SymInfo{"Constructor"}) {
                $MType = "constructor";
            }
            elsif($SymInfo{"Destructor"}) {
                $MType = "destructor";
            }
            
            my $ClassName = $TypeInfo{1}{$SymInfo{"Class"}}{"Name"};
            
            if($ClassName eq $PAttr->{"Type_Name"}) {
                push(@Sentence, "This $MType is from \'".$PAttr->{"Type_Name"}."\' class.");
            }
            else {
                push(@Sentence, "This $MType is from derived class \'".$ClassName."\'.");
            }
        }
        else
        {
            my $TypeID = undef;
            
            if($Loc=~/retval/)
            { # return value
                if(index($Loc, "->")!=-1) {
                    push(@Sentence, "Field \'".$Loc."\' in the return value");
                }
                else {
                    push(@Sentence, "Return value");
                }
                
                $TypeID = $SymInfo{"Return"};
            }
            elsif($Loc=~/this/)
            { # "this" pointer
                if(index($Loc, "->")!=-1) {
                    push(@Sentence, "Field \'".$Loc."\' in the object of this method");
                }
                else {
                    push(@Sentence, "\'this\' pointer");
                }
                
                $TypeID = $SymInfo{"Class"};
            }
            else
            { # parameters
                my $PName = getParamName($Loc);
                my $PPos = getParamPos($PName, $Symbol, 1);
            
                if(index($Loc, "->")!=-1) {
                    push(@Sentence, "Field \'".$Loc."\' in ".showPos(adjustParamPos($PPos, $Symbol, 1))." parameter");
                }
                else {
                    push(@Sentence, showPos(adjustParamPos($PPos, $Symbol, 1))." parameter");
                }
                if($PName) {
                    push(@Sentence, "\'".$PName."\'");
                }
                
                $TypeID = $SymInfo{"Param"}{$PPos}{"type"};
            }
            
            if($Loc!~/this/)
            {
                if(my %PureType = getPureType($TypeID, 1))
                {
                    if($PureType{"Type"} eq "Pointer") {
                        push(@Sentence, "(pointer)");
                    }
                    elsif($PureType{"Type"} eq "Ref") {
                        push(@Sentence, "(reference)");
                    }
                }
            }
            
            if($Loc eq "this") {
                push(@Sentence, "has base type \'".$PAttr->{"Type_Name"}."\'.");
            }
            else
            {
                my $Loc_T = $Loc;
                $Loc_T=~s/\A\w+(\->|\Z)//; # location in type
                
                my $TypeID_Problem = $TypeID;
                if($Loc_T) {
                    $TypeID_Problem = getFieldType($Loc_T, $TypeID, 1);
                }
                
                if($TypeInfo{1}{$TypeID_Problem}{"Name"} eq $PAttr->{"Type_Name"}) {
                    push(@Sentence, "is of type \'".$PAttr->{"Type_Name"}."\'.");
                }
                else {
                    push(@Sentence, "has base type \'".$PAttr->{"Type_Name"}."\'.");
                }
            }
        }
    }
    if($ExtendedSymbols{$Symbol}) {
        push(@Sentence, " This is a symbol from an external library that may use subject library and change the ABI after recompiling.");
    }
    
    my $Sent = join(" ", @Sentence);
    
    $Sent=~s/->/./g;
    
    if($In::Opt{"ReportFormat"} eq "xml") {
        $Sent=~s/'//g;
    }
    
    return $Sent;
}

sub getFieldType($$$)
{
    my ($Loc, $TypeId, $LVer) = @_;
    
    my @Fields = split(/\->/, $Loc);
    
    foreach my $Name (@Fields)
    {
        my %Info = getBaseType($TypeId, $LVer);
        
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

sub writeReport($$)
{
    my ($Level, $Report) = @_;
    if($In::Opt{"ReportFormat"} eq "xml") {
        $Report = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n".$Report;
    }
    if($In::Opt{"StdOut"})
    { # --stdout option
        print STDOUT $Report;
    }
    else
    {
        my $RPath = getReportPath($Level);
        mkpath(getDirname($RPath));
        
        open(REPORT, ">", $RPath) || die ("can't open file \'$RPath\': $!\n");
        print REPORT $Report;
        close(REPORT);
    }
}

sub getReport($)
{
    my $Level = $_[0];
    if($In::Opt{"ReportFormat"} eq "xml")
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
            my ($Summary, $MetaData) = getSummary($Level);
            $Report .= $Summary."\n";
            $Report .= getReportProblems_All($Level);
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
            my $Title = $In::Opt{"TargetTitle"}.": ".$In::Desc{1}{"Version"}." to ".$In::Desc{2}{"Version"}." compatibility report";
            my $Keywords = $In::Opt{"TargetTitle"}.", compatibility, API, ABI, report";
            my $Des = "API/ABI compatibility report for the ".$In::Opt{"TargetTitle"}." ".$In::Opt{"TargetComponent"}." between ".$In::Desc{1}{"Version"}." and ".$In::Desc{2}{"Version"}." versions";
            my ($BSummary, $BMetaData) = getSummary("Binary");
            my ($SSummary, $SMetaData) = getSummary("Source");
            my $Report = "<!-\- $BMetaData -\->\n<!-\- $SMetaData -\->\n".composeHTML_Head($Title, $Keywords, $Des, $CssStyles, $JScripts)."<body><a name='Source'></a><a name='Binary'></a><a name='Top'></a>";
            $Report .= getReportTitle("Join")."
            <br/>
            <div class='tabset'>
            <a id='BinaryID' href='#BinaryTab' class='tab active'>Binary<br/>Compatibility</a>
            <a id='SourceID' href='#SourceTab' style='margin-left:3px' class='tab disabled'>Source<br/>Compatibility</a>
            </div>";
            $Report .= "<div id='BinaryTab' class='tab'>\n$BSummary\n".getReportProblems_All("Binary").getSourceInfo()."<br/><br/><br/></div>";
            $Report .= "<div id='SourceTab' class='tab'>\n$SSummary\n".getReportProblems_All("Source").getSourceInfo()."<br/><br/><br/></div>";
            $Report .= getReportFooter();
            $Report .= "\n</body></html>\n";
            return $Report;
        }
        else
        {
            my ($Summary, $MetaData) = getSummary($Level);
            my $Title = $In::Opt{"TargetTitle"}.": ".$In::Desc{1}{"Version"}." to ".$In::Desc{2}{"Version"}." ".lc($Level)." compatibility report";
            my $Keywords = $In::Opt{"TargetTitle"}.", ".lc($Level)." compatibility, API, report";
            my $Des = "$Level compatibility report for the ".$In::Opt{"TargetTitle"}." ".$In::Opt{"TargetComponent"}." between ".$In::Desc{1}{"Version"}." and ".$In::Desc{2}{"Version"}." versions";
            if($Level eq "Binary")
            {
                if($In::ABI{1}{"Arch"} eq $In::ABI{2}{"Arch"}) {
                    $Des .= " on ".showArch($In::ABI{1}{"Arch"});
                }
            }
            my $Report = "<!-\- $MetaData -\->\n".composeHTML_Head($Title, $Keywords, $Des, $CssStyles, $JScripts)."\n<body>\n<div><a name='Top'></a>\n";
            $Report .= getReportTitle($Level)."\n".$Summary."\n";
            $Report .= getReportProblems_All($Level);
            $Report .= getSourceInfo();
            $Report .= "</div>\n<br/><br/><br/>\n";
            $Report .= getReportFooter();
            $Report .= "\n</body></html>\n";
            return $Report;
        }
    }
}

sub getReportProblems_All($)
{
    my $Level = $_[0];
    
    my $Report = getReportAdded($Level).getReportRemoved($Level);
    $Report .= getReportProblems("High", $Level);
    $Report .= getReportProblems("Medium", $Level);
    $Report .= getReportProblems("Low", $Level);
    $Report .= getReportProblems("Safe", $Level);
    
    # clean memory
    delete($TypeProblemsIndex{$Level});
    delete($TypeChanges{$Level});
    delete($CompatProblems{$Level});
    
    return $Report;
}

sub createReport()
{
    if($In::Opt{"JoinReport"}) {
        writeReport("Join", getReport("Join"));
    }
    elsif($In::Opt{"DoubleReport"})
    { # default
        writeReport("Binary", getReport("Binary"));
        writeReport("Source", getReport("Source"));
    }
    elsif($In::Opt{"BinOnly"})
    { # --binary
        writeReport("Binary", getReport("Binary"));
    }
    elsif($In::Opt{"SrcOnly"})
    { # --source
        writeReport("Source", getReport("Source"));
    }
}

sub getReportFooter()
{
    my $Footer = "";
    
    $Footer .= "<hr/>\n";
    $Footer .= "<div class='footer' align='right'>";
    $Footer .= "<i>Generated by <a href='".$HomePage{"Dev"}."'>ABI Compliance Checker</a> $TOOL_VERSION &#160;</i>\n";
    $Footer .= "</div>\n";
    $Footer .= "<br/>\n";
    
    return $Footer;
}

sub getReportProblems($$)
{
    my ($Severity, $Level) = @_;
    
    my $Report = getReportTypeProblems($Severity, $Level);
    if(my $SProblems = getReportSymbolProblems($Severity, $Level)) {
        $Report .= $SProblems;
    }
    
    if($Severity eq "Low" or $Severity eq "Safe") {
        $Report .= getReportChangedConstants($Severity, $Level);
    }
    
    if($In::Opt{"ReportFormat"} eq "html")
    {
        if($Report)
        { # add anchor
            if($In::Opt{"JoinReport"})
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
    my ($Title, $Keywords, $Des, $Styles, $Scripts) = @_;
    
    my $Head = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n";
    $Head .= "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n";
    $Head .= "<head>\n";
    $Head .= "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
    $Head .= "<meta name=\"keywords\" content=\"$Keywords\" />\n";
    $Head .= "<meta name=\"description\" content=\"$Des\" />\n";
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

sub uncoverConstant($$)
{
    my ($LVer, $Constant) = @_;
    
    if(isCyclical(\@RecurConstant, $Constant)) {
        return $Constant;
    }
    
    if(defined $Cache{"uncoverConstant"}{$LVer}{$Constant}) {
        return $Cache{"uncoverConstant"}{$LVer}{$Constant};
    }
    
    if(defined $Constants{$LVer}{$Constant})
    {
        my $Value = $Constants{$LVer}{$Constant}{"Value"};
        if(defined $Constants{$LVer}{$Value})
        {
            push(@RecurConstant, $Constant);
            my $Uncovered = uncoverConstant($LVer, $Value);
            if($Uncovered ne "") {
                $Value = $Uncovered;
            }
            pop(@RecurConstant);
        }
        
        # FIXME: uncover $Value using all the enum constants
        # USE CASE: change of define NC_LONG from NC_INT (enum value) to NC_INT (define)
        return ($Cache{"uncoverConstant"}{$LVer}{$Constant} = $Value);
    }
    return ($Cache{"uncoverConstant"}{$LVer}{$Constant} = "");
}

sub simpleConstant($$)
{
    my ($LVer, $Value) = @_;
    if($Value=~/\W/)
    {
        my $Value_Copy = $Value;
        while($Value_Copy=~s/([a-z_]\w+)/\@/i)
        {
            my $Word = $1;
            if($Value!~/$Word\s*\(/)
            {
                my $Val = uncoverConstant($LVer, $Word);
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

my $IgnoreConstant = join("|",
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
        if($Name=~/(\A|_)($IgnoreConstant)(_|\Z)/)
        { # version
            return 1;
        }
        if($Name=~/(\A|[a-z])(Release|Version)([A-Z]|\Z)/)
        { # version
            return 1;
        }
        my $LShort = $In::Opt{"TargetLibShort"};
        if($Name=~/(\A|_)(lib|open|)$LShort(_|)(VERSION|VER|DATE|API|PREFIX)(_|\Z)/i)
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
    foreach my $Constant (sort keys(%{$Constants{1}}))
    {
        if($In::Desc{1}{"SkipConstants"}{$Constant})
        { # skipped by the user
            next;
        }
        
        if(my $Header = $Constants{1}{$Constant}{"Header"})
        {
            if(not isTargetHeader($Header, 1)
            and not isTargetHeader($Header, 2)) {
                next;
            }
        }
        elsif(my $Source = $Constants{1}{$Constant}{"Source"})
        {
            if(not isTargetSource($Source, 1)
            and not isTargetSource($Source, 2)) {
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
            if(not defined $In::Opt{"SkipRemovedConstants"})
            {
                %{$CompatProblems_Constants{$Level}{$Constant}{"Removed_Constant"}} = (
                    "Target"=>$Constant,
                    "Old_Value"=>$Old_Value  );
            }
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
    
    if(defined $In::Opt{"SkipAddedConstants"}) {
        return;
    }
    
    foreach my $Constant (keys(%{$Constants{2}}))
    {
        if(not defined $Constants{1}{$Constant}{"Value"})
        {
            if($In::Desc{2}{"SkipConstants"}{$Constant})
            { # skipped by the user
                next;
            }
            
            if(my $Header = $Constants{2}{$Constant}{"Header"})
            {
                if(not isTargetHeader($Header, 1)
                and not isTargetHeader($Header, 2))
                { # user-defined header
                    next;
                }
            }
            elsif(my $Source = $Constants{2}{$Constant}{"Source"})
            {
                if(not isTargetSource($Source, 1)
                and not isTargetSource($Source, 2))
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

sub getSymbolSize($$)
{ # size from the shared library
    my ($Symbol, $LVer) = @_;
    
    if(defined $In::ABI{$LVer}{"SymLib"}{$Symbol}
    and my $LibName = $In::ABI{$LVer}{"SymLib"}{$Symbol})
    {
        if(defined $In::ABI{$LVer}{"Symbols"}{$LibName}{$Symbol}
        and my $Size = $In::ABI{$LVer}{"Symbols"}{$LibName}{$Symbol})
        {
            if($Size<0) {
                return -$Size;
            }
        }
    }
    return 0;
}

sub createSymbolsList($$$$$)
{
    my ($DPath, $SaveTo, $LName, $LVersion, $ArchName) = @_;
    
    $In::ABI{1} = readABIDump(1, $DPath);
    initAliases(1);
    
    prepareSymbols(1);
    
    my %SymbolHeaderLib = ();
    my $Total = 0;
    
    # Get List
    foreach my $Symbol (sort keys(%{$CompSign{1}}))
    {
        if(not linkSymbol($Symbol, 1, "-Deps"))
        { # skip src only and all external functions
            next;
        }
        if(not symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Public", "Binary", 1))
        { # skip other symbols
            next;
        }
        my $HeaderName = $CompSign{1}{$Symbol}{"Header"};
        if(not $HeaderName)
        { # skip src only and all external functions
            next;
        }
        my $DyLib = $In::ABI{1}{"SymLib"}{$Symbol};
        if(not $DyLib)
        { # skip src only and all external functions
            next;
        }
        $SymbolHeaderLib{$HeaderName}{$DyLib}{$Symbol} = 1;
        $Total += 1;
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
                $NS_Symbol{selectSymbolNs($Symbol, 1)}{$Symbol} = 1;
            }
            foreach my $NameSpace (sort keys(%NS_Symbol))
            {
                $SYMBOLS_LIST .= getTitle($HeaderName, $DyLib, $NameSpace);
                my @SortedInterfaces = sort {lc($CompSign{1}{$a}{"Unmangled"}) cmp lc($CompSign{1}{$b}{"Unmangled"})} sort {lc($a) cmp lc($b)} keys(%{$NS_Symbol{$NameSpace}});
                foreach my $Symbol (@SortedInterfaces)
                {
                    my $SubReport = "";
                    my $Signature = highLight_ItalicColor($Symbol, 1);
                    if($NameSpace) {
                        $Signature = cutNs($Signature, $NameSpace);
                    }
                    if($Symbol=~/\A(_Z|\?)/) {
                        $SubReport = insertIDs($ContentSpanStart.$Signature.$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mngl'>$Symbol</span><br/><br/>".$ContentDivEnd."\n");
                    }
                    else {
                        $SubReport = "<span class='iname'>".$Signature."</span><br/>\n";
                    }
                    $SYMBOLS_LIST .= $SubReport;
                }
            }
            $SYMBOLS_LIST .= "<br/>\n";
        }
    }
    # clear info
    (%CompSign, %ClassMethods, %AllocableClass, %ClassNames, %In::ABI) = ();
    
    ($Content_Counter, $ContentID) = (0, 0);
    
    my $CssStyles = readModule("Styles", "SymbolsList.css");
    my $JScripts = readModule("Scripts", "Sections.js");
    $SYMBOLS_LIST = "<a name='Top'></a>".$SYMBOLS_LIST.$TOP_REF."<br/>\n";
    my $Title = "$LName: public symbols";
    my $Keywords = "$LName, API, symbols";
    my $Des = "List of symbols in $LName ($LVersion) on ".showArch($ArchName);
    $SYMBOLS_LIST = composeHTML_Head($Title, $Keywords, $Des, $CssStyles, $JScripts)."
    <body><div>\n$SYMBOLS_LIST</div>
    <br/><br/>\n".getReportFooter()."
    </body></html>";
    writeFile($SaveTo, $SYMBOLS_LIST);
}

sub dumpSorting($)
{
    my $Hash = $_[0];
    if(not $Hash) {
        return [];
    }
    
    my @Keys = keys(%{$Hash});
    if($#Keys<0) {
        return [];
    }
    
    if($Keys[0]=~/\A\d+\Z/)
    { # numbers
        return [sort {$a<=>$b} @Keys];
    }
    else
    { # strings
        return [sort {$a cmp $b} @Keys];
    }
}

sub exitReport()
{ # the tool has run without any errors
    printReport();
    if($In::Opt{"CompileError"})
    { # errors in headers may add false positives/negatives
        exit(getErrorCode("Compile_Error"));
    }
    if($In::Opt{"BinOnly"} and $RESULT{"Binary"}{"Problems"})
    { # --binary
        exit(getErrorCode("Incompatible"));
    }
    elsif($In::Opt{"SrcOnly"}
    and $RESULT{"Source"}{"Problems"})
    { # --source
        exit(getErrorCode("Incompatible"));
    }
    elsif($RESULT{"Source"}{"Problems"}
    or $RESULT{"Binary"}{"Problems"})
    { # default
        exit(getErrorCode("Incompatible"));
    }
    else {
        exit(getErrorCode("Compatible"));
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
    my $Dir = "compat_reports/".$In::Opt{"TargetLib"}."/".$In::Desc{1}{"Version"}."_to_".$In::Desc{2}{"Version"};
    if($Level eq "Binary")
    {
        if($In::Opt{"BinReportPath"})
        { # --bin-report-path
            return $In::Opt{"BinReportPath"};
        }
        elsif($In::Opt{"OutputReportPath"})
        { # --report-path
            return $In::Opt{"OutputReportPath"};
        }
        else
        { # default
            return $Dir."/abi_compat_report.".$In::Opt{"ReportFormat"};
        }
    }
    elsif($Level eq "Source")
    {
        if($In::Opt{"SrcReportPath"})
        { # --src-report-path
            return $In::Opt{"SrcReportPath"};
        }
        elsif($In::Opt{"OutputReportPath"})
        { # --report-path
            return $In::Opt{"OutputReportPath"};
        }
        else
        { # default
            return $Dir."/src_compat_report.".$In::Opt{"ReportFormat"};
        }
    }
    else
    {
        if($In::Opt{"OutputReportPath"})
        { # --report-path
            return $In::Opt{"OutputReportPath"};
        }
        else
        { # default
            return $Dir."/compat_report.".$In::Opt{"ReportFormat"};
        }
    }
}

sub printStatMsg($)
{
    my $Level = $_[0];
    printMsg("INFO", "Total \"$Level\" compatibility problems: ".$RESULT{$Level}{"Problems"}.", warnings: ".$RESULT{$Level}{"Warnings"});
}

sub listAffected($)
{
    my $Level = $_[0];
    my $List = "";
    foreach (keys(%{$TotalAffected{$Level}}))
    {
        if($In::Opt{"StrictCompat"} and $TotalAffected{$Level}{$_} eq "Low")
        { # skip "Low"-severity problems
            next;
        }
        $List .= "$_\n";
    }
    my $Dir = getDirname(getReportPath($Level));
    if($Level eq "Binary") {
        writeFile($Dir."/abi_affected.txt", $List);
    }
    elsif($Level eq "Source") {
        writeFile($Dir."/src_affected.txt", $List);
    }
}

sub printReport()
{
    printMsg("INFO", "Creating compatibility report ...");
    
    createReport();
    
    if($In::Opt{"JoinReport"} or $In::Opt{"DoubleReport"})
    {
        if($RESULT{"Binary"}{"Problems"}
        or $RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "Result: INCOMPATIBLE (Binary: ".$RESULT{"Binary"}{"Affected"}."\%, Source: ".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "Result: COMPATIBLE");
        }
        printStatMsg("Binary");
        printStatMsg("Source");
        if($In::Opt{"ListAffected"})
        { # --list-affected
            listAffected("Binary");
            listAffected("Source");
        }
    }
    elsif($In::Opt{"BinOnly"})
    {
        if($RESULT{"Binary"}{"Problems"}) {
            printMsg("INFO", "Result: INCOMPATIBLE (".$RESULT{"Binary"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "Result: COMPATIBLE");
        }
        printStatMsg("Binary");
        if($In::Opt{"ListAffected"})
        { # --list-affected
            listAffected("Binary");
        }
    }
    elsif($In::Opt{"SrcOnly"})
    {
        if($RESULT{"Source"}{"Problems"}) {
            printMsg("INFO", "Result: INCOMPATIBLE (".$RESULT{"Source"}{"Affected"}."\%)");
        }
        else {
            printMsg("INFO", "Result: COMPATIBLE");
        }
        printStatMsg("Source");
        if($In::Opt{"ListAffected"})
        { # --list-affected
            listAffected("Source");
        }
    }
    if($In::Opt{"StdOut"})
    {
        if($In::Opt{"JoinReport"} or not $In::Opt{"DoubleReport"})
        { # --binary or --source
            printMsg("INFO", "Compatibility report has been generated to stdout");
        }
        else
        { # default
            printMsg("INFO", "Compatibility reports have been generated to stdout");
        }
    }
    else
    {
        if($In::Opt{"JoinReport"}) {
            printMsg("INFO", "See detailed report:\n  ".pathFmt(getReportPath("Join")));
        }
        elsif($In::Opt{"DoubleReport"})
        { # default
            printMsg("INFO", "See detailed reports:\n  ".pathFmt(getReportPath("Binary"))."\n  ".pathFmt(getReportPath("Source")));
        }
        elsif($In::Opt{"BinOnly"})
        { # --binary
            printMsg("INFO", "See detailed report:\n  ".pathFmt(getReportPath("Binary")));
        }
        elsif($In::Opt{"SrcOnly"})
        { # --source
            printMsg("INFO", "See detailed report:\n  ".pathFmt(getReportPath("Source")));
        }
    }
}

sub defaultDumpPath($$)
{
    my ($N, $V) = @_;
    return "abi_dumps/".$N."/".$V."/ABI.dump";
}

sub createABIFile($$)
{
    my ($LVer, $DescPath) = @_;
    
    if(not -e $DescPath) {
        exitStatus("Access_Error", "can't access \'$DescPath\'");
    }
    
    detectDefaultPaths(undef, undef, "bin", undef);
    
    if(isDump($DescPath))
    {
        $In::ABI{$LVer} = readABIDump($LVer, $DescPath);
        initAliases($LVer);
        
        if(my $V = $In::Desc{$LVer}{"TargetVersion"}) {
            $In::Desc{$LVer}{"Version"} = $V;
        }
        else {
            $In::Desc{$LVer}{"Version"} = $In::ABI{$LVer}{"LibraryVersion"};
        }
    }
    else
    {
        loadModule("ABIDump");
        readDesc(createDesc($DescPath, $LVer), $LVer);
        
        initLogging($LVer);
        
        if($In::Opt{"Debug"})
        {
            if(not $In::Opt{"ExtraInfo"}) {
                $In::Opt{"ExtraInfo"} = getExtraDir($LVer);
            }
        }
        
        detectDefaultPaths("inc", "lib", undef, "gcc");
        createABIDump($LVer);
    }
    
    clearSysFilesCache($LVer);
    
    printMsg("INFO", "Creating library ABI dump ...");
    
    $In::ABI{$LVer}{"ABI_DUMP_VERSION"} = $ABI_DUMP_VERSION;
    $In::ABI{$LVer}{"ABI_COMPLIANCE_CHECKER_VERSION"} = $TOOL_VERSION;
    
    if($In::Opt{"UseXML"}) {
        $In::ABI{$LVer}{"XML_ABI_DUMP_VERSION"} = $XML_ABI_DUMP_VERSION;
    }
    
    $In::ABI{$LVer}{"TargetHeaders"} = $In::Desc{$LVer}{"TargetHeader"};
    
    foreach ("SymLib", "DepSymLib", "TName_Tid", "TypeTypedef",
    "TypedefBase", "Class_SubClasses", "ClassVTable") {
        delete($In::ABI{$LVer}{$_});
    }
    
    my $DumpPath = defaultDumpPath($In::Opt{"TargetLib"}, $In::Desc{1}{"Version"});
    if($In::Opt{"OutputDumpPath"})
    { # user defined path
        $DumpPath = $In::Opt{"OutputDumpPath"};
    }
    
    my $ArExt = $In::Opt{"Ar"};
    my $Archive = ($DumpPath=~s/\Q.$ArExt\E\Z//g);
    
    if($Archive and not $In::Opt{"StdOut"})
    { # check archive utilities
        if($In::Opt{"OS"} eq "windows")
        { # using zip
            my $ZipCmd = getCmdPath("zip");
            if(not $ZipCmd) {
                exitStatus("Not_Found", "can't find \"zip\"");
            }
        }
        else
        { # using tar and gzip
            my $TarCmd = getCmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\"");
            }
            my $GzipCmd = getCmdPath("gzip");
            if(not $GzipCmd) {
                exitStatus("Not_Found", "can't find \"gzip\"");
            }
        }
    }
    
    my $ABI_DUMP = "";
    if($In::Opt{"UseXML"})
    {
        loadModule("XmlDump");
        $ABI_DUMP = createXmlDump($LVer);
    }
    else
    { # default
        $ABI_DUMP = Dumper($In::ABI{$LVer});
    }
    if($In::Opt{"StdOut"})
    {
        print STDOUT $ABI_DUMP;
        printMsg("INFO", "ABI dump has been generated to stdout");
        return;
    }
    else
    { # to file
        my ($DDir, $DName) = sepPath($DumpPath);
        my $DPath = $In::Opt{"Tmp"}."/".$DName;
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
        
        printMsg("INFO", "Dump path: ".pathFmt($DumpPath));
    }
}

sub readABIDump($$)
{
    my ($LVer, $Path) = @_;
    
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
    
    my $ABIRef = {};
    
    my $Line = readLineNum($FilePath, 0);
    if($Line=~/xml/)
    { # XML format
        loadModule("XmlDump");
        $ABIRef = readXmlDump($FilePath);
    }
    else
    { # Perl Data::Dumper format (default)
        open(DUMP, $FilePath);
        local $/ = undef;
        my $Content = <DUMP>;
        close(DUMP);
        
        if(getDirname($FilePath) eq $In::Opt{"Tmp"}."/unpack")
        { # remove temp file
            unlink($FilePath);
        }
        if($Content!~/};\s*\Z/) {
            exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
        }
        $ABIRef = eval($Content);
        if(not $ABIRef) {
            exitStatus("Error", "internal error - eval() procedure seem to not working correctly, try to remove 'use strict' and try again");
        }
    }
    
    my $ABIVer = $ABIRef->{"ABI_DUMP_VERSION"};
    
    if($ABIVer)
    {
        if(cmpVersions($ABIVer, $ABI_DUMP_VERSION)>0)
        { # future formats
            exitStatus("Dump_Version", "the versions of the ABI dump is newer than version of the tool");
        }
    }
    
    if(cmpVersions($ABIVer, $ABI_DUMP_VERSION_MIN)<0) {
        exitStatus("Dump_Version", "the version of the ABI dump is too old and unsupported anymore, please regenerate it");
    }
    
    if(defined $ABIRef->{"ABI_DUMPER_VERSION"})
    { # DWARF ABI Dump
        $UseConv_Real{$LVer}{"P"} = 1;
        $UseConv_Real{$LVer}{"R"} = 0; # not implemented yet
        
        $UsedDump{$LVer}{"DWARF"} = 1;
        
        if($ABIRef->{"LibraryName"}=~/\.ko(\.|\Z)/) {
            $In::Opt{"TargetComponent"} = "module";
        }
        else {
            $In::Opt{"TargetComponent"} = "object";
        }
    }
    
    if(index($ABIRef->{"LibraryName"}, "libstdc++")==0
    or index($ABIRef->{"LibraryName"}, "libc++")==0) {
        $In::Opt{"StdcxxTesting"} = 1;
    }
    
    if($ABIRef->{"BinOnly"})
    { # ABI dump created with --binary option
        $UsedDump{$LVer}{"BinOnly"} = 1;
    }
    else
    { # default
        $UsedDump{$LVer}{"SrcBin"} = 1;
    }
    
    if(defined $ABIRef->{"Mode"}
    and $ABIRef->{"Mode"} eq "Extended")
    { # --ext option
        $In::Opt{"ExtendedCheck"} = 1;
    }
    
    if($ABIRef->{"Extra"}) {
        $In::Opt{"ExtraDump"} = 1;
    }
    
    if(not keys(%{$ABIRef->{"SymbolInfo"}}))
    { # validation of old-version dumps
        if(not $In::Opt{"ExtendedCheck"}) {
            exitStatus("Invalid_Dump", "no symbols info in the ABI dump");
        }
    }
    
    if(defined $ABIRef->{"GccConstants"})
    { # support for 3.0
        foreach my $Name (keys(%{$ABIRef->{"GccConstants"}})) {
            $ABIRef->{"Constants"}{$Name}{"Value"} = $ABIRef->{"GccConstants"}{$Name};
        }
    }
    elsif(defined $ABIRef->{"CompilerConstants"})
    {
        foreach my $Name (keys(%{$ABIRef->{"CompilerConstants"}})) {
            $ABIRef->{"Constants"}{$Name}{"Value"} = $ABIRef->{"CompilerConstants"}{$Name};
        }
    }
    
    if(not $ABIRef->{"SymbolVersion"}) {
        $ABIRef->{"SymbolVersion"} = $ABIRef->{"SymVer"};
    }
    
    if(defined $ABIRef->{"TargetHeaders"}) {
        $In::Desc{$LVer}{"TargetHeader"} = $ABIRef->{"TargetHeaders"};
    }
    
    foreach my $LName (keys(%{$ABIRef->{"Symbols"}}))
    {
        foreach my $Symbol (keys(%{$ABIRef->{"Symbols"}{$LName}})) {
            $ABIRef->{"SymLib"}{$Symbol} = $LName;
        }
    }
    
    foreach my $LName (keys(%{$ABIRef->{"DepSymbols"}}))
    {
        foreach my $Symbol (keys(%{$ABIRef->{"DepSymbols"}{$LName}})) {
            $ABIRef->{"DepSymLib"}{$Symbol} = $LName;
        }
    }
    
    $In::Opt{"Target"} = $ABIRef->{"Target"};
    $In::Desc{$LVer}{"Dump"} = 1;
    
    return $ABIRef;
}

sub prepareCompare($)
{
    my $LVer = $_[0];
    
    foreach my $Lib_Name (keys(%{$In::ABI{$LVer}{"Symbols"}}))
    {
        foreach my $Symbol (keys(%{$In::ABI{$LVer}{"Symbols"}{$Lib_Name}}))
        {
            if($In::ABI{$LVer}{"Symbols"}{$Lib_Name}{$Symbol}<0)
            { # data marked as -size in the dump
                $GlobalDataObject{$LVer}{$Symbol} = -$In::ABI{$LVer}{"Symbols"}{$Lib_Name}{$Symbol};
                
                if($Symbol=~/\A(.+?)\@.+/) {
                    $GlobalDataObject{$LVer}{$1} = $GlobalDataObject{$LVer}{$Symbol};
                }
            }
        }
    }
    
    foreach my $TypeId (sort {$a<=>$b} keys(%{$TypeInfo{$LVer}}))
    { # NOTE: order is important
        if(not defined $TypeInfo{$LVer}{$TypeId}{"Tid"}) {
            $TypeInfo{$LVer}{$TypeId}{"Tid"} = $TypeId;
        }
        
        my $TInfo = $TypeInfo{$LVer}{$TypeId};
        if(defined $TInfo->{"Base"})
        {
            foreach my $SubId (keys(%{$TInfo->{"Base"}}))
            {
                if($SubId eq $TypeId)
                { # Fix erroneus ABI dump
                    delete($TypeInfo{$LVer}{$TypeId}{"Base"}{$SubId});
                    next;
                }
                
                $In::ABI{$LVer}{"Class_SubClasses"}{$SubId}{$TypeId} = 1;
            }
        }
        
        if($TInfo->{"BaseType"} eq $TypeId)
        { # fix ABI dump
            delete($TypeInfo{$LVer}{$TypeId}{"BaseType"});
        }
        
        if($TInfo->{"Type"} eq "Typedef" and not $TInfo->{"Artificial"})
        {
            if(my $BTid = $TInfo->{"BaseType"})
            {
                my $BName = $TypeInfo{$LVer}{$BTid}{"Name"};
                if(not $BName)
                { # broken type
                    next;
                }
                if($TInfo->{"Name"} eq $BName)
                { # typedef to "class Class"
                  # should not be registered in TName_Tid
                    next;
                }
                if(not $In::ABI{$LVer}{"TypedefBase"}{$TInfo->{"Name"}}) {
                    $In::ABI{$LVer}{"TypedefBase"}{$TInfo->{"Name"}} = $BName;
                }
            }
        }
        if(not $TName_Tid{$LVer}{$TInfo->{"Name"}})
        { # classes: class (id1), typedef (artificial, id2 > id1)
            $TName_Tid{$LVer}{$TInfo->{"Name"}} = $TypeId;
        }
    }
}

sub compareABIDumps($$)
{
    my ($V1, $V2) = @_;
    my $DumpPath1 = defaultDumpPath($In::Opt{"TargetLib"}, $V1);
    my $DumpPath2 = defaultDumpPath($In::Opt{"TargetLib"}, $V2);
    
    unlink($DumpPath1);
    unlink($DumpPath2);
    
    my $pid = fork();
    if($pid)
    { # dump on two CPU cores
        my @PARAMS = ("-dump", $In::Desc{1}{"Path"}, "-l", $In::Opt{"TargetLib"});
        if($In::Desc{1}{"RelativeDirectory"}) {
            @PARAMS = (@PARAMS, "-relpath", $In::Desc{1}{"RelativeDirectory"});
        }
        if($In::Desc{1}{"OutputLogPath"}) {
            @PARAMS = (@PARAMS, "-log-path", $In::Desc{1}{"OutputLogPath"});
        }
        if($In::Opt{"CrossGcc"}) {
            @PARAMS = (@PARAMS, "-cross-gcc", $In::Opt{"CrossGcc"});
        }
        if($In::Opt{"Quiet"})
        {
            @PARAMS = (@PARAMS, "-quiet");
            @PARAMS = (@PARAMS, "-logging-mode", "a");
        }
        elsif($In::Opt{"LogMode"} and $In::Opt{"LogMode"} ne "w")
        { # "w" is default
            @PARAMS = (@PARAMS, "-logging-mode", $In::Opt{"LogMode"});
        }
        if($In::Opt{"ExtendedCheck"}) {
            @PARAMS = (@PARAMS, "-extended");
        }
        if($In::Opt{"UserLang"}) {
            @PARAMS = (@PARAMS, "-lang", $In::Opt{"UserLang"});
        }
        if($In::Desc{1}{"TargetVersion"}) {
            @PARAMS = (@PARAMS, "-vnum", $In::Desc{1}{"TargetVersion"});
        }
        if($In::Opt{"BinOnly"}) {
            @PARAMS = (@PARAMS, "-binary");
        }
        if($In::Opt{"SrcOnly"}) {
            @PARAMS = (@PARAMS, "-source");
        }
        if($In::Opt{"SortDump"}) {
            @PARAMS = (@PARAMS, "-sort");
        }
        if($In::Opt{"DumpFormat"} and $In::Opt{"DumpFormat"} ne "perl") {
            @PARAMS = (@PARAMS, "-dump-format", $In::Opt{"DumpFormat"});
        }
        if($In::Opt{"CheckHeadersOnly"}) {
            @PARAMS = (@PARAMS, "-headers-only");
        }
        if($In::Opt{"CxxIncompat"}) {
            @PARAMS = (@PARAMS, "-cxx-incompatible");
        }
        if($In::Opt{"Debug"})
        {
            @PARAMS = (@PARAMS, "-debug");
            printMsg("INFO", "Executing perl $0 @PARAMS");
        }
        system("perl", $0, @PARAMS);
        if(not -f $DumpPath1) {
            exit(1);
        }
    }
    else
    { # child
        my @PARAMS = ("-dump", $In::Desc{2}{"Path"}, "-l", $In::Opt{"TargetLib"});
        if($In::Desc{2}{"RelativeDirectory"}) {
            @PARAMS = (@PARAMS, "-relpath", $In::Desc{2}{"RelativeDirectory"});
        }
        if($In::Desc{2}{"OutputLogPath"}) {
            @PARAMS = (@PARAMS, "-log-path", $In::Desc{2}{"OutputLogPath"});
        }
        if($In::Opt{"CrossGcc"}) {
            @PARAMS = (@PARAMS, "-cross-gcc", $In::Opt{"CrossGcc"});
        }
        if($In::Opt{"Quiet"})
        {
            @PARAMS = (@PARAMS, "-quiet");
            @PARAMS = (@PARAMS, "-logging-mode", "a");
        }
        elsif($In::Opt{"LogMode"} and $In::Opt{"LogMode"} ne "w")
        { # "w" is default
            @PARAMS = (@PARAMS, "-logging-mode", $In::Opt{"LogMode"});
        }
        if($In::Opt{"ExtendedCheck"}) {
            @PARAMS = (@PARAMS, "-extended");
        }
        if($In::Opt{"UserLang"}) {
            @PARAMS = (@PARAMS, "-lang", $In::Opt{"UserLang"});
        }
        if($In::Desc{2}{"TargetVersion"}) {
            @PARAMS = (@PARAMS, "-vnum", $In::Desc{2}{"TargetVersion"});
        }
        if($In::Opt{"BinOnly"}) {
            @PARAMS = (@PARAMS, "-binary");
        }
        if($In::Opt{"SrcOnly"}) {
            @PARAMS = (@PARAMS, "-source");
        }
        if($In::Opt{"SortDump"}) {
            @PARAMS = (@PARAMS, "-sort");
        }
        if($In::Opt{"DumpFormat"} and $In::Opt{"DumpFormat"} ne "perl") {
            @PARAMS = (@PARAMS, "-dump-format", $In::Opt{"DumpFormat"});
        }
        if($In::Opt{"CheckHeadersOnly"}) {
            @PARAMS = (@PARAMS, "-headers-only");
        }
        if($In::Opt{"CxxIncompat"}) {
            @PARAMS = (@PARAMS, "-cxx-incompatible");
        }
        if($In::Opt{"Debug"})
        {
            @PARAMS = (@PARAMS, "-debug");
            printMsg("INFO", "Executing perl $0 @PARAMS");
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
    
    my @CMP_PARAMS = ("-l", $In::Opt{"TargetLib"});
    @CMP_PARAMS = (@CMP_PARAMS, "-d1", $DumpPath1);
    @CMP_PARAMS = (@CMP_PARAMS, "-d2", $DumpPath2);
    if($In::Opt{"TargetTitle"} ne $In::Opt{"TargetLib"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-title", $In::Opt{"TargetTitle"});
    }
    if($In::Opt{"ShowRetVal"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-show-retval");
    }
    if($In::Opt{"CrossGcc"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-cross-gcc", $In::Opt{"CrossGcc"});
    }
    @CMP_PARAMS = (@CMP_PARAMS, "-logging-mode", "a");
    if($In::Opt{"Quiet"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-quiet");
    }
    if($In::Opt{"ReportFormat"}
    and $In::Opt{"ReportFormat"} ne "html")
    { # HTML is default format
        @CMP_PARAMS = (@CMP_PARAMS, "-report-format", $In::Opt{"ReportFormat"});
    }
    if($In::Opt{"OutputReportPath"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-report-path", $In::Opt{"OutputReportPath"});
    }
    if($In::Opt{"BinReportPath"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-bin-report-path", $In::Opt{"BinReportPath"});
    }
    if($In::Opt{"SrcReportPath"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-src-report-path", $In::Opt{"SrcReportPath"});
    }
    if($In::Opt{"LoggingPath"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-log-path", $In::Opt{"LoggingPath"});
    }
    if($In::Opt{"CheckHeadersOnly"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-headers-only");
    }
    if($In::Opt{"BinOnly"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-binary");
    }
    if($In::Opt{"SrcOnly"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-source");
    }
    if($In::Opt{"FilterPath"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-filter", $In::Opt{"FilterPath"});
    }
    if($In::Opt{"SkipInternalSymbols"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-skip-internal-symbols", $In::Opt{"SkipInternalSymbols"});
    }
    if($In::Opt{"SkipInternalTypes"}) {
        @CMP_PARAMS = (@CMP_PARAMS, "-skip-internal-types", $In::Opt{"SkipInternalTypes"});
    }
    if($In::Opt{"Debug"})
    {
        @CMP_PARAMS = (@CMP_PARAMS, "-debug");
        printMsg("INFO", "Executing perl $0 @CMP_PARAMS");
    }
    system("perl", $0, @CMP_PARAMS);
    exit($?>>8);
}

sub compareInit()
{
    # read input XML descriptors or ABI dumps
    if(not $In::Desc{1}{"Path"}) {
        exitStatus("Error", "-old option is not specified");
    }
    if(not -e $In::Desc{1}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$In::Desc{1}{"Path"}."\'");
    }
    
    if(not $In::Desc{2}{"Path"}) {
        exitStatus("Error", "-new option is not specified");
    }
    if(not -e $In::Desc{2}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$In::Desc{2}{"Path"}."\'");
    }
    
    detectDefaultPaths(undef, undef, "bin", undef); # to extract dumps
    
    printMsg("INFO", "Preparing, please wait ...");
    
    if($In::Opt{"UseDumps"})
    { # --use-dumps
      # parallel processing
        if(isDump($In::Desc{1}{"Path"})
        or isDump($In::Desc{2}{"Path"})) {
            exitStatus("Error", "please specify input XML descriptors instead of ABI dumps to use with -use-dumps option.");
        }
        
        readDesc(createDesc($In::Desc{1}{"Path"}, 1), 1);
        readDesc(createDesc($In::Desc{2}{"Path"}, 2), 2);
        
        compareABIDumps($In::Desc{1}{"Version"}, $In::Desc{2}{"Version"});
    }
    
    if(isDump($In::Desc{1}{"Path"}))
    {
        $In::ABI{1} = readABIDump(1, $In::Desc{1}{"Path"});
        initAliases(1);
        
        if(my $V = $In::Desc{1}{"TargetVersion"}) {
            $In::Desc{1}{"Version"} = $V;
        }
        else {
            $In::Desc{1}{"Version"} = $In::ABI{1}{"LibraryVersion"};
        }
        
        if(not defined $In::Desc{1}{"Version"}) {
            $In::Desc{1}{"Version"} = "X";
        }
    }
    else
    {
        loadModule("ABIDump");
        readDesc(createDesc($In::Desc{1}{"Path"}, 1), 1);
        
        initLogging(1);
        detectDefaultPaths("inc", "lib", undef, "gcc");
        createABIDump(1);
    }
    
    if(isDump($In::Desc{2}{"Path"}))
    {
        $In::ABI{2} = readABIDump(2, $In::Desc{2}{"Path"});
        initAliases(2);
        
        if(my $V = $In::Desc{2}{"TargetVersion"}) {
            $In::Desc{2}{"Version"} = $V;
        }
        else {
            $In::Desc{2}{"Version"} = $In::ABI{2}{"LibraryVersion"};
        }
        
        if(not defined $In::Desc{2}{"Version"}) {
            $In::Desc{2}{"Version"} = "Y";
        }
    }
    else
    {
        loadModule("ABIDump");
        readDesc(createDesc($In::Desc{2}{"Path"}, 2), 2);
        
        initLogging(2);
        detectDefaultPaths("inc", "lib", undef, "gcc");
        createABIDump(2);
    }
    
    clearSysFilesCache(1);
    clearSysFilesCache(2);
    
    if(my $FPath = $In::Opt{"FilterPath"})
    {
        if(not -f $FPath) {
            exitStatus("Access_Error", "can't access \'".$FPath."\'");
        }
        
        if(my $Filt = readFile($FPath))
        {
            readFilter($Filt, 1);
            readFilter($Filt, 2);
        }
    }
    
    prepareCompare(1);
    prepareCompare(2);
    
    if($In::Opt{"AppPath"} and not keys(%{$In::ABI{1}{"SymLib"}})) {
        printMsg("WARNING", "the application ".getFilename($In::Opt{"AppPath"})." has no symbols imported from libraries");
    }
    
    prepareSymbols(1);
    prepareSymbols(2);
    
    # Virtual Tables
    registerVTable(1);
    registerVTable(2);
    
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
        printMsg("INFO", "Comparing ABIs ...");
    }
    else {
        printMsg("INFO", "Comparing APIs ...");
    }
    
    if($In::Opt{"CheckHeadersOnly"}
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
    
    if(not defined $In::Opt{"DisableConstantsCheck"})
    {
        if(keys(%{$CheckedSymbols{$Level}})) {
            mergeConstants($Level);
        }
    }
    
    $Cache{"mergeTypes"} = (); # free memory
    
    if($In::Opt{"CheckHeadersOnly"}
    or $Level eq "Source")
    { # added/removed in headers
        mergeHeaders($Level);
    }
    else
    { # added/removed in libs
        mergeLibs($Level);
    }
}

sub initAliases($)
{
    my $LVer = $_[0];
    
    initABI($LVer);
    
    $SymbolInfo{$LVer} = $In::ABI{$LVer}{"SymbolInfo"};
    $TypeInfo{$LVer} = $In::ABI{$LVer}{"TypeInfo"};
    $TName_Tid{$LVer} = $In::ABI{$LVer}{"TName_Tid"};
    $Constants{$LVer} = $In::ABI{$LVer}{"Constants"};
    
    initAliases_TypeAttr($LVer);
}

sub scenario()
{
    setTarget("default");
    
    initAliases(1);
    initAliases(2);
    
    $In::Opt{"Locale"} = "C.UTF-8";
    $In::Opt{"OrigDir"} = cwd();
    $In::Opt{"Tmp"} = tempdir(CLEANUP=>1);
    $In::Opt{"TargetLibShort"} = libPart($In::Opt{"TargetLib"}, "shortest");
    
    $In::Opt{"DoubleReport"} = 0;
    $In::Opt{"JoinReport"} = 1;
    
    $In::Opt{"SysPaths"}{"include"} = [];
    $In::Opt{"SysPaths"}{"lib"} = [];
    $In::Opt{"SysPaths"}{"bin"} = [];
    
    $In::Opt{"CompileError"} = 0;
    
    if($In::Opt{"TargetComponent"}) {
        $In::Opt{"TargetComponent"} = lc($In::Opt{"TargetComponent"});
    }
    else
    { # default: library
        $In::Opt{"TargetComponent"} = "library";
    }
    
    foreach (keys(%{$In::Desc{0}}))
    { # common options
        $In::Desc{1}{$_} = $In::Desc{0}{$_};
        $In::Desc{2}{$_} = $In::Desc{0}{$_};
    }
    
    $In::Opt{"AddTemplateInstances"} = 1;
    $In::Opt{"GccMissedMangling"} = 0;
    
    if($In::Opt{"StdOut"})
    { # enable quiet mode
        $In::Opt{"Quiet"} = 1;
        $In::Opt{"JoinReport"} = 1;
    }
    if(not $In::Opt{"LogMode"})
    { # default
        $In::Opt{"LogMode"} = "w";
    }
    
    if($In::Opt{"UserLang"}) {
        $In::Opt{"UserLang"} = uc($In::Opt{"UserLang"});
    }
    
    if(my $LoggingPath = $In::Opt{"LoggingPath"})
    {
        $In::Desc{1}{"OutputLogPath"} = $LoggingPath;
        $In::Desc{2}{"OutputLogPath"} = $LoggingPath;
        if($In::Opt{"Quiet"}) {
            $In::Opt{"DefaultLog"} = $LoggingPath;
        }
    }
    
    if($In::Opt{"Force"}) {
        $In::Opt{"GccMissedMangling"} = 1;
    }
    
    if($In::Opt{"Quick"}) {
        $In::Opt{"AddTemplateInstances"} = 0;
    }
    if(my $DP = $In::Opt{"OutputDumpPath"})
    { # validate
        if(not isDump($DP)) {
            exitStatus("Error", "the dump path should be a path to *.dump or *.dump.".$In::Opt{"Ar"}." file");
        }
    }
    if($In::Opt{"BinOnly"}
    and $In::Opt{"SrcOnly"})
    { # both --binary and --source
      # is the default mode
        if(not $In::Opt{"CmpSystems"})
        {
            $In::Opt{"BinOnly"} = 0;
            $In::Opt{"SrcOnly"} = 0;
        }
        
        $In::Opt{"DoubleReport"} = 1;
        $In::Opt{"JoinReport"} = 0;
        
        if($In::Opt{"OutputReportPath"})
        { # --report-path
            $In::Opt{"DoubleReport"} = 0;
            $In::Opt{"JoinReport"} = 1;
        }
    }
    elsif($In::Opt{"BinOnly"}
    or $In::Opt{"SrcOnly"})
    { # --binary or --source
        $In::Opt{"DoubleReport"} = 0;
        $In::Opt{"JoinReport"} = 0;
    }
    if($In::Opt{"UseXML"})
    { # --xml option
        $In::Opt{"ReportFormat"} = "xml";
        $In::Opt{"DumpFormat"} = "xml";
    }
    if($In::Opt{"ReportFormat"})
    { # validate
        $In::Opt{"ReportFormat"} = lc($In::Opt{"ReportFormat"});
        if($In::Opt{"ReportFormat"}!~/\A(xml|html|htm)\Z/) {
            exitStatus("Error", "unknown report format \'".$In::Opt{"ReportFormat"}."\'");
        }
        if($In::Opt{"ReportFormat"} eq "htm")
        { # HTM == HTML
            $In::Opt{"ReportFormat"} = "html";
        }
        elsif($In::Opt{"ReportFormat"} eq "xml")
        { # --report-format=XML equal to --xml
            $In::Opt{"UseXML"} = 1;
        }
    }
    else
    { # default: HTML
        $In::Opt{"ReportFormat"} = "html";
    }
    if($In::Opt{"DumpFormat"})
    { # validate
        $In::Opt{"DumpFormat"} = lc($In::Opt{"DumpFormat"});
        if($In::Opt{"DumpFormat"}!~/\A(xml|perl)\Z/) {
            exitStatus("Error", "unknown ABI dump format \'".$In::Opt{"DumpFormat"}."\'");
        }
        if($In::Opt{"DumpFormat"} eq "xml")
        { # --dump-format=XML equal to --xml
            $In::Opt{"UseXML"} = 1;
        }
    }
    else
    { # default: Perl Data::Dumper
        $In::Opt{"DumpFormat"} = "perl";
    }
    if($In::Opt{"Quiet"} and $In::Opt{"LogMode"}!~/a|n/)
    { # --quiet log
        if(-f $In::Opt{"DefaultLog"}) {
            unlink($In::Opt{"DefaultLog"});
        }
    }
    if($In::Opt{"ExtraInfo"}) {
        $In::Opt{"CheckUndefined"} = 1;
    }
    
    if($In::Opt{"TestTool"} and $In::Opt{"UseDumps"})
    { # --test && --use-dumps == --test-dump
        $In::Opt{"TestDump"} = 1;
    }
    if($In::Opt{"Tolerant"})
    { # enable all
        $In::Opt{"Tolerance"} = 1234;
    }
    if($In::Opt{"Help"})
    {
        helpMsg();
        exit(0);
    }
    if($In::Opt{"InfoMsg"})
    {
        infoMsg();
        exit(0);
    }
    if($In::Opt{"ShowVersion"})
    {
        printMsg("INFO", "ABI Compliance Checker (ABICC) $TOOL_VERSION\nCopyright (C) 2016 Andrey Ponomarenko's ABI Laboratory\nLicense: LGPL or GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($In::Opt{"DumpVersion"})
    {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    if($In::Opt{"ExtendedCheck"}) {
        $In::Opt{"CheckHeadersOnly"} = 1;
    }
    if($In::Opt{"SystemRoot"})
    { # user defined root
        if(not -e $In::Opt{"SystemRoot"}) {
            exitStatus("Access_Error", "can't access \'".$In::Opt{"SystemRoot"}."\'");
        }
        $In::Opt{"SystemRoot"}=~s/[\/]+\Z//g;
        if($In::Opt{"SystemRoot"}) {
            $In::Opt{"SystemRoot"} = getAbsPath($In::Opt{"SystemRoot"});
        }
    }
    $Data::Dumper::Sortkeys = 1;
    
    if($In::Opt{"SortDump"})
    {
        $Data::Dumper::Useperl = 1;
        $Data::Dumper::Sortkeys = \&dump_sorting;
    }
    
    if(my $TargetLibsPath = $In::Opt{"TargetLibsPath"})
    {
        if(not -f $TargetLibsPath) {
            exitStatus("Access_Error", "can't access file \'$TargetLibsPath\'");
        }
        foreach my $Lib (split(/\s*\n\s*/, readFile($TargetLibsPath)))
        {
            if($In::Opt{"OS"} eq "windows") {
                $In::Opt{"TargetLibs"}{lc($Lib)} = 1;
            }
            else {
                $In::Opt{"TargetLibs"}{$Lib} = 1;
            }
        }
    }
    if(my $TPath = $In::Opt{"TargetHeadersPath"})
    { # --headers-list
        if(not -f $TPath) {
            exitStatus("Access_Error", "can't access file \'$TPath\'");
        }
        
        $In::Desc{1}{"TargetHeader"} = {};
        $In::Desc{2}{"TargetHeader"} = {};
        
        foreach my $Header (split(/\s*\n\s*/, readFile($TPath)))
        {
            my $Name = getFilename($Header);
            $In::Desc{1}{"TargetHeader"}{$Name} = 1;
            $In::Desc{2}{"TargetHeader"}{$Name} = 1;
        }
    }
    if($In::Opt{"TargetHeader"})
    { # --header
        $In::Desc{1}{"TargetHeader"} = {};
        $In::Desc{2}{"TargetHeader"} = {};
        
        my $Name = getFilename($In::Opt{"TargetHeader"});
        $In::Desc{1}{"TargetHeader"}{$Name} = 1;
        $In::Desc{2}{"TargetHeader"}{$Name} = 1;
    }
    if($In::Opt{"TestABIDumper"})
    {
        if($In::Opt{"OS"} ne "linux") {
            exitStatus("Error", "-test-abi-dumper option is available on Linux only");
        }
    }
    if($In::Opt{"TestTool"}
    or $In::Opt{"TestDump"}
    or $In::Opt{"TestABIDumper"})
    { # --test, --test-dump
        detectDefaultPaths(undef, undef, "bin", "gcc"); # to compile libs
        loadModule("RegTests");
        testTool();
        exit(0);
    }
    if($In::Opt{"DumpSystem"})
    { # --dump-system
        if(not $In::Opt{"TargetSysInfo"})
        {
            if(-d $MODULES_DIR."/Targets/"
            and -d $MODULES_DIR."/Targets/".$In::Opt{"Target"}) {
                $In::Opt{"TargetSysInfo"} = $MODULES_DIR."/Targets/".$In::Opt{"Target"};
            }
        }
        
        if(not $In::Opt{"TargetSysInfo"}) {
            exitStatus("Error", "-sysinfo option should be specified to dump system ABI");
        }
        
        if(not -d $In::Opt{"TargetSysInfo"}) {
            exitStatus("Access_Error", "can't access \'".$In::Opt{"TargetSysInfo"}."\'");
        }
        
        loadModule("SysCheck");
        if($In::Opt{"DumpSystem"}=~/\.(xml|desc)\Z/)
        { # system XML descriptor
            if(not -f $In::Opt{"DumpSystem"}) {
                exitStatus("Access_Error", "can't access file \'".$In::Opt{"DumpSystem"}."\'");
            }
            
            my $SDesc = readFile($In::Opt{"DumpSystem"});
            if(my $RelDir = $In::Desc{1}{"RelativeDirectory"}) {
                $SDesc=~s/{RELPATH}/$RelDir/g;
            }
            
            readSysDesc($SDesc);
        }
        elsif(defined $In::Opt{"SystemRoot"})
        { # -sysroot "/" option
          # default target: /usr/lib, /usr/include
          # search libs: /usr/lib and /lib
            my $SystemRoot = $In::Opt{"SystemRoot"};
            
            if(not -e $SystemRoot."/usr/lib") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/usr/lib'");
            }
            if(not -e $SystemRoot."/lib") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/lib'");
            }
            if(not -e $SystemRoot."/usr/include") {
                exitStatus("Access_Error", "can't access '".$SystemRoot."/usr/include'");
            }
            readSysDesc("
                <name>
                    ".$In::Opt{"DumpSystem"}."
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
        detectDefaultPaths(undef, undef, "bin", "gcc"); # to check symbols
        if($In::Opt{"Target"} eq "windows")
        { # to run dumpbin.exe
          # and undname.exe
            checkWin32Env();
        }
        dumpSystem();
        exit(0);
    }
    
    if($In::Opt{"CmpSystems"})
    { # --cmp-systems
        detectDefaultPaths(undef, undef, "bin", undef); # to extract dumps
        loadModule("SysCheck");
        
        if(not $In::Opt{"BinOnly"}
        and not $In::Opt{"SrcOnly"})
        { # default
            $In::Opt{"BinOnly"} = 1;
        }
        
        cmpSystems($In::Desc{1}{"Path"}, $In::Desc{2}{"Path"});
        exit(0);
    }
    
    if(not $In::Opt{"CountSymbols"})
    {
        if(not $In::Opt{"TargetLib"}) {
            exitStatus("Error", "library name is not selected (-l option)");
        }
        else
        { # validate library name
            if($In::Opt{"TargetLib"}=~/[\*\/\\]/) {
                exitStatus("Error", "\"\\\", \"\/\" and \"*\" symbols are not allowed in the library name");
            }
        }
    }
    
    if(not $In::Opt{"TargetTitle"}) {
        $In::Opt{"TargetTitle"} = $In::Opt{"TargetLib"};
    }
    
    if(my $SymbolsListPath = $In::Opt{"SymbolsListPath"})
    {
        if(not -f $SymbolsListPath) {
            exitStatus("Access_Error", "can't access file \'$SymbolsListPath\'");
        }
        foreach my $S (split(/\s*\n\s*/, readFile($SymbolsListPath)))
        {
            $In::Desc{1}{"SymbolsList"}{$S} = 1;
            $In::Desc{2}{"SymbolsList"}{$S} = 1;
        }
    }
    if(my $TypesListPath = $In::Opt{"TypesListPath"})
    {
        if(not -f $TypesListPath) {
            exitStatus("Access_Error", "can't access file \'$TypesListPath\'");
        }
        foreach my $Type (split(/\s*\n\s*/, readFile($TypesListPath)))
        {
            $In::Desc{1}{"TypesList"}{$Type} = 1;
            $In::Desc{2}{"TypesList"}{$Type} = 1;
        }
    }
    if(my $SymbolsListPath = $In::Opt{"SkipSymbolsListPath"})
    {
        if(not -f $SymbolsListPath) {
            exitStatus("Access_Error", "can't access file \'$SymbolsListPath\'");
        }
        foreach my $Interface (split(/\s*\n\s*/, readFile($SymbolsListPath)))
        {
            $In::Desc{1}{"SkipSymbols"}{$Interface} = 1;
            $In::Desc{2}{"SkipSymbols"}{$Interface} = 1;
        }
    }
    if(my $TypesListPath = $In::Opt{"SkipTypesListPath"})
    {
        if(not -f $TypesListPath) {
            exitStatus("Access_Error", "can't access file \'$TypesListPath\'");
        }
        foreach my $Type (split(/\s*\n\s*/, readFile($TypesListPath)))
        {
            $In::Desc{1}{"SkipTypes"}{$Type} = 1;
            $In::Desc{2}{"SkipTypes"}{$Type} = 1;
        }
    }
    if(my $HeadersList = $In::Opt{"SkipHeadersPath"})
    {
        if(not -f $HeadersList) {
            exitStatus("Access_Error", "can't access file \'$HeadersList\'");
        }
        foreach my $Path (split(/\s*\n\s*/, readFile($HeadersList)))
        {
            my ($CPath, $Type) = classifyPath($Path);
            $In::Desc{1}{"SkipHeaders"}{$Type}{$CPath} = 1;
            $In::Desc{2}{"SkipHeaders"}{$Type}{$CPath} = 1;
        }
    }
    if(my $ParamNamesPath = $In::Opt{"ParamNamesPath"})
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
                        $AddSymbolParams{$Interface}{$1}=$2;
                    }
                }
                else
                {
                    my $Num = 0;
                    foreach my $Name (split(/;/, $Line)) {
                        $AddSymbolParams{$Interface}{$Num++}=$Name;
                    }
                }
            }
        }
    }
    
    if(my $AppPath = $In::Opt{"AppPath"})
    {
        if(not -f $AppPath) {
            exitStatus("Access_Error", "can't access file \'$AppPath\'");
        }
        
        detectDefaultPaths(undef, undef, "bin", "gcc");
        foreach my $Symbol (readSymbols_App($AppPath)) {
            $In::Opt{"SymbolsList_App"}{$Symbol} = 1;
        }
    }
    
    if(my $Path = $In::Opt{"CountSymbols"})
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        
        $In::ABI{1} = readABIDump(1, $Path);
        initAliases(1);
        
        foreach my $Id (keys(%{$SymbolInfo{1}}))
        {
            my $MnglName = $SymbolInfo{1}{$Id}{"MnglName"};
            if(not $MnglName) {
                $MnglName = $SymbolInfo{1}{$Id}{"ShortName"}
            }
            
            if(my $SV = $In::ABI{1}{"SymbolVersion"}{$MnglName}) {
                $CompSign{1}{$SV} = $SymbolInfo{1}{$Id};
            }
            else {
                $CompSign{1}{$MnglName} = $SymbolInfo{1}{$Id};
            }
            
            if(my $Alias = $CompSign{1}{$MnglName}{"Alias"}) {
                $CompSign{1}{$Alias} = $SymbolInfo{1}{$Id};
            }
        }
        
        my $Count = 0;
        foreach my $Symbol (sort keys(%{$CompSign{1}}))
        {
            if($CompSign{1}{$Symbol}{"PureVirt"}) {
                next;
            }
            if(not $CompSign{1}{$Symbol}{"Header"}) {
                next;
            }
            
            $Count += symbolFilter($Symbol, $CompSign{1}{$Symbol}, "Affected + InlineVirt", "Binary", 1);
        }
        
        printMsg("INFO", $Count);
        exit(0);
    }
    
    if($In::Opt{"DumpABI"})
    {
        createABIFile(1, $In::Opt{"DumpABI"});
        
        if($In::Opt{"CompileError"}) {
            exit(getErrorCode("Compile_Error"));
        }
        
        exit(0);
    }
    
    # default: compare APIs
    compareInit();
    if($In::Opt{"JoinReport"} or $In::Opt{"DoubleReport"})
    {
        compareAPIs("Binary");
        compareAPIs("Source");
    }
    elsif($In::Opt{"BinOnly"}) {
        compareAPIs("Binary");
    }
    elsif($In::Opt{"SrcOnly"}) {
        compareAPIs("Source");
    }
    exitReport();
}

scenario();
