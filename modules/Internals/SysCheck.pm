###########################################################################
# Module for ABI Compliance Checker to compare Operating Systems
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
use File::Temp qw(tempdir);
use Cwd qw(abs_path cwd);

my ($Debug, $Quiet, $LogMode, $CheckHeadersOnly, $SystemRoot, $MODULES_DIR, $GCC_PATH,
$CrossPrefix, $TargetSysInfo, $TargetLibraryName, $CrossGcc, $UseStaticLibs, $NoStdInc, $OStarget);
my $OSgroup = get_OSgroup();
my $TMP_DIR = tempdir(CLEANUP=>1);
my $ORIG_DIR = cwd();
my $LIB_EXT = getLIB_EXT($OSgroup);

my %SysDescriptor;
my %Cache;

sub cmpSystems($$$)
{ # -cmp-systems option handler
  # should be used with -d1 and -d2 options
    my ($SPath1, $SPath2, $Opts) = @_;
    readOpts($Opts);
    if(not $SPath1) {
        exitStatus("Error", "the option -d1 should be specified");
    }
    elsif(not -d $SPath1) {
        exitStatus("Access_Error", "can't access directory \'".$SPath1."\'");
    }
    elsif(not -d $SPath1."/abi_dumps") {
        exitStatus("Access_Error", "can't access directory \'".$SPath1."/abi_dumps\'");
    }
    if(not $SPath2) {
        exitStatus("Error", "the option -d2 should be specified");
    }
    elsif(not -d $SPath2) {
        exitStatus("Access_Error", "can't access directory \'".$SPath2."\'");
    }
    elsif(not -d $SPath2."/abi_dumps") {
        exitStatus("Access_Error", "can't access directory \'".$SPath2."/abi_dumps\'");
    }
    # sys_dumps/<System>/<Arch>/...
    my $SystemName1 = get_filename(get_dirname($SPath1));
    my $SystemName2 = get_filename(get_dirname($SPath2));
    # sys_dumps/<System>/<Arch>/...
    my $ArchName = get_filename($SPath1);
    if($ArchName ne get_filename($SPath2)) {
        exitStatus("Error", "can't compare systems of different CPU architecture");
    }
    if(my $OStarget_Dump = readFile($SPath1."/target.txt"))
    { # change target
        $OStarget = $OStarget_Dump;
        $LIB_EXT = getLIB_EXT($OStarget);
    }
    my $GroupByHeaders = 0;
    if(my $Mode = readFile($SPath1."/mode.txt"))
    { # change mode
        if($Mode eq "headers-only")
        { # -headers-only mode
            $CheckHeadersOnly = 1;
            $GroupByHeaders = 1;
        }
        if($Mode eq "group-by-headers") {
            $GroupByHeaders = 1;
        }
    }
    my $SYS_REPORT_PATH = "sys_compat_reports/".$SystemName1."_to_".$SystemName2."/$ArchName";
    rmtree($SYS_REPORT_PATH);
    my (%LibSoname1, %LibSoname2) = ();
    foreach (split(/\n/, readFile($SPath1."/sonames.txt"))) {
        if(my ($LFName, $Soname) = split(/;/, $_))
        {
            if($OStarget eq "symbian") {
                $Soname=~s/\{.+\}//;
            }
            $LibSoname1{$LFName} = $Soname;
        }
    }
    foreach (split(/\n/, readFile($SPath2."/sonames.txt"))) {
        if(my ($LFName, $Soname) = split(/;/, $_))
        {
            if($OStarget eq "symbian") {
                $Soname=~s/\{.+\}//;
            }
            $LibSoname2{$LFName} = $Soname;
        }
    }
    my (%LibV1, %LibV2) = ();
    foreach (split(/\n/, readFile($SPath1."/versions.txt"))) {
        if(my ($LFName, $V) = split(/;/, $_)) {
            $LibV1{$LFName} = $V;
        }
    }
    foreach (split(/\n/, readFile($SPath2."/versions.txt"))) {
        if(my ($LFName, $V) = split(/;/, $_)) {
            $LibV2{$LFName} = $V;
        }
    }
    my @Dumps1 = cmd_find($SPath1."/abi_dumps","f","*.tar.gz",1);
    if(not @Dumps1)
    { # zip-based dump
        @Dumps1 = cmd_find($SPath1."/abi_dumps","f","*.zip",1);
    }
    my @Dumps2 = cmd_find($SPath2."/abi_dumps","f","*.tar.gz",1);
    if(not @Dumps2)
    { # zip-based dump
        @Dumps2 = cmd_find($SPath2."/abi_dumps","f","*.zip",1);
    }
    my (%LibVers1, %LibVers2) = ();
    foreach my $DPath (@Dumps1)
    {
        if(my $Name = isDump($DPath))
        {
            my ($Soname, $V) = ($LibSoname1{$Name}, $LibV1{$Name});
            if(not $V) {
                $V = parse_libname($Name, "version", $OStarget);
            }
            if($GroupByHeaders) {
                $Soname = $Name;
            }
            $LibVers1{$Soname}{$V} = $DPath;
        }
    }
    foreach my $DPath (@Dumps2)
    {
        if(my $Name = isDump($DPath))
        {
            my ($Soname, $V) = ($LibSoname2{$Name}, $LibV2{$Name});
            if(not $V) {
                $V = parse_libname($Name, "version", $OStarget);
            }
            if($GroupByHeaders) {
                $Soname = $Name;
            }
            $LibVers2{$Soname}{$V} = $DPath;
        }
    }
    my (%Added, %Removed) = ();
    my (%ChangedSoname, %TestResults, %SONAME_Changed);
    if(not $GroupByHeaders)
    {
        my %ChangedSoname_Safe = ();
        foreach my $LName (sort keys(%LibSoname2))
        { # libcurl.so.3 -> libcurl.so.4 (search for SONAME by the file name)
          # OS #1 => OS #2
            if(defined $LibVers2{$LName})
            { # already registered
                next;
            }
            my $Soname = $LibSoname2{$LName};
            if(defined $LibVers2{$Soname}
            and defined $LibVers1{$LName})
            {
                $LibVers2{$LName} = $LibVers2{$Soname};
                $ChangedSoname_Safe{$Soname}=$LName;
            }
        }
        foreach my $LName (sort keys(%LibSoname1))
        { # libcurl.so.3 -> libcurl.so.4 (search for SONAME by the file name)
          # OS #1 <= OS #2
            if(defined $LibVers1{$LName})
            { # already registered
                next;
            }
            my $Soname = $LibSoname1{$LName};
            if(defined $LibVers1{$Soname}
            and defined $LibVers2{$LName}) {
                $LibVers1{$LName} = $LibVers1{$Soname};
            }
        }
        my (%AddedShort, %RemovedShort) = ();
        if(not $GroupByHeaders) {
            printMsg("INFO", "Checking added/removed libs");
        }
        foreach my $LName (sort {lc($a) cmp lc($b)} keys(%LibVers1))
        { # removed libs
            if(not is_target_lib($LName)) {
                next;
            }
            if(not defined $LibVers1{$LName}) {
                next;
            }
            my @Versions1 = keys(%{$LibVers1{$LName}});
            if($#Versions1>=1)
            { # should be only one version
                next;
            }
            if(not defined $LibVers2{$LName}
            or not keys(%{$LibVers2{$LName}}))
            { # removed library
                if(not $LibSoname2{$LName})
                {
                    $RemovedShort{parse_libname($LName, "name+ext", $OStarget)}{$LName}=1;
                    $Removed{$LName}{"version"}=$Versions1[0];
                    my $ListPath = "info/$LName/symbols.html";
                    createSymbolsList($LibVers1{$LName}{$Versions1[0]},
                    $SYS_REPORT_PATH."/".$ListPath, $LName, $Versions1[0]."-".$SystemName1, $ArchName);
                    $Removed{$LName}{"list"} = $ListPath;
                }
            }
        }
        foreach my $LName (sort {lc($a) cmp lc($b)} keys(%LibVers2))
        { # added libs
            if(not is_target_lib($LName)) {
                next;
            }
            if(not defined $LibVers2{$LName}) {
                next;
            }
            my @Versions2 = keys(%{$LibVers2{$LName}});
            if($#Versions2>=1)
            { # should be only one version
                next;
            }
            if($ChangedSoname_Safe{$LName})
            { # changed soname but added the symbolic link for old-version library
                next;
            }
            if(not defined $LibVers1{$LName}
            or not keys(%{$LibVers1{$LName}}))
            { # added library
                if(not $LibSoname1{$LName})
                {
                    $AddedShort{parse_libname($LName, "name+ext", $OStarget)}{$LName}=1;
                    $Added{$LName}{"version"}=$Versions2[0];
                    my $ListPath = "info/$LName/symbols.html";
                    createSymbolsList($LibVers2{$LName}{$Versions2[0]},
                    $SYS_REPORT_PATH."/".$ListPath, $LName, $Versions2[0]."-".$SystemName2, $ArchName);
                    $Added{$LName}{"list"} = $ListPath;
                }
            }
        }
        foreach my $LSName (keys(%AddedShort))
        { # changed SONAME
            my @AddedSonames = keys(%{$AddedShort{$LSName}});
            next if(length(@AddedSonames)!=1);
            my @RemovedSonames = keys(%{$RemovedShort{$LSName}});
            next if(length(@RemovedSonames)!=1);
            $ChangedSoname{$AddedSonames[0]}=$RemovedSonames[0];
            $ChangedSoname{$RemovedSonames[0]}=$AddedSonames[0];
        }
    }
    foreach my $LName (sort {lc($a) cmp lc($b)} keys(%LibVers1))
    {
        if(not is_target_lib($LName)) {
            next;
        }
        my @Versions1 = keys(%{$LibVers1{$LName}});
        if(not @Versions1 or $#Versions1>=1)
        { # should be only one version
            next;
        }
        my $LV1 = $Versions1[0];
        my $DPath1 = $LibVers1{$LName}{$LV1};
        my @Versions2 = keys(%{$LibVers2{$LName}});
        if($#Versions2>=1)
        { # should be only one version
            next;
        }
        my ($LV2, $LName2, $DPath2) = ();
        if(@Versions2)
        {
            $LV2 = $Versions2[0];
            $DPath2 = $LibVers2{$LName}{$LV2};
        }
        elsif($LName2 = $ChangedSoname{$LName})
        { # changed SONAME
            @Versions2 = keys(%{$LibVers2{$LName2}});
            if(not @Versions2 or $#Versions2>=1) {
                next;
            }
            $LV2 = $Versions2[0];
            $DPath2 = $LibVers2{$LName2}{$LV2};
            $LName = parse_libname($LName, "name+ext", $OStarget);
            $SONAME_Changed{$LName} = 1;
        }
        else
        { # removed
            next;
        }
        my ($FV1, $FV2) = ($LV1."-".$SystemName1, $LV2."-".$SystemName2);
        my $ACC_compare = "perl $0 -binary -l $LName -d1 \"$DPath1\" -d2 \"$DPath2\"";
        my $LReportPath = "compat_reports/$LName/abi_compat_report.html";
        my $LReportPath_Full = $SYS_REPORT_PATH."/".$LReportPath;
        $ACC_compare .= " -report-path \"$LReportPath_Full\"";
        if($CheckHeadersOnly) {
            $ACC_compare .= " -headers-only";
        }
        if($GroupByHeaders) {
            $ACC_compare .= " -component header";
        }
        if($Quiet)
        { # quiet mode
            $ACC_compare .= " -quiet";
        }
        if($LogMode eq "n") {
            $ACC_compare .= " -logging-mode n";
        }
        elsif($Quiet) {
            $ACC_compare .= " -logging-mode a";
        }
        if($Debug)
        { # debug mode
            $ACC_compare .= " -debug";
            printMsg("INFO", "$ACC_compare");
        }
        printMsg("INFO_C", "Checking $LName: ");
        system($ACC_compare." 1>$TMP_DIR/null 2>$TMP_DIR/$LName.stderr");
        if(-s "$TMP_DIR/$LName.stderr")
        {
            my $ErrorLog = readFile("$TMP_DIR/$LName.stderr");
            chomp($ErrorLog);
            printMsg("INFO", "Failed ($ErrorLog)");
        }
        else
        {
            printMsg("INFO", "Ok");
            $TestResults{$LName} = readAttributes($LReportPath_Full, 0);
            $TestResults{$LName}{"v1"} = $LV1;
            $TestResults{$LName}{"v2"} = $LV2;
            $TestResults{$LName}{"path"} = $LReportPath;
        }
    }
    my $SONAME_Title = "SONAME";
    if($OStarget eq "windows") {
        $SONAME_Title = "DLL";
    }
    elsif($OStarget eq "symbian") {
        $SONAME_Title = "DSO";
    }
    if($GroupByHeaders)
    { # show the list of headers
        $SONAME_Title = "Header File";
    }
    my $SYS_REPORT = "<h1>Binary compatibility between <span style='color:Blue;'>$SystemName1</span> and <span style='color:Blue;'>$SystemName2</span> on <span style='color:Blue;'>".showArch($ArchName)."</span></h1>\n";
    
    # legend
    $SYS_REPORT .= "<table cellpadding='2'><tr>\n";
    $SYS_REPORT .= "<td class='new' width='85px' style='text-align:center'>Added</td>\n";
    $SYS_REPORT .= "<td class='passed' width='85px' style='text-align:center'>Compatible</td>\n";
    $SYS_REPORT .= "</tr><tr>\n";
    $SYS_REPORT .= "<td class='warning' style='text-align:center'>Warning</td>\n";
    $SYS_REPORT .= "<td class='failed' style='text-align:center'>Incompatible</td>\n";
    $SYS_REPORT .= "</tr></table>\n";
    
    $SYS_REPORT .= "<table class='wikitable'>
    <tr><th rowspan='2'>$SONAME_Title<sup>".(keys(%TestResults) + keys(%Added) + keys(%Removed) - keys(%SONAME_Changed))."</sup></th>";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<th colspan='2'>VERSION</th>";
    }
    $SYS_REPORT .= "<th rowspan='2'>Compatibility</th>
    <th rowspan='2'>Added<br/>Symbols</th>
    <th rowspan='2'>Removed<br/>Symbols</th>
    <th colspan='3' style='white-space:nowrap;'>API Changes / Compatibility Problems</th></tr>";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<tr><th>$SystemName1</th><th>$SystemName2</th>";
    }
    $SYS_REPORT .= "<th class='severity'>High</th><th class='severity'>Medium</th><th class='severity'>Low</th></tr>\n";
    my %RegisteredPairs = ();
    foreach my $LName (sort {lc($a) cmp lc($b)} (keys(%TestResults), keys(%Added), keys(%Removed)))
    {
        next if($SONAME_Changed{$LName});
        my $CompatReport = $TestResults{$LName}{"path"};
        my $Anchor = $LName;
        $Anchor=~s/\+/p/g;# anchors to libFLAC++ is libFLACpp
        $Anchor=~s/\~//g;# libqttracker.so.1~6
        $SYS_REPORT .= "<tr>\n<td class='left'>$LName<a name=\'$Anchor\'></a></td>\n";
        if(defined $Removed{$LName}) {
            $SYS_REPORT .= "<td class='failed'>".$Removed{$LName}{"version"}."</td>\n";
        }
        elsif(defined $Added{$LName}) {
            $SYS_REPORT .= "<td class='new'><a href='".$Added{$LName}{"list"}."'>added</a></td>\n";
        }
        elsif(not $GroupByHeaders) {
            $SYS_REPORT .= "<td>".$TestResults{$LName}{"v1"}."</td>\n";
        }
        if(defined $Added{$LName})
        { # added library
            $SYS_REPORT .= "<td class='new'>".$Added{$LName}{"version"}."</td>\n";
            $SYS_REPORT .= "<td class='passed'>100%</td>\n";
            if($RegisteredPairs{$LName}) {
                # do nothing
            }
            elsif(my $To = $ChangedSoname{$LName})
            {
                $RegisteredPairs{$To}=1;
                $SYS_REPORT .= "<td colspan='5' rowspan='2'>SONAME has <a href='".$TestResults{parse_libname($LName, "name+ext", $OStarget)}{"path"}."'>changed</a></td>\n";
            }
            else {
                foreach (1 .. 5) {
                    $SYS_REPORT .= "<td>n/a</td>\n"; # colspan='5'
                }
            }
            $SYS_REPORT .= "</tr>\n";
            next;
        }
        elsif(defined $Removed{$LName})
        { # removed library
            $SYS_REPORT .= "<td class='failed'><a href='".$Removed{$LName}{"list"}."'>removed</a></td>\n";
            $SYS_REPORT .= "<td class='failed'>0%</td>\n";
            if($RegisteredPairs{$LName}) {
                # do nothing
            }
            elsif(my $To = $ChangedSoname{$LName})
            {
                $RegisteredPairs{$To}=1;
                $SYS_REPORT .= "<td colspan='5' rowspan='2'>SONAME has <a href='".$TestResults{parse_libname($LName, "name+ext", $OStarget)}{"path"}."'>changed</a></td>\n";
            }
            else {
                foreach (1 .. 5) {
                    $SYS_REPORT .= "<td>n/a</td>\n"; # colspan='5'
                }
            }
            $SYS_REPORT .= "</tr>\n";
            next;
        }
        elsif(not $GroupByHeaders) {
            $SYS_REPORT .= "<td>".$TestResults{$LName}{"v2"}."</td>\n";
        }
        if($TestResults{$LName}{"verdict"} eq "compatible") {
            $SYS_REPORT .= "<td class='passed'><a href=\'$CompatReport\'>100%</a></td>\n";
        }
        else
        {
            my $Compatible = 100 - $TestResults{$LName}{"affected"};
            $SYS_REPORT .= "<td class='failed'><a href=\'$CompatReport\'>$Compatible%</a></td>\n";
        }
        my $AddedSym="";
        if(my $Count = $TestResults{$LName}{"added"}) {
            $AddedSym="<a href='$CompatReport\#Added'>$Count new</a>";
        }
        if($AddedSym) {
            $SYS_REPORT.="<td class='new'>$AddedSym</td>";
        }
        else {
            $SYS_REPORT.="<td class='passed'>0</td>";
        }
        my $RemovedSym="";
        if(my $Count = $TestResults{$LName}{"removed"}) {
            $RemovedSym="<a href='$CompatReport\#Removed'>$Count removed</a>";
        }
        if($RemovedSym) {
            $SYS_REPORT.="<td class='failed'>$RemovedSym</td>";
        }
        else {
            $SYS_REPORT.="<td class='passed'>0</td>";
        }
        my $High="";
        if(my $Count = $TestResults{$LName}{"type_problems_high"}+$TestResults{$LName}{"interface_problems_high"}) {
            $High="<a href='$CompatReport\#High_Risk_Problems'>".problem_title($Count)."</a>";
        }
        if($High) {
            $SYS_REPORT.="<td class='failed'>$High</td>";
        }
        else {
            $SYS_REPORT.="<td class='passed'>0</td>";
        }
        my $Medium="";
        if(my $Count = $TestResults{$LName}{"type_problems_medium"}+$TestResults{$LName}{"interface_problems_medium"}) {
            $Medium="<a href='$CompatReport\#Medium_Risk_Problems'>".problem_title($Count)."</a>";
        }
        if($Medium) {
            $SYS_REPORT.="<td class='failed'>$Medium</td>";
        }
        else {
            $SYS_REPORT.="<td class='passed'>0</td>";
        }
        my $Low="";
        if(my $Count = $TestResults{$LName}{"type_problems_low"}+$TestResults{$LName}{"interface_problems_low"}+$TestResults{$LName}{"changed_constants"}) {
            $Low="<a href='$CompatReport\#Low_Risk_Problems'>".warning_title($Count)."</a>";
        }
        if($Low) {
            $SYS_REPORT.="<td class='warning'>$Low</td>";
        }
        else {
            $SYS_REPORT.="<td class='passed'>0</td>";
        }
        $SYS_REPORT .= "</tr>\n";
    }
    my @META_DATA = ();
    my %Stat = (
        "total"=>int(keys(%TestResults)),
        "added"=>int(keys(%Added)),
        "removed"=>int(keys(%Removed))
    );
    foreach ("added", "removed")
    {
        my $Kind = $_."_interfaces";
        foreach my $LName (keys(%TestResults)) {
            $Stat{$Kind} += $TestResults{$LName}{$_};
        }
        push(@META_DATA, $Kind.":".$Stat{$Kind});
    }
    foreach my $T ("type", "interface")
    {
        foreach my $S ("high", "medium", "low")
        {
            my $Kind = $T."_problems_".$S;
            foreach my $LName (keys(%TestResults)) {
                $Stat{$Kind} += $TestResults{$LName}{$Kind};
            }
            push(@META_DATA, $Kind.":".$Stat{$Kind});
        }
    }
    foreach my $LName (keys(%TestResults))
    {
        foreach ("affected", "changed_constants") {
            $Stat{$_} += $TestResults{$LName}{$_};
        }
        if(not defined $Stat{"verdict"}
        and $TestResults{$LName}{"verdict"} eq "incompatible") {
            $Stat{"verdict"} = "incompatible";
        }
    }
    if(not defined $Stat{"verdict"}) {
        $Stat{"verdict"} = "compatible";
    }
    if($Stat{"total"}) {
        $Stat{"affected"} /= $Stat{"total"};
    }
    else {
        $Stat{"affected"} = 0;
    }
    $Stat{"affected"} = show_number($Stat{"affected"});
    if($Stat{"verdict"}>1) {
        $Stat{"verdict"} = 1;
    }
    push(@META_DATA, "changed_constants:".$Stat{"changed_constants"});
    push(@META_DATA, "tool_version:".get_dumpversion("perl $0"));
    foreach ("removed", "added", "total", "affected", "verdict") {
        @META_DATA = ($_.":".$Stat{$_}, @META_DATA);
    }
    
    # bottom header
    $SYS_REPORT .= "<tr><th rowspan='2'>$SONAME_Title</th>";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<th>$SystemName1</th><th>$SystemName2</th>";
    }
    $SYS_REPORT .= "<th rowspan='2'>Compatibility</th>
    <th rowspan='2'>Added<br/>Symbols</th>
    <th rowspan='2'>Removed<br/>Symbols</th>
    <th class='severity'>High</th><th class='severity'>Medium</th><th class='severity'>Low</th></tr>";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<tr><th colspan='2'>VERSION</th>";
    }
    $SYS_REPORT .= "<th colspan='3' style='white-space:nowrap;'>API Changes / Compatibility Problems</th></tr>\n";
    $SYS_REPORT .= "</table>";
    my $Title = "$SystemName1 to $SystemName2 binary compatibility report";
    my $Keywords = "compatibility, $SystemName1, $SystemName2, API, changes";
    my $Description = "Binary compatibility between $SystemName1 and $SystemName2 on ".showArch($ArchName);
    my $Styles = readModule("Styles", "CmpSystems.css");
    writeFile($SYS_REPORT_PATH."/abi_compat_report.html", "<!-\- ".join(";", @META_DATA)." -\->\n".composeHTML_Head($Title, $Keywords, $Description, $Styles, "")."\n<body>
    <div>$SYS_REPORT</div>
    <br/><br/><br/><hr/>
    ".getReportFooter($SystemName2)."
    <div style='height:999px;'></div>\n</body></html>");
    printMsg("INFO", "see detailed report:\n  $SYS_REPORT_PATH/abi_compat_report.html");
}

sub readSystemDescriptor($)
{
    my $Content = $_[0];
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    $SysDescriptor{"Name"} = parseTag(\$Content, "name");
    my @Tools = ();
    if(not $SysDescriptor{"Name"}) {
        exitStatus("Error", "system name is not specified (<name> section)");
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "libs")))
    { # target libs
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $SysDescriptor{"Libs"}{clean_path($Path)} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_libs")))
    { # target libs
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $SysDescriptor{"SearchLibs"}{clean_path($Path)} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "headers")))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $SysDescriptor{"Headers"}{clean_path($Path)} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_headers")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $SysDescriptor{"SearchHeaders"}{clean_path($Path)} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "tools")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path = clean_path($Path);
        $SysDescriptor{"Tools"}{$Path} = 1;
        push(@Tools, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "gcc_options"))) {
        $SysDescriptor{"GccOpts"}{clean_path($Path)} = 1;
    }
    if($SysDescriptor{"CrossPrefix"} = parseTag(\$Content, "cross_prefix"))
    { # <cross_prefix> section of XML descriptor
        $CrossPrefix = $SysDescriptor{"CrossPrefix"};
    }
    elsif($CrossPrefix)
    { # -cross-prefix tool option
        $SysDescriptor{"CrossPrefix"} = $CrossPrefix;
    }
    $SysDescriptor{"Defines"} = parseTag(\$Content, "defines");
    if($SysDescriptor{"Image"} = parseTag(\$Content, "image"))
    { # <image>
      # FIXME: isn't implemented yet
        if(not -f $SysDescriptor{"Image"}) {
            exitStatus("Access_Error", "can't access \'".$SysDescriptor{"Image"}."\'");
        }
    }
    return {"Tools"=>\@Tools,"CrossPrefix"=>$CrossPrefix};
}

