#!/usr/bin/perl
###########################################################################
# ABI Compliance Checker (ACC) 1.97.1
# A tool for checking backward compatibility of a C/C++ library API
#
# Copyright (C) 2009-2010 The Linux Foundation.
# Copyright (C) 2009-2011 Institute for System Programming, RAS.
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies).
# Copyright (C) 2011-2012 ROSA Laboratory.
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
#    - G++ (3.0-4.6.2, recommended >= 4.5)
#    - GNU Binutils (readelf, c++filt, objdump)
#    - Perl 5 (5.8-5.14)
#
#  Mac OS X
#    - Xcode (gcc, otool, c++filt)
#
#  MS Windows
#    - MinGW (3.0-4.6.2, recommended >= 4.5)
#    - MS Visual C++ (dumpbin, undname, cl)
#    - Active Perl 5 (5.8-5.14)
#    - Sigcheck v1.71 or newer
#    - Info-ZIP 3.0 (zip, unzip)
#    - Add gcc.exe path (C:\MinGW\bin\) to your system PATH variable
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
use Cwd qw(abs_path cwd);
use Data::Dumper;
use Config;

my $TOOL_VERSION = "1.97.1";
my $ABI_DUMP_VERSION = "2.11";
my $OLDEST_SUPPORTED_VERSION = "1.18";
my $XML_REPORT_VERSION = "1.0";
my $OSgroup = get_OSgroup();
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);

# Internal modules
my $MODULES_DIR = get_Modules();
push(@INC, get_dirname($MODULES_DIR));
# Rules DB
my %RULES_PATH = (
    "Binary" => $MODULES_DIR."/RulesBin.xml",
    "Source" => $MODULES_DIR."/RulesSrc.xml");

my ($Help, $ShowVersion, %Descriptor, $TargetLibraryName, $GenerateTemplate,
$TestTool, $DumpAPI, $SymbolsListPath, $CheckHeadersOnly_Opt, $UseDumps,
$CheckObjectsOnly_Opt, $AppPath, $StrictCompat, $DumpVersion, $ParamNamesPath,
%RelativeDirectory, $TargetLibraryFName, $TestDump, $CheckImpl, $LoggingPath,
%TargetVersion, $InfoMsg, $UseOldDumps, %UsedDump, $CrossGcc, %OutputLogPath,
$OutputReportPath, $OutputDumpPath, $ShowRetVal, $SystemRoot_Opt, $DumpSystem,
$CmpSystems, $TargetLibsPath, $Debug, $CrossPrefix, $UseStaticLibs, $NoStdInc,
$TargetComponent_Opt, $TargetSysInfo, $TargetHeader, $ExtendedCheck, $Quiet,
$SkipHeadersPath, $Cpp2003, $LogMode, $StdOut, $ListAffected, $ReportFormat,
$UserLang, $TargetHeadersPath, $BinaryOnly, $SourceOnly, $BinaryReportPath,
$SourceReportPath, $UseXML, $Browse);

my $CmdName = get_filename($0);
my %OS_LibExt = (
    "dynamic" => {
        "default"=>"so",
        "macos"=>"dylib",
        "windows"=>"dll",
        "symbian"=>"dso"
    },
    "static" => {
        "default"=>"a",
        "windows"=>"lib",
        "symbian"=>"lib"
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

my %HomePage = (
    "Wiki"=>"http://ispras.linuxbase.org/index.php/ABI_compliance_checker",
    "Dev1"=>"https://github.com/lvc/abi-compliance-checker",
    "Dev2"=>"http://forge.ispras.ru/projects/abi-compliance-checker"
);

my $ShortUsage = "ABI Compliance Checker (ACC) $TOOL_VERSION
A tool for checking backward compatibility of a C/C++ library API
Copyright (C) 2012 ROSA Laboratory
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

if($#ARGV==-1) {
    printMsg("INFO", $ShortUsage);
    exit(0);
}

foreach (2 .. $#ARGV)
{ # correct comma separated options
    if($ARGV[$_-1] eq ",") {
        $ARGV[$_-2].=",".$ARGV[$_];
        splice(@ARGV, $_-1, 2);
    }
    elsif($ARGV[$_-1]=~/,\Z/) {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
    elsif($ARGV[$_]=~/\A,/
    and $ARGV[$_] ne ",") {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
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
  "old-dumps!" => \$UseOldDumps,
# extra options
  "d|descriptor-template!" => \$GenerateTemplate,
  "app|application=s" => \$AppPath,
  "static-libs!" => \$UseStaticLibs,
  "cross-gcc=s" => \$CrossGcc,
  "cross-prefix=s" => \$CrossPrefix,
  "sysroot=s" => \$SystemRoot_Opt,
  "v1|version1|vnum=s" => \$TargetVersion{1},
  "v2|version2=s" => \$TargetVersion{2},
  "s|strict!" => \$StrictCompat,
  "symbols-list=s" => \$SymbolsListPath,
  "skip-headers=s" => \$SkipHeadersPath,
  "headers-only|headers_only!" => \$CheckHeadersOnly_Opt,
  "objects-only!" => \$CheckObjectsOnly_Opt,
  "check-impl|check-implementation!" => \$CheckImpl,
  "show-retval!" => \$ShowRetVal,
  "use-dumps!" => \$UseDumps,
  "nostdinc!" => \$NoStdInc,
  "dump-system=s" => \$DumpSystem,
  "sysinfo=s" => \$TargetSysInfo,
  "cmp-systems!" => \$CmpSystems,
  "libs-list=s" => \$TargetLibsPath,
  "headers-list=s" => \$TargetHeadersPath,
  "header=s" => \$TargetHeader,
  "ext|extended!" => \$ExtendedCheck,
  "q|quiet!" => \$Quiet,
  "stdout!" => \$StdOut,
  "report-format=s" => \$ReportFormat,
  "xml!" => \$UseXML,
  "lang=s" => \$UserLang,
  "binary|bin|abi!" => \$BinaryOnly,
  "source|src|api!" => \$SourceOnly,
# other options
  "test!" => \$TestTool,
  "test-dump!" => \$TestDump,
  "debug!" => \$Debug,
  "cpp-compatible!" => \$Cpp2003,
  "p|params=s" => \$ParamNamesPath,
  "relpath1|relpath=s" => \$RelativeDirectory{1},
  "relpath2=s" => \$RelativeDirectory{2},
  "dump-path=s" => \$OutputDumpPath,
  "report-path=s" => \$OutputReportPath,
  "bin-report-path=s" => \$BinaryReportPath,
  "src-report-path=s" => \$SourceReportPath,
  "log-path=s" => \$LoggingPath,
  "log1-path=s" => \$OutputLogPath{1},
  "log2-path=s" => \$OutputLogPath{2},
  "logging-mode=s" => \$LogMode,
  "list-affected!" => \$ListAffected,
  "l-full|lib-full=s" => \$TargetLibraryFName,
  "component=s" => \$TargetComponent_Opt,
  "b|browse=s" => \$Browse
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
  Check backward binary and source-level compatibility of a C/C++ library API

DESCRIPTION:
  ABI Compliance Checker (ACC) is a tool for checking backward binary and
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
  $CmdName -lib NAME -d1 OLD.xml -d2 NEW.xml

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
  -l|-lib|-library <name>
      Library name (without version).
      It affects only on the path and the title of the report.

  -d1|-old|-o <path>
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

                 ... (XML-descriptor template
                         can be generated by -d option)
             
         2. ABI dump generated by -dump option
         3. Directory with headers and/or $SLIB_TYPE libraries
         4. Single header file
         5. Single $SLIB_TYPE library
         6. Comma separated list of headers and/or libraries

      If you are using an 2-6 descriptor types then you should
      specify version numbers with -v1 <num> and -v2 <num> options too.

      For more information, please see:
        http://ispras.linuxbase.org/index.php/Library_Descriptor

  -d2|-new|-n <path>
      Descriptor of 2nd (new) library version.

  -dump|-dump-abi <descriptor path(s)>
      Dump library ABI to gzipped TXT format file. You can transfer it
      anywhere and pass instead of the descriptor. Also it can be used
      for debugging the tool. Compatible dump versions: ".majorVersion($ABI_DUMP_VERSION).".0<=V<=$ABI_DUMP_VERSION

  -old-dumps
      Enable support for old-version ABI dumps ($OLDEST_SUPPORTED_VERSION<=V<".majorVersion($ABI_DUMP_VERSION).".0).\n";

sub HELP_MESSAGE() {
    printMsg("INFO", $HelpMessage."
MORE INFO:
     $CmdName --info\n");
}

sub INFO_MESSAGE()
{
    printMsg("INFO", "$HelpMessage
EXTRA OPTIONS:
  -d|-descriptor-template
      Create XML-descriptor template ./VERSION.xml

  -app|-application <path>
      This option allows to specify the application that should be checked
      for portability to the new library version.

  -static-libs
      Check static libraries instead of the shared ones. The <libs> section
      of the XML-descriptor should point to static libraries location.

  -cross-gcc <path>
      Path to the cross GCC compiler to use instead of the usual (host) GCC.

  -cross-prefix <prefix>
      GCC toolchain prefix.

  -sysroot <dirpath>
      Specify the alternative root directory. The tool will search for include
      paths in the <dirpath>/usr/include and <dirpath>/usr/lib directories.

  -v1|-version1 <num>
      Specify 1st library version outside the descriptor. This option is needed
      if you have prefered an alternative descriptor type (see -d1 option).

      In general case you should specify it in the XML-descriptor:
          <version>
              VERSION
          </version>

  -v2|-version2 <num>
      Specify 2nd library version outside the descriptor.

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

  -objects-only
      Check $SLIB_TYPE libraries without header files. It is easy to run, but may
      provide a low quality compatibility report with false positives and
      without analysis of changes in parameters and data types.

      Alternatively you can write \"none\" word to the <headers> section
      in the XML-descriptor:
          <headers>
              none
          </headers>

  -check-impl|-check-implementation
      Compare canonified disassembled binary code of $SLIB_TYPE libraries to
      detect changes in the implementation. Add \'Problems with Implementation\'
      section to the report.

  -show-retval
      Show the symbol's return type in the report.

  -symbols-list <path>
      This option allows to specify a file with a list of symbols (mangled
      names in C++) that should be checked, other symbols will not be checked.

  -skip-headers <path>
      The file with the list of header files, that should not be checked.

  -use-dumps
      Make dumps for two versions of a library and compare dumps. This should
      increase the performance of the tool and decrease the system memory usage.

  -nostdinc
      Do not search the GCC standard system directories for header files.

  -dump-system <name> -sysroot <dirpath>
      Find all the shared libraries and header files in <dirpath> directory,
      create XML descriptors and make ABI dumps for each library. The result
      set of ABI dumps can be compared (--cmp-systems) with the other one
      created for other version of operating system in order to check them for
      compatibility. Do not forget to specify -cross-gcc option if your target
      system requires some specific version of GCC compiler (different from
      the host GCC). The system ABI dump will be generated to:
          sys_dumps/<name>/<arch>
          
  -dump-system <descriptor.xml>
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

  -sysinfo <dir>
      This option may be used with -dump-system to dump ABI of operating
      systems and configure the dumping process.
      Default:
          modules/Targets/{unix, symbian, windows}

  -cmp-systems -d1 sys_dumps/<name1>/<arch> -d2 sys_dumps/<name2>/<arch>
      Compare two system ABI dumps. Create compatibility reports for each
      library and the common HTML report including the summary of test
      results for all checked libraries. Report will be generated to:
          sys_compat_reports/<name1>_to_<name2>/<arch>

  -libs-list <path>
      The file with a list of libraries, that should be dumped by
      the -dump-system option or should be checked by the -cmp-systems option.

  -header <name>
      Check/Dump ABI of this header only.

  -headers-list <path>
      The file with a list of headers, that should be checked/dumped.

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

  -report-format <fmt>
      Change format of compatibility report.
      Formats:
        htm - HTML format (default)
        xml - XML format

  -xml
      Alias for: --report-format=xml

  -lang <lang>
      Set library language (C or C++). You can use this option if the tool
      cannot auto-detect a language. This option may be useful for checking
      C-library headers (--lang=C) in --headers-only or --extended modes.

  -binary|-bin|-abi
      Show \"Binary\" compatibility problems only.
      Generate report to:
        compat_reports/<library name>/<v1>_to_<v2>/abi_compat_report.html
      
  -source|-src|-api
      Show \"Source\" compatibility problems only.
      Generate report to:
        compat_reports/<library name>/<v1>_to_<v2>/src_compat_report.html

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
          debug/<library>/<version>/

      Also consider using --dump option for debugging the tool.

  -cpp-compatible
      If your header file is written in C language and can be compiled by
      the C++ compiler (i.e. doesn't contain C++-keywords and other bad
      things), then you can tell ACC about this and speedup the analysis.

  -p|-params <path>
      Path to file with the function parameter names. It can be used
      for improving report view if the library header files have no
      parameter names. File format:
      
            func1;param1;param2;param3 ...
            func2;param1;param2;param3 ...
             ...

  -relpath <path>
      Replace {RELPATH} macros to <path> in the XML-descriptor used
      for dumping the library ABI (see -dump option).
  
  -relpath1 <path>
      Replace {RELPATH} macros to <path> in the 1st XML-descriptor (-d1).

  -relpath2 <path>
      Replace {RELPATH} macros to <path> in the 2nd XML-descriptor (-d2).

  -dump-path <path>
      Specify a file path (*.abi.$AR_EXT) where to generate an ABI dump.
      Default: 
          abi_dumps/<library>/<library>_<version>.abi.$AR_EXT

  -report-path <path>
      Path to joined compatibility report (see -join-report option).
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/compat_report.html

  -bin-report-path <path>
      Path to \"Binary\" compatibility report.
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/abi_compat_report.html

  -src-report-path <path>
      Path to \"Source\" compatibility report.
      Default: 
          compat_reports/<library name>/<v1>_to_<v2>/src_compat_report.html

  -log-path <path>
      Log path for all messages.
      Default:
          logs/<library>/<version>/log.txt

  -log1-path <path>
      Log path for 1st version of a library.
      Default:
          logs/<library name>/<v1>/log.txt

  -log2-path <path>
      Log path for 2nd version of a library.
      Default:
          logs/<library name>/<v2>/log.txt

  -logging-mode <mode>
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

  -component <name>
      The component name in the title and summary of the HTML report.
      Default:
          library
      
  -l-full|-lib-full <name>
      Change library name in the report title to <name>. By default
      will be displayed a name specified by -l option.

  -b|-browse <program>
      Open report(s) in the browser (firefox, opera, etc.).

REPORT:
    Compatibility report will be generated to:
        compat_reports/<library name>/<v1>_to_<v2>/compat_report.html

    Log will be generated to:
        logs/<library name>/<v1>/log.txt
        logs/<library name>/<v2>/log.txt

EXIT CODES:
    0 - Compatible. The tool has run without any errors.
    non-zero - Incompatible or the tool has run with errors.

REPORT BUGS TO:
    Andrey Ponomarenko <aponomarenko\@rosalab.ru>

MORE INFORMATION:
    ".$HomePage{"Wiki"}."
    ".$HomePage{"Dev1"}."\n");
}

my $DescriptorTemplate = "
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<descriptor>

/* Primary sections */

<version>
    /* Version of the library */
</version>

<headers>
    /* The list of paths to header files and/or
       directories with header files, one per line */
</headers>

<libs>
    /* The list of paths to shared libraries (*.$LIB_EXT) and/or
       directories with shared libraries, one per line */
</libs>

/* Optional sections */

<include_paths>
    /* The list of include paths that will be provided
       to GCC to compile library headers, one per line.
       NOTE: If you define this section then the tool
       will not automatically generate include paths */
</include_paths>

<add_include_paths>
    /* The list of include paths that will be added
       to the automatically generated include paths, one per line */
</add_include_paths>

<skip_include_paths>
    /* The list of include paths that will be removed from the
       list of automatically generated include paths, one per line */
</skip_include_paths>

<gcc_options>
    /* Additional GCC options, one per line */
</gcc_options>

<include_preamble>
    /* The list of header files that will be
       included before other headers, one per line.
       Examples:
           1) tree.h for libxml2
           2) ft2build.h for freetype2 */
</include_preamble>

<defines>
    /* The list of defines that will be added at the
       headers compiling stage, one per line:
          #define A B
          #define C D */
</defines>

<skip_types>
    /* The list of data types, that
       should not be checked, one per line */
</skip_types>

<skip_symbols>
    /* The list of functions (mangled/symbol names in C++),
       that should not be checked, one per line */
</skip_symbols>

<skip_namespaces>
    /* The list of C++ namespaces, that
       should not be checked, one per line */
</skip_namespaces>

<skip_constants>
    /* The list of constants that should
       not be checked, one name per line */
</skip_constants>

<skip_headers>
    /* The list of header files and/or directories
       with header files that should not be checked, one per line */
</skip_headers>

<skip_libs>
    /* The list of shared libraries and/or directories
       with shared libraries that should not be checked, one per line */
</skip_libs>

<skip_including>
    /* The list of header files, that cannot be included
       directly (or non-self compiled ones), one per line */
</skip_including>

<search_headers>
    /* List of directories to be searched
       for header files to automatically
       generate include paths, one per line. */
</search_headers>

<search_libs>
    /* List of directories to be searched
       for shared librariess to resolve
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

</descriptor>";

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
    "throw"
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

my %StdcxxMangling = (
    "3std"=>"St",
    "3std9allocator"=>"Sa",
    "3std12basic_string"=>"Sb",
    "3std12basic_stringIcE"=>"Ss",
    "3std13basic_istreamIcE"=>"Si",
    "3std13basic_ostreamIcE"=>"So",
    "3std14basic_iostreamIcE"=>"Sd"
);

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

my %LocalIncludes = map {$_=>1} (
    "/usr/local/include",
    "/usr/local" );

my %OS_AddPath=(
# These paths are needed if the tool cannot detect them automatically
    "macos"=>{
        "include"=>{
            "/Library"=>1,
            "/Developer/usr/include"=>1
        },
        "lib"=>{
            "/Library"=>1,
            "/Developer/usr/lib"=>1
        },
        "bin"=>{
            "/Developer/usr/bin"=>1
        }
    },
    "beos"=>{
    # Haiku has GCC 2.95.3 by default
    # try to find GCC>=3.0 in /boot/develop/abi
        "include"=>{
            "/boot/common"=>1,
            "/boot/develop"=>1},
        "lib"=>{
            "/boot/common/lib"=>1,
            "/boot/system/lib"=>1,
            "/boot/apps"=>1},
        "bin"=>{
            "/boot/common/bin"=>1,
            "/boot/system/bin"=>1,
            "/boot/develop/abi"=>1
    }
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
my (%WORD_SIZE, %CPU_ARCH, %GCC_VERSION);

my %LIB_ARCH;

my $STDCXX_TESTING = 0;
my $GLIBC_TESTING = 0;

my $CheckHeadersOnly = $CheckHeadersOnly_Opt;
my $CheckObjectsOnly = $CheckObjectsOnly_Opt;
my $TargetComponent;

# Set Target Component Name
if($TargetComponent_Opt) {
    $TargetComponent = lc($TargetComponent_Opt);
}
else
{ # default: library
  # other components: header, system, ...
    $TargetComponent = "library";
}

my $TOP_REF = "<a style='font-size:11px;' href='#Top'>to the top</a>";

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

# Types
my %TypeInfo;
my %TemplateInstance_Func;
my %TemplateInstance;
my %SkipTypes = (
  "1"=>{},
  "2"=>{} );
my %Tid_TDid = (
  "1"=>{},
  "2"=>{} );
my %CheckedTypes;
my %TName_Tid;
my %EnumMembName_Id;
my %NestedNameSpaces = (
  "1"=>{},
  "2"=>{} );
my %UsedType;
my %VirtualTable;
my %VirtualTable_Full;
my %ClassVTable;
my %ClassVTable_Content;
my %VTableClass;
my %AllocableClass;
my %ClassMethods;
my %ClassToId;
my %Class_SubClasses;
my %OverriddenMethods;
my $MAX_TID;

# Typedefs
my %Typedef_BaseName;
my %Typedef_Tr;
my %Typedef_Eq;
my %StdCxxTypedef;
my %MissedTypedef;

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
my %SymbolsList;
my %SymbolsList_App;
my %CheckedSymbols;
my %GeneratedSymbols;
my %DepSymbols = (
  "1"=>{},
  "2"=>{} );
my %MangledNames;
my %AddIntParams;
my %Interface_Impl;

# Headers
my %Include_Preamble;
my %Registered_Headers;
my %HeaderName_Paths;
my %Header_Dependency;
my %Include_Neighbors;
my %Include_Paths;
my %INC_PATH_AUTODETECT = (
  "1"=>1,
  "2"=>1 );
my %Add_Include_Paths;
my %Skip_Include_Paths;
my %RegisteredDirs;
my %RegisteredDeps;
my %Header_ErrorRedirect;
my %Header_Includes;
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

my %C99Mode = (
  "1"=>0,
  "2"=>0 );
my %AutoPreambleMode = (
  "1"=>0,
  "2"=>0 );
my %MinGWMode = (
  "1"=>0,
  "2"=>0 );

# Shared Objects
my %DyLib_DefaultPath;
my %InputObject_Paths;
my %RegisteredObjDirs;

# System Objects
my %SystemObjects;
my %DefaultLibPaths;

# System Headers
my %SystemHeaders;
my %DefaultCppPaths;
my %DefaultGccPaths;
my %DefaultIncPaths;
my %DefaultCppHeader;
my %DefaultGccHeader;
my %UserIncPath;

# Merging
my %CompleteSignature;
my %Symbol_Library;
my %Library_Symbol = (
  "1"=>{},
  "2"=>{} );
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
my %VTableChanged;
my %ExtendedFuncs;
my %ReturnedClass;
my %ParamClass;
my %SourceAlternative;
my %SourceAlternative_B;
my %SourceReplacement;

# OS Compliance
my %TargetLibs;
my %TargetHeaders;

# OS Specifics
my $OStarget = $OSgroup;
my %TargetTools;

# Compliance Report
my %Type_MaxSeverity;

# Recursion locks
my @RecurLib;
my @RecurSymlink;
my @RecurTypes;
my @RecurInclude;
my @RecurConstant;

# System
my %SystemPaths;
my %DefaultBinPaths;
my $GCC_PATH;

# Symbols versioning
my %SymVer = (
  "1"=>{},
  "2"=>{} );

# Problem descriptions
my %CompatProblems;
my %ProblemsWithConstants;
my %ImplProblems;
my %TotalAffected;

# Reports
my $ContentID = 1;
my $ContentSpanStart = "<span class=\"section\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanStart_Affected = "<span class=\"section_affected\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanStart_Info = "<span class=\"section_info\" onclick=\"javascript:showContent(this, 'CONTENT_ID')\">\n";
my $ContentSpanEnd = "</span>\n";
my $ContentDivStart = "<div id=\"CONTENT_ID\" style=\"display:none;\">\n";
my $ContentDivEnd = "</div>\n";
my $Content_Counter = 0;

# Modes
my $JoinReport = 1;
my $DoubleReport = 0;

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
        # system directory
        "ACC_MODULES_INSTALL_PATH"
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

sub loadModule($)
{
    my $Name = $_[0];
    my $Path = $MODULES_DIR."/Internals/$Name.pm";
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    require $Path;
}

sub showNum($)
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
            if(-f joinPath($Path, $Name)) {
                return joinPath($Path, $Name);
            }
            if($CrossPrefix)
            { # user-defined prefix (arm-none-symbianelf, ...)
                my $Candidate = joinPath($Path, $CrossPrefix."-".$Name);
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
    if($Candidate=~s/(\W|\A)gcc(|\.\w+)\Z/$1$Name$2/) {
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
    if($BinUtils{$Name}) {
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
    foreach my $Path (sort {length($a)<=>length($b)} keys(%{$SystemPaths{"bin"}}))
    {
        my $CmdPath = joinPath($Path,$Name);
        if(-f $CmdPath)
        {
            if($Name=~/gcc/) {
                next if(not check_gcc_version($CmdPath, "3"));
            }
            return ($Cache{"search_Cmd"}{$Name} = $CmdPath);
        }
    }
    return ($Cache{"search_Cmd"}{$Name} = "");
}

sub get_CmdPath_Default($)
{ # search in PATH
    my $Name = $_[0];
    return "" if(not $Name);
    if(defined $Cache{"get_CmdPath_Default"}{$Name}) {
        return $Cache{"get_CmdPath_Default"}{$Name};
    }
    if($Name=~/find/)
    { # special case: search for "find" utility
        if(`find . -maxdepth 0 2>$TMP_DIR/null`) {
            return ($Cache{"get_CmdPath_Default"}{$Name} = "find");
        }
    }
    elsif($Name=~/gcc/) {
        return check_gcc_version($Name, "3");
    }
    if(check_command($Name)) {
        return ($Cache{"get_CmdPath_Default"}{$Name} = $Name);
    }
    if($OSgroup eq "windows"
    and `$Name /? 2>$TMP_DIR/null`) {
        return ($Cache{"get_CmdPath_Default"}{$Name} = $Name);
    }
    if($Name!~/which/)
    {
        my $WhichCmd = get_CmdPath("which");
        if($WhichCmd and `$WhichCmd $Name 2>$TMP_DIR/null`) {
            return ($Cache{"get_CmdPath_Default"}{$Name} = $Name);
        }
    }
    foreach my $Path (sort {length($a)<=>length($b)} keys(%DefaultBinPaths))
    {
        if(-f $Path."/".$Name) {
            return ($Cache{"get_CmdPath_Default"}{$Name} = joinPath($Path,$Name));
        }
    }
    return ($Cache{"get_CmdPath_Default"}{$Name} = "");
}

sub clean_path($)
{
    my $Path = $_[0];
    $Path=~s/[\/\\]+\Z//g;
    return $Path;
}

sub classifyPath($)
{
    my $Path = $_[0];
    if($Path=~/[\*\[]/)
    { # wildcard
        $Path=~s/\*/.*/g;
        $Path=~s/\\/\\\\/g;
        return ($Path, "Pattern");
    }
    elsif($Path=~/[\/\\]/)
    { # directory or relative path
        $Path=~s/[\/\\]+\Z//g;
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
        exitStatus("Error", "$DName is not a descriptor (see -d1 option)");
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
    
    if(not $CheckObjectsOnly_Opt)
    {
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
        $Path = clean_path($Path);
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = path_format($Path, $OSgroup);
        $SystemPaths{"include"}{$Path}=1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_libs")))
    {
        $Path = clean_path($Path);
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = path_format($Path, $OSgroup);
        $SystemPaths{"lib"}{$Path}=1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "tools")))
    {
        $Path=clean_path($Path);
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = path_format($Path, $OSgroup);
        $SystemPaths{"bin"}{$Path}=1;
        $TargetTools{$Path}=1;
    }
    if(my $Prefix = parseTag(\$Content, "cross_prefix")) {
        $CrossPrefix = $Prefix;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "include_paths")))
    {
        $Path=clean_path($Path);
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = path_format($Path, $OSgroup);
        $Descriptor{$LibVersion}{"IncludePaths"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "add_include_paths")))
    {
        $Path=clean_path($Path);
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = path_format($Path, $OSgroup);
        $Descriptor{$LibVersion}{"AddIncludePaths"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_include_paths")))
    {
        # skip some auto-generated include paths
        $Skip_Include_Paths{$LibVersion}{path_format($Path)}=1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_including")))
    {
        # skip direct including of some headers
        $SkipHeadersList{$LibVersion}{$Path} = 2;
        my ($CPath, $Type) = classifyPath($Path);
        $SkipHeaders{$LibVersion}{$Type}{$CPath} = 2;
    }
    $Descriptor{$LibVersion}{"GccOptions"} = parseTag(\$Content, "gcc_options");
    foreach my $Option (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"GccOptions"})) {
        $CompilerOptions{$LibVersion} .= " ".$Option;
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

sub parseTag($$)
{
    my ($CodeRef, $Tag) = @_;
    return "" if(not $CodeRef or not ${$CodeRef} or not $Tag);
    if(${$CodeRef}=~s/\<\Q$Tag\E\>((.|\n)+?)\<\/\Q$Tag\E\>//)
    {
        my $Content = $1;
        $Content=~s/(\A\s+|\s+\Z)//g;
        return $Content;
    }
    else {
        return "";
    }
}

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
  "template_type_parm" => "Other",
  "tree_list" => "Other",
  "tree_vec" => "Other",
  "type_decl" => "Other",
  "union_type" => "Union",
  "var_decl" => "Other",
  "void_type" => "Intrinsic",
  "offset_type" => "Other" );

sub getInfo($)
{
    my $InfoPath = $_[0];
    return if(not $InfoPath or not -f $InfoPath);
    my $Content = readFile($InfoPath);
    unlink($InfoPath);
    $Content=~s/\n[ ]+/ /g;
    my @Lines = split("\n", $Content);
    $Content="";# clear
    foreach (@Lines)
    {
        if(/\A\@(\d+)\s+([a-z_]+)\s+(.+)\Z/oi)
        { # get a number and attributes of a node
            next if(not $NodeType{$2});
            $LibInfo{$Version}{"info_type"}{$1}=$2;
            $LibInfo{$Version}{"info"}{$1}=$3;
        }
    }
    $MAX_TID = $#Lines+1;
    @Lines=();# clear
    # processing info
    setTemplateParams_All();
    getTypeInfo_All();
    simplifyNames();
    getSymbolInfo_All();
    getVarInfo_All();
    
    # cleaning memory
    %LibInfo = ();
    %TemplateInstance = ();
    %TemplateInstance_Func = ();
    %MangledNames = ();

    if($Debug) {
        # debugMangling($Version);
    }
}

sub simplifyNames()
{
    foreach my $Base (keys(%{$Typedef_Tr{$Version}}))
    {
        my @Translations = keys(%{$Typedef_Tr{$Version}{$Base}});
        if($#Translations==0 and length($Translations[0])<=length($Base)) {
            $Typedef_Eq{$Version}{$Base} = $Translations[0];
        }
    }
    foreach my $TDid (keys(%{$TypeInfo{$Version}}))
    {
        foreach my $Tid (keys(%{$TypeInfo{$Version}{$TDid}}))
        {
            my $TypeName = $TypeInfo{$Version}{$TDid}{$Tid}{"Name"};
            if(not $TypeName) {
                next;
            }
            next if(index($TypeName,"<")==-1);# template instances only
            if($TypeName=~/>(::\w+)+\Z/)
            { # skip unused types
                next;
            };
            foreach my $Base (sort {length($b)<=>length($a)}
            sort {$b cmp $a} keys(%{$Typedef_Eq{$Version}}))
            {
                next if(not $Base);
                next if(index($TypeName,$Base)==-1);
                next if(length($TypeName) - length($Base) <= 3);
                my $Typedef = $Typedef_Eq{$Version}{$Base};
                $TypeName=~s/(\<|\,)\Q$Base\E(\W|\Z)/$1$Typedef$2/g;
                $TypeName=~s/(\<|\,)\Q$Base\E(\w|\Z)/$1$Typedef $2/g;
            }
            if($TypeName ne $TypeInfo{$Version}{$TDid}{$Tid}{"Name"})
            {
                $TypeInfo{$Version}{$TDid}{$Tid}{"Name"} = formatName($TypeName);
                $TName_Tid{$Version}{$TypeName} = $Tid;
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
    my $TypeInfoId = $_[0];
    if($LibInfo{$Version}{"info"}{$TypeInfoId}=~/(inst|spcs)[ ]*:[ ]*@(\d+) /)
    {
        my $TmplInst_InfoId = $2;
        setTemplateInstParams($TmplInst_InfoId);
        my $TmplInst_Info = $LibInfo{$Version}{"info"}{$TmplInst_InfoId};
        while($TmplInst_Info=~/(chan|chain)[ ]*:[ ]*@(\d+) /)
        {
            $TmplInst_InfoId = $2;
            $TmplInst_Info = $LibInfo{$Version}{"info"}{$TmplInst_InfoId};
            setTemplateInstParams($TmplInst_InfoId);
        }
    }
}

sub setTemplateInstParams($)
{
    my $TmplInst_Id = $_[0];
    my $Info = $LibInfo{$Version}{"info"}{$TmplInst_Id};
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
            my ($Param_Pos, $Param_TypeId) = ($1, $2);
            return if($LibInfo{$Version}{"info_type"}{$Param_TypeId} eq "template_type_parm");
            if($LibInfo{$Version}{"info_type"}{$ElemId} eq "function_decl") {
                $TemplateInstance_Func{$Version}{$ElemId}{$Param_Pos} = $Param_TypeId;
            }
            else {
                $TemplateInstance{$Version}{getTypeDeclId($ElemId)}{$ElemId}{$Param_Pos} = $Param_TypeId;
            }
        }
    }
}

sub getTypeDeclId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+)/) {
            return $1;
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

sub getTypeInfo_All()
{
    if(not check_gcc_version($GCC_PATH, "4.5"))
    { # support for GCC < 4.5
      # missed typedefs: QStyle::State is typedef to QFlags<QStyle::StateFlag>
      # but QStyleOption.state is of type QFlags<QStyle::StateFlag> in the TU dump
      # FIXME: check GCC versions
        addMissedTypes_Pre();
    }
    foreach (sort {int($a)<=>int($b)} keys(%{$LibInfo{$Version}{"info"}}))
    {
        my $IType = $LibInfo{$Version}{"info_type"}{$_};
        if($IType=~/_type\Z/ and $IType ne "function_type"
        and $IType ne "method_type") {
            getTypeInfo(getTypeDeclId("$_"), "$_");
        }
    }
    $TypeInfo{$Version}{""}{-1}{"Name"} = "...";
    $TypeInfo{$Version}{""}{-1}{"Type"} = "Intrinsic";
    $TypeInfo{$Version}{""}{-1}{"Tid"} = -1;
    if(not check_gcc_version($GCC_PATH, "4.5"))
    { # support for GCC < 4.5
        addMissedTypes_Post();
    }
}

sub addMissedTypes_Pre()
{
    foreach my $MissedTDid (sort {int($a)<=>int($b)} keys(%{$LibInfo{$Version}{"info"}}))
    { # detecting missed typedefs
        if($LibInfo{$Version}{"info_type"}{$MissedTDid} eq "type_decl")
        {
            my $TypeId = getTreeAttr($MissedTDid, "type");
            next if(not $TypeId);
            my $TypeType = getTypeType($MissedTDid, $TypeId);
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
                $MissedTypedef{$Version}{$TypeId}{"$MissedTDid"} = 1;
            }
        }
    }
    foreach my $Tid (keys(%{$MissedTypedef{$Version}}))
    { # add missed typedefs
        my @Missed = keys(%{$MissedTypedef{$Version}{$Tid}});
        if(not @Missed or $#Missed>=1) {
            delete($MissedTypedef{$Version}{$Tid});
            next;
        }
        my $MissedTDid = $Missed[0];
        my $TDid = getTypeDeclId($Tid);
        my ($TypedefName, $TypedefNS) = getTrivialName($MissedTDid, $Tid);
        my %MissedInfo = ( # typedef info
            "Name" => $TypedefName,
            "NameSpace" => $TypedefNS,
            "BaseType" => {
                            "TDid" => $TDid,
                            "Tid" => $Tid
                          },
            "Type" => "Typedef",
            "Tid" => ++$MAX_TID,
            "TDid" => $MissedTDid );
        my ($H, $L) = getLocation($MissedTDid);
        $MissedInfo{"Header"} = $H;
        $MissedInfo{"Line"} = $L;
        # $MissedInfo{"Size"} = getSize($Tid)/$BYTE_SIZE;
        my $MName = $MissedInfo{"Name"};
        next if(not $MName);
        if($MName=~/\*|\&|\s/)
        { # other types
            next;
        }
        if($MName=~/>(::\w+)+\Z/)
        { # QFlags<Qt::DropAction>::enum_type
            delete($MissedTypedef{$Version}{$Tid});
            next;
        }
        if(getTypeType($TDid, $Tid)=~/\A(Intrinsic|Union|Struct|Enum|Class)\Z/)
        { # double-check for the name of typedef
            my ($TName, $TNS) = getTrivialName($TDid, $Tid); # base type info
            next if(not $TName);
            if(length($MName)>=length($TName))
            { # too long typedef
                delete($MissedTypedef{$Version}{$Tid});
                next;
            }
            if($TName=~/\A\Q$MName\E</) {
                next;
            }
            if($MName=~/\A\Q$TName\E/)
            { # QDateTimeEdit::Section and QDateTimeEdit::Sections::enum_type
                delete($MissedTypedef{$Version}{$Tid});
                next;
            }
            if(get_depth($MName)==0 and get_depth($TName)!=0)
            { # std::_Vector_base and std::vector::_Base
                delete($MissedTypedef{$Version}{$Tid});
                next;
            }
        }
        %{$TypeInfo{$Version}{$MissedTDid}{$MissedInfo{"Tid"}}} = %MissedInfo;
        $Tid_TDid{$Version}{$MissedInfo{"Tid"}} = $MissedTDid;
        delete($TypeInfo{$Version}{$MissedTDid}{$Tid});
        # register typedef
        $MissedTypedef{$Version}{$Tid}{"TDid"} = $MissedTDid;
        $MissedTypedef{$Version}{$Tid}{"Tid"} = $MissedInfo{"Tid"};
    }
}

sub addMissedTypes_Post()
{
    foreach my $BaseId (keys(%{$MissedTypedef{$Version}}))
    {
        my $Tid = $MissedTypedef{$Version}{$BaseId}{"Tid"};
        my $TDid = $MissedTypedef{$Version}{$BaseId}{"TDid"};
        $TypeInfo{$Version}{$TDid}{$Tid}{"Size"} = get_TypeAttr($BaseId, $Version, "Size");
    }
}

sub getTypeInfo($$)
{
    my ($TDId, $TId) = @_;
    %{$TypeInfo{$Version}{$TDId}{$TId}} = getTypeAttr($TDId, $TId);
    my $TName = $TypeInfo{$Version}{$TDId}{$TId}{"Name"};
    if(not $TName) {
        delete($TypeInfo{$Version}{$TDId}{$TId});
        return;
    }
    if($TDId) {
        $Tid_TDid{$Version}{$TId} = $TDId;
    }
    if(not $TName_Tid{$Version}{$TName}) {
        $TName_Tid{$Version}{$TName} = $TId;
    }
}

sub getArraySize($$)
{
    my ($TypeId, $BaseName) = @_;
    my $SizeBytes = getSize($TypeId)/$BYTE_SIZE;
    while($BaseName=~s/\s*\[(\d+)\]//) {
        $SizeBytes/=$1;
    }
    my $BasicId = $TName_Tid{$Version}{$BaseName};
    if(my $BasicSize = $TypeInfo{$Version}{getTypeDeclId($BasicId)}{$BasicId}{"Size"}) {
        $SizeBytes/=$BasicSize;
    }
    return $SizeBytes;
}

sub getTParams_Func($)
{
    my @TmplParams = ();
    foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$TemplateInstance_Func{$Version}{$_[0]}}))
    {
        my $Param = get_TemplateParam($Pos, $TemplateInstance_Func{$Version}{$_[0]}{$Pos});
        if($Param eq "") {
            return ();
        }
        elsif($Param ne "\@skip\@") {
            push(@TmplParams, $Param);
        }
    }
    return @TmplParams;
}

sub getTParams($$)
{
    my ($TypeDeclId, $TypeId) = @_;
    my @Template_Params = ();
    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$TemplateInstance{$Version}{$TypeDeclId}{$TypeId}}))
    {
        my $Param_TypeId = $TemplateInstance{$Version}{$TypeDeclId}{$TypeId}{$Pos};
        my $Param = get_TemplateParam($Pos, $Param_TypeId);
        if($Param eq "") {
            return ();
        }
        elsif($Param ne "\@skip\@") {
            @Template_Params = (@Template_Params, $Param);
        }
    }
    return @Template_Params;
}

sub getTypeAttr($$)
{
    my ($TypeDeclId, $TypeId) = @_;
    my ($BaseTypeSpec, %TypeAttr) = ();
    if(defined $TypeInfo{$Version}{$TypeDeclId}{$TypeId}
    and $TypeInfo{$Version}{$TypeDeclId}{$TypeId}{"Name"}) {
        return %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}};
    }
    $TypeAttr{"Tid"} = $TypeId;
    $TypeAttr{"TDid"} = $TypeDeclId;
    $TypeAttr{"Type"} = getTypeType($TypeDeclId, $TypeId);
    if($TypeAttr{"Type"} eq "Unknown") {
        return ();
    }
    elsif($TypeAttr{"Type"}=~/(Func|Method|Field)Ptr/)
    {
        %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}} = getMemPtrAttr(pointTo($TypeId), $TypeDeclId, $TypeId, $TypeAttr{"Type"});
        $TName_Tid{$Version}{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}{"Name"}} = $TypeId;
        return %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}};
    }
    elsif($TypeAttr{"Type"} eq "Array")
    {
        ($TypeAttr{"BaseType"}{"Tid"}, $TypeAttr{"BaseType"}{"TDid"}, $BaseTypeSpec) = selectBaseType($TypeDeclId, $TypeId);
        my %BaseTypeAttr = getTypeAttr($TypeAttr{"BaseType"}{"TDid"}, $TypeAttr{"BaseType"}{"Tid"});
        if(my $NElems = getArraySize($TypeId, $BaseTypeAttr{"Name"}))
        {
            $TypeAttr{"Size"} = getSize($TypeId)/$BYTE_SIZE;
            if($BaseTypeAttr{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                $TypeAttr{"Name"} = $1."[$NElems]".$2;
            }
            else {
                $TypeAttr{"Name"} = $BaseTypeAttr{"Name"}."[$NElems]";
            }
        }
        else
        {
            $TypeAttr{"Size"} = $WORD_SIZE{$Version}; # pointer
            if($BaseTypeAttr{"Name"}=~/\A([^\[\]]+)(\[(\d+|)\].*)\Z/) {
                $TypeAttr{"Name"} = $1."[]".$2;
            }
            else {
                $TypeAttr{"Name"} = $BaseTypeAttr{"Name"}."[]";
            }
        }
        $TypeAttr{"Name"} = formatName($TypeAttr{"Name"});
        if($BaseTypeAttr{"Header"})  {
            $TypeAttr{"Header"} = $BaseTypeAttr{"Header"};
        }
        %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}} = %TypeAttr;
        $TName_Tid{$Version}{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}{"Name"}} = $TypeId;
        return %TypeAttr;
    }
    elsif($TypeAttr{"Type"}=~/\A(Intrinsic|Union|Struct|Enum|Class)\Z/)
    {
        %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}} = getTrivialTypeAttr($TypeDeclId, $TypeId);
        return %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}};
    }
    else
    {
        ($TypeAttr{"BaseType"}{"Tid"}, $TypeAttr{"BaseType"}{"TDid"}, $BaseTypeSpec) = selectBaseType($TypeDeclId, $TypeId);
        if(my $MissedTDid = $MissedTypedef{$Version}{$TypeAttr{"BaseType"}{"Tid"}}{"TDid"})
        {
            if($MissedTDid ne $TypeDeclId)
            {
                $TypeAttr{"BaseType"}{"TDid"} = $MissedTDid;
                $TypeAttr{"BaseType"}{"Tid"} = $MissedTypedef{$Version}{$TypeAttr{"BaseType"}{"Tid"}}{"Tid"};
            }
        }
        my %BaseTypeAttr = getTypeAttr($TypeAttr{"BaseType"}{"TDid"}, $TypeAttr{"BaseType"}{"Tid"});
        if(not $BaseTypeAttr{"Name"})
        { # const "template_type_parm"
            return ();
        }
        if($BaseTypeAttr{"Type"} eq "Typedef")
        { # relinking typedefs
            my %BaseBase = get_Type($BaseTypeAttr{"BaseType"}{"TDid"},$BaseTypeAttr{"BaseType"}{"Tid"}, $Version);
            if($BaseTypeAttr{"Name"} eq $BaseBase{"Name"}) {
                ($TypeAttr{"BaseType"}{"Tid"}, $TypeAttr{"BaseType"}{"TDid"}) = ($BaseBase{"Tid"}, $BaseBase{"TDid"});
            }
        }
        if($BaseTypeSpec)
        {
            if($TypeAttr{"Type"} eq "Pointer"
            and $BaseTypeAttr{"Name"}=~/\([\*]+\)/) {
                $TypeAttr{"Name"} = $BaseTypeAttr{"Name"};
                $TypeAttr{"Name"}=~s/\(([*]+)\)/($1*)/g;
            }
            else {
                $TypeAttr{"Name"} = $BaseTypeAttr{"Name"}." ".$BaseTypeSpec;
            }
        }
        else {
            $TypeAttr{"Name"} = $BaseTypeAttr{"Name"};
        }
        if($TypeAttr{"Type"} eq "Typedef")
        {
            $TypeAttr{"Name"} = getNameByInfo($TypeDeclId);
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
                    if($TypeAttr{"NameSpace"}=~/\Astd(::|\Z)/ and $BaseTypeAttr{"NameSpace"}=~/\Astd(::|\Z)/
                    and $BaseTypeAttr{"Name"}=~/</ and $TypeAttr{"Name"}!~/>(::\w+)+\Z/)
                    { # types like "std::fpos<__mbstate_t>" are
                      # not covered by typedefs in the ABI dump
                      # so trying to add such typedefs manually
                        $StdCxxTypedef{$Version}{$BaseTypeAttr{"Name"}}{$TypeAttr{"Name"}} = 1;
                        if(length($TypeAttr{"Name"})<=length($BaseTypeAttr{"Name"}))
                        {
                            if(($BaseTypeAttr{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/))
                            { # skip "other" in "std" and "type" in "boost"
                                $Typedef_Eq{$Version}{$BaseTypeAttr{"Name"}} = $TypeAttr{"Name"};
                            }
                        }
                    }
                }
            }
            if($TypeAttr{"Name"} ne $BaseTypeAttr{"Name"}
            and $TypeAttr{"Name"}!~/>(::\w+)+\Z/ and $BaseTypeAttr{"Name"}!~/>(::\w+)+\Z/)
            {
                $Typedef_BaseName{$Version}{$TypeAttr{"Name"}} = $BaseTypeAttr{"Name"};
                if($BaseTypeAttr{"Name"}=~/</)
                {
                    if(($BaseTypeAttr{"Name"}!~/\A(std|boost)::/ or $TypeAttr{"Name"}!~/\A[a-z]+\Z/)) {
                        $Typedef_Tr{$Version}{$BaseTypeAttr{"Name"}}{$TypeAttr{"Name"}} = 1;
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
            elsif($BaseTypeAttr{"Size"}) {
                $TypeAttr{"Size"} = $BaseTypeAttr{"Size"};
            }
        }
        $TypeAttr{"Name"} = formatName($TypeAttr{"Name"});
        if(not $TypeAttr{"Header"} and $BaseTypeAttr{"Header"})  {
            $TypeAttr{"Header"} = $BaseTypeAttr{"Header"};
        }
        %{$TypeInfo{$Version}{$TypeDeclId}{$TypeId}} = %TypeAttr;
        if(not $TName_Tid{$Version}{$TypeAttr{"Name"}}) {
            $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
        }
        return %TypeAttr;
    }
}

sub get_TemplateParam($$)
{
    my ($Pos, $Type_Id) = @_;
    return "" if(not $Type_Id);
    if($Cache{"get_TemplateParam"}{$Type_Id}) {
        return $Cache{"get_TemplateParam"}{$Type_Id};
    }
    if(getNodeType($Type_Id) eq "integer_cst")
    { # int (1), unsigned (2u), char ('c' as 99), ...
        my $CstTid = getTreeAttr($Type_Id, "type");
        my %CstType = getTypeAttr(getTypeDeclId($CstTid), $CstTid);
        my $Num = getNodeIntCst($Type_Id);
        if(my $CstSuffix = $ConstantSuffix{$CstType{"Name"}}) {
            return $Num.$CstSuffix;
        }
        else {
            return "(".$CstType{"Name"}.")".$Num;
        }
    }
    elsif(getNodeType($Type_Id) eq "string_cst") {
        return getNodeStrCst($Type_Id);
    }
    elsif(getNodeType($Type_Id) eq "tree_vec") {
        return "\@skip\@";
    }
    else
    {
        my $Type_DId = getTypeDeclId($Type_Id);
        my %ParamAttr = getTypeAttr($Type_DId, $Type_Id);
        if(not $ParamAttr{"Name"}) {
            return "";
        }
        my $PName = $ParamAttr{"Name"};
        if($ParamAttr{"Name"}=~/\>/) {
            if(my $Cover = cover_stdcxx_typedef($ParamAttr{"Name"})) {
                $PName = $Cover;
            }
        }
        if($Pos>=1 and
        $PName=~/\Astd::(allocator|less|((char|regex)_traits)|((i|o)streambuf_iterator))\</)
        { # template<typename _Tp, typename _Alloc = std::allocator<_Tp> >
          # template<typename _Key, typename _Compare = std::less<_Key>
          # template<typename _CharT, typename _Traits = std::char_traits<_CharT> >
          # template<typename _Ch_type, typename _Rx_traits = regex_traits<_Ch_type> >
          # template<typename _CharT, typename _InIter = istreambuf_iterator<_CharT> >
          # template<typename _CharT, typename _OutIter = ostreambuf_iterator<_CharT> >
            return "\@skip\@";
        }
        return $PName;
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
    my $TypeName_Covered = $TypeName;
    while($TypeName=~s/(>)[ ]*(const|volatile|restrict| |\*|\&)\Z/$1/g){};
    if(my @Covers = sort {length($a)<=>length($b)} sort keys(%{$StdCxxTypedef{$Version}{$TypeName}}))
    {
        my $Cover = $Covers[0];
        $TypeName_Covered=~s/(\W|\A)\Q$TypeName\E(\W|\Z)/$1$Cover$2/g;
        $TypeName_Covered=~s/(\W|\A)\Q$TypeName\E(\w|\Z)/$1$Cover $2/g;
    }
    return formatName($TypeName_Covered);
}

sub getNodeType($)
{
    return $LibInfo{$Version}{"info_type"}{$_[0]};
}

sub getNodeIntCst($)
{
    my $CstId = $_[0];
    my $CstTypeId = getTreeAttr($CstId, "type");
    if($EnumMembName_Id{$Version}{$CstId}) {
        return $EnumMembName_Id{$Version}{$CstId};
    }
    elsif((my $Value = getTreeValue($CstId)) ne "")
    {
        if($Value eq "0")
        {
            if(getNodeType($CstTypeId) eq "boolean_type") {
                return "false";
            }
            else {
                return "0";
            }
        }
        elsif($Value eq "1")
        {
            if(getNodeType($CstTypeId) eq "boolean_type") {
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
        { # string length is N-1 because of the null terminator
            return substr($1, 0, $2-1);
        }
    }
    return "";
}

sub getMemPtrAttr($$$$)
{ # function, method and field pointers
    my ($PtrId, $TypeDeclId, $TypeId, $Type) = @_;
    my $MemInfo = $LibInfo{$Version}{"info"}{$PtrId};
    if($Type eq "FieldPtr") {
        $MemInfo = $LibInfo{$Version}{"info"}{$TypeId};
    }
    my $MemInfo_Type = $LibInfo{$Version}{"info_type"}{$PtrId};
    my $MemPtrName = "";
    my %TypeAttr = ("Size"=>$WORD_SIZE{$Version}, "Type"=>$Type, "TDid"=>$TypeDeclId, "Tid"=>$TypeId);
    if($Type eq "MethodPtr")
    { # size of "method pointer" may be greater than WORD size
        $TypeAttr{"Size"} = getSize($TypeId)/$BYTE_SIZE;
    }
    # Return
    if($Type eq "FieldPtr")
    {
        my %ReturnAttr = getTypeAttr(getTypeDeclId($PtrId), $PtrId);
        $MemPtrName .= $ReturnAttr{"Name"};
        $TypeAttr{"Return"} = $PtrId;
    }
    else
    {
        if($MemInfo=~/retn[ ]*:[ ]*\@(\d+) /)
        {
            my $ReturnTypeId = $1;
            my %ReturnAttr = getTypeAttr(getTypeDeclId($ReturnTypeId), $ReturnTypeId);
            $MemPtrName .= $ReturnAttr{"Name"};
            $TypeAttr{"Return"} = $ReturnTypeId;
        }
    }
    # Class
    if($MemInfo=~/(clas|cls)[ ]*:[ ]*@(\d+) /)
    {
        $TypeAttr{"Class"} = $2;
        my %Class = getTypeAttr(getTypeDeclId($TypeAttr{"Class"}), $TypeAttr{"Class"});
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
            my $ParamTypeInfoId = $1;
            my $Position = 0;
            while($ParamTypeInfoId)
            {
                my $ParamTypeInfo = $LibInfo{$Version}{"info"}{$ParamTypeInfoId};
                last if($ParamTypeInfo!~/valu[ ]*:[ ]*@(\d+) /);
                my $ParamTypeId = $1;
                my %ParamAttr = getTypeAttr(getTypeDeclId($ParamTypeId), $ParamTypeId);
                last if($ParamAttr{"Name"} eq "void");
                if($Position!=0 or $Type ne "MethodPtr")
                {
                    $TypeAttr{"Param"}{$Position}{"type"} = $ParamTypeId;
                    push(@ParamTypeName, $ParamAttr{"Name"});
                }
                last if($ParamTypeInfo!~/(chan|chain)[ ]*:[ ]*@(\d+) /);
                $ParamTypeInfoId = $2;
                $Position+=1;
            }
        }
        $MemPtrName .= " (".join(", ", @ParamTypeName).")";
    }
    $TypeAttr{"Name"} = formatName($MemPtrName);
    return %TypeAttr;
}

sub getTreeTypeName($)
{
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /) {
            return getNameByInfo($1);
        }
        elsif($LibInfo{$Version}{"info_type"}{$_[0]} eq "integer_type")
        {
            if($Info=~/unsigned/) {
                return "unsigned int";
            }
            else {
                return "int";
            }
        }
    }
    return "";
}

sub getTypeType($$)
{
    my ($TypeDeclId, $TypeId) = @_;
    if($MissedTypedef{$Version}{$TypeId}{"TDid"}
    and $MissedTypedef{$Version}{$TypeId}{"TDid"} eq $TypeDeclId)
    { # support for old GCC versions
        return "Typedef";
    }
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if($Info and $Info=~/unql[ ]*:/ and $Info!~/qual[ ]*:/
    and getNameByInfo($TypeDeclId)) {
        return "Typedef";
    }
    elsif(my ($Qual, $To) = getQual($TypeId))
    {
        if($Qual eq "const volatile") {
            return "ConstVolatile";
        }
        else {
            return ucfirst($Qual);
        }
    }
    my $TypeType = getTypeTypeByTypeId($TypeId);
    if($TypeType eq "Struct")
    {
        if($TypeDeclId
        and $LibInfo{$Version}{"info_type"}{$TypeDeclId} eq "template_decl") {
            return "Template";
        }
        else {
            return "Struct";
        }
    }
    else {
        return $TypeType;
    }
}

sub getQual($)
{
    my $TypeId = $_[0];
    my %UnQual = (
        "r"=>"restrict",
        "v"=>"volatile",
        "c"=>"const",
        "cv"=>"const volatile"
    );
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

sub selectBaseType($$)
{
    my ($TypeDeclId, $TypeId) = @_;
    if($MissedTypedef{$Version}{$TypeId}{"TDid"}
    and $MissedTypedef{$Version}{$TypeId}{"TDid"} eq $TypeDeclId) {
        return ($TypeId, getTypeDeclId($TypeId), "");
    }
    my $TInfo = $LibInfo{$Version}{"info"}{$TypeId};
    my ($Qual, $To) = getQual($TypeId);
    if(($Qual or $To) and $TInfo=~/name[ ]*:[ ]*\@(\d+) /
    and (getTypeId($1) ne $TypeId)) {
        return (getTypeId($1), $1, $Qual);
    }
    elsif($TInfo!~/qual[ ]*:/
    and $TInfo=~/unql[ ]*:[ ]*\@(\d+) /
    and getNameByInfo($TypeDeclId))
    { # typedefs
        return ($1, getTypeDeclId($1), "");
    }
    elsif($Qual or $To) {
        return ($To, getTypeDeclId($To), $Qual);
    }
    elsif($LibInfo{$Version}{"info_type"}{$TypeId} eq "reference_type")
    {
        if($TInfo=~/refd[ ]*:[ ]*@(\d+) /) {
            return ($1, getTypeDeclId($1), "&");
        }
        else {
            return (0, 0, "");
        }
    }
    elsif($LibInfo{$Version}{"info_type"}{$TypeId} eq "array_type")
    {
        if($TInfo=~/elts[ ]*:[ ]*@(\d+) /) {
            return ($1, getTypeDeclId($1), "");
        }
        else {
            return (0, 0, "");
        }
    }
    elsif($LibInfo{$Version}{"info_type"}{$TypeId} eq "pointer_type")
    {
        if($TInfo=~/ptd[ ]*:[ ]*@(\d+) /) {
            return ($1, getTypeDeclId($1), "*");
        }
        else {
            return (0, 0, "");
        }
    }
    else {
        return (0, 0, "");
    }
}

sub getSymbolInfo_All()
{
    foreach (sort {int($b)<=>int($a)} keys(%{$LibInfo{$Version}{"info"}}))
    { # reverse order
        if($LibInfo{$Version}{"info_type"}{$_} eq "function_decl") {
            getSymbolInfo("$_");
        }
    }
}

sub getVarInfo_All()
{
    foreach (sort {int($b)<=>int($a)} keys(%{$LibInfo{$Version}{"info"}}))
    { # reverse order
        if($LibInfo{$Version}{"info_type"}{$_} eq "var_decl") {
            getVarInfo("$_");
        }
    }
}

sub isBuiltIn($) {
    return ($_[0] and $_[0]=~/\<built\-in\>|\<internal\>|\A\./);
}

sub getVarInfo($)
{
    my $InfoId = $_[0];
    if(my $NSid = getNameSpaceId($InfoId))
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
    my $ShortName = $SymbolInfo{$Version}{$InfoId}{"ShortName"} = getVarShortName($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"ShortName"}=~/\Atmp_add_class_\d+\Z/) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    $SymbolInfo{$Version}{$InfoId}{"MnglName"} = getFuncMnglName($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}
    and $SymbolInfo{$Version}{$InfoId}{"MnglName"}!~/\A_Z/)
    { # validate mangled name
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    $SymbolInfo{$Version}{$InfoId}{"Data"} = 1;
    $SymbolInfo{$Version}{$InfoId}{"Return"} = getTypeId($InfoId);
    if(not $SymbolInfo{$Version}{$InfoId}{"Return"}) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    set_Class_And_Namespace($InfoId);
    if($LibInfo{$Version}{"info"}{$InfoId}=~/ lang:[ ]*C /i) {
        $SymbolInfo{$Version}{$InfoId}{"Lang"} = "C";
    }
    if($UserLang and $UserLang eq "C")
    { # --lang=C option
        $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
    }
    if($COMMON_LANGUAGE{$Version} eq "C++")
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
        { # for some symbols (_ZTI) the short name is the mangled name
            if($ShortName=~/\A_Z/) {
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
    if(not $CheckHeadersOnly
    and not link_symbol($SymbolInfo{$Version}{$InfoId}{"MnglName"}, $Version, "-Deps"))
    {
        if(link_symbol($ShortName, $Version, "-Deps")
        and $SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/_ZL\d+$ShortName\Z/)
        { # "const" global data is mangled as _ZL... in the TU dump
          # but not mangled when compiling a C shared library
            $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $ShortName;
        }
        elsif($BinaryOnly)
        { # --binary: remove src-only symbols
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"}) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(my $AddedTid = $MissedTypedef{$Version}{$SymbolInfo{$Version}{$InfoId}{"Return"}}{"Tid"}) {
        $SymbolInfo{$Version}{$InfoId}{"Return"} = $AddedTid;
    }
    setFuncAccess($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A_ZTV/) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    if($ShortName=~/\A(_Z|\?)/) {
        delete($SymbolInfo{$Version}{$InfoId}{"ShortName"});
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
    $TypeAttr{"Type"} = getTypeType($TypeInfoId, $TypeId);
    $TypeAttr{"Name"}=~s/<(.+)\Z//g; # GCC 3.4.4 add template params to the name
    if(isAnon($TypeAttr{"Name"}))
    {
        my $NameSpaceId = $TypeId;
        while(my $NSId = getNameSpaceId(getTypeDeclId($NameSpaceId)))
        { # searching for a first not anon scope
            if($NSId eq $NameSpaceId) {
                last;
            }
            else
            {
                $TypeAttr{"NameSpace"} = getNameSpace(getTypeDeclId($TypeId));
                if(not $TypeAttr{"NameSpace"}
                or isNotAnon($TypeAttr{"NameSpace"})) {
                    last;
                }
            }
            $NameSpaceId=$NSId;
        }
    }
    else
    {
        if(my $NameSpaceId = getNameSpaceId($TypeInfoId))
        {
            if($NameSpaceId ne $TypeId) {
                $TypeAttr{"NameSpace"} = getNameSpace($TypeInfoId);
            }
        }
    }
    if($TypeAttr{"NameSpace"} and isNotAnon($TypeAttr{"Name"})) {
        $TypeAttr{"Name"} = $TypeAttr{"NameSpace"}."::".$TypeAttr{"Name"};
    }
    $TypeAttr{"Name"} = formatName($TypeAttr{"Name"});
    if(isAnon($TypeAttr{"Name"}))
    { # anon-struct-header.h-line
        $TypeAttr{"Name"} = "anon-".lc($TypeAttr{"Type"})."-";
        $TypeAttr{"Name"} .= $TypeAttr{"Header"}."-".$TypeAttr{"Line"};
        if($TypeAttr{"NameSpace"}) {
            $TypeAttr{"Name"} = $TypeAttr{"NameSpace"}."::".$TypeAttr{"Name"};
        }
    }
    if(defined $TemplateInstance{$Version}{$TypeInfoId}{$TypeId})
    {
        my @TParams = getTParams($TypeInfoId, $TypeId);
        if(not @TParams)
        { # template declarations with abstract params
            # vector (tree_vec) of template_type_parm nodes in the TU dump
            return ("", "");
        }
        $TypeAttr{"Name"} = formatName($TypeAttr{"Name"}."< ".join(", ", @TParams)." >");
    }
    return ($TypeAttr{"Name"}, $TypeAttr{"NameSpace"});
}

sub getTrivialTypeAttr($$)
{
    my ($TypeInfoId, $TypeId) = @_;
    my %TypeAttr = ();
    if(getTypeTypeByTypeId($TypeId)!~/\A(Intrinsic|Union|Struct|Enum|Class)\Z/) {
        return ();
    }
    setTypeAccess($TypeId, \%TypeAttr);
    ($TypeAttr{"Header"}, $TypeAttr{"Line"}) = getLocation($TypeInfoId);
    if(isBuiltIn($TypeAttr{"Header"}))
    {
        delete($TypeAttr{"Header"});
        delete($TypeAttr{"Line"});
    }
    $TypeAttr{"Type"} = getTypeType($TypeInfoId, $TypeId);
    ($TypeAttr{"Name"}, $TypeAttr{"NameSpace"}) = getTrivialName($TypeInfoId, $TypeId);
    if(not $TypeAttr{"Name"}) {
        return ();
    }
    if(not $TypeAttr{"NameSpace"}) {
        delete($TypeAttr{"NameSpace"});
    }
    if(my $Size = getSize($TypeId)) {
        $TypeAttr{"Size"} = $Size/$BYTE_SIZE;
    }
    if($TypeAttr{"Type"} eq "Struct"
    and detect_lang($TypeId))
    {
        $TypeAttr{"Type"} = "Class";
        $TypeAttr{"Copied"} = 1;# default, will be changed in getSymbolInfo()
    }
    if($TypeAttr{"Type"} eq "Struct"
    or $TypeAttr{"Type"} eq "Class") {
        setBaseClasses($TypeInfoId, $TypeId, \%TypeAttr);
    }
    setSpec($TypeId, \%TypeAttr);
    setTypeMemb($TypeId, \%TypeAttr);
    $TypeAttr{"Tid"} = $TypeId;
    $TypeAttr{"TDid"} = $TypeInfoId;
    if($TypeInfoId) {
        $Tid_TDid{$Version}{$TypeId} = $TypeInfoId;
    }
    if(not $TName_Tid{$Version}{$TypeAttr{"Name"}}) {
        $TName_Tid{$Version}{$TypeAttr{"Name"}} = $TypeId;
    }
    if(my $VTable = $ClassVTable_Content{$Version}{$TypeAttr{"Name"}})
    {
        my @Entries = split(/\n/, $VTable);
        foreach (1 .. $#Entries)
        {
            my $Entry = $Entries[$_];
            if($Entry=~/\A(\d+)\s+(.+)\Z/) {
                $TypeAttr{"VTable"}{$1} = $2;
            }
        }
    }
    return %TypeAttr;
}

sub detect_lang($)
{
    my $TypeId = $_[0];
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if(check_gcc_version($GCC_PATH, "4"))
    { # GCC 4 fncs-node points to only non-artificial methods
        return ($Info=~/(fncs)[ ]*:[ ]*@(\d+) /);
    }
    else
    { # GCC 3
        my $Fncs = getTreeAttr($TypeId, "fncs");
        while($Fncs)
        {
            my $Info = $LibInfo{$Version}{"info"}{$Fncs};
            if($Info!~/artificial/) {
                return 1;
            }
            $Fncs = getTreeAttr($Fncs, "chan");
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

sub setBaseClasses($$$)
{
    my ($TypeInfoId, $TypeId, $TypeAttr) = @_;
    my $Info = $LibInfo{$Version}{"info"}{$TypeId};
    if($Info=~/binf[ ]*:[ ]*@(\d+) /)
    {
        $Info = $LibInfo{$Version}{"info"}{$1};
        my $Pos = 0;
        while($Info=~s/(pub|public|prot|protected|priv|private|)[ ]+binf[ ]*:[ ]*@(\d+) //)
        {
            my ($Access, $BInfoId) = ($1, $2);
            my $ClassId = getBinfClassId($BInfoId);
            my $BaseInfo = $LibInfo{$Version}{"info"}{$BInfoId};
            if($Access=~/prot/)
            {
                $TypeAttr->{"Base"}{$ClassId}{"access"} = "protected";
            }
            elsif($Access=~/priv/)
            {
                $TypeAttr->{"Base"}{$ClassId}{"access"} = "private";
            }
            $TypeAttr->{"Base"}{$ClassId}{"pos"} = $Pos++;
            if($BaseInfo=~/virt/)
            { # virtual base
                $TypeAttr->{"Base"}{$ClassId}{"virtual"} = 1;
            }
            $Class_SubClasses{$Version}{$ClassId}{$TypeId}=1;
        }
    }
}

sub getBinfClassId($)
{
    my $Info = $LibInfo{$Version}{"info"}{$_[0]};
    $Info=~/type[ ]*:[ ]*@(\d+) /;
    return $1;
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
            my %PType = get_PureType($Tid_TDid{$Version}{$PId}, $PId, $Version);
            my $PTName = unmangledFormat($PType{"Name"}, $Version);
            $PTName=~s/(\A|\W)(restrict|register)(\W|\Z)/$1$3/g;
            if($Compiler eq "MSVC") {
                $PTName=~s/(\W|\A)long long(\W|\Z)/$1__int64$2/;
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
        my $ClassName = unmangledFormat(get_TypeName($ClassId, $Version), $Version);
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
    elsif(defined $TemplateInstance_Func{$Version}{$InfoId}
    and keys(%{$TemplateInstance_Func{$Version}{$InfoId}}))
    {
        $ShowReturn=1;
    }
    if($ShowReturn)
    { # mangled names for template function specializations include return value
        if(my $ReturnId = $SymbolInfo{$Version}{$InfoId}{"Return"})
        {
            my %RType = get_PureType($Tid_TDid{$Version}{$ReturnId}, $ReturnId, $Version);
            my $ReturnName = unmangledFormat($RType{"Name"}, $Version);
            $PureSignature = $ReturnName." ".$PureSignature;
        }
    }
    return ($Cache{"modelUnmangled"}{$Version}{$Compiler}{$InfoId} = formatName($PureSignature));
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
        $Mangled = mangle_symbol_gcc($InfoId, $LibVersion);
    }
    elsif($Compiler eq "MSVC") {
        $Mangled = mangle_symbol_msvc($InfoId, $LibVersion);
    }
    return ($Cache{"mangle_symbol"}{$LibVersion}{$InfoId}{$Compiler} = $Mangled);
}

sub mangle_symbol_msvc($$)
{
    my ($InfoId, $LibVersion) = @_;
    return "";
}

sub mangle_symbol_gcc($$)
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
    my ($ShortName, $TmplParams) = template_base($SymbolInfo{$LibVersion}{$InfoId}{"ShortName"});
    my @TParams = getTParams_Func($InfoId);
    if(not @TParams and $TmplParams)
    { # support for old ABI dumps
        @TParams = separate_params($TmplParams, 0);
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
            if(get_TypeAttr($Return, $LibVersion, "Type") eq "Const")
            { # "const" global data is mangled as _ZL...
                $Mangled .= "L";
            }
        }
        elsif(($NameSpace eq "__gnu_cxx"
        or $ShortName=~/\A__(gthrw|gthread)_/)
        and not $ClassId)
        { # _ZN9__gnu_cxxL25__exchange_and_add_singleEPii
          # _ZN9__gnu_cxxL19__atomic_add_singleEPii
          # _ZL19__gthrw_sched_yieldv
          # _ZL21__gthread_setspecificjPKv
            $Mangled .= "L";
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
    if(@TParams) {
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
            $Mangled=~s/C1E/C2E/;
        }
    }
    elsif($SymbolInfo{$LibVersion}{$InfoId}{"Destructor"})
    {
        if($MangledNames{$LibVersion}{$Mangled}) {
            $Mangled=~s/D0E/D1E/;
        }
        if($MangledNames{$LibVersion}{$Mangled}) {
            $Mangled=~s/D1E/D2E/;
        }
    }
    return $Mangled;
}

sub template_base($)
{ # NOTE: std::_Vector_base<mysqlpp::mysql_type_info>::_Vector_impl
  # NOTE: operator<<
    my $Name = $_[0];
    if($Name!~/>\Z/) {
        return $Name;
    }
    my $TParams = $Name;
    while(my $CPos = detect_center($TParams, "<")) {
        $TParams = substr($TParams, $CPos);
    }
    $Name=~s/\Q$TParams\E\Z//;
    $TParams=~s/\A<(.+)>\Z/$1/;
    return ($Name, $TParams);
}

sub get_sub_ns($)
{
    my $Name = $_[0];
    my @NS = ();
    while(my $CPos = detect_center($Name, ":"))
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
    my %BaseType = get_BaseType($Tid_TDid{$LibVersion}{$PTid}, $PTid, $LibVersion);
    my $BaseType_Name = $BaseType{"Name"};
    if(not $BaseType_Name) {
        return "";
    }
    my ($ShortName, $TmplParams) = template_base($BaseType_Name);
    my $Suffix = get_BaseTypeQual($Tid_TDid{$LibVersion}{$PTid}, $PTid, $LibVersion);
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
        my @TParams = getTParams($BaseType{"TDid"}, $BaseType{"Tid"});
        if(not @TParams and $TmplParams)
        { # support for old ABI dumps
            @TParams = separate_params($TmplParams, 0);
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
    $TypeName=~s/(\W|\A)(enum |struct |union |class )/$1/g;
    return $TypeName;
}

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

sub uncover_typedefs($$)
{
    my ($TypeName, $LibVersion) = @_;
    return "" if(not $TypeName);
    if(defined $Cache{"uncover_typedefs"}{$LibVersion}{$TypeName}) {
        return $Cache{"uncover_typedefs"}{$LibVersion}{$TypeName};
    }
    my ($TypeName_New, $TypeName_Pre) = (formatName($TypeName), "");
    while($TypeName_New ne $TypeName_Pre)
    {
        $TypeName_Pre = $TypeName_New;
        my $TypeName_Copy = $TypeName_New;
        my %Words = ();
        while($TypeName_Copy=~s/(\W|\A)([a-z_][\w:]*)(\W|\Z)//io)
        {
            my $Word = $2;
            next if(not $Word or $Intrinsic_Keywords{$Word});
            $Words{$Word} = 1;
        }
        foreach my $Word (keys(%Words))
        {
            my $BaseType_Name = $Typedef_BaseName{$LibVersion}{$Word};
            next if(not $BaseType_Name);
            next if($TypeName_New=~/(\A|\W)(struct|union|enum)\s\Q$Word\E(\W|\Z)/);
            if($BaseType_Name=~/\([\*]+\)/)
            { # FuncPtr
                if($TypeName_New=~/\Q$Word\E(.*)\Z/)
                {
                    my $Type_Suffix = $1;
                    $TypeName_New = $BaseType_Name;
                    if($TypeName_New=~s/\(([\*]+)\)/($1 $Type_Suffix)/) {
                        $TypeName_New = formatName($TypeName_New);
                    }
                }
            }
            else
            {
                if($TypeName_New=~s/(\W|\A)\Q$Word\E(\W|\Z)/$1$BaseType_Name$2/g) {
                    $TypeName_New = formatName($TypeName_New);
                }
            }
        }
    }
    return ($Cache{"uncover_typedefs"}{$LibVersion}{$TypeName} = $TypeName_New);
}

sub isInternal($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    return 0 if($FuncInfo!~/mngl[ ]*:[ ]*@(\d+) /);
    my $FuncMnglNameInfoId = $1;
    return ($LibInfo{$Version}{"info"}{$FuncMnglNameInfoId}=~/\*[ ]*INTERNAL[ ]*\*/);
}

sub set_Class_And_Namespace($)
{
    my $InfoId = $_[0];
    if($LibInfo{$Version}{"info"}{$InfoId}=~/scpe[ ]*:[ ]*@(\d+) /)
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
    if($SymbolInfo{$Version}{$InfoId}{"Class"}
    or $SymbolInfo{$Version}{$InfoId}{"NameSpace"})
    { # identify language
        setLanguage($Version, "C++");
    }
}

sub debugType($$)
{
    my ($Tid, $LibVersion) = @_;
    my %Type = get_Type($Tid_TDid{$LibVersion}{$Tid}, $Tid, $LibVersion);
    printMsg("INFO", Dumper(\%Type));
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
        my $Unmngl1 = modelUnmangled($Mangled{$Mngl}, "GCC");
        my $Unmngl2 = $tr_name{$Mngl};
        if($Unmngl1 ne $Unmngl2) {
            printMsg("INFO", "INCORRECT MANGLING:\n  $Mngl\n  $Unmngl1\n  $Unmngl2\n");
        }
    }
}

sub linkSymbol($)
{ # link symbols from shared libraries
  # with the symbols from header files
    my $InfoId = $_[0];
    if(my $Lang = $SymbolInfo{$Version}{$InfoId}{"Lang"})
    {
        if($Lang eq "C")
        { # extern "C"
            return $SymbolInfo{$Version}{$InfoId}{"ShortName"};
        }
    }
    # try to mangle symbol
    if((not check_gcc_version($GCC_PATH, "4") and $SymbolInfo{$Version}{$InfoId}{"Class"})
    or (check_gcc_version($GCC_PATH, "4") and not $SymbolInfo{$Version}{$InfoId}{"Class"}))
    { # 1. GCC 3.x doesn't mangle class methods names in the TU dump (only functions and global data)
      # 2. GCC 4.x doesn't mangle C++ functions in the TU dump (only class methods) except extern "C" functions
        if($CheckHeadersOnly)
        {
            if(my $Mangled = mangle_symbol($InfoId, $Version, "GCC")) {
                return $Mangled;
            }
        }
        else
        {
            if(my $Mangled = $mangled_name_gcc{modelUnmangled($InfoId, "GCC")}) {
                return correct_incharge($InfoId, $Version, $Mangled);
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
    return if(isInternal($InfoId));
    ($SymbolInfo{$Version}{$InfoId}{"Header"}, $SymbolInfo{$Version}{$InfoId}{"Line"}) = getLocation($InfoId);
    if(not $SymbolInfo{$Version}{$InfoId}{"Header"}
    or isBuiltIn($SymbolInfo{$Version}{$InfoId}{"Header"})) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    setFuncAccess($InfoId);
    setFuncKind($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"PseudoTemplate"}) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    $SymbolInfo{$Version}{$InfoId}{"Type"} = getFuncType($InfoId);
    $SymbolInfo{$Version}{$InfoId}{"Return"} = getFuncReturn($InfoId);
    if(my $AddedTid = $MissedTypedef{$Version}{$SymbolInfo{$Version}{$InfoId}{"Return"}}{"Tid"}) {
        $SymbolInfo{$Version}{$InfoId}{"Return"} = $AddedTid;
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Return"}) {
        delete($SymbolInfo{$Version}{$InfoId}{"Return"});
    }
    $SymbolInfo{$Version}{$InfoId}{"ShortName"} = getFuncShortName(getFuncOrig($InfoId));
    if($SymbolInfo{$Version}{$InfoId}{"ShortName"}=~/\._/) {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(defined $TemplateInstance_Func{$Version}{$InfoId})
    {
        my @TParams = getTParams_Func($InfoId);
        if(not @TParams) {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
        my $PrmsInLine = join(", ", @TParams);
        $SymbolInfo{$Version}{$InfoId}{"ShortName"} .= "<".$PrmsInLine.">";
        $SymbolInfo{$Version}{$InfoId}{"ShortName"} = formatName($SymbolInfo{$Version}{$InfoId}{"ShortName"});
    }
    else
    { # support for GCC 3.4
        $SymbolInfo{$Version}{$InfoId}{"ShortName"}=~s/<.+>\Z//;
    }
    $SymbolInfo{$Version}{$InfoId}{"MnglName"} = getFuncMnglName($InfoId);
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}
    and $SymbolInfo{$Version}{$InfoId}{"MnglName"}!~/\A_Z/)
    {
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if($SymbolInfo{$InfoId}{"MnglName"} and not $STDCXX_TESTING)
    { # stdc++ interfaces
        if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A(_ZS|_ZNS|_ZNKS)/) {
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if(not $SymbolInfo{$Version}{$InfoId}{"Destructor"})
    { # destructors have an empty parameter list
        my $Skip = setFuncParams($InfoId);
        if($CheckHeadersOnly and $Skip)
        { # skip template symbols that cannot be
          # filtered without access to the library
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    set_Class_And_Namespace($InfoId);
    if(not $CheckHeadersOnly and $SymbolInfo{$Version}{$InfoId}{"Type"} eq "Function"
    and not $SymbolInfo{$Version}{$InfoId}{"Class"}
    and link_symbol($SymbolInfo{$Version}{$InfoId}{"ShortName"}, $Version, "-Deps"))
    { # functions (C++): not mangled in library, but are mangled in TU dump
        if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"}
        or not link_symbol($SymbolInfo{$Version}{$InfoId}{"MnglName"}, $Version, "-Deps")) {
            $SymbolInfo{$Version}{$InfoId}{"MnglName"} = $SymbolInfo{$Version}{$InfoId}{"ShortName"};
        }
    }
    if($LibInfo{$Version}{"info"}{$InfoId}=~/ lang:[ ]*C /i) {
        $SymbolInfo{$Version}{$InfoId}{"Lang"} = "C";
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
    if(not $SymbolInfo{$Version}{$InfoId}{"MnglName"})
    { # can't detect symbol name
        delete($SymbolInfo{$Version}{$InfoId});
        return;
    }
    if(getFuncSpec($InfoId) eq "Virt")
    { # virtual methods
        $SymbolInfo{$Version}{$InfoId}{"Virt"} = 1;
    }
    if(getFuncSpec($InfoId) eq "PureVirt")
    { # pure virtual methods
        $SymbolInfo{$Version}{$InfoId}{"PureVirt"} = 1;
    }
    if(isInline($InfoId)) {
        $SymbolInfo{$Version}{$InfoId}{"InLine"} = 1;
    }
    if($SymbolInfo{$Version}{$InfoId}{"Constructor"}
    and my $ClassId = $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"InLine"}
        and $LibInfo{$Version}{"info"}{$InfoId}!~/ artificial /i)
        { # inline or auto-generated constructor
            delete($TypeInfo{$Version}{$Tid_TDid{$Version}{$ClassId}}{$ClassId}{"Copied"});
        }
    }
    if(not $CheckHeadersOnly and $BinaryOnly
    and not link_symbol($SymbolInfo{$Version}{$InfoId}{"MnglName"}, $Version, "-Deps"))
    {
        if(not $SymbolInfo{$Version}{$InfoId}{"Virt"}
        and not $SymbolInfo{$Version}{$InfoId}{"PureVirt"})
        { # removing src only and external non-virtual functions
          # non-virtual template instances going here
            delete($SymbolInfo{$Version}{$InfoId});
            return;
        }
    }
    if($SymbolInfo{$Version}{$InfoId}{"Type"} eq "Method"
    or $SymbolInfo{$Version}{$InfoId}{"Constructor"}
    or $SymbolInfo{$Version}{$InfoId}{"Destructor"}
    or $SymbolInfo{$Version}{$InfoId}{"Class"})
    {
        if($SymbolInfo{$Version}{$InfoId}{"MnglName"}!~/\A(_Z|\?)/) {
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
            if($Unmangled=~/\.\_\d/) {
                delete($SymbolInfo{$Version}{$InfoId});
                return;
            }
        }
    }
    delete($SymbolInfo{$Version}{$InfoId}{"Type"});
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A_ZN(V|)K/) {
        $SymbolInfo{$Version}{$InfoId}{"Const"} = 1;
    }
    if($SymbolInfo{$Version}{$InfoId}{"MnglName"}=~/\A_ZN(K|)V/) {
        $SymbolInfo{$Version}{$InfoId}{"Volatile"} = 1;
    }
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
    my ($Position, $UnnamedPos) = (0, 0);
    if($TypeType eq "Enum")
    {
        my $TypeMembInfoId = getEnumMembInfoId($TypeId);
        while($TypeMembInfoId)
        {
            $TypeAttr->{"Memb"}{$Position}{"value"} = getEnumMembVal($TypeMembInfoId);
            my $MembName = getEnumMembName($TypeMembInfoId);
            $TypeAttr->{"Memb"}{$Position}{"name"} = getEnumMembName($TypeMembInfoId);
            $EnumMembName_Id{$Version}{getTreeAttr($TypeMembInfoId, "valu")} = ($TypeAttr->{"NameSpace"})?$TypeAttr->{"NameSpace"}."::".$MembName:$MembName;
            $TypeMembInfoId = getNextMembInfoId($TypeMembInfoId);
            $Position += 1;
        }
    }
    elsif($TypeType=~/\A(Struct|Class|Union)\Z/)
    {
        my $TypeMembInfoId = getStructMembInfoId($TypeId);
        while($TypeMembInfoId)
        {
            if($LibInfo{$Version}{"info_type"}{$TypeMembInfoId} ne "field_decl") {
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            my $StructMembName = getStructMembName($TypeMembInfoId);
            if($StructMembName=~/_vptr\./)
            { # virtual tables
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            if(not $StructMembName)
            { # unnamed fields
                if($TypeAttr->{"Name"}!~/_type_info_pseudo/)
                {
                    my $UnnamedTid = getTreeAttr($TypeMembInfoId, "type");
                    my $UnnamedTName = getNameByInfo(getTypeDeclId($UnnamedTid));
                    if(isAnon($UnnamedTName))
                    { # rename unnamed fields to unnamed0, unnamed1, ...
                        $StructMembName = "unnamed".($UnnamedPos++);
                    }
                }
            }
            if(not $StructMembName)
            { # unnamed fields and base classes
                $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
                next;
            }
            my $MembTypeId = getTreeAttr($TypeMembInfoId, "type");
            if(my $AddedTid = $MissedTypedef{$Version}{$MembTypeId}{"Tid"}) {
                $MembTypeId = $AddedTid;
            }
            $TypeAttr->{"Memb"}{$Position}{"type"} = $MembTypeId;
            $TypeAttr->{"Memb"}{$Position}{"name"} = $StructMembName;
            if((my $Access = getTreeAccess($TypeMembInfoId)) ne "public")
            { # marked only protected and private, public by default
                $TypeAttr->{"Memb"}{$Position}{"access"} = $Access;
            }
            if(my $BFSize = getStructMembBitFieldSize($TypeMembInfoId)) {
                $TypeAttr->{"Memb"}{$Position}{"bitfield"} = $BFSize;
            }
            else
            { # set alignment for non-bit fields
              # alignment for bitfields is always equal to 1 bit
                $TypeAttr->{"Memb"}{$Position}{"algn"} = getAlgn($TypeMembInfoId)/$BYTE_SIZE;
            }
            $TypeMembInfoId = getNextStructMembInfoId($TypeMembInfoId);
            $Position += 1;
        }
    }
}

sub setFuncParams($)
{
    my $InfoId = $_[0];
    my $ParamInfoId = getFuncParamInfoId($InfoId);
    my $FunctionType = getFuncType($InfoId);
    if($FunctionType eq "Method")
    { # check type of "this" pointer
        my $ObjectTypeId = getFuncParamType($ParamInfoId);
        if(get_TypeName($ObjectTypeId, $Version)=~/(\A|\W)const(| volatile)\*const(\W|\Z)/) {
            $SymbolInfo{$Version}{$InfoId}{"Const"} = 1;
        }
        if(get_TypeName($ObjectTypeId, $Version)=~/(\A|\W)volatile(\W|\Z)/) {
            $SymbolInfo{$Version}{$InfoId}{"Volatile"} = 1;
        }
        $ParamInfoId = getNextElem($ParamInfoId);
    }
    my ($Position, $Vtt_Pos) = (0, -1);
    while($ParamInfoId)
    {
        my $ParamTypeId = getFuncParamType($ParamInfoId);
        my $ParamName = getFuncParamName($ParamInfoId);
        if($TypeInfo{$Version}{getTypeDeclId($ParamTypeId)}{$ParamTypeId}{"Name"} eq "void") {
            last;
        }
        if(my $AddedTid = $MissedTypedef{$Version}{$ParamTypeId}{"Tid"}) {
            $ParamTypeId = $AddedTid;
        }
        my $PType = get_TypeAttr($ParamTypeId, $Version, "Type");
        if(not $PType or $PType eq "Unknown") {
            return 1;
        }
        if($ParamName eq "__vtt_parm"
        and get_TypeName($ParamTypeId, $Version) eq "void const**")
        {
            $Vtt_Pos = $Position;
            $ParamInfoId = getNextElem($ParamInfoId);
            next;
        }
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"type"} = $ParamTypeId;
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"name"} = $ParamName;
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"algn"} = getAlgn($ParamInfoId)/$BYTE_SIZE;
        if(not $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"name"}) {
            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"name"} = "p".($Position+1);
        }
        if($LibInfo{$Version}{"info"}{$ParamInfoId}=~/spec:\s*register /)
        { # foo(register type arg)
            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"reg"} = 1;
        }
        $ParamInfoId = getNextElem($ParamInfoId);
        $Position += 1;
    }
    if(detect_nolimit_args($InfoId, $Vtt_Pos)) {
        $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"type"} = -1;
    }
    return 0;
}

sub detect_nolimit_args($$)
{
    my ($InfoId, $Vtt_Pos) = @_;
    my $FuncTypeId = getFuncTypeId($InfoId);
    my $ParamListElemId = getTreeAttr($FuncTypeId, "prms");
    if(getFuncType($InfoId) eq "Method") {
        $ParamListElemId = getNextElem($ParamListElemId);
    }
    return 1 if(not $ParamListElemId);# foo(...)
    my $HaveVoid = 0;
    my $Position = 0;
    while($ParamListElemId)
    {
        if($Vtt_Pos!=-1 and $Position==$Vtt_Pos)
        {
            $Vtt_Pos=-1;
            $ParamListElemId = getNextElem($ParamListElemId);
            next;
        }
        my $ParamTypeId = getTreeAttr($ParamListElemId, "valu");
        if(my $PurpId = getTreeAttr($ParamListElemId, "purp"))
        {
            if(my $PurpType = $LibInfo{$Version}{"info_type"}{$PurpId})
            {
                if($PurpType eq "integer_cst") {
                    $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"default"} = getTreeValue($PurpId);
                }
                elsif($PurpType eq "string_cst") {
                    $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"default"} = getNodeStrCst($PurpId);
                }
            }
        }
        if($TypeInfo{$Version}{getTypeDeclId($ParamTypeId)}{$ParamTypeId}{"Name"} eq "void")
        {
            $HaveVoid = 1;
            last;
        }
        elsif(not defined $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"type"})
        {
            $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"type"} = $ParamTypeId;
            if(not $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"name"}) {
                $SymbolInfo{$Version}{$InfoId}{"Param"}{$Position}{"name"} = "p".($Position+1);
            }
        }
        $ParamListElemId = getNextElem($ParamListElemId);
        $Position += 1;
    }
    return ($Position>=1 and not $HaveVoid);
}

sub getTreeAttr($$)
{
    my $Attr = $_[1];
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/\Q$Attr\E\s*:\s*\@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getTreeValue($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/low[ ]*:[ ]*([^ ]+) /) {
            return $1;
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

sub getFuncSpec($)
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

sub getFuncClass($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/scpe[ ]*:[ ]*@(\d+) /) {
            return $1;
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

sub getNextElem($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/(chan|chain)[ ]*:[ ]*@(\d+) /) {
            return $2;
        }
    }
    return "";
}

sub getFuncParamInfoId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/args[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getFuncParamType($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/type[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getFuncParamName($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /) {
            return getTreeStr($1);
        }
    }
    return "";
}

sub getEnumMembInfoId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/csts[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getStructMembInfoId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/flds[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub get_IntNameSpace($$)
{
    my ($Interface, $LibVersion) = @_;
    return "" if(not $Interface or not $LibVersion);
    if(defined $Cache{"get_IntNameSpace"}{$Interface}{$LibVersion}) {
        return $Cache{"get_IntNameSpace"}{$Interface}{$LibVersion};
    }
    my $Signature = get_Signature($Interface, $LibVersion);
    if($Signature=~/\:\:/)
    {
        my $FounNameSpace = 0;
        foreach my $NameSpace (sort {get_depth($b)<=>get_depth($a)} keys(%{$NestedNameSpaces{$LibVersion}}))
        {
            if($Signature=~/(\A|\s+for\s+)\Q$NameSpace\E\:\:/) {
                return ($Cache{"get_IntNameSpace"}{$Interface}{$LibVersion} = $NameSpace);
            }
        }
    }
    else {
        return ($Cache{"get_IntNameSpace"}{$Interface}{$LibVersion} = "");
    }
}

sub parse_TypeNameSpace($$)
{
    my ($TypeName, $LibVersion) = @_;
    return "" if(not $TypeName or not $LibVersion);
    if(defined $Cache{"parse_TypeNameSpace"}{$TypeName}{$LibVersion}) {
        return $Cache{"parse_TypeNameSpace"}{$TypeName}{$LibVersion};
    }
    if($TypeName=~/\:\:/)
    {
        my $FounNameSpace = 0;
        foreach my $NameSpace (sort {get_depth($b)<=>get_depth($a)} keys(%{$NestedNameSpaces{$LibVersion}}))
        {
            if($TypeName=~/\A\Q$NameSpace\E\:\:/) {
                return ($Cache{"parse_TypeNameSpace"}{$TypeName}{$LibVersion} = $NameSpace);
            }
        }
    }
    else {
        return ($Cache{"parse_TypeNameSpace"}{$TypeName}{$LibVersion} = "");
    }
}

sub getNameSpace($)
{
    my $TypeInfoId = $_[0];
    my $NSInfoId = getTreeAttr($TypeInfoId, "scpe");
    return "" if(not $NSInfoId);
    if(my $InfoType = $LibInfo{$Version}{"info_type"}{$NSInfoId})
    {
        if($InfoType eq "namespace_decl")
        {
            if($LibInfo{$Version}{"info"}{$NSInfoId}=~/name[ ]*:[ ]*@(\d+) /)
            {
                my $NameSpace = getTreeStr($1);
                return "" if($NameSpace eq "::");
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
        elsif($InfoType eq "record_type")
        { # inside data type
            my ($Name, $NameNS) = getTrivialName(getTypeDeclId($NSInfoId), $NSInfoId);
            return $Name;
        }
    }
    return "";
}

sub getNameSpaceId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/scpe[ ]*:[ ]*\@(\d+)/) {
            return $1;
        }
    }
    return "";
}

sub getEnumMembName($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/purp[ ]*:[ ]*\@(\d+)/) {
            return getTreeStr($1);
        }
    }
    return "";
}

sub getStructMembName($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*\@(\d+)/) {
            return getTreeStr($1);
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

sub getStructMembBitFieldSize($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/ bitfield /) {
            return getSize($_[0]);
        }
    }
    return 0;
}

sub getNextMembInfoId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/(chan|chain)[ ]*:[ ]*@(\d+) /) {
            return $2;
        }
    }
    return "";
}

sub getNextStructMembInfoId($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/(chan|chain)[ ]*:[ ]*@(\d+) /) {
            return $2;
        }
    }
    return "";
}

sub register_header($$)
{ # input: header absolute path, relative path or name
    my ($Header, $LibVersion) = @_;
    return "" if(not $Header);
    if(is_abs($Header) and not -f $Header) {
        exitStatus("Access_Error", "can't access \'$Header\'");
    }
    return "" if(skip_header($Header, $LibVersion));
    my $Header_Path = identify_header($Header, $LibVersion);
    return "" if(not $Header_Path);
    detect_header_includes($Header_Path, $LibVersion);
    if(my $RHeader_Path = $Header_ErrorRedirect{$LibVersion}{$Header_Path})
    {
        return "" if(skip_header($RHeader_Path, $LibVersion));
        $Header_Path = $RHeader_Path;
        return "" if($Registered_Headers{$LibVersion}{$Header_Path}{"Identity"});
    }
    elsif($Header_ShouldNotBeUsed{$LibVersion}{$Header_Path}) {
        return "";
    }
    $Registered_Headers{$LibVersion}{$Header_Path}{"Identity"} = get_filename($Header_Path);
    $HeaderName_Paths{$LibVersion}{get_filename($Header_Path)}{$Header_Path} = 1;
    if(($Header=~/\.(\w+)\Z/ and $1 ne "h")
    or $Header!~/\.(\w+)\Z/)
    { # hpp, hh
        setLanguage($LibVersion, "C++");
    }
    if($CheckHeadersOnly
    and $Header=~/(\A|\/)c\+\+(\/|\Z)/)
    { # /usr/include/c++/4.6.1/...
        $STDCXX_TESTING = 1;
    }
    return $Header_Path;
}

sub register_directory($$$)
{
    my ($Dir, $WithDeps, $LibVersion) = @_;
    $Dir=~s/[\/\\]+\Z//g;
    return if(not $LibVersion or not $Dir or not -d $Dir);
    return if(skip_header($Dir, $LibVersion));
    $Dir = get_abs_path($Dir);
    my $Mode = "All";
    if($WithDeps) {
        if($RegisteredDirs{$LibVersion}{$Dir}{1}) {
            return;
        }
        elsif($RegisteredDirs{$LibVersion}{$Dir}{0}) {
            $Mode = "DepsOnly";
        }
    }
    else {
        if($RegisteredDirs{$LibVersion}{$Dir}{1}
        or $RegisteredDirs{$LibVersion}{$Dir}{0}) {
            return;
        }
    }
    $Header_Dependency{$LibVersion}{$Dir} = 1;
    $RegisteredDirs{$LibVersion}{$Dir}{$WithDeps} = 1;
    if($Mode eq "DepsOnly")
    {
        foreach my $Path (cmd_find($Dir,"d","","")) {
            $Header_Dependency{$LibVersion}{$Path} = 1;
        }
        return;
    }
    foreach my $Path (sort {length($b)<=>length($a)} cmd_find($Dir,"f","",""))
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
        next if(skip_header($Path, $LibVersion));
        # Neighbors
        foreach my $Part (get_path_prefixes($Path)) {
            $Include_Neighbors{$LibVersion}{$Part} = $Path;
        }
    }
    if(get_filename($Dir) eq "include")
    { # search for "lib/include/" directory
        my $LibDir = $Dir;
        if($LibDir=~s/([\/\\])include\Z/$1lib/g and -d $LibDir) {
            register_directory($LibDir, $WithDeps, $LibVersion);
        }
    }
}

sub parse_redirect($$$)
{
    my ($Content, $Path, $LibVersion) = @_;
    if(defined $Cache{"parse_redirect"}{$LibVersion}{$Path}) {
        return $Cache{"parse_redirect"}{$LibVersion}{$Path};
    }
    return "" if(not $Content);
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
        |is\ in|use)\ (<[^<>]+>|[\w\-\/\\]+\.($HEADER_EXT))/ix)
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
         |should\ not\ be\ used
         |cannot\ be\ included\ directly/ix and not /\ from\ /i) {
            $Header_ShouldNotBeUsed{$LibVersion}{$Path} = 1;
        }
    }
    $Redirect=~s/\A<//g;
    $Redirect=~s/>\Z//g;
    return ($Cache{"parse_redirect"}{$LibVersion}{$Path} = $Redirect);
}

sub parse_includes($$)
{
    my ($Content, $Path) = @_;
    my %Includes = ();
    while($Content=~s/#([ \t]*)(include|include_next|import)([ \t]*)(<|")([^<>"]+)(>|")//)
    {# C/C++: include, Objective C/C++: import directive
        my ($Header, $Method) = ($5, $4);
        $Header = path_format($Header, $OSgroup);
        if(($Method eq "\"" and -e joinPath(get_dirname($Path), $Header))
        or is_abs($Header)) {
        # include "path/header.h" that doesn't exist is equal to include <path/header.h>
            $Includes{$Header} = -1;
        }
        else {
            $Includes{$Header} = 1;
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

sub sort_by_word($$)
{
    my ($ArrRef, $W) = @_;
    return if(length($W)<2);
    @{$ArrRef} = sort {get_filename($b)=~/\Q$W\E/i<=>get_filename($a)=~/\Q$W\E/i} @{$ArrRef};
}

sub natural_sorting($$)
{
    my ($H1, $H2) = @_;
    $H1=~s/\.[a-z]+\Z//ig;
    $H2=~s/\.[a-z]+\Z//ig;
    my ($HDir1, $Hname1) = separate_path($H1);
    my ($HDir2, $Hname2) = separate_path($H2);
    my $Dirname1 = get_filename($HDir1);
    my $Dirname2 = get_filename($HDir2);
    if($H1 eq $H2) {
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
    {# include/glib-2.0/glib.h
        return -1;
    }
    elsif($HDir2=~/\Q$Hname2\E/i
    and $HDir1!~/\Q$Hname1\E/i)
    {# include/glib-2.0/glib.h
        return 1;
    }
    elsif($Hname1=~/\Q$Dirname1\E/i
    and $Hname2!~/\Q$Dirname2\E/i)
    {# include/hildon-thumbnail/hildon-thumbnail-factory.h
        return -1;
    }
    elsif($Hname2=~/\Q$Dirname2\E/i
    and $Hname1!~/\Q$Dirname1\E/i)
    {# include/hildon-thumbnail/hildon-thumbnail-factory.h
        return 1;
    }
    elsif($Hname1=~/(config|lib)/i
    and $Hname2!~/(config|lib)/i)
    {# include/alsa/asoundlib.h
        return -1;
    }
    elsif($Hname2=~/(config|lib)/i
    and $Hname1!~/(config|lib)/i)
    {# include/alsa/asoundlib.h
        return 1;
    }
    elsif(checkRelevance($H1)
    and not checkRelevance($H2))
    {# libebook/e-book.h
        return -1;
    }
    elsif(checkRelevance($H2)
    and not checkRelevance($H1))
    {# libebook/e-book.h
        return 1;
    }
    else {
        return (lc($H1) cmp lc($H2));
    }
}

sub searchForHeaders($)
{
    my $LibVersion = $_[0];
    # gcc standard include paths
    find_gcc_cxx_headers($LibVersion);
    # processing header paths
    foreach my $Path (keys(%{$Descriptor{$LibVersion}{"IncludePaths"}}),
    keys(%{$Descriptor{$LibVersion}{"AddIncludePaths"}}))
    {
        my $IPath = $Path;
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        elsif(-f $Path) {
            exitStatus("Access_Error", "\'$Path\' - not a directory");
        }
        elsif(-d $Path)
        {
            $Path = get_abs_path($Path);
            register_directory($Path, 0, $LibVersion);
            if($Descriptor{$LibVersion}{"AddIncludePaths"}{$IPath}) {
                $Add_Include_Paths{$LibVersion}{$Path} = 1;
            }
            else {
                $Include_Paths{$LibVersion}{$Path} = 1;
            }
        }
    }
    if(keys(%{$Include_Paths{$LibVersion}})) {
        $INC_PATH_AUTODETECT{$LibVersion} = 0;
    }
    # registering directories
    foreach my $Path (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Headers"}))
    {
        next if(not -e $Path);
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        if(-d $Path) {
            register_directory($Path, 1, $LibVersion);
        }
        elsif(-f $Path)
        {
            my $Dir = get_dirname($Path);
            if(not $SystemPaths{"include"}{$Dir}
            and not $LocalIncludes{$Dir})
            {
                register_directory($Dir, 1, $LibVersion);
                if(my $OutDir = get_dirname($Dir))
                { # registering the outer directory
                    if(not $SystemPaths{"include"}{$OutDir}
                    and not $LocalIncludes{$OutDir}) {
                        register_directory($OutDir, 0, $LibVersion);
                    }
                }
            }
        }
    }
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
            if(my $HPath = register_header($Dest, $LibVersion)) {
                $Registered_Headers{$LibVersion}{$HPath}{"Pos"} = $Position++;
            }
        }
        elsif(-d $Dest)
        {
            my @Registered = ();
            foreach my $Path (cmd_find($Dest,"f","",""))
            {
                next if(ignore_path($Path));
                next if(not is_header($Path, 0, $LibVersion));
                if(my $HPath = register_header($Path, $LibVersion)) {
                    push(@Registered, $HPath);
                }
            }
            @Registered = sort {natural_sorting($a, $b)} @Registered;
            sort_by_word(\@Registered, $TargetLibraryShortName);
            foreach my $Path (@Registered) {
                $Registered_Headers{$LibVersion}{$Path}{"Pos"} = $Position++;
            }
        }
        else {
            exitStatus("Access_Error", "can't identify \'$Dest\' as a header file");
        }
    }
    if(my $HList = $Descriptor{$LibVersion}{"IncludePreamble"})
    { # preparing preamble headers
        my $PPos=0;
        foreach my $Header (split(/\s*\n\s*/, $HList))
        {
            if(is_abs($Header) and not -f $Header) {
                exitStatus("Access_Error", "can't access file \'$Header\'");
            }
            $Header = path_format($Header, $OSgroup);
            if(my $Header_Path = is_header($Header, 1, $LibVersion))
            {
                next if(skip_header($Header_Path, $LibVersion));
                $Include_Preamble{$LibVersion}{$Header_Path}{"Position"} = $PPos++;
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
                { # all names are differend with current prefix
                    foreach my $Path (keys(%{$HeaderName_Paths{$LibVersion}{$Header_Name}})) {
                        $Registered_Headers{$LibVersion}{$Path}{"Identity"} = $Identity{$Path};
                    }
                    last;
                }
                $Prefix = $NewPrefix; # increase prefix
            }
        }
    }
    foreach my $HeaderName (keys(%{$Include_Order{$LibVersion}}))
    { # ordering headers according to descriptor
        my $PairName=$Include_Order{$LibVersion}{$HeaderName};
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
    $Cache{"detect_real_includes"}{$LibVersion}{$AbsPath}=1;
    return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
}

sub detect_header_includes($$)
{
    my ($Path, $LibVersion) = @_;
    return if(not $LibVersion or not $Path or not -e $Path);
    return if($Cache{"detect_header_includes"}{$LibVersion}{$Path});
    my $Content = readFile($Path);
    if($Content=~/#[ \t]*error[ \t]+/ and (my $Redirect = parse_redirect($Content, $Path, $LibVersion)))
    {# detecting error directive in the headers
        if(my $RedirectPath = identify_header($Redirect, $LibVersion))
        {
            if($RedirectPath=~/\/usr\/include\// and $Path!~/\/usr\/include\//) {
                $RedirectPath = identify_header(get_filename($Redirect), $LibVersion);
            }
            if($RedirectPath ne $Path) {
                $Header_ErrorRedirect{$LibVersion}{$Path} = $RedirectPath;
            }
        }
    }
    my $Inc = parse_includes($Content, $Path);
    foreach my $Include (keys(%{$Inc}))
    {# detecting includes
        #if(is_not_header($Include))
        #{ #include<*.c> and others
            # next;
        #}
        $Header_Includes{$LibVersion}{$Path}{$Include} = $Inc->{$Include};
    }
    $Cache{"detect_header_includes"}{$LibVersion}{$Path} = 1;
}

sub simplify_path($)
{
    my $Path = $_[0];
    while($Path=~s&([\/\\])[^\/\\]+[\/\\]\.\.[\/\\]&$1&){};
    return $Path;
}

sub fromLibc($)
{ # GLIBC header
    my $Path = $_[0];
    my ($Dir, $Name) = separate_path($Path);
    if(get_filename($Dir)=~/\A(include|libc)\Z/ and $GlibcHeader{$Name})
    { # /usr/include/{stdio, ...}.h
      # epoc32/include/libc/{stdio, ...}.h
        return 1;
    }
    if(isLibcDir($Dir)) {
        return 1;
    }
    return 0;
}

sub isLibcDir($)
{ # GLIBC directory
    my $Dir = $_[0];
    my ($OutDir, $Name) = separate_path($Dir);
    if(get_filename($OutDir)=~/\A(include|libc)\Z/
    and ($Name=~/\Aasm(|-.+)\Z/ or $GlibcDir{$Name}))
    { # /usr/include/{sys,bits,asm,asm-*}/*.h
        return 1;
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
    { # GLIBC internals
        return ();
    }
    if(keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}})) {
        return keys(%{$RecursiveIncludes{$LibVersion}{$AbsPath}});
    }
    return () if($OSgroup ne "windows" and $Name=~/windows|win32|win64/i);
    return () if($MAIN_CPP_DIR and $AbsPath=~/\A\Q$MAIN_CPP_DIR\E/ and not $STDCXX_TESTING);
    push(@RecurInclude, $AbsPath);
    if($DefaultGccPaths{$AbsDir}
    or fromLibc($AbsPath))
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
        my $HPath = "";
        if($Header_Includes{$LibVersion}{$AbsPath}{$Include}==-1)
        { # for #include "..."
            my $Candidate = joinPath($AbsDir, $Include);
            if(-f $Candidate) {
                $HPath = simplify_path($Candidate);
            }
        }
        elsif($Header_Includes{$LibVersion}{$AbsPath}{$Include}==1
        and $Include=~/[\/\\]/) # and not find_in_defaults($Include)
        { # search for the nearest header
          # QtCore/qabstractanimation.h includes <QtCore/qobject.h>
            my $Candidate = joinPath(get_dirname($AbsDir), $Include);
            if(-f $Candidate) {
                $HPath = $Candidate;
            }
        }
        if(not $HPath) {
            $HPath = identify_header($Include, $LibVersion);
        }
        next if(not $HPath);
        if($HPath eq $AbsPath) {
            next;
        }
        $RecursiveIncludes{$LibVersion}{$AbsPath}{$HPath} = 1;
        if($Header_Includes{$LibVersion}{$AbsPath}{$Include}==1)
        { # only include <...>, skip include "..." prefixes
            $Header_Include_Prefix{$LibVersion}{$AbsPath}{$HPath}{get_dirname($Include)} = 1;
        }
        foreach my $IncPath (detect_recursive_includes($HPath, $LibVersion))
        {
            if($IncPath eq $AbsPath) {
                next;
            }
            $RecursiveIncludes{$LibVersion}{$AbsPath}{$IncPath} = 1;
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
    foreach my $Dir (sort {get_depth($a)<=>get_depth($b)}
    (keys(%DefaultIncPaths), keys(%DefaultGccPaths), keys(%DefaultCppPaths), keys(%UserIncPath)))
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
    my ($Path) = @_;
    return 0 if(not $Path);
    if($SystemRoot) {
        $Path=~s/\A\Q$SystemRoot\E//g;
    }
    my ($Dir, $Name) = separate_path($Path);
    $Name=~s/\.\w+\Z//g;# remove extension (.h)
    my @Tokens = split(/[_\d\W]+/, $Name);
    foreach (@Tokens)
    {
        next if(not $_);
        if($Dir=~/(\A|lib|[_\d\W])\Q$_\E([_\d\W]|lib|\Z)/i
        or length($_)>=4 and $Dir=~/\Q$_\E/i)
        { # include/gupnp-1.0/libgupnp/gupnp-context.h
          # include/evolution-data-server-1.4/libebook/e-book.h
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
    if($OStarget ne "bsd") {
        if($Candidate=~/[\/\\]include[\/\\]bsd[\/\\]/)
        { # openssh: skip /usr/lib/bcc/include/bsd/signal.h
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
{
    my ($Header, $LibVersion) = @_;
    return $Header if(-f $Header);
    return "" if(is_abs($Header) and not -f $Header);
    return "" if($Header=~/\A(atomic|config|configure|build|conf|setup)\.h\Z/i);
    if($OSgroup ne "windows")
    {
        if(get_filename($Header)=~/windows|win32|win64|\A(dos|process|winsock|config-win)\.h\Z/i) {
            return "";
        }
        elsif($Header=~/\A(mem)\.h\Z/)
        { # pngconf.h include mem.h for __MSDOS__
            return "";
        }
    }
    if($OSgroup ne "solaris")
    {
        if($Header=~/\A(thread)\.h\Z/)
        { # thread.h in Solaris
            return "";
        }
    }
    if(defined $Cache{"selectSystemHeader"}{$LibVersion}{$Header}) {
        return $Cache{"selectSystemHeader"}{$LibVersion}{$Header};
    }
    foreach my $Path (keys(%{$SystemPaths{"include"}}))
    { # search in default paths
        if(-f $Path."/".$Header) {
            return ($Cache{"selectSystemHeader"}{$LibVersion}{$Header} = joinPath($Path,$Header));
        }
    }
    if(not keys(%SystemHeaders)) {
        detectSystemHeaders();
    }
    foreach my $Candidate (sort {get_depth($a)<=>get_depth($b)}
    sort {cmp_paths($b, $a)} getSystemHeaders($Header, $LibVersion))
    {
        if(isRelevant($Header, $Candidate, $LibVersion)) {
            return ($Cache{"selectSystemHeader"}{$LibVersion}{$Header} = $Candidate);
        }
    }
    return ($Cache{"selectSystemHeader"}{$LibVersion}{$Header} = ""); # error
}

sub getSystemHeaders($$)
{
    my ($Header, $LibVersion) = @_;
    my @Candidates = ();
    foreach my $Candidate (sort keys(%{$SystemHeaders{$Header}}))
    {
        if(skip_header($Candidate, $LibVersion)) {
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
    return ($DefaultGccPaths{$Dir} or $DefaultCppPaths{$Dir} or $DefaultIncPaths{$Dir});
}

sub identify_header($$)
{
    my ($Header, $LibVersion) = @_;
    $Header=~s/\A(\.\.[\\\/])+//g;
    if(defined $Cache{"identify_header"}{$Header}{$LibVersion}) {
        return $Cache{"identify_header"}{$Header}{$LibVersion};
    }
    my $Path = identify_header_internal($Header, $LibVersion);
    if(not $Path and $OSgroup eq "macos" and my $Dir = get_dirname($Header))
    { # search in frameworks: "OpenGL/gl.h" is "OpenGL.framework/Headers/gl.h"
        my $RelPath = "Headers\/".get_filename($Header);
        if(my $HeaderDir = find_in_framework($RelPath, $Dir.".framework", $LibVersion)) {
            $Path = joinPath($HeaderDir, $RelPath);
        }
    }
    return ($Cache{"identify_header"}{$Header}{$LibVersion} = $Path);
}

sub identify_header_internal($$)
{ # search for header by absolute path, relative path or name
    my ($Header, $LibVersion) = @_;
    return "" if(not $Header);
    if(-f $Header)
    { # it's relative or absolute path
        return get_abs_path($Header);
    }
    elsif($GlibcHeader{$Header} and not $GLIBC_TESTING
    and my $HeaderDir = find_in_defaults($Header))
    { # search for libc headers in the /usr/include
      # for non-libc target library before searching
      # in the library paths
        return joinPath($HeaderDir,$Header);
    }
    elsif(my $Path = $Include_Neighbors{$LibVersion}{$Header})
    { # search in the target library paths
        return $Path;
    }
    elsif($DefaultGccHeader{$Header})
    { # search in the internal GCC include paths
        return $DefaultGccHeader{$Header};
    }
    elsif(my $DefaultDir = find_in_defaults($Header))
    { # search in the default GCC include paths
        return joinPath($DefaultDir,$Header);
    }
    elsif($DefaultCppHeader{$Header})
    { # search in the default G++ include paths
        return $DefaultCppHeader{$Header};
    }
    elsif(my $AnyPath = selectSystemHeader($Header, $LibVersion))
    { # search everywhere in the system
        return $AnyPath;
    }
    else
    { # cannot find anything
        return "";
    }
}

sub getLocation($)
{
    if($_[0] and my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/srcp[ ]*:[ ]*([\w\-\<\>\.\+\/\\]+):(\d+) /) {
            return ($1, $2);
        }
    }
    return ();
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

sub getNameByInfo($)
{
    if(my $Info = $LibInfo{$Version}{"info"}{$_[0]})
    {
        if($Info=~/name[ ]*:[ ]*@(\d+) /)
        {
            if(my $NInfo = $LibInfo{$Version}{"info"}{$1})
            {
                if($NInfo=~/strg[ ]*:[ ]*(.*?)[ ]+lngt/)
                { # short unsigned int (may include spaces)
                    return $1;
                }
            }
        }
    }
    return "";
}

sub getTreeStr($)
{
    my $Info = $LibInfo{$Version}{"info"}{$_[0]};
    if($Info=~/strg[ ]*:[ ]*([^ ]*)/)
    {
        my $Str = $1;
        if($C99Mode{$Version}
        and $Str=~/\Ac99_(.+)\Z/) {
            if($CppKeywords_A{$1}) {
                $Str=$1;
            }
        }
        return $Str;
    }
    else {
        return "";
    }
}

sub getVarShortName($)
{
    my $VarInfo = $LibInfo{$Version}{"info"}{$_[0]};
    return "" if($VarInfo!~/name[ ]*:[ ]*@(\d+) /);
    return getTreeStr($1);
}

sub getFuncShortName($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    if($FuncInfo=~/ operator /)
    {
        if($FuncInfo=~/ conversion /) {
            return "operator ".get_TypeName($SymbolInfo{$Version}{$_[0]}{"Return"}, $Version);
        }
        else
        {
            return "" if($FuncInfo!~/ operator[ ]+([a-zA-Z]+) /);
            return "operator".$Operator_Indication{$1};
        }
    }
    else
    {
        return "" if($FuncInfo!~/name[ ]*:[ ]*@(\d+) /);
        return getTreeStr($1);
    }
}

sub getFuncMnglName($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    return "" if($FuncInfo!~/mngl[ ]*:[ ]*@(\d+) /);
    return getTreeStr($1);
}

sub getFuncReturn($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    if($FuncInfo=~/type[ ]*:[ ]*@(\d+) /) {
        if($LibInfo{$Version}{"info"}{$1}=~/retn[ ]*:[ ]*@(\d+) /) {
            return $1;
        }
    }
    return "";
}

sub getFuncOrig($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    if($FuncInfo=~/orig[ ]*:[ ]*@(\d+) /) {
        return $1;
    }
    else {
        return $_[0];
    }
}

sub unmangleSymbol($)
{
    my $Symbol = $_[0];
    my @Unmngl = unmangleArray($Symbol);
    return $Unmngl[0];
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
        return split(/\n/, `$UndNameCmd 0x8386 $TMP_DIR/unmangle`);
    }
    else
    { # GCC mangling
        my $CppFiltCmd = get_CmdPath("c++filt");
        if(not $CppFiltCmd) {
            exitStatus("Not_Found", "can't find c++filt in PATH");
        }
        my $Info = `$CppFiltCmd -h 2>&1`;
        if($Info=~/\@<file>/)
        {# new version of c++filt can take a file
            my $NoStrip = "";
            if($OSgroup eq "macos"
            or $OSgroup eq "windows") {
                $NoStrip = "-n";
            }
            writeFile("$TMP_DIR/unmangle", join("\n", @_));
            return split(/\n/, `$CppFiltCmd $NoStrip \@\"$TMP_DIR/unmangle\"`);
        }
        else
        { # old-style unmangling
            if($#_>$MAX_COMMAND_LINE_ARGUMENTS) {
                my @Half = splice(@_, 0, ($#_+1)/2);
                return (unmangleArray(@Half), unmangleArray(@_))
            }
            else
            {
                my $NoStrip = "";
                if($OSgroup eq "macos"
                or $OSgroup eq "windows") {
                    $NoStrip = "-n";
                }
                my $Strings = join(" ", @_);
                return split(/\n/, `$CppFiltCmd $NoStrip $Strings`);
            }
        }
    }
}

sub get_SignatureNoInfo($$)
{
    my ($Interface, $LibVersion) = @_;
    if($Cache{"get_SignatureNoInfo"}{$LibVersion}{$Interface}) {
        return $Cache{"get_SignatureNoInfo"}{$LibVersion}{$Interface};
    }
    my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Interface);
    my $Signature = $tr_name{$MnglName}?$tr_name{$MnglName}:$MnglName;
    if($Interface=~/\A(_Z|\?)/)
    { # C++
        $Signature=~s/\Qstd::basic_string<char, std::char_traits<char>, std::allocator<char> >\E/std::string/g;
        $Signature=~s/\Qstd::map<std::string, std::string, std::less<std::string >, std::allocator<std::pair<std::string const, std::string > > >\E/std::map<std::string, std::string>/g;
    }
    if(not $CheckObjectsOnly or $OSgroup=~/linux|bsd|beos/)
    { # ELF format marks data as OBJECT
        if($CompleteSignature{$LibVersion}{$Interface}{"Object"}) {
            $Signature .= " [data]";
        }
        elsif($Interface!~/\A(_Z|\?)/) {
            $Signature .= " (...)";
        }
    }
    if(my $ChargeLevel = get_ChargeLevel($Interface, $LibVersion))
    {
        my $ShortName = substr($Signature, 0, detect_center($Signature, "("));
        $Signature=~s/\A\Q$ShortName\E/$ShortName $ChargeLevel/g;
    }
    if($SymbolVersion) {
        $Signature .= $VersionSpec.$SymbolVersion;
    }
    return ($Cache{"get_SignatureNoInfo"}{$LibVersion}{$Interface} = $Signature);
}

sub get_ChargeLevel($$)
{
    my ($Interface, $LibVersion) = @_;
    return "" if($Interface!~/\A(_Z|\?)/);
    if(defined $CompleteSignature{$LibVersion}{$Interface}
    and $CompleteSignature{$LibVersion}{$Interface}{"Header"})
    {
        if($CompleteSignature{$LibVersion}{$Interface}{"Constructor"})
        {
            if($Interface=~/C1E/) {
                return "[in-charge]";
            }
            elsif($Interface=~/C2E/) {
                return "[not-in-charge]";
            }
        }
        elsif($CompleteSignature{$LibVersion}{$Interface}{"Destructor"})
        {
            if($Interface=~/D1E/) {
                return "[in-charge]";
            }
            elsif($Interface=~/D2E/) {
                return "[not-in-charge]";
            }
            elsif($Interface=~/D0E/) {
                return "[in-charge-deleting]";
            }
        }
    }
    else
    {
        if($Interface=~/C1E/) {
            return "[in-charge]";
        }
        elsif($Interface=~/C2E/) {
            return "[not-in-charge]";
        }
        elsif($Interface=~/D1E/) {
            return "[in-charge]";
        }
        elsif($Interface=~/D2E/) {
            return "[not-in-charge]";
        }
        elsif($Interface=~/D0E/) {
            return "[in-charge-deleting]";
        }
    }
    return "";
}

sub get_Signature($$)
{
    my ($Interface, $LibVersion) = @_;
    if($Cache{"get_Signature"}{$LibVersion}{$Interface}) {
        return $Cache{"get_Signature"}{$LibVersion}{$Interface};
    }
    my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Interface);
    if(skipGlobalData($MnglName) or not $CompleteSignature{$LibVersion}{$Interface}{"Header"}) {
        return get_SignatureNoInfo($Interface, $LibVersion);
    }
    my ($Func_Signature, @Param_Types_FromUnmangledName) = ();
    my $ShortName = $CompleteSignature{$LibVersion}{$Interface}{"ShortName"};
    if($Interface=~/\A(_Z|\?)/)
    {
        if(my $ClassId = $CompleteSignature{$LibVersion}{$Interface}{"Class"}) {
            $Func_Signature = get_TypeName($ClassId, $LibVersion)."::".(($CompleteSignature{$LibVersion}{$Interface}{"Destructor"})?"~":"").$ShortName;
        }
        elsif(my $NameSpace = $CompleteSignature{$LibVersion}{$Interface}{"NameSpace"}) {
            $Func_Signature = $NameSpace."::".$ShortName;
        }
        else {
            $Func_Signature = $ShortName;
        }
        @Param_Types_FromUnmangledName = get_s_params($tr_name{$MnglName}, 0);
    }
    else {
        $Func_Signature = $MnglName;
    }
    my @ParamArray = ();
    foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{$LibVersion}{$Interface}{"Param"}}))
    {
        next if($Pos eq "");
        my $ParamTypeId = $CompleteSignature{$LibVersion}{$Interface}{"Param"}{$Pos}{"type"};
        next if(not $ParamTypeId);
        my $ParamTypeName = get_TypeName($ParamTypeId, $LibVersion);
        if(not $ParamTypeName) {
            $ParamTypeName = $Param_Types_FromUnmangledName[$Pos];
        }
        foreach my $Typedef (keys(%ChangedTypedef))
        {
            my $Base = $Typedef_BaseName{$LibVersion}{$Typedef};
            $ParamTypeName=~s/(\A|\W)\Q$Typedef\E(\W|\Z)/$1$Base$2/g;
        }
        if(my $ParamName = $CompleteSignature{$LibVersion}{$Interface}{"Param"}{$Pos}{"name"}) {
            push(@ParamArray, create_member_decl($ParamTypeName, $ParamName));
        }
        else {
            push(@ParamArray, $ParamTypeName);
        }
    }
    if($CompleteSignature{$LibVersion}{$Interface}{"Data"}
    or $CompleteSignature{$LibVersion}{$Interface}{"Object"}) {
        $Func_Signature .= " [data]";
    }
    else
    {
        if(my $ChargeLevel = get_ChargeLevel($Interface, $LibVersion))
        { # add [in-charge]
            $Func_Signature .= " ".$ChargeLevel;
        }
        $Func_Signature .= " (".join(", ", @ParamArray).")";
        if($CompleteSignature{$LibVersion}{$Interface}{"Const"}
        or $Interface=~/\A_ZN(V|)K/) {
            $Func_Signature .= " const";
        }
        if($CompleteSignature{$LibVersion}{$Interface}{"Volatile"}
        or $Interface=~/\A_ZN(K|)V/) {
            $Func_Signature .= " volatile";
        }
        if($CompleteSignature{$LibVersion}{$Interface}{"Static"}
        and $Interface=~/\A(_Z|\?)/)
        {# for static methods
            $Func_Signature .= " [static]";
        }
    }
    if(defined $ShowRetVal
    and my $ReturnTId = $CompleteSignature{$LibVersion}{$Interface}{"Return"}) {
        $Func_Signature .= ":".get_TypeName($ReturnTId, $LibVersion);
    }
    if($SymbolVersion) {
        $Func_Signature .= $VersionSpec.$SymbolVersion;
    }
    return ($Cache{"get_Signature"}{$LibVersion}{$Interface} = $Func_Signature);
}

sub create_member_decl($$)
{
    my ($TName, $Member) = @_;
    if($TName=~/\([\*]+\)/) {
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
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    return "" if($FuncInfo!~/type[ ]*:[ ]*@(\d+) /);
    my $FuncTypeInfoId = $1;
    my $FunctionType = $LibInfo{$Version}{"info_type"}{$FuncTypeInfoId};
    if($FunctionType eq "method_type") {
        return "Method";
    }
    elsif($FunctionType eq "function_type") {
        return "Function";
    }
    else {
        return $FunctionType;
    }
}

sub getFuncTypeId($)
{
    my $FuncInfo = $LibInfo{$Version}{"info"}{$_[0]};
    if($FuncInfo=~/type[ ]*:[ ]*@(\d+)( |\Z)/) {
        return $1;
    }
    else {
        return 0;
    }
}

sub isNotAnon($) {
    return (not isAnon($_[0]));
}

sub isAnon($)
{# "._N" or "$_N" in older GCC versions
    return ($_[0]=~/(\.|\$)\_\d+|anon\-/);
}

sub unmangled_Compact($)
{ # Removes all non-essential (for C++ language) whitespace from a string.  If 
  # the whitespace is essential it will be replaced with exactly one ' ' 
  # character. Works correctly only for unmangled names.
    my $Name = $_[0];
    if(defined $Cache{"unmangled_Compact"}{$Name}) {
        return $Cache{"unmangled_Compact"}{$Name};
    }
    # First, we reduce all spaces that we can
    my $coms='[-()<>:*&~!|+=%@~"?.,/[^'."']";
    my $coms_nobr='[-()<:*&~!|+=%@~"?.,'."']";
    my $clos='[),;:\]]';
    $_ = $Name;
    s/^\s+//gm;
    s/\s+$//gm;
    s/((?!\n)\s)+/ /g;
    s/(\w+)\s+($coms+)/$1$2/gm;
    s/($coms+)\s+(\w+)/$1$2/gm;
    s/(\w)\s+($clos)/$1$2/gm;
    s/($coms+)\s+($coms+)/$1 $2/gm;
    s/($coms_nobr+)\s+($coms+)/$1$2/gm;
    s/($coms+)\s+($coms_nobr+)/$1$2/gm;
    # don't forget about >> and <:.  In unmangled names global-scope modifier 
    # is not used, so <: will always be a digraph and requires no special treatment.
    # We also try to remove other parts that are better to be removed here than in other places
    # double-cv
    s/\bconst\s+const\b/const/gm;
    s/\bvolatile\s+volatile\b/volatile/gm;
    s/\bconst\s+volatile\b\s+const\b/const volatile/gm;
    s/\bvolatile\s+const\b\s+volatile\b/const volatile/gm;
    # Place cv in proper order
    s/\bvolatile\s+const\b/const volatile/gm;
    return ($Cache{"unmangled_Compact"}{$Name} = $_);
}

sub unmangled_PostProcess($)
{
    my $Name = $_[0];
    $_ = $Name;
    #s/\bunsigned int\b/unsigned/g;
    s/\bshort unsigned int\b/unsigned short/g;
    s/\bshort int\b/short/g;
    s/\blong long unsigned int\b/unsigned long long/g;
    s/\blong unsigned int\b/unsigned long/g;
    s/\blong long int\b/long long/g;
    s/\blong int\b/long/g;
    s/\)const\b/\) const/g;
    s/\blong long unsigned\b/unsigned long long/g;
    s/\blong unsigned\b/unsigned long/g;
    return $_;
}

sub formatName($)
{# type name correction
    my $Name = $_[0];
    $Name=unmangled_Compact($Name);
    $Name=unmangled_PostProcess($Name);
    $Name=~s/>>/> >/g; # double templates
    $Name=~s/(operator\s*)> >/$1>>/;
    return $Name;
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
            $IncDir{$Dep}=1;
        }
    }
    $Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath} = sortIncPaths([keys(%IncDir)], $LibVersion);
    return @{$Cache{"get_HeaderDeps"}{$LibVersion}{$AbsPath}};
}

sub sortIncPaths($$)
{
    my ($ArrRef, $LibVersion) = @_;
    @{$ArrRef} = sort {$b cmp $a} @{$ArrRef};
    @{$ArrRef} = sort {get_depth($a)<=>get_depth($b)} @{$ArrRef};
    @{$ArrRef} = sort {$Header_Dependency{$LibVersion}{$b}<=>$Header_Dependency{$LibVersion}{$a}} @{$ArrRef};
    return $ArrRef;
}

sub joinPath($$) {
    return join($SLASH, @_);
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
        my $TypeDecl = $TypeDecl_Prefix."typedef int tmp_add_type_$AddNameSpaceId;".$TypeDecl_Suffix;
        my $FuncDecl = "$NS\:\:tmp_add_type_$AddNameSpaceId tmp_add_func_$AddNameSpaceId(){return 0;};";
        $Additions.="  $TypeDecl\n  $FuncDecl\n";
        $AddNameSpaceId+=1;
    }
    return $Additions;
}

sub path_format($$)
{ # forward slash to pass into MinGW GCC
    my ($Path, $Fmt) = @_;
    if($Fmt eq "windows")
    {
        $Path=~s/\//\\/g;
        $Path=lc($Path);
    }
    else {
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
        {# to Apple's GCC
            return "-F".esc(get_dirname($Path));
        }
        else {
            return "-I".esc($Path);
        }
    }
    elsif($Style eq "CL") {
        return "/I \"$Path\"";
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
# Other C structures appearing in every dump
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
    "siginfo"
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
    if(check_gcc_version($GCC_PATH, "4"))
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
    {# platform-specific options
        $GccCall .= " ".$Opts;
    }
    # allow extra qualifications
    # and other nonconformant code
    $GccCall .= " -fpermissive -w";
    if($NoStdInc)
    {
        $GccCall .= " -nostdinc";
        $GccCall .= " -nostdinc++";
    }
    if($CompilerOptions{$Version})
    { # user-defined options
        $GccCall .= " ".$CompilerOptions{$Version};
    }
    $GccCall .= " \"$Path\"";
    if($Inc)
    { # include paths
        $GccCall .= " ".$Inc;
    }
    return $GccCall;
}

sub getDump()
{
    if(not $GCC_PATH) {
        exitStatus("Error", "internal error - GCC path is not set");
    }
    my %HeaderElems = (
        # Types
        "stdio.h" => ["FILE", "va_list"],
        "stddef.h" => ["NULL"],
        "stdint.h" => ["uint32_t", "int32_t", "uint64_t"],
        "time.h" => ["time_t"],
        "sys/types.h" => ["ssize_t", "u_int32_t", "u_short", "u_char",
             "u_int", "off_t", "u_quad_t", "u_long", "size_t", "mode_t"],
        "unistd.h" => ["gid_t", "uid_t"],
        "stdbool.h" => ["_Bool"],
        "rpc/xdr.h" => ["bool_t"],
        "in_systm.h" => ["n_long", "n_short"],
        # Fields
        "arpa/inet.h" => ["fw_src", "ip_src"]
    );
    my %AutoPreamble = ();
    foreach (keys(%HeaderElems)) {
        foreach my $Elem (@{$HeaderElems{$_}}) {
            $AutoPreamble{$Elem}=$_;
        }
    }
    my $TmpHeaderPath = "$TMP_DIR/dump$Version.h";
    my $MHeaderPath = $TmpHeaderPath;
    open(LIB_HEADER, ">".$TmpHeaderPath) || die ("can't open file \'$TmpHeaderPath\': $!\n");
    if(my $AddDefines = $Descriptor{$Version}{"Defines"})
    {
        $AddDefines=~s/\n\s+/\n  /g;
        print LIB_HEADER "\n  // add defines\n  ".$AddDefines."\n";
    }
    print LIB_HEADER "\n  // add includes\n";
    my @PreambleHeaders = keys(%{$Include_Preamble{$Version}});
    @PreambleHeaders = sort {int($Include_Preamble{$Version}{$a}{"Position"})<=>int($Include_Preamble{$Version}{$b}{"Position"})} @PreambleHeaders;
    foreach my $Header_Path (@PreambleHeaders) {
        print LIB_HEADER "  #include \"".path_format($Header_Path, "unix")."\"\n";
    }
    my @Headers = keys(%{$Registered_Headers{$Version}});
    @Headers = sort {int($Registered_Headers{$Version}{$a}{"Pos"})<=>int($Registered_Headers{$Version}{$b}{"Pos"})} @Headers;
    foreach my $Header_Path (@Headers)
    {
        next if($Include_Preamble{$Version}{$Header_Path});
        print LIB_HEADER "  #include \"".path_format($Header_Path, "unix")."\"\n";
    }
    close(LIB_HEADER);
    my $IncludeString = getIncString(getIncPaths(@PreambleHeaders, @Headers), "GCC");
    if($Debug)
    { # debug mode
        writeFile($DEBUG_PATH{$Version}."/headers/direct-includes.txt", Dumper(\%Header_Includes));
        writeFile($DEBUG_PATH{$Version}."/headers/recursive-includes.txt", Dumper(\%RecursiveIncludes));
        writeFile($DEBUG_PATH{$Version}."/headers/include-paths.txt", Dumper($Cache{"get_HeaderDeps"}));
        writeFile($DEBUG_PATH{$Version}."/headers/default-paths.txt", Dumper(\%DefaultIncPaths));
    }
    # preprocessing stage
    checkPreprocessedUnit(callPreprocessor($TmpHeaderPath, $IncludeString, $Version));
    my $MContent = "";
    my $PreprocessCmd = getCompileCmd($TmpHeaderPath, "-E", $IncludeString);
    if($OStarget eq "windows"
    and get_dumpmachine($GCC_PATH)=~/mingw/i
    and $MinGWMode{$Version}!=-1)
    { # modify headers to compile by MinGW
        if(not $MContent)
        { # preprocessing
            $MContent = `$PreprocessCmd 2>$TMP_DIR/null`;
        }
        if($MContent=~s/__asm\s*(\{[^{}]*?\}|[^{};]*)//g)
        { # __asm { ... }
            $MinGWMode{$Version}=1;
        }
        if($MContent=~s/\s+(\/ \/.*?)\n/\n/g)
        { # comments after preprocessing
            $MinGWMode{$Version}=1;
        }
        if($MContent=~s/(\W)(0x[a-f]+|\d+)(i|ui)(8|16|32|64)(\W)/$1$2$5/g)
        { # 0xffui8
            $MinGWMode{$Version}=1;
        }
        if($MinGWMode{$Version}) {
            printMsg("INFO", "Using MinGW compatibility mode");
            $MHeaderPath = "$TMP_DIR/dump$Version.i";
        }
    }
    if(($COMMON_LANGUAGE{$Version} eq "C" or $CheckHeadersOnly)
    and $C99Mode{$Version}!=-1 and not $Cpp2003)
    { # rename C++ keywords in C code
        if(not $MContent)
        { # preprocessing
            $MContent = `$PreprocessCmd 2>$TMP_DIR/null`;
        }
        my $RegExp_C = join("|", keys(%CppKeywords_C));
        my $RegExp_F = join("|", keys(%CppKeywords_F));
        my $RegExp_O = join("|", keys(%CppKeywords_O));
        while($MContent=~s/(\A|\n[^\#\/\n][^\n]*?|\n)(\*\s*|\s+|\@|\,|\()($RegExp_C|$RegExp_F)(\s*(\,|\)|\;|\-\>|\.|\:\s*\d))/$1$2c99_$3$4/g)
        { # MATCH:
          # int foo(int new, int class, int (*new)(int));
          # unsigned private: 8;
          # DO NOT MATCH:
          # #pragma GCC visibility push(default)
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/([^\w\s]|\w\s+)(?<!operator )(delete)(\s*\()/$1c99_$2$3/g)
        { # MATCH:
          # int delete(...);
          # int explicit(...);
          # DO NOT MATCH:
          # void operator delete(...)
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/(\s+)($RegExp_O)(\s*(\;|\:))/$1c99_$2$3/g)
        { # MATCH:
          # int bool;
          # DO NOT MATCH:
          # bool X;
          # return *this;
          # throw;
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/(\s+)(operator)(\s*(\(\s*\)\s*[^\(\s]|\(\s*[^\)\s]))/$1c99_$2$3/g)
        { # MATCH:
          # int operator(...);
          # DO NOT MATCH:
          # int operator()(...);
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/([^\w\(\,\s]\s*|\s+)(operator)(\s*(\,\s*[^\(\s]|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(int operator);
          # int foo(int operator, int other);
          # DO NOT MATCH:
          # int operator,(...);
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/(\*\s*|\w\s+)(bool)(\s*(\,|\)))/$1c99_$2$3/g)
        { # MATCH:
          # int foo(gboolean *bool);
          # DO NOT MATCH:
          # void setTabEnabled(int index, bool);
            $C99Mode{$Version} = 1;
        }
        if($MContent=~s/(\w)([^\w\(\,\s]\s*|\s+)(this)(\s*(\,|\)))/$1$2c99_$3$4/g)
        { # MATCH:
          # int foo(int* this);
          # int bar(int this);
          # DO NOT MATCH:
          # baz(X, this);
            $C99Mode{$Version} = 1;
        }
        if($C99Mode{$Version}==1)
        { # try to change C++ "keyword" to "c99_keyword"
            printMsg("INFO", "Using C99 compatibility mode");
            $MHeaderPath = "$TMP_DIR/dump$Version.i";
        }
    }
    if($C99Mode{$Version}==1
    or $MinGWMode{$Version}==1)
    { # compile the corrected preprocessor output
        writeFile($MHeaderPath, $MContent);
    }
    if($COMMON_LANGUAGE{$Version} eq "C++")
    { # add classes and namespaces to the dump
        my $CHdump = "-fdump-class-hierarchy -c";
        if($C99Mode{$Version}==1
        or $MinGWMode{$Version}==1) {
            $CHdump .= " -fpreprocessed";
        }
        my $ClassHierarchyCmd = getCompileCmd($MHeaderPath, $CHdump, $IncludeString);
        chdir($TMP_DIR);
        system("$ClassHierarchyCmd >null 2>&1");
        chdir($ORIG_DIR);
        if(my $ClassDump = (cmd_find($TMP_DIR,"f","*.class",1))[0])
        {
            my %AddClasses = ();
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
                        $AddClasses{$CName} = 1;
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
            if($Debug)
            { # debug mode
                mkpath($DEBUG_PATH{$Version});
                copy($ClassDump, $DEBUG_PATH{$Version}."/class-hierarchy-dump.txt");
            }
            unlink($ClassDump);
            if(my $NS_Add = get_namespace_additions($TUnit_NameSpaces{$Version}))
            { # GCC on all supported platforms does not include namespaces to the dump by default
                appendFile($MHeaderPath, "\n  // add namespaces\n".$NS_Add);
            }
            # some GCC versions don't include class methods to the TU dump by default
            my ($AddClass, $ClassNum) = ("", 0);
            foreach my $CName (sort keys(%AddClasses))
            {
                next if($C_Structure{$CName});
                next if(not $STDCXX_TESTING and $CName=~/\Astd::/);
                next if(($CName=~tr![:]!!)>2);
                next if($SkipTypes{$Version}{$CName});
                if($CName=~/\A(.+)::[^:]+\Z/
                and $AddClasses{$1}) {
                    next;
                }
                $AddClass .= "  $CName* tmp_add_class_".($ClassNum++).";\n";
            }
            appendFile($MHeaderPath, "\n  // add classes\n".$AddClass);
        }
    }
    writeLog($Version, "Temporary header file \'$TmpHeaderPath\' with the following content will be compiled to create GCC translation unit dump:\n".readFile($TmpHeaderPath)."\n");
    # create TU dump
    my $TUdump = "-fdump-translation-unit -fkeep-inline-functions -c";
    if($C99Mode{$Version}==1
    or $MinGWMode{$Version}==1) {
        $TUdump .= " -fpreprocessed";
    }
    my $SyntaxTreeCmd = getCompileCmd($MHeaderPath, $TUdump, $IncludeString);
    writeLog($Version, "The GCC parameters:\n  $SyntaxTreeCmd\n\n");
    chdir($TMP_DIR);
    system($SyntaxTreeCmd." >$TMP_DIR/tu_errors 2>&1");
    if($?)
    { # failed to compile, but the TU dump still can be created
        my $Errors = readFile("$TMP_DIR/tu_errors");
        if($Errors=~/c99_/)
        { # disable c99 mode
            $C99Mode{$Version}=-1;
            printMsg("INFO", "Disabling C99 compatibility mode");
            resetLogging($Version);
            $TMP_DIR = tempdir(CLEANUP=>1);
            return getDump();
        }
        elsif($AutoPreambleMode{$Version}!=-1
        and my $TErrors = $Errors)
        {
            my %Types = ();
            while($TErrors=~s/error\:\s*(field\s*|)\W+(.+?)\W+//)
            { # error: 'FILE' has not been declared
                $Types{$2}=1;
            }
            my %AddHeaders = ();
            foreach my $Type (keys(%Types))
            {
                if(my $Header = $AutoPreamble{$Type}) {
                    $AddHeaders{path_format($Header, $OSgroup)}=$Type;
                }
            }
            if(my @Headers = sort {$b cmp $a} keys(%AddHeaders))
            { # sys/types.h should be the first
                foreach my $Num (0 .. $#Headers)
                {
                    my $Name = $Headers[$Num];
                    if(my $Path = identify_header($Name, $Version))
                    { # add automatic preamble headers
                        if(defined $Include_Preamble{$Version}{$Path})
                        { # already added
                            next;
                        }
                        $Include_Preamble{$Version}{$Path}{"Position"} = keys(%{$Include_Preamble{$Version}});
                        my $Type = $AddHeaders{$Name};
                        printMsg("INFO", "Add \'$Name\' preamble header for \'$Type\'");
                    }
                }
                $AutoPreambleMode{$Version}=-1;
                resetLogging($Version);
                $TMP_DIR = tempdir(CLEANUP=>1);
                return getDump();
            }
        }
        elsif($MinGWMode{$Version}!=-1)
        {
            $MinGWMode{$Version}=-1;
            resetLogging($Version);
            $TMP_DIR = tempdir(CLEANUP=>1);
            return getDump();
        }
        # FIXME: handle other errors and try to recompile
        writeLog($Version, $Errors);
        printMsg("ERROR", "some errors occurred when compiling headers");
        printErrorLog($Version);
        $COMPILE_ERRORS = $ERROR_CODE{"Compile_Error"};
        writeLog($Version, "\n");# new line
    }
    chdir($ORIG_DIR);
    unlink($TmpHeaderPath, $MHeaderPath);
    return (cmd_find($TMP_DIR,"f","*.tu",1))[0];
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
    return if(not $ArrRef or $#{$ArrRef}<0);
    my $String = "";
    foreach (@{$ArrRef}) {
        $String .= " ".inc_opt($_, $Style);
    }
    return $String;
}

sub getIncPaths(@)
{
    my @HeaderPaths = @_;
    my @IncPaths = ();
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
                $Includes{$Dir}=1;
            }
        }
        foreach my $Dir (keys(%{$Add_Include_Paths{$Version}}))
        { # added by user
            next if($Includes{$Dir});
            push(@IncPaths, $Dir);
        }
        foreach my $Dir (@{sortIncPaths([keys(%Includes)], $Version)}) {
            push(@IncPaths, $Dir);
        }
    }
    else
    { # user-defined paths
        foreach my $Dir (sort {get_depth($a)<=>get_depth($b)}
        sort {$b cmp $a} keys(%{$Include_Paths{$Version}})) {
            push(@IncPaths, $Dir);
        }
    }
    return \@IncPaths;
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
    my $Out = "$TMP_DIR/preprocessed";
    system("$Cmd >$Out 2>$TMP_DIR/null");
    return $Out;
}

sub cmd_find($$$$)
{ # native "find" is much faster than File::Find (~6x)
  # also the File::Find doesn't support --maxdepth N option
  # so using the cross-platform wrapper for the native one
    my ($Path, $Type, $Name, $MaxDepth) = @_;
    return () if(not $Path or not -e $Path);
    if($OSgroup eq "windows")
    {
        my $DirCmd = get_CmdPath("dir");
        if(not $DirCmd) {
            exitStatus("Not_Found", "can't find \"dir\" command");
        }
        $Path=~s/[\\]+\Z//;
        $Path = get_abs_path($Path);
        $Path = path_format($Path, $OSgroup);
        my $Cmd = $DirCmd." \"$Path\" /B /O";
        if($MaxDepth!=1) {
            $Cmd .= " /S";
        }
        if($Type eq "d") {
            $Cmd .= " /AD";
        }
        my @Files = ();
        if($Name)
        { # FIXME: how to search file names in MS shell?
            $Name=~s/\*/.*/g if($Name!~/\]/);
            foreach my $File (split(/\n/, `$Cmd`))
            {
                if($File=~/$Name\Z/i) {
                    push(@Files, $File);
                }
            }
        }
        else {
            @Files = split(/\n/, `$Cmd 2>$TMP_DIR/null`);
        }
        my @AbsPaths = ();
        foreach my $File (@Files)
        {
            if(not is_abs($File)) {
                $File = joinPath($Path, $File);
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
        if($Name)
        { # file name
            if($Name=~/\]/) {
                $Cmd .= " -regex \"$Name\"";
            }
            else {
                $Cmd .= " -name \"$Name\"";
            }
        }
        return split(/\n/, `$Cmd 2>$TMP_DIR/null`);
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
        system("$UnzipCmd \"$Path\" >$UnpackDir/contents.txt");
        if($?) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        chdir($ORIG_DIR);
        my @Contents = ();
        foreach (split("\n", readFile("$UnpackDir/contents.txt")))
        {
            if(/inflating:\s*([^\s]+)/) {
                push(@Contents, $1);
            }
        }
        if(not @Contents) {
            exitStatus("Error", "can't extract \'$Path\'");
        }
        return joinPath($UnpackDir, $Contents[0]);
    }
    elsif($FileName=~s/\Q.tar.gz\E\Z//g)
    { # *.tar.gz
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
            system("$GzipCmd -k -d -f \"$Path\"");# keep input files (-k)
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            system("$TarCmd -xvf \"$Dir\\$FileName.tar\" >$UnpackDir/contents.txt");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($ORIG_DIR);
            unlink($Dir."/".$FileName.".tar");
            my @Contents = split("\n", readFile("$UnpackDir/contents.txt"));
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return joinPath($UnpackDir, $Contents[0]);
        }
        else
        { # Unix
            my $TarCmd = get_CmdPath("tar");
            if(not $TarCmd) {
                exitStatus("Not_Found", "can't find \"tar\" command");
            }
            chdir($UnpackDir);
            system("$TarCmd -xvzf \"$Path\" >$UnpackDir/contents.txt");
            if($?) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            chdir($ORIG_DIR);
            # The content file name may be different
            # from the package file name
            my @Contents = split("\n", readFile("$UnpackDir/contents.txt"));
            if(not @Contents) {
                exitStatus("Error", "can't extract \'$Path\'");
            }
            return joinPath($UnpackDir, $Contents[0]);
        }
    }
}

sub createArchive($$)
{
    my ($Path, $To) = @_;
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
        system("$ZipCmd -j \"$Name.zip\" \"$Path\" >$TMP_DIR/null");
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
        if(my $HPath = identify_header($Header, $LibVersion)) {
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
            if(cmd_file($Header)=~/C[\+]*\s+program/i)
            { # !~/HTML|XML|shared|dynamic/i
                return $Header;
            }
        }
    }
    return 0;
}

sub detectTargetHeaders($)
{
    my $LibVersion = $_[0];
    foreach my $RegHeader (keys(%{$Registered_Headers{$LibVersion}}))
    {
        my $RegDir = get_dirname($RegHeader);
        $TargetHeaders{$LibVersion}{get_filename($RegHeader)}=1;
        foreach my $RecInc (keys(%{$RecursiveIncludes{$LibVersion}{$RegHeader}}))
        {
            my $Dir = get_dirname($RecInc);
            if($Dir=~/\A$RegDir([\/\\]|\Z)/)
            { # in the same directory
                $TargetHeaders{$LibVersion}{get_filename($RecInc)}=1;
            }
        }
    }
}

sub readHeaders($)
{
    $Version = $_[0];
    printMsg("INFO", "checking header(s) ".$Descriptor{$Version}{"Version"}." ...");
    my $DumpPath = getDump();
    if(not $DumpPath) {
        exitStatus("Cannot_Compile", "can't compile header(s)");
    }
    if($Debug)
    { # debug mode
        mkpath($DEBUG_PATH{$Version});
        copy($DumpPath, $DEBUG_PATH{$Version}."/translation-unit-dump.txt");
    }
    getInfo($DumpPath);
    if($CheckHeadersOnly
    or not $BinaryOnly)
    { # --headers-only mode
        detectTargetHeaders($Version);
    }
}

sub prepareTypes($)
{
    my $LibVersion = $_[0];
    if(not checkDumpVersion($LibVersion, "2.0"))
    { # support for old ABI dumps
      # type names have been corrected in ACC 1.22 (dump 2.0 format)
        foreach my $TypeDeclId (keys(%{$TypeInfo{$LibVersion}}))
        {
            foreach my $TypeId (keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}}))
            {
                my $TName = $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Name"};
                if($TName=~/\A(\w+)::(\w+)/) {
                    my ($P1, $P2) = ($1, $2);
                    if($P1 eq $P2) {
                        $TName=~s/\A$P1:\:$P1(\W)/$P1$1/;
                    }
                    else {
                        $TName=~s/\A(\w+:\:)$P2:\:$P2(\W)/$1$P2$2/;
                    }
                }
                $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Name"} = $TName;
            }
        }
    }
    if(not checkDumpVersion($LibVersion, "2.5"))
    { # support for old ABI dumps
      # V < 2.5: array size == "number of elements"
      # V >= 2.5: array size in bytes
        foreach my $TypeDeclId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}}))
            {
                my %Type = get_PureType($TypeDeclId, $TypeId, $LibVersion);
                if($Type{"Type"} eq "Array")
                {
                    if($Type{"Size"})
                    { # array[N]
                        my %Base = get_OneStep_BaseType($Type{"TDid"}, $Type{"Tid"}, $LibVersion);
                        $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Size"} = $Type{"Size"}*$Base{"Size"};
                    }
                    else
                    { # array[] is a pointer
                        $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Size"} = $WORD_SIZE{$LibVersion};
                    }
                }
            }
        }
    }
    my $V2 = ($LibVersion==1)?2:1;
    if(not checkDumpVersion($LibVersion, "2.7"))
    { # support for old ABI dumps
      # size of "method ptr" corrected in 2.7
        foreach my $TypeDeclId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
        {
            foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}}))
            {
                my %PureType = get_PureType($TypeDeclId, $TypeId, $LibVersion);
                if($PureType{"Type"} eq "MethodPtr")
                {
                    my %Type = get_Type($TypeDeclId, $TypeId, $LibVersion);
                    my $TypeId_2 = getTypeIdByName($PureType{"Name"}, $V2);
                    my %Type2 = get_Type($Tid_TDid{$V2}{$TypeId_2}, $TypeId_2, $V2);
                    if($Type{"Size"} ne $Type2{"Size"}) {
                        $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Size"} = $Type2{"Size"};
                    }
                }
            }
        }
    }
}

sub prepareSymbols($)
{
    my $LibVersion = $_[0];
    my $Remangle = 0;
    if(not checkDumpVersion(1, "2.10")
    or not checkDumpVersion(2, "2.10"))
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
        if($SymbolInfo{$LibVersion}{$InfoId}{"Destructor"})
        {
            if(defined $SymbolInfo{$LibVersion}{$InfoId}{"Param"}
            and keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}})
            and $SymbolInfo{$LibVersion}{$InfoId}{"Param"}{"0"}{"name"})
            { # support for old GCC < 4.5: skip artificial ~dtor(int __in_chrg)
              # + support for old ABI dumps
                next;
            }
        }
        my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
        if($Remangle==1)
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
            if(($SymbolInfo{$LibVersion}{$InfoId}{"Class"} and ($MnglName!~/\A_Z/ or not link_symbol($MnglName, $LibVersion, "-Deps")))
            or (not $SymbolInfo{$LibVersion}{$InfoId}{"Class"} and $CheckHeadersOnly))
            { # GCC >= 4.0
              # remangling C++-functions (not mangled in the TU dump)
              # remangling broken C++-methods (without a mangled name)
              # remangling all inline virtual C++-methods
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
        if(not $MnglName)
        { # ABI dumps don't contain mangled names for C-functions
            $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"ShortName"};
            $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"} = $MnglName;
        }
        if(not $MnglName) {
            next;
        }
        if(not $CompleteSignature{$LibVersion}{$MnglName}{"MnglName"})
        { # NOTE: global data may enter here twice
            %{$CompleteSignature{$LibVersion}{$MnglName}} = %{$SymbolInfo{$LibVersion}{$InfoId}};
            
        }
        if(not checkDumpVersion($LibVersion, "2.6"))
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
    }
    if($COMMON_LANGUAGE{$LibVersion} eq "C++" or $OSgroup eq "windows") {
        translateSymbols(keys(%{$CompleteSignature{$LibVersion}}), $LibVersion);
    }
    if($ExtendedCheck)
    { # --ext option
        addExtension($LibVersion);
    }
    if(not keys(%{$SymbolInfo{$LibVersion}}))
    { # check if input is valid
        if(not $ExtendedCheck and not $CheckObjectsOnly)
        {
            if($CheckHeadersOnly) {
                exitStatus("Empty_Set", "the set of public symbols is empty (".$Descriptor{$LibVersion}{"Version"}.")");
            }
            else {
                exitStatus("Empty_Intersection", "the sets of public symbols in headers and libraries have empty intersection (".$Descriptor{$LibVersion}{"Version"}.")");
            }
        }
    }
    $SymbolInfo{$LibVersion} = ();
    foreach my $MnglName (keys(%{$CompleteSignature{$LibVersion}}))
    { # detect allocable classes with public exported constructors
      # or classes with auto-generated or inline-only constructors
        if(my $ClassId = $CompleteSignature{$LibVersion}{$MnglName}{"Class"})
        {
            my $ClassName = get_TypeName($ClassId, $LibVersion);
            if($CompleteSignature{$LibVersion}{$MnglName}{"Constructor"}
            and not $CompleteSignature{$LibVersion}{$MnglName}{"InLine"})
            { # Class() { ... } will not be exported
                if(not $CompleteSignature{$LibVersion}{$MnglName}{"Private"})
                {
                    if(link_symbol($MnglName, $LibVersion, "-Deps")) {
                        $AllocableClass{$LibVersion}{$ClassName} = 1;
                    }
                }
            }
            if(not $CompleteSignature{$LibVersion}{$MnglName}{"Private"})
            { # all imported class methods
                if($CheckHeadersOnly)
                {
                    if(not $CompleteSignature{$LibVersion}{$MnglName}{"InLine"}
                    or $CompleteSignature{$LibVersion}{$MnglName}{"Virt"})
                    { # all symbols except non-virtual inline
                        $ClassMethods{"Binary"}{$LibVersion}{$ClassName}{$MnglName} = 1;
                    }
                }
                elsif(link_symbol($MnglName, $LibVersion, "-Deps"))
                { # all symbols
                    $ClassMethods{"Binary"}{$LibVersion}{$ClassName}{$MnglName} = 1;
                }
                $ClassMethods{"Source"}{$LibVersion}{$ClassName}{$MnglName} = 1;
            }
            $ClassToId{$LibVersion}{$ClassName} = $ClassId;
        }
        if(my $RetId = $CompleteSignature{$LibVersion}{$MnglName}{"Return"})
        {
            my %Base = get_BaseType($Tid_TDid{$LibVersion}{$RetId}, $RetId, $LibVersion);
            if($Base{"Type"}=~/Struct|Class/)
            {
                my $Name = get_TypeName($Base{"Tid"}, $LibVersion);
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
        foreach my $Num (keys(%{$CompleteSignature{$LibVersion}{$MnglName}{"Param"}}))
        {
            my $PId = $CompleteSignature{$LibVersion}{$MnglName}{"Param"}{$Num}{"type"};
            if(get_PointerLevel($Tid_TDid{1}{$PId}, $PId, $LibVersion)>=1)
            {
                my %Base = get_BaseType($Tid_TDid{$LibVersion}{$PId}, $PId, $LibVersion);
                if($Base{"Type"}=~/Struct|Class/)
                {
                    $ParamClass{$LibVersion}{$Base{"Tid"}}{$MnglName} = 1;
                    foreach my $SubId (get_sub_classes($Base{"Tid"}, $LibVersion, 1))
                    { # mark all derived classes
                        $ParamClass{$LibVersion}{$SubId}{$MnglName} = 1;
                    }
                }
            }
        }
    }
    foreach my $MnglName (keys(%VTableClass))
    { # reconstruct header name for v-tables
        if($MnglName=~/\A_ZTV/)
        {
            if(my $ClassName = $VTableClass{$MnglName})
            {
                if(my $ClassId = $TName_Tid{$LibVersion}{$ClassName}) {
                    $CompleteSignature{$LibVersion}{$MnglName}{"Header"} = get_TypeAttr($ClassId, $LibVersion, "Header");
                }
            }
        }
    }
}

sub addExtension($)
{
    my $LibVersion = $_[0];
    foreach my $TDid (keys(%{$TypeInfo{$LibVersion}}))
    {
        foreach my $Tid (keys(%{$TypeInfo{$LibVersion}{$TDid}}))
        {
            my $TType = $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Type"};
            if($TType=~/Struct|Union|Enum|Class/)
            {
                my $HName = $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Header"};
                if(not $HName or isBuiltIn($HName)) {
                    next;
                }
                my $TName = $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Name"};
                if(isAnon($TName))
                { # anon-struct-header.h-265
                    next;
                }
                my $FuncName = "external_func_".$TName;
                $ExtendedFuncs{$FuncName}=1;
                my %Attrs = (
                    "Header" => "extended.h",
                    "ShortName" => $FuncName,
                    "MnglName" => $FuncName,
                    "Param" => { "0" => { "type"=>$Tid, "name"=>"p1" } }
                );
                %{$CompleteSignature{$LibVersion}{$FuncName}} = %Attrs;
                register_TypeUsing($TDid, $Tid, $LibVersion);
                $GeneratedSymbols{$FuncName}=1;
                $CheckedSymbols{"Binary"}{$FuncName}=1;
                $CheckedSymbols{"Source"}{$FuncName}=1;
            }
        }
    }
    my $ConstFunc = "external_func_0";
    $GeneratedSymbols{$ConstFunc}=1;
    $CheckedSymbols{"Binary"}{$ConstFunc}=1;
    $CheckedSymbols{"Source"}{$ConstFunc}=1;
}

sub formatDump($)
{ # remove unnecessary data from the ABI dump
    my $LibVersion = $_[0];
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
        if(not $MnglName) {
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        if($MnglName eq $SymbolInfo{$LibVersion}{$InfoId}{"ShortName"}) {
            delete($SymbolInfo{$LibVersion}{$InfoId}{"MnglName"});
        }
        if(not is_target_header($SymbolInfo{$LibVersion}{$InfoId}{"Header"}))
        { # user-defined header
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        if($BinaryOnly and not $SourceOnly)
        { # --dump --binary
            if(not link_symbol($MnglName, $LibVersion, "-Deps")
            and not $SymbolInfo{$LibVersion}{$InfoId}{"Virt"}
            and not $SymbolInfo{$LibVersion}{$InfoId}{"PureVirt"})
            { # removing src only (inline)
              # and all non-exported functions
                if(not $CheckHeadersOnly) {
                    delete($SymbolInfo{$LibVersion}{$InfoId});
                    next;
                }
            }
        }
        if(not symbolFilter($MnglName, $LibVersion, "Public", "Source")) {
            delete($SymbolInfo{$LibVersion}{$InfoId});
            next;
        }
        my %FuncInfo = %{$SymbolInfo{$LibVersion}{$InfoId}};
        register_TypeUsing($Tid_TDid{$LibVersion}{$FuncInfo{"Return"}}, $FuncInfo{"Return"}, $LibVersion);
        register_TypeUsing($Tid_TDid{$LibVersion}{$FuncInfo{"Class"}}, $FuncInfo{"Class"}, $LibVersion);
        foreach my $Param_Pos (keys(%{$FuncInfo{"Param"}}))
        {
            my $Param_TypeId = $FuncInfo{"Param"}{$Param_Pos}{"type"};
            register_TypeUsing($Tid_TDid{$LibVersion}{$Param_TypeId}, $Param_TypeId, $LibVersion);
        }
        if(not keys(%{$SymbolInfo{$LibVersion}{$InfoId}{"Param"}})) {
            delete($SymbolInfo{$LibVersion}{$InfoId}{"Param"});
        }
    }
    foreach my $TDid (keys(%{$TypeInfo{$LibVersion}}))
    {
        if(not keys(%{$TypeInfo{$LibVersion}{$TDid}})) {
            delete($TypeInfo{$LibVersion}{$TDid});
        }
        else
        {
            foreach my $Tid (keys(%{$TypeInfo{$LibVersion}{$TDid}}))
            {
                if(not $UsedType{$LibVersion}{$TDid}{$Tid})
                {
                    delete($TypeInfo{$LibVersion}{$TDid}{$Tid});
                    if(not keys(%{$TypeInfo{$LibVersion}{$TDid}})) {
                        delete($TypeInfo{$LibVersion}{$TDid});
                    }
                    if($Tid_TDid{$LibVersion}{$Tid} eq $TDid) {
                        delete($Tid_TDid{$LibVersion}{$Tid});
                    }
                }
                else
                { # clean attributes
                    if(not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"TDid"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"TDid"});
                    }
                    if(not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"NameSpace"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"NameSpace"});
                    }
                    if(defined $TypeInfo{$LibVersion}{$TDid}{$Tid}{"BaseType"}
                    and not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"BaseType"}{"TDid"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"BaseType"}{"TDid"});
                    }
                    if(not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Header"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"Header"});
                    }
                    if(not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Line"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"Line"});
                    }
                    if(not $TypeInfo{$LibVersion}{$TDid}{$Tid}{"Size"}) {
                        delete($TypeInfo{$LibVersion}{$TDid}{$Tid}{"Size"});
                    }
                }
            }
        }
    }
    foreach my $Tid (keys(%{$Tid_TDid{$LibVersion}}))
    {
        if(not $Tid_TDid{$LibVersion}{$Tid}) {
            delete($Tid_TDid{$LibVersion}{$Tid});
        }
    }
}

sub register_TypeUsing($$$)
{
    my ($TypeDeclId, $TypeId, $LibVersion) = @_;
    return if($UsedType{$LibVersion}{$TypeDeclId}{$TypeId});
    my %Type = get_Type($TypeDeclId, $TypeId, $LibVersion);
    if($Type{"Type"}=~/\A(Struct|Union|Class|FuncPtr|MethodPtr|FieldPtr|Enum)\Z/)
    {
        $UsedType{$LibVersion}{$TypeDeclId}{$TypeId} = 1;
        if($Type{"Type"}=~/\A(Struct|Class)\Z/)
        {
            if(my $ThisPtrId = getTypeIdByName(get_TypeName($TypeId, $LibVersion)."*const", $LibVersion))
            {# register "this" pointer
                my $ThisPtrDId = $Tid_TDid{$LibVersion}{$ThisPtrId};
                my %ThisPtrType = get_Type($ThisPtrDId, $ThisPtrId, $LibVersion);
                $UsedType{$LibVersion}{$ThisPtrDId}{$ThisPtrId} = 1;
                register_TypeUsing($ThisPtrType{"BaseType"}{"TDid"}, $ThisPtrType{"BaseType"}{"Tid"}, $LibVersion);
            }
            foreach my $BaseId (keys(%{$Type{"Base"}}))
            {# register base classes
                register_TypeUsing($Tid_TDid{$LibVersion}{$BaseId}, $BaseId, $LibVersion);
            }
        }
        foreach my $Memb_Pos (keys(%{$Type{"Memb"}}))
        {
            my $Member_TypeId = $Type{"Memb"}{$Memb_Pos}{"type"};
            register_TypeUsing($Tid_TDid{$LibVersion}{$Member_TypeId}, $Member_TypeId, $LibVersion);
        }
        if($Type{"Type"} eq "FuncPtr"
        or $Type{"Type"} eq "MethodPtr") {
            my $ReturnType = $Type{"Return"};
            register_TypeUsing($Tid_TDid{$LibVersion}{$ReturnType}, $ReturnType, $LibVersion);
            foreach my $Memb_Pos (keys(%{$Type{"Param"}}))
            {
                my $Member_TypeId = $Type{"Param"}{$Memb_Pos}{"type"};
                register_TypeUsing($Tid_TDid{$LibVersion}{$Member_TypeId}, $Member_TypeId, $LibVersion);
            }
        }
    }
    elsif($Type{"Type"}=~/\A(Const|Pointer|Ref|Volatile|Restrict|Array|Typedef)\Z/)
    {
        $UsedType{$LibVersion}{$TypeDeclId}{$TypeId} = 1;
        register_TypeUsing($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
    }
    elsif($Type{"Type"} eq "Intrinsic") {
        $UsedType{$LibVersion}{$TypeDeclId}{$TypeId} = 1;
    }
    else
    {
        delete($TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId});
        if(not keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}})) {
            delete($TypeInfo{$LibVersion}{$TypeDeclId});
        }
        if($Tid_TDid{$LibVersion}{$TypeId} eq $TypeDeclId) {
            delete($Tid_TDid{$LibVersion}{$TypeId});
        }
    }
}

sub findMethod($$$)
{
    my ($VirtFunc, $ClassId, $LibVersion) = @_;
    foreach my $BaseClass_Id (keys(%{$TypeInfo{$LibVersion}{$Tid_TDid{$LibVersion}{$ClassId}}{$ClassId}{"Base"}}))
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
    my $ClassName = get_TypeName($ClassId, $LibVersion);
    return "" if(not defined $VirtualTable{$LibVersion}{$ClassName});
    my $TargetSuffix = get_symbol_suffix($VirtFunc, 1);
    my $TargetShortName = $CompleteSignature{$LibVersion}{$VirtFunc}{"ShortName"};
    foreach my $Candidate (keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
    { # search for interface with the same parameters suffix (overridden)
        if($TargetSuffix eq get_symbol_suffix($Candidate, 1))
        {
            if($CompleteSignature{$LibVersion}{$VirtFunc}{"Destructor"}) {
                if($CompleteSignature{$LibVersion}{$Candidate}{"Destructor"}) {
                    if(($VirtFunc=~/D0E/ and $Candidate=~/D0E/)
                    or ($VirtFunc=~/D1E/ and $Candidate=~/D1E/)
                    or ($VirtFunc=~/D2E/ and $Candidate=~/D2E/)) {
                        return $Candidate;
                    }
                }
            }
            else {
                if($TargetShortName eq $CompleteSignature{$LibVersion}{$Candidate}{"ShortName"}) {
                    return $Candidate;
                }
            }
        }
    }
    return "";
}

sub registerVTable($$)
{
    my ($LibVersion, $Level) = @_;
    foreach my $Symbol (keys(%{$CompleteSignature{$LibVersion}}))
    {
        if($CompleteSignature{$LibVersion}{$Symbol}{"Virt"}
        or $CompleteSignature{$LibVersion}{$Symbol}{"PureVirt"})
        {
            my $ClassName = get_TypeName($CompleteSignature{$LibVersion}{$Symbol}{"Class"}, $LibVersion);
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
        if($CheckHeadersOnly
        and $CompleteSignature{$LibVersion}{$Symbol}{"Virt"})
        { # Register added and removed virtual symbols
          # This is necessary for --headers-only mode
          # Virtual function cannot be inline, so:
          # presence in headers <=> presence in shared libs
            if($LibVersion==2 and not $CompleteSignature{1}{$Symbol}{"Header"})
            { # not presented in old-version headers
                $AddedInt{$Level}{$Symbol} = 1;
            }
            if($LibVersion==1 and not $CompleteSignature{2}{$Symbol}{"Header"})
            { # not presented in new-version headers
                $RemovedInt{$Level}{$Symbol} = 1;
            }
        }
    }
}

sub registerOverriding($)
{
    my $LibVersion = $_[0];
    my @Classes = keys(%{$VirtualTable{$LibVersion}});
    @Classes = sort {int($ClassToId{$LibVersion}{$a})<=>int($ClassToId{$LibVersion}{$b})} @Classes;
    foreach my $ClassName (@Classes)
    {
        foreach my $VirtFunc (keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
        {
            next if($CompleteSignature{$LibVersion}{$VirtFunc}{"PureVirt"});
            if(my $OverriddenMethod = findMethod($VirtFunc, $TName_Tid{$LibVersion}{$ClassName}, $LibVersion))
            { # both overridden virtual and implemented pure virtual functions
                $CompleteSignature{$LibVersion}{$VirtFunc}{"Override"} = $OverriddenMethod;
                $OverriddenMethods{$LibVersion}{$OverriddenMethod}{$VirtFunc} = 1;
                delete($VirtualTable{$LibVersion}{$ClassName}{$VirtFunc});
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
        my ($Num, $RelPos, $AbsNum) = (1, 0, 1);
        foreach my $VirtFunc (sort {int($CompleteSignature{$LibVersion}{$a}{"Line"}) <=> int($CompleteSignature{$LibVersion}{$b}{"Line"})}
        sort keys(%{$VirtualTable{$LibVersion}{$ClassName}}))
        {
            if(not $CompleteSignature{1}{$VirtFunc}{"Override"}
            and not $CompleteSignature{2}{$VirtFunc}{"Override"})
            {
                if(defined $VirtualTable{1}{$ClassName} and defined $VirtualTable{1}{$ClassName}{$VirtFunc}
                and defined $VirtualTable{2}{$ClassName} and defined $VirtualTable{2}{$ClassName}{$VirtFunc})
                { # relative position excluding added and removed virtual functions
                    $CompleteSignature{$LibVersion}{$VirtFunc}{"RelPos"} = $RelPos++;
                }
                $VirtualTable{$LibVersion}{$ClassName}{$VirtFunc}=$Num++;
            }
            
        }
    }
    foreach my $ClassName (keys(%{$ClassToId{$LibVersion}}))
    {
        my $AbsNum = 1;
        foreach my $VirtFunc (getVTable($ClassToId{$LibVersion}{$ClassName}, $LibVersion)) {
            $VirtualTable_Full{$LibVersion}{$ClassName}{$VirtFunc}=$AbsNum++;
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
        if($Recursive) {
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
    my %ClassType = get_Type($Tid_TDid{$LibVersion}{$ClassId}, $ClassId, $LibVersion);
    return () if(not defined $ClassType{"Base"});
    my @Bases = ();
    foreach my $BaseId (sort {int($ClassType{"Base"}{$a}{"pos"})<=>int($ClassType{"Base"}{$b}{"pos"})}
    keys(%{$ClassType{"Base"}}))
    {
        if($Recursive) {
            foreach my $SubBaseId (get_base_classes($BaseId, $LibVersion, $Recursive)) {
                push(@Bases, $SubBaseId);
            }
        }
        push(@Bases, $BaseId);
    }
    return @Bases;
}

sub getVTable($$)
{# return list of v-table elements
    my ($ClassId, $LibVersion) = @_;
    my @Bases = get_base_classes($ClassId, $LibVersion, 1);
    my @Elements = ();
    foreach my $BaseId (@Bases, $ClassId)
    {
        my $BName = get_TypeName($BaseId, $LibVersion);
        my @VFunctions = keys(%{$VirtualTable{$LibVersion}{$BName}});
        @VFunctions = sort {int($CompleteSignature{$LibVersion}{$a}{"Line"}) <=> int($CompleteSignature{$LibVersion}{$b}{"Line"})} @VFunctions;
        foreach my $VFunc (@VFunctions)
        {
            push(@Elements, $VFunc);
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
        my $BName = get_TypeName($BaseId, $LibVersion);
        if(defined $VirtualTable{$LibVersion}{$BName}) {
            $VShift+=keys(%{$VirtualTable{$LibVersion}{$BName}});
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
        if(my $Size = get_TypeSize($BaseId, $LibVersion))
        {
            if($Size!=1)
            { # not empty base class
                $Shift+=$Size;
            }
        }
    }
    return $Shift;
}

sub getVSize($$)
{
    my ($ClassName, $LibVersion) = @_;
    if(defined $VirtualTable{$LibVersion}{$ClassName})  {
        return keys(%{$VirtualTable{$LibVersion}{$ClassName}});
    }
    else {
        return 0;
    }
}

sub isCopyingClass($$)
{
    my ($TypeId, $LibVersion) = @_;
    return $TypeInfo{$LibVersion}{$Tid_TDid{$LibVersion}{$TypeId}}{$TypeId}{"Copied"};
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
    foreach my $MemPos (keys(%{$TypePtr->{"Memb"}}))
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

sub getAlignment($$$)
{
    my ($Pos, $TypePtr, $LibVersion) = @_;
    my $Tid = $TypePtr->{"Memb"}{$Pos}{"type"};
    my %Type = get_PureType($Tid_TDid{$LibVersion}{$Tid}, $Tid, $LibVersion);
    my $TSize = $Type{"Size"}*$BYTE_SIZE;
    my $MSize = $Type{"Size"}*$BYTE_SIZE;
    if(my $BSize = $TypePtr->{"Memb"}{$Pos}{"bitfield"})
    { # bitfields
        ($TSize, $MSize) = ($WORD_SIZE{$LibVersion}*$BYTE_SIZE, $BSize);
    }
    elsif($Type{"Type"} eq "Array")
    { # in the context of function parameter
      # it's passed through the pointer
    }
    # alignment
    my $Alignment = $WORD_SIZE{$LibVersion}*$BYTE_SIZE; # default
    if(my $Computed = $TypePtr->{"Memb"}{$Pos}{"algn"})
    { # computed by GCC
        $Alignment = $Computed*$BYTE_SIZE;
    }
    elsif($TypePtr->{"Memb"}{$Pos}{"bitfield"})
    { # bitfields are 1 bit aligned
        $Alignment = 1;
    }
    elsif($TSize and $TSize<$WORD_SIZE{$LibVersion}*$BYTE_SIZE)
    { # model
        $Alignment = $TSize;
    }
    return ($Alignment, $MSize);
}

sub getOffset($$$)
{ # offset of the field including padding
    my ($FieldPos, $TypePtr, $LibVersion) = @_;
    my $Offset = 0;
    foreach my $Pos (0 .. keys(%{$TypePtr->{"Memb"}})-1)
    {
        my ($Alignment, $MSize) = getAlignment($Pos, $TypePtr, $LibVersion);
        # padding
        my $Padding = 0;
        if($Offset % $Alignment!=0)
        { # not aligned, add padding
            $Padding = $Alignment - $Offset % $Alignment;
        }
        $Offset += $Padding;
        if($Pos==$FieldPos)
        { # after the padding
          # before the field
            return $Offset;
        }
        $Offset += $MSize;
    }
    return $FieldPos;# if something is going wrong
}

sub isMemPadded($$$$$)
{ # check if the target field can be added/removed/changed
  # without shifting other fields because of padding bits
    my ($FieldPos, $Size, $TypePtr, $Skip, $LibVersion) = @_;
    return 0 if($FieldPos==0);
    if(defined $TypePtr->{"Memb"}{""})
    {
        delete($TypePtr->{"Memb"}{""});
        if($Debug) {
            printMsg("WARNING", "internal error detected");
        }
    }
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
        ($Alignment{$Pos}, $MSize{$Pos}) = getAlignment($Pos, $TypePtr, $LibVersion);
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

sub isReserved($)
{ # reserved fields == private
    my $MName = $_[0];
    if($MName=~/reserved|padding|f_spare/i) {
        return 1;
    }
    if($MName=~/\A[_]*(spare|pad|unused)[_]*\Z/i) {
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
    if(not $TypePtr->{"Memb"}{$FieldPos}{"access"})
    { # by name in C language
      # FIXME: add other methods to detect private members
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
    elsif($TypePtr->{"Memb"}{$FieldPos}{"access"} ne "private")
    { # by access in C++ language
        return 1;
    }
    return 0;
}

sub cmpVTables_Model($)
{
    my $ClassName = $_[0];
    foreach my $Symbol (keys(%{$VirtualTable_Full{1}{$ClassName}}))
    {
        if(not defined $VirtualTable_Full{2}{$ClassName}{$Symbol}) {
            return 1;
        }
    }
    return 0;
}

sub cmpVTables($$)
{
    my ($ClassName, $Strong) = @_;
    my $ClassId1 = $ClassToId{1}{$ClassName};
    my $ClassId2 = $ClassToId{2}{$ClassName};
    if(not $ClassId1 or not $ClassId2) {
        return 0;
    }
    my %Type1 = get_Type($Tid_TDid{1}{$ClassId1}, $ClassId1, 1);
    my %Type2 = get_Type($Tid_TDid{2}{$ClassId2}, $ClassId2, 2);
    if(not defined $Type1{"VTable"}
    or not defined $Type2{"VTable"})
    { # old ABI dumps
        return 0;
    }
    my %Indexes = map {$_=>1} (keys(%{$Type1{"VTable"}}), keys(%{$Type2{"VTable"}}));
    foreach my $Offset (sort {int($a)<=>int($b)} keys(%Indexes))
    {
        if(not defined $Type1{"VTable"}{$Offset})
        { # v-table v.1 < v-table v.2
            return $Strong;
        }
        my $Entry1 = $Type1{"VTable"}{$Offset};
        if(not defined $Type2{"VTable"}{$Offset})
        { # v-table v.1 > v-table v.2
            return $Strong;
        }
        my $Entry2 = $Type2{"VTable"}{$Offset};
        $Entry1 = simpleVEntry($Entry1);
        $Entry2 = simpleVEntry($Entry2);
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
            return 1;
        }
    }
    return 0;
}

sub mergeVTables($)
{ # merging v-tables without diagnostics
    my $Level = $_[0];
    foreach my $ClassName (keys(%{$VirtualTable{1}}))
    {
        if($VTableChanged{$ClassName})
        { # already registered
            next;
        }
        if(cmpVTables($ClassName, 0))
        {
            my @Affected = (keys(%{$ClassMethods{$Level}{1}{$ClassName}}));
            foreach my $Symbol (@Affected)
            {
                %{$CompatProblems{$Level}{$Symbol}{"Virtual_Table_Changed_Unknown"}{$ClassName}}=(
                    "Type_Name"=>$ClassName,
                    "Type_Type"=>"Class",
                    "Target"=>$ClassName);
            }
        }
    }
}

sub mergeBases($)
{
    my $Level = $_[0];
    foreach my $ClassName (keys(%{$ClassToId{1}}))
    { # detect added and removed virtual functions
        my $ClassId = $ClassToId{1}{$ClassName};
        next if(not $ClassId);
        if(defined $VirtualTable{2}{$ClassName})
        {
            foreach my $VirtFunc (keys(%{$VirtualTable{2}{$ClassName}}))
            {
                if($ClassToId{1}{$ClassName}
                and not defined $VirtualTable{1}{$ClassName}{$VirtFunc})
                { # added to v-table
                    if(not $CompleteSignature{2}{$VirtFunc}{"Override"}) {
                        $AddedInt_Virt{$Level}{$ClassName}{$VirtFunc} = 1;
                    }
                }
            }
        }
        if(defined $VirtualTable{1}{$ClassName})
        {
            foreach my $VirtFunc (keys(%{$VirtualTable{1}{$ClassName}}))
            {
                if($ClassToId{2}{$ClassName}
                and not defined $VirtualTable{2}{$ClassName}{$VirtFunc})
                { # removed from v-table
                    if(not $CompleteSignature{1}{$VirtFunc}{"Override"}) {
                        $RemovedInt_Virt{$Level}{$ClassName}{$VirtFunc} = 1;
                    }
                }
            }
        }
        if($Level eq "Binary")
        { # Binary-level
            my %Class_Type = get_Type($Tid_TDid{1}{$ClassId}, $ClassId, 1);
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
                        @Affected = (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                    }
                    foreach my $AffectedInt (@Affected)
                    {
                        if($CompleteSignature{1}{$AffectedInt}{"PureVirt"})
                        { # affected exported methods only
                            next;
                        }
                        %{$CompatProblems{$Level}{$AffectedInt}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$Class_Type{"Name"},
                            "Type_Type"=>"Class",
                            "Target"=>get_Signature($AddedVFunc, 2),
                            "Old_Value"=>get_Signature($RemovedVFunc, 1));
                    }
                }
            }
        }
    }
    if(not checkDumpVersion(1, "2.0")
    or not checkDumpVersion(2, "2.0"))
    { # support for old ABI dumps
      # "Base" attribute introduced in ACC 1.22 (dump 2.0 format)
        return;
    }
    foreach my $ClassName (sort keys(%{$ClassToId{1}}))
    {
        my $ClassId_Old = $ClassToId{1}{$ClassName};
        next if(not $ClassId_Old);
        if(not isCreatable($ClassId_Old, 1))
        { # skip classes without public constructors (including auto-generated)
          # example: class has only a private exported or private inline constructor
            next;
        }
        if($ClassName=~/>/)
        { # skip affected template instances
            next;
        }
        my %Class_Old = get_Type($Tid_TDid{1}{$ClassId_Old}, $ClassId_Old, 1);
        my $ClassId_New = $ClassToId{2}{$ClassName};
        next if(not $ClassId_New);
        my %Class_New = get_Type($Tid_TDid{2}{$ClassId_New}, $ClassId_New, 2);
        my @Bases_Old = sort {$Class_Old{"Base"}{$a}{"pos"}<=>$Class_Old{"Base"}{$b}{"pos"}} keys(%{$Class_Old{"Base"}});
        my @Bases_New = sort {$Class_New{"Base"}{$a}{"pos"}<=>$Class_New{"Base"}{$b}{"pos"}} keys(%{$Class_New{"Base"}});
        my ($BNum1, $BNum2) = (1, 1);
        my %BasePos_Old = map {get_TypeName($_, 1) => $BNum1++} @Bases_Old;
        my %BasePos_New = map {get_TypeName($_, 2) => $BNum2++} @Bases_New;
        my %ShortBase_Old = map {get_ShortType($_, 1) => 1} @Bases_Old;
        my %ShortBase_New = map {get_ShortType($_, 2) => 1} @Bases_New;
        my $Shift_Old = getShift($ClassId_Old, 1);
        my $Shift_New = getShift($ClassId_New, 2);
        my %BaseId_New = map {get_TypeName($_, 2) => $_} @Bases_New;
        my ($Added, $Removed) = (0, 0);
        my @StableBases_Old = ();
        foreach my $BaseId (@Bases_Old)
        {
            my $BaseName = get_TypeName($BaseId, 1);
            if($BasePos_New{$BaseName}) {
                push(@StableBases_Old, $BaseId);
            }
            elsif(not $ShortBase_New{$BaseName}
            and not $ShortBase_New{get_ShortType($BaseId, 1)})
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
                    if(keys(%{$VirtualTable_Full{1}{$BaseName}})
                    and (cmpVTables($ClassName, 1) or cmpVTables_Model($ClassName)))
                    { # affected v-table
                        $ProblemKind .= "_And_VTable";
                        $VTableChanged{$ClassName}=1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (get_sub_classes($ClassId_Old, 1, 1))
                {
                    my $SubName = get_TypeName($SubId, 1);
                    push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                    if($ProblemKind=~/VTable/) {
                        $VTableChanged{$SubName}=1;
                    }
                }
                foreach my $Interface (@Affected)
                {
                    %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                        "Type_Name"=>$ClassName,
                        "Type_Type"=>"Class",
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
            my $BaseName = get_TypeName($BaseId, 2);
            if($BasePos_Old{$BaseName}) {
                push(@StableBases_New, $BaseId);
            }
            elsif(not $ShortBase_Old{$BaseName}
            and not $ShortBase_Old{get_ShortType($BaseId, 2)})
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
                    if(keys(%{$VirtualTable_Full{2}{$BaseName}})
                    and (cmpVTables($ClassName, 1) or cmpVTables_Model($ClassName)))
                    { # affected v-table
                        $ProblemKind .= "_And_VTable";
                        $VTableChanged{$ClassName}=1;
                    }
                }
                my @Affected = keys(%{$ClassMethods{$Level}{1}{$ClassName}});
                foreach my $SubId (get_sub_classes($ClassId_Old, 1, 1))
                {
                    my $SubName = get_TypeName($SubId, 1);
                    push(@Affected, keys(%{$ClassMethods{$Level}{1}{$SubName}}));
                    if($ProblemKind=~/VTable/) {
                        $VTableChanged{$SubName}=1;
                    }
                }
                foreach my $Interface (@Affected)
                {
                    %{$CompatProblems{$Level}{$Interface}{$ProblemKind}{"this"}}=(
                        "Type_Name"=>$ClassName,
                        "Type_Type"=>"Class",
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
            my %BaseRelPos_Old = map {get_TypeName($_, 1) => $BNum1++} @StableBases_Old;
            my %BaseRelPos_New = map {get_TypeName($_, 2) => $BNum2++} @StableBases_New;
            foreach my $BaseId (@Bases_Old)
            {
                my $BaseName = get_TypeName($BaseId, 1);
                if(my $NewPos = $BaseRelPos_New{$BaseName})
                {
                    my $BaseNewId = $BaseId_New{$BaseName};
                    my $OldPos = $BaseRelPos_Old{$BaseName};
                    if($NewPos!=$OldPos)
                    { # changed position of the base class
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Position"}{"this"}}=(
                                "Type_Name"=>$ClassName,
                                "Type_Type"=>"Class",
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
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Became_Non_Virtually_Inherited"}{"this->".$BaseName}}=(
                                "Type_Name"=>$ClassName,
                                "Type_Type"=>"Class",
                                "Target"=>$BaseName  );
                        }
                    }
                    elsif(not $Class_Old{"Base"}{$BaseId}{"virtual"}
                    and $Class_New{"Base"}{$BaseNewId}{"virtual"})
                    { # became virtual base
                        foreach my $Interface (keys(%{$ClassMethods{$Level}{1}{$ClassName}}))
                        {
                            %{$CompatProblems{$Level}{$Interface}{"Base_Class_Became_Virtually_Inherited"}{"this->".$BaseName}}=(
                                "Type_Name"=>$ClassName,
                                "Type_Type"=>"Class",
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
                    my %BaseType = get_Type($Tid_TDid{1}{$BaseId}, $BaseId, 1);
                    my $Size_Old = get_TypeSize($BaseId, 1);
                    my $Size_New = get_TypeSize($BaseId_New{$BaseType{"Name"}}, 2);
                    if($Size_Old ne $Size_New
                    and $Size_Old and $Size_New)
                    {
                        my $ProblemType = "";
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
                            %{$CompatProblems{$Level}{$Interface}{$ProblemType}{"this->".$BaseType{"Name"}}}=(
                                "Type_Name"=>$BaseType{"Name"},
                                "Type_Type"=>"Class",
                                "Target"=>$BaseType{"Name"},
                                "Old_Size"=>$Size_Old*$BYTE_SIZE,
                                "New_Size"=>$Size_New*$BYTE_SIZE  );
                        }
                    }
                }
            }
            if(defined $VirtualTable{1}{$ClassName}
            and my @VFunctions = keys(%{$VirtualTable{1}{$ClassName}}))
            { # compare virtual tables size in base classes
                my $VShift_Old = getVShift($ClassId_Old, 1);
                my $VShift_New = getVShift($ClassId_New, 2);
                if($VShift_Old ne $VShift_New)
                { # changes in the base class or changes in the list of base classes
                    my @AllBases_Old = get_base_classes($ClassId_Old, 1, 1);
                    my @AllBases_New = get_base_classes($ClassId_New, 2, 1);
                    ($BNum1, $BNum2) = (1, 1);
                    my %StableBase = map {get_TypeName($_, 2) => $_} @AllBases_New;
                    foreach my $BaseId (@AllBases_Old)
                    {
                        my %BaseType = get_Type($Tid_TDid{1}{$BaseId}, $BaseId, 1);
                        if(not $StableBase{$BaseType{"Name"}})
                        { # lost base
                            next;
                        }
                        my $VSize_Old = getVSize($BaseType{"Name"}, 1);
                        my $VSize_New = getVSize($BaseType{"Name"}, 2);
                        if($VSize_Old!=$VSize_New)
                        {
                            my $VRealSize_Old = get_VTableSymbolSize($BaseType{"Name"}, 1);
                            my $VRealSize_New = get_VTableSymbolSize($BaseType{"Name"}, 2);
                            if(not $VRealSize_Old or not $VRealSize_New)
                            { # try to compute a model v-table size
                                $VRealSize_Old = ($VSize_Old+2+getVShift($BaseId, 1))*$WORD_SIZE{1};
                                $VRealSize_New = ($VSize_New+2+getVShift($StableBase{$BaseType{"Name"}}, 2))*$WORD_SIZE{2};
                            }
                            foreach my $Interface (@VFunctions)
                            {
                                if(not defined $VirtualTable{2}{$ClassName}{$Interface})
                                { # Removed_Virtual_Method, will be registered in mergeVirtualTables()
                                    next;
                                }
                                if($VirtualTable{2}{$ClassName}{$Interface}-$VirtualTable{1}{$ClassName}{$Interface}+$VSize_New-$VSize_Old==0)
                                { # skip interfaces that have not changed the absolute virtual position
                                    next;
                                }
                                if(not link_symbol($Interface, 1, "-Deps")
                                and not $CheckHeadersOnly)
                                { # affected symbols in shared library
                                    next;
                                }
                                if($LIB_ARCH{1} eq $LIB_ARCH{2}
                                or not $LIB_ARCH{1} or not $LIB_ARCH{2})
                                {
                                    %{$CompatProblems{$Level}{$Interface}{"Virtual_Table_Size"}{$BaseType{"Name"}}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Type_Type"=>"Class",
                                        "Target"=>get_Signature($Interface, 1),
                                        "Old_Size"=>$VRealSize_Old*$BYTE_SIZE,
                                        "New_Size"=>$VRealSize_New*$BYTE_SIZE  );
                                }
                                $VTableChanged{$BaseType{"Name"}} = 1;
                                $VTableChanged{$ClassName} = 1;
                                foreach my $VirtFunc (keys(%{$AddedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: added virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Added_Virtual_Method";
                                    if($CompleteSignature{2}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Added_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Interface}{$ProblemType}{get_Signature($VirtFunc, 2)}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Type_Type"=>"Class",
                                        "Target"=>get_Signature($VirtFunc, 2)  );
                                }
                                foreach my $VirtFunc (keys(%{$RemovedInt_Virt{$Level}{$BaseType{"Name"}}}))
                                { # the reason of the layout change: removed virtual functions
                                    next if($VirtualReplacement{$VirtFunc});
                                    my $ProblemType = "Removed_Virtual_Method";
                                    if($CompleteSignature{1}{$VirtFunc}{"PureVirt"}) {
                                        $ProblemType = "Removed_Pure_Virtual_Method";
                                    }
                                    %{$CompatProblems{$Level}{$Interface}{$ProblemType}{get_Signature($VirtFunc, 1)}}=(
                                        "Type_Name"=>$BaseType{"Name"},
                                        "Type_Type"=>"Class",
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
    if($AllocableClass{$LibVersion}{get_TypeName($ClassId, $LibVersion)}
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
    my $CName = get_TypeName($ClassId, 1);
    if(keys(%{$ClassMethods{$Level}{1}{$CName}}))
    { # method from target class
        return 1;
    }
    return 0;
}

sub mergeVirtualTables($$)
{ # check for changes in the virtual table
    my ($Interface, $Level) = @_;
    # affected method:
    #  - virtual
    #  - pure-virtual
    #  - non-virtual
    
    if($CompleteSignature{1}{$Interface}{"Data"})
    { # global data is not affected
        return;
    }
    my $Class_Id = $CompleteSignature{1}{$Interface}{"Class"};
    my $CName = get_TypeName($Class_Id, 1);
    $CheckedTypes{$Level}{$CName} = 1;
    if($Level eq "Binary")
    { # Binary-level
        if($CompleteSignature{1}{$Interface}{"PureVirt"}
        and not isUsedClass($Class_Id, 1, $Level))
        { # pure virtuals should not be affected
        # if there are no exported methods using this class
            return;
        }
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
                    "Type_Type"=>"Class",
                    "Target"=>get_Signature($AddedVFunc, 2)  );
                $VTableChanged{$CName} = 1;
            }
            elsif(not defined $VirtualTable{1}{$CName}
            or $VPos_Added>keys(%{$VirtualTable{1}{$CName}}))
            { # added virtual function at the end of v-table
                if(not keys(%{$VirtualTable_Full{1}{$CName}}))
                { # became polymorphous class, added v-table pointer
                    %{$CompatProblems{$Level}{$Interface}{"Added_First_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                        "Type_Name"=>$CName,
                        "Type_Type"=>"Class",
                        "Target"=>get_Signature($AddedVFunc, 2)  );
                    $VTableChanged{$CName} = 1;
                }
                else
                {
                    my $VSize_Old = getVSize($CName, 1);
                    my $VSize_New = getVSize($CName, 2);
                    next if($VSize_Old==$VSize_New);# exception: register as removed and added virtual method
                    if(isCopyingClass($Class_Id, 1))
                    { # class has no constructors and v-table will be copied by applications, this may affect all methods
                        my $ProblemType = "Added_Virtual_Method";
                        if(isLeafClass($Class_Id, 1)) {
                            $ProblemType = "Added_Virtual_Method_At_End_Of_Leaf_Copying_Class";
                        }
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$CName,
                            "Type_Type"=>"Class",
                            "Target"=>get_Signature($AddedVFunc, 2)  );
                        $VTableChanged{$CName} = 1;
                    }
                    else
                    {
                        my $ProblemType = "Added_Virtual_Method";
                        if(isLeafClass($Class_Id, 1)) {
                            $ProblemType = "Added_Virtual_Method_At_End_Of_Leaf_Allocable_Class";
                        }
                        %{$CompatProblems{$Level}{$Interface}{$ProblemType}{$tr_name{$AddedVFunc}}}=(
                            "Type_Name"=>$CName,
                            "Type_Type"=>"Class",
                            "Target"=>get_Signature($AddedVFunc, 2)  );
                        $VTableChanged{$CName} = 1;
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
                            if(not $CompleteSignature{1}{$ASymbol}{"PureVirt"}
                            and not link_symbol($ASymbol, 1, "-Deps")) {
                                next;
                            }
                            $CheckedSymbols{$Level}{$ASymbol} = 1;
                            %{$CompatProblems{$Level}{$ASymbol}{"Added_Virtual_Method"}{$tr_name{$AddedVFunc}}}=(
                                "Type_Name"=>$CName,
                                "Type_Type"=>"Class",
                                "Target"=>get_Signature($AddedVFunc, 2)  );
                            $VTableChanged{get_TypeName($CompleteSignature{1}{$ASymbol}{"Class"}, 1)} = 1;
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
            if(not keys(%{$VirtualTable_Full{2}{$CName}}))
            { # became non-polymorphous class, removed v-table pointer
                %{$CompatProblems{$Level}{$Interface}{"Removed_Last_Virtual_Method"}{$tr_name{$RemovedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Type_Type"=>"Class",
                    "Target"=>get_Signature($RemovedVFunc, 1)  );
                $VTableChanged{$CName} = 1;
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
                            if(not $CompleteSignature{1}{$ASymbol}{"PureVirt"}
                            and not link_symbol($ASymbol, 1, "-Deps")) {
                                next;
                            }
                            my $ProblemType = "Removed_Virtual_Method";
                            if($CompleteSignature{1}{$RemovedVFunc}{"PureVirt"}) {
                                $ProblemType = "Removed_Pure_Virtual_Method";
                            }
                            $CheckedSymbols{$Level}{$ASymbol} = 1;
                            %{$CompatProblems{$Level}{$ASymbol}{$ProblemType}{$tr_name{$RemovedVFunc}}}=(
                                "Type_Name"=>$CName,
                                "Type_Type"=>"Class",
                                "Target"=>get_Signature($RemovedVFunc, 1)  );
                            $VTableChanged{get_TypeName($CompleteSignature{1}{$ASymbol}{"Class"}, 1)} = 1;
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
                    "Type_Type"=>"Class",
                    "Target"=>get_Signature($AddedVFunc, 2)  );
            }
        }
        foreach my $RemovedVFunc (keys(%{$RemovedInt_Virt{$Level}{$CName}}))
        {
            if($CompleteSignature{1}{$RemovedVFunc}{"PureVirt"})
            {
                %{$CompatProblems{$Level}{$Interface}{"Removed_Pure_Virtual_Method"}{$tr_name{$RemovedVFunc}}}=(
                    "Type_Name"=>$CName,
                    "Type_Type"=>"Class",
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

my %Severity_Val=(
    "High"=>3,
    "Medium"=>2,
    "Low"=>1,
    "Safe"=>-1
);

sub maxSeverity($$)
{
    my ($S1, $S2) = @_;
    if(cmpSeverities($S1, $S2)) {
        return $S1;
    }
    else {
        return $S2;
    }
}

sub cmpSeverities($$)
{
    my ($S1, $S2) = @_;
    if(not $S1) {
        return 0;
    }
    elsif(not $S2) {
        return 1;
    }
    return ($Severity_Val{$S1}>$Severity_Val{$S2});
}

sub getProblemSeverity($$)
{
    my ($Level, $Kind) = @_;
    return $CompatRules{$Level}{$Kind}{"Severity"};
}

sub isRecurType($$$$)
{
    foreach (@RecurTypes)
    {
        if($_->{"Tid1"} eq $_[0]
        and $_->{"TDid1"} eq $_[1]
        and $_->{"Tid2"} eq $_[2]
        and $_->{"TDid2"} eq $_[3])
        {
            return 1;
        }
    }
    return 0;
}

sub pushType($$$$)
{
    my %TypeIDs=(
        "Tid1"  => $_[0],
        "TDid1" => $_[1],
        "Tid2"  => $_[2],
        "TDid2" => $_[3]  );
    push(@RecurTypes, \%TypeIDs);
}

sub isRenamed($$$$$)
{
    my ($MemPos, $Type1, $LVersion1, $Type2, $LVersion2) = @_;
    my $Member_Name = $Type1->{"Memb"}{$MemPos}{"name"};
    my $MemberType_Id = $Type1->{"Memb"}{$MemPos}{"type"};
    my %MemberType_Pure = get_PureType($Tid_TDid{$LVersion1}{$MemberType_Id}, $MemberType_Id, $LVersion1);
    if(not defined $Type2->{"Memb"}{$MemPos}) {
        return "";
    }
    my $StraightPairType_Id = $Type2->{"Memb"}{$MemPos}{"type"};
    my %StraightPairType_Pure = get_PureType($Tid_TDid{$LVersion2}{$StraightPairType_Id}, $StraightPairType_Id, $LVersion2);
    
    my $StraightPair_Name = $Type2->{"Memb"}{$MemPos}{"name"};
    my $MemberPair_Pos_Rev = ($Member_Name eq $StraightPair_Name)?$MemPos:find_MemberPair_Pos_byName($StraightPair_Name, $Type1);
    if($MemberPair_Pos_Rev eq "lost")
    {
        if($MemberType_Pure{"Name"} eq $StraightPairType_Pure{"Name"})
        {# base type match
            return $StraightPair_Name;
        }
        if(get_TypeName($MemberType_Id, $LVersion1) eq get_TypeName($StraightPairType_Id, $LVersion2))
        {# exact type match
            return $StraightPair_Name;
        }
        if($MemberType_Pure{"Size"} eq $StraightPairType_Pure{"Size"})
        {# size match
            return $StraightPair_Name;
        }
        if(isReserved($StraightPair_Name))
        {# reserved fields
            return $StraightPair_Name;
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
    if($T1->{"Name"} ne $T2->{"Name"}
    and not isAnon($T1->{"Name"})
    and not isAnon($T2->{"Name"}))
    { # different names
        if($T1->{"Type"} ne "Pointer"
        or $T2->{"Type"} ne "Pointer")
        { # compare base types
            return 1;
        }
        if($T1->{"Name"}!~/\Avoid\s*\*/
        and $T2->{"Name"}=~/\Avoid\s*\*/)
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

sub mergeTypes($$$$$)
{
    my ($Type1_Id, $Type1_DId, $Type2_Id, $Type2_DId, $Level) = @_;
    return () if((not $Type1_Id and not $Type1_DId) or (not $Type2_Id and not $Type2_DId));
    $Type1_DId = "" if(not defined $Type1_DId);
    $Type2_DId = "" if(not defined $Type2_DId);
    my (%Sub_SubProblems, %SubProblems) = ();
    if($Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId})
    { # already merged
        return %{$Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId}};
    }
    my %Type1 = get_Type($Type1_DId, $Type1_Id, 1);
    my %Type2 = get_Type($Type2_DId, $Type2_Id, 2);
    my %Type1_Pure = get_PureType($Type1_DId, $Type1_Id, 1);
    my %Type2_Pure = get_PureType($Type2_DId, $Type2_Id, 2);
    $CheckedTypes{$Level}{$Type1{"Name"}}=1;
    $CheckedTypes{$Level}{$Type1_Pure{"Name"}}=1;
    return () if(not $Type1_Pure{"Size"} or not $Type2_Pure{"Size"});
    if(isRecurType($Type1_Pure{"Tid"}, $Type1_Pure{"TDid"}, $Type2_Pure{"Tid"}, $Type2_Pure{"TDid"}))
    { # skip recursive declarations
        return ();
    }
    return () if(not $Type1_Pure{"Name"} or not $Type2_Pure{"Name"});
    return () if($SkipTypes{1}{$Type1_Pure{"Name"}});
    return () if($SkipTypes{1}{$Type1{"Name"}});
    
    my %Typedef_1 = goToFirst($Type1{"TDid"}, $Type1{"Tid"}, 1, "Typedef");
    my %Typedef_2 = goToFirst($Type2{"TDid"}, $Type2{"Tid"}, 2, "Typedef");
    if(not $UseOldDumps and %Typedef_1 and %Typedef_2
    and $Typedef_1{"Type"} eq "Typedef" and $Typedef_2{"Type"} eq "Typedef"
    and $Typedef_1{"Name"} eq $Typedef_2{"Name"})
    {
        my %Base_1 = get_OneStep_BaseType($Typedef_1{"TDid"}, $Typedef_1{"Tid"}, 1);
        my %Base_2 = get_OneStep_BaseType($Typedef_2{"TDid"}, $Typedef_2{"Tid"}, 2);
        if(differentDumps("G")
        or differentDumps("V"))
        { # different GCC versions or different dumps
            $Base_1{"Name"} = uncover_typedefs($Base_1{"Name"}, 1);
            $Base_2{"Name"} = uncover_typedefs($Base_2{"Name"}, 2);
            # std::__va_list and __va_list
            $Base_1{"Name"}=~s/\A(\w+::)+//;
            $Base_2{"Name"}=~s/\A(\w+::)+//;
            $Base_1{"Name"} = formatName($Base_1{"Name"});
            $Base_2{"Name"} = formatName($Base_2{"Name"});
        }
        if($Base_1{"Name"}!~/anon\-/ and $Base_2{"Name"}!~/anon\-/
        and $Base_1{"Name"} ne $Base_2{"Name"})
        {
            if($Level eq "Binary"
            and $Type1{"Size"} ne $Type2{"Size"})
            {
                %{$SubProblems{"DataType_Size"}{$Typedef_1{"Name"}}}=(
                    "Target"=>$Typedef_1{"Name"},
                    "Type_Name"=>$Typedef_1{"Name"},
                    "Type_Type"=>"Typedef",
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE  );
            }
            %{$SubProblems{"Typedef_BaseType"}{$Typedef_1{"Name"}}}=(
                "Target"=>$Typedef_1{"Name"},
                "Type_Name"=>$Typedef_1{"Name"},
                "Type_Type"=>"Typedef",
                "Old_Value"=>$Base_1{"Name"},
                "New_Value"=>$Base_2{"Name"}  );
        }
    }
    if(nonComparable(\%Type1_Pure, \%Type2_Pure))
    { # different types (reported in detectTypeChange(...))
        if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"}
        and $Type1_Pure{"Type"} ne $Type2_Pure{"Type"}
        and $Type1_Pure{"Type"}!~/Intrinsic|Pointer|Ref|Typedef/)
        { # different type of the type
            %{$SubProblems{"DataType_Type"}{$Type1_Pure{"Name"}}}=(
                "Target"=>$Type1_Pure{"Name"},
                "Type_Name"=>$Type1_Pure{"Name"},
                "Type_Type"=>$Type1_Pure{"Type"},
                "Old_Value"=>lc($Type1_Pure{"Type"}),
                "New_Value"=>lc($Type2_Pure{"Type"})  );
        }
        %{$Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId}} = %SubProblems;
        return %SubProblems;
    }
    pushType($Type1_Pure{"Tid"}, $Type1_Pure{"TDid"},
             $Type2_Pure{"Tid"}, $Type2_Pure{"TDid"});
    if(($Type1_Pure{"Name"} eq $Type2_Pure{"Name"}
    or (isAnon($Type1_Pure{"Name"}) and isAnon($Type2_Pure{"Name"})))
    and $Type1_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
    { # checking size
        if($Level eq "Binary"
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
                    else {
                        # descreased size of allocable class
                        # it has no special effects
                    }
                }
            }
            %{$SubProblems{$ProblemKind}{$Type1_Pure{"Name"}}}=(
                "Target"=>$Type1_Pure{"Name"},
                "Type_Name"=>$Type1_Pure{"Name"},
                "Type_Type"=>$Type1_Pure{"Type"},
                "Old_Size"=>$Type1_Pure{"Size"}*$BYTE_SIZE,
                "New_Size"=>$Type2_Pure{"Size"}*$BYTE_SIZE,
                "InitialType_Type"=>$Type1_Pure{"Type"}  );
        }
    }
    if($Type1_Pure{"BaseType"}{"Tid"} and $Type2_Pure{"BaseType"}{"Tid"})
    {# checking base types
        %Sub_SubProblems = mergeTypes($Type1_Pure{"BaseType"}{"Tid"}, $Type1_Pure{"BaseType"}{"TDid"},
                                       $Type2_Pure{"BaseType"}{"Tid"}, $Type2_Pure{"BaseType"}{"TDid"}, $Level);
        foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
        {
            foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
            {
                foreach my $Attr (keys(%{$Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}})) {
                    $SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{$Attr} = $Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{$Attr};
                }
                $SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{"InitialType_Type"} = $Type1_Pure{"Type"};
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
                    if(not checkDumpVersion(2, "2.1")) {
                        next;
                    }
                }
                if(my $RenamedTo = isRenamed($Member_Pos, \%Type1_Pure, 1, \%Type2_Pure, 2))
                { # renamed
                    $RenamedField{$Member_Pos}=$RenamedTo;
                    $RenamedField_Rev{$NameToPosB{$RenamedTo}}=$Member_Name;
                }
                else
                { # removed
                    $RemovedField{$Member_Pos}=1;
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
                        $RenamedField{$Member_Pos}=$RenamedTo;
                        $RenamedField_Rev{$NameToPosB{$RenamedTo}}=$Member_Name;
                    }
                    else {
                        $RemovedField{$Member_Pos}=1;
                    }
                }
                else
                { # removed
                    $RemovedField{$Member_Pos}=1;
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
                if(not checkDumpVersion(1, "2.1")) {
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
                $RelPos{1}{$Member_Name}=$Pos;
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
                $RelPos{2}{$Member_Name}=$Pos;
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
                        my $MemSize1 = get_TypeSize($Type1_Pure{"Memb"}{$AbsPos1}{"type"}, 1);
                        my $MovedAbsPos = $AbsPos{1}{$RPos2};
                        my $MemSize2 = get_TypeSize($Type1_Pure{"Memb"}{$MovedAbsPos}{"type"}, 1);
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
                        "Type_Type"=>$Type1_Pure{"Type"},
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
        if(my $RenamedTo = $RenamedField{$Member_Pos})
        { # renamed
            if($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
                if(isPublic(\%Type1_Pure, $Member_Pos))
                {
                    %{$SubProblems{"Renamed_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"},
                        "Old_Value"=>$Member_Name,
                        "New_Value"=>$RenamedTo  );
                }
            }
            elsif($Type1_Pure{"Type"} eq "Enum")
            {
                %{$SubProblems{"Enum_Member_Name"}{$Type1_Pure{"Memb"}{$Member_Pos}{"value"}}}=(
                    "Target"=>$Type1_Pure{"Memb"}{$Member_Pos}{"value"},
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Type_Type"=>$Type1_Pure{"Type"},
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
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Type_Type"=>$Type1_Pure{"Type"}  );
            }
            elsif($Type2_Pure{"Type"} eq "Union")
            {
                if($Level eq "Binary"
                and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                {
                    %{$SubProblems{"Removed_Union_Field_And_Size"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"}  );
                }
                else
                {
                    %{$SubProblems{"Removed_Union_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"}  );
                }
            }
            elsif($Type1_Pure{"Type"} eq "Enum")
            {
                %{$SubProblems{"Enum_Member_Removed"}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Type_Type"=>$Type1_Pure{"Type"},
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
                    %{$SubProblems{$ProblemType}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"},
                        "Old_Value"=>$Member_Value1,
                        "New_Value"=>$Member_Value2  );
                }
            }
            elsif($Type2_Pure{"Type"}=~/\A(Struct|Class|Union)\Z/)
            {
                my $MemberType1_Id = $Type1_Pure{"Memb"}{$Member_Pos}{"type"};
                my $MemberType2_Id = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"type"};
                my $SizeV1 = get_TypeSize($MemberType1_Id, 1)*$BYTE_SIZE;
                if(my $BSize1 = $Type1_Pure{"Memb"}{$Member_Pos}{"bitfield"}) {
                    $SizeV1 = $BSize1;
                }
                my $SizeV2 = get_TypeSize($MemberType2_Id, 2)*$BYTE_SIZE;
                if(my $BSize2 = $Type2_Pure{"Memb"}{$MemberPair_Pos}{"bitfield"}) {
                    $SizeV2 = $BSize2;
                }
                my $MemberType1_Name = get_TypeName($MemberType1_Id, 1);
                my $MemberType2_Name = get_TypeName($MemberType2_Id, 2);
                if($Level eq "Binary"
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
                        if(not isMemPadded($Member_Pos, get_TypeSize($MemberType2_Id, 2)*$BYTE_SIZE, \%Type1_Pure, \%RemovedField, 1))
                        { # check an effect
                            if(my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
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
                            $ProblemType = "";
                        }
                        if($ProblemType)
                        { # register a problem
                            %{$SubProblems{$ProblemType}{$Member_Name}}=(
                                "Target"=>$Member_Name,
                                "Type_Name"=>$Type1_Pure{"Name"},
                                "Type_Type"=>$Type1_Pure{"Type"},
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
                %Sub_SubProblems = detectTypeChange($MemberType1_Id, $MemberType2_Id, "Field", $Level);
                foreach my $ProblemType (keys(%Sub_SubProblems))
                {
                    my $Old_Value = $Sub_SubProblems{$ProblemType}{"Old_Value"};
                    my $New_Value = $Sub_SubProblems{$ProblemType}{"New_Value"};
                    if($ProblemType eq "Field_Type"
                    or $ProblemType eq "Field_Type_And_Size")
                    {
                        if(checkDumpVersion(1, "2.6") and checkDumpVersion(2, "2.6"))
                        {
                            if($Level eq "Binary")
                            {
                                if($Old_Value!~/(\A|\W)volatile(\W|\Z)/
                                and $New_Value=~/(\A|\W)volatile(\W|\Z)/)
                                { # non-"volatile" to "volatile"
                                    %{$Sub_SubProblems{"Field_Became_Volatile"}} = %{$Sub_SubProblems{$ProblemType}};
                                }
                                elsif($Old_Value=~/(\A|\W)volatile(\W|\Z)/
                                and $New_Value!~/(\A|\W)volatile(\W|\Z)/)
                                { # non-"volatile" to "volatile"
                                    %{$Sub_SubProblems{"Field_Became_NonVolatile"}} = %{$Sub_SubProblems{$ProblemType}};
                                }
                            }
                            else
                            { # Source
                                if(removedQual($New_Value, $Old_Value, "volatile"))
                                { # non-"volatile" to "volatile"
                                    %{$Sub_SubProblems{"Field_Became_Volatile"}} = %{$Sub_SubProblems{$ProblemType}};
                                    delete($Sub_SubProblems{$ProblemType});
                                }
                                elsif(removedQual($Old_Value, $New_Value, "volatile"))
                                { # non-"volatile" to "volatile"
                                    %{$Sub_SubProblems{"Field_Became_NonVolatile"}} = %{$Sub_SubProblems{$ProblemType}};
                                    delete($Sub_SubProblems{$ProblemType});
                                }
                            }
                        }
                    }
                }
                foreach my $ProblemType (keys(%Sub_SubProblems))
                {
                    my $ProblemType_Init = $ProblemType;
                    if($ProblemType eq "Field_Type_And_Size")
                    { # Binary
                        if(not isPublic(\%Type1_Pure, $Member_Pos)
                        or isUnnamed($Member_Name)) {
                            $ProblemType = "Private_".$ProblemType;
                        }
                        if(not isMemPadded($Member_Pos, get_TypeSize($MemberType2_Id, 2)*$BYTE_SIZE, \%Type1_Pure, \%RemovedField, 1))
                        { # check an effect
                            if(my $MNum = isAccessible(\%Type1_Pure, \%RemovedField, $Member_Pos+1, -1))
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
                        if(not isPublic(\%Type1_Pure, $Member_Pos)
                        or isUnnamed($Member_Name)) {
                            next;
                        }
                    }
                    if($ProblemType eq "Private_Field_Type_And_Size")
                    { # private field change with no effect
                        next;
                    }
                    %{$SubProblems{$ProblemType}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"}  );
                    foreach my $Attr (keys(%{$Sub_SubProblems{$ProblemType_Init}}))
                    { # other properties
                        $SubProblems{$ProblemType}{$Member_Name}{$Attr} = $Sub_SubProblems{$ProblemType_Init}{$Attr};
                    }
                }
                if(not isPublic(\%Type1_Pure, $Member_Pos))
                { # do NOT check internal type changes
                    next;
                }
                if($MemberType1_Id and $MemberType2_Id)
                {# checking member type changes (replace)
                    %Sub_SubProblems = mergeTypes($MemberType1_Id, $Tid_TDid{1}{$MemberType1_Id},
                                                  $MemberType2_Id, $Tid_TDid{2}{$MemberType2_Id}, $Level);
                    foreach my $Sub_SubProblemType (keys(%Sub_SubProblems))
                    {
                        foreach my $Sub_SubLocation (keys(%{$Sub_SubProblems{$Sub_SubProblemType}}))
                        {
                            my $NewLocation = ($Sub_SubLocation)?$Member_Name."->".$Sub_SubLocation:$Member_Name;
                            $SubProblems{$Sub_SubProblemType}{$NewLocation}{"IsInTypeInternals"}=1;
                            foreach my $Attr (keys(%{$Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}})) {
                                $SubProblems{$Sub_SubProblemType}{$NewLocation}{$Attr} = $Sub_SubProblems{$Sub_SubProblemType}{$Sub_SubLocation}{$Attr};
                            }
                            if($Sub_SubLocation!~/\-\>/) {
                                $SubProblems{$Sub_SubProblemType}{$NewLocation}{"Start_Type_Name"} = $MemberType1_Name;
                            }
                        }
                    }
                }
            }
        }
    }
    foreach my $Member_Pos (sort {int($a) <=> int($b)} keys(%{$Type2_Pure{"Memb"}}))
    { # checking added members, public and private
        my $Member_Name = $Type2_Pure{"Memb"}{$Member_Pos}{"name"};
        next if(not $Member_Name);
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
                    "Type_Name"=>$Type1_Pure{"Name"},
                    "Type_Type"=>$Type1_Pure{"Type"}  );
            }
            elsif($Type2_Pure{"Type"} eq "Union")
            {
                if($Level eq "Binary"
                and $Type1_Pure{"Size"} ne $Type2_Pure{"Size"})
                {
                    %{$SubProblems{"Added_Union_Field_And_Size"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"}  );
                }
                else
                {
                    %{$SubProblems{"Added_Union_Field"}{$Member_Name}}=(
                        "Target"=>$Member_Name,
                        "Type_Name"=>$Type1_Pure{"Name"},
                        "Type_Type"=>$Type1_Pure{"Type"}  );
                }
            }
            elsif($Type2_Pure{"Type"} eq "Enum")
            {
                my $Member_Value = $Type2_Pure{"Memb"}{$Member_Pos}{"value"};
                next if($Member_Value eq "");
                %{$SubProblems{"Added_Enum_Member"}{$Member_Name}}=(
                    "Target"=>$Member_Name,
                    "Type_Name"=>$Type2_Pure{"Name"},
                    "Type_Type"=>$Type2_Pure{"Type"},
                    "New_Value"=>$Member_Value  );
            }
        }
    }
    %{$Cache{"mergeTypes"}{$Level}{$Type1_Id}{$Type1_DId}{$Type2_Id}{$Type2_DId}} = %SubProblems;
    pop(@RecurTypes);
    return %SubProblems;
}

sub isUnnamed($) {
    return $_[0]=~/\Aunnamed\d+\Z/;
}

sub get_TypeName($$)
{
    my ($TypeId, $LibVersion) = @_;
    return get_TypeAttr($TypeId, $LibVersion, "Name");
}

sub get_TypeSize($$)
{
    my ($TypeId, $LibVersion) = @_;
    return get_TypeAttr($TypeId, $LibVersion, "Size");
}

sub get_TypeAttr($$$)
{
    my ($TypeId, $LibVersion, $Attr) = @_;
    return "" if(not defined $TypeId);
    if(not defined $Tid_TDid{$LibVersion}{$TypeId})
    { # correcting data
        $Tid_TDid{$LibVersion}{$TypeId} = "";
    }
    return $TypeInfo{$LibVersion}{$Tid_TDid{$LibVersion}{$TypeId}}{$TypeId}{$Attr};
}

sub get_ShortType($$)
{
    my ($TypeId, $LibVersion) = @_;
    my $TypeName = get_TypeAttr($TypeId, $LibVersion, "Name");
    if(my $NameSpace = get_TypeAttr($TypeId, $LibVersion, "NameSpace")) {
        $TypeName=~s/\A$NameSpace\:\://g;
    }
    return $TypeName;
}

sub goToFirst($$$$)
{
    my ($TypeDId, $TypeId, $LibVersion, $Type_Type) = @_;
    if(defined $Cache{"goToFirst"}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type}) {
        return %{$Cache{"goToFirst"}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type}};
    }
    return () if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    return () if(not $Type{"Type"});
    if($Type{"Type"} ne $Type_Type)
    {
        return () if(not $Type{"BaseType"}{"TDid"} and not $Type{"BaseType"}{"Tid"});
        %Type = goToFirst($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion, $Type_Type);
    }
    $Cache{"goToFirst"}{$TypeDId}{$TypeId}{$LibVersion}{$Type_Type} = \%Type;
    return %Type;
}

my %TypeSpecAttributes = (
    "Const" => 1,
    "Volatile" => 1,
    "ConstVolatile" => 1,
    "Restrict" => 1,
    "Typedef" => 1
);

sub get_PureType($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    $TypeDId = "" if(not defined $TypeDId);
    if(defined $Cache{"get_PureType"}{$TypeDId}{$TypeId}{$LibVersion}) {
        return %{$Cache{"get_PureType"}{$TypeDId}{$TypeId}{$LibVersion}};
    }
    return () if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    return %Type if(not $Type{"BaseType"}{"TDid"} and not $Type{"BaseType"}{"Tid"});
    if($TypeSpecAttributes{$Type{"Type"}}) {
        %Type = get_PureType($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
    }
    $Cache{"get_PureType"}{$TypeDId}{$TypeId}{$LibVersion} = \%Type;
    return %Type;
}

sub get_PointerLevel($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return 0 if(not $TypeId);
    $TypeDId = "" if(not defined $TypeDId);
    if(defined $Cache{"get_PointerLevel"}{$TypeDId}{$TypeId}{$LibVersion}) {
        return $Cache{"get_PointerLevel"}{$TypeDId}{$TypeId}{$LibVersion};
    }
    return 0 if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    return 1 if($Type{"Type"}=~/FuncPtr|MethodPtr|FieldPtr/);
    return 0 if(not $Type{"BaseType"}{"TDid"} and not $Type{"BaseType"}{"Tid"});
    my $PointerLevel = 0;
    if($Type{"Type"} =~/Pointer|Ref|FuncPtr|MethodPtr|FieldPtr/) {
        $PointerLevel += 1;
    }
    $PointerLevel += get_PointerLevel($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
    $Cache{"get_PointerLevel"}{$TypeDId}{$TypeId}{$LibVersion} = $PointerLevel;
    return $PointerLevel;
}

sub get_BaseType($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    $TypeDId = "" if(not defined $TypeDId);
    if(defined $Cache{"get_BaseType"}{$TypeDId}{$TypeId}{$LibVersion}) {
        return %{$Cache{"get_BaseType"}{$TypeDId}{$TypeId}{$LibVersion}};
    }
    return () if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    return %Type if(not $Type{"BaseType"}{"TDid"} and not $Type{"BaseType"}{"Tid"});
    %Type = get_BaseType($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
    $Cache{"get_BaseType"}{$TypeDId}{$TypeId}{$LibVersion} = \%Type;
    return %Type;
}

sub get_BaseTypeQual($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return "" if(not $TypeId);
    return "" if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    return "" if(not $Type{"BaseType"}{"TDid"} and not $Type{"BaseType"}{"Tid"});
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
    my $BQual = get_BaseTypeQual($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
    return $BQual.$Qual;
}

sub get_OneStep_BaseType($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    return () if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    my %Type = %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
    if(not $Type{"BaseType"}{"TDid"}
    and not $Type{"BaseType"}{"Tid"}) {
        return %Type;
    }
    return get_Type($Type{"BaseType"}{"TDid"}, $Type{"BaseType"}{"Tid"}, $LibVersion);
}

sub get_Type($$$)
{
    my ($TypeDId, $TypeId, $LibVersion) = @_;
    return () if(not $TypeId);
    $TypeDId = "" if(not defined $TypeDId);
    return () if(not $TypeInfo{$LibVersion}{$TypeDId}{$TypeId});
    return %{$TypeInfo{$LibVersion}{$TypeDId}{$TypeId}};
}

sub skipGlobalData($)
{
    my $Symbol = $_[0];
    return ($Symbol=~/\A(_ZGV|_ZTI|_ZTS|_ZTT|_ZTV|_ZTC|_ZThn|_ZTv0_n)/);
}

sub isTemplateInstance($)
{
    my $Symbol = $_[0];
    return 0 if($Symbol!~/\A(_Z|\?)/);
    my $Signature = $tr_name{$Symbol};
    return 0 if($Signature!~/>/);
    my $ShortName = substr($Signature, 0, detect_center($Signature, "("));
    $ShortName=~s/::operator .*//;# class::operator template<instance>
    return ($ShortName=~/<.+>/);
}

sub isTemplateSpec($$)
{
    my ($Symbol, $LibVersion) = @_;
    if(my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"})
    {
        if(get_TypeAttr($ClassId, $LibVersion, "Spec"))
        { # class specialization
            return 1;
        }
        elsif($CompleteSignature{$LibVersion}{$Symbol}{"Spec"})
        { # method specialization
            return 1;
        }
    }
    return 0;
}

sub symbolFilter($$$$)
{ # some special cases when the symbol cannot be imported
    my ($Symbol, $LibVersion, $Type, $Level) = @_;
    if(skipGlobalData($Symbol))
    { # non-public global data
        return 0;
    }
    if($CheckObjectsOnly) {
        return 0 if($Symbol=~/\A(_init|_fini)\Z/);
    }
    if($CheckHeadersOnly and not checkDumpVersion($LibVersion, "2.7"))
    { # support for old ABI dumps in --headers-only mode
        foreach my $Pos (keys(%{$CompleteSignature{$LibVersion}{$Symbol}{"Param"}}))
        {
            if(my $Pid = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$Pos}{"type"})
            {
                my $PType = get_TypeAttr($Pid, $LibVersion, "Type");
                if(not $PType or $PType eq "Unknown") {
                    return 0;
                }
            }
        }
    }
    if($Type=~/Imported/)
    {
        my $ClassId = $CompleteSignature{$LibVersion}{$Symbol}{"Class"};
        if(not $STDCXX_TESTING and $Symbol=~/\A(_ZS|_ZNS|_ZNKS)/)
        { # stdc++ interfaces
            return 0;
        }
        if($SkipSymbols{$LibVersion}{$Symbol})
        { # user defined symbols to ignore
            return 0;
        }
        my $NameSpace = $CompleteSignature{$LibVersion}{$Symbol}{"NameSpace"};
        if(not $NameSpace and $ClassId)
        { # class methods have no "NameSpace" attribute
            $NameSpace = get_TypeAttr($ClassId, $LibVersion, "NameSpace");
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
        if(my $Header = $CompleteSignature{$LibVersion}{$Symbol}{"Header"})
        {
            if(my $Skip = skip_header($Header, $LibVersion))
            { # --skip-headers or <skip_headers> (not <skip_including>)
                if($Skip==1) {
                    return 0;
                }
            }
            if(not is_target_header($Header))
            { # --header, --headers-list
                return 0;
            }
        }
        if($SymbolsListPath and not $SymbolsList{$Symbol})
        { # user defined symbols
            return 0;
        }
        if($AppPath and not $SymbolsList_App{$Symbol})
        { # user defined symbols (in application)
            return 0;
        }
        if($Level eq "Binary")
        {
            if($CompleteSignature{$LibVersion}{$Symbol}{"InLine"}
            or (isTemplateInstance($Symbol) and not isTemplateSpec($Symbol, $LibVersion)))
            {
                if($ClassId and $CompleteSignature{$LibVersion}{$Symbol}{"Virt"})
                { # inline virtual methods
                    if($Type=~/InlineVirtual/) {
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

sub mergeImpl()
{
    my $DiffCmd = get_CmdPath("diff");
    if(not $DiffCmd) {
        exitStatus("Not_Found", "can't find \"diff\"");
    }
    foreach my $Interface (sort keys(%{$Symbol_Library{1}}))
    { # implementation changes
        next if($CompleteSignature{1}{$Interface}{"Private"});
        next if(not $CompleteSignature{1}{$Interface}{"Header"} and not $CheckObjectsOnly);
        next if(not $Symbol_Library{2}{$Interface} and not $Symbol_Library{2}{$SymVer{2}{$Interface}});
        next if(not symbolFilter($Interface, 1, "Imported", "Binary"));
        my $Impl1 = canonify_implementation($Interface_Impl{1}{$Interface});
        next if(not $Impl1);
        my $Impl2 = canonify_implementation($Interface_Impl{2}{$Interface});
        next if(not $Impl2);
        if($Impl1 ne $Impl2)
        {
            writeFile("$TMP_DIR/impl1", $Impl1);
            writeFile("$TMP_DIR/impl2", $Impl2);
            my $Diff = `$DiffCmd -rNau $TMP_DIR/impl1 $TMP_DIR/impl2`;
            $Diff=~s/(---|\+\+\+).+\n//g;
            $Diff=~s/[ ]{3,}/ /g;
            $Diff=~s/\n\@\@/\n \n\@\@/g;
            unlink("$TMP_DIR/impl1", "$TMP_DIR/impl2");
            %{$ImplProblems{$Interface}}=(
                "Diff" => get_CodeView($Diff)  );
        }
    }
}

sub canonify_implementation($)
{
    my $FuncBody=  $_[0];
    return "" if(not $FuncBody);
    $FuncBody=~s/0x[a-f\d]+/0x?/g;# addr
    $FuncBody=~s/((\A|\n)[a-z]+[\t ]+)[a-f\d]+([^x]|\Z)/$1?$3/g;# call, jump
    $FuncBody=~s/# [a-f\d]+ /# ? /g;# call, jump
    $FuncBody=~s/%([a-z]+[a-f\d]*)/\%reg/g;# registers
    while($FuncBody=~s/\nnop[ \t]*(\n|\Z)/$1/g){};# empty op
    $FuncBody=~s/<.+?\.cpp.+?>/<name.cpp>/g;
    $FuncBody=~s/(\A|\n)[a-f\d]+ </$1? </g;# 5e74 <_ZN...
    $FuncBody=~s/\.L\d+/.L/g;
    $FuncBody=~s/#(-?)\d+/#$1?/g;# r3, [r3, #120]
    $FuncBody=~s/[\n]{2,}/\n/g;
    return $FuncBody;
}

sub get_CodeView($)
{
    my $Code = $_[0];
    my $View = "";
    foreach my $Line (split(/\n/, $Code))
    {
        if($Line=~s/\A(\+|-)/$1 /g)
        { # bold line
            $View .= "<tr><td><b>".htmlSpecChars($Line)."</b></td></tr>\n";
        }
        else {
            $View .= "<tr><td>".htmlSpecChars($Line)."</td></tr>\n";
        }
    }
    return "<table class='code_view'>$View</table>\n";
}

sub getImplementations($$)
{
    my ($LibVersion, $Path) = @_;
    return if(not $LibVersion or not -e $Path);
    if($OSgroup eq "macos")
    {
        my $OtoolCmd = get_CmdPath("otool");
        if(not $OtoolCmd) {
            exitStatus("Not_Found", "can't find \"otool\"");
        }
        my $CurInterface = "";
        foreach my $Line (split(/\n/, `$OtoolCmd -tv $Path 2>$TMP_DIR/null`))
        {
            if($Line=~/\A\s*_(\w+)\s*:/i) {
                $CurInterface = $1;
            }
            elsif($Line=~/\A\s*[\da-z]+\s+(.+?)\Z/i) {
                $Interface_Impl{$LibVersion}{$CurInterface} .= "$1\n";
            }
        }
    }
    else
    {
        my $ObjdumpCmd = get_CmdPath("objdump");
        if(not $ObjdumpCmd) {
            exitStatus("Not_Found", "can't find \"objdump\"");
        }
        my $CurInterface = "";
        foreach my $Line (split(/\n/, `$ObjdumpCmd -d $Path 2>$TMP_DIR/null`))
        {
            if($Line=~/\A[\da-z]+\s+<(\w+)>/i) {
                $CurInterface = $1;
            }
            else
            { # x86:    51fa:(\t)89 e5               (\t)mov    %esp,%ebp
              # arm:    5020:(\t)e24cb004(\t)sub(\t)fp, ip, #4(\t); 0x4
                if($Line=~/\A\s*[a-f\d]+:\s+([a-f\d]+\s+)+([a-z]+\s+.*?)\s*(;.*|)\Z/i) {
                    $Interface_Impl{$LibVersion}{$CurInterface} .= "$2\n";
                }
            }
        }
    }
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
        and $Symbol!~/\@/) {
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
        if($CheckObjectsOnly) {
            $CheckedSymbols{"Binary"}{$Symbol} = 1;
        }
        if(link_symbol($Symbol, 2, "+Deps"))
        { # linker can find an old symbol
          # in the new-version library
            next;
        }
        if(my $VSym = $SymVer{1}{$Symbol}
        and $Symbol!~/\@/) {
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
        next if(not $CompleteSignature{2}{$Symbol}{"Header"} and not $CheckObjectsOnly);
        next if(not symbolFilter($Symbol, 2, "Imported", $Level));
        %{$CompatProblems{$Level}{$Symbol}{"Added_Symbol"}{""}}=();
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # checking removed symbols
        next if($CompleteSignature{1}{$Symbol}{"Private"});
        next if(not $CompleteSignature{1}{$Symbol}{"Header"} and not $CheckObjectsOnly);
        if($Symbol=~/\A_ZTV/)
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
        }
        else {
            next if(not symbolFilter($Symbol, 1, "Imported", $Level));
        }
        if($CompleteSignature{1}{$Symbol}{"PureVirt"})
        { # symbols for pure virtual methods cannot be called by clients
            next;
        }
        %{$CompatProblems{$Level}{$Symbol}{"Removed_Symbol"}{""}}=();
    }
}

sub checkDumpVersion($$)
{
    my ($LibVersion, $DumpVersion) = @_;
    return (not $UsedDump{$LibVersion}{"V"} or cmpVersions($UsedDump{$LibVersion}{"V"}, $DumpVersion)>=0);
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
        }
        if(not $CompleteSignature{2}{$Symbol}{"Header"}) {
            next;
        }
        if($GeneratedSymbols{$Symbol}) {
            next;
        }
        if(not defined $CompleteSignature{1}{$Symbol}
        or not $CompleteSignature{1}{$Symbol}{"MnglName"})
        {
            if(($UsedDump{1}{"BinOnly"} and $UsedDump{2}{"SrcBin"})
            or (not checkDumpVersion(1, "2.11") and checkDumpVersion(2, "2.11")))
            { # support for old and different (!) ABI dumps
                if(not $CompleteSignature{2}{$Symbol}{"Virt"}
                and not $CompleteSignature{2}{$Symbol}{"PureVirt"})
                {
                    if($CheckHeadersOnly)
                    {
                        if($CompleteSignature{2}{$Symbol}{"InLine"})
                        { # skip added inline symbols
                            next;
                        }
                    }
                    else
                    {
                        if(not link_symbol($Symbol, 2, "-Deps"))
                        { # skip added inline symbols
                            next;
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
        if(not $CompleteSignature{1}{$Symbol}{"Header"}) {
            next;
        }
        if($GeneratedSymbols{$Symbol}) {
            next;
        }
        if(not defined $CompleteSignature{2}{$Symbol}
        or not $CompleteSignature{2}{$Symbol}{"MnglName"})
        { # support for old and different (!) ABI dumps
            if(($UsedDump{1}{"SrcBin"} and $UsedDump{2}{"BinOnly"})
            or (checkDumpVersion(1, "2.11") and not checkDumpVersion(2, "2.11")))
            {
                if(not $CompleteSignature{1}{$Symbol}{"Virt"}
                and not $CompleteSignature{1}{$Symbol}{"PureVirt"})
                {
                    if($CheckHeadersOnly)
                    {
                        if($CompleteSignature{1}{$Symbol}{"InLine"})
                        { # skip added inline symbols
                            next;
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
        if($Level eq "Binary") {
            next if($CompleteSignature{2}{$Symbol}{"InLine"});
        }
        else
        { # Source
            if($SourceAlternative_B{$Symbol}) {
                next;
            }
        }
        next if($CompleteSignature{2}{$Symbol}{"Private"});
        next if(not symbolFilter($Symbol, 2, "Imported", $Level));
        %{$CompatProblems{$Level}{$Symbol}{"Added_Symbol"}{""}}=();
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # checking removed symbols
        next if($CompleteSignature{1}{$Symbol}{"PureVirt"});
        if($Level eq "Binary") {
            next if($CompleteSignature{1}{$Symbol}{"InLine"});
        }
        else
        { # Source
            if($SourceAlternative{$Symbol}) {
                next;
            }
        }
        next if($CompleteSignature{1}{$Symbol}{"Private"});
        next if(not symbolFilter($Symbol, 1, "Imported", $Level));
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
        {# add absent parameter names
            my $ParamName = $CompleteSignature{$LibraryVersion}{$Interface}{"Param"}{$ParamPos}{"name"};
            if($ParamName=~/\Ap\d+\Z/ and my $NewParamName = $AddIntParams{$Interface}{$ParamPos})
            {# names from the external file
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
{ # detect changed typedefs to create correct function signatures
    foreach my $Typedef (keys(%{$Typedef_BaseName{1}}))
    {
        next if(not $Typedef);
        next if(isAnon($Typedef_BaseName{1}{$Typedef}));
        next if(isAnon($Typedef_BaseName{2}{$Typedef}));
        next if(not $Typedef_BaseName{1}{$Typedef});
        next if(not $Typedef_BaseName{2}{$Typedef});# exclude added/removed
        if($Typedef_BaseName{1}{$Typedef} ne $Typedef_BaseName{2}{$Typedef}) {
            $ChangedTypedef{$Typedef} = 1;
        }
    }
}

sub get_symbol_suffix($$)
{
    my ($Symbol, $Full) = @_;
    my ($SN, $SO, $SV) = separate_symbol($Symbol);
    $Symbol=$SN;# remove version
    my $Signature = $tr_name{$Symbol};
    my $Suffix = substr($Signature, detect_center($Signature, "("));
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
        $ShortName = get_TypeName($ClassId, $LibVersion)."::".$ShortName;
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

sub mergeSignatures($)
{
    my $Level = $_[0];
    my %SubProblems = ();
    
    registerVTable(1, $Level);
    registerVTable(2, $Level);

    if(not checkDumpVersion(1, "1.22")
    and checkDumpVersion(2, "1.22"))
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
    
    addParamNames(1);
    addParamNames(2);
    
    detectChangedTypedefs();
    mergeBases($Level);
    
    my %AddedOverloads = ();
    foreach my $Symbol (sort keys(%{$AddedInt{$Level}}))
    { # check all added exported symbols
        if(not $CompleteSignature{2}{$Symbol}{"Header"}) {
            next;
        }
        if($CheckHeadersOnly or $Level eq "Source")
        {
            if(defined $CompleteSignature{1}{$Symbol}
            and $CompleteSignature{1}{$Symbol}{"Header"})
            { # double-check added symbol
                next;
            }
        }
        if(not symbolFilter($Symbol, 2, "Imported", $Level)) {
            next;
        }
        if($Symbol=~/\A(_Z|\?)/)
        { # C++
            $AddedOverloads{get_symbol_prefix($Symbol, 2)}{get_symbol_suffix($Symbol, 1)} = $Symbol;
        }
        if(my $OverriddenMethod = $CompleteSignature{2}{$Symbol}{"Override"})
        { # register virtual overridings
            my $AffectedClass_Name = get_TypeName($CompleteSignature{2}{$Symbol}{"Class"}, 2);
            if(defined $CompleteSignature{1}{$OverriddenMethod}
            and $CompleteSignature{1}{$OverriddenMethod}{"Virt"} and $ClassToId{1}{$AffectedClass_Name}
            and not $CompleteSignature{1}{$OverriddenMethod}{"Private"})
            { # public virtual methods, virtual destructors: class should exist in previous version
                if(isCopyingClass($ClassToId{1}{$AffectedClass_Name}, 1))
                { # old v-table (copied) will be used by applications
                    next;
                }
                if(defined $CompleteSignature{1}{$Symbol}
                and $CompleteSignature{1}{$Symbol}{"InLine"})
                { # auto-generated virtual destructors stay in the header (and v-table), added to library
                  # use case: Ice 3.3.1 -> 3.4.0
                    next;
                }
                %{$CompatProblems{$Level}{$OverriddenMethod}{"Overridden_Virtual_Method"}{$tr_name{$Symbol}}}=(
                    "Type_Name"=>$AffectedClass_Name,
                    "Type_Type"=>"Class",
                    "Target"=>get_Signature($Symbol, 2),
                    "Old_Value"=>get_Signature($OverriddenMethod, 2),
                    "New_Value"=>get_Signature($Symbol, 2)  );
            }
        }
    }
    foreach my $Symbol (sort keys(%{$RemovedInt{$Level}}))
    { # check all removed exported symbols
        if(not $CompleteSignature{1}{$Symbol}{"Header"}) {
            next;
        }
        if($CheckHeadersOnly or $Level eq "Source")
        {
            if(defined $CompleteSignature{2}{$Symbol}
            and $CompleteSignature{2}{$Symbol}{"Header"})
            { # double-check removed symbol
                next;
            }
        }
        if($CompleteSignature{1}{$Symbol}{"Private"})
        { # skip private methods
            next;
        }
        if(not symbolFilter($Symbol, 1, "Imported", $Level)) {
            next;
        }
        $CheckedSymbols{$Level}{$Symbol} = 1;
        if(my $OverriddenMethod = $CompleteSignature{1}{$Symbol}{"Override"})
        { # register virtual overridings
            my $AffectedClass_Name = get_TypeName($CompleteSignature{1}{$Symbol}{"Class"}, 1);
            if(defined $CompleteSignature{2}{$OverriddenMethod}
            and $CompleteSignature{2}{$OverriddenMethod}{"Virt"} and $ClassToId{2}{$AffectedClass_Name})
            { # virtual methods, virtual destructors: class should exist in newer version
                if(isCopyingClass($CompleteSignature{1}{$Symbol}{"Class"}, 1))
                { # old v-table (copied) will be used by applications
                    next;
                }
                if(defined $CompleteSignature{2}{$Symbol}
                and $CompleteSignature{2}{$Symbol}{"InLine"})
                { # auto-generated virtual destructors stay in the header (and v-table), removed from library
                  # use case: Ice 3.3.1 -> 3.4.0
                    next;
                }
                %{$CompatProblems{$Level}{$Symbol}{"Overridden_Virtual_Method_B"}{$tr_name{$OverriddenMethod}}}=(
                    "Type_Name"=>$AffectedClass_Name,
                    "Type_Type"=>"Class",
                    "Target"=>get_Signature($OverriddenMethod, 1),
                    "Old_Value"=>get_Signature($Symbol, 1),
                    "New_Value"=>get_Signature($OverriddenMethod, 1)  );
            }
        }
        if($Level eq "Binary"
        and $OSgroup eq "windows")
        { # register the reason of symbol name change
            if(my $NewSymbol = $mangled_name{2}{$tr_name{$Symbol}})
            {
                if($AddedInt{$Level}{$NewSymbol})
                {
                    if($CompleteSignature{1}{$Symbol}{"Static"} ne $CompleteSignature{2}{$NewSymbol}{"Static"})
                    {
                        if($CompleteSignature{2}{$NewSymbol}{"Static"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Static"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSymbol  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_NonStatic"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSymbol  );
                        }
                    }
                    if($CompleteSignature{1}{$Symbol}{"Virt"} ne $CompleteSignature{2}{$NewSymbol}{"Virt"})
                    {
                        if($CompleteSignature{2}{$NewSymbol}{"Virt"})
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Virtual"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSymbol  );
                        }
                        else
                        {
                            %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_NonVirtual"}{$tr_name{$Symbol}}}=(
                                "Target"=>$tr_name{$Symbol},
                                "Old_Value"=>$Symbol,
                                "New_Value"=>$NewSymbol  );
                        }
                    }
                    my $ReturnTypeName1 = get_TypeName($CompleteSignature{1}{$Symbol}{"Return"}, 1);
                    my $ReturnTypeName2 = get_TypeName($CompleteSignature{2}{$NewSymbol}{"Return"}, 2);
                    if($ReturnTypeName1 ne $ReturnTypeName2)
                    {
                        my $ProblemType = "Symbol_Changed_Return";
                        if($CompleteSignature{1}{$Symbol}{"Data"}) {
                            $ProblemType = "Global_Data_Symbol_Changed_Type";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "Old_Type"=>$ReturnTypeName1,
                            "New_Type"=>$ReturnTypeName2,
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
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
                my $NewSymbol = $AddedOverloads{$Prefix}{$Overloads[0]};
                if($CompleteSignature{1}{$Symbol}{"Constructor"})
                {
                    if($Symbol=~/(C1E|C2E)/) {
                        my $CtorType = $1;
                        $NewSymbol=~s/(C1E|C2E)/$CtorType/g;
                    }
                }
                elsif($CompleteSignature{1}{$Symbol}{"Destructor"})
                {
                    if($Symbol=~/(D0E|D1E|D2E)/) {
                        my $DtorType = $1;
                        $NewSymbol=~s/(D0E|D1E|D2E)/$DtorType/g;
                    }
                }
                my $NS1 = $CompleteSignature{1}{$Symbol}{"NameSpace"};
                my $NS2 = $CompleteSignature{2}{$NewSymbol}{"NameSpace"};
                if((not $NS1 and not $NS2) or ($NS1 and $NS2 and $NS1 eq $NS2))
                { # from the same class and namespace
                    if($CompleteSignature{1}{$Symbol}{"Const"}
                    and not $CompleteSignature{2}{$NewSymbol}{"Const"})
                    { # "const" to non-"const"
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_NonConst"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSymbol, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
                    }
                    elsif(not $CompleteSignature{1}{$Symbol}{"Const"}
                    and $CompleteSignature{2}{$NewSymbol}{"Const"})
                    { # non-"const" to "const"
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Const"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSymbol, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
                    }
                    if($CompleteSignature{1}{$Symbol}{"Volatile"}
                    and not $CompleteSignature{2}{$NewSymbol}{"Volatile"})
                    { # "volatile" to non-"volatile"
                        
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_NonVolatile"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSymbol, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
                    }
                    elsif(not $CompleteSignature{1}{$Symbol}{"Volatile"}
                    and $CompleteSignature{2}{$NewSymbol}{"Volatile"})
                    { # non-"volatile" to "volatile"
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Became_Volatile"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSymbol, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
                    }
                    if(get_symbol_suffix($Symbol, 0) ne get_symbol_suffix($NewSymbol, 0))
                    { # params list
                        %{$CompatProblems{$Level}{$Symbol}{"Symbol_Changed_Parameters"}{$tr_name{$Symbol}}}=(
                            "Target"=>$tr_name{$Symbol},
                            "New_Signature"=>get_Signature($NewSymbol, 2),
                            "Old_Value"=>$Symbol,
                            "New_Value"=>$NewSymbol  );
                    }
                }
            }
        }
    }
    foreach my $Symbol (sort keys(%{$CompleteSignature{1}}))
    { # checking symbols
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
        if($CheckHeadersOnly)
        { # skip added and removed pure virtual methods
            next if(not $CompleteSignature{1}{$Symbol}{"PureVirt"} and $CompleteSignature{2}{$PSymbol}{"PureVirt"});
            next if($CompleteSignature{1}{$Symbol}{"PureVirt"} and not $CompleteSignature{2}{$PSymbol}{"PureVirt"});
        }
        elsif($Level eq "Binary")
        { # skip non-exported, added and removed functions except pure virtual methods
            if(not link_symbol($Symbol, 1, "-Deps")
            or not link_symbol($PSymbol, 2, "-Deps"))
            { # symbols from target library(ies) only
              # excluding dependent libraries
                if(not $CompleteSignature{1}{$Symbol}{"PureVirt"}
                or not $CompleteSignature{2}{$PSymbol}{"PureVirt"}) {
                    next;
                }
            }
        }
        if(not symbolFilter($Symbol, 1, "Imported|InlineVirtual", $Level))
        { # symbols that cannot be imported at binary-level
          # or used at source-level
            next;
        }
        # checking virtual table
        if($CompleteSignature{1}{$Symbol}{"Class"}) {
            mergeVirtualTables($Symbol, $Level);
        }
        if($COMPILE_ERRORS)
        { # if some errors occurred at the compiling stage
          # then some false positives can be skipped here
            if(not $CompleteSignature{1}{$Symbol}{"Data"} and $CompleteSignature{2}{$PSymbol}{"Data"}
            and not $CompleteSignature{2}{$Symbol}{"Object"})
            { # missed information about parameters in newer version
                next;
            }
            if($CompleteSignature{1}{$Symbol}{"Data"} and not $CompleteSignature{1}{$Symbol}{"Object"}
            and not $CompleteSignature{2}{$PSymbol}{"Data"})
            {# missed information about parameters in older version
                next;
            }
        }
        my ($MnglName, $VersionSpec, $SymbolVersion) = separate_symbol($Symbol);
        # checking attributes
        if($CompleteSignature{2}{$PSymbol}{"Static"}
        and not $CompleteSignature{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/) {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_Static"}{""}}=(
                "Target"=>get_Signature($Symbol, 1)
            );
        }
        elsif(not $CompleteSignature{2}{$PSymbol}{"Static"}
        and $CompleteSignature{1}{$Symbol}{"Static"} and $Symbol=~/\A(_Z|\?)/) {
            %{$CompatProblems{$Level}{$Symbol}{"Method_Became_NonStatic"}{""}}=(
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
                    my $Class_Name = get_TypeName($Class_Id, 1);
                    if(defined $VirtualTable{1}{$Class_Name} and defined $VirtualTable{2}{$Class_Name}
                    and $VirtualTable{1}{$Class_Name}{$Symbol}!=$VirtualTable{2}{$Class_Name}{$Symbol})
                    { # check the absolute position of virtual method (including added and removed methods)
                        my %Class_Type = get_Type($Tid_TDid{1}{$Class_Id}, $Class_Id, 1);
                        my $ProblemType = "Virtual_Method_Position";
                        if($CompleteSignature{1}{$Symbol}{"PureVirt"}) {
                            $ProblemType = "Pure_Virtual_Method_Position";
                        }
                        if(isUsedClass($Class_Id, 1, $Level))
                        {
                            my @Affected = ($Symbol, keys(%{$OverriddenMethods{1}{$Symbol}}));
                            foreach my $AffectedInterface (@Affected)
                            {
                                %{$CompatProblems{$Level}{$AffectedInterface}{$ProblemType}{$tr_name{$MnglName}}}=(
                                    "Type_Name"=>$Class_Type{"Name"},
                                    "Type_Type"=>"Class",
                                    "Old_Value"=>$CompleteSignature{1}{$Symbol}{"RelPos"},
                                    "New_Value"=>$CompleteSignature{2}{$PSymbol}{"RelPos"},
                                    "Target"=>get_Signature($Symbol, 1)  );
                            }
                            $VTableChanged{$Class_Type{"Name"}} = 1;
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
        $CheckedSymbols{$Level}{$Symbol}=1;
        if($Symbol=~/\A(_Z|\?)/
        or keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})==keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}}))
        { # C/C++: changes in parameters
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # checking parameters
                mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level);
            }
        }
        else
        { # C: added/removed parameters
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}}))
            { # checking added parameters
                my $PType2_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                last if(get_TypeName($PType2_Id, 2) eq "...");
                my $Parameter_Name = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"name"};
                my $Parameter_OldName = (defined $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos})?$CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_Prev = "-1";
                if($Parameter_Name=~/\Ap\d+\Z/i)
                { # added unnamed parameter ( pN )
                    my @Positions1 = find_ParamPair_Pos_byTypeAndPos(get_TypeName($PType2_Id, 2), $ParamPos, "backward", $Symbol, 1);
                    my @Positions2 = find_ParamPair_Pos_byTypeAndPos(get_TypeName($PType2_Id, 2), $ParamPos, "backward", $Symbol, 2);
                    if($#Positions1==-1 or $#Positions2>$#Positions1) {
                        $ParamPos_Prev = "lost";
                    }
                }
                else {
                    $ParamPos_Prev = find_ParamPair_Pos_byName($Parameter_Name, $Symbol, 1);
                }
                if($ParamPos_Prev eq "lost")
                {
                    if($ParamPos>keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Added_Parameter";
                        if($Parameter_Name=~/\Ap\d+\Z/) {
                            $ProblemType = "Added_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showNum($ParamPos)." Parameter"}}=(
                            "Target"=>$Parameter_Name,
                            "Param_Pos"=>$ParamPos,
                            "Param_Type"=>get_TypeName($PType2_Id, 2),
                            "New_Signature"=>get_Signature($Symbol, 2)  );
                    }
                    else
                    {
                        my %ParamType_Pure = get_PureType($Tid_TDid{2}{$PType2_Id}, $PType2_Id, 2);
                        my $ParamStraightPairType_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                        my %ParamStraightPairType_Pure = get_PureType($Tid_TDid{1}{$ParamStraightPairType_Id}, $ParamStraightPairType_Id, 1);
                        if(($ParamType_Pure{"Name"} eq $ParamStraightPairType_Pure{"Name"} or get_TypeName($PType2_Id, 2) eq get_TypeName($ParamStraightPairType_Id, 1))
                        and find_ParamPair_Pos_byName($Parameter_OldName, $Symbol, 2) eq "lost")
                        {
                            if($Parameter_OldName!~/\Ap\d+\Z/ and $Parameter_Name!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showNum($ParamPos)." Parameter"}}=(
                                    "Target"=>$Parameter_OldName,
                                    "Param_Pos"=>$ParamPos,
                                    "Param_Type"=>get_TypeName($PType2_Id, 2),
                                    "Old_Value"=>$Parameter_OldName,
                                    "New_Value"=>$Parameter_Name,
                                    "New_Signature"=>get_Signature($Symbol, 2)  );
                            }
                        }
                        else
                        {
                            my $ProblemType = "Added_Middle_Parameter";
                            if($Parameter_Name=~/\Ap\d+\Z/) {
                                $ProblemType = "Added_Middle_Unnamed_Parameter";
                            }
                            %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showNum($ParamPos)." Parameter"}}=(
                                "Target"=>$Parameter_Name,
                                "Param_Pos"=>$ParamPos,
                                "Param_Type"=>get_TypeName($PType2_Id, 2),
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
                    if(($ParamName1!~/\Ap\d+\Z/i and $ParamName1 eq $ParamName2)
                    or get_TypeName($PType1_Id, 1) eq get_TypeName($PType2_Id, 2)) {
                        mergeParameters($Symbol, $PSymbol, $ParamPos, $ParamPos, $Level);
                    }
                }
            }
            foreach my $ParamPos (sort {int($a) <=> int($b)} keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # checking removed parameters
                my $PType1_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"type"};
                last if(get_TypeName($PType1_Id, 1) eq "...");
                my $Parameter_Name = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos}{"name"};
                my $Parameter_NewName = (defined $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos})?$CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"name"}:"";
                my $ParamPos_New = "-1";
                if($Parameter_Name=~/\Ap\d+\Z/i)
                { # removed unnamed parameter ( pN )
                    my @Positions1 = find_ParamPair_Pos_byTypeAndPos(get_TypeName($PType1_Id, 1), $ParamPos, "forward", $Symbol, 1);
                    my @Positions2 = find_ParamPair_Pos_byTypeAndPos(get_TypeName($PType1_Id, 1), $ParamPos, "forward", $Symbol, 2);
                    if($#Positions2==-1 or $#Positions2<$#Positions1) {
                        $ParamPos_New = "lost";
                    }
                }
                else {
                    $ParamPos_New = find_ParamPair_Pos_byName($Parameter_Name, $Symbol, 2);
                }
                if($ParamPos_New eq "lost")
                {
                    if($ParamPos>keys(%{$CompleteSignature{2}{$PSymbol}{"Param"}})-1)
                    {
                        my $ProblemType = "Removed_Parameter";
                        if($Parameter_Name=~/\Ap\d+\Z/) {
                            $ProblemType = "Removed_Unnamed_Parameter";
                        }
                        %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showNum($ParamPos)." Parameter"}}=(
                            "Target"=>$Parameter_Name,
                            "Param_Pos"=>$ParamPos,
                            "Param_Type"=>get_TypeName($PType1_Id, 1),
                            "New_Signature"=>get_Signature($Symbol, 2)  );
                    }
                    elsif($ParamPos<keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})-1)
                    {
                        my %ParamType_Pure = get_PureType($Tid_TDid{1}{$PType1_Id}, $PType1_Id, 1);
                        my $ParamStraightPairType_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos}{"type"};
                        my %ParamStraightPairType_Pure = get_PureType($Tid_TDid{2}{$ParamStraightPairType_Id}, $ParamStraightPairType_Id, 2);
                        if(($ParamType_Pure{"Name"} eq $ParamStraightPairType_Pure{"Name"} or get_TypeName($PType1_Id, 1) eq get_TypeName($ParamStraightPairType_Id, 2))
                        and find_ParamPair_Pos_byName($Parameter_NewName, $Symbol, 1) eq "lost")
                        {
                            if($Parameter_NewName!~/\Ap\d+\Z/ and $Parameter_Name!~/\Ap\d+\Z/)
                            {
                                %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showNum($ParamPos)." Parameter"}}=(
                                    "Target"=>$Parameter_Name,
                                    "Param_Pos"=>$ParamPos,
                                    "Param_Type"=>get_TypeName($PType1_Id, 1),
                                    "Old_Value"=>$Parameter_Name,
                                    "New_Value"=>$Parameter_NewName,
                                    "New_Signature"=>get_Signature($Symbol, 2)  );
                            }
                        }
                        else
                        {
                            my $ProblemType = "Removed_Middle_Parameter";
                            if($Parameter_Name=~/\Ap\d+\Z/) {
                                $ProblemType = "Removed_Middle_Unnamed_Parameter";
                            }
                            %{$CompatProblems{$Level}{$Symbol}{$ProblemType}{showNum($ParamPos)." Parameter"}}=(
                                "Target"=>$Parameter_Name,
                                "Param_Pos"=>$ParamPos,
                                "Param_Type"=>get_TypeName($PType1_Id, 1),
                                "New_Signature"=>get_Signature($Symbol, 2)  );
                        }
                    }
                }
            }
        }
        # checking return type
        my $ReturnType1_Id = $CompleteSignature{1}{$Symbol}{"Return"};
        my $ReturnType2_Id = $CompleteSignature{2}{$PSymbol}{"Return"};
        %SubProblems = detectTypeChange($ReturnType1_Id, $ReturnType2_Id, "Return", $Level);
        foreach my $SubProblemType (keys(%SubProblems))
        {
            my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
            my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
            my $NewProblemType = $SubProblemType;
            if($Level eq "Binary" and $SubProblemType eq "Return_Type_Became_Void"
            and keys(%{$CompleteSignature{1}{$Symbol}{"Param"}}))
            { # parameters stack has been affected
                $NewProblemType = "Return_Type_Became_Void_And_Stack_Layout";
            }
            elsif($Level eq "Binary"
            and $SubProblemType eq "Return_Type_From_Void")
            { # parameters stack has been affected
                if(keys(%{$CompleteSignature{1}{$Symbol}{"Param"}})) {
                    $NewProblemType = "Return_Type_From_Void_And_Stack_Layout";
                }
                else
                { # safe
                    delete($SubProblems{$SubProblemType});
                    next;
                }
            }
            elsif($SubProblemType eq "Return_Type_And_Size"
            and $CompleteSignature{1}{$Symbol}{"Data"}) {
                $NewProblemType = "Global_Data_Type_And_Size";
            }
            elsif($SubProblemType eq "Return_Type")
            {
                if($CompleteSignature{1}{$Symbol}{"Data"})
                {
                    if(removedQual($Old_Value, $New_Value, "const"))
                    { # const -> non-const global data
                        $NewProblemType = "Global_Data_Became_Non_Const";
                    }
                    elsif(removedQual($New_Value, $Old_Value, "const"))
                    { # non-const -> const global data
                        $NewProblemType = "Global_Data_Became_Const";
                    }
                    else {
                        $NewProblemType = "Global_Data_Type";
                    }
                }
                else
                {
                    if(removedQual($New_Value, $Old_Value, "const")) {
                        $NewProblemType = "Return_Type_Became_Const";
                    }
                }
            }
            elsif($SubProblemType eq "Return_Type_Format")
            {
                if($CompleteSignature{1}{$Symbol}{"Data"}) {
                    $NewProblemType = "Global_Data_Type_Format";
                }
            }
            @{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{"retval"}}{keys(%{$SubProblems{$SubProblemType}})} = values %{$SubProblems{$SubProblemType}};
        }
        if($ReturnType1_Id and $ReturnType2_Id)
        {
            @RecurTypes = ();
            %SubProblems = mergeTypes($ReturnType1_Id, $Tid_TDid{1}{$ReturnType1_Id},
                                      $ReturnType2_Id, $Tid_TDid{2}{$ReturnType2_Id}, $Level);
            foreach my $SubProblemType (keys(%SubProblems))
            { # add "Global_Data_Size" problem
                my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
                my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
                if($SubProblemType eq "DataType_Size"
                and $CompleteSignature{1}{$Symbol}{"Data"}
                and get_PointerLevel($Tid_TDid{1}{$ReturnType1_Id}, $ReturnType1_Id, 1)==0)
                { # add a new problem
                    %{$SubProblems{"Global_Data_Size"}} = %{$SubProblems{$SubProblemType}};
                }
            }
            foreach my $SubProblemType (keys(%SubProblems))
            {
                foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                {
                    my $NewLocation = ($SubLocation)?"retval->".$SubLocation:"retval";
                    %{$CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}}=(
                        "Return_Type_Name"=>get_TypeName($ReturnType1_Id, 1) );
                    @{$CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}}{keys(%{$SubProblems{$SubProblemType}{$SubLocation}})} = values %{$SubProblems{$SubProblemType}{$SubLocation}};
                    if($SubLocation!~/\-\>/) {
                        $CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($ReturnType1_Id, 1);
                    }
                }
            }
        }
        
        # checking object type
        my $ObjectType1_Id = $CompleteSignature{1}{$Symbol}{"Class"};
        my $ObjectType2_Id = $CompleteSignature{2}{$PSymbol}{"Class"};
        if($ObjectType1_Id and $ObjectType2_Id
        and not $CompleteSignature{1}{$Symbol}{"Static"})
        {
            my $ThisPtr1_Id = getTypeIdByName(get_TypeName($ObjectType1_Id, 1)."*const", 1);
            my $ThisPtr2_Id = getTypeIdByName(get_TypeName($ObjectType2_Id, 2)."*const", 2);
            if($ThisPtr1_Id and $ThisPtr2_Id)
            {
                @RecurTypes = ();
                %SubProblems = mergeTypes($ThisPtr1_Id, $Tid_TDid{1}{$ThisPtr1_Id},
                                          $ThisPtr2_Id, $Tid_TDid{2}{$ThisPtr2_Id}, $Level);
                foreach my $SubProblemType (keys(%SubProblems))
                {
                    foreach my $SubLocation (keys(%{$SubProblems{$SubProblemType}}))
                    {
                        my $NewLocation = ($SubLocation)?"this->".$SubLocation:"this";
                        %{$CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}}=(
                            "Object_Type_Name"=>get_TypeName($ObjectType1_Id, 1) );
                        @{$CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}}{keys(%{$SubProblems{$SubProblemType}{$SubLocation}})} = values %{$SubProblems{$SubProblemType}{$SubLocation}};
                        if($SubLocation!~/\-\>/) {
                            $CompatProblems{$Level}{$Symbol}{$SubProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($ObjectType1_Id, 1);
                        }
                    }
                }
            }
        }
    }
    if($Level eq "Binary") {
        mergeVTables($Level);
    }
}

sub removedQual($$$)
{
    my ($Old_Value, $New_Value, $Qual) = @_;
    if($Old_Value eq $New_Value) {
        return 0;
    }
    while($Old_Value=~s/(\A|\W)$Qual(\W|\Z)/$1$2/)
    { # remove all qualifiers
      # one-by-one, left-to-right
        $Old_Value=~s/\s+\Z//g;
        $Old_Value=~s/\A\s+//g;
        $Old_Value = formatName($Old_Value);
        if($Old_Value eq $New_Value)
        { # compare with a new type
            return 1;
        }
    }
    return 0;
}

sub mergeParameters($$$$$)
{
    my ($Symbol, $PSymbol, $ParamPos1, $ParamPos2, $Level) = @_;
    return if(not $Symbol);
    return if(not defined $CompleteSignature{1}{$Symbol}{"Param"});
    return if(not defined $CompleteSignature{2}{$PSymbol}{"Param"});
    my $PType1_Id = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"type"};
    my $PName1 = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"name"};
    my $PType2_Id = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"type"};
    my $PName2 = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"name"};
    return if(not $PType1_Id or not $PType2_Id);
    my %Type1 = get_Type($Tid_TDid{1}{$PType1_Id}, $PType1_Id, 1);
    my %Type2 = get_Type($Tid_TDid{2}{$PType2_Id}, $PType2_Id, 2);
    my %BaseType1 = get_BaseType($Tid_TDid{1}{$PType1_Id}, $PType1_Id, 1);
    my %BaseType2 = get_BaseType($Tid_TDid{2}{$PType2_Id}, $PType2_Id, 2);
    my $Parameter_Location = ($PName1)?$PName1:showNum($ParamPos1)." Parameter";
    if($Level eq "Binary")
    {
        if(checkDumpVersion(1, "2.6.1") and checkDumpVersion(2, "2.6.1"))
        { # "reg" attribute added in ACC 1.95.1 (dump 2.6.1 format)
            if($CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
            and not $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Non_Register"}{$Parameter_Location}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>$ParamPos1  );
            }
            elsif(not $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"reg"}
            and $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"reg"})
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Became_Register"}{$Parameter_Location}}=(
                    "Target"=>$PName1,
                    "Param_Pos"=>$ParamPos1  );
            }
        }
    }
    if(checkDumpVersion(1, "2.0") and checkDumpVersion(2, "2.0"))
    { # "default" attribute added in ACC 1.22 (dump 2.0 format)
        my $DefaultValue_Old = $CompleteSignature{1}{$Symbol}{"Param"}{$ParamPos1}{"default"};
        my $DefaultValue_New = $CompleteSignature{2}{$PSymbol}{"Param"}{$ParamPos2}{"default"};
        my %PureType1 = get_PureType($Tid_TDid{1}{$PType1_Id}, $PType1_Id, 1);
        if($PureType1{"Name"}=~/\A(char\*|char const\*)\Z/)
        {
            if($DefaultValue_Old)
            { # FIXME: how to distinguish "0" and 0 (NULL)
                $DefaultValue_Old = "\"$DefaultValue_Old\"";
            }
            if($DefaultValue_New) {
                $DefaultValue_New = "\"$DefaultValue_New\"";
            }
        }
        elsif($PureType1{"Name"}=~/\A(char)\Z/)
        {
            if($DefaultValue_Old) {
                $DefaultValue_Old = "\'$DefaultValue_Old\'";
            }
            if($DefaultValue_New) {
                $DefaultValue_New = "\'$DefaultValue_New\'";
            }
        }
        if(defined $DefaultValue_Old
        and $DefaultValue_Old ne "")
        {
            if(defined $DefaultValue_New
            and $DefaultValue_New ne "")
            {
                if($DefaultValue_Old ne $DefaultValue_New)
                {
                    %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Changed"}{$Parameter_Location}}=(
                        "Target"=>$PName1,
                        "Param_Pos"=>$ParamPos1,
                        "Old_Value"=>$DefaultValue_Old,
                        "New_Value"=>$DefaultValue_New  );
                }
            }
            else
            {
                %{$CompatProblems{$Level}{$Symbol}{"Parameter_Default_Value_Removed"}{$Parameter_Location}}=(
                        "Target"=>$PName1,
                        "Param_Pos"=>$ParamPos1,
                        "Old_Value"=>$DefaultValue_Old  );
            }
        }
    }
    if($PName1 and $PName2 and $PName1 ne $PName2
    and $PType1_Id!=-1 and $PType2_Id!=-1
    and $PName1!~/\Ap\d+\Z/ and $PName2!~/\Ap\d+\Z/)
    { # except unnamed "..." value list (Id=-1)
        %{$CompatProblems{$Level}{$Symbol}{"Renamed_Parameter"}{showNum($ParamPos1)." Parameter"}}=(
            "Target"=>$PName1,
            "Param_Pos"=>$ParamPos1,
            "Param_Type"=>get_TypeName($PType1_Id, 1),
            "Old_Value"=>$PName1,
            "New_Value"=>$PName2,
            "New_Signature"=>get_Signature($Symbol, 2)  );
    }
    # checking type change (replace)
    my %SubProblems = detectTypeChange($PType1_Id, $PType2_Id, "Parameter", $Level);
    foreach my $SubProblemType (keys(%SubProblems))
    { # add new problems, remove false alarms
        my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
        my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
        if($SubProblemType eq "Parameter_Type")
        {
            if(checkDumpVersion(1, "2.6") and checkDumpVersion(2, "2.6"))
            {
                if($Level eq "Binary")
                {
                    if($Old_Value!~/(\A|\W)restrict(\W|\Z)/
                    and $New_Value=~/(\A|\W)restrict(\W|\Z)/)
                    { # change to be "restrict"
                        %{$SubProblems{"Parameter_Became_Restrict"}} = %{$SubProblems{$SubProblemType}};
                    }
                    elsif($Old_Value=~/(\A|\W)restrict(\W|\Z)/
                    and $New_Value!~/(\A|\W)restrict(\W|\Z)/)
                    { # change to be "restrict"
                        %{$SubProblems{"Parameter_Became_NonRestrict"}} = %{$SubProblems{$SubProblemType}};
                    }
                }
                else
                {
                    if(removedQual($New_Value, $Old_Value, "restrict"))
                    { # change to be "restrict"
                        %{$SubProblems{"Parameter_Became_Restrict"}} = %{$SubProblems{$SubProblemType}};
                        delete($SubProblems{$SubProblemType});
                    }
                    elsif(removedQual($Old_Value, $New_Value, "restrict"))
                    { # change to be "restrict"
                        %{$SubProblems{"Parameter_Became_NonRestrict"}} = %{$SubProblems{$SubProblemType}};
                        delete($SubProblems{$SubProblemType});
                    }
                }
            }
            if($Type2{"Type"} eq "Const" and $BaseType2{"Name"} eq $Type1{"Name"}
            and $Type1{"Type"}=~/Intrinsic|Class|Struct|Union|Enum/)
            { # int to "int const"
                delete($SubProblems{$SubProblemType});
            }
            if($Type1{"Type"} eq "Const" and $BaseType1{"Name"} eq $Type2{"Name"}
            and $Type2{"Type"}=~/Intrinsic|Class|Struct|Union|Enum/)
            { # "int const" to int
                delete($SubProblems{$SubProblemType});
            }
        }
    }
    foreach my $SubProblemType (keys(%SubProblems))
    { # modify/register problems
        my $New_Value = $SubProblems{$SubProblemType}{"New_Value"};
        my $Old_Value = $SubProblems{$SubProblemType}{"Old_Value"};
        my $NewProblemType = $SubProblemType;
        if($Old_Value eq "..." and $New_Value ne "...")
        { # change from "..." to "int"
            if($ParamPos1==0)
            { # ISO C requires a named argument before "..."
                next;
            }
            $NewProblemType = "Parameter_Became_NonVaList";
        }
        elsif($New_Value eq "..." and $Old_Value ne "...")
        { # change from "int" to "..."
            if($ParamPos2==0)
            { # ISO C requires a named argument before "..."
                next;
            }
            $NewProblemType = "Parameter_Became_VaList";
        }
        elsif($SubProblemType eq "Parameter_Type"
        and removedQual($Old_Value, $New_Value, "const"))
        { # parameter: "const" to non-"const"
            $NewProblemType = "Parameter_Became_Non_Const";
        }
        elsif($Level eq "Binary" and ($SubProblemType eq "Parameter_Type_And_Size"
        or $SubProblemType eq "Parameter_Type"))
        {
            my ($Arch1, $Arch2) = (getArch(1), getArch(2));
            if($Arch1 eq "unknown" or $Arch2 eq "unknown")
            { # if one of the architectures is unknown
                # then set other arhitecture to unknown too
                ($Arch1, $Arch2) = ("unknown", "unknown");
            }
            my ($Method1, $Passed1, $SizeOnStack1, $RegName1) = callingConvention($Symbol, $ParamPos1, 1, $Arch1);
            my ($Method2, $Passed2, $SizeOnStack2, $RegName2) = callingConvention($Symbol, $ParamPos2, 2, $Arch2);
            if($Method1 eq $Method2)
            {
                if($Method1 eq "stack" and $SizeOnStack1 ne $SizeOnStack2) {
                    $NewProblemType = "Parameter_Type_And_Stack";
                }
                elsif($Method1 eq "register" and $RegName1 ne $RegName2) {
                    $NewProblemType = "Parameter_Type_And_Register";
                }
            }
            else
            {
                if($Method1 eq "stack") {
                    $NewProblemType = "Parameter_Type_And_Pass_Through_Register";
                }
                elsif($Method1 eq "register") {
                    $NewProblemType = "Parameter_Type_And_Pass_Through_Stack";
                }
            }
            $SubProblems{$SubProblemType}{"Old_Reg"} = $RegName1;
            $SubProblems{$SubProblemType}{"New_Reg"} = $RegName2;
        }
        %{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$Parameter_Location}}=(
            "Target"=>$PName1,
            "Param_Pos"=>$ParamPos1,
            "New_Signature"=>get_Signature($Symbol, 2) );
        @{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$Parameter_Location}}{keys(%{$SubProblems{$SubProblemType}})} = values %{$SubProblems{$SubProblemType}};
    }
    @RecurTypes = ();
    # checking type definition changes
    my %SubProblems_Merge = mergeTypes($PType1_Id, $Tid_TDid{1}{$PType1_Id}, $PType2_Id, $Tid_TDid{2}{$PType2_Id}, $Level);
    foreach my $SubProblemType (keys(%SubProblems_Merge))
    {
        foreach my $SubLocation (keys(%{$SubProblems_Merge{$SubProblemType}}))
        {
            my $NewProblemType = $SubProblemType;
            if($SubProblemType eq "DataType_Size")
            {
                my $InitialType_Type = $SubProblems_Merge{$SubProblemType}{$SubLocation}{"InitialType_Type"};
                if($InitialType_Type!~/\A(Pointer|Ref)\Z/ and $SubLocation!~/\-\>/)
                { # stack has been affected
                    $NewProblemType = "DataType_Size_And_Stack";
                }
            }
            my $NewLocation = ($SubLocation)?$Parameter_Location."->".$SubLocation:$Parameter_Location;
            %{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$NewLocation}}=(
                "Param_Type"=>get_TypeName($PType1_Id, 1),
                "Param_Pos"=>$ParamPos1,
                "Param_Name"=>$PName1  );
            @{$CompatProblems{$Level}{$Symbol}{$NewProblemType}{$NewLocation}}{keys(%{$SubProblems_Merge{$SubProblemType}{$SubLocation}})} = values %{$SubProblems_Merge{$SubProblemType}{$SubLocation}};
            if($SubLocation!~/\-\>/) {
                $CompatProblems{$Level}{$Symbol}{$NewProblemType}{$NewLocation}{"Start_Type_Name"} = get_TypeName($PType1_Id, 1);
            }
        }
    }
}

sub callingConvention($$$$)
{ # calling conventions for different compilers and operating systems
    my ($Symbol, $ParamPos, $LibVersion, $Arch) = @_;
    my $ParamTypeId = $CompleteSignature{$LibVersion}{$Symbol}{"Param"}{$ParamPos}{"type"};
    my %Type = get_PureType($Tid_TDid{$LibVersion}{$ParamTypeId}, $ParamTypeId, $LibVersion);
    my ($Method, $Alignment, $Passed, $Register) = ("", 0, "", "");
    if($OSgroup=~/\A(linux|macos|freebsd)\Z/)
    { # GCC
        if($Arch eq "x86")
        { # System V ABI Intel386 ("Function Calling Sequence")
          # The stack is word aligned. Although the architecture does not require any
          # alignment of the stack, software convention and the operating system
          # requires that the stack be aligned on a word boundary.

          # Argument words are pushed onto the stack in reverse order (that is, the
          # rightmost argument in C call syntax has the highest address), preserving the
          # stack’s word alignment. All incoming arguments appear on the stack, residing
          # in the stack frame of the caller.

          # An argument’s size is increased, if necessary, to make it a multiple of words.
          # This may require tail padding, depending on the size of the argument.

          # Other areas depend on the compiler and the code being compiled. The stan-
          # dard calling sequence does not define a maximum stack frame size, nor does
          # it restrict how a language system uses the ‘‘unspecified’’ area of the stan-
          # dard stack frame.
            ($Method, $Alignment) = ("stack", 4);
        }
        elsif($Arch eq "x86_64")
        { # System V AMD64 ABI ("Function Calling Sequence")
            ($Method, $Alignment) = ("stack", 8);# eightbyte aligned
        }
        elsif($Arch eq "arm")
        { # Procedure Call Standard for the ARM Architecture
          # The stack must be double-word aligned
            ($Method, $Alignment) = ("stack", 8);# double-word
        }
    }
    elsif($OSgroup eq "windows")
    { # MS C++ Compiler
        if($Arch eq "x86")
        {
            if($ParamPos==0) {
                ($Method, $Register, $Passed) = ("register", "ecx", "value");
            }
            elsif($ParamPos==1) {
                ($Method, $Register, $Passed) = ("register", "edx", "value");
            }
            else {
                ($Method, $Alignment) = ("stack", 4);
            }
        }
        elsif($Arch eq "x86_64")
        {
            if($ParamPos<=3)
            {
                if($Type{"Name"}=~/\A(float|double|long double)\Z/) {
                    ($Method, $Passed) = ("xmm".$ParamPos, "value");
                }
                elsif($Type{"Name"}=~/\A(unsigned |)(short|int|long|long long)\Z/
                or $Type{"Type"}=~/\A(Struct|Union|Enum|Array)\Z/
                or $Type{"Name"}=~/\A(__m64|__m128)\Z/)
                {
                    if($ParamPos==0) {
                        ($Method, $Register, $Passed) = ("register", "rcx", "value");
                    }
                    elsif($ParamPos==1) {
                        ($Method, $Register, $Passed) = ("register", "rdx", "value");
                    }
                    elsif($ParamPos==2) {
                        ($Method, $Register, $Passed) = ("register", "r8", "value");
                    }
                    elsif($ParamPos==3) {
                        ($Method, $Register, $Passed) = ("register", "r9", "value");
                    }
                    if($Type{"Size"}>64
                    or $Type{"Type"} eq "Array") {
                        $Passed = "pointer";
                    }
                }
            }
            else {
                ($Method, $Alignment) = ("stack", 8);# word alignment
            }
        }
    }
    if($Method eq "register") {
        return ("register", $Passed, "", $Register);
    }
    else
    { # on the stack
        if(not $Alignment)
        { # default convention
            $Alignment = $WORD_SIZE{$LibVersion};
        }
        if(not $Passed)
        { # default convention
            $Passed = "value";
        }
        my $SizeOnStack = $Type{"Size"};
        # FIXME: improve stack alignment
        if($SizeOnStack!=$Alignment) {
            $SizeOnStack = int(($Type{"Size"}+$Alignment)/$Alignment)*$Alignment;
        }
        return ("stack", $Passed, $SizeOnStack, "");
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
        if(get_TypeName($PTypeId, $LibVersion) eq $TypeName) {
            push(@Positions, $ParamPos);
        }
    }
    return @Positions;
}

sub getTypeIdByName($$)
{
    my ($TypeName, $Version) = @_;
    return $TName_Tid{$Version}{formatName($TypeName)};
}

sub checkFormatChange($$$)
{
    my ($Type1_Id, $Type2_Id, $Level) = @_;
    my $Type1_DId = $Tid_TDid{1}{$Type1_Id};
    my $Type2_DId = $Tid_TDid{2}{$Type2_Id};
    my %Type1_Pure = get_PureType($Type1_DId, $Type1_Id, 1);
    my %Type2_Pure = get_PureType($Type2_DId, $Type2_Id, 2);
    if($Type1_Pure{"Name"} eq $Type2_Pure{"Name"})
    { # equal types
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
    if($Type1_Pure{"Type"} ne $Type2_Pure{"Type"})
    { # different types
        if($Type1_Pure{"Type"} eq "Intrinsic"
        and $Type2_Pure{"Type"} eq "Enum")
        { # "int" to "enum"
            return 0;
        }
        elsif($Type2_Pure{"Type"} eq "Intrinsic"
        and $Type1_Pure{"Type"} eq "Enum")
        { # "enum" to "int"
            return 0;
        }
        else
        { # "union" to "struct"
          #  ...
            return 1;
        }
    }
    else
    {
        if($Type1_Pure{"Type"} eq "Intrinsic")
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
        elsif($Type1_Pure{"Type"}=~/Class|Struct|Union|Enum/)
        {
            my @Membs1 = keys(%{$Type1_Pure{"Memb"}});
            my @Membs2 = keys(%{$Type2_Pure{"Memb"}});
            if($#Membs1!=$#Membs2)
            { # different number of elements
                return 1;
            }
            if($Type1_Pure{"Type"} eq "Enum")
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
                { # compare elements by type name
                    my $MT1 = get_TypeName($Type1_Pure{"Memb"}{$Pos}{"type"}, 1);
                    my $MT2 = get_TypeName($Type2_Pure{"Memb"}{$Pos}{"type"}, 2);
                    if($MT1 ne $MT2)
                    { # different types
                        return 1;
                    }
                    if($Level eq "Source")
                    {
                        if($Type1_Pure{"Memb"}{$Pos}{"name"} ne $Type2_Pure{"Memb"}{$Pos}{"name"})
                        { # different names
                            return 1;
                        }
                    }
                }
            }
        }
    }
    return 0;
}

sub isScalar($) {
    return ($_[0]=~/\A(unsigned |)(short|int|long|long long)\Z/);
}

sub isFloat($) {
    return ($_[0]=~/\A(float|double|long double)\Z/);
}

sub detectTypeChange($$$$)
{
    my ($Type1_Id, $Type2_Id, $Prefix, $Level) = @_;
    if(not $Type1_Id or not $Type2_Id) {
        return ();
    }
    my %LocalProblems = ();
    my $Type1_DId = $Tid_TDid{1}{$Type1_Id};
    my $Type2_DId = $Tid_TDid{2}{$Type2_Id};
    my %Type1 = get_Type($Type1_DId, $Type1_Id, 1);
    my %Type2 = get_Type($Type2_DId, $Type2_Id, 2);
    my %Type1_Pure = get_PureType($Type1_DId, $Type1_Id, 1);
    my %Type2_Pure = get_PureType($Type2_DId, $Type2_Id, 2);
    my %Type1_Base = ($Type1_Pure{"Type"} eq "Array")?get_OneStep_BaseType($Type1_Pure{"TDid"}, $Type1_Pure{"Tid"}, 1):get_BaseType($Type1_DId, $Type1_Id, 1);
    my %Type2_Base = ($Type2_Pure{"Type"} eq "Array")?get_OneStep_BaseType($Type2_Pure{"TDid"}, $Type2_Pure{"Tid"}, 2):get_BaseType($Type2_DId, $Type2_Id, 2);
    my $Type1_PLevel = get_PointerLevel($Type1_DId, $Type1_Id, 1);
    my $Type2_PLevel = get_PointerLevel($Type2_DId, $Type2_Id, 2);
    return () if(not $Type1{"Name"} or not $Type2{"Name"});
    return () if(not $Type1_Base{"Name"} or not $Type2_Base{"Name"});
    return () if($Type1_PLevel eq "" or $Type2_PLevel eq "");
    if($Type1_Base{"Name"} ne $Type2_Base{"Name"}
    and ($Type1{"Name"} eq $Type2{"Name"} or ($Type1_PLevel>=1 and $Type1_PLevel==$Type2_PLevel
    and $Type1_Base{"Name"} ne "void" and $Type2_Base{"Name"} ne "void")))
    { # base type change
        if($Type1{"Type"} eq "Typedef" and $Type2{"Type"} eq "Typedef"
        and $Type1{"Name"} eq $Type2{"Name"})
        { # will be reported in mergeTypes() as typedef problem
            return ();
        }
        if($Type1_Base{"Name"}!~/anon\-/ and $Type2_Base{"Name"}!~/anon\-/)
        {
            if($Level eq "Binary"
            and $Type1_Base{"Size"} ne $Type2_Base{"Size"}
            and $Type1_Base{"Size"} and $Type2_Base{"Size"})
            {
                %{$LocalProblems{$Prefix."_BaseType_And_Size"}}=(
                    "Old_Value"=>$Type1_Base{"Name"},
                    "New_Value"=>$Type2_Base{"Name"},
                    "Old_Size"=>$Type1_Base{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2_Base{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
            }
            else
            {
                if(checkFormatChange($Type1_Base{"Tid"}, $Type2_Base{"Tid"}, $Level))
                { # format change
                    %{$LocalProblems{$Prefix."_BaseType_Format"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "InitialType_Type"=>$Type1_Pure{"Type"});
                }
                elsif(tNameLock($Type1_Base{"Tid"}, $Type2_Base{"Tid"}))
                {
                    %{$LocalProblems{$Prefix."_BaseType"}}=(
                        "Old_Value"=>$Type1_Base{"Name"},
                        "New_Value"=>$Type2_Base{"Name"},
                        "InitialType_Type"=>$Type1_Pure{"Type"});
                }
            }
        }
    }
    elsif($Type1{"Name"} ne $Type2{"Name"})
    { # type change
        if($Type1{"Name"}!~/anon\-/ and $Type2{"Name"}!~/anon\-/)
        {
            if($Prefix eq "Return" and $Type1{"Name"} eq "void"
            and $Type2_Pure{"Type"}=~/Intrinsic|Enum/) {
                # safe change
            }
            elsif($Level eq "Binary"
            and $Prefix eq "Return"
            and $Type1_Pure{"Name"} eq "void")
            {
                %{$LocalProblems{"Return_Type_From_Void"}}=(
                    "New_Value"=>$Type2{"Name"},
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
            }
            elsif($Level eq "Binary"
            and $Prefix eq "Return" and $Type1_Pure{"Type"}=~/Intrinsic|Enum/
            and $Type2_Pure{"Type"}=~/Struct|Class|Union/)
            { # returns into hidden first parameter instead of a register
                
                # System V ABI Intel386 ("Function Calling Sequence")
                # A function that returns an integral or pointer value places its result in register %eax.

                # A floating-point return value appears on the top of the Intel387 register stack. The
                # caller then must remove the value from the Intel387 stack, even if it doesn’t use the
                # value.

                # If a function returns a structure or union, then the caller provides space for the
                # return value and places its address on the stack as argument word zero. In effect,
                # this address becomes a ‘‘hidden’’ first argument.
                
                %{$LocalProblems{"Return_Type_From_Register_To_Stack"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "New_Value"=>$Type2{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
            }
            elsif($Prefix eq "Return"
            and $Type2_Pure{"Name"} eq "void")
            {
                %{$LocalProblems{"Return_Type_Became_Void"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
            }
            elsif($Level eq "Binary" and $Prefix eq "Return"
            and ((isScalar($Type1_Pure{"Name"}) and isFloat($Type2_Pure{"Name"}))
            or (isScalar($Type2_Pure{"Name"}) and isFloat($Type1_Pure{"Name"}))))
            { # The scalar and floating-point values are passed in different registers
                %{$LocalProblems{"Return_Type_And_Register"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "New_Value"=>$Type2{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
            }
            elsif($Level eq "Binary"
            and $Prefix eq "Return" and $Type2_Pure{"Type"}=~/Intrinsic|Enum/
            and $Type1_Pure{"Type"}=~/Struct|Class|Union/)
            { # returns in a register instead of a hidden first parameter
                %{$LocalProblems{"Return_Type_From_Stack_To_Register"}}=(
                    "Old_Value"=>$Type1{"Name"},
                    "New_Value"=>$Type2{"Name"},
                    "Old_Size"=>$Type1{"Size"}*$BYTE_SIZE,
                    "New_Size"=>$Type2{"Size"}*$BYTE_SIZE,
                    "InitialType_Type"=>$Type1_Pure{"Type"});
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
                        "New_Size"=>$Type2{"Size"}*$BYTE_SIZE,
                        "InitialType_Type"=>$Type1_Pure{"Type"});
                }
                else
                {
                    if(checkFormatChange($Type1_Id, $Type2_Id, $Level))
                    { # format change
                        %{$LocalProblems{$Prefix."_Type_Format"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "InitialType_Type"=>$Type1_Pure{"Type"});
                    }
                    elsif(tNameLock($Type1_Id, $Type2_Id))
                    { # FIXME: correct this condition
                        %{$LocalProblems{$Prefix."_Type"}}=(
                            "Old_Value"=>$Type1{"Name"},
                            "New_Value"=>$Type2{"Name"},
                            "InitialType_Type"=>$Type1_Pure{"Type"});
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
                if($Type2_PLevel>$Type1_PLevel) {
                    %{$LocalProblems{$Prefix."_PointerLevel_Increased"}}=(
                        "Old_Value"=>$Type1_PLevel,
                        "New_Value"=>$Type2_PLevel);
                }
                else {
                    %{$LocalProblems{$Prefix."_PointerLevel_Decreased"}}=(
                        "Old_Value"=>$Type1_PLevel,
                        "New_Value"=>$Type2_PLevel);
                }
            }
        }
    }
    if($Type1_Pure{"Type"} eq "Array")
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
    if(differentDumps("G")
    or differentDumps("V"))
    { # different formats
        if($UseOldDumps)
        { # old dumps
            return 0;
        }
        my $TN1 = get_TypeName($Tid1, 1);
        my $TN2 = get_TypeName($Tid2, 2);
        my %Base1 = get_Type($Tid_TDid{1}{$Tid1}, $Tid1, 1);
        while($Base1{"Type"} eq "Typedef") {
            %Base1 = get_OneStep_BaseType($Base1{"TDid"}, $Base1{"Tid"}, 1);
        }
        my %Base2 = get_Type($Tid_TDid{2}{$Tid2}, $Tid2, 2);
        while($Base2{"Type"} eq "Typedef") {
            %Base2 = get_OneStep_BaseType($Base2{"TDid"}, $Base2{"Tid"}, 2);
        }
        my $Base1 = uncover_typedefs($Base1{"Name"}, 1);
        my $Base2 = uncover_typedefs($Base2{"Name"}, 2);
        if($TN1 ne $TN2
        and $Base1 eq $Base2)
        { # equal base types
            return 0;
        }
        if(not checkDumpVersion(1, "2.6")
        or not checkDumpVersion(2, "2.6"))
        {
            if($TN1!~/(\A|\W)restrict(\W|\Z)/
            and $TN2=~/(\A|\W)restrict(\W|\Z)/) {
                return 0;
            }
        }
        
    }
    return 1;
}

sub differentDumps($)
{
    my $Check = $_[0];
    if($UsedDump{1}{"V"} and $UsedDump{2}{"V"})
    {
        if($Check eq "G")
        {
            if(getGccVersion(1) ne getGccVersion(2))
            { # different GCC versions
                return 1;
            }
        }
        if($Check eq "V")
        {
            if(cmpVersions(formatVersion($UsedDump{1}{"V"}, 2),
            formatVersion($UsedDump{2}{"V"}, 2))!=0)
            { # different dump versions (skip micro version)
                return 1;
            }
        }
    }
    return 0;
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
    if($Str eq "") {
        return "";
    }
    $Str=~s/\&([^#]|\Z)/&amp;$1/g;
    $Str=~s/</&lt;/g;
    $Str=~s/\-\>/&#45;&gt;/g; # &minus;
    $Str=~s/>/&gt;/g;
    $Str=~s/([^ ])( )([^ ])/$1\@ALONE_SP\@$3/g;
    $Str=~s/ /&#160;/g; # &nbsp;
    $Str=~s/\@ALONE_SP\@/ /g;
    $Str=~s/\n/<br\/>/g;
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
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
    if($CheckObjectsOnly) {
        $ItalicParams=$ColorParams=0;
    }
    my ($Signature, $VersionSpec, $SymbolVersion) = separate_symbol($FullSignature);
    my $Return = "";
    if($ShowRetVal and $Signature=~s/([^:]):([^:].+?)\Z/$1/g) {
        $Return = $2;
    }
    my $SCenter = detect_center($Signature, "(");
    if(not $SCenter)
    { # global data
        $Signature = htmlSpecChars($Signature);
        $Signature=~s!(\[data\])!<span style='color:Black;font-weight:normal;'>$1</span>!g;
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
    my @SParts = get_s_params($Signature, 1);
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
        if(not $ParamName) {
            push(@Parts, $Part_Styled);
            next;
        }
        if($ItalicParams and not $TName_Tid{1}{$Part}
        and not $TName_Tid{2}{$Part})
        {
            if($Param_Pos ne ""
            and $Pos==$Param_Pos) {
                $Part_Styled =~ s!(\W)$ParamName([\,\)]|\Z)!$1<span class='focus_p'>$ParamName</span>$2!ig;
            }
            elsif($ColorParams) {
                $Part_Styled =~ s!(\W)$ParamName([\,\)]|\Z)!$1<span class='color_p'>$ParamName</span>$2!ig;
            }
            else {
                $Part_Styled =~ s!(\W)$ParamName([\,\)]|\Z)!$1<span style='font-style:italic;'>$ParamName</span>$2!ig;
            }
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
    $Signature=~s!(\[in-charge\]|\[not-in-charge\]|\[in-charge-deleting\]|\[static\])!<span class='sym_kind'>$1</span>!g;
    return $Signature.(($SymbolVersion)?"<span class='sym_ver'>&#160;$VersionSpec&#160;$SymbolVersion</span>":"");
}

sub get_s_params($$)
{
    my ($Signature, $Comma) = @_;
    my @Parts = ();
    my $ShortName = substr($Signature, 0, detect_center($Signature, "("));
    $Signature=~s/\A\Q$ShortName\E\(//g;
    cut_f_attrs($Signature);
    $Signature=~s/\)\Z//;
    return separate_params($Signature, $Comma);
}

sub separate_params($$)
{
    my ($Params, $Comma) = @_;
    my @Parts = ();
    my ($Bracket_Num, $Bracket2_Num, $Part_Num) = (0, 0, 0);
    foreach my $Pos (0 .. length($Params) - 1)
    {
        my $Symbol = substr($Params, $Pos, 1);
        $Bracket_Num += 1 if($Symbol eq "(");
        $Bracket_Num -= 1 if($Symbol eq ")");
        $Bracket2_Num += 1 if($Symbol eq "<");
        $Bracket2_Num -= 1 if($Symbol eq ">");
        if($Symbol eq "," and $Bracket_Num==0 and $Bracket2_Num==0)
        {
            if($Comma)
            { # include comma
                $Parts[$Part_Num] .= $Symbol;
            }
            $Part_Num += 1;
        }
        else {
            $Parts[$Part_Num] .= $Symbol;
        }
    }
    return @Parts;
}

sub detect_center($$)
{
    my ($Sign, $Target) = @_;
    my %B = (
        "("=>0,
        "<"=>0,
        ")"=>0,
        ">"=>0 );
    my $Center = 0;
    if($Sign=~s/(operator([<>\-\=\*]+|\(\)))//g)
    { # operators: (),->,->*,<,<=,<<,<<=,>,>=,>>,>>=
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
    open(FILE, ">>".$Path) || die ("can't open file \'$Path\': $!\n");
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
    open (FILE, ">".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open (FILE, $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    if($Path!~/\.(tu|class)\Z/) {
        $Content=~s/\r/\n/g;
    }
    return $Content;
}

sub get_filename($)
{ # much faster than basename() from File::Basename module
    if($_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub get_dirname($)
{ # much faster than dirname() from File::Basename module
    if($_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return $1;
    }
    return "";
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
    open (FILE, $Path);
    foreach (1 ... $Num) {
        <FILE>;
    }
    my $Line = <FILE>;
    close(FILE);
    return $Line;
}

sub readAttributes($)
{
    my $Path = $_[0];
    return () if(not $Path or not -f $Path);
    my %Attributes = ();
    if(readLineNum($Path, 0)=~/<!--\s+(.+)\s+-->/) {
        foreach my $AttrVal (split(/;/, $1)) {
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
    $_ = $Config{"osname"};
    if(/macos|darwin|rhapsody/i) {
        return "macos";
    }
    elsif(/freebsd|openbsd|netbsd/i) {
        return "bsd";
    }
    elsif(/haiku|beos/i) {
        return "beos";
    }
    elsif(/symbian|epoc/i) {
        return "symbian";
    }
    elsif(/win/i) {
        return "windows";
    }
    else {
        return $_;
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
    if($CPU_ARCH{$LibVersion})
    { # dump version
        return $CPU_ARCH{$LibVersion};
    }
    elsif($UsedDump{$LibVersion}{"V"})
    { # old-version dumps
        return "unknown";
    }
    if(defined $Cache{"getArch"}{$LibVersion}) {
        return $Cache{"getArch"}{$LibVersion};
    }
    my $Arch = get_dumpmachine($GCC_PATH); # host version
    if(not $Arch) {
        return "unknown";
    }
    if($Arch=~/\A([\w]{3,})(-|\Z)/) {
        $Arch = $1;
    }
    $Arch = "x86" if($Arch=~/\Ai[3-7]86\Z/);
    if($OSgroup eq "windows") {
        $Arch = "x86" if($Arch=~/win32|mingw32/i);
        $Arch = "x86_64" if($Arch=~/win64|mingw64/i);
    }
    $Cache{"getArch"}{$LibVersion} = $Arch;
    return $Arch;
}

sub get_Report_Header($)
{
    my $Level = $_[0];
    my $ArchInfo = " on <span style='color:Blue;'>".showArch(getArch(1))."</span>";
    if(getArch(1) ne getArch(2)
    or getArch(1) eq "unknown"
    or $Level eq "Source")
    { # don't show architecture in the header
        $ArchInfo="";
    }
    my $Report_Header = "<h1><span class='nowrap'>";
    if($Level eq "Source") {
        $Report_Header .= "Source compatibility";
    }
    elsif($Level eq "Binary") {
        $Report_Header .= "Binary compatibility";
    }
    else {
        $Report_Header .= "API compatibility";
    }
    $Report_Header .= " report for the <span style='color:Blue;'>$TargetLibraryFName</span> $TargetComponent</span>";
    $Report_Header .= " <span class='nowrap'>&#160;between <span style='color:Red;'>".$Descriptor{1}{"Version"}."</span> and <span style='color:Red;'>".$Descriptor{2}{"Version"}."</span> versions$ArchInfo</span>";
    if($AppPath) {
        $Report_Header .= " <span class='nowrap'>&#160;(relating to the portability of application <span style='color:Blue;'>".get_filename($AppPath)."</span>)</span>";
    }
    $Report_Header .= "</h1>\n";
    return $Report_Header;
}

sub get_SourceInfo()
{
    my $CheckedHeaders = "<a name='Headers'></a><h2>Header Files (".keys(%{$Registered_Headers{1}}).")</h2><hr/>\n";
    $CheckedHeaders .= "<div class='h_list'>\n";
    foreach my $Header_Path (sort {lc($Registered_Headers{1}{$a}{"Identity"}) cmp lc($Registered_Headers{1}{$b}{"Identity"})} keys(%{$Registered_Headers{1}}))
    {
        my $Identity = $Registered_Headers{1}{$Header_Path}{"Identity"};
        my $Header_Name = get_filename($Identity);
        my $Dest_Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
        $CheckedHeaders .= "$Header_Name$Dest_Comment<br/>\n";
    }
    $CheckedHeaders .= "</div>\n";
    $CheckedHeaders .= "<br/>$TOP_REF<br/>\n";
    my $CheckedLibs = "<a name='Libs'></a><h2>".ucfirst($SLIB_TYPE)." Libraries (".keys(%{$Library_Symbol{1}}).")</h2><hr/>\n";
    $CheckedLibs .= "<div class='lib_list'>\n";
    foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$Library_Symbol{1}}))
    {
        $Library.=" (.$LIB_EXT)" if($Library!~/\.\w+\Z/);
        $CheckedLibs .= "$Library<br/>\n";
    }
    $CheckedLibs .= "</div>\n";
    $CheckedLibs .= "<br/>$TOP_REF<br/>\n";
    if($CheckObjectsOnly) {
        $CheckedHeaders = "";
    }
    if($CheckHeadersOnly) {
        $CheckedLibs = "";
    }
    return $CheckedHeaders.$CheckedLibs;
}

sub get_TypeProblems_Count($$$)
{
    my ($TypeChanges, $TargetPriority, $Level) = @_;
    my $Type_Problems_Count = 0;
    foreach my $Type_Name (sort keys(%{$TypeChanges}))
    {
        my %Kinds_Target = ();
        foreach my $Kind (keys(%{$TypeChanges->{$Type_Name}}))
        {
            foreach my $Location (keys(%{$TypeChanges->{$Type_Name}{$Kind}}))
            {
                my $Target = $TypeChanges->{$Type_Name}{$Kind}{$Location}{"Target"};
                my $Priority = getProblemSeverity($Level, $Kind);
                next if($Priority ne $TargetPriority);
                if($Kinds_Target{$Kind}{$Target}) {
                    next;
                }
                if(cmpSeverities($Type_MaxSeverity{$Level}{$Type_Name}{$Kind}{$Target}, $Priority))
                { # select a problem with the highest priority
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
    $C_Problems_Low, $T_Problems_Medium, $T_Problems_Low, $I_Other, $T_Other) = (0,0,0,0,0,0,0,0,0,0,0);
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
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols")
            {
                foreach my $Location (sort keys(%{$CompatProblems{$Level}{$Interface}{$Kind}}))
                {
                    my $Priority = getProblemSeverity($Level, $Kind);
                    if($Kind eq "Added_Symbol") {
                        $Added += 1;
                    }
                    elsif($Kind eq "Removed_Symbol")
                    {
                        $Removed += 1;
                        $TotalAffected{$Level}{$Interface} = $Priority;
                    }
                    else
                    {
                        if($Priority eq "Safe") {
                            $I_Other += 1;
                        }
                        elsif($Priority eq "High") {
                            $I_Problems_High += 1;
                        }
                        elsif($Priority eq "Medium") {
                            $I_Problems_Medium += 1;
                        }
                        elsif($Priority eq "Low") {
                            $I_Problems_Low += 1;
                        }
                        if(($Priority ne "Low" or $StrictCompat)
                        and $Priority ne "Safe") {
                            $TotalAffected{$Level}{$Interface} = $Priority;
                        }
                    }
                }
            }
        }
    }
    my %TypeChanges = ();
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
            {
                foreach my $Location (sort {cmp_locations($b, $a)} sort keys(%{$CompatProblems{$Level}{$Interface}{$Kind}}))
                {
                    my $Type_Name = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Name"};
                    my $Target = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Target"};
                    my $Priority = getProblemSeverity($Level, $Kind);
                    if(cmpSeverities($Type_MaxSeverity{$Level}{$Type_Name}{$Kind}{$Target}, $Priority))
                    { # select a problem with the highest priority
                        next;
                    }
                    if(($Priority ne "Low" or $StrictCompat)
                    and $Priority ne "Safe") {
                        $TotalAffected{$Level}{$Interface} = maxSeverity($TotalAffected{$Level}{$Interface}, $Priority);
                    }
                    %{$TypeChanges{$Type_Name}{$Kind}{$Location}} = %{$CompatProblems{$Level}{$Interface}{$Kind}{$Location}};
                    $Type_MaxSeverity{$Level}{$Type_Name}{$Kind}{$Target} = maxSeverity($Type_MaxSeverity{$Level}{$Type_Name}{$Kind}{$Target}, $Priority);
                }
            }
        }
    }
    
    $T_Problems_High = get_TypeProblems_Count(\%TypeChanges, "High", $Level);
    $T_Problems_Medium = get_TypeProblems_Count(\%TypeChanges, "Medium", $Level);
    $T_Problems_Low = get_TypeProblems_Count(\%TypeChanges, "Low", $Level);
    $T_Other = get_TypeProblems_Count(\%TypeChanges, "Safe", $Level);
    
    if($CheckObjectsOnly)
    { # only removed exported symbols
        $RESULT{$Level}{"Affected"} = $Removed*100/keys(%{$Symbol_Library{1}});
    }
    else
    { # changed and removed public symbols
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
    }
    $RESULT{$Level}{"Affected"} = show_number($RESULT{$Level}{"Affected"});
    if($RESULT{$Level}{"Affected"}>=100) {
        $RESULT{$Level}{"Affected"} = 100;
    }
    
    $RESULT{$Level}{"Problems"} = $Removed + $T_Problems_High + $I_Problems_High;
    $RESULT{$Level}{"Problems"} += $T_Problems_Medium + $I_Problems_Medium;
    $RESULT{$Level}{$StrictCompat?"Problems":"Warnings"} += $T_Problems_Low + $I_Problems_Low;
    
    if($C_Problems_Low = keys(%{$ProblemsWithConstants{$Level}}))
    {
        if(defined $CompatRules{$Level}{"Changed_Constant"}) {
            $RESULT{$Level}{$StrictCompat?"Problems":"Warnings"} += $C_Problems_Low;
        }
        else
        {
            printMsg("WARNING", "unknown rule \"Changed_Constant\" (\"$Level\")");
            $C_Problems_Low = 0;
        }
    }
    if($CheckImpl and $Level eq "Binary") {
        $RESULT{$Level}{$StrictCompat?"Problems":"Warnings"} += keys(%ImplProblems);
    }
    $RESULT{$Level}{"Verdict"} = $RESULT{$Level}{"Problems"}?"incompatible":"compatible";
    
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
        $TestInfo .= "    <architecture>$Arch1</architecture>\n";
        $TestInfo .= "    <gcc>$GccV1</gcc>\n";
        $TestInfo .= "  </version1>\n";
        
        $TestInfo .= "  <version2>\n";
        $TestInfo .= "    <number>".$Descriptor{2}{"Version"}."</number>\n";
        $TestInfo .= "    <architecture>$Arch2</architecture>\n";
        $TestInfo .= "    <gcc>$GccV2</gcc>\n";
        $TestInfo .= "  </version2>\n";
        $TestInfo = "<test_info>\n".$TestInfo."</test_info>\n\n";
        
        # test results
        $TestResults .= "  <headers>\n";
        foreach my $Name (sort {lc($Registered_Headers{1}{$a}{"Identity"}) cmp lc($Registered_Headers{1}{$b}{"Identity"})} keys(%{$Registered_Headers{1}}))
        {
            my $Identity = $Registered_Headers{1}{$Name}{"Identity"};
            my $Comment = ($Identity=~/[\/\\]/)?" ($Identity)":"";
            $TestResults .= "    <name>".get_filename($Name).$Comment."</name>\n";
        }
        $TestResults .= "  </headers>\n";
        
        $TestResults .= "  <libs>\n";
        foreach my $Library (sort {lc($a) cmp lc($b)}  keys(%{$Library_Symbol{1}}))
        {
            $Library.=" (.$LIB_EXT)" if($Library!~/\.\w+\Z/);
            $TestResults .= "    <name>$Library</name>\n";
        }
        $TestResults .= "  </libs>\n";
        
        $TestResults .= "  <symbols>".(keys(%{$CheckedSymbols{$Level}}) - keys(%GeneratedSymbols))."</symbols>\n";
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
        if($CheckImpl and $Level eq "Binary")
        {
            $Problem_Summary .= "  <impl>\n";
            $Problem_Summary .= "    <low>".keys(%ImplProblems)."</low>\n";
            $Problem_Summary .= "  </impl>\n";
        }
        $Problem_Summary = "<problem_summary>\n".$Problem_Summary."</problem_summary>\n\n";
        
        return ($TestInfo.$TestResults.$Problem_Summary, "");
    }
    else
    { # HTML
        # test info
        $TestInfo = "<h2>Test Info</h2><hr/>\n";
        $TestInfo .= "<table class='summary'>\n";
        $TestInfo .= "<tr><th>".ucfirst($TargetComponent)." Name</th><td>$TargetLibraryFName</td></tr>\n";
        
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
                $TestInfo .= "<tr><th>Subject</th><td>Binary Compatibility</td></tr>\n"; # Run-time
            }
            if($Level eq "Source") {
                $TestInfo .= "<tr><th>Subject</th><td>Source Compatibility</td></tr>\n"; # Build-time
            }
        }
        $TestInfo .= "</table>\n";
        
        # test results
        $TestResults = "<h2>Test Results</h2><hr/>\n";
        $TestResults .= "<table class='summary'>";
        
        my $Headers_Link = "0";
        $Headers_Link = "<a href='#Headers' style='color:Blue;'>".keys(%{$Registered_Headers{1}})."</a>" if(keys(%{$Registered_Headers{1}})>0);
        $TestResults .= "<tr><th>Total Header Files</th><td>".($CheckObjectsOnly?"0&#160;(not&#160;analyzed)":$Headers_Link)."</td></tr>\n";
        
        if(not $ExtendedCheck)
        {
            my $Libs_Link = "0";
            $Libs_Link = "<a href='#Libs' style='color:Blue;'>".keys(%{$Library_Symbol{1}})."</a>" if(keys(%{$Library_Symbol{1}})>0);
            $TestResults .= "<tr><th>Total ".ucfirst($SLIB_TYPE)." Libraries</th><td>".($CheckHeadersOnly?"0&#160;(not&#160;analyzed)":$Libs_Link)."</td></tr>\n";
        }
        
        $TestResults .= "<tr><th>Total Symbols / Types</th><td>".(keys(%{$CheckedSymbols{$Level}}) - keys(%GeneratedSymbols))." / ".$TotalTypes."</td></tr>\n";
        
        my $Verdict = "";
        if($RESULT{$Level}{"Problems"}) {
            $Verdict = "<span style='color:Red;'><b>Incompatible<br/>(".$RESULT{$Level}{"Affected"}."%)</b></span>";
        }
        else {
            $Verdict = "<span style='color:Green;'><b>Compatible</b></span>";
        }
        my $META_DATA = $RESULT{$Level}{"Problems"}?"verdict:incompatible;":"verdict:compatible;";
        if($JoinReport) {
            $META_DATA = "kind:".lc($Level).";".$META_DATA;
        }
        $TestResults .= "<tr><th>Verdict</th><td>$Verdict</td></tr>";
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
        #$Added_Link = "n/a" if($CheckHeadersOnly);
        $META_DATA .= "added:$Added;";
        $Problem_Summary .= "<tr><th>Added Symbols</th><td>-</td><td>$Added_Link</td></tr>\n";
        
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
        #$Removed_Link = "n/a" if($CheckHeadersOnly);
        $META_DATA .= "removed:$Removed;";
        $Problem_Summary .= "<tr><th>Removed Symbols</th><td style='color:Red;'>High</td><td>$Removed_Link</td></tr>\n";
        
        my $TH_Link = "0";
        $TH_Link = "<a href='#".get_Anchor("Type", $Level, "High")."' style='color:Blue;'>$T_Problems_High</a>" if($T_Problems_High>0);
        $TH_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "type_problems_high:$T_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Data Types</th><td style='color:Red;'>High</td><td>$TH_Link</td></tr>\n";
        
        my $TM_Link = "0";
        $TM_Link = "<a href='#".get_Anchor("Type", $Level, "Medium")."' style='color:Blue;'>$T_Problems_Medium</a>" if($T_Problems_Medium>0);
        $TM_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "type_problems_medium:$T_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td>$TM_Link</td></tr>\n";
        
        my $TL_Link = "0";
        $TL_Link = "<a href='#".get_Anchor("Type", $Level, "Low")."' style='color:Blue;'>$T_Problems_Low</a>" if($T_Problems_Low>0);
        $TL_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "type_problems_low:$T_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td>$TL_Link</td></tr>\n";
        
        my $IH_Link = "0";
        $IH_Link = "<a href='#".get_Anchor("Symbol", $Level, "High")."' style='color:Blue;'>$I_Problems_High</a>" if($I_Problems_High>0);
        $IH_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "interface_problems_high:$I_Problems_High;";
        $Problem_Summary .= "<tr><th rowspan='3'>Problems with<br/>Symbols</th><td style='color:Red;'>High</td><td>$IH_Link</td></tr>\n";
        
        my $IM_Link = "0";
        $IM_Link = "<a href='#".get_Anchor("Symbol", $Level, "Medium")."' style='color:Blue;'>$I_Problems_Medium</a>" if($I_Problems_Medium>0);
        $IM_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "interface_problems_medium:$I_Problems_Medium;";
        $Problem_Summary .= "<tr><td>Medium</td><td>$IM_Link</td></tr>\n";
        
        my $IL_Link = "0";
        $IL_Link = "<a href='#".get_Anchor("Symbol", $Level, "Low")."' style='color:Blue;'>$I_Problems_Low</a>" if($I_Problems_Low>0);
        $IL_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "interface_problems_low:$I_Problems_Low;";
        $Problem_Summary .= "<tr><td>Low</td><td>$IL_Link</td></tr>\n";
        
        my $ChangedConstants_Link = "0";
        if(keys(%{$CheckedSymbols{$Level}}) and $C_Problems_Low)
        {
            if($JoinReport) {
                $ChangedConstants_Link = "<a href='#".$Level."_Changed_Constants' style='color:Blue;'>$C_Problems_Low</a>";
            }
            else {
                $ChangedConstants_Link = "<a href='#Changed_Constants' style='color:Blue;'>$C_Problems_Low</a>";
            }
        }
        $ChangedConstants_Link = "n/a" if($CheckObjectsOnly);
        $META_DATA .= "changed_constants:$C_Problems_Low;";
        $Problem_Summary .= "<tr><th>Problems with<br/>Constants</th><td>Low</td><td>$ChangedConstants_Link</td></tr>\n";
        
        if($CheckImpl and $Level eq "Binary")
        {
            my $ChangedImpl_Link = "0";
            $ChangedImpl_Link = "<a href='#Changed_Implementation' style='color:Blue;'>".keys(%ImplProblems)."</a>" if(keys(%ImplProblems)>0);
            $ChangedImpl_Link = "n/a" if($CheckHeadersOnly);
            $META_DATA .= "changed_implementation:".keys(%ImplProblems).";";
            $Problem_Summary .= "<tr><th>Problems with<br/>Implementation</th><td>Low</td><td>$ChangedImpl_Link</td></tr>\n";
        }
        # Safe Changes
        if($T_Other and not $CheckObjectsOnly)
        {
            my $TS_Link = "<a href='#".get_Anchor("Type", $Level, "Safe")."' style='color:Blue;'>$T_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Data Types</th><td>-</td><td>$TS_Link</td></tr>\n";
        }
        
        if($I_Other and not $CheckObjectsOnly)
        {
            my $IS_Link = "<a href='#".get_Anchor("Symbol", $Level, "Safe")."' style='color:Blue;'>$I_Other</a>";
            $Problem_Summary .= "<tr><th>Other Changes<br/>in Symbols</th><td>-</td><td>$IS_Link</td></tr>\n";
        }
        
        $META_DATA .= "tool_version:$TOOL_VERSION";
        $Problem_Summary .= "</table>\n";
        return ($TestInfo.$TestResults.$Problem_Summary, $META_DATA);
    }
}

sub show_number($)
{
    if($_[0])
    {
        my $Num = cut_off_number($_[0], 3, 0);
        if($Num eq "0") {
            $Num = cut_off_number($_[0], 7, 1);
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

sub get_Report_ChangedConstants($)
{
    my $Level = $_[0];
    my ($CHANGED_CONSTANTS, %HeaderConstant) = ();
    foreach my $Constant (keys(%{$ProblemsWithConstants{$Level}})) {
        $HeaderConstant{$Constants{1}{$Constant}{"Header"}}{$Constant} = 1;
    }
    my $Kind = "Changed_Constant";
    if(not defined $CompatRules{$Level}{$Kind}) {
        return "";
    }
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%HeaderConstant))
        {
            $CHANGED_CONSTANTS .= "  <header name=\"$HeaderName\">\n";
            foreach my $Constant (sort {lc($a) cmp lc($b)} keys(%{$HeaderConstant{$HeaderName}}))
            {
                $CHANGED_CONSTANTS .= "    <constant name=\"$Constant\">\n";
                my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"};
                $CHANGED_CONSTANTS .= "      <problem id=\"$Kind\">\n";
                $CHANGED_CONSTANTS .= "        <change".getXmlParams($Change, $ProblemsWithConstants{$Level}{$Constant}).">$Change</change>\n";
                $CHANGED_CONSTANTS .= "        <effect".getXmlParams($Effect, $ProblemsWithConstants{$Level}{$Constant}).">$Effect</effect>\n";
                $CHANGED_CONSTANTS .= "        <overcome".getXmlParams($Overcome, $ProblemsWithConstants{$Level}{$Constant}).">$Overcome</overcome>\n";
                $CHANGED_CONSTANTS .= "      </problem>\n";
                $CHANGED_CONSTANTS .= "    </constant>\n";
            }
            $CHANGED_CONSTANTS .= "    </header>\n";
        }
        $CHANGED_CONSTANTS = "<problems_with_constants severity=\"Low\">\n".$CHANGED_CONSTANTS."</problems_with_constants>\n\n";
    }
    else
    { # HTML
        my $Number = 0;
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%HeaderConstant))
        {
            $CHANGED_CONSTANTS .= "<span class='h_name'>$HeaderName</span><br/>\n";
            foreach my $Name (sort {lc($a) cmp lc($b)} keys(%{$HeaderConstant{$HeaderName}}))
            {
                $Number += 1;
                my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, $ProblemsWithConstants{$Level}{$Name});
                my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                my $Report = "<tr><th>1</th><td align='left' valign='top'>".$Change."</td><td align='left' valign='top'>$Effect</td></tr>\n";
                $Report = $ContentDivStart."<table class='ptable'><tr><th width='2%'></th><th width='47%'>Change</th><th>Effect</th></tr>".$Report."</table><br/>$ContentDivEnd\n";
                $Report = $ContentSpanStart."<span class='extendable'>[+]</span> ".$Name.$ContentSpanEnd."<br/>\n".$Report;
                $CHANGED_CONSTANTS .= insertIDs($Report);
            }
            $CHANGED_CONSTANTS .= "<br/>\n";
        }
        if($CHANGED_CONSTANTS)
        {
            my $Anchor = "<a name='Changed_Constants'></a>";
            if($JoinReport) {
                $Anchor = "<a name='".$Level."_Changed_Constants'></a>";
            }
            $CHANGED_CONSTANTS = $Anchor."<h2>Problems with Constants ($Number)</h2><hr/>\n".$CHANGED_CONSTANTS.$TOP_REF."<br/>\n";
        }
    }
    return $CHANGED_CONSTANTS;
}

sub get_Report_Impl()
{
    my ($CHANGED_IMPLEMENTATION, %HeaderLibFunc);
    foreach my $Interface (sort keys(%ImplProblems))
    {
        my $HeaderName = $CompleteSignature{1}{$Interface}{"Header"};
        my $DyLib = $Symbol_Library{1}{$Interface};
        $HeaderLibFunc{$HeaderName}{$DyLib}{$Interface} = 1;
    }
    my $Changed_Number = 0;
    foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%HeaderLibFunc))
    {
        foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$HeaderLibFunc{$HeaderName}}))
        {
            my $FDyLib=$DyLib.($DyLib!~/\.\w+\Z/?" (.$LIB_EXT)":"");
            if($HeaderName) {
                $CHANGED_IMPLEMENTATION .= "<span class='h_name'>$HeaderName</span>, <span class='lib_name'>$FDyLib</span><br/>\n";
            }
            else {
                $CHANGED_IMPLEMENTATION .= "<span class='lib_name'>$DyLib</span><br/>\n";
            }
            my %NameSpaceSymbols = ();
            foreach my $Interface (keys(%{$HeaderLibFunc{$HeaderName}{$DyLib}})) {
                $NameSpaceSymbols{get_IntNameSpace($Interface, 2)}{$Interface} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpaceSymbols))
            {
                $CHANGED_IMPLEMENTATION .= ($NameSpace)?"<span class='ns_title'>namespace</span> <span class='ns'>$NameSpace</span>"."<br/>\n":"";
                my @SortedInterfaces = sort {lc(get_Signature($a, 1)) cmp lc(get_Signature($b, 1))} keys(%{$NameSpaceSymbols{$NameSpace}});
                foreach my $Interface (@SortedInterfaces)
                {
                    $Changed_Number += 1;
                    my $Signature = get_Signature($Interface, 1);
                    if($NameSpace) {
                        $Signature=~s/(\W|\A)\Q$NameSpace\E\:\:(\w)/$1$2/g;
                    }
                    $CHANGED_IMPLEMENTATION .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Interface</b>]</span>".$ImplProblems{$Interface}{"Diff"}."<br/><br/>".$ContentDivEnd."\n");
                }
            }
            $CHANGED_IMPLEMENTATION .= "<br/>\n";
        }
    }
    if($CHANGED_IMPLEMENTATION) {
        $CHANGED_IMPLEMENTATION = "<a name='Changed_Implementation'></a><h2>Problems with Implementation ($Changed_Number)</h2><hr/>\n".$CHANGED_IMPLEMENTATION.$TOP_REF."<br/>\n";
    }
    return $CHANGED_IMPLEMENTATION;
}

sub getTitle($$$)
{
    my ($Header, $Library, $NameSpace) = @_;
    my $Title = "";
    if($Library and $Library!~/\.\w+\Z/) {
        $Library .= " (.$LIB_EXT)";
    }
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
        $Title .= "<span class='ns_title'>namespace</span> <span class='ns'>$NameSpace</span><br/>\n";
    }
    return $Title;
}

sub get_Report_Added($)
{
    my $Level = $_[0];
    my ($ADDED_INTERFACES, %ReportMap);
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
                    $NameSpaceSymbols{get_IntNameSpace($Interface, 2)}{$Interface} = 1;
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
                            $Signature=~s/(\W|\A)\Q$NameSpace\E\:\:(\w)/$1$2/g;
                        }
                        if($Interface=~/\A(_Z|\?)/) {
                            if($Signature) {
                                $ADDED_INTERFACES .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Interface</b>]</span><br/><br/>".$ContentDivEnd."\n");
                            }
                            else {
                                $ADDED_INTERFACES .= "<span class=\"iname\">".$Interface."</span><br/>\n";
                            }
                        }
                        else {
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
            $ADDED_INTERFACES = $Anchor."<h2>Added Symbols ($Added_Number)</h2><hr/>\n".$ADDED_INTERFACES.$TOP_REF."<br/>\n";
        }
    }
    return $ADDED_INTERFACES;
}

sub get_Report_Removed($)
{
    my $Level = $_[0];
    my (%ReportMap, $REMOVED_INTERFACES) = ();
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($Kind eq "Removed_Symbol")
            {
                my $HeaderName = $CompleteSignature{1}{$Interface}{"Header"};
                my $DyLib = $Symbol_Library{1}{$Interface};
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
            $REMOVED_INTERFACES .= "  <header name=\"$HeaderName\">\n";
            foreach my $DyLib (sort {lc($a) cmp lc($b)} keys(%{$ReportMap{$HeaderName}}))
            {
                $REMOVED_INTERFACES .= "    <library name=\"$DyLib\">\n";
                foreach my $Interface (keys(%{$ReportMap{$HeaderName}{$DyLib}})) {
                    $REMOVED_INTERFACES .= "      <name>$Interface</name>\n";
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
                    $NameSpaceSymbols{get_IntNameSpace($Interface, 1)}{$Interface} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $REMOVED_INTERFACES .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc(get_Signature($a, 1)) cmp lc(get_Signature($b, 1))} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Interface (@SortedInterfaces)
                    {
                        $Removed_Number += 1;
                        my $SubReport = "";
                        my $Signature = get_Signature($Interface, 1);
                        if($NameSpace) {
                            $Signature=~s/(\W|\A)\Q$NameSpace\E\:\:(\w)/$1$2/g;
                        }
                        if($Interface=~/\A(_Z|\?)/)
                        {
                            if($Signature) {
                                $REMOVED_INTERFACES .= insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Interface</b>]</span><br/><br/>".$ContentDivEnd."\n");
                            }
                            else {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".$Interface."</span><br/>\n";
                            }
                        }
                        else
                        {
                            if($Signature) {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".highLight_Signature_Italic_Color($Signature)."</span><br/>\n";
                            }
                            else {
                                $REMOVED_INTERFACES .= "<span class=\"iname\">".$Interface."</span><br/>\n";
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
            $REMOVED_INTERFACES = $Anchor."<h2>Removed Symbols ($Removed_Number)</h2><hr/>\n".$REMOVED_INTERFACES.$TOP_REF."<br/>\n";
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
        push(@PString, $P."=\"".htmlSpecChars($XMLparams{$P})."\"");
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
        "virtual",
        "virtually"
    );
    my $MKeys = join("|", @Keywords);
    foreach (@Keywords) {
        $MKeys .= "|non-".$_;
    }
    $Content=~s!(added\s*|to\s*|from\s*|became\s*)($MKeys)([^\w-]|\Z)!$1<b>$2</b>$3!ig; # intrinsic types, modifiers
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
        if($Value=~/\s\(/)
        { # functions
            $Value=~s/\s*\[[\w\-]+\]//g; # remove quals
            $Value=~s/\s\w+(\)|,)/$1/g; # remove parameter names
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
        else {
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
    $Content=~s!<nowrap>(.+?)</nowrap>!<span class='nowrap'>$1</span>!g;
    return $Content;
}

sub get_Report_SymbolProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my ($INTERFACE_PROBLEMS, %ReportMap, %SymbolChanges);
    foreach my $Symbol (sort keys(%{$CompatProblems{$Level}}))
    {
        my ($SN, $SS, $SV) = separate_symbol($Symbol);
        if($SV and defined $CompatProblems{$Level}{$SN}) {
            next;
        }
        foreach my $Kind (sort keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Symbols"
            and $Kind ne "Added_Symbol" and $Kind ne "Removed_Symbol")
            {
                my $HeaderName = $CompleteSignature{1}{$Symbol}{"Header"};
                my $DyLib = $Symbol_Library{1}{$Symbol};
                if(not $DyLib and my $VSym = $SymVer{1}{$Symbol})
                { # Symbol with Version
                    $DyLib = $Symbol_Library{1}{$VSym};
                }
                if($Level eq "Source" and $ReportFormat eq "html")
                { # do not show library name in HTML report
                    $DyLib = "";
                }
                %{$SymbolChanges{$Symbol}{$Kind}} = %{$CompatProblems{$Level}{$Symbol}{$Kind}};
                foreach my $Location (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                {
                    my $Priority = getProblemSeverity($Level, $Kind);
                    if($Priority ne $TargetSeverity) {
                        delete($SymbolChanges{$Symbol}{$Kind}{$Location});
                    }
                }
                if(not keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                {
                    delete($SymbolChanges{$Symbol}{$Kind});
                    next;
                }
                $ReportMap{$HeaderName}{$DyLib}{$Symbol} = 1;
            }
        }
        if(not keys(%{$SymbolChanges{$Symbol}})) {
            delete($SymbolChanges{$Symbol});
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
                foreach my $Symbol (sort {lc($tr_name{$a}) cmp lc($tr_name{$b})} keys(%SymbolChanges))
                {
                    $INTERFACE_PROBLEMS .= "      <symbol name=\"$Symbol\">\n";
                    foreach my $Kind (keys(%{$SymbolChanges{$Symbol}}))
                    {
                        foreach my $Location (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                        {
                            my %Problem = %{$SymbolChanges{$Symbol}{$Kind}{$Location}};
                            $Problem{"Param_Pos"} = showNum($Problem{"Param_Pos"});
                            $INTERFACE_PROBLEMS .= "        <problem id=\"$Kind\">\n";
                            my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                            $INTERFACE_PROBLEMS .= "          <change".getXmlParams($Change, \%Problem).">$Change</change>\n";
                            my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                            $INTERFACE_PROBLEMS .= "          <effect".getXmlParams($Effect, \%Problem).">$Effect</effect>\n";
                            my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"};
                            $INTERFACE_PROBLEMS .= "          <overcome".getXmlParams($Overcome, \%Problem).">$Overcome</overcome>\n";
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
                    $NameSpaceSymbols{get_IntNameSpace($Symbol, 1)}{$Symbol} = 1;
                }
                foreach my $NameSpace (sort keys(%NameSpaceSymbols))
                {
                    $INTERFACE_PROBLEMS .= getTitle($HeaderName, $DyLib, $NameSpace);
                    my @SortedInterfaces = sort {lc($tr_name{$a}) cmp lc($tr_name{$b})} keys(%{$NameSpaceSymbols{$NameSpace}});
                    foreach my $Symbol (@SortedInterfaces)
                    {
                        my $Signature = get_Signature($Symbol, 1);
                        my $SYMBOL_REPORT = "";
                        my $ProblemNum = 1;
                        foreach my $Kind (keys(%{$SymbolChanges{$Symbol}}))
                        {
                            foreach my $Location (sort keys(%{$SymbolChanges{$Symbol}{$Kind}}))
                            {
                                my %Problem = %{$SymbolChanges{$Symbol}{$Kind}{$Location}};
                                $Problem{"Param_Pos"} = showNum($Problem{"Param_Pos"});
                                if($Problem{"New_Signature"}) {
                                    $NewSignature{$Symbol} = $Problem{"New_Signature"};
                                }
                                if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, \%Problem))
                                {
                                    my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, \%Problem);
                                    $SYMBOL_REPORT .= "<tr><th>$ProblemNum</th><td align='left' valign='top'>".$Change."</td><td align='left' valign='top'>".$Effect."</td></tr>\n";
                                    $ProblemNum += 1;
                                    $ProblemsNum += 1;
                                }
                            }
                        }
                        $ProblemNum -= 1;
                        if($SYMBOL_REPORT)
                        {
                            $INTERFACE_PROBLEMS .= $ContentSpanStart."<span class='extendable'>[+]</span> ";
                            if($Signature) {
                                $INTERFACE_PROBLEMS .= highLight_Signature_Italic_Color($Signature);
                            }
                            else {
                                $INTERFACE_PROBLEMS .= $Symbol;
                            }
                            $INTERFACE_PROBLEMS .= " ($ProblemNum)".$ContentSpanEnd."<br/>\n";
                            $INTERFACE_PROBLEMS .= $ContentDivStart."\n";
                            if($NewSignature{$Symbol})
                            { # argument list changed to
                                $INTERFACE_PROBLEMS .= "\n<span class='new_sign_lbl'>changed to:</span><br/><span class='new_sign'>".highLight_Signature_Italic_Color($NewSignature{$Symbol})."</span><br/>\n";
                            }
                            if($Symbol=~/\A(_Z|\?)/) {
                                $INTERFACE_PROBLEMS .= "<span class='mangled'>&#160;&#160;&#160;&#160;[symbol: <b>$Symbol</b>]</span><br/>\n";
                            }
                            $INTERFACE_PROBLEMS .= "<table class='ptable'><tr><th width='2%'></th><th width='47%'>Change</th><th>Effect</th></tr>$SYMBOL_REPORT</table><br/>\n";
                            $INTERFACE_PROBLEMS .= $ContentDivEnd;
                            if($NameSpace) {
                                $INTERFACE_PROBLEMS=~s/(\W|\A)\Q$NameSpace\E\:\:(\w)/$1$2/g;
                            }
                        }
                    }
                    $INTERFACE_PROBLEMS .= "<br/>";
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
            $INTERFACE_PROBLEMS = "<a name=\'".get_Anchor("Symbol", $Level, $TargetSeverity)."\'></a>"."<a name=\'".get_Anchor("Interface", $Level, $TargetSeverity)."\'></a>"."\n<h2>$Title ($ProblemsNum)</h2><hr/>\n".$INTERFACE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $INTERFACE_PROBLEMS;
}

sub get_Report_TypeProblems($$)
{
    my ($TargetSeverity, $Level) = @_;
    my ($TYPE_PROBLEMS, %ReportMap, %TypeChanges, %TypeType) = ();
    foreach my $Interface (sort keys(%{$CompatProblems{$Level}}))
    {
        foreach my $Kind (keys(%{$CompatProblems{$Level}{$Interface}}))
        {
            if($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
            {
                foreach my $Location (sort {cmp_locations($b, $a)} sort keys(%{$CompatProblems{$Level}{$Interface}{$Kind}}))
                {
                    my $TypeName = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Name"};
                    my $TypeType = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Type"};
                    my $Target = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Target"};
                    $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Type"} = lc($TypeType);
                    my $Severity = getProblemSeverity($Level, $Kind);
                    if($Severity eq "Safe"
                    and $TargetSeverity ne "Safe") {
                        next;
                    }
                    if(not $TypeType{$TypeName}
                    or $TypeType{$TypeName} eq "struct")
                    { # register type of the type, select "class" if type has "class"- and "struct"-type changes
                        $TypeType{$TypeName} = $CompatProblems{$Level}{$Interface}{$Kind}{$Location}{"Type_Type"};
                    }
                    
                    if(cmpSeverities($Type_MaxSeverity{$Level}{$TypeName}{$Kind}{$Target}, $Severity))
                    { # select a problem with the highest priority
                        next;
                    }
                    %{$TypeChanges{$TypeName}{$Kind}{$Location}} = %{$CompatProblems{$Level}{$Interface}{$Kind}{$Location}};
                }
            }
        }
    }
    my %Kinds_Locations = ();
    foreach my $TypeName (keys(%TypeChanges))
    {
        my %Kinds_Target = ();
        foreach my $Kind (sort keys(%{$TypeChanges{$TypeName}}))
        {
            foreach my $Location (sort {cmp_locations($b, $a)} sort keys(%{$TypeChanges{$TypeName}{$Kind}}))
            {
                my $Severity = getProblemSeverity($Level, $Kind);
                if($Severity ne $TargetSeverity)
                { # other priority
                    delete($TypeChanges{$TypeName}{$Kind}{$Location});
                    next;
                }
                $Kinds_Locations{$TypeName}{$Kind}{$Location} = 1;
                my $Target = $TypeChanges{$TypeName}{$Kind}{$Location}{"Target"};
                if($Kinds_Target{$Kind}{$Target})
                { # duplicate target
                    delete($TypeChanges{$TypeName}{$Kind}{$Location});
                    next;
                }
                $Kinds_Target{$Kind}{$Target} = 1;
                my $HeaderName = get_TypeAttr($TName_Tid{1}{$TypeName}, 1, "Header");
                $ReportMap{$HeaderName}{$TypeName} = 1;
            }
            if(not keys(%{$TypeChanges{$TypeName}{$Kind}})) {
                delete($TypeChanges{$TypeName}{$Kind});
            }
        }
        if(not keys(%{$TypeChanges{$TypeName}})) {
            delete($TypeChanges{$TypeName});
        }
    }
    if($ReportFormat eq "xml")
    { # XML
        foreach my $HeaderName (sort {lc($a) cmp lc($b)} keys(%ReportMap))
        {
            $TYPE_PROBLEMS .= "  <header name=\"$HeaderName\">\n";
            foreach my $TypeName (keys(%{$ReportMap{$HeaderName}}))
            {
                $TYPE_PROBLEMS .= "    <type name=\"".htmlSpecChars($TypeName)."\">\n";
                foreach my $Kind (sort {$b=~/Size/ <=> $a=~/Size/} sort keys(%{$TypeChanges{$TypeName}}))
                {
                    foreach my $Location (sort {cmp_locations($b, $a)} sort keys(%{$TypeChanges{$TypeName}{$Kind}}))
                    {
                        my %Problem = %{$TypeChanges{$TypeName}{$Kind}{$Location}};
                        $TYPE_PROBLEMS .= "      <problem id=\"$Kind\">\n";
                        my $Change = $CompatRules{$Level}{$Kind}{"Change"};
                        $TYPE_PROBLEMS .= "        <change".getXmlParams($Change, \%Problem).">$Change</change>\n";
                        my $Effect = $CompatRules{$Level}{$Kind}{"Effect"};
                        $TYPE_PROBLEMS .= "        <effect".getXmlParams($Effect, \%Problem).">$Effect</effect>\n";
                        my $Overcome = $CompatRules{$Level}{$Kind}{"Overcome"};
                        $TYPE_PROBLEMS .= "        <overcome".getXmlParams($Overcome, \%Problem).">$Overcome</overcome>\n";
                        $TYPE_PROBLEMS .= "      </problem>\n";
                    }
                }
                $TYPE_PROBLEMS .= getAffectedInterfaces($Level, $TypeName, $Kinds_Locations{$TypeName});
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
                $NameSpace_Type{parse_TypeNameSpace($TypeName, 1)}{$TypeName} = 1;
            }
            foreach my $NameSpace (sort keys(%NameSpace_Type))
            {
                $TYPE_PROBLEMS .= getTitle($HeaderName, "", $NameSpace);
                my @SortedTypes = sort {$TypeType{$a}." ".lc($a) cmp $TypeType{$b}." ".lc($b)} keys(%{$NameSpace_Type{$NameSpace}});
                foreach my $TypeName (@SortedTypes)
                {
                    my $ProblemNum = 1;
                    my $TYPE_REPORT = "";
                    foreach my $Kind (sort {$b=~/Size/ <=> $a=~/Size/} sort keys(%{$TypeChanges{$TypeName}}))
                    {
                        foreach my $Location (sort {cmp_locations($b, $a)} sort keys(%{$TypeChanges{$TypeName}{$Kind}}))
                        {
                            my %Problem = %{$TypeChanges{$TypeName}{$Kind}{$Location}};
                            if(my $Change = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Change"}, \%Problem))
                            {
                                my $Effect = applyMacroses($Level, $Kind, $CompatRules{$Level}{$Kind}{"Effect"}, \%Problem);
                                $TYPE_REPORT .= "<tr><th>$ProblemNum</th><td align='left' valign='top'>".$Change."</td><td align='left' valign='top'>$Effect</td></tr>\n";
                                $ProblemNum += 1;
                                $ProblemsNum += 1;
                            }
                        }
                    }
                    $ProblemNum -= 1;
                    if($TYPE_REPORT)
                    {
                        my $Affected = getAffectedInterfaces($Level, $TypeName, $Kinds_Locations{$TypeName});
                        my $ShowVTables = "";
                        if($Level eq "Binary" and grep {$_=~/Virtual|Base_Class/} keys(%{$Kinds_Locations{$TypeName}})) {
                            $ShowVTables = showVTables($TypeName);
                        }
                        $TYPE_PROBLEMS .= $ContentSpanStart."<span class='extendable'>[+]</span> <span class='ttype'>".$TypeType{$TypeName}."</span> ".htmlSpecChars($TypeName)." ($ProblemNum)".$ContentSpanEnd;
                        $TYPE_PROBLEMS .= "<br/>\n".$ContentDivStart."<table class='ptable'><tr>\n";
                        $TYPE_PROBLEMS .= "<th width='2%'></th><th width='47%'>Change</th>\n";
                        $TYPE_PROBLEMS .= "<th>Effect</th></tr>".$TYPE_REPORT."</table>\n";
                        $TYPE_PROBLEMS .= $ShowVTables.$Affected."<br/><br/>".$ContentDivEnd."\n";
                        if($NameSpace) {
                            $TYPE_PROBLEMS=~s/(\W|\A)\Q$NameSpace\E\:\:(\w|\~)/$1$2/g;
                        }
                    }
                }
                $TYPE_PROBLEMS .= "<br/>";
            }
        }
        if($TYPE_PROBLEMS)
        {
            $TYPE_PROBLEMS = insertIDs($TYPE_PROBLEMS);
            my $Title = "Problems with Data Types, $TargetSeverity Severity";
            my $Anchor = "Type_Problems_$TargetSeverity";
            if($TargetSeverity eq "Safe")
            { # Safe Changes
                $Title = "Other Changes in Data Types";
            }
            $TYPE_PROBLEMS = "<a name=\'".get_Anchor("Type", $Level, $TargetSeverity)."\'></a>\n<h2>$Title ($ProblemsNum)</h2><hr/>\n".$TYPE_PROBLEMS.$TOP_REF."<br/>\n";
        }
    }
    return $TYPE_PROBLEMS;
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
    my %Type1 = get_Type($Tid_TDid{1}{$TypeId1}, $TypeId1, 1);
    if(defined $Type1{"VTable"}
    and keys(%{$Type1{"VTable"}}))
    {
        my $TypeId2 = $TName_Tid{2}{$TypeName};
        my %Type2 = get_Type($Tid_TDid{2}{$TypeId2}, $TypeId2, 2);
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
                    $VTABLES .= "          <old>".htmlSpecChars($Entries{$Index}{"E1"})."</old>\n";
                    $VTABLES .= "          <new>".htmlSpecChars($Entries{$Index}{"E2"})."</new>\n";
                    $VTABLES .= "        </entry>\n";
                }
                $VTABLES .= "      </vtable>\n\n";
            }
            else
            { # HTML
                $VTABLES .= "<table class='vtable'>";
                $VTABLES .= "<tr><th width='2%'>Offset</th>";
                $VTABLES .= "<th width='45%'>Virtual Table (Old) - ".(keys(%{$Type1{"VTable"}}))." entries</th>";
                $VTABLES .= "<th>Virtual Table (New) - ".(keys(%{$Type2{"VTable"}}))." entries</th></tr>";
                foreach my $Index (sort {int($a)<=>int($b)} (keys(%Entries)))
                {
                    my ($Color1, $Color2) = ("", "");
                    if($Entries{$Index}{"E1"} ne $Entries{$Index}{"E2"})
                    {
                        if($Entries{$Index}{"E1"})
                        {
                            $Color1 = " class='vtable_red'";
                            $Color2 = " class='vtable_red'";
                        }
                        else {
                            $Color2 = " class='vtable_yellow'";
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
    $VEntry=~s/\A(.+)::(_ZThn.+)\Z/$2/; # thunks
    $VEntry=~s/_ZTI\w+/typeinfo/g; # typeinfo
    if($VEntry=~/\A_ZThn.+\Z/) {
        $VEntry = "non-virtual thunk";
    }
    $VEntry=~s/\A\(int \(\*\)\(...\)\)([^\(\d])/$1/i;
    # support for old GCC versions
    $VEntry=~s/\A0u\Z/(int (*)(...))0/;
    $VEntry=~s/\A4294967268u\Z/(int (*)(...))-0x000000004/;
    $VEntry=~s/\A&_Z\Z/& _Z/;
    # templates
    if($VEntry=~s/ \[with (\w+) = (.+?)(, [^=]+ = .+|])\Z//g)
    { # std::basic_streambuf<_CharT, _Traits>::imbue [with _CharT = char, _Traits = std::char_traits<char>]
      # become std::basic_streambuf<char, ...>::imbue
        my ($Pname, $Pval) = ($1, $2);
        if($Pname eq "_CharT" and $VEntry=~/\Astd::/)
        { # stdc++ typedefs
            $VEntry=~s/<$Pname(, [^<>]+|)>/<$Pval>/g;
            # FIXME: simplify names using stdcxx typedefs (StdCxxTypedef)
            # The typedef info should be added to ABI dumps
        }
        else
        {
            $VEntry=~s/<$Pname>/<$Pval>/g;
            $VEntry=~s/<$Pname, [^<>]+>/<$Pval, ...>/g;
        }
    }
    $VEntry=~s/([^:]+)::\~([^:]+)\Z/~$1/; # destructors
    return $VEntry;
}

sub getAffectedInterfaces($$$)
{
    my ($Level, $Target_TypeName, $Kinds_Locations) = @_;
    my (%INumber, %SymProblems) = ();
    my $LIMIT = 1000;
    foreach my $Symbol (sort {lc($tr_name{$a}?$tr_name{$a}:$a) cmp lc($tr_name{$b}?$tr_name{$b}:$b)} keys(%{$CompatProblems{$Level}}))
    {
        last if(keys(%INumber)>$LIMIT);
        if(($Symbol=~/C2E|D2E|D0E/))
        { # duplicated problems for C2 constructors, D2 and D0 destructors
            next;
        }
        my ($SN, $SS, $SV) = separate_symbol($Symbol);
        if($Level eq "Source")
        { # remove symbol version
            $Symbol=$SN;
        }
        my ($MinPath_Length, $ProblemLocation_Last) = (-1, "");
        my $Severity_Max = 0;
        my $Signature = get_Signature($Symbol, 1);
        foreach my $Kind (keys(%{$CompatProblems{$Level}{$Symbol}}))
        {
            foreach my $Location (keys(%{$CompatProblems{$Level}{$Symbol}{$Kind}}))
            {
                if(not defined $Kinds_Locations->{$Kind}
                or not $Kinds_Locations->{$Kind}{$Location}) {
                    next;
                }
                if($SV and defined $CompatProblems{$Level}{$SN}
                and defined $CompatProblems{$Level}{$SN}{$Kind}{$Location})
                { # duplicated problems for versioned symbols
                    next;
                }
                my $Type_Name = $CompatProblems{$Level}{$Symbol}{$Kind}{$Location}{"Type_Name"};
                next if($Type_Name ne $Target_TypeName);
                
                my $Position = $CompatProblems{$Level}{$Symbol}{$Kind}{$Location}{"Param_Pos"};
                my $Param_Name = $CompatProblems{$Level}{$Symbol}{$Kind}{$Location}{"Param_Name"};
                my $Severity = getProblemSeverity($Level, $Kind);
                $INumber{$Symbol} = 1;
                my $Path_Length = 0;
                my $ProblemLocation = $Location;
                if($Type_Name) {
                    $ProblemLocation=~s/->\Q$Type_Name\E\Z//g;
                }
                while($ProblemLocation=~/\-\>/g) {
                    $Path_Length += 1;
                }
                if($MinPath_Length==-1 or ($Path_Length<=$MinPath_Length and $Severity_Val{$Severity}>$Severity_Max)
                or (cmp_locations($ProblemLocation, $ProblemLocation_Last) and $Severity_Val{$Severity}==$Severity_Max))
                {
                    $MinPath_Length = $Path_Length;
                    $Severity_Max = $Severity_Val{$Severity};
                    $ProblemLocation_Last = $ProblemLocation;
                    %{$SymProblems{$Symbol}} = (
                        "Descr"=>getAffectDescription($Level, $Symbol, $Kind, $Location),
                        "Severity_Max"=>$Severity_Max,
                        "Signature"=>$Signature,
                        "Position"=>$Position,
                        "Param_Name"=>$Param_Name,
                        "Location"=>$Location
                    );
                }
            }
        }
    }
    my @Symbols = keys(%SymProblems);
    @Symbols = sort {lc($tr_name{$a}?$tr_name{$a}:$a) cmp lc($tr_name{$b}?$tr_name{$b}:$b)} @Symbols;
    @Symbols = sort {$SymProblems{$b}{"Severity_Max"}<=>$SymProblems{$a}{"Severity_Max"}} @Symbols;
    my $Affected = "";
    if($ReportFormat eq "xml")
    { # XML
        $Affected .= "      <affected>\n";
        foreach my $Symbol (@Symbols)
        {
            my $Param_Name = $SymProblems{$Symbol}{"Param_Name"};
            my $Description = $SymProblems{$Symbol}{"Descr"};
            my $Location = $SymProblems{$Symbol}{"Location"};
            my $Target = "";
            if($Param_Name) {
                $Target = " affected=\"param\" param_name=\"$Param_Name\"";
            }
            elsif($Location=~/\Aretval(\-|\Z)/i) {
                $Target = " affected=\"retval\"";
            }
            elsif($Location=~/\Athis(\-|\Z)/i) {
                $Target = " affected=\"this\"";
            }
            $Affected .= "        <symbol$Target name=\"$Symbol\">\n";
            $Affected .= "          <comment>".htmlSpecChars($Description)."</comment>\n";
            $Affected .= "        </symbol>\n";
        }
        $Affected .= "      </affected>\n";
    }
    else
    { # HTML
        foreach my $Symbol (@Symbols)
        {
            my $Description = $SymProblems{$Symbol}{"Descr"};
            my $Signature = $SymProblems{$Symbol}{"Signature"};
            my $Pos = $SymProblems{$Symbol}{"Position"};
            $Affected .= "<span class='iname_b'>".highLight_Signature_PPos_Italic($Signature, $Pos, 1, 0, 0)."</span><br/>"."<div class='affect'>".htmlSpecChars($Description)."</div>\n";
        }
        $Affected = "<div class='affected'>".$Affected."</div>";
        if(keys(%INumber)>$LIMIT) {
            $Affected .= "and others ...<br/>";
        }
        if($Affected)
        {
            $Affected = $ContentDivStart.$Affected.$ContentDivEnd;
            my $AHeader = $ContentSpanStart_Affected."[+] affected symbols (".(keys(%INumber)>$LIMIT?"more than $LIMIT":keys(%INumber)).")".$ContentSpanEnd;
            $Affected = $AHeader.$Affected;
        }
    }
    return $Affected;
}

sub cmp_locations($$)
{
    my ($Location1, $Location2) = @_;
    if($Location2=~/(\A|\W)(retval|this)(\W|\Z)/
    and $Location1!~/(\A|\W)(retval|this)(\W|\Z)/ and $Location1!~/\-\>/) {
        return 1;
    }
    if($Location2=~/(\A|\W)(retval|this)(\W|\Z)/ and $Location2=~/\-\>/
    and $Location1!~/(\A|\W)(retval|this)(\W|\Z)/ and $Location1=~/\-\>/) {
        return 1;
    }
    return 0;
}

sub getAffectDescription($$$$)
{
    my ($Level, $Symbol, $Kind, $Location) = @_;
    my %Problem = %{$CompatProblems{$Level}{$Symbol}{$Kind}{$Location}};
    my $PPos = showNum($Problem{"Param_Pos"});
    my @Sentence = ();
    $Location=~s/\A(.*)\-\>.+?\Z/$1/;
    if($Kind eq "Overridden_Virtual_Method"
    or $Kind eq "Overridden_Virtual_Method_B") {
        push(@Sentence, "The method '".$Problem{"New_Value"}."' will be called instead of this method.");
    }
    elsif($CompatRules{$Level}{$Kind}{"Kind"} eq "Types")
    {
        if($Location eq "this" or $Kind=~/(\A|_)Virtual(_|\Z)/)
        {
            my $METHOD_TYPE = $CompleteSignature{1}{$Symbol}{"Constructor"}?"constructor":"method";
            my $ClassName = get_TypeName($CompleteSignature{1}{$Symbol}{"Class"}, 1);
            if($ClassName eq $Problem{"Type_Name"}) {
                push(@Sentence, "This $METHOD_TYPE is from \'".$Problem{"Type_Name"}."\' class.");
            }
            else {
                push(@Sentence, "This $METHOD_TYPE is from derived class \'".$ClassName."\'.");
            }
        }
        else
        {
            if($Location=~/retval/)
            { # return value
                if($Location=~/\-\>/) {
                    push(@Sentence, "Field \'".$Location."\' in return value");
                }
                else {
                    push(@Sentence, "Return value");
                }
                if(my $Init = $Problem{"InitialType_Type"})
                {
                    if($Init eq "Pointer") {
                        push(@Sentence, "(pointer)");
                    }
                    elsif($Init eq "Ref") {
                        push(@Sentence, "(reference)");
                    }
                }
            }
            elsif($Location=~/this/)
            { # "this" pointer
                if($Location=~/\-\>/) {
                    push(@Sentence, "Field \'".$Location."\' in the object of this method");
                }
                else {
                    push(@Sentence, "\'this\' pointer");
                }
            }
            else
            { # parameters
                if($Location=~/\-\>/) {
                    push(@Sentence, "Field \'".$Location."\' in $PPos parameter");
                }
                else {
                    push(@Sentence, "$PPos parameter");
                }
                if($Problem{"Param_Name"}) {
                    push(@Sentence, "\'".$Problem{"Param_Name"}."\'");
                }
                if(my $Init = $Problem{"InitialType_Type"})
                {
                    if($Init eq "Pointer") {
                        push(@Sentence, "(pointer)");
                    }
                    elsif($Init eq "Ref") {
                        push(@Sentence, "(reference)");
                    }
                }
            }
            if($Location eq "this") {
                push(@Sentence, "has base type \'".$Problem{"Type_Name"}."\'.");
            }
            elsif($Problem{"Start_Type_Name"} eq $Problem{"Type_Name"}) {
                push(@Sentence, "has type \'".$Problem{"Type_Name"}."\'.");
            }
            else {
                push(@Sentence, "has base type \'".$Problem{"Type_Name"}."\'.");
            }
        }
    }
    if($ExtendedFuncs{$Symbol}) {
        push(@Sentence, " This is a symbol from an artificial external library that may use the \'$TargetLibraryName\' library and change its ABI after recompiling.");
    }
    return join(" ", @Sentence);
}

sub get_XmlSign($$)
{
    my ($Symbol, $LibVersion) = @_;
    my $Info = $CompleteSignature{$LibVersion}{$Symbol};
    my $Report = "";
    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$Info->{"Param"}}))
    {
        my $Name = $Info->{"Param"}{$Pos}{"name"};
        my $TypeName = get_TypeName($Info->{"Param"}{$Pos}{"type"}, $LibVersion);
        foreach my $Typedef (keys(%ChangedTypedef))
        {
            my $Base = $Typedef_BaseName{$LibVersion}{$Typedef};
            $TypeName=~s/(\A|\W)\Q$Typedef\E(\W|\Z)/$1$Base$2/g;
        }
        $Report .= "    <param pos=\"$Pos\">\n";
        $Report .= "      <name>".$Name."</name>\n";
        $Report .= "      <type>".htmlSpecChars($TypeName)."</type>\n";
        $Report .= "    </param>\n";
    }
    if(my $Return = $Info->{"Return"})
    {
        my $RTName = get_TypeName($Return, $LibVersion);
        $Report .= "    <retval>\n";
        $Report .= "      <type>".htmlSpecChars($RTName)."</type>\n";
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
            $Report .= "    <old signature=\"".htmlSpecChars($S1)."\">\n";
            $Report .= $P1;
            $Report .= "    </old>\n";
        }
        if($S2 and $S2 ne $S1)
        {
            $Report .= "    <new signature=\"".htmlSpecChars($S2)."\">\n";
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
        writeFile($RPath, $Report);
        if($Browse)
        {
            system($Browse." $RPath >/dev/null 2>&1 &");
            if($JoinReport or $DoubleReport)
            {
                if($Level eq "Binary")
                { # wait to open a browser
                    sleep(1);
                }
            }
        }
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
            $Report .= get_Report_SymbolsInfo($Level);
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
            my $Title = "$TargetLibraryFName: ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." compatibility report";
            my $Keywords = "$TargetLibraryFName, compatibility, API, report";
            my $Description = "Compatibility report for the $TargetLibraryFName $TargetComponent between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
            my ($BSummary, $BMetaData) = get_Summary("Binary");
            my ($SSummary, $SMetaData) = get_Summary("Source");
            my $Report = "<!-\- $BMetaData -\->\n<!-\- $SMetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."<body><a name='Source'></a><a name='Binary'></a><a name='Top'></a>";
            $Report .= get_Report_Header("Join")."
            <br/><div class='tabset'>
            <a id='BinaryID' href='#BinaryTab' class='tab active'>Binary-level</a>
            <a id='SourceID' href='#SourceTab' style='margin-left:3px' class='tab disabled'>Source-level</a>
            </div>";
            $Report .= "<div id='BinaryTab' class='tab'>\n$BSummary\n".get_Report_Added("Binary").get_Report_Removed("Binary").get_Report_Problems("High", "Binary").get_Report_Problems("Medium", "Binary").get_Report_Problems("Low", "Binary").get_Report_Problems("Safe", "Binary").get_SourceInfo()."<br/><br/><br/></div>";
            $Report .= "<div id='SourceTab' class='tab'>\n$SSummary\n".get_Report_Added("Source").get_Report_Removed("Source").get_Report_Problems("High", "Source").get_Report_Problems("Medium", "Source").get_Report_Problems("Low", "Source").get_Report_Problems("Safe", "Source").get_SourceInfo()."<br/><br/><br/></div>";
            $Report .= getReportFooter($TargetLibraryFName);
            $Report .= "\n<div style='height:999px;'></div>\n</body></html>";
            return $Report;
        }
        else
        {
            my ($Summary, $MetaData) = get_Summary($Level);
            my $Title = "$TargetLibraryFName: ".$Descriptor{1}{"Version"}." to ".$Descriptor{2}{"Version"}." ".lc($Level)." compatibility report";
            my $Keywords = "$TargetLibraryFName, ".lc($Level)." compatibility, API, report";
            my $Description = "$Level compatibility report for the $TargetLibraryFName $TargetComponent between ".$Descriptor{1}{"Version"}." and ".$Descriptor{2}{"Version"}." versions";
            if($Level eq "Binary")
            {
                if(getArch(1) eq getArch(2)
                and getArch(1) ne "unknown") {
                    $Description .= " on ".showArch(getArch(1));
                }
            }
            my $Report = "<!-\- $MetaData -\->\n".composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."\n<body>\n<div><a name='Top'></a>\n";
            $Report .= get_Report_Header($Level)."\n".$Summary."\n";
            $Report .= get_Report_Added($Level).get_Report_Removed($Level);
            $Report .= get_Report_Problems("High", $Level).get_Report_Problems("Medium", $Level).get_Report_Problems("Low", $Level).get_Report_Problems("Safe", $Level);
            $Report .= get_SourceInfo();
            $Report .= "</div>\n<br/><br/><br/><hr/>\n";
            $Report .= getReportFooter($TargetLibraryFName);
            $Report .= "\n<div style='height:999px;'></div>\n</body></html>";
            return $Report;
        }
    }
}

sub createReport()
{
    if($JoinReport)
    { # --join-report, --stdout
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

sub getReportFooter($)
{
    my $LibName = $_[0];
    my $FooterStyle = (not $JoinReport)?"width:99%":"width:97%;padding-top:3px";
    my $Footer = "<div style='$FooterStyle;font-size:11px;' align='right'><i>Generated on ".(localtime time); # report date
    $Footer .= " for <span style='font-weight:bold'>$LibName</span>"; # tested library/system name
    $Footer .= " by <a href='".$HomePage{"Wiki"}."'>ABI Compliance Checker</a>"; # tool name
    my $ToolSummary = "<br/>A tool for checking backward compatibility of a C/C++ library API&#160;&#160;";
    $Footer .= " $TOOL_VERSION &#160;$ToolSummary</i></div>"; # tool version
    return $Footer;
}

sub get_Report_Problems($$)
{
    my ($Priority, $Level) = @_;
    my $Report = get_Report_TypeProblems($Priority, $Level);
    if(my $SymProblems = get_Report_SymbolProblems($Priority, $Level)) {
        $Report .= $SymProblems;
    }
    if($Priority eq "Low")
    {
        $Report .= get_Report_ChangedConstants($Level);
        if($ReportFormat eq "html") {
            if($CheckImpl and $Level eq "Binary") {
                $Report .= get_Report_Impl();
            }
        }
    }
    if($ReportFormat eq "html")
    {
        if($Report)
        { # add anchor
            if($JoinReport)
            {
                if($Priority eq "Safe") {
                    $Report = "<a name=\'Other_".$Level."_Changes\'></a>".$Report;
                }
                else {
                    $Report = "<a name=\'".$Priority."_Risk_".$Level."_Problems\'></a>".$Report;
                }
            }
            else
            {
                if($Priority eq "Safe") {
                    $Report = "<a name=\'Other_Changes\'></a>".$Report;
                }
                else {
                    $Report = "<a name=\'".$Priority."_Risk_Problems\'></a>".$Report;
                }
            }
        }
    }
    return $Report;
}

sub composeHTML_Head($$$$$)
{
    my ($Title, $Keywords, $Description, $Styles, $Scripts) = @_;
    return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
    <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <meta name=\"keywords\" content=\"$Keywords\" />
    <meta name=\"description\" content=\"$Description\" />
    <title>
        $Title
    </title>
    <style type=\"text/css\">
    $Styles
    </style>
    <script type=\"text/javascript\" language=\"JavaScript\">
    <!--
    $Scripts
    -->
    </script>
    </head>";
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
    my $CurHeader = "";
    open(PREPROC, $Path) || die ("can't open file \'$Path\': $!\n");
    while(<PREPROC>)
    { # detecting public and private constants
        next if(not /\A#/);
        chomp($_);
        if(/#[ \t]+\d+[ \t]+\"(.+)\"/) {
            $CurHeader=path_format($1, $OSgroup);
        }
        if(not $Include_Neighbors{$Version}{get_filename($CurHeader)}
        and not $Registered_Headers{$Version}{$CurHeader})
        { # not a target
            next;
        }
        if(not is_target_header(get_filename($CurHeader)))
        { # user-defined header
            next;
        }
        if(/\#[ \t]*define[ \t]+([_A-Z0-9]+)[ \t]+(.+)[ \t]*\Z/)
        {
            my ($Name, $Value) = ($1, $2);
            if(not $Constants{$Version}{$Name}{"Access"})
            {
                $Constants{$Version}{$Name}{"Access"} = "public";
                $Constants{$Version}{$Name}{"Value"} = $Value;
                $Constants{$Version}{$Name}{"Header"} = get_filename($CurHeader);
            }
        }
        elsif(/\#[ \t]*undef[ \t]+([_A-Z]+)[ \t]*/) {
            $Constants{$Version}{$1}{"Access"} = "private";
        }
    }
    close(PREPROC);
    foreach my $Constant (keys(%{$Constants{$Version}}))
    {
        if($Constants{$Version}{$Constant}{"Access"} eq "private" or $Constant=~/_h\Z/i
        or isBuiltIn($Constants{$Version}{$Constant}{"Header"}))
        { # skip private constants
            delete($Constants{$Version}{$Constant});
        }
        else {
            delete($Constants{$Version}{$Constant}{"Access"});
        }
    }
}

my %IgnoreConstant=(
    "VERSION"=>1,
    "VERSIONCODE"=>1,
    "VERNUM"=>1,
    "VERS_INFO"=>1,
    "PATCHLEVEL"=>1,
    "INSTALLPREFIX"=>1,
    "VBUILD"=>1,
    "VPATCH"=>1,
    "VMINOR"=>1,
    "BUILD_STRING"=>1,
    "BUILD_TIME"=>1,
    "PACKAGE_STRING"=>1,
    "PRODUCTION"=>1,
    "CONFIGURE_COMMAND"=>1,
    "INSTALLDIR"=>1,
    "BINDIR"=>1,
    "CONFIG_FILE_PATH"=>1,
    "DATADIR"=>1,
    "EXTENSION_DIR"=>1,
    "INCLUDE_PATH"=>1,
    "LIBDIR"=>1,
    "LOCALSTATEDIR"=>1,
    "SBINDIR"=>1,
    "SYSCONFDIR"=>1,
    "RELEASE"=>1,
    "SOURCE_ID"=>1,
    "SUBMINOR"=>1,
    "MINOR"=>1,
    "MINNOR"=>1,
    "MINORVERSION"=>1,
    "MAJOR"=>1,
    "MAJORVERSION"=>1,
    "MICRO"=>1,
    "MICROVERSION"=>1,
    "BINARY_AGE"=>1,
    "INTERFACE_AGE"=>1,
    "CORE_ABI"=>1,
    "PATCH"=>1,
    "COPYRIGHT"=>1,
    "TIMESTAMP"=>1,
    "REVISION"=>1,
    "PACKAGE_TAG"=>1,
    "PACKAGEDATE"=>1,
    "NUMVERSION"=>1
);

sub mergeConstants($)
{
    my $Level = $_[0];
    foreach my $Constant (keys(%{$Constants{1}}))
    {
        if($SkipConstants{1}{$Constant})
        { # skipped by the user
            next;
        }
        if($Constants{2}{$Constant}{"Value"} eq "")
        { # empty value
            next;
        }
        if(not is_target_header($Constants{1}{$Constant}{"Header"}))
        { # user-defined header
            next;
        }
        my ($Old_Value, $New_Value, $Old_Value_Pure, $New_Value_Pure);
        $Old_Value = $Old_Value_Pure = uncover_constant(1, $Constant);
        $New_Value = $New_Value_Pure = uncover_constant(2, $Constant);
        $Old_Value_Pure=~s/(\W)\s+/$1/g;
        $Old_Value_Pure=~s/\s+(\W)/$1/g;
        $New_Value_Pure=~s/(\W)\s+/$1/g;
        $New_Value_Pure=~s/\s+(\W)/$1/g;
        next if($New_Value_Pure eq "" or $Old_Value_Pure eq "");
        if($New_Value_Pure ne $Old_Value_Pure)
        { # different values
            if($Level eq "Binary")
            {
                if(grep {$Constant=~/(\A|_)$_(_|\Z)/} keys(%IgnoreConstant))
                { # ignore library version
                    next;
                }
                if($Constant=~/(\A|_)(lib|open|)$TargetLibraryShortName(_|)(VERSION|VER|DATE|API|PREFIX)(_|\Z)/i)
                { # ignore library version
                    next;
                }
                if($Old_Value=~/\A('|"|)[\/\\]\w+([\/\\]|:|('|"|)\Z)/ or $Old_Value=~/[\/\\]\w+[\/\\]\w+/)
                { # ignoring path defines:
                #  /lib64:/usr/lib64:/lib:/usr/lib:/usr/X11R6/lib/Xaw3d ...
                    next;
                }
                if($Old_Value=~/\A\(*[a-z_]+(\s+|\|)/i)
                { # ignore source defines:
                #  static int gcry_pth_init ( void) { return ...
                #  (RE_BACKSLASH_ESCAPE_IN_LISTS | RE...
                    next;
                }
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
            %{$ProblemsWithConstants{$Level}{$Constant}} = (
                "Target"=>$Constant,
                "Old_Value"=>$Old_Value,
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

sub uncover_constant($$)
{
    my ($LibVersion, $Constant) = @_;
    return "" if(not $LibVersion or not $Constant);
    return $Constant if(isCyclical(\@RecurConstant, $Constant));
    if(defined $Cache{"uncover_constant"}{$LibVersion}{$Constant}) {
        return $Cache{"uncover_constant"}{$LibVersion}{$Constant};
    }
    my $Value = $Constants{$LibVersion}{$Constant}{"Value"};
    if($Value=~/\A[A-Z0-9_]+\Z/ and $Value=~/[A-Z]/)
    {
        push(@RecurConstant, $Constant);
        if((my $Uncovered = uncover_constant($LibVersion, $Value)) ne "") {
            $Value = $Uncovered;
        }
        pop(@RecurConstant);
    }
    # FIXME: uncover $Value using all the enum constants
    # USECASE: change of define NC_LONG from NC_INT (enum value) to NC_INT (define)
    $Cache{"uncover_constant"}{$LibVersion}{$Constant} = $Value;
    return $Value;
}

sub getSymbols($)
{
    my $LibVersion = $_[0];
    my @DyLibPaths = getSoPaths($LibVersion);
    if($#DyLibPaths==-1 and not $CheckHeadersOnly)
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
    my %GroupNames = map {parse_libname(get_filename($_), "name+ext", $OStarget)=>1} @DyLibPaths;
    foreach my $DyLibPath (sort {length($a)<=>length($b)} @DyLibPaths) {
        getSymbols_Lib($LibVersion, $DyLibPath, 0, \%GroupNames, "+Weak");
    }
}

sub get_VTableSymbolSize($$)
{
    my ($ClassName, $LibVersion) = @_;
    return 0 if(not $ClassName);
    if(my $Symbol = $ClassVTable{$ClassName})
    {
        if(defined $Symbol_Library{$LibVersion}{$Symbol}
        and my $DyLib = $Symbol_Library{$LibVersion}{$Symbol})
        { # bind class name and v-table size
            if(defined $Library_Symbol{$LibVersion}{$DyLib}{$Symbol}
            and my $Size = -$Library_Symbol{$LibVersion}{$DyLib}{$Symbol})
            { # size from the shared library
                if($Size>=12) {
    #               0     (int (*)(...))0
    #               4     (int (*)(...))(& _ZTIN7mysqlpp8DateTimeE)
    #               8     mysqlpp::DateTime::~DateTime
                    return $Size;
                }
                else {
                    return 0;
                }
            }
        }
    }
}

sub canonifyName($)
{ # make TIFFStreamOpen(char const*, std::basic_ostream<char, std::char_traits<char> >*)
  # to be TIFFStreamOpen(char const*, std::basic_ostream<char>*)
    my $Name = $_[0];
    my $Rem = "std::(allocator|less|char_traits|regex_traits)";
    if($Name=~/([^<>,]+),\s*$Rem<([^<>,]+)>\s*/)
    {
        if($1 eq $3)
        {
            my $P = $1;
            while($Name=~s/\Q$P\E,\s*$Rem<\Q$P\E>\s*/$P/g){};
        }
    }
    return $Name;
}

sub translateSymbols(@)
{
    my $LibVersion = pop(@_);
    my (@MnglNames1, @MnglNames2, @UnMnglNames) = ();
    foreach my $Interface (sort @_)
    {
        if($Interface=~/\A_Z/)
        {
            next if($tr_name{$Interface});
            $Interface=~s/[\@\$]+(.*)\Z//;
            push(@MnglNames1, $Interface);
        }
        elsif($Interface=~/\A\?/) {
            push(@MnglNames2, $Interface);
        }
        else
        { # not mangled
            $tr_name{$Interface} = $Interface;
            $mangled_name_gcc{$Interface} = $Interface;
            $mangled_name{$LibVersion}{$Interface} = $Interface;
        }
    }
    if($#MnglNames1 > -1)
    { # GCC names
        @UnMnglNames = reverse(unmangleArray(@MnglNames1));
        foreach my $MnglName (@MnglNames1)
        {
            my $Unmangled = $tr_name{$MnglName} = formatName(canonifyName(pop(@UnMnglNames)));
            if(not $mangled_name_gcc{$Unmangled}) {
                $mangled_name_gcc{$Unmangled} = $MnglName;
            }
            if($MnglName=~/\A_ZTV/ and $Unmangled=~/vtable for (.+)/)
            { # bind class name and v-table symbol
                my $ClassName = $1;
                $ClassVTable{$ClassName} = $MnglName;
                $VTableClass{$MnglName} = $ClassName;
            }
        }
    }
    if($#MnglNames2 > -1)
    { # MSVC names
        @UnMnglNames = reverse(unmangleArray(@MnglNames2));
        foreach my $MnglName (@MnglNames2)
        {
            $tr_name{$MnglName} = formatName(pop(@UnMnglNames));
            $mangled_name{$LibVersion}{$tr_name{$MnglName}} = $MnglName;
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
        if(link_symbol_internal($Symbol, $RunWith, \%DepSymbols)) {
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
      # foo_old may be in .symtab table
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

sub getSymbols_App($)
{
    my $Path = $_[0];
    return () if(not $Path or not -f $Path);
    my @Imported = ();
    if($OSgroup eq "macos")
    {
        my $OtoolCmd = get_CmdPath("otool");
        if(not $OtoolCmd) {
            exitStatus("Not_Found", "can't find \"otool\"");
        }
        open(APP, "$OtoolCmd -IV \"".$Path."\" 2>$TMP_DIR/null |");
        while(<APP>) {
            if(/[^_]+\s+_?([\w\$]+)\s*\Z/) {
                push(@Imported, $1);
            }
        }
        close(APP);
    }
    elsif($OSgroup eq "windows")
    {
        my $DumpBinCmd = get_CmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin.exe\"");
        }
        open(APP, "$DumpBinCmd /IMPORTS \"".$Path."\" 2>$TMP_DIR/null |");
        while(<APP>) {
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
        open(APP, "$ReadelfCmd -WhlSsdA \"".$Path."\" 2>$TMP_DIR/null |");
        my $symtab=0; # indicates that we are processing 'symtab' section of 'readelf' output
        while(<APP>)
        {
            if( /'.dynsym'/ ) {
                $symtab=0;
            }
            elsif($symtab == 1) {
                # do nothing with symtab (but there are some plans for the future)
                next;
            }
            elsif( /'.symtab'/ ) {
                $symtab=1;
            }
            elsif(my ($fullname, $idx, $Ndx, $type, $size, $bind) = readline_ELF($_))
            {
                if( $Ndx eq "UND" ) {
                    #only imported symbols
                    push(@Imported, $fullname);
                }
            }
        }
        close(APP);
    }
    return @Imported;
}

sub readline_ELF($)
{
    if($_[0]=~/\s*\d+:\s+(\w*)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s([^\s]+)/)
    { # the line of 'readelf' output corresponding to the interface
      # symbian-style: _ZN12CCTTokenType4NewLE4TUid3RFs@@ctfinder{000a0000}[102020e5].dll
        my ($value, $size, $type, $bind,
        $vis, $Ndx, $fullname)=($1, $2, $3, $4, $5, $6, $7);
        if($bind!~/\A(WEAK|GLOBAL)\Z/) {
            return ();
        }
        if($type!~/\A(FUNC|IFUNC|OBJECT|COMMON)\Z/) {
            return ();
        }
        if($vis!~/\A(DEFAULT|PROTECTED)\Z/) {
            return ();
        }
        if($Ndx eq "ABS" and $value!~/\D|1|2|3|4|5|6|7|8|9/) {
            return ();
        }
        if($OStarget eq "symbian")
        {
            if($fullname=~/_\._\.absent_export_\d+/)
            { # "_._.absent_export_111"@@libstdcpp{00010001}[10282872].dll
                return ();
            }
            my @Elems = separate_symbol($fullname);
            $fullname = $Elems[0]; # remove internal version, {00020001}[10011235].dll
        }
        return ($fullname, $value, $Ndx, $type, $size, $bind);
    }
    else {
        return ();
    }
}

sub getSymbols_Lib($$$$$)
{
    my ($LibVersion, $Lib_Path, $IsNeededLib, $GroupNames, $Weak) = @_;
    return if(not $Lib_Path or not -f $Lib_Path);
    my ($Lib_Dir, $Lib_Name) = separate_path(resolve_symlink($Lib_Path));
    return if($CheckedDyLib{$LibVersion}{$Lib_Name} and $IsNeededLib);
    return if(isCyclical(\@RecurLib, $Lib_Name) or $#RecurLib>=1);
    $CheckedDyLib{$LibVersion}{$Lib_Name} = 1;
    if($CheckImpl and not $IsNeededLib) {
        getImplementations($LibVersion, $Lib_Path);
    }
    push(@RecurLib, $Lib_Name);
    my (%Value_Interface, %Interface_Value, %NeededLib) = ();
    if(not $IsNeededLib)
    { # libstdc++ and libc are always used by other libs
      # if you test one of these libs then you not need
      # to find them in the system for reusing
        if(parse_libname($Lib_Name, "short", $OStarget) eq "libstdc++")
        { # libstdc++.so.6
            $STDCXX_TESTING = 1;
        }
        if(parse_libname($Lib_Name, "short", $OStarget) eq "libc")
        { # libc-2.11.3.so
            $GLIBC_TESTING = 1;
        }
    }
    my $DebugPath = "";
    if($Debug)
    { # debug mode
        $DebugPath = $DEBUG_PATH{$LibVersion}."/libs/".get_filename($Lib_Path).".txt";
        mkpath(get_dirname($DebugPath));
    }
    if($OStarget eq "macos")
    { # Mac OS X: *.dylib, *.a
        my $OtoolCmd = get_CmdPath("otool");
        if(not $OtoolCmd) {
            exitStatus("Not_Found", "can't find \"otool\"");
        }
        $OtoolCmd .= " -TV \"".$Lib_Path."\" 2>$TMP_DIR/null";
        if($Debug)
        { # debug mode
            system($OtoolCmd." >".$DebugPath);
            open(LIB, $DebugPath); # write to file
        }
        else {
            open(LIB, $OtoolCmd." |"); # write to pipe
        }
        while(<LIB>)
        {
            if(/[^_]+\s+_([\w\$]+)\s*\Z/)
            {
                my $realname = $1;
                if($IsNeededLib and $GroupNames
                and not $GroupNames->{parse_libname($Lib_Name, "name+ext", $OStarget)}) {
                    $DepSymbols{$LibVersion}{$realname} = 1;
                }
                if(not $IsNeededLib)
                {
                    $Symbol_Library{$LibVersion}{$realname} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$realname} = 1;
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++"
                    and $realname=~/\A(_Z|\?)/) {
                        setLanguage($LibVersion, "C++");
                    }
                    if($CheckObjectsOnly
                    and $LibVersion==1) {
                        $CheckedSymbols{"Binary"}{$realname} = 1;
                    }
                }
            }
        }
        close(LIB);
        if($LIB_TYPE eq "dynamic")
        { # dependencies
            open(LIB, "$OtoolCmd -L \"".$Lib_Path."\" 2>$TMP_DIR/null |");
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
    elsif($OStarget eq "windows")
    { # Windows *.dll, *.lib
        my $DumpBinCmd = get_CmdPath("dumpbin");
        if(not $DumpBinCmd) {
            exitStatus("Not_Found", "can't find \"dumpbin\"");
        }
        $DumpBinCmd .= " /EXPORTS \"".$Lib_Path."\" 2>$TMP_DIR/null";
        if($Debug)
        { # debug mode
            system($DumpBinCmd." >".$DebugPath);
            open(LIB, $DebugPath); # write to file
        }
        else {
            open(LIB, $DumpBinCmd." |"); # write to pipe
        }
        while(<LIB>)
        { # 1197 4AC 0000A620 SetThreadStackGuarantee
          # 1198 4AD          SetThreadToken (forwarded to ...)
          # 3368 _o2i_ECPublicKey
            if(/\A\s*\d+\s+[a-f\d]+\s+[a-f\d]+\s+([\w\?\@]+)\s*\Z/i
            or /\A\s*\d+\s+[a-f\d]+\s+([\w\?\@]+)\s*\(\s*forwarded\s+/
            or /\A\s*\d+\s+_([\w\?\@]+)\s*\Z/)
            { # dynamic, static and forwarded symbols
                my $realname = $1;
                if($IsNeededLib and not $GroupNames->{parse_libname($Lib_Name, "name+ext", $OStarget)}) {
                    $DepSymbols{$LibVersion}{$realname} = 1;
                }
                if(not $IsNeededLib)
                {
                    $Symbol_Library{$LibVersion}{$realname} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$realname} = 1;
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++"
                    and $realname=~/\A(_Z|\?)/) {
                        setLanguage($LibVersion, "C++");
                    }
                    if($CheckObjectsOnly
                    and $LibVersion==1) {
                        $CheckedSymbols{"Binary"}{$realname} = 1;
                    }
                }
            }
        }
        close(LIB);
        if($LIB_TYPE eq "dynamic")
        { # dependencies
            open(LIB, "$DumpBinCmd /DEPENDENTS \"".$Lib_Path."\" 2>$TMP_DIR/null |");
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
    else
    { # Unix; *.so, *.a
      # Symbian: *.dso, *.lib
        my $ReadelfCmd = get_CmdPath("readelf");
        if(not $ReadelfCmd) {
            exitStatus("Not_Found", "can't find \"readelf\"");
        }
        $ReadelfCmd .= " -WhlSsdA \"".$Lib_Path."\" 2>$TMP_DIR/null";
        if($Debug)
        { # debug mode
            system($ReadelfCmd." >".$DebugPath);
            open(LIB, $DebugPath); # write to file
        }
        else {
            open(LIB, $ReadelfCmd." |"); # write to pipe
        }
        my $symtab=0; # indicates that we are processing 'symtab' section of 'readelf' output
        while(<LIB>)
        {
            if($LIB_TYPE eq "dynamic")
            { # dynamic library specifics
                if(/NEEDED.+\[([^\[\]]+)\]/)
                { # dependencies:
                  # 0x00000001 (NEEDED) Shared library: [libc.so.6]
                    $NeededLib{$1} = 1;
                    next;
                }
                if(/'\.dynsym'/)
                { # dynamic table
                    $symtab=0;
                    next;
                }
                if($symtab == 1)
                { # do nothing with symtab
                    next;
                }
                if(/'\.symtab'/)
                { # symbol table
                    $symtab=1;
                    next;
                }
            }
            if(not $LIB_ARCH{$LibVersion})
            {
                if(/Machine:.*?([\w\-]+)\s*\Z/)
                { # architecture
                    $LIB_ARCH{$LibVersion}=$1;
                    next;
                }
            }
            if(my ($fullname, $idx, $Ndx, $type, $size, $bind) = readline_ELF($_))
            { # read ELF entry
                if( $Ndx eq "UND" )
                { # ignore interfaces that are imported from somewhere else
                    next;
                }
                if($bind eq "WEAK"
                and $Weak eq "-Weak")
                { # skip WEAK symbols
                    next;
                }
                my ($realname, $version_spec, $version) = separate_symbol($fullname);
                if($type eq "OBJECT")
                { # global data
                    $CompleteSignature{$LibVersion}{$fullname}{"Object"} = 1;
                    $CompleteSignature{$LibVersion}{$realname}{"Object"} = 1;
                }
                if($IsNeededLib and not $GroupNames->{parse_libname($Lib_Name, "name+ext", $OStarget)}) {
                    $DepSymbols{$LibVersion}{$fullname} = 1;
                }
                if(not $IsNeededLib)
                {
                    $Symbol_Library{$LibVersion}{$fullname} = $Lib_Name;
                    $Library_Symbol{$LibVersion}{$Lib_Name}{$fullname} = ($type eq "OBJECT")?-$size:1;
                    if($LIB_EXT eq "so")
                    { # value
                        $Interface_Value{$LibVersion}{$fullname} = $idx;
                        $Value_Interface{$LibVersion}{$idx}{$fullname} = 1;
                    }
                    if($COMMON_LANGUAGE{$LibVersion} ne "C++"
                    and $realname=~/\A(_Z|\?)/) {
                        setLanguage($LibVersion, "C++");
                    }
                    if($CheckObjectsOnly
                    and $LibVersion==1) {
                        $CheckedSymbols{"Binary"}{$fullname} = 1;
                    }
                }
            }
        }
        close(LIB);
    }
    if(not $IsNeededLib and $LIB_EXT eq "so")
    { # get symbol versions
        foreach my $Symbol (keys(%{$Symbol_Library{$LibVersion}}))
        {
            next if($Symbol!~/\@/);
            my $Interface_SymName = "";
            foreach my $Symbol_SameValue (keys(%{$Value_Interface{$LibVersion}{$Interface_Value{$LibVersion}{$Symbol}}}))
            {
                if($Symbol_SameValue ne $Symbol
                and $Symbol_SameValue!~/\@/)
                {
                    $SymVer{$LibVersion}{$Symbol_SameValue} = $Symbol;
                    $Interface_SymName = $Symbol_SameValue;
                    last;
                }
            }
            if(not $Interface_SymName)
            {
                if($Symbol=~/\A([^\@\$\?]*)[\@\$]+([^\@\$]*)\Z/
                and not $SymVer{$LibVersion}{$1}) {
                    $SymVer{$LibVersion}{$1} = $Symbol;
                }
            }
        }
    }
    foreach my $DyLib (sort keys(%NeededLib))
    {
        my $DepPath = find_lib_path($LibVersion, $DyLib);
        if($DepPath and -f $DepPath) {
            getSymbols_Lib($LibVersion, $DepPath, 1, $GroupNames, "+Weak");
        }
    }
    pop(@RecurLib);
    return $Library_Symbol{$LibVersion};
}

sub get_path_prefixes($)
{
    my $Path = $_[0];
    my ($Dir, $Name) = separate_path($Path);
    my %Prefixes = ();
    foreach my $Prefix (reverse(split(/[\/\\]+/, $Dir)))
    {
        $Prefixes{$Name} = 1;
        $Name = joinPath($Prefix, $Name);
        last if(keys(%Prefixes)>5 or $Prefix eq "include");
    }
    return keys(%Prefixes);
}

sub detectSystemHeaders()
{
    my @SysHeaders = ();
    foreach my $DevelPath (keys(%{$SystemPaths{"include"}}))
    {
        next if(not -d $DevelPath);
        # search for all header files in the /usr/include
        # with or without extension (ncurses.h, QtCore, ...)
        @SysHeaders = (@SysHeaders, cmd_find($DevelPath,"f","",""));
        foreach my $Link (cmd_find($DevelPath,"l","",""))
        { # add symbolic links
            if(-f $Link) {
                push(@SysHeaders, $Link);
            }
        }
    }
    foreach my $DevelPath (keys(%{$SystemPaths{"lib"}}))
    {
        next if(not -d $DevelPath);
        # search for config headers in the /usr/lib
        @SysHeaders = (@SysHeaders, cmd_find($DevelPath,"f","*.h",""));
        foreach my $Dir (cmd_find($DevelPath,"d","include",""))
        { # search for all include directories
          # this is for headers that are installed to /usr/lib
          # Example: Qt4 headers in Mandriva (/usr/lib/qt4/include/)
            if($Dir=~/\/(gcc|jvm|syslinux|kdb)\//) {
                next;
            }
            @SysHeaders = (@SysHeaders, cmd_find($Dir,"f","",""));
        }
    }
    foreach my $Path (@SysHeaders)
    {
        foreach my $Part (get_path_prefixes($Path)) {
            $SystemHeaders{$Part}{$Path}=1;
        }
    }
}

sub detectSystemObjects()
{
    foreach my $DevelPath (keys(%{$SystemPaths{"lib"}}))
    {
        next if(not -d $DevelPath);
        foreach my $Path (find_libs($DevelPath,"",""))
        { # search for shared libraries in the /usr/lib (including symbolic links)
            $SystemObjects{parse_libname(get_filename($Path), "name+ext", $OStarget)}{$Path}=1;
        }
    }
}

sub find_lib_path($$)
{
    my ($LibVersion, $DyLib) = @_;
    return "" if(not $DyLib or not $LibVersion);
    return $DyLib if(is_abs($DyLib));
    if(defined $Cache{"find_lib_path"}{$LibVersion}{$DyLib}) {
        return $Cache{"find_lib_path"}{$LibVersion}{$DyLib};
    }
    if(my @Paths = sort keys(%{$InputObject_Paths{$LibVersion}{$DyLib}})) {
        return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = $Paths[0]);
    }
    elsif(my $DefaultPath = $DyLib_DefaultPath{$DyLib}) {
        return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = $DefaultPath);
    }
    else
    {
        foreach my $Dir (sort keys(%DefaultLibPaths), sort keys(%{$SystemPaths{"lib"}}))
        { # search in default linker paths and then in all system paths
            if(-f $Dir."/".$DyLib) {
                return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = joinPath($Dir,$DyLib));
            }
        }
        detectSystemObjects() if(not keys(%SystemObjects));
        if(my @AllObjects = keys(%{$SystemObjects{$DyLib}})) {
            return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = $AllObjects[0]);
        }
        my $ShortName = parse_libname($DyLib, "name+ext", $OStarget);
        if($ShortName ne $DyLib
        and my $Path = find_lib_path($ShortName))
        { # FIXME: check this case
            return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = $Path);
        }
        return ($Cache{"find_lib_path"}{$LibVersion}{$DyLib} = "");
    }
}

sub getSoPaths($)
{
    my $LibVersion = $_[0];
    my @SoPaths = ();
    foreach my $Dest (split(/\s*\n\s*/, $Descriptor{$LibVersion}{"Libs"}))
    {
        if(not -e $Dest) {
            exitStatus("Access_Error", "can't access \'$Dest\'");
        }
        my @SoPaths_Dest = getSOPaths_Dest($Dest, $LibVersion);
        foreach (@SoPaths_Dest) {
            push(@SoPaths, $_);
        }
    }
    return @SoPaths;
}

sub skip_lib($$)
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

sub skip_header($$)
{ # returns:
  #  1 - if header should NOT be included and checked
  #  2 - if header should NOT be included, but should be checked
    my ($Path, $LibVersion) = @_;
    return 1 if(not $Path or not $LibVersion);
    my $Name = get_filename($Path);
    if(my $Kind = $SkipHeaders{$LibVersion}{"Name"}{$Name}) {
        return $Kind;
    }
    foreach my $D (keys(%{$SkipHeaders{$LibVersion}{"Path"}}))
    {
        if($Path=~/\Q$D\E([\/\\]|\Z)/) {
            return $SkipHeaders{$LibVersion}{"Path"}{$D};
        }
    }
    foreach my $P (keys(%{$SkipHeaders{$LibVersion}{"Pattern"}}))
    {
        if($Name=~/$P/) {
            return $SkipHeaders{$LibVersion}{"Pattern"}{$P};
        }
        if($P=~/[\/\\]/ and $Path=~/$P/) {
            return $SkipHeaders{$LibVersion}{"Pattern"}{$P};
        }
    }
    return 0;
}

sub register_objects($$)
{
    my ($Dir, $LibVersion) = @_;
    if($SystemPaths{"lib"}{$Dir})
    { # system directory
        return;
    }
    if($RegisteredObjDirs{$LibVersion}{$Dir})
    { # already registered
        return;
    }
    foreach my $Path (find_libs($Dir,"",1))
    {
        next if(ignore_path($Path));
        next if(skip_lib($Path, $LibVersion));
        $InputObject_Paths{$LibVersion}{get_filename($Path)}{$Path} = 1;
    }
    $RegisteredObjDirs{$LibVersion}{$Dir} = 1;
}

sub getSOPaths_Dest($$)
{
    my ($Dest, $LibVersion) = @_;
    if(skip_lib($Dest, $LibVersion)) {
        return ();
    }
    if(-f $Dest)
    {
        if(not parse_libname($Dest, "name", $OStarget)) {
            exitStatus("Error", "incorrect format of library (should be *.$LIB_EXT): \'$Dest\'");
        }
        $InputObject_Paths{$LibVersion}{get_filename($Dest)}{$Dest} = 1;
        register_objects(get_dirname($Dest), $LibVersion);
        return ($Dest);
    }
    elsif(-d $Dest)
    {
        $Dest=~s/[\/\\]+\Z//g;
        my @AllObjects = ();
        if($SystemPaths{"lib"}{$Dest})
        { # you have specified /usr/lib as the search directory (<libs>) in the XML descriptor
          # and the real name of the library by -l option (bz2, stdc++, Xaw, ...)
            foreach my $Path (cmd_find($Dest,"","*".esc($TargetLibraryName)."*\.$LIB_EXT*",2))
            { # all files and symlinks that match the name of a library
                if(get_filename($Path)=~/\A(|lib)\Q$TargetLibraryName\E[\d\-]*\.$LIB_EXT[\d\.]*\Z/i)
                {
                    $InputObject_Paths{$LibVersion}{get_filename($Path)}{$Path} = 1;
                    push(@AllObjects, resolve_symlink($Path));
                }
            }
        }
        else
        { # search for all files and symlinks
            foreach my $Path (find_libs($Dest,"",""))
            {
                next if(ignore_path($Path));
                next if(skip_lib($Path, $LibVersion));
                $InputObject_Paths{$LibVersion}{get_filename($Path)}{$Path} = 1;
                push(@AllObjects, resolve_symlink($Path));
            }
            if($OSgroup eq "macos")
            { # shared libraries on MacOS X may have no extension
                foreach my $Path (cmd_find($Dest,"f","",""))
                {
                    next if(ignore_path($Path));
                    next if(skip_lib($Path, $LibVersion));
                    if(get_filename($Path)!~/\./
                    and cmd_file($Path)=~/(shared|dynamic)\s+library/i) {
                        $InputObject_Paths{$LibVersion}{get_filename($Path)}{$Path} = 1;
                        push(@AllObjects, resolve_symlink($Path));
                    }
                }
            }
        }
        return @AllObjects;
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

sub read_symlink($)
{
    my $Path = $_[0];
    return "" if(not $Path);
    return "" if(not -f $Path and not -l $Path);
    if(defined $Cache{"read_symlink"}{$Path}) {
        return $Cache{"read_symlink"}{$Path};
    }
    if(my $Res = readlink($Path)) {
        return ($Cache{"read_symlink"}{$Path} = $Res);
    }
    elsif(my $ReadlinkCmd = get_CmdPath("readlink")) {
        return ($Cache{"read_symlink"}{$Path} = `$ReadlinkCmd -n $Path`);
    }
    elsif(my $FileCmd = get_CmdPath("file"))
    {
        my $Info = `$FileCmd $Path`;
        if($Info=~/symbolic\s+link\s+to\s+['`"]*([\w\d\.\-\/\\]+)['`"]*/i) {
            return ($Cache{"read_symlink"}{$Path} = $1);
        }
    }
    return ($Cache{"read_symlink"}{$Path} = "");
}

sub resolve_symlink($)
{
    my $Path = $_[0];
    return "" if(not $Path);
    return "" if(not -f $Path and not -l $Path);
    if(defined $Cache{"resolve_symlink"}{$Path}) {
        return $Cache{"resolve_symlink"}{$Path};
    }
    return $Path if(isCyclical(\@RecurSymlink, $Path));
    push(@RecurSymlink, $Path);
    if(-l $Path and my $Redirect=read_symlink($Path))
    {
        if(is_abs($Redirect))
        { # absolute path
            if($SystemRoot and $SystemRoot ne "/"
            and $Path=~/\A\Q$SystemRoot\E\//
            and (-f $SystemRoot.$Redirect or -l $SystemRoot.$Redirect))
            { # symbolic links from the sysroot
              # should be corrected to point to
              # the files inside sysroot
                $Redirect = $SystemRoot.$Redirect;
            }
            my $Res = resolve_symlink($Redirect);
            pop(@RecurSymlink);
            return ($Cache{"resolve_symlink"}{$Path} = $Res);
        }
        elsif($Redirect=~/\.\.[\/\\]/)
        { # relative path
            $Redirect = joinPath(get_dirname($Path),$Redirect);
            while($Redirect=~s&(/|\\)[^\/\\]+(\/|\\)\.\.(\/|\\)&$1&){};
            my $Res = resolve_symlink($Redirect);
            pop(@RecurSymlink);
            return ($Cache{"resolve_symlink"}{$Path} = $Res);
        }
        elsif(-f get_dirname($Path)."/".$Redirect)
        { # file name in the same directory
            my $Res = resolve_symlink(joinPath(get_dirname($Path),$Redirect));
            pop(@RecurSymlink);
            return ($Cache{"resolve_symlink"}{$Path} = $Res);
        }
        else
        { # broken link
            pop(@RecurSymlink);
            return ($Cache{"resolve_symlink"}{$Path} = "");
        }
    }
    pop(@RecurSymlink);
    return ($Cache{"resolve_symlink"}{$Path} = $Path);
}

sub generateTemplate()
{
    writeFile("VERSION.xml", $DescriptorTemplate."\n");
    printMsg("INFO", "XML-descriptor template ./VERSION.xml has been generated");
}

sub detectWordSize()
{
    return "" if(not $GCC_PATH);
    if($Cache{"detectWordSize"}) {
        return $Cache{"detectWordSize"};
    }
    writeFile("$TMP_DIR/empty.h", "");
    my $Defines = `$GCC_PATH -E -dD $TMP_DIR/empty.h`;
    unlink("$TMP_DIR/empty.h");
    my $WSize = 0;
    if($Defines=~/ __SIZEOF_POINTER__\s+(\d+)/)
    { # GCC 4
        $WSize = $1;
    }
    elsif($Defines=~/ __PTRDIFF_TYPE__\s+(\w+)/)
    { # GCC 3
        my $PTRDIFF = $1;
        if($PTRDIFF=~/long/) {
            $WSize = 8;
        }
        else {
            $WSize = 4;
        }
    }
    if(not int($WSize)) {
        exitStatus("Error", "can't check WORD size");
    }
    return ($Cache{"detectWordSize"} = $WSize);
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
    return undef if($V1!~/\A\d+[\.\d+]*\Z/);
    return undef if($V2!~/\A\d+[\.\d+]*\Z/);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++) {
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
    if($Path=~/\.abi\Z/)
    { # input *.abi
        $FilePath = $Path;
    }
    else
    { # input *.abi.tar.gz
        $FilePath = unpackDump($Path);
    }
    if($FilePath!~/\.abi\Z/) {
        exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
    }
    my $Content = readFile($FilePath);
    if($Path!~/\.abi\Z/)
    { # remove temp file
        unlink($FilePath);
    }
    if($Content!~/};\s*\Z/) {
        exitStatus("Invalid_Dump", "specified ABI dump \'$Path\' is not valid, try to recreate it");
    }
    my $LibraryABI = eval($Content);
    if(not $LibraryABI) {
        exitStatus("Error", "internal error - eval() procedure seem to not working correctly, try to remove 'use strict' and try again");
    }
    # new dumps (>=1.22) have a personal versioning
    my $DumpVersion = $LibraryABI->{"ABI_DUMP_VERSION"};
    my $ToolVersion = $LibraryABI->{"ABI_COMPLIANCE_CHECKER_VERSION"};
    if(not $DumpVersion)
    { # old dumps (<=1.21.6) have been marked by the tool version
        $DumpVersion = $ToolVersion;
    }
    $UsedDump{$LibVersion}{"V"} = $DumpVersion;
    if(majorVersion($DumpVersion) ne majorVersion($ABI_DUMP_VERSION))
    { # should be compatible with dumps of the same major version
        if(cmpVersions($DumpVersion, $ABI_DUMP_VERSION)>0)
        { # Don't know how to parse future dump formats
            exitStatus("Dump_Version", "incompatible version $DumpVersion of specified ABI dump (newer than $ABI_DUMP_VERSION)");
        }
        elsif(cmpVersions($DumpVersion, $TOOL_VERSION)>0 and not $LibraryABI->{"ABI_DUMP_VERSION"})
        { # Don't know how to parse future dump formats
            exitStatus("Dump_Version", "incompatible version $DumpVersion of specified ABI dump (newer than $TOOL_VERSION)");
        }
        if($UseOldDumps)
        {
            if(cmpVersions($DumpVersion, $OLDEST_SUPPORTED_VERSION)<0) {
                exitStatus("Dump_Version", "incompatible version $DumpVersion of specified ABI dump (older than $OLDEST_SUPPORTED_VERSION)");
            }
        }
        else
        {
            my $Msg = "incompatible version $DumpVersion of specified ABI dump (allowed only ".majorVersion($ABI_DUMP_VERSION).".0<=V<=$ABI_DUMP_VERSION)";
            if(cmpVersions($DumpVersion, $OLDEST_SUPPORTED_VERSION)>=0) {
                $Msg .= "\nUse -old-dumps option to use old-version dumps ($OLDEST_SUPPORTED_VERSION<=V<".majorVersion($ABI_DUMP_VERSION).".0)";
            }
            exitStatus("Dump_Version", $Msg);
        }
    }
    if($LibraryABI->{"SrcBin"})
    { # default
        $UsedDump{$LibVersion}{"SrcBin"} = 1;
    }
    elsif($LibraryABI->{"BinOnly"})
    { # ABI dump created with --binary option
        $UsedDump{$LibVersion}{"BinOnly"} = 1;
    }
    if($LibraryABI->{"Mode"} eq "Extended")
    { # --ext option
        $ExtendedCheck = 1;
    }
    if(my $Lang = $LibraryABI->{"Language"})
    {
        $UsedDump{$LibVersion}{"L"} = $Lang;
        setLanguage($LibVersion, $Lang);
    }
    $TypeInfo{$LibVersion} = $LibraryABI->{"TypeInfo"};
    if(not $TypeInfo{$LibVersion})
    { # support for old ABI dumps
        $TypeInfo{$LibVersion} = $LibraryABI->{"TypeDescr"};
    }
    read_Machine_DumpInfo($LibraryABI, $LibVersion);
    $SymbolInfo{$LibVersion} = $LibraryABI->{"SymbolInfo"};
    if(not $SymbolInfo{$LibVersion})
    { # support for old dumps
        $SymbolInfo{$LibVersion} = $LibraryABI->{"FuncDescr"};
    }
    if(not keys(%{$SymbolInfo{$LibVersion}}))
    { # validation of old-version dumps
        if(not $ExtendedCheck) {
            exitStatus("Invalid_Dump", "the input dump d$LibVersion is invalid");
        }
    }
    $Library_Symbol{$LibVersion} = $LibraryABI->{"Symbols"};
    if(not $Library_Symbol{$LibVersion})
    { # support for old dumps
        $Library_Symbol{$LibVersion} = $LibraryABI->{"Interfaces"};
    }
    $DepSymbols{$LibVersion} = $LibraryABI->{"DepSymbols"};
    if(not $DepSymbols{$LibVersion})
    { # support for old dumps
        $DepSymbols{$LibVersion} = $LibraryABI->{"DepInterfaces"};
    }
    if(not $DepSymbols{$LibVersion})
    { # support for old dumps
      # Cannot reconstruct DepSymbols. This may result in false
      # positives if the old dump is for library 2. Not a problem if
      # old dumps are only from old libraries.
        $DepSymbols{$LibVersion} = {};
    }
    $SymVer{$LibVersion} = $LibraryABI->{"SymbolVersion"};
    $Tid_TDid{$LibVersion} = $LibraryABI->{"Tid_TDid"};
    $Descriptor{$LibVersion}{"Version"} = $LibraryABI->{"LibraryVersion"};
    $SkipTypes{$LibVersion} = $LibraryABI->{"SkipTypes"};
    if(not $SkipTypes{$LibVersion})
    { # support for old dumps
        $SkipTypes{$LibVersion} = $LibraryABI->{"OpaqueTypes"};
    }
    $SkipSymbols{$LibVersion} = $LibraryABI->{"SkipSymbols"};
    if(not $SkipSymbols{$LibVersion})
    { # support for old dumps
        $SkipSymbols{$LibVersion} = $LibraryABI->{"SkipInterfaces"};
    }
    if(not $SkipSymbols{$LibVersion})
    { # support for old dumps
        $SkipSymbols{$LibVersion} = $LibraryABI->{"InternalInterfaces"};
    }
    $SkipNameSpaces{$LibVersion} = $LibraryABI->{"SkipNameSpaces"};
    $TargetHeaders{$LibVersion} = $LibraryABI->{"TargetHeaders"};
    foreach my $Path (keys(%{$LibraryABI->{"SkipHeaders"}}))
    {
        $SkipHeadersList{$LibVersion}{$Path} = $LibraryABI->{"SkipHeaders"}{$Path};
        my ($CPath, $Type) = classifyPath($Path);
        $SkipHeaders{$LibVersion}{$Type}{$CPath} = $LibraryABI->{"SkipHeaders"}{$Path};
    }
    read_Headers_DumpInfo($LibraryABI, $LibVersion);
    read_Libs_DumpInfo($LibraryABI, $LibVersion);
    if(not $Descriptor{$LibVersion}{"Libs"})
    { # support for old ABI dumps
        if(cmpVersions($DumpVersion, "2.10.1")<0)
        {
            if(not $TargetHeaders{$LibVersion})
            {
                foreach (keys(%{$Registered_Headers{$LibVersion}})) {
                    $TargetHeaders{$LibVersion}{get_filename($_)}=1;
                }
            }
        }
    }
    $Constants{$LibVersion} = $LibraryABI->{"Constants"};
    $NestedNameSpaces{$LibVersion} = $LibraryABI->{"NameSpaces"};
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
        $OStarget = $LibraryABI->{"Target"};
    }
    # recreate environment
    foreach my $Lib_Name (keys(%{$Library_Symbol{$LibVersion}}))
    {
        foreach my $Interface (keys(%{$Library_Symbol{$LibVersion}{$Lib_Name}}))
        {
            $Symbol_Library{$LibVersion}{$Interface} = $Lib_Name;
            if($Library_Symbol{$LibVersion}{$Lib_Name}{$Interface}<=-1)
            { # data marked as -size in the dump
                $CompleteSignature{$LibVersion}{$Interface}{"Object"} = 1;
            }
            if($COMMON_LANGUAGE{$LibVersion} ne "C++"
            and $Interface=~/\A(_Z|\?)/) {
                setLanguage($LibVersion, "C++");
            }
        }
    }
    my @VFunc = ();
    foreach my $InfoId (keys(%{$SymbolInfo{$LibVersion}}))
    {
        my $MnglName = $SymbolInfo{$LibVersion}{$InfoId}{"MnglName"};
        if(not $MnglName)
        { # C-functions
            next;
        }
        if(not $Symbol_Library{$LibVersion}{$MnglName}
        and not $DepSymbols{$LibVersion}{$MnglName}) {
            push(@VFunc, $MnglName);
        }
    }
    translateSymbols(@VFunc, $LibVersion);
    translateSymbols(keys(%{$Symbol_Library{$LibVersion}}), $LibVersion);
    translateSymbols(keys(%{$DepSymbols{$LibVersion}}), $LibVersion);

    foreach my $TypeDeclId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}}))
    {
        foreach my $TypeId (sort {int($a)<=>int($b)} keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}}))
        {
            if(defined $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"BaseClass"})
            { # support for old ABI dumps < 2.0 (ACC 1.22)
                foreach my $BId (keys(%{$TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"BaseClass"}}))
                {
                    if(my $Access = $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"BaseClass"}{$BId})
                    {
                        if($Access ne "public") {
                            $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Base"}{$BId}{"access"} = $Access;
                        }
                    }
                    $TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"Base"}{$BId} = {};
                }
                delete($TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}{"BaseClass"});
            }
            my %TInfo = %{$TypeInfo{$LibVersion}{$TypeDeclId}{$TypeId}};
            if(defined $TInfo{"Base"})
            {
                foreach (keys(%{$TInfo{"Base"}})) {
                    $Class_SubClasses{$LibVersion}{$_}{$TypeId}=1;
                }
            }
            if($TInfo{"Type"} eq "Typedef")
            {
                my ($BTDid, $BTid) = ($TInfo{"BaseType"}{"TDid"}, $TInfo{"BaseType"}{"Tid"});
                $Typedef_BaseName{$LibVersion}{$TInfo{"Name"}} = $TypeInfo{$LibVersion}{$BTDid}{$BTid}{"Name"};
            }
            if(not $TName_Tid{$LibVersion}{$TInfo{"Name"}})
            { # classes: class (id1), typedef (artificial, id2 > id1)
                $TName_Tid{$LibVersion}{$TInfo{"Name"}} = $TypeId;
            }
        }
    }
    
    $Descriptor{$LibVersion}{"Dump"} = 1;
}

sub read_Machine_DumpInfo($$)
{
    my ($LibraryABI, $LibVersion) = @_;
    if($LibraryABI->{"Arch"}) {
        $CPU_ARCH{$LibVersion} = $LibraryABI->{"Arch"};
    }
    if($LibraryABI->{"WordSize"}) {
        $WORD_SIZE{$LibVersion} = $LibraryABI->{"WordSize"};
    }
    else
    { # support for old dumps
        $WORD_SIZE{$LibVersion} = $LibraryABI->{"SizeOfPointer"};
    }
    if(not $WORD_SIZE{$LibVersion})
    { # support for old dumps (<1.23)
        if(my $Tid = getTypeIdByName("char*", $LibVersion))
        { # size of char*
            $WORD_SIZE{$LibVersion} = get_TypeSize($Tid, $LibVersion);
        }
        else
        {
            my $PSize = 0;
            foreach my $TDid (keys(%{$TypeInfo{$LibVersion}}))
            {
                foreach my $Tid (keys(%{$TypeInfo{$LibVersion}{$TDid}}))
                {
                    if(get_TypeAttr($Tid, $LibVersion, "Type") eq "Pointer")
                    { # any "pointer"-type
                        $PSize = get_TypeSize($Tid, $LibVersion);
                        last;
                    }
                }
                if($PSize) {
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
    if($LibraryABI->{"GccVersion"}) {
        $GCC_VERSION{$LibVersion} = $LibraryABI->{"GccVersion"};
    }
}

sub read_Libs_DumpInfo($$)
{
    my ($LibraryABI, $LibVersion) = @_;
    if(keys(%{$Library_Symbol{$LibVersion}})
    and not $DumpAPI) {
        $Descriptor{$LibVersion}{"Libs"} = "OK";
    }
}

sub read_Headers_DumpInfo($$)
{
    my ($LibraryABI, $LibVersion) = @_;
    if(keys(%{$LibraryABI->{"Headers"}})
    and not $DumpAPI) {
        $Descriptor{$LibVersion}{"Headers"} = "OK";
    }
    foreach my $Identity (keys(%{$LibraryABI->{"Headers"}}))
    { # headers info is stored in the old dumps in the different way
        if($UseOldDumps
        and my $Name = $LibraryABI->{"Headers"}{$Identity}{"Name"})
        { # support for old dumps: headers info corrected in 1.22
            $Identity = $Name;
        }
        $Registered_Headers{$LibVersion}{$Identity}{"Identity"} = $Identity;
    }
}

sub find_libs($$$)
{
    my ($Path, $Type, $MaxDepth) = @_;
    # FIXME: correct the search pattern
    return cmd_find($Path, $Type, ".*\\.$LIB_EXT\[0-9.]*", $MaxDepth);
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
        if($Path=~/\.xml\Z/i)
        { # standard XML-descriptor
            return readFile($Path);
        }
        elsif(is_header($Path, 2, $LibVersion))
        { # header file
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
        elsif(parse_libname($Path, "name", $OStarget))
        { # shared object
            return "
                <version>
                    ".$TargetVersion{$LibVersion}."
                </version>

                <headers>
                    none
                </headers>

                <libs>
                    $Path
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
        if(my $LdConfig = get_CmdPath("ldconfig")) {
            foreach my $Line (split(/\n/, `$LdConfig -r 2>$TMP_DIR/null`)) {
                if($Line=~/\A[ \t]*\d+:\-l(.+) \=\> (.+)\Z/) {
                    $LPaths{"lib".$1} = $2;
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
            foreach my $Line (split(/\n/, `$LdConfig -p 2>$TMP_DIR/null`)) {
                if($Line=~/\A[ \t]*([^ \t]+) .* \=\> (.+)\Z/)
                {
                    my ($Name, $Path) = ($1, $2);
                    $Path=~s/[\/]{2,}/\//;
                    $LPaths{$Name} = $Path;
                }
            }
        }
        elsif($OSgroup=~/linux/i) {
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
    foreach my $Path (sort {length($a)<=>length($b)} split(/$Sep/, $EnvPaths))
    {
        $Path = path_format($Path, $OSgroup);
        $Path=~s/[\/\\]+\Z//g;
        next if(not $Path);
        if($SystemRoot
        and $Path=~/\A\Q$SystemRoot\E\//)
        { # do NOT use binaries from target system
            next;
        }
        $DefaultBinPaths{$Path} = 1;
    }
}

sub detect_inc_default_paths()
{
    return () if(not $GCC_PATH);
    my %DPaths = ("Cpp"=>{},"Gcc"=>{},"Inc"=>{});
    writeFile("$TMP_DIR/empty.h", "");
    foreach my $Line (split(/\n/, `$GCC_PATH -v -x c++ -E "$TMP_DIR/empty.h" 2>&1`))
    { # detecting GCC default include paths
        if($Line=~/\A[ \t]*((\/|\w+:\\).+)[ \t]*\Z/)
        {
            my $Path = simplify_path($1);
            $Path=~s/[\/\\]+\Z//g;
            $Path = path_format($Path, $OSgroup);
            if($Path=~/c\+\+|\/g\+\+\//)
            {
                $DPaths{"Cpp"}{$Path}=1;
                if(not defined $MAIN_CPP_DIR
                or get_depth($MAIN_CPP_DIR)>get_depth($Path)) {
                    $MAIN_CPP_DIR = $Path;
                }
            }
            elsif($Path=~/gcc/) {
                $DPaths{"Gcc"}{$Path}=1;
            }
            else
            {
                next if($Path=~/local[\/\\]+include/);
                if($SystemRoot
                and $Path!~/\A\Q$SystemRoot\E(\/|\Z)/)
                { # The GCC include path for user headers is not a part of the system root
                  # The reason: you are not specified the --cross-gcc option or selected a wrong compiler
                  # or it is the internal cross-GCC path like arm-linux-gnueabi/include
                    next;
                }
                $DPaths{"Inc"}{$Path}=1;
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
    if(keys(%{$SystemPaths{"include"}}))
    { # <search_headers> section of the XML descriptor
      # do NOT search for systems headers
        $HSearch = 0;
    }
    if(keys(%{$SystemPaths{"lib"}}))
    { # <search_headers> section of the XML descriptor
      # do NOT search for systems headers
        $LSearch = 0;
    }
    foreach my $Type (keys(%{$OS_AddPath{$OSgroup}}))
    { # additional search paths
        next if($Type eq "include" and not $HSearch);
        next if($Type eq "lib" and not $LSearch);
        next if($Type eq "bin" and not $BSearch);
        foreach my $Path (keys(%{$OS_AddPath{$OSgroup}{$Type}}))
        {
            next if(not -d $Path);
            $SystemPaths{$Type}{$Path} = $OS_AddPath{$OSgroup}{$Type}{$Path};
        }
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
            foreach my $Path (cmd_find($RootDir,"d","*$Type*",1)) {
                $SystemPaths{$Type}{$Path} = 1;
            }
            if(-d $RootDir."/".$Type)
            { # if "/lib" is symbolic link
                if($RootDir eq "/") {
                    $SystemPaths{$Type}{"/".$Type} = 1;
                }
                else {
                    $SystemPaths{$Type}{$RootDir."/".$Type} = 1;
                }
            }
            if(-d $UsrDir) {
                foreach my $Path (cmd_find($UsrDir,"d","*$Type*",1)) {
                    $SystemPaths{$Type}{$Path} = 1;
                }
                if(-d $UsrDir."/".$Type)
                { # if "/usr/lib" is symbolic link
                    $SystemPaths{$Type}{$UsrDir."/".$Type} = 1;
                }
            }
        }
    }
    if($BSearch)
    {
        detect_bin_default_paths();
        foreach my $Path (keys(%DefaultBinPaths)) {
            $SystemPaths{"bin"}{$Path} = $DefaultBinPaths{$Path};
        }
    }
    # check environment variables
    if($OSgroup eq "beos")
    {
        foreach (keys(%{$SystemPaths{"bin"}}))
        {
            if($_ eq ".") {
                next;
            }
            foreach my $Path (cmd_find($_, "d", "bin", ""))
            { # search for /boot/develop/abi/x86/gcc4/tools/gcc-4.4.4-haiku-101111/bin/
                $SystemPaths{"bin"}{$Path} = 1;
            }
        }
        if($HSearch)
        {
            foreach my $Path (split(/:|;/, $ENV{"BEINCLUDES"}))
            {
                if(is_abs($Path)) {
                    $DefaultIncPaths{$Path} = 1;
                }
            }
        }
        if($LSearch)
        {
            foreach my $Path (split(/:|;/, $ENV{"BELIBRARIES"}), split(/:|;/, $ENV{"LIBRARY_PATH"}))
            {
                if(is_abs($Path)) {
                    $DefaultLibPaths{$Path} = 1;
                }
            }
        }
    }
    if($LSearch)
    { # using linker to get system paths
        if(my $LPaths = detect_lib_default_paths())
        { # unix-like
            foreach my $Name (keys(%{$LPaths}))
            {
                if($SystemRoot
                and $LPaths->{$Name}!~/\A\Q$SystemRoot\E\//)
                { # wrong ldconfig configuration
                  # check your <sysroot>/etc/ld.so.conf
                    next;
                }
                $DyLib_DefaultPath{$Name} = $LPaths->{$Name};
                $DefaultLibPaths{get_dirname($LPaths->{$Name})} = 1;
            }
        }
        foreach my $Path (keys(%DefaultLibPaths)) {
            $SystemPaths{"lib"}{$Path} = $DefaultLibPaths{$Path};
        }
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
        if(not $CrossGcc) {
            $GCC_PATH = get_CmdPath("gcc");
        }
        if(not $GCC_PATH) {
            exitStatus("Not_Found", "can't find GCC>=3.0 in PATH");
        }
        if(not $CheckObjectsOnly_Opt)
        {
            if(my $GCC_Ver = get_dumpversion($GCC_PATH))
            {
                my $GccTarget = get_dumpmachine($GCC_PATH);
                printMsg("INFO", "Using GCC $GCC_Ver ($GccTarget)");
                if($GccTarget=~/symbian/)
                {
                    $OStarget = "symbian";
                    $LIB_EXT = $OS_LibExt{$LIB_TYPE}{$OStarget};
                }
            }
            else {
                exitStatus("Error", "something is going wrong with the GCC compiler");
            }
        }
        if(not $NoStdInc)
        { # do NOT search in GCC standard paths
            my %DPaths = detect_inc_default_paths();
            %DefaultCppPaths = %{$DPaths{"Cpp"}};
            %DefaultGccPaths = %{$DPaths{"Gcc"}};
            %DefaultIncPaths = %{$DPaths{"Inc"}};
            foreach my $Path (keys(%DefaultIncPaths)) {
                $SystemPaths{"include"}{$Path} = $DefaultIncPaths{$Path};
            }
        }
    }
    if($HSearch)
    { # user include paths
        my $IncPath = "/usr/include";
        if($SystemRoot) {
            $IncPath = $SystemRoot.$IncPath;
        }
        if(-d $IncPath) {
            $UserIncPath{$IncPath}=1;
        }
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
    my $V = `$Cmd -dumpversion 2>$TMP_DIR/null`;
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
    my $Machine = `$Cmd -dumpmachine 2>$TMP_DIR/null`;
    chomp($Machine);
    return ($Cache{"get_dumpmachine"}{$Cmd} = $Machine);
}

sub check_command($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    my @Options = (
        "--version",
        "-help"
    );
    foreach my $Opt (@Options)
    {
        my $Info = `$Cmd $Opt 2>$TMP_DIR/null`;
        if($Info) {
            return 1;
        }
    }
    return 0;
}

sub check_gcc_version($$)
{
    my ($Cmd, $Req_V) = @_;
    return 0 if(not $Cmd or not $Req_V);
    my $Gcc_V = get_dumpversion($Cmd);
    $Gcc_V=~s/(-|_)[a-z_]+.*\Z//; # remove suffix (like "-haiku-100818")
    if(cmpVersions($Gcc_V, $Req_V)>=0) {
        return $Cmd;
    }
    return "";
}

sub get_depth($)
{
    if(defined $Cache{"get_depth"}{$_[0]}) {
        return $Cache{"get_depth"}{$_[0]}
    }
    return ($Cache{"get_depth"}{$_[0]} = ($_[0]=~tr![\/\\]|\:\:!!));
}

sub find_gcc_cxx_headers($)
{
    my $LibVersion = $_[0];
    return if($Cache{"find_gcc_cxx_headers"});# this function should be called once
    # detecting system header paths
    foreach my $Path (sort {get_depth($b) <=> get_depth($a)} keys(%DefaultGccPaths))
    {
        foreach my $HeaderPath (sort {get_depth($a) <=> get_depth($b)} cmd_find($Path,"f","",""))
        {
            my $FileName = get_filename($HeaderPath);
            next if($DefaultGccHeader{$FileName});
            $DefaultGccHeader{$FileName} = $HeaderPath;
        }
    }
    if($COMMON_LANGUAGE{$LibVersion} eq "C++" and not $STDCXX_TESTING)
    {
        foreach my $CppDir (sort {get_depth($b)<=>get_depth($a)} keys(%DefaultCppPaths))
        {
            my @AllCppHeaders = cmd_find($CppDir,"f","","");
            foreach my $Path (sort {get_depth($a)<=>get_depth($b)} @AllCppHeaders)
            {
                my $FileName = get_filename($Path);
                next if($DefaultCppHeader{$FileName});
                $DefaultCppHeader{$FileName} = $Path;
            }
        }
    }
    $Cache{"find_gcc_cxx_headers"} = 1;
}

sub parse_libname($$$)
{
    my ($Name, $Type, $Target) = @_;
    if(not $Name) {
        return "";
    }
    if($Target eq "symbian") {
        return parse_libname_symbian($Name, $Type);
    }
    elsif($Target eq "windows") {
        return parse_libname_windows($Name, $Type);
    }
    my $Ext = getLIB_EXT($Target);
    if($Name=~/((((lib|).+?)([\-\_][\d\-\.\_]+|))\.$Ext)(\.(.+)|)\Z/)
    { # libSDL-1.2.so.0.7.1
      # libwbxml2.so.0.0.18
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
            if($7 ne "")
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

sub getPrefix($)
{
    my $Str = $_[0];
    if($Str=~/\A(Get|get|Set|set)([A-Z]|_)/)
    { # GetError
        return "";
    }
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
    elsif($Str=~/\A([_]*[a-z0-9]{2,}_)[a-z]+/i)
    { # alarm_event_add: alarm_
        return $1;
    }
    elsif($Str=~/\A(([a-z])\2{1,})/i)
    { # ffopen
        return $1;
    }
    else {
        return "";
    }
}

sub problem_title($)
{
    if($_[0]==1)  {
        return "1 problem";
    }
    else  {
        return $_[0]." problems";
    }
}

sub warning_title($)
{
    if($_[0]==1)  {
        return "1 warning";
    }
    else  {
        return $_[0]." warnings";
    }
}

sub createSymbolsList($$$$$)
{
    my ($DPath, $SaveTo, $LName, $LVersion, $ArchName) = @_;
    read_ABI_Dump(1, $DPath);
    if(not $CheckObjectsOnly) {
        prepareSymbols(1);
    }
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
                $NS_Symbol{get_IntNameSpace($Symbol, 1)}{$Symbol} = 1;
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
                        $Signature=~s/(\W|\A)\Q$NameSpace\E\:\:(\w)/$1$2/g;
                    }
                    if($Symbol=~/\A(_Z|\?)/)
                    {
                        if($Signature) {
                            $SubReport = insertIDs($ContentSpanStart.highLight_Signature_Italic_Color($Signature).$ContentSpanEnd."<br/>\n".$ContentDivStart."<span class='mangled'>[symbol: <b>$Symbol</b>]</span><br/><br/>".$ContentDivEnd."\n");
                        }# report_added
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
    # Clear Info
    (%TypeInfo, %SymbolInfo, %Library_Symbol,
    %DepSymbols, %SymVer, %Tid_TDid, %SkipTypes,
    %SkipSymbols, %NestedNameSpaces, %ClassMethods,
    %AllocableClass, %ClassToId, %CompleteSignature,
    %SkipNameSpaces, %Symbol_Library) = ();
    ($Content_Counter, $ContentID) = (0, 0);
    # Print Report
    my $CssStyles = readModule("Styles", "SymbolsList.css");
    my $JScripts = readModule("Scripts", "Sections.js");
    $SYMBOLS_LIST = "<a name='Top'></a>".$SYMBOLS_LIST.$TOP_REF."<br/>\n";
    my $Title = "$LName: public symbols";
    my $Keywords = "$LName, API, symbols";
    my $Description = "List of symbols in $LName ($LVersion) on ".showArch($ArchName);
    $SYMBOLS_LIST = composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts)."
    <body><div>\n$SYMBOLS_LIST</div>
    <br/><br/><hr/>\n".getReportFooter($LName)."
    <div style='height:999px;'></div></body></html>";
    writeFile($SaveTo, $SYMBOLS_LIST);
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

sub is_target_lib($)
{
    my $LName = $_[0];
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

sub is_target_header($)
{ # --header, --headers-list
    if(keys(%{$TargetHeaders{1}})
    or keys(%{$TargetHeaders{2}}))
    {
        if(not $TargetHeaders{1}{$_[0]}
        and not $TargetHeaders{2}{$_[0]})
        {
            return 0;
        }
    }
    return 1;
}

sub checkVersionNum($$)
{
    my ($LibVersion, $Path) = @_;
    if(my $VerNum = $TargetVersion{$LibVersion}) {
        return $VerNum;
    }
    my $UsedAltDescr = 0;
    foreach my $Part (split(/\s*,\s*/, $Path))
    { # try to get version string from file path
        next if($Part=~/\.xml\Z/i);
        next if(isDump($Part));
        if(parse_libname($Part, "version", $OStarget)
        or is_header($Part, 2, $LibVersion) or -d $Part)
        {
            $UsedAltDescr = 1;
            if(my $VerNum = readStringVersion($Part))
            {
                $TargetVersion{$LibVersion} = $VerNum;
                if($DumpAPI) {
                    printMsg("WARNING", "setting version number to $VerNum (use -vnum <num> option to change it)");
                }
                else {
                    printMsg("WARNING", "setting ".($LibVersion==1?"1st":"2nd")." version number to \"$VerNum\" (use -v$LibVersion <num> option to change it)");
                }
                return $TargetVersion{$LibVersion};
            }
        }
    }
    if($UsedAltDescr)
    {
        if($DumpAPI) {
            exitStatus("Error", "version number is not set (use -vnum <num> option)");
        }
        else {
            exitStatus("Error", ($LibVersion==1?"1st":"2nd")." version number is not set (use -v$LibVersion <num> option)");
        }
    }
}

sub readStringVersion($)
{
    my $Str = $_[0];
    return "" if(not $Str);
    $Str=~s/\Q$TargetLibraryName\E//g;
    if($Str=~/(\/|\\|\w|\A)[\-\_]*(\d+[\d\.\-]+\d+|\d+)/)
    { # .../libssh-0.4.0/...
        return $2;
    }
    elsif(my $V = parse_libname($Str, "version", $OStarget)) {
        return $V;
    }
    return "";
}

sub readLibs($)
{
    my $LibVersion = $_[0];
    if($OStarget eq "windows")
    { # dumpbin.exe will crash
        # without VS Environment
        check_win32_env();
    }
    getSymbols($LibVersion);
    translateSymbols(keys(%{$Symbol_Library{$LibVersion}}), $LibVersion);
    translateSymbols(keys(%{$DepSymbols{$LibVersion}}), $LibVersion);
}

sub dump_sorting($)
{
    my $hash = $_[0];
    return [] if(not $hash or not keys(%{$hash}));
    if((keys(%{$hash}))[0]=~/\A\d+\Z/) {
        return [sort {int($a) <=> int($b)} keys(%{$hash})];
    }
    else {
        return [sort {$a cmp $b} keys(%{$hash})];
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
        { # --join-report, --binary or --source
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
        { # --join-report
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

sub create_ABI_Dump()
{
    if(not -e $DumpAPI) {
        exitStatus("Access_Error", "can't access \'$DumpAPI\'");
    }
    # check the archive utilities
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
    my @DParts = split(/\s*,\s*/, $DumpAPI);
    foreach my $Part (@DParts)
    {
        if(not -e $Part) {
            exitStatus("Access_Error", "can't access \'$Part\'");
        }
    }
    checkVersionNum(1, $DumpAPI);
    foreach my $Part (@DParts)
    {
        if(isDump($Part)) {
            read_ABI_Dump(1, $Part);
        }
        else {
            readDescriptor(1, createDescriptor(1, $Part));
        }
    }
    initLogging(1);
    detect_default_paths("inc|lib|bin|gcc"); # complete analysis
    if(not $CheckHeadersOnly) {
        readLibs(1);
    }
    if($CheckHeadersOnly) {
        setLanguage(1, "C++");
    }
    if(not $CheckObjectsOnly) {
        searchForHeaders(1);
    }
    $WORD_SIZE{1} = detectWordSize();
    if($Descriptor{1}{"Headers"}
    and not $Descriptor{1}{"Dump"}) {
        readHeaders(1);
    }
    if($ExtendedCheck)
    { # --ext option
        addExtension(1);
    }
    formatDump(1);
    if(not keys(%{$SymbolInfo{1}}))
    { # check if created dump is valid
        if(not $ExtendedCheck and not $CheckObjectsOnly)
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
    foreach my $HPath (keys(%{$Registered_Headers{1}}))
    { # headers info stored without paths in the dump
        $HeadersInfo{$Registered_Headers{1}{$HPath}{"Identity"}} = $Registered_Headers{1}{$HPath}{"Pos"};
    }
    printMsg("INFO", "creating library ABI dump ...");
    my %LibraryABI = (
        "TypeInfo" => $TypeInfo{1},
        "SymbolInfo" => $SymbolInfo{1},
        "Symbols" => $Library_Symbol{1},
        "DepSymbols" => $DepSymbols{1},
        "SymbolVersion" => $SymVer{1},
        "LibraryVersion" => $Descriptor{1}{"Version"},
        "LibraryName" => $TargetLibraryName,
        "Language" => $COMMON_LANGUAGE{1},
        "Tid_TDid" => $Tid_TDid{1},
        "SkipTypes" => $SkipTypes{1},
        "SkipSymbols" => $SkipSymbols{1},
        "SkipNameSpaces" => $SkipNameSpaces{1},
        "SkipHeaders" => $SkipHeadersList{1},
        "TargetHeaders" => $TargetHeaders{1},
        "Headers" => \%HeadersInfo,
        "Constants" => $Constants{1},
        "NameSpaces" => $NestedNameSpaces{1},
        "Target" => $OStarget,
        "Arch" => getArch(1),
        "WordSize" => $WORD_SIZE{1},
        "GccVersion" => get_dumpversion($GCC_PATH),
        "ABI_DUMP_VERSION" => $ABI_DUMP_VERSION,
        "ABI_COMPLIANCE_CHECKER_VERSION" => $TOOL_VERSION
    );
    if($ExtendedCheck)
    { # --ext option
        $LibraryABI{"Mode"} = "Extended";
    }
    if($BinaryOnly)
    { # --binary
        $LibraryABI{"BinOnly"} = 1;
    }
    else
    { # default
        $LibraryABI{"SrcBin"} = 1;
    }
    if($StdOut)
    { # --stdout option
        print STDOUT Dumper(\%LibraryABI);
        printMsg("INFO", "ABI dump has been generated to stdout");
        return;
    }
    else
    { # write to gzipped file
        my $DumpPath = "abi_dumps/$TargetLibraryName/".$TargetLibraryName."_".$Descriptor{1}{"Version"}.".abi.".$AR_EXT;
        if($OutputDumpPath)
        { # user defined path
            $DumpPath = $OutputDumpPath;
        }
        if(not $DumpPath=~s/\Q.$AR_EXT\E\Z//g) {
            exitStatus("Error", "the dump path (-dump-path option) should be the path to a *.$AR_EXT file");
        }
        my ($DDir, $DName) = separate_path($DumpPath);
        my $DPath = $TMP_DIR."/".$DName;
        mkpath($DDir);
        writeFile($DPath, Dumper(\%LibraryABI));
        if(not -s $DPath) {
            exitStatus("Error", "can't create ABI dump because something is going wrong with the Data::Dumper module");
        }
        my $Pkg = createArchive($DPath, $DDir);
        printMsg("INFO", "library ABI has been dumped to:\n  $Pkg");
        printMsg("INFO", "you can transfer this dump everywhere and use instead of the ".$Descriptor{1}{"Version"}." version descriptor");
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
        my $FilePath1 = unpackDump($Descriptor{1}{"Path"});
        my $FilePath2 = unpackDump($Descriptor{2}{"Path"});
        if($FilePath1 and $FilePath2)
        {
            my $Content = readFile($FilePath1);
            if($Content eq readFile($FilePath2))
            {
                # read a number of headers, libs, symbols and types
                my $ABIdump = eval($Content);
                if(not $ABIdump) {
                    exitStatus("Error", "internal error");
                }
                if(not $ABIdump->{"TypeInfo"})
                { # support for old dumps
                    $ABIdump->{"TypeInfo"} = $ABIdump->{"TypeDescr"};
                }
                if(not $ABIdump->{"SymbolInfo"})
                { # support for old dumps
                    $ABIdump->{"SymbolInfo"} = $ABIdump->{"FuncDescr"};
                }
                read_Headers_DumpInfo($ABIdump, 1);
                read_Libs_DumpInfo($ABIdump, 1);
                read_Machine_DumpInfo($ABIdump, 1);
                read_Machine_DumpInfo($ABIdump, 2);
                
                %{$CheckedTypes{"Binary"}} = %{$ABIdump->{"TypeInfo"}};
                %{$CheckedTypes{"Source"}} = %{$ABIdump->{"TypeInfo"}};
                
                %{$CheckedSymbols{"Binary"}} = %{$ABIdump->{"SymbolInfo"}};
                %{$CheckedSymbols{"Source"}} = %{$ABIdump->{"SymbolInfo"}};
                
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
    resetLogging($LibVersion);
    if($Debug)
    { # debug directory
        $DEBUG_PATH{$LibVersion} = "debug/$TargetLibraryName/".$Descriptor{$LibVersion}{"Version"};
        rmtree($DEBUG_PATH{$LibVersion});
    }
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
    if(get_filename($_[0])=~/\A(.+)\.abi(\Q.tar.gz\E|\Q.zip\E|)\Z/)
    { # returns a name of package
        return $1;
    }
    return 0;
}

sub compareInit()
{
    # read input XML descriptors or ABI dumps
    if(not $Descriptor{1}{"Path"}) {
        exitStatus("Error", "-d1 option is not specified");
    }
    my @DParts1 = split(/\s*,\s*/, $Descriptor{1}{"Path"});
    foreach my $Part (@DParts1)
    {
        if(not -e $Part) {
            exitStatus("Access_Error", "can't access \'$Part\'");
        }
    }
    if(not $Descriptor{2}{"Path"}) {
        exitStatus("Error", "-d2 option is not specified");
    }
    my @DParts2 = split(/\s*,\s*/, $Descriptor{2}{"Path"});
    foreach my $Part (@DParts2)
    {
        if(not -e $Part) {
            exitStatus("Access_Error", "can't access \'$Part\'");
        }
    }
    detect_default_paths("bin"); # to extract dumps
    if($#DParts1==0 and $#DParts2==0
    and isDump($Descriptor{1}{"Path"})
    and isDump($Descriptor{2}{"Path"}))
    { # optimization: equal ABI dumps
        quickEmptyReports();
    }
    checkVersionNum(1, $Descriptor{1}{"Path"});
    checkVersionNum(2, $Descriptor{2}{"Path"});
    printMsg("INFO", "preparation, please wait ...");
    foreach my $Part (@DParts1)
    {
        if(isDump($Part)) {
            read_ABI_Dump(1, $Part);
        }
        else {
            readDescriptor(1, createDescriptor(1, $Part));
        }
    }
    foreach my $Part (@DParts2)
    {
        if(isDump($Part)) {
            read_ABI_Dump(2, $Part);
        }
        else {
            readDescriptor(2, createDescriptor(2, $Part));
        }
    }
    initLogging(1);
    initLogging(2);
    # check consistency
    if(not $Descriptor{1}{"Headers"}
    and not $Descriptor{1}{"Libs"}) {
        exitStatus("Error", "descriptor d1 does not contain both header files and libraries info");
    }
    if(not $Descriptor{2}{"Headers"}
    and not $Descriptor{2}{"Libs"}) {
        exitStatus("Error", "descriptor d2 does not contain both header files and libraries info");
    }
    if($Descriptor{1}{"Headers"} and not $Descriptor{1}{"Libs"}
    and not $Descriptor{2}{"Headers"} and $Descriptor{2}{"Libs"}) {
        exitStatus("Error", "can't compare headers with $SLIB_TYPE libraries");
    }
    elsif(not $Descriptor{1}{"Headers"} and $Descriptor{1}{"Libs"}
    and $Descriptor{2}{"Headers"} and not $Descriptor{2}{"Libs"}) {
        exitStatus("Error", "can't compare $SLIB_TYPE libraries with headers");
    }
    if(not $Descriptor{1}{"Headers"}) {
        if($CheckHeadersOnly_Opt) {
            exitStatus("Error", "can't find header files info in descriptor d1");
        }
    }
    if(not $Descriptor{2}{"Headers"}) {
        if($CheckHeadersOnly_Opt) {
            exitStatus("Error", "can't find header files info in descriptor d2");
        }
    }
    if(not $Descriptor{1}{"Headers"}
    or not $Descriptor{2}{"Headers"}) {
        if(not $CheckObjectsOnly_Opt) {
            printMsg("WARNING", "comparing $SLIB_TYPE libraries only");
            $CheckObjectsOnly = 1;
        }
    }
    if(not $Descriptor{1}{"Libs"}) {
        if($CheckObjectsOnly_Opt) {
            exitStatus("Error", "can't find $SLIB_TYPE libraries info in descriptor d1");
        }
    }
    if(not $Descriptor{2}{"Libs"}) {
        if($CheckObjectsOnly_Opt) {
            exitStatus("Error", "can't find $SLIB_TYPE libraries info in descriptor d2");
        }
    }
    if(not $Descriptor{1}{"Libs"}
    or not $Descriptor{2}{"Libs"})
    { # comparing standalone header files
      # comparing ABI dumps created with --headers-only
        if(not $CheckHeadersOnly_Opt)
        {
            printMsg("WARNING", "checking headers only");
            $CheckHeadersOnly = 1;
        }
    }
    if($UseDumps)
    { # --use-dumps
      # parallel processing
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
            if($Debug) {
                @PARAMS = (@PARAMS, "-debug");
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
            system("perl", $0, @PARAMS);
            if($?) {
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
            if($Debug) {
                @PARAMS = (@PARAMS, "-debug");
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
            system("perl", $0, @PARAMS);
            if($?) {
                exit(1);
            }
            else {
                exit(0);
            }
        }
        waitpid($pid, 0);
        my @CMP_PARAMS = ("-l", $TargetLibraryName);
        @CMP_PARAMS = (@CMP_PARAMS, "-d1", "abi_dumps/$TargetLibraryName/".$TargetLibraryName."_".$Descriptor{1}{"Version"}.".abi.$AR_EXT");
        @CMP_PARAMS = (@CMP_PARAMS, "-d2", "abi_dumps/$TargetLibraryName/".$TargetLibraryName."_".$Descriptor{2}{"Version"}.".abi.$AR_EXT");
        if($TargetLibraryFName ne $TargetLibraryName) {
            @CMP_PARAMS = (@CMP_PARAMS, "-l-full", $TargetLibraryFName);
        }
        if($ShowRetVal) {
            @CMP_PARAMS = (@CMP_PARAMS, "-show-retval");
        }
        if($CrossGcc) {
            @CMP_PARAMS = (@CMP_PARAMS, "-cross-gcc", $CrossGcc);
        }
        if($Quiet)
        {
            @CMP_PARAMS = (@CMP_PARAMS, "-quiet");
            @CMP_PARAMS = (@CMP_PARAMS, "-logging-mode", "a");
        }
        elsif($LogMode and $LogMode ne "w")
        { # "w" is default
            @CMP_PARAMS = (@CMP_PARAMS, "-logging-mode", $LogMode);
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
        if(not $CheckObjectsOnly) {
            searchForHeaders(1);
        }
        $WORD_SIZE{1} = detectWordSize();
    }
    if(not $Descriptor{2}{"Dump"})
    {
        if(not $CheckHeadersOnly) {
            readLibs(2);
        }
        if($CheckHeadersOnly) {
            setLanguage(2, "C++");
        }
        if(not $CheckObjectsOnly) {
            searchForHeaders(2);
        }
        $WORD_SIZE{2} = detectWordSize();
    }
    if($WORD_SIZE{1} ne $WORD_SIZE{2})
    { # support for old ABI dumps
      # try to synch different WORD sizes
        if(not checkDumpVersion(1, "2.1"))
        {
            $WORD_SIZE{1} = $WORD_SIZE{2};
            printMsg("WARNING", "set WORD size to ".$WORD_SIZE{2}." bytes");
        }
        elsif(not checkDumpVersion(2, "2.1"))
        {
            $WORD_SIZE{2} = $WORD_SIZE{1};
            printMsg("WARNING", "set WORD size to ".$WORD_SIZE{1}." bytes");
        }
    }
    elsif(not $WORD_SIZE{1}
    and not $WORD_SIZE{2})
    { # support for old ABI dumps
        $WORD_SIZE{1} = 4;
        $WORD_SIZE{2} = 4;
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
    # started to process input data
    if(not $CheckObjectsOnly)
    {
        if($Descriptor{1}{"Headers"}
        and not $Descriptor{1}{"Dump"}) {
            readHeaders(1);
        }
        if($Descriptor{2}{"Headers"}
        and not $Descriptor{2}{"Dump"}) {
            readHeaders(2);
        }
    }
    prepareSymbols(1);
    prepareSymbols(2);
    %SymbolInfo = ();
}

sub compareAPIs($)
{
    my $Level = $_[0];
    readRules($Level);
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
    if(not $CheckObjectsOnly)
    {
        mergeSignatures($Level);
        if(keys(%{$CheckedSymbols{$Level}})) {
            mergeConstants($Level);
        }
    }
    if($CheckHeadersOnly
    or $Level eq "Source")
    { # added/removed in headers
        mergeHeaders($Level);
    }
    else
    { # added/removed in libs
        mergeLibs($Level);
        if($CheckImpl
        and $Level eq "Binary") {
            mergeImpl();
        }
    }
}

sub optimize_set(@)
{
    my %Included = ();
    foreach my $Path (@_)
    {
        detect_header_includes($Path, 1);
        foreach my $Include (keys(%{$Header_Includes{1}{$Path}})) {
            $Included{get_filename($Include)}{$Include}=1;
        }
    }
    my @Res = ();
    foreach my $Path (@_)
    {
        my $Add = 1;
        foreach my $Inc (keys(%{$Included{get_filename($Path)}}))
        {
            if($Path=~/\/\Q$Inc\E\Z/)
            {
                $Add = 0;
                last;
            }
        }
        if($Add) {
            push(@Res, $Path);
        }
    }
    return @Res;
}

sub writeOpts()
{
    my %Opts = (
    "OStarget"=>$OStarget,
    "Debug"=>$Debug,
    "Quiet"=>$Quiet,
    "LogMode"=>$LogMode,
    "CheckHeadersOnly"=>$CheckHeadersOnly,
    
    "SystemRoot"=>$SystemRoot,
    "MODULES_DIR"=>$MODULES_DIR,
    "GCC_PATH"=>$GCC_PATH,
    "TargetSysInfo"=>$TargetSysInfo,
    "CrossPrefix"=>$CrossPrefix,
    "TargetLibraryName"=>$TargetLibraryName,
    "CrossGcc"=>$CrossGcc,
    "UseStaticLibs"=>$UseStaticLibs,
    "NoStdInc"=>$NoStdInc
    );
    return \%Opts;
}

sub get_CoreError($)
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
    if($BinaryOnly and $SourceOnly)
    { # both --binary and --source
      # is the default mode
        $DoubleReport = 1;
        $JoinReport = 0;
        $BinaryOnly = 0;
        $SourceOnly = 0;
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
    }
    if($ReportFormat)
    { # validate
        $ReportFormat = lc($ReportFormat);
        if($ReportFormat!~/\A(xml|html|htm)\Z/) {
            exitStatus("Error", "unknown format \'$ReportFormat\'");
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
    if($Quiet and $LogMode!~/a|n/)
    { # --quiet log
        if(-f $COMMON_LOG_PATH) {
            unlink($COMMON_LOG_PATH);
        }
    }
    if($TestTool and $UseDumps)
    { # --test && --use-dumps == --test-dump
        $TestDump = 1;
    }
    if($Help) {
        HELP_MESSAGE();
        exit(0);
    }
    if($InfoMsg) {
        INFO_MESSAGE();
        exit(0);
    }
    if($ShowVersion) {
        printMsg("INFO", "ABI Compliance Checker (ACC) $TOOL_VERSION\nCopyright (C) 2012 ROSA Laboratory\nLicense: LGPL or GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion) {
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
    # FIXME: can't pass \&dump_sorting - cause a segfault sometimes
    # $Data::Dumper::Sortkeys = \&dump_sorting;
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
            $TargetHeaders{1}{$Header} = 1;
            $TargetHeaders{2}{$Header} = 1;
        }
    }
    if($TargetHeader)
    { # --header
        $TargetHeaders{1}{$TargetHeader} = 1;
        $TargetHeaders{2}{$TargetHeader} = 1;
    }
    if($TestTool
    or $TestDump)
    { # --test, --test-dump
        detect_default_paths("bin|gcc"); # to compile libs
        loadModule("RegTests");
        testTool($TestDump, $Debug, $Quiet, $ExtendedCheck,
        $LogMode, $ReportFormat, $LIB_EXT, $GCC_PATH, $Browse);
        exit(0);
    }
    if($DumpSystem)
    { # --dump-system
        loadModule("SysCheck");
        if($DumpSystem=~/\.xml\Z/)
        { # system XML descriptor
            if(not -f $DumpSystem) {
                exitStatus("Access_Error", "can't access file \'$DumpSystem\'");
            }
            my $Ret = readSystemDescriptor(readFile($DumpSystem));
            foreach (@{$Ret->{"Tools"}}) {
                $SystemPaths{"bin"}{$_} = 1;
                $TargetTools{$_}=1;
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
        dumpSystem(writeOpts());
        exit(0);
    }
    if($CmpSystems)
    { # --cmp-systems
        detect_default_paths("bin"); # to extract dumps
        loadModule("SysCheck");
        cmpSystems($Descriptor{1}{"Path"}, $Descriptor{2}{"Path"}, writeOpts());
        exit(0);
    }
    if($GenerateTemplate) {
        generateTemplate();
        exit(0);
    }
    if(not $TargetLibraryName) {
        exitStatus("Error", "library name is not selected (option -l <name>)");
    }
    else
    { # validate library name
        if($TargetLibraryName=~/[\*\/\\]/) {
            exitStatus("Error", "\"\\\", \"\/\" and \"*\" symbols are not allowed in the library name");
        }
    }
    if(not $TargetLibraryFName) {
        $TargetLibraryFName = $TargetLibraryName;
    }
    if($CheckHeadersOnly_Opt and $CheckObjectsOnly_Opt) {
        exitStatus("Error", "you can't specify both -headers-only and -objects-only options at the same time");
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
                if($Line=~/;(\d+);/) {
                    while($Line=~s/(\d+);(\w+)//) {
                        $AddIntParams{$Interface}{$1}=$2;
                    }
                }
                else {
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
        foreach my $Interface (getSymbols_App($AppPath)) {
            $SymbolsList_App{$Interface} = 1;
        }
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