sub readOpts($)
{
    my $S = $_[0];
    $OStarget = $S->{"OStarget"};
    $Debug = $S->{"Debug"};
    $Quiet = $S->{"Quiet"};
    $LogMode = $S->{"LogMode"};
    $CheckHeadersOnly = $S->{"CheckHeadersOnly"};
    
    $SystemRoot = $S->{"SystemRoot"};
    $MODULES_DIR = $S->{"MODULES_DIR"};
    $GCC_PATH = $S->{"GCC_PATH"};
    $TargetSysInfo = $S->{"TargetSysInfo"};
    $CrossPrefix = $S->{"CrossPrefix"};
    $TargetLibraryName = $S->{"TargetLibraryName"};
    $CrossGcc = $S->{"CrossGcc"};
    $UseStaticLibs = $S->{"UseStaticLibs"};
    $NoStdInc = $S->{"NoStdInc"};
}

sub check_list($$)
{
    my ($Item, $Skip) = @_;
    return 0 if(not $Skip);
    my @Patterns = @{$Skip};
    foreach my $Pattern (@Patterns)
    {
        if($Pattern=~s/\*/.*/g)
        { # wildcards
            if($Item=~/$Pattern/) {
                return 1;
            }
        }
        elsif($Pattern=~/[\/\\]/)
        { # directory
            if($Item=~/\Q$Pattern\E/) {
                return 1;
            }
        }
        elsif($Item eq $Pattern
        or get_filename($Item) eq $Pattern)
        { # by name
            return 1;
        }
    }
    return 0;
}

sub filter_format($)
{
    my $FiltRef = $_[0];
    foreach my $Entry (keys(%{$FiltRef}))
    {
        foreach my $Filt (@{$FiltRef->{$Entry}})
        {
            if($Filt=~/[\/\\]/) {
                $Filt = path_format($Filt, $OSgroup);
            }
        }
    }
}

sub read_sys_descriptor($)
{
    my $Path = $_[0];
    my $Content = readFile($Path);
    my %Tags = (
        "headers" => "mf",
        "skip_headers" => "mf",
        "skip_including" => "mf",
        "skip_libs" => "mf",
        "include_preamble" => "mf",
        "non_self_compiled" => "mf",
        "add_include_paths" => "mf",
        "gcc_options" => "m",
        "skip_symbols" => "m",
        "skip_types" => "m",
        "ignore_symbols" => "h",
        "defines" => "s"
    );
    my %DInfo = ();
    foreach my $Tag (keys(%Tags))
    {
        if(my $TContent = parseTag(\$Content, $Tag))
        {
            if($Tags{$Tag}=~/m/)
            { # multi-line (+order)
                my @Items = split(/\s*\n\s*/, $TContent);
                $DInfo{$Tag} = [];
                foreach my $Item (@Items)
                {
                    if($Tags{$Tag}=~/f/) {
                        $Item = path_format($Item, $OSgroup);
                    }
                    push(@{$DInfo{$Tag}}, $Item);
                }
            
            }
            elsif($Tags{$Tag}=~/s/)
            { # single element
                $DInfo{$Tag} = $TContent;
            }
            else
            { # hash array
                my @Items = split(/\s*\n\s*/, $TContent);
                foreach my $Item (@Items) {
                    $DInfo{$Tag}{$Item}=1;
                }
            }
        }
    }
    return \%DInfo;
}

sub read_sys_info($)
{
    my $Target = $_[0];
    my $SYS_INFO_PATH = $MODULES_DIR."/Targets";
    if(-d $SYS_INFO_PATH."/".$Target)
    { # symbian, windows
        $SYS_INFO_PATH .= "/".$Target;
    }
    else
    { # default
        $SYS_INFO_PATH .= "/unix";
    }
    if($TargetSysInfo)
    { # user-defined target
        $SYS_INFO_PATH = $TargetSysInfo;
    }
    if(not -d $SYS_INFO_PATH) {
        exitStatus("Module_Error", "can't access \'$SYS_INFO_PATH\'");
    }
    # Library Specific Info
    my %SysInfo = ();
    if(not -d $SYS_INFO_PATH."/descriptors/") {
        exitStatus("Module_Error", "can't access \'$SYS_INFO_PATH/descriptors\'");
    }
    foreach my $DPath (cmd_find($SYS_INFO_PATH."/descriptors/","f","",1))
    {
        my $LSName = get_filename($DPath);
        $LSName=~s/\.xml\Z//;
        $SysInfo{$LSName} = read_sys_descriptor($DPath);
    }
    # Exceptions
    if(check_gcc($GCC_PATH, "4.4"))
    { # exception for libstdc++
        $SysInfo{"libstdc++"}{"gcc_options"} = ["-std=c++0x"];
    }
    if($OStarget eq "symbian")
    { # exception for libstdcpp
        $SysInfo{"libstdcpp"}{"defines"} = "namespace std { struct nothrow_t {}; }";
    }
    if($SysDescriptor{"Name"}=~/maemo/i)
    { # GL/gl.h: No such file
        $SysInfo{"libSDL"}{"skip_headers"}=["SDL_opengl.h"];
    }
    if($OStarget eq "linux") {
        $SysInfo{"libboost_"}{"headers"} = ["/boost/", "/asio/"];
    }
    # Common Info
    if(not -f $SYS_INFO_PATH."/common.xml") {
        exitStatus("Module_Error", "can't access \'$SYS_INFO_PATH/common.xml\'");
    }
    my $SysCInfo = read_sys_descriptor($SYS_INFO_PATH."/common.xml");
    my @CompilerOpts = ();
    if($SysDescriptor{"Name"}=~/maemo|meego/i) {
        push(@CompilerOpts, "-DMAEMO_CHANGES", "-DM_APPLICATION_NAME=\\\"app\\\"");
    }
    if(my @Opts = keys(%{$SysDescriptor{"GccOpts"}})) {
        push(@CompilerOpts, @Opts);
    }
    if(@CompilerOpts)
    {
        if(not $SysCInfo->{"gcc_options"}) {
            $SysCInfo->{"gcc_options"} = [];
        }
        push(@{$SysCInfo->{"gcc_options"}}, @CompilerOpts);
    }
    foreach my $Name (keys(%SysInfo))
    { # strict headers that should be
      # matched for only one library
        if($SysInfo{$Name}{"headers"}) {
            $SysCInfo->{"sheaders"}{$Name} = $SysInfo{$Name}{"headers"};
        }
    }
    return (\%SysInfo, $SysCInfo);
}

sub get_binversion($)
{
    my $Path = $_[0];
    if($OStarget eq "windows"
    and $LIB_EXT eq "dll")
    { # get version of DLL using "sigcheck"
        my $SigcheckCmd = get_CmdPath("sigcheck");
        if(not $SigcheckCmd) {
            return "";
        }
        my $VInfo = `$SigcheckCmd -n $Path 2>$TMP_DIR/null`;
        $VInfo=~s/\s*\(.*\)\s*//;
        chomp($VInfo);
        return $VInfo;
    }
    return "";
}

sub get_soname($)
{
    my $Path = $_[0];
    return if(not $Path or not -e $Path);
    if(defined $Cache{"get_soname"}{$Path}) {
        return $Cache{"get_soname"}{$Path};
    }
    my $ObjdumpCmd = get_CmdPath("objdump");
    if(not $ObjdumpCmd) {
        exitStatus("Not_Found", "can't find \"objdump\"");
    }
    my $SonameCmd = "$ObjdumpCmd -x $Path 2>$TMP_DIR/null";
    if($OSgroup eq "windows") {
        $SonameCmd .= " | find \"SONAME\"";
    }
    else {
        $SonameCmd .= " | grep SONAME";
    }
    if(my $SonameInfo = `$SonameCmd`) {
        if($SonameInfo=~/SONAME\s+([^\s]+)/) {
            return ($Cache{"get_soname"}{$Path} = $1);
        }
    }
    return ($Cache{"get_soname"}{$Path}="");
}

sub dumpSystem($)
{ # -dump-system option handler
  # should be used with -sysroot and -cross-gcc options
    my $Opts = $_[0];
    readOpts($Opts);
    my $SYS_DUMP_PATH = "sys_dumps/".$SysDescriptor{"Name"}."/".getArch(1);
    if(not $TargetLibraryName) {
        rmtree($SYS_DUMP_PATH);
    }
    my (@SystemLibs, @SysHeaders) = ();
    foreach my $Path (keys(%{$SysDescriptor{"Libs"}}))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        if(-d $Path)
        {
            if(my @SubLibs = find_libs($Path,"",1)) {
                push(@SystemLibs, @SubLibs);
            }
            $SysDescriptor{"SearchLibs"}{$Path}=1;
        }
        else
        { # single file
            push(@SystemLibs, $Path);
            $SysDescriptor{"SearchLibs"}{get_dirname($Path)}=1;
        }
    }
    foreach my $Path (keys(%{$SysDescriptor{"Headers"}}))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        if(-d $Path)
        {
            if(my @SubHeaders = cmd_find($Path,"f","","")) {
                push(@SysHeaders, @SubHeaders);
            }
            $SysDescriptor{"SearchHeaders"}{$Path}=1;
        }
        else
        { # single file
            push(@SysHeaders, $Path);
            $SysDescriptor{"SearchHeaders"}{get_dirname($Path)}=1;
        }
    }
    my $GroupByHeaders = 0;
    if($CheckHeadersOnly)
    { # -headers-only
        $GroupByHeaders = 1;
        # @SysHeaders = optimize_set(@SysHeaders);
    }
    elsif($SysDescriptor{"Image"})
    { # one big image
        $GroupByHeaders = 1;
        @SystemLibs = ($SysDescriptor{"Image"});
    }
    writeFile($SYS_DUMP_PATH."/target.txt", $OStarget);
    my (%SysLib_Symbols, %SymbolGroup, %Symbol_SysHeaders,
    %SysHeader_Symbols, %SysLib_SysHeaders, %MatchByName) = ();
    my (%Skipped, %Failed, %Success) = ();
    my (%SysHeaderDir_SysLibs, %SysHeaderDir_SysHeaders) = ();
    my (%LibPrefixes, %SymbolCounter, %TotalLibs) = ();
    my %Glibc = map {$_=>1} (
        "libc",
        "libpthread"
    );
    my ($SysInfo, $SysCInfo) = read_sys_info($OStarget);
    if(not $GroupByHeaders) {
        printMsg("INFO", "Indexing sonames ...");
    }
    my (%LibSoname, %SysLibVersion) = ();
    my %DevelPaths = map {$_=>1} @SystemLibs;
    foreach my $Path (sort keys(%{$SysDescriptor{"SearchLibs"}}))
    {
        foreach my $LPath (find_libs($Path,"",1)) {
            $DevelPaths{$LPath}=1;
        }
    }
    foreach my $LPath (keys(%DevelPaths))
    { # register SONAMEs
        my $LName = get_filename($LPath);
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        if(not is_target_lib($LName)) {
            next;
        }
        if($OSgroup=~/\A(linux|macos|freebsd)\Z/
        and $LName!~/\Alib/) {
            next;
        }
        if(my $Soname = get_soname($LPath))
        {
            if($OStarget eq "symbian")
            {
                if($Soname=~/[\/\\]/)
                { # L://epoc32/release/armv5/lib/gfxtrans{000a0000}.dso
                    $Soname = get_filename($Soname);
                }
                $Soname = lc($Soname);
            }
            if(not defined $LibSoname{$LName}) {
                $LibSoname{$LName}=$Soname;
            }
            if(-l $LPath and my $Path = resolve_symlink($LPath))
            {
                my $Name = get_filename($Path);
                if(not defined $LibSoname{$Name}) {
                    $LibSoname{$Name}=$Soname;
                }
            }
        }
        else
        { # windows and others
            $LibSoname{$LName}=$LName;
        }
    }
    my $SONAMES = "";
    foreach (sort {lc($a) cmp lc($b)} keys(%LibSoname)) {
        $SONAMES .= $_.";".$LibSoname{$_}."\n";
    }
    if(not $GroupByHeaders) {
        writeFile($SYS_DUMP_PATH."/sonames.txt", $SONAMES);
    }
    foreach my $LPath (sort keys(%DevelPaths))
    { # register VERSIONs
        my $LName = get_filename($LPath);
        if(not is_target_lib($LName)
        and not is_target_lib($LibSoname{$LName})) {
            next;
        }
        if(my $BV = get_binversion($LPath))
        { # binary version
            $SysLibVersion{$LName} = $BV;
        }
        elsif(my $PV = parse_libname($LName, "version", $OStarget))
        { # source version
            $SysLibVersion{$LName} = $PV;
        }
        elsif($LName=~/(\d[\d\.\-\_]*)\.$LIB_EXT\Z/)
        { # libfreebl3.so
            if($1 ne 32 and $1 ne 64) {
                $SysLibVersion{$LName} = $1;
            }
        }
    }
    my $VERSIONS = "";
    foreach (sort {lc($a) cmp lc($b)} keys(%SysLibVersion)) {
        $VERSIONS .= $_.";".$SysLibVersion{$_}."\n";
    }
    if(not $GroupByHeaders) {
        writeFile($SYS_DUMP_PATH."/versions.txt", $VERSIONS);
    }
    my %SysLibs = ();
    foreach my $LPath (sort @SystemLibs)
    {
        my $LName = get_filename($LPath);
        my $LSName = parse_libname($LName, "short", $OStarget);
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        if(not is_target_lib($LName)) {
            next;
        }
        if($OSgroup=~/\A(linux|macos|freebsd)\Z/
        and $LName!~/\Alib/) {
            next;
        }
        if($OStarget eq "symbian")
        {
            if(my $V = parse_libname($LName, "version", $OStarget))
            { # skip qtcore.dso
              # register qtcore{00040604}.dso
                delete($SysLibs{get_dirname($LPath)."\\".$LSName.".".$LIB_EXT});
                my $MV = parse_libname($LibSoname{$LSName.".".$LIB_EXT}, "version", $OStarget);
                if($MV and $V ne $MV)
                { # skip other versions:
                  #  qtcore{00040700}.dso
                  #  qtcore{00040702}.dso
                    next;
                }
            }
        }
        if(my $Skip = $SysCInfo->{"skip_libs"})
        { # do NOT check some libs
            if(check_list($LRelPath, $Skip)) {
                next;
            }
        }
        if(-l $LPath)
        { # symlinks
            if(my $Path = resolve_symlink($LPath)) {
                $SysLibs{$Path} = 1;
            }
        }
        elsif(-f $LPath)
        {
            if($Glibc{$LSName}
            and cmd_file($LPath)=~/ASCII/)
            {# GNU ld scripts (libc.so, libpthread.so)
                my @Candidates = cmd_find($SystemRoot."/lib","",$LSName.".".$LIB_EXT."*","1");
                if(@Candidates)
                {
                    my $Candidate = $Candidates[0];
                    if(-l $Candidate
                    and my $Path = resolve_symlink($Candidate)) {
                        $Candidate = $Path;
                    }
                    $SysLibs{$Candidate} = 1;
                }
            }
            else {
                $SysLibs{$LPath} = 1;
            }
        }
    }
    @SystemLibs = ();# clear memory
    if(not $CheckHeadersOnly)
    {
        if($SysDescriptor{"Image"}) {
            printMsg("INFO", "Reading symbols from image ...");
        }
        else {
            printMsg("INFO", "Reading symbols from libraries ...");
        }
    }
    
    foreach my $LPath (sort keys(%SysLibs))
    {
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        my $LName = get_filename($LPath);
        my $Library_Symbol = readSymbols_Lib(1, $LPath, 0, (), "-Weak");
        my @AllSymbols = keys(%{$Library_Symbol->{$LName}});
        my $tr_name = translateSymbols(@AllSymbols, 1);
        foreach my $Symbol (@AllSymbols)
        {
            $Symbol=~s/[\@\$]+(.*)\Z//g;
            if($Symbol=~/\A(_Z|\?)/)
            {
                if(isPrivateData($Symbol)) {
                    next;
                }
                if($Symbol=~/(C1|C2|D0|D1|D2)E/)
                { # do NOT analyze constructors
                  # and destructors
                    next;
                }
                my $Unmangled = $tr_name->{$Symbol};
                $Unmangled=~s/<.+>//g;
                if($Unmangled=~/\A([\w:]+)/)
                { # cut out the parameters
                    my @Elems = split(/::/, $1);
                    my ($Class, $Short) = ("", "");
                    $Short = $Elems[$#Elems];
                    if($#Elems>=1)
                    {
                        $Class = $Elems[$#Elems-1];
                        pop(@Elems);
                    }
                    # the short and class name should be
                    # matched in one header file
                    $SymbolGroup{$LRelPath}{$Class} = $Short;
                    foreach my $Sym (@Elems)
                    {
                        if($SysCInfo->{"ignore_symbols"}{$Symbol})
                        { # do NOT match this symbol
                            next;
                        }
                        $SysLib_Symbols{$LPath}{$Sym}=1;
                        if(my $Prefix = getPrefix($Sym)) {
                            $LibPrefixes{$Prefix}{$LName}+=1;
                        }
                        $SymbolCounter{$Sym}{$LName}=1;
                    }
                }
            }
            else
            {
                if($SysCInfo->{"ignore_symbols"}{$Symbol})
                { # do NOT match this symbol
                    next;
                }
                $SysLib_Symbols{$LPath}{$Symbol}=1;
                if(my $Prefix = getPrefix($Symbol)) {
                    $LibPrefixes{$Prefix}{$LName}+=1;
                }
                $SymbolCounter{$Symbol}{$LName}=1;
            }
        }
    }
    if(not $CheckHeadersOnly) {
        writeFile($SYS_DUMP_PATH."/symbols.txt", Dumper(\%SysLib_Symbols));
    }
    my (%DupLibs, %VersionedLibs) = ();
    foreach my $LPath1 (sort keys(%SysLib_Symbols))
    { # match duplicated libs
      # libmenu contains all symbols from libmenuw
        my $SName = parse_libname(get_filename($LPath1), "shortest", $OStarget);
        foreach my $LPath2 (sort keys(%SysLib_Symbols))
        {
            next if($LPath1 eq $LPath2);
            if($SName eq parse_libname(get_filename($LPath2), "shortest", $OStarget))
            { # libpython-X.Y
                $VersionedLibs{$LPath1}{$LPath2}=1;
                next;
            }
            my $Duplicate=1;
            foreach (keys(%{$SysLib_Symbols{$LPath1}}))
            {
                if(not defined $SysLib_Symbols{$LPath2}{$_}) {
                    $Duplicate=0;
                    last;
                }
            }
            if($Duplicate) {
                $DupLibs{$LPath1}{$LPath2}=1;
            }
        }
    }
    foreach my $Prefix (keys(%LibPrefixes))
    {
        my @Libs = keys(%{$LibPrefixes{$Prefix}});
        @Libs = sort {$LibPrefixes{$Prefix}{$b}<=>$LibPrefixes{$Prefix}{$a}} @Libs;
        $LibPrefixes{$Prefix}=$Libs[0];
    }
    printMsg("INFO", "Reading symbols from headers ...");
    foreach my $HPath (@SysHeaders)
    {
        $HPath = path_format($HPath, $OSgroup);
        my $HRelPath = cut_path_prefix($HPath, $SystemRoot);
        my ($HDir, $HName) = separate_path($HRelPath);
        if(is_not_header($HName))
        { # have a wrong extension: .gch, .in
            next;
        }
        if($HName=~/~\Z/)
        { # reserved copy
            next;
        }
        if($HRelPath=~/[\/\\]_gen/)
        { # telepathy-1.0/telepathy-glib/_gen
          # telepathy-1.0/libtelepathy/_gen-tp-constants-deprecated.h
            next;
        }
        if($HRelPath=~/include[\/\\]linux[\/\\]/)
        { # kernel-space headers
            next;
        }
        if($HRelPath=~/include[\/\\]asm[\/\\]/)
        { # asm headers
            next;
        }
        if($HRelPath=~/[\/\\]microb-engine[\/\\]/)
        { # MicroB engine (Maemo 4)
            next;
        }
        if($HRelPath=~/\Wprivate(\W|\Z)/)
        { # private directories (include/tcl-private, ...)
            next;
        }
        my $Content = readFile($HPath);
        $Content=~s/\/\*(.|\n)+?\*\///g;
        $Content=~s/\/\/.*?\n//g;# remove comments
        $Content=~s/#\s*define[^\n\\]*(\\\n[^\n\\]*)+\n*//g;# remove defines
        $Content=~s/#[^\n]*?\n//g;# remove directives
        $Content=~s/(\A|\n)class\s+\w+;\n//g;# remove forward declarations
        # FIXME: try to add preprocessing stage
        foreach my $Symbol (split(/\W+/, $Content))
        {
            $Symbol_SysHeaders{$Symbol}{$HRelPath} = 1;
            $SysHeader_Symbols{$HRelPath}{$Symbol} = 1;
        }
        $SysHeaderDir_SysHeaders{$HDir}{$HName} = 1;
        my $HShort = $HName;
        $HShort=~s/\.\w+\Z//g;
        if($HShort=~/\Alib/) {
            $MatchByName{$HShort} = $HRelPath;
        }
        elsif(get_filename(get_dirname($HRelPath))=~/\Alib(.+)\Z/)
        { # libical/ical.h
            if($HShort=~/\Q$1\E/) {
                $MatchByName{"lib".$HShort} = $HRelPath;
            }
        }
        elsif($OStarget eq "windows"
        and $HShort=~/api\Z/) {
            $MatchByName{$HShort} = $HRelPath;
        }
    }
    my %SkipDHeaders = (
    # header files, that should be in the <skip_headers> section
    # but should be matched in the algorithm
        # MeeGo 1.2 Harmattan
        "libtelepathy-qt4" => ["TelepathyQt4/_gen", "client.h",
                        "TelepathyQt4/*-*", "debug.h", "global.h",
                        "properties.h", "Channel", "channel.h", "message.h"],
    );
    filter_format(\%SkipDHeaders);
    if(not $GroupByHeaders) {
        printMsg("INFO", "Matching symbols ...");
    }
    foreach my $LPath (sort keys(%SysLibs))
    { # matching
        my $LName = get_filename($LPath);
        my $LNameSE = parse_libname($LName, "name+ext", $OStarget);
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        my $LSName = parse_libname($LName, "short", $OStarget);
        my $SName = parse_libname($LName, "shortest", $OStarget);
        if($LRelPath=~/\/debug\//)
        { # debug libs
            $Skipped{$LRelPath}=1;
            next;
        }
        $TotalLibs{$LRelPath}=1;
        $SysLib_SysHeaders{$LRelPath} = ();
        if(keys(%{$SysLib_Symbols{$LPath}}))
        { # try to match by name of the header
            if(my $Path = $MatchByName{$LSName}) {
                $SysLib_SysHeaders{$LRelPath}{$Path}="exact match ($LSName)";
            }
            if(length($SName)>=3
            and my $Path = $MatchByName{"lib".$SName}) {
                $SysLib_SysHeaders{$LRelPath}{$Path}="exact match (lib$SName)";
            }
        }
        my (%SymbolDirs, %SymbolFiles) = ();
        foreach my $Symbol (sort {length($b) cmp length($a)}
        sort keys(%{$SysLib_Symbols{$LPath}}))
        {
            if($SysCInfo->{"ignore_symbols"}{$Symbol}) {
                next;
            }
            if(not $DupLibs{$LPath}
            and not $VersionedLibs{$LPath}
            and keys(%{$SymbolCounter{$Symbol}})>=2
            and my $Prefix = getPrefix($Symbol))
            { # duplicated symbols
                if($LibPrefixes{$Prefix}
                and $LibPrefixes{$Prefix} ne $LName
                and not $Glibc{$LSName}) {
                    next;
                }
            }
            if(length($Symbol)<=2) {
                next;
            }
            if($Symbol!~/[A-Z_0-9]/
            and length($Symbol)<10
            and keys(%{$Symbol_SysHeaders{$Symbol}})>=3)
            { # undistinguished symbols
              # FIXME: improve this filter
              # signalfd (libc.so)
              # regcomp (libpcreposix.so)
                next;
            }
            if($Symbol=~/\A(_M_|_Rb_|_S_)/)
            { # _M_insert, _Rb_tree, _S_destroy_c_locale
                next;
            }
            if($Symbol=~/\A[A-Z][a-z]+\Z/)
            { # Clone, Initialize, Skip, Unlock, Terminate, Chunk
                next;
            }
            if($Symbol=~/\A[A-Z][A-Z]\Z/)
            { #  BC, PC, UP, SP
                next;
            }
            if($Symbol=~/_t\Z/)
            { # pthread_mutex_t, wchar_t
                next;
            }
            my @SymHeaders = keys(%{$Symbol_SysHeaders{$Symbol}});
            @SymHeaders = sort {lc($a) cmp lc($b)} @SymHeaders;# sort by name
            @SymHeaders = sort {length(get_dirname($a))<=>length(get_dirname($b))} @SymHeaders;# sort by length
            if(length($SName)>=3)
            { # sort candidate headers by name
                @SymHeaders = sort {$b=~/\Q$SName\E/i<=>$a=~/\Q$SName\E/i} @SymHeaders;
            }
            else
            { # libz, libX11
                @SymHeaders = sort {$b=~/lib\Q$SName\E/i<=>$a=~/lib\Q$SName\E/i} @SymHeaders;
                @SymHeaders = sort {$b=~/\Q$SName\Elib/i<=>$a=~/\Q$SName\Elib/i} @SymHeaders;
            }
            @SymHeaders = sort {$b=~/\Q$LSName\E/i<=>$a=~/\Q$LSName\E/i} @SymHeaders;
            @SymHeaders = sort {$SymbolDirs{get_dirname($b)}<=>$SymbolDirs{get_dirname($a)}} @SymHeaders;
            @SymHeaders = sort {$SymbolFiles{get_filename($b)}<=>$SymbolFiles{get_filename($a)}} @SymHeaders;
            foreach my $HRelPath (@SymHeaders)
            {
                if(my $Group = $SymbolGroup{$LRelPath}{$Symbol}) {
                    if(not $SysHeader_Symbols{$HRelPath}{$Group}) {
                        next;
                    }
                }
                if(my $Search = $SysInfo->{$LSName}{"headers"})
                { # search for specified headers
                    if(not check_list($HRelPath, $Search)) {
                        next;
                    }
                }
                if(my $Skip = $SysInfo->{$LSName}{"skip_headers"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Skip)) {
                        next;
                    }
                }
                if(my $Skip = $SysInfo->{$LSName}{"skip_including"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Skip)) {
                        next;
                    }
                }
                if(my $Skip = $SysCInfo->{"skip_headers"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Skip)) {
                        next;
                    }
                }
                if(my $Skip = $SysCInfo->{"skip_including"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Skip)) {
                        next;
                    }
                }
                if(my $Skip = $SysInfo->{$LSName}{"non_self_compiled"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Skip)) {
                        $SymbolDirs{get_dirname($HRelPath)}+=1;
                        $SymbolFiles{get_filename($HRelPath)}+=1;
                        next;
                    }
                }
                my $Continue = 1;
                foreach my $Name (keys(%{$SysCInfo->{"sheaders"}}))
                {
                    if($LSName!~/\Q$Name\E/
                    and check_list($HRelPath, $SysCInfo->{"sheaders"}{$Name}))
                    { # restriction to search for C++ or Boost headers
                      # in the boost/ and c++/ directories only
                        $Continue=0;
                        last;
                    }
                }
                if(not $Continue) {
                    next;
                }
                $SysLib_SysHeaders{$LRelPath}{$HRelPath}=$Symbol;
                $SysHeaderDir_SysLibs{get_dirname($HRelPath)}{$LNameSE}=1;
                $SysHeaderDir_SysLibs{get_dirname(get_dirname($HRelPath))}{$LNameSE}=1;
                $SymbolDirs{get_dirname($HRelPath)}+=1;
                $SymbolFiles{get_filename($HRelPath)}+=1;
                last;# select one header for one symbol
            }
        }
        if(keys(%{$SysLib_SysHeaders{$LRelPath}})) {
            $Success{$LRelPath}=1;
        }
        else {
            $Failed{$LRelPath}=1;
        }
    }
    if(not $GroupByHeaders)
    { # matching results
        writeFile($SYS_DUMP_PATH."/match.txt", Dumper(\%SysLib_SysHeaders));
        writeFile($SYS_DUMP_PATH."/skipped.txt", join("\n", sort keys(%Skipped)));
        writeFile($SYS_DUMP_PATH."/failed.txt", join("\n", sort keys(%Failed)));
    }
    (%SysLib_Symbols, %SymbolGroup, %Symbol_SysHeaders, %SysHeader_Symbols) = ();# free memory
    if($GroupByHeaders)
    {
        if($SysDescriptor{"Image"} and not $CheckHeadersOnly) {
            @SysHeaders = keys(%{$SysLib_SysHeaders{$SysDescriptor{"Image"}}});
        }
        %SysLib_SysHeaders = ();
        foreach my $Path (@SysHeaders)
        {
            if(my $Skip = $SysCInfo->{"skip_headers"})
            { # do NOT search for some headers
                if(check_list($Path, $Skip)) {
                    next;
                }
            }
            if(my $Skip = $SysCInfo->{"skip_including"})
            { # do NOT search for some headers
                if(check_list($Path, $Skip)) {
                    next;
                }
            }
            $SysLib_SysHeaders{$Path}{$Path} = 1;
        }
        if($CheckHeadersOnly) {
            writeFile($SYS_DUMP_PATH."/mode.txt", "headers-only");
        }
        else {
            writeFile($SYS_DUMP_PATH."/mode.txt", "group-by-headers");
        }
    }
    @SysHeaders = ();# clear memory
    (%Skipped, %Failed, %Success) = ();
    printMsg("INFO", "Generating XML descriptors ...");
    foreach my $LRelPath (keys(%SysLib_SysHeaders))
    {
        my $LName = get_filename($LRelPath);
        my $DPath = $SYS_DUMP_PATH."/descriptors/$LName.xml";
        unlink($DPath);
        if(my @LibHeaders = keys(%{$SysLib_SysHeaders{$LRelPath}}))
        {
            my $LSName = parse_libname($LName, "short", $OStarget);
            if($GroupByHeaders)
            { # header short name
                $LSName = $LName;
                $LSName=~s/\.(.+?)\Z//;
            }
            my (%DirsHeaders, %Includes) = ();
            foreach my $HRelPath (@LibHeaders) {
                $DirsHeaders{get_dirname($HRelPath)}{$HRelPath}=1;
            }
            foreach my $Dir (keys(%DirsHeaders))
            {
                my $DirPart = 0;
                my $TotalHeaders = keys(%{$SysHeaderDir_SysHeaders{$Dir}});
                if($TotalHeaders) {
                    $DirPart = (keys(%{$DirsHeaders{$Dir}})*100)/$TotalHeaders;
                }
                my $Neighbourhoods = keys(%{$SysHeaderDir_SysLibs{$Dir}});
                if($Neighbourhoods==1)
                { # one lib in this directory
                    if(get_filename($Dir) ne "include"
                    and $DirPart>=5)
                    { # complete directory
                        $Includes{$Dir} = 1;
                    }
                    else
                    { # list of headers
                        @Includes{keys(%{$DirsHeaders{$Dir}})}=values(%{$DirsHeaders{$Dir}});
                    }
                }
                elsif((keys(%{$DirsHeaders{$Dir}})*100)/($#LibHeaders+1)>5)
                {# remove 5% divergence
                    if(get_filename($Dir) ne "include"
                    and $DirPart>=50)
                    { # complete directory
                        $Includes{$Dir} = 1;
                    }
                    else
                    { # list of headers
                        @Includes{keys(%{$DirsHeaders{$Dir}})}=values(%{$DirsHeaders{$Dir}});
                    }
                }
            }
            if($GroupByHeaders)
            { # one header in one ABI dump
                %Includes = ($LibHeaders[0] => 1);
            }
            my $LVersion = $SysLibVersion{$LName};
            if($LVersion)
            {# append by system name
                $LVersion .= "-".$SysDescriptor{"Name"};
            }
            else {
                $LVersion = $SysDescriptor{"Name"};
            }
            my @Content = ("<version>\n    $LVersion\n</version>");
            my @IncHeaders = sort {natural_sorting($a, $b)} keys(%Includes);
            sort_by_word(\@IncHeaders, parse_libname($LName, "shortest", $OStarget));
            if(is_abs($IncHeaders[0])) {
                push(@Content, "<headers>\n    ".join("\n    ", @IncHeaders)."\n</headers>");
            }
            else {
                push(@Content, "<headers>\n    {RELPATH}/".join("\n    {RELPATH}/", @IncHeaders)."\n</headers>");
            }
            if($GroupByHeaders)
            {
                if($SysDescriptor{"Image"}) {
                    push(@Content, "<libs>\n    ".$SysDescriptor{"Image"}."\n</libs>");
                }
            }
            else
            {
                if(is_abs($LRelPath) or -f $LRelPath) {
                    push(@Content, "<libs>\n    $LRelPath\n</libs>");
                }
                else {
                    push(@Content, "<libs>\n    {RELPATH}/$LRelPath\n</libs>");
                }
            }
            if(my @SearchHeaders = keys(%{$SysDescriptor{"SearchHeaders"}})) {
                push(@Content, "<search_headers>\n    ".join("\n    ", @SearchHeaders)."\n</search_headers>");
            }
            if(my @SearchLibs = keys(%{$SysDescriptor{"SearchLibs"}})) {
                push(@Content, "<search_libs>\n    ".join("\n    ", @SearchLibs)."\n</search_libs>");
            }
            if(my @Tools = keys(%{$SysDescriptor{"Tools"}})) {
                push(@Content, "<tools>\n    ".join("\n    ", @Tools)."\n</tools>");
            }
            my @Skip = ();
            if($SysInfo->{$LSName}{"skip_headers"}) {
                @Skip = (@Skip, @{$SysInfo->{$LSName}{"skip_headers"}});
            }
            if($SysCInfo->{"skip_headers"}) {
                @Skip = (@Skip, @{$SysCInfo->{"skip_headers"}});
            }
            if(@Skip) {
                push(@Content, "<skip_headers>\n    ".join("\n    ", @Skip)."\n</skip_headers>");
            }
            my @SkipInc = ();
            if($SysInfo->{$LSName}{"skip_including"}) {
                @SkipInc = (@SkipInc, @{$SysInfo->{$LSName}{"skip_including"}});
            }
            if($SysCInfo->{"skip_including"}) {
                @SkipInc = (@SkipInc, @{$SysCInfo->{"skip_including"}});
            }
            if($SysInfo->{$LSName}{"non_self_compiled"}) {
                @SkipInc = (@SkipInc, @{$SysInfo->{$LSName}{"non_self_compiled"}});
            }
            if($SkipDHeaders{$LSName}) {
                @SkipInc = (@SkipInc, @{$SkipDHeaders{$LSName}});
            }
            if(@SkipInc) {
                push(@Content, "<skip_including>\n    ".join("\n    ", @SkipInc)."\n</skip_including>");
            }
            if($SysInfo->{$LSName}{"add_include_paths"}) {
                push(@Content, "<add_include_paths>\n    ".join("\n    ", @{$SysInfo->{$LSName}{"add_include_paths"}})."\n</add_include_paths>");
            }
            if($SysInfo->{$LSName}{"skip_types"}) {
                push(@Content, "<skip_types>\n    ".join("\n    ", @{$SysInfo->{$LSName}{"skip_types"}})."\n</skip_types>");
            }
            my @SkipSymb = ();
            if($SysInfo->{$LSName}{"skip_symbols"}) {
                push(@SkipSymb, @{$SysInfo->{$LSName}{"skip_symbols"}});
            }
            if($SysCInfo->{"skip_symbols"}) {
                push(@SkipSymb, @{$SysCInfo->{"skip_symbols"}});
            }
            if(@SkipSymb) {
                push(@Content, "<skip_symbols>\n    ".join("\n    ", @SkipSymb)."\n</skip_symbols>");
            }
            my @Preamble = ();
            if($SysCInfo->{"include_preamble"}) {
                push(@Preamble, @{$SysCInfo->{"include_preamble"}});
            }
            if($LSName=~/\AlibX\w+\Z/)
            { # add Xlib.h for libXt, libXaw, libXext and others
                push(@Preamble, "Xlib.h", "X11/Intrinsic.h");
            }
            if($SysInfo->{$LSName}{"include_preamble"}) {
                push(@Preamble, @{$SysInfo->{$LSName}{"include_preamble"}});
            }
            if(@Preamble) {
                push(@Content, "<include_preamble>\n    ".join("\n    ", @Preamble)."\n</include_preamble>");
            }
            my @Defines = ();
            if($SysCInfo->{"defines"}) {
                push(@Defines, $SysCInfo->{"defines"});
            }
            if($SysInfo->{$LSName}{"defines"}) {
                push(@Defines, $SysInfo->{$LSName}{"defines"});
            }
            if($SysDescriptor{"Defines"}) {
                push(@Defines, $SysDescriptor{"Defines"});
            }
            if(@Defines) {
                push(@Content, "<defines>\n    ".join("\n    ", @Defines)."\n</defines>");
            }
            my @CompilerOpts = ();
            if($SysCInfo->{"gcc_options"}) {
                push(@CompilerOpts, @{$SysCInfo->{"gcc_options"}});
            }
            if($SysInfo->{$LSName}{"gcc_options"}) {
                push(@CompilerOpts, @{$SysInfo->{$LSName}{"gcc_options"}});
            }
            if(@CompilerOpts) {
                push(@Content, "<gcc_options>\n    ".join("\n    ", @CompilerOpts)."\n</gcc_options>");
            }
            if($SysDescriptor{"CrossPrefix"}) {
                push(@Content, "<cross_prefix>\n    ".$SysDescriptor{"CrossPrefix"}."\n</cross_prefix>");
            }
            writeFile($DPath, join("\n\n", @Content));
            $Success{$LRelPath}=1;
        }
    }
    printMsg("INFO", "Dumping ABIs:");
    my %DumpSuccess = ();
    my @Descriptors = cmd_find($SYS_DUMP_PATH."/descriptors","f","*.xml","1");
    foreach my $DPath (sort {lc($a) cmp lc($b)} @Descriptors)
    {
        my $DName = get_filename($DPath);
        my $LName = "";
        if($DName=~/\A(.+).xml\Z/) {
            $LName = $1;
        }
        else {
            next;
        }
        if(not is_target_lib($LName)
        and not is_target_lib($LibSoname{$LName})) {
            next;
        }
        $DPath = cut_path_prefix($DPath, $ORIG_DIR);
        my $ACC_dump = "perl $0 -binary";
        if($GroupByHeaders)
        { # header name is going here
            $ACC_dump .= " -l $LName";
        }
        else {
            $ACC_dump .= " -l ".parse_libname($LName, "name", $OStarget);
        }
        $ACC_dump .= " -dump \"$DPath\"";
        if($SystemRoot)
        {
            $ACC_dump .= " -relpath \"$SystemRoot\"";
            $ACC_dump .= " -sysroot \"$SystemRoot\"";
        }
        my $DumpPath = "$SYS_DUMP_PATH/abi_dumps/$LName.abi.".getAR_EXT($OSgroup);
        $ACC_dump .= " -dump-path \"$DumpPath\"";
        my $LogPath = "$SYS_DUMP_PATH/logs/$LName.txt";
        unlink($LogPath);
        $ACC_dump .= " -log-path \"$LogPath\"";
        if($CrossGcc) {
            $ACC_dump .= " -cross-gcc \"$CrossGcc\"";
        }
        if($CheckHeadersOnly) {
            $ACC_dump .= " -headers-only";
        }
        if($UseStaticLibs) {
            $ACC_dump .= " -static-libs";
        }
        if($GroupByHeaders) {
            $ACC_dump .= " -header $LName";
        }
        if($NoStdInc
        or $OStarget=~/windows|symbian/)
        { # 1. user-defined
          # 2. windows/minGW
          # 3. symbian/GCC
            $ACC_dump .= " -nostdinc";
        }
        if($Quiet)
        { # quiet mode
            $ACC_dump .= " -quiet";
        }
        if($LogMode eq "n") {
            $ACC_dump .= " -logging-mode n";
        }
        elsif($Quiet) {
            $ACC_dump .= " -logging-mode a";
        }
        if($Debug)
        { # debug mode
            $ACC_dump .= " -debug";
            printMsg("INFO", "$ACC_dump");
        }
        printMsg("INFO_C", "Dumping $LName: ");
        system($ACC_dump." 1>$TMP_DIR/null 2>$TMP_DIR/$LName.stderr");
        appendFile("$SYS_DUMP_PATH/logs/$LName.txt", "The ACC parameters:\n  $ACC_dump\n");
        if(-s "$TMP_DIR/$LName.stderr")
        {
            appendFile("$SYS_DUMP_PATH/logs/$LName.txt", readFile("$TMP_DIR/$LName.stderr"));
            if(get_CoreError($?>>8) eq "Invalid_Dump") {
                printMsg("INFO", "Empty");
            }
            else {
                printMsg("INFO", "Failed (\'$SYS_DUMP_PATH/logs/$LName.txt\')");
            }
        }
        elsif(not -f $DumpPath) {
            printMsg("INFO", "Failed (\'$SYS_DUMP_PATH/logs/$LName.txt\')");
        }
        else
        {
            $DumpSuccess{$LName}=1;
            printMsg("INFO", "Ok");
        }
    }
    if(not $GroupByHeaders)
    { # general mode
        printMsg("INFO", "Total libraries:         ".keys(%TotalLibs));
        printMsg("INFO", "Skipped libraries:       ".keys(%Skipped)." ($SYS_DUMP_PATH/skipped.txt)");
        printMsg("INFO", "Failed to find headers:  ".keys(%Failed)." ($SYS_DUMP_PATH/failed.txt)");
    }
    printMsg("INFO", "Created descriptors:     ".keys(%Success)." ($SYS_DUMP_PATH/descriptors/)");
    printMsg("INFO", "Dumped ABIs:             ".keys(%DumpSuccess)." ($SYS_DUMP_PATH/abi_dumps/)");
    printMsg("INFO", "The ".$SysDescriptor{"Name"}." system ABI has been dumped to:\n  $SYS_DUMP_PATH");
}

return 1;