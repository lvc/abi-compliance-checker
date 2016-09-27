###########################################################################
# Module for ABI Compliance Checker to compare Operating Systems
#
# Copyright (C) 2009-2011 Institute for System Programming, RAS
# Copyright (C) 2011-2012 Nokia Corporation and/or its subsidiary(-ies)
# Copyright (C) 2011-2012 ROSA Laboratory
# Copyright (C) 2012-2016 Andrey Ponomarenko's ABI Laboratory
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
use Fcntl;

my ($Debug, $Quiet, $LogMode, $CheckHeadersOnly, $SystemRoot, $GCC_PATH,
$CrossPrefix, $TargetSysInfo, $TargetLibraryName, $CrossGcc, $UseStaticLibs,
$NoStdInc, $CxxIncompat, $SkipUnidentified, $OStarget, $BinaryOnly,
$SourceOnly, $DisableConstantsCheck);

my $OSgroup = get_OSgroup();
my $TMP_DIR = tempdir(CLEANUP=>1);
my $ORIG_DIR = cwd();
my $LIB_EXT = getLIB_EXT($OSgroup);

my %SysDescriptor;
my %Cache;
my %NonPrefix;

sub cmpSystems($$$)
{ # -cmp-systems option handler
  # should be used with -d1 and -d2 options
    my ($SPath1, $SPath2, $Opts) = @_;
    initModule($Opts);
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
    
    my $SystemName1_P = $SystemName1;
    my $SystemName2_P = $SystemName2;
    
    $SystemName1=~s/_/ /g;
    $SystemName2=~s/_/ /g;
    
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
    my $SYS_REPORT_PATH = "sys_compat_reports/".$SystemName1_P."_to_".$SystemName2_P."/$ArchName";
    rmtree($SYS_REPORT_PATH);
    my (%LibSoname1, %LibSoname2) = ();
    foreach (split(/\n/, readFile($SPath1."/sonames.txt")))
    {
        if(my ($LFName, $Soname) = split(/;/, $_))
        {
            if($OStarget eq "symbian") {
                $Soname=~s/\{.+\}//;
            }
            $LibSoname1{$LFName} = $Soname;
        }
    }
    foreach (split(/\n/, readFile($SPath2."/sonames.txt")))
    {
        if(my ($LFName, $Soname) = split(/;/, $_))
        {
            if($OStarget eq "symbian") {
                $Soname=~s/\{.+\}//;
            }
            $LibSoname2{$LFName} = $Soname;
        }
    }
    my (%LibV1, %LibV2) = ();
    foreach (split(/\n/, readFile($SPath1."/versions.txt")))
    {
        if(my ($LFName, $V) = split(/;/, $_)) {
            $LibV1{$LFName} = $V;
        }
    }
    foreach (split(/\n/, readFile($SPath2."/versions.txt")))
    {
        if(my ($LFName, $V) = split(/;/, $_)) {
            $LibV2{$LFName} = $V;
        }
    }
    my @Dumps1 = cmd_find($SPath1."/abi_dumps","f","*.abi",1);
    my @Dumps2 = cmd_find($SPath2."/abi_dumps","f","*.abi",1);
    
    my (%LibVers1, %LibVers2) = ();
    my (%ShortNames1, %ShortNames2) = ();
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
            $ShortNames1{parse_libname($Soname, "short", $OStarget)}{$Soname} = 1;
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
            $ShortNames2{parse_libname($Soname, "short", $OStarget)}{$Soname} = 1;
        }
    }
    my (%Added, %Removed) = ();
    my (%ChangedSoname, %TestResults) = ();
    my (%AddedShort, %RemovedShort) = ();
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
                    my $LSName = parse_libname($LName, "short", $OStarget);
                    $RemovedShort{$LSName}{$LName} = 1;
                    my $V = $Versions1[0];
                    $Removed{$LName}{"version"} = $V;
                    
                    my $ListPath = "info/$LName/symbols.html";
                    my $FV = $SystemName1;
                    if($V) {
                        $FV = $V."-".$FV;
                    }
                    createSymbolsList($LibVers1{$LName}{$V},
                    $SYS_REPORT_PATH."/".$ListPath, $LName, $FV, $ArchName);
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
                    my $LSName = parse_libname($LName, "short", $OStarget);
                    $AddedShort{$LSName}{$LName} = 1;
                    my $V = $Versions2[0];
                    $Added{$LName}{"version"} = $V;
                    
                    my $ListPath = "info/$LName/symbols.html";
                    my $FV = $SystemName2;
                    if($V) {
                        $FV = $V."-".$FV;
                    }
                    createSymbolsList($LibVers2{$LName}{$V},
                    $SYS_REPORT_PATH."/".$ListPath, $LName, $FV, $ArchName);
                    $Added{$LName}{"list"} = $ListPath;
                }
            }
        }
        foreach my $LSName (keys(%AddedShort))
        { # changed SONAME
            my @AddedSonames = sort keys(%{$AddedShort{$LSName}});
            next if($#AddedSonames!=0);
            
            if(defined $RemovedShort{$LSName})
            { # removed old soname
                my @RemovedSonames = sort keys(%{$RemovedShort{$LSName}});
                $ChangedSoname{$AddedSonames[0]} = $RemovedSonames[0];
                $ChangedSoname{$RemovedSonames[0]} = $AddedSonames[0];
            }
            elsif(defined $ShortNames1{$LSName})
            { # saved old soname
                my @Sonames = sort keys(%{$ShortNames1{$LSName}});
                $ChangedSoname{$AddedSonames[0]} = $Sonames[0];
                $ChangedSoname{$Sonames[0]} = $AddedSonames[0];
            }
        }
    }
    
    my %SONAME_Changed = ();
    my %SONAME_Added = ();
    
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
        my $LName_Short = parse_libname($LName, "name+ext", $OStarget);
        if($LName2 = $ChangedSoname{$LName})
        { # changed SONAME
            @Versions2 = keys(%{$LibVers2{$LName2}});
            if(not @Versions2 or $#Versions2>=1) {
                next;
            }
            $LV2 = $Versions2[0];
            $DPath2 = $LibVers2{$LName2}{$LV2};
            
            if(defined $LibVers2{$LName})
            { # show old soname in the table
                $TestResults{$LName}{"v1"} = $LV1;
                $TestResults{$LName}{"v2"} = $LV1;
            }
            
            if(defined $LibVers2{$LName})
            { # do not count results
                $SONAME_Added{$LName_Short} = 1;
            }
            $SONAME_Changed{$LName_Short} = 1;
            $LName = $LName_Short;
        }
        elsif(@Versions2)
        {
            $LV2 = $Versions2[0];
            $DPath2 = $LibVers2{$LName}{$LV2};
        }
        else
        { # removed
            next;
        }
        my $ACC_compare = "perl $0 -l $LName -d1 \"$DPath1\" -d2 \"$DPath2\"";
        
        my $BinReportPath = "compat_reports/$LName/abi_compat_report.html";
        my $SrcReportPath = "compat_reports/$LName/src_compat_report.html";
        my $BinReportPath_Full = $SYS_REPORT_PATH."/".$BinReportPath;
        my $SrcReportPath_Full = $SYS_REPORT_PATH."/".$SrcReportPath;
        
        if($BinaryOnly)
        {
            $ACC_compare .= " -binary";
            $ACC_compare .= " -bin-report-path \"$BinReportPath_Full\"";
        }
        if($SourceOnly)
        {
            $ACC_compare .= " -source";
            $ACC_compare .= " -src-report-path \"$SrcReportPath_Full\"";
        }
        
        if($CheckHeadersOnly) {
            $ACC_compare .= " -headers-only";
        }
        if($GroupByHeaders) {
            $ACC_compare .= " -component header";
        }
        
        if($DisableConstantsCheck) {
            $ACC_compare .= " -disable-constants-check";
        }
        
        $ACC_compare .= " -skip-added-constants";
        $ACC_compare .= " -skip-removed-constants";
        
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
            if($BinaryOnly)
            {
                $TestResults{$LName}{"Binary"} = readAttributes($BinReportPath_Full, 0);
                $TestResults{$LName}{"Binary"}{"path"} = $BinReportPath;
            }
            if($SourceOnly)
            {
                $TestResults{$LName}{"Source"} = readAttributes($SrcReportPath_Full, 0);
                $TestResults{$LName}{"Source"}{"path"} = $SrcReportPath;
            }
            $TestResults{$LName}{"v1"} = $LV1;
            $TestResults{$LName}{"v2"} = $LV2;
        }
        
        my $HP1 = $SPath1."/headers/".$LName;
        my $HP2 = $SPath2."/headers/".$LName;
        
        if(-d $HP1
        and -d $HP2
        and my $RfcDiff = get_CmdPath("rfcdiff"))
        {
            my @Headers1 = cmd_find($HP1,"f");
            my @Headers2 = cmd_find($HP2,"f");
            
            my (%Files1, %Files2) = ();
            
            foreach my $P (@Headers1) {
                $Files1{get_filename($P)} = $P;
            }
            
            foreach my $P (@Headers2) {
                $Files2{get_filename($P)} = $P;
            }
            
            my $Diff = "";
            foreach my $N (sort {lc($a) cmp lc($b)} keys(%Files1))
            {
                my $Path1 = $Files1{$N};
                my $Path2 = undef;
                
                if(defined $Files2{$N}) {
                    $Path2 = $Files2{$N};
                }
                else {
                    next;
                }
                
                if(-s $Path1 == -s $Path2)
                {
                    if(readFile($Path1) eq readFile($Path2)) {
                        next;
                    }
                }
                
                my $DiffOut = $TMP_DIR."/rfcdiff";
                
                if(-e $DiffOut) {
                    unlink($DiffOut);
                }
                
                my $Cmd_R = $RfcDiff." --width 80 --stdout \"$Path1\" \"$Path2\" >$DiffOut 2>/dev/null";
                qx/$Cmd_R/; # execute
                
                if(-s $DiffOut)
                {
                    my $Content = readFile($DiffOut);
                    if(length($Content)<3500 and $Content=~/The files are identical|No changes|Failed to create/i) {
                        next;
                    }
                    
                    $Content=~s/<\!--(.|\n)+?-->\s*//g;
                    $Content=~s/\A((.|\n)+<body\s*>)((.|\n)+)(<\/body>(.|\n)+)\Z/$3/;
                    $Content=~s/(<td colspan=\"5\"[^>]*>)(.+)(<\/td>)/$1$3/;
                    $Content=~s/(<table) /$1 class='diff_tbl' /g;
                    
                    $Content=~s&<td class="lineno" valign="top"></td>&&g;
                    $Content=~s&<td class="lineno"></td>&&g;
                    $Content=~s&<th></th>&&g;
                    $Content=~s&<td></td>&&g;
                    
                    $Content=~s/(\Q$N\E)(&nbsp;)/$1 ($LV1-$SystemName1)$2/;
                    $Content=~s/(\Q$N\E)(&nbsp;)/$1 ($LV2-$SystemName2)$2/;
                    
                    if($Diff) {
                        $Diff .= "<br/><br/>\n";
                    }
                    $Diff .= $Content;
                }
            }
            
            if($Diff)
            {
                my $Title = $LName.": headers diff between $LV1-$SystemName1 and $LV2-$SystemName2 versions";
                my $Keywords = $LName.", header, diff";
                my $Description = "Diff for header files between $LV1-$SystemName1 and $LV2-$SystemName2 versions of $LName";
                my $Styles = readModule("Styles", "HeadersDiff.css");
                
                my $Link = "This html diff was produced by <a href='http://tools.ietf.org/tools/rfcdiff/'>rfcdiff</a> 1.41.";
                
                $Diff .= "<br/>";
                $Diff .= "<div style='width:100%;' align='left'>$Link</div>\n";
                
                $Diff = "<h1>Headers diff for <span style='color:Blue;'>$LName</span> between <span style='color:Red;'>$LV1-$SystemName1</span> and <span style='color:Red;'>$LV2-$SystemName2</span> versions</h1><br/><br/>".$Diff;
                
                $Diff = "<table width='100%' cellpadding='0' cellspacing='0'><tr><td>$Diff</td></tr></table>";
                
                $Diff = composeHTML_Head($Title, $Keywords, $Description, $Styles, "")."\n<body>\n$Diff\n</body>\n</html>\n";
                
                my $Output = $SYS_REPORT_PATH."/headers_diff/$LName";
                writeFile($Output."/diff.html", $Diff);
            }
        }
    }
    
    my %TOTAL = ();
    foreach my $LName (keys(%TestResults))
    {
        if($SONAME_Changed{$LName}) {
            next;
        }
        foreach my $Comp ("Binary", "Source")
        {
            if(not defined $TestResults{$LName}{$Comp}) {
                next;
            }
            foreach my $Kind (keys(%{$TestResults{$LName}{$Comp}}))
            {
                if($Kind=~/_problems_(high|medium|low)/) {
                    $TOTAL{$LName}{$Comp} += $TestResults{$LName}{$Comp}{$Kind};
                }
            }
        }
    }
    
    my %META_DATA = ();
    my %STAT = ();
    foreach my $Comp ("Binary", "Source")
    {
        $STAT{$Comp}{"total"} = keys(%TestResults) - keys(%SONAME_Changed);
        $STAT{$Comp}{"added"} = keys(%Added);
        $STAT{$Comp}{"removed"} = keys(%Removed);
        
        foreach ("added", "removed")
        {
            my $Kind = $_."_interfaces";
            foreach my $LName (keys(%TestResults))
            {
                next if($SONAME_Changed{$LName});
                $STAT{$Comp}{$Kind} += $TestResults{$LName}{$Comp}{$_};
            }
            push(@{$META_DATA{$Comp}}, $Kind.":".$STAT{$Comp}{$Kind});
        }
        foreach my $T ("type", "interface")
        {
            foreach my $S ("high", "medium", "low")
            {
                my $Kind = $T."_problems_".$S;
                foreach my $LName (keys(%TestResults))
                {
                    next if($SONAME_Changed{$LName});
                    $STAT{$Comp}{$Kind} += $TestResults{$LName}{$Comp}{$Kind};
                }
                push(@{$META_DATA{$Comp}}, $Kind.":".$STAT{$Comp}{$Kind});
            }
        }
        foreach my $LName (keys(%TestResults))
        {
            next if($SONAME_Changed{$LName});
            foreach ("affected", "changed_constants") {
                $STAT{$Comp}{$_} += $TestResults{$LName}{$Comp}{$_};
            }
            if(not defined $STAT{$Comp}{"verdict"}
            and $TestResults{$LName}{$Comp}{"verdict"} eq "incompatible") {
                $STAT{$Comp}{"verdict"} = "incompatible";
            }
        }
        if(not defined $STAT{$Comp}{"verdict"}) {
            $STAT{$Comp}{"verdict"} = "compatible";
        }
        if($STAT{$Comp}{"total"}) {
            $STAT{$Comp}{"affected"} /= $STAT{$Comp}{"total"};
        }
        else {
            $STAT{$Comp}{"affected"} = 0;
        }
        $STAT{$Comp}{"affected"} = show_number($STAT{$Comp}{"affected"});
        if($STAT{$Comp}{"verdict"}>1) {
            $STAT{$Comp}{"verdict"} = 1;
        }
        push(@{$META_DATA{$Comp}}, "changed_constants:".$STAT{$Comp}{"changed_constants"});
        push(@{$META_DATA{$Comp}}, "tool_version:".get_dumpversion("perl $0"));
        foreach ("removed", "added", "total", "affected", "verdict") {
            @{$META_DATA{$Comp}} = ($_.":".$STAT{$Comp}{$_}, @{$META_DATA{$Comp}});
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
    
    my $SYS_REPORT = "<h1>";
    
    if($BinaryOnly and $SourceOnly) {
        $SYS_REPORT .= "API compatibility";
    }
    elsif($BinaryOnly) {
        $SYS_REPORT .= "Binary compatibility";
    }
    elsif($SourceOnly) {
        $SYS_REPORT .= "Source compatibility";
    }
    
    $SYS_REPORT .= " report between <span style='color:Blue;'>$SystemName1</span> and <span style='color:Blue;'>$SystemName2</span>";
    $SYS_REPORT .= " on <span style='color:Blue;'>".showArch($ArchName)."</span>\n";
    
    $SYS_REPORT .= "</h1>";
    $SYS_REPORT .= "<br/>\n";
    
    # legend
    my $LEGEND = "<table class='legend'><tr>\n";
    $LEGEND .= "<td class='new' width='70px' style='text-align:left'>ADDED</td>\n";
    $LEGEND .= "<td class='passed' width='70px' style='text-align:left'>COMPATIBLE</td>\n";
    $LEGEND .= "</tr><tr>\n";
    $LEGEND .= "<td class='warning' style='text-align:left'>WARNING</td>\n";
    $LEGEND .= "<td class='failed' style='text-align:left'>INCOMPATIBLE</td>\n";
    $LEGEND .= "</tr></table>\n";
    
    $SYS_REPORT .= $LEGEND;
    $SYS_REPORT .= "<br/>\n";
    
    my $Columns = 2;
    
    my $Total = (keys(%TestResults) + keys(%Added) + keys(%Removed) - keys(%SONAME_Changed));
    my $HDiff = $SYS_REPORT_PATH."/headers_diff";
    
    $SYS_REPORT .= "<table class='summary'>\n";
    $SYS_REPORT .= "<tr>\n";
    $SYS_REPORT .= "<th rowspan='2'>$SONAME_Title<sup>$Total</sup></th>\n";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<th colspan='2'>Version</th>\n";
    }
    if($BinaryOnly and $SourceOnly) {
        $SYS_REPORT .= "<th colspan='2'>Compatibility</th>\n";
    }
    else {
        $SYS_REPORT .= "<th rowspan='2'>Compatibility</th>\n";
    }
    $SYS_REPORT .= "<th rowspan='2'>Added<br/>Symbols</th>\n";
    $SYS_REPORT .= "<th rowspan='2'>Removed<br/>Symbols</th>\n";
    if(-d $HDiff)
    {
        $SYS_REPORT .= "<th rowspan='2'>Headers<br/>Diff</th>\n";
        $Columns += 1;
    }
    $SYS_REPORT .= "</tr>\n";
    
    $SYS_REPORT .= "<tr>\n";
    if(not $GroupByHeaders) {
        $SYS_REPORT .= "<th class='ver'>$SystemName1</th><th class='ver'>$SystemName2</th>\n";
    }
    if($BinaryOnly and $SourceOnly) {
        $SYS_REPORT .= "<th>Binary</th><th>Source</th>\n";
    }
    $SYS_REPORT .= "</tr>\n";
    my %RegisteredPairs = ();
    
    foreach my $LName (sort {lc($a) cmp lc($b)} (keys(%TestResults), keys(%Added), keys(%Removed)))
    {
        next if($SONAME_Changed{$LName});
        my $LName_Short = parse_libname($LName, "name+ext", $OStarget);
        my $Anchor = $LName;
        $Anchor=~s/\+/p/g; # anchor for libFLAC++ is libFLACpp
        $Anchor=~s/\~/-/g; # libqttracker.so.1~6
        
        $SYS_REPORT .= "<tr>\n";
        $SYS_REPORT .= "<td class='object'>$LName<a name=\'$Anchor\'></a></td>\n";
        if(defined $Removed{$LName}) {
            $SYS_REPORT .= "<td class='failed ver'>".printVer($Removed{$LName}{"version"})."</td>\n";
        }
        elsif(defined $Added{$LName}) {
            $SYS_REPORT .= "<td class='new'><a href='".$Added{$LName}{"list"}."'>added</a></td>\n";
        }
        elsif(not $GroupByHeaders)
        {
            $SYS_REPORT .= "<td class='ver'>".printVer($TestResults{$LName}{"v1"})."</td>\n";
        }
        my $SONAME_report = "<td colspan=\'$Columns\' rowspan='2'>\n";
        if($BinaryOnly and $SourceOnly) {
            $SONAME_report .= "SONAME has been changed (see <a href='".$TestResults{$LName_Short}{"Binary"}{"path"}."'>binary</a> and <a href='".$TestResults{$LName_Short}{"Source"}{"path"}."'>source</a> compatibility reports)\n";
        }
        elsif($BinaryOnly) {
            $SONAME_report .= "SONAME has been <a href='".$TestResults{$LName_Short}{"Binary"}{"path"}."'>changed</a>\n";
        }
        elsif($SourceOnly) {
            $SONAME_report .= "SONAME has been <a href='".$TestResults{$LName_Short}{"Source"}{"path"}."'>changed</a>\n";
        }
        $SONAME_report .= "</td>\n";
        
        if(defined $Added{$LName})
        { # added library
            $SYS_REPORT .= "<td class='new ver'>".printVer($Added{$LName}{"version"})."</td>\n";
            $SYS_REPORT .= "<td class='passed'>100%</td>\n" if($BinaryOnly);
            $SYS_REPORT .= "<td class='passed'>100%</td>\n" if($SourceOnly);
            if($RegisteredPairs{$LName}) {
                # do nothing
            }
            elsif(my $To = $ChangedSoname{$LName})
            {
                $RegisteredPairs{$To}=1;
                $SYS_REPORT .= $SONAME_report;
            }
            else
            {
                foreach (1 .. $Columns) {
                    $SYS_REPORT .= "<td>N/A</td>\n"; # colspan='5'
                }
            }
            $SYS_REPORT .= "</tr>\n";
            next;
        }
        elsif(defined $Removed{$LName})
        { # removed library
            $SYS_REPORT .= "<td class='failed'><a href='".$Removed{$LName}{"list"}."'>removed</a></td>\n";
            $SYS_REPORT .= "<td class='failed'>0%</td>\n" if($BinaryOnly);
            $SYS_REPORT .= "<td class='failed'>0%</td>\n" if($SourceOnly);
            if($RegisteredPairs{$LName}) {
                # do nothing
            }
            elsif(my $To = $ChangedSoname{$LName})
            {
                $RegisteredPairs{$To}=1;
                $SYS_REPORT .= $SONAME_report;
            }
            else
            {
                foreach (1 .. $Columns) {
                    $SYS_REPORT .= "<td>N/A</td>\n"; # colspan='5'
                }
            }
            $SYS_REPORT .= "</tr>\n";
            next;
        }
        elsif(defined $ChangedSoname{$LName})
        { # added library
            $SYS_REPORT .= "<td class='ver'>".printVer($TestResults{$LName}{"v2"})."</td>\n";
            $SYS_REPORT .= "<td class='passed'>100%</td>\n" if($BinaryOnly);
            $SYS_REPORT .= "<td class='passed'>100%</td>\n" if($SourceOnly);
            if($RegisteredPairs{$LName}) {
                # do nothing
            }
            elsif(my $To = $ChangedSoname{$LName})
            {
                $RegisteredPairs{$To}=1;
                $SYS_REPORT .= $SONAME_report;
            }
            else
            {
                foreach (1 .. $Columns) {
                    $SYS_REPORT .= "<td>N/A</td>\n"; # colspan='5'
                }
            }
            $SYS_REPORT .= "</tr>\n";
            next;
        }
        elsif(not $GroupByHeaders)
        {
            $SYS_REPORT .= "<td class='ver'>".printVer($TestResults{$LName}{"v2"})."</td>\n";
        }
        
        my $BinCompatReport = $TestResults{$LName}{"Binary"}{"path"};
        my $SrcCompatReport = $TestResults{$LName}{"Source"}{"path"};
        
        if($BinaryOnly)
        {
            if($TestResults{$LName}{"Binary"}{"verdict"} eq "compatible")
            {
                my $Cl = "passed";
                if($TOTAL{$LName}{"Binary"}) {
                    $Cl = "warning";
                }
                $SYS_REPORT .= "<td class=\'$Cl\'><a href=\'$BinCompatReport\'>100%</a></td>\n";
            }
            else
            {
                my $Compatible = 100 - $TestResults{$LName}{"Binary"}{"affected"};
                my $Cl = "incompatible";
                if($Compatible>=90) {
                    $Cl = "warning";
                }
                elsif($Compatible>=80) {
                    $Cl = "almost_compatible";
                }
                $SYS_REPORT .= "<td class=\'$Cl\'><a href=\'$BinCompatReport\'>$Compatible%</a></td>\n";
            }
        }
        if($SourceOnly)
        {
            if($TestResults{$LName}{"Source"}{"verdict"} eq "compatible")
            {
                my $Cl = "passed";
                if($TOTAL{$LName}{"Source"}) {
                    $Cl = "warning";
                }
                $SYS_REPORT .= "<td class=\'$Cl\'><a href=\'$SrcCompatReport\'>100%</a></td>\n";
            }
            else
            {
                my $Compatible = 100 - $TestResults{$LName}{"Source"}{"affected"};
                my $Cl = "incompatible";
                if($Compatible>=90) {
                    $Cl = "warning";
                }
                elsif($Compatible>=80) {
                    $Cl = "almost_compatible";
                }
                $SYS_REPORT .= "<td class=\'$Cl\'><a href=\'$SrcCompatReport\'>$Compatible%</a></td>\n";
            }
        }
        if($BinaryOnly)
        { # show added/removed symbols at binary level
          # for joined and -binary-only reports
            my $AddedSym="";
            if(my $Count = $TestResults{$LName}{"Binary"}{"added"}) {
                $AddedSym="<a href='$BinCompatReport\#Added'>$Count new</a>";
            }
            if($AddedSym) {
                $SYS_REPORT.="<td class='new'>$AddedSym</td>\n";
            }
            else {
                $SYS_REPORT.="<td class='passed'>0</td>\n";
            }
            my $RemovedSym="";
            if(my $Count = $TestResults{$LName}{"Binary"}{"removed"}) {
                $RemovedSym="<a href='$BinCompatReport\#Removed'>$Count removed</a>";
            }
            if($RemovedSym) {
                $SYS_REPORT.="<td class='failed'>$RemovedSym</td>\n";
            }
            else {
                $SYS_REPORT.="<td class='passed'>0</td>\n";
            }
        }
        elsif($SourceOnly)
        {
            my $AddedSym="";
            if(my $Count = $TestResults{$LName}{"Source"}{"added"}) {
                $AddedSym="<a href='$SrcCompatReport\#Added'>$Count new</a>";
            }
            if($AddedSym) {
                $SYS_REPORT.="<td class='new'>$AddedSym</td>\n";
            }
            else {
                $SYS_REPORT.="<td class='passed'>0</td>\n";
            }
            my $RemovedSym="";
            if(my $Count = $TestResults{$LName}{"Source"}{"removed"}) {
                $RemovedSym="<a href='$SrcCompatReport\#Removed'>$Count removed</a>";
            }
            if($RemovedSym) {
                $SYS_REPORT.="<td class='failed'>$RemovedSym</td>\n";
            }
            else {
                $SYS_REPORT.="<td class='passed'>0</td>\n";
            }
        }
        
        if(-d $HDiff)
        {
            if(-d $HDiff."/".$LName) {
                $SYS_REPORT .= "<td><a href=\'headers_diff/$LName/diff.html\'>diff</a></td>\n";
            }
            elsif(defined $Added{$LName} or defined $Removed{$LName}) {
                $SYS_REPORT .= "<td>N/A</td>\n";
            }
            else {
                $SYS_REPORT .= "<td>Empty</td>\n";
            }
        }
        
        $SYS_REPORT .= "</tr>\n";
    }
    
    $SYS_REPORT .= "</table>";
    
    my $Title = "$SystemName1 vs $SystemName2 compatibility report";
    my $Keywords = "compatibility, $SystemName1, $SystemName2, API, changes";
    my $Description = "API compatibility report between $SystemName1 and $SystemName2 on ".showArch($ArchName);
    my $Styles = readModule("Styles", "CmpSystems.css");
    
    $SYS_REPORT = composeHTML_Head($Title, $Keywords, $Description, $Styles, "")."\n<body>\n<div>".$SYS_REPORT."</div>\n";
    $SYS_REPORT .= "<br/><br/>\n";
    $SYS_REPORT .= getReportFooter();
    $SYS_REPORT .= "</body></html>\n";
    
    if($SourceOnly) {
        $SYS_REPORT = "<!-\- kind:source;".join(";", @{$META_DATA{"Source"}})." -\->\n".$SYS_REPORT;
    }
    if($BinaryOnly) {
        $SYS_REPORT = "<!-\- kind:binary;".join(";", @{$META_DATA{"Binary"}})." -\->\n".$SYS_REPORT;
    }
    my $REPORT_PATH = $SYS_REPORT_PATH."/";
    if($BinaryOnly and $SourceOnly) {
        $REPORT_PATH .= "compat_report.html";
    }
    elsif($BinaryOnly) {
        $REPORT_PATH .= "abi_compat_report.html";
    }
    elsif($SourceOnly) {
        $REPORT_PATH .= "src_compat_report.html";
    }
    writeFile($REPORT_PATH, $SYS_REPORT);
    printMsg("INFO", "\nSee detailed report:\n  $REPORT_PATH");
}

sub printVer($)
{
    if($_[0] eq "") {
        return 0;
    }
    return $_[0];
}

sub getPrefix_S($)
{
    my $Prefix = getPrefix($_[0]);
    if(not $Prefix or defined $NonPrefix{lc($Prefix)}) {
        return "NONE";
    }
    return $Prefix;
}

sub problem_title($)
{
    if($_[0]==1)  {
        return "1 change";
    }
    else  {
        return $_[0]." changes";
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
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"Libs"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_libs")))
    { # target libs
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"SearchLibs"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_libs")))
    { # skip libs
        $SysDescriptor{"SkipLibs"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "headers")))
    {
        if(not -e $Path) {
            exitStatus("Access_Error", "can't access \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"Headers"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "search_headers")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"SearchHeaders"}{$Path} = 1;
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "tools")))
    {
        if(not -d $Path) {
            exitStatus("Access_Error", "can't access directory \'$Path\'");
        }
        $Path = get_abs_path($Path);
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"Tools"}{$Path} = 1;
        push(@Tools, $Path);
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "gcc_options")))
    {
        $Path=~s/[\/\\]+\Z//g;
        $SysDescriptor{"GccOpts"}{$Path} = 1;
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

sub initModule($)
{
    my $S = $_[0];
    
    $OStarget = $S->{"OStarget"};
    $Debug = $S->{"Debug"};
    $Quiet = $S->{"Quiet"};
    $LogMode = $S->{"LogMode"};
    $CheckHeadersOnly = $S->{"CheckHeadersOnly"};
    
    $SystemRoot = $S->{"SystemRoot"};
    $GCC_PATH = $S->{"GCC_PATH"};
    $TargetSysInfo = $S->{"TargetSysInfo"};
    $CrossPrefix = $S->{"CrossPrefix"};
    $TargetLibraryName = $S->{"TargetLibraryName"};
    $CrossGcc = $S->{"CrossGcc"};
    $UseStaticLibs = $S->{"UseStaticLibs"};
    $NoStdInc = $S->{"NoStdInc"};
    $CxxIncompat = $S->{"CxxIncompat"};
    $SkipUnidentified = $S->{"SkipUnidentified"};
    $DisableConstantsCheck = $S->{"DisableConstantsCheck"};
    
    $BinaryOnly = $S->{"BinaryOnly"};
    $SourceOnly = $S->{"SourceOnly"};
    
    if(not $BinaryOnly and not $SourceOnly)
    { # default
        $BinaryOnly = 1;
    }
}

sub check_list($$)
{
    my ($Item, $Skip) = @_;
    return 0 if(not $Skip);
    foreach (@{$Skip})
    {
        my $Pattern = $_;
        if(index($Pattern, "*")!=-1)
        { # wildcards
            $Pattern=~s/\*/.*/g; # to perl format
            if($Item=~/$Pattern/) {
                return 1;
            }
        }
        elsif(index($Pattern, "/")!=-1
        or index($Pattern, "\\")!=-1)
        { # directory
            if(index($Item, $Pattern)!=-1) {
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

sub readSysDescriptor($)
{
    my $Path = $_[0];
    my $Content = readFile($Path);
    my %Tags = (
        "headers" => "mf",
        "skip_headers" => "mf",
        "skip_including" => "mf",
        "skip_include_paths" => "mf",
        "skip_libs" => "mf",
        "include_preamble" => "mf",
        "add_include_paths" => "mf",
        "gcc_options" => "m",
        "skip_symbols" => "m",
        "skip_types" => "m",
        "ignore_symbols" => "h",
        "non_prefix" => "h",
        "defines" => "s",
        "cxx_incompatible" => "s"
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
    
    if(defined $DInfo{"non_self_compiled"})
    { # support for old ABI dumps
        $DInfo{"skip_including"} = $DInfo{"non_self_compiled"};
    }
    
    return \%DInfo;
}

sub readSysInfo($)
{
    my $Target = $_[0];
    
    if(not $TargetSysInfo) {
        exitStatus("Error", "system info path is not specified");
    }
    if(not -d $TargetSysInfo) {
        exitStatus("Module_Error", "can't access \'$TargetSysInfo\'");
    }
    # Library Specific Info
    my %SysInfo = ();
    if(-d $TargetSysInfo."/descriptors/")
    {
        foreach my $DPath (cmd_find($TargetSysInfo."/descriptors/","f","",1))
        {
            my $LSName = get_filename($DPath);
            $LSName=~s/\.xml\Z//;
            $SysInfo{$LSName} = readSysDescriptor($DPath);
        }
    }
    else {
        printMsg("WARNING", "can't find \'$TargetSysInfo/descriptors\'");
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
    
    # Common Info
    my $SysCInfo = {};
    if(-f $TargetSysInfo."/common.xml") {
        $SysCInfo = readSysDescriptor($TargetSysInfo."/common.xml");
    }
    else {
        printMsg("Module_Error", "can't find \'$TargetSysInfo/common.xml\'");
    }
    
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
        my $VInfo = `$SigcheckCmd -nobanner -n $Path 2>$TMP_DIR/null`;
        $VInfo=~s/\s*\(.*\)\s*//;
        chomp($VInfo);
        
        if($VInfo eq "n/a") {
            $VInfo = uc($VInfo);
        }
        
        return $VInfo;
    }
    return "";
}

sub readBytes($)
{
    sysopen(FILE, $_[0], O_RDONLY);
    sysread(FILE, my $Header, 4);
    close(FILE);
    my @Bytes = map { sprintf('%02x', ord($_)) } split (//, $Header);
    return join("", @Bytes);
}

sub dumpSystem($)
{ # -dump-system option handler
  # should be used with -sysroot and -cross-gcc options
    my $Opts = $_[0];
    initModule($Opts);
    
    my $SysName_P = $SysDescriptor{"Name"};
    $SysName_P=~s/ /_/g;
    
    my $SYS_DUMP_PATH = "sys_dumps/".$SysName_P."/".getArch(1);
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
    %SysHeader_Symbols, %SysLib_SysHeaders) = ();
    my (%Skipped, %Failed) = ();
    my (%SysHeaderDir_Used, %SysHeaderDir_SysHeaders) = ();
    my (%SymbolCounter, %TotalLibs) = ();
    my (%PrefixToLib, %LibPrefix, %PrefixSymbols) = ();
    
    my %Glibc = map {$_=>1} (
        "libc",
        "libpthread"
    );
    my ($SysInfo, $SysCInfo) = readSysInfo($OStarget);
    
    foreach (keys(%{$SysCInfo->{"non_prefix"}}))
    {
        $NonPrefix{$_} = 1;
        $NonPrefix{$_."_"} = 1;
        $NonPrefix{"_".$_} = 1;
        $NonPrefix{"_".$_."_"} = 1;
    }
    
    if(not $GroupByHeaders)
    {
        if($Debug) {
            printMsg("INFO", localtime(time));
        }
        printMsg("INFO", "Indexing sonames ...\n");
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
        if(not is_target_lib($LName)) {
            next;
        }
        if($OSgroup=~/\A(linux|macos|freebsd)\Z/
        and $LName!~/\Alib/) {
            next;
        }
        if(my $Soname = getSONAME($LPath))
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
            if(-l $LPath and my $Path = realpath_F($LPath))
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
        elsif(my $SV = parse_libname(getSONAME($LPath), "version", $OStarget))
        { # soname version
            $SysLibVersion{$LName} = $SV;
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
    
    # create target list
    my @SkipLibs = keys(%{$SysDescriptor{"SkipLibs"}});
    if(my $CSkip = $SysCInfo->{"skip_libs"}) {
        push(@SkipLibs, @{$CSkip});
    }
    if(@SkipLibs and not $TargetLibraryName)
    {
        my %SkipLibs = map {$_ => 1} @SkipLibs;
        my @Target = ();
        foreach my $LPath (@SystemLibs)
        {
            my $LName = get_filename($LPath);
            my $LName_Short = parse_libname($LName, "name+ext", $OStarget);
            if(not defined $SkipLibs{$LName_Short}
            and not defined $SkipLibs{$LName}
            and not check_list($LPath, \@SkipLibs)) {
                push(@Target, $LName);
            }
        }
        add_target_libs(\@Target);
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
        if(-l $LPath)
        { # symlinks
            if(my $Path = realpath_F($LPath)) {
                $SysLibs{$Path} = 1;
            }
        }
        elsif(-f $LPath)
        {
            if($Glibc{$LSName}
            and cmd_file($LPath)=~/ASCII/)
            { # GNU ld scripts (libc.so, libpthread.so)
                my @Candidates = cmd_find($SystemRoot."/lib","",$LSName.".".$LIB_EXT."*","1");
                if(@Candidates)
                {
                    my $Candidate = $Candidates[0];
                    if(-l $Candidate
                    and my $Path = realpath_F($Candidate)) {
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
    @SystemLibs = (); # clear memory
    
    if(not keys(%SysLibs)) {
        exitStatus("Error", "can't find libraries");
    }
    
    if(not $CheckHeadersOnly)
    {
        if($Debug) {
            printMsg("INFO", localtime(time));
        }
        if($SysDescriptor{"Image"}) {
            printMsg("INFO", "Reading symbols from image ...\n");
        }
        else {
            printMsg("INFO", "Reading symbols from libraries ...\n");
        }
    }
    
    my %Syms = ();
    my @AllSyms = {};
    my %ShortestNames = ();
    
    foreach my $LPath (sort {lc($a) cmp lc($b)} keys(%SysLibs))
    {
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        my $LName = get_filename($LPath);
        
        $ShortestNames{$LPath} = parse_libname($LName, "shortest", $OStarget);
        
        my $Res = readSymbols_Lib(1, $LPath, 0, "-Weak", 0, 0);
        
        if(not keys(%{$Res}) and $TargetLibraryName) {
            exitStatus("Error", "can't find exported symbols in the library");
        }
        
        $Syms{$LPath} = $Res->{$LName};
        push(@AllSyms, keys(%{$Syms{$LPath}}));
    }
    
    my $Translate = translateSymbols(@AllSyms, 1);
    
    my %DupSymbols = ();
    
    foreach my $LPath (sort {lc($a) cmp lc($b)} keys(%SysLibs))
    {
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        my $LName = get_filename($LPath);
        foreach my $Symbol (keys(%{$Syms{$LPath}}))
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
                my $Unmangled = $Translate->{$Symbol};
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
                        $SysLib_Symbols{$LPath}{$Sym} = 1;
                        if(my $Prefix = getPrefix_S($Sym))
                        {
                            $PrefixToLib{$Prefix}{$LName} += 1;
                            $LibPrefix{$LPath}{$Prefix} += 1;
                            $PrefixSymbols{$LPath}{$Prefix}{$Sym} = 1;
                        }
                        $SymbolCounter{$Sym}{$LPath} = 1;
                        
                        if(my @Libs = keys(%{$SymbolCounter{$Sym}}))
                        {
                            if($#Libs>=1)
                            {
                                foreach (@Libs) {
                                    $DupSymbols{$_}{$Sym} = 1;
                                }
                            }
                        }
                    }
                }
            }
            else
            {
                if($SysCInfo->{"ignore_symbols"}{$Symbol})
                { # do NOT match this symbol
                    next;
                }
                $SysLib_Symbols{$LPath}{$Symbol} = 1;
                if(my $Prefix = getPrefix_S($Symbol))
                {
                    $PrefixToLib{$Prefix}{$LName} += 1;
                    $LibPrefix{$LPath}{$Prefix} += 1;
                    $PrefixSymbols{$LPath}{$Prefix}{$Symbol} = 1;
                }
                $SymbolCounter{$Symbol}{$LPath} = 1;
                
                if(my @Libs = keys(%{$SymbolCounter{$Symbol}}))
                {
                    if($#Libs>=1)
                    {
                        foreach (@Libs) {
                            $DupSymbols{$_}{$Symbol} = 1;
                        }
                    }
                }
            }
        }
    }
    
    %Syms = ();
    %{$Translate} = ();
    
    # remove minor symbols
    foreach my $LPath (keys(%SysLib_Symbols))
    {
        my $SName = $ShortestNames{$LPath};
        my $Count = keys(%{$SysLib_Symbols{$LPath}});
        my %Prefixes = %{$LibPrefix{$LPath}};
        my @Prefixes = sort {$Prefixes{$b}<=>$Prefixes{$a}} keys(%Prefixes);
        
        if($#Prefixes>=1)
        {
            my $MaxPrefix = $Prefixes[0];
            if($MaxPrefix eq "NONE") {
                $MaxPrefix = $Prefixes[1];
            }
            my $Max = $Prefixes{$MaxPrefix};
            my $None = $Prefixes{"NONE"};
            
            next if($None*100/$Count>=50);
            next if($None>=$Max);
            
            foreach my $Prefix (@Prefixes)
            {
                next if($Prefix eq $MaxPrefix);
                my $Num = $Prefixes{$Prefix};
                my $Rm = 0;
                
                if($Prefix eq "NONE") {
                    $Rm = 1;
                }
                else
                {
                    if($Num*100/$Max<5) {
                        $Rm = 1;
                    }
                }
                
                if($Rm)
                {
                    next if($Prefix=~/\Q$MaxPrefix\E/i);
                    next if($MaxPrefix=~/\Q$Prefix\E/i);
                    next if($Prefix=~/\Q$SName\E/i);
                    
                    foreach my $Symbol (keys(%{$PrefixSymbols{$LPath}{$Prefix}})) {
                        delete($SysLib_Symbols{$LPath}{$Symbol});
                    }
                }
            }
        }
    }
    
    %PrefixSymbols = (); # free memory
    
    if(not $CheckHeadersOnly) {
        writeFile($SYS_DUMP_PATH."/debug/symbols.txt", Dumper(\%SysLib_Symbols));
    }
    
    my (%DupLibs, %VersionedLibs) = ();
    foreach my $LPath (sort keys(%DupSymbols))
    { # match duplicated libs
      # libmenu contains all symbols from libmenuw
        my @Syms = keys(%{$SysLib_Symbols{$LPath}});
        next if($#Syms==-1);
        if($#Syms+1==keys(%{$DupSymbols{$LPath}})) {
            $DupLibs{$LPath} = 1;
        }
    }
    foreach my $Prefix (keys(%PrefixToLib))
    {
        my @Libs = keys(%{$PrefixToLib{$Prefix}});
        @Libs = sort {$PrefixToLib{$Prefix}{$b}<=>$PrefixToLib{$Prefix}{$a}} @Libs;
        $PrefixToLib{$Prefix} = $Libs[0];
    }
    
    my %PackageFile = (); # to improve results
    my %FilePackage = ();
    my %LibraryFile = ();
    
    if(0)
    {
        if($Debug) {
            printMsg("INFO", localtime(time));
        }
        printMsg("INFO", "Reading info from packages ...\n");
        if(my $Urpmf = get_CmdPath("urpmf"))
        { # Mandriva, ROSA
            my $Out = $TMP_DIR."/urpmf.out";
            system("urpmf : >\"$Out\"");
            open(FILE, $Out);
            while(<FILE>)
            {
                chomp($_);
                if(my $M = index($_, ":"))
                {
                    my $Pkg = substr($_, 0, $M);
                    my $File = substr($_, $M+1);
                    $PackageFile{$Pkg}{$File} = 1;
                    $FilePackage{$File} = $Pkg;
                }
            }
            close(FILE);
        }
    }
    
    if(keys(%FilePackage))
    {
        foreach my $LPath (sort {lc($a) cmp lc($b)} keys(%SysLibs))
        {
            my $LName = get_filename($LPath);
            my $LDir = get_dirname($LPath);
            my $LName_Short = parse_libname($LName, "name+ext", $OStarget);
            
            my $Pkg = $FilePackage{$LDir."/".$LName_Short};
            if(not $Pkg)
            {
                my $RPkg = $FilePackage{$LPath};
                if(defined $PackageFile{$RPkg."-devel"}) {
                    $Pkg = $RPkg."-devel";
                }
                if($RPkg=~s/[\d\.]+\Z//g)
                {
                    if(defined $PackageFile{$RPkg."-devel"}) {
                        $Pkg = $RPkg."-devel";
                    }
                }
            }
            if($Pkg)
            {
                foreach (keys(%{$PackageFile{$Pkg}}))
                {
                    if(index($_, "/usr/include/")==0) {
                        $LibraryFile{$LPath}{$_} = 1;
                    }
                }
            }
            
            $LName_Short=~s/\.so\Z/.a/;
            if($Pkg = $FilePackage{$LDir."/".$LName_Short})
            { # headers for static library
                foreach (keys(%{$PackageFile{$Pkg}}))
                {
                    if(index($_, "/usr/include/")==0) {
                        $LibraryFile{$LPath}{$_} = 1;
                    }
                }
            }
        }
    }
    
    my %HeaderFile_Path = ();
    
    if($Debug) {
        printMsg("INFO", localtime(time));
    }
    printMsg("INFO", "Reading symbols from headers ...\n");
    foreach my $HPath (@SysHeaders)
    {
        $HPath = path_format($HPath, $OSgroup);
        if(readBytes($HPath) eq "7f454c46")
        { # skip ELF files
            next;
        }
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
        if(index($HRelPath, "/_gen")!=-1)
        { # telepathy-1.0/telepathy-glib/_gen
          # telepathy-1.0/libtelepathy/_gen-tp-constants-deprecated.h
            next;
        }
        if(index($HRelPath, "include/linux/")!=-1)
        { # kernel-space headers
            next;
        }
        if(index($HRelPath, "include/asm/")!=-1)
        { # asm headers
            next;
        }
        if(index($HRelPath, "/microb-engine/")!=-1)
        { # MicroB engine (Maemo 4)
            next;
        }
        if($HRelPath=~/\Wprivate(\W|\Z)/)
        { # private directories (include/tcl-private, ...)
            next;
        }
        if(index($HRelPath, "/lib/")!=-1)
        {
            if(not is_header_file($HName))
            { # without or with a wrong extension
              # under the /lib directory
                next;
            }
        }
        my $Content = readFile($HPath);
        $Content=~s/\/\*(.|\n)+?\*\///g;
        $Content=~s/\/\/.*?\n//g; # remove comments
        $Content=~s/#\s*define[^\n\\]*(\\\n[^\n\\]*)+\n*//g; # remove defines
        $Content=~s/#[^\n]*?\n//g; # remove directives
        $Content=~s/(\A|\n)class\s+\w+;\n//g; # remove forward declarations
        # FIXME: try to add preprocessing stage
        foreach my $Symbol (split(/\W+/, $Content))
        {
            next if(not $Symbol);
            $Symbol_SysHeaders{$Symbol}{$HRelPath} = 1;
            $SysHeader_Symbols{$HRelPath}{$Symbol} = 1;
        }
        $SysHeaderDir_SysHeaders{$HDir}{$HName} = 1;
        $HeaderFile_Path{get_filename($HRelPath)}{$HRelPath} = 1;
    }
    
    # writeFile($SYS_DUMP_PATH."/debug/headers.txt", Dumper(\%SysHeader_Symbols));
    
    my %SkipDHeaders = (
    # header files, that should be in the <skip_headers> section
    # but should be matched in the algorithm
        # MeeGo 1.2 Harmattan
        "libtelepathy-qt4" => ["TelepathyQt4/_gen", "client.h",
                        "TelepathyQt4/*-*", "debug.h", "global.h",
                        "properties.h", "Channel", "channel.h", "message.h"],
    );
    filter_format(\%SkipDHeaders);
    if(not $GroupByHeaders)
    {
        if($Debug) {
            printMsg("INFO", localtime(time));
        }
        printMsg("INFO", "Matching symbols ...\n");
    }
    
    foreach my $LPath (sort {lc($a) cmp lc($b)} keys(%SysLibs))
    { # matching
        my $LName = get_filename($LPath);
    }
    
    foreach my $LPath (sort {lc($a) cmp lc($b)} keys(%SysLibs))
    { # matching
        my $LName = get_filename($LPath);
        my $LName_Short = parse_libname($LName, "name", $OStarget);
        my $LRelPath = cut_path_prefix($LPath, $SystemRoot);
        my $LSName = parse_libname($LName, "short", $OStarget);
        my $SName = $ShortestNames{$LPath};
        
        my @TryNames = (); # libX-N.so.M
        
        if(my $Ver = $SysLibVersion{$LName})
        { # libX-N-M
            if($LSName."-".$Ver ne $LName_Short)
            {
                push(@TryNames, $LName_Short."-".$Ver);
                #while($Ver=~s/\.\d+\Z//) { # partial versions
                #    push(@TryNames, $LName_Short."-".$Ver);
                #}
            }
        }
        push(@TryNames, $LName_Short); # libX-N
        if($LSName ne $LName_Short)
        { # libX
            push(@TryNames, $LSName);
        }
        
        if($LRelPath=~/\/debug\//)
        { # debug libs
            $Skipped{$LRelPath} = 1;
            next;
        }
        $TotalLibs{$LRelPath} = 1;
        $SysLib_SysHeaders{$LRelPath} = ();
        
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
            and my $Prefix = getPrefix_S($Symbol))
            { # duplicated symbols
                if($PrefixToLib{$Prefix}
                and $PrefixToLib{$Prefix} ne $LName
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
            @SymHeaders = sort {lc($a) cmp lc($b)} @SymHeaders; # sort by name
            @SymHeaders = sort {length(get_dirname($a))<=>length(get_dirname($b))} @SymHeaders; # sort by length
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
                my $HDir = get_dirname($HRelPath);
                my $HName = get_filename($HRelPath);
                
                if(my $Group = $SymbolGroup{$LRelPath}{$Symbol})
                {
                    if(not $SysHeader_Symbols{$HRelPath}{$Group}) {
                        next;
                    }
                }
                my $Filter = 0;
                foreach (@TryNames)
                {
                    if(my $Filt = $SysInfo->{$_}{"headers"})
                    { # search for specified headers
                        if(not check_list($HRelPath, $Filt))
                        {
                            $Filter = 1;
                            last;
                        }
                    }
                    if(my $Filt = $SysInfo->{$_}{"skip_headers"})
                    { # do NOT search for some headers
                        if(check_list($HRelPath, $Filt))
                        {
                            $Filter = 1;
                            last;
                        }
                    }
                    if(my $Filt = $SysInfo->{$_}{"skip_including"})
                    { # do NOT search for some headers
                        if(check_list($HRelPath, $Filt))
                        {
                            $SymbolDirs{$HDir}+=1;
                            $SymbolFiles{$HName}+=1;
                            $Filter = 1;
                            last;
                        }
                    }
                }
                if($Filter) {
                    next;
                }
                if(my $Filt = $SysCInfo->{"skip_headers"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Filt)) {
                        next;
                    }
                }
                if(my $Filt = $SysCInfo->{"skip_including"})
                { # do NOT search for some headers
                    if(check_list($HRelPath, $Filt)) {
                        next;
                    }
                }
                
                if(defined $LibraryFile{$LRelPath})
                { # skip wrongly matched headers
                    if(not defined $LibraryFile{$LRelPath}{$HRelPath})
                    { print "WRONG: $LRelPath $HRelPath\n";
                        # next;
                    }
                }
                
                $SysLib_SysHeaders{$LRelPath}{$HRelPath} = $Symbol;
                
                $SysHeaderDir_Used{$HDir}{$LName_Short} = 1;
                $SysHeaderDir_Used{get_dirname($HDir)}{$LName_Short} = 1;
                
                $SymbolDirs{$HDir} += 1;
                $SymbolFiles{$HName} +=1 ;
                
                # select one header for one symbol
                last;
            }
        }
        
        if(keys(%{$SysLib_Symbols{$LPath}})
        and not $SysInfo->{$_}{"headers"})
        { # try to match by name of the header
            if(length($SName)>=3)
            {
                my @Paths = ();
                foreach my $Path (keys(%{$HeaderFile_Path{$SName.".h"}}), keys(%{$HeaderFile_Path{$LSName.".h"}}))
                {
                    my $Dir = get_dirname($Path);
                    if(defined $SymbolDirs{$Dir} or $Dir eq "/usr/include") {
                        push(@Paths, $Path);
                    }
                }
                if($#Paths==0)
                {
                    my $Path = $Paths[0];
                    if(not defined $SysLib_SysHeaders{$LRelPath}{$Path}) {
                        $SysLib_SysHeaders{$LRelPath}{$Path} = "by name ($LSName)";
                    }
                }
            }
        }
        
        if(not keys(%{$SysLib_SysHeaders{$LRelPath}}))
        {
            foreach (@TryNames)
            {
                if(my $List = $SysInfo->{$_}{"headers"})
                {
                    foreach my $HName (@{$List})
                    {
                        next if($HName=~/[\*\/\\]/);
                        if(my $HPath = selectSystemHeader($HName, 1))
                        {
                            my $HRelPath = cut_path_prefix($HPath, $SystemRoot);
                            $SysLib_SysHeaders{$LRelPath}{$HRelPath} = "by descriptor";
                        }
                    }
                }
            }
        }
        
        if(not keys(%{$SysLib_SysHeaders{$LRelPath}})) {
            $Failed{$LRelPath} = 1;
        }
    }
    
    if(not $GroupByHeaders)
    { # matching results
        writeFile($SYS_DUMP_PATH."/debug/match.txt", Dumper(\%SysLib_SysHeaders));
        writeFile($SYS_DUMP_PATH."/debug/skipped.txt", join("\n", sort keys(%Skipped)));
        writeFile($SYS_DUMP_PATH."/debug/failed.txt", join("\n", sort keys(%Failed)));
    }
    (%SysLib_Symbols, %SymbolGroup, %Symbol_SysHeaders, %SysHeader_Symbols) = (); # free memory
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
    @SysHeaders = (); # clear memory
    
    if($Debug) {
        printMsg("INFO", localtime(time));
    }
    printMsg("INFO", "Generating XML descriptors ...");
    my %Generated = ();
    my %CxxIncompat_L = ();
    foreach my $LRelPath (keys(%SysLib_SysHeaders))
    {
        my $LName = get_filename($LRelPath);
        my $DPath = $SYS_DUMP_PATH."/descriptors/$LName.xml";
        unlink($DPath);
        if(my @LibHeaders = keys(%{$SysLib_SysHeaders{$LRelPath}}))
        {
            my $LSName = parse_libname($LName, "short", $OStarget);
            my $LName_Short = parse_libname($LName, "name", $OStarget);
            my $LName_Shortest = parse_libname($LName, "shortest", $OStarget);
            if($GroupByHeaders)
            { # header short name
                $LSName = $LName;
                $LSName=~s/\.(.+?)\Z//;
            }
            
            my (%DirsHeaders, %Includes, %MainDirs) = ();
            foreach my $HRelPath (@LibHeaders)
            {
                my $Dir = get_dirname($HRelPath);
                $DirsHeaders{$Dir}{$HRelPath} = 1;
                
                if($Dir=~/\/\Q$LName_Shortest\E(\/|\Z)/i
                or $Dir=~/\/\Q$LName_Short\E(\/|\Z)/i)
                {
                    if(get_filename($Dir) ne "include")
                    { # except /usr/include
                        $MainDirs{$Dir} += 1;
                    }
                }
            }
            
            if($#LibHeaders==0)
            { # one header at all
                $Includes{$LibHeaders[0]} = 1;
            }
            else
            {
                foreach my $Dir (keys(%DirsHeaders))
                {
                    if(keys(%MainDirs) and not defined $MainDirs{$Dir})
                    { # search in /X/ dir for libX headers
                        if(get_filename($Dir) ne "include")
                        { # except /usr/include
                            next;
                        }
                    }
                    my $DirPart = 0;
                    my $TotalHeaders = keys(%{$SysHeaderDir_SysHeaders{$Dir}});
                    if($TotalHeaders) {
                        $DirPart = (keys(%{$DirsHeaders{$Dir}})*100)/$TotalHeaders;
                    }
                    my $Neighbourhoods = keys(%{$SysHeaderDir_Used{$Dir}});
                    if($Neighbourhoods==1)
                    { # one lib in this directory
                        if(get_filename($Dir) ne "include"
                        and $DirPart>=5)
                        { # complete directory
                            $Includes{$Dir} = 1;
                        }
                        else
                        { # list of headers
                            foreach (keys(%{$DirsHeaders{$Dir}})) {
                                $Includes{$_} = 1;
                            }
                        }
                    }
                    elsif((keys(%{$DirsHeaders{$Dir}})*100)/($#LibHeaders+1)>5)
                    { # remove 5% divergence
                        if(get_filename($Dir) ne "include"
                        and $DirPart>=50)
                        { # complete directory if more than 50%
                            $Includes{$Dir} = 1;
                        }
                        else
                        { # list of headers
                            foreach (keys(%{$DirsHeaders{$Dir}})) {
                                $Includes{$_} = 1;
                            }
                        }
                    }
                    else
                    { # noise
                        foreach (keys(%{$DirsHeaders{$Dir}}))
                        { # NOTE: /usr/include/libX.h
                            if(/\Q$LName_Shortest\E/i) {
                                $Includes{$_} = 1;
                            }
                        }
                    }
                }
            }
            if($GroupByHeaders)
            { # one header in one ABI dump
                %Includes = ($LibHeaders[0] => 1);
            }
            my $LVersion = $SysLibVersion{$LName};
            if($LVersion)
            { # append by system name
                $LVersion .= "-".$SysDescriptor{"Name"};
            }
            else {
                $LVersion = $SysDescriptor{"Name"};
            }
            my @Content = ("<version>\n    $LVersion\n</version>");
            
            my @IncHeaders = sort keys(%Includes);
            
            # sort files up
            @IncHeaders = sort {$b=~/\.h\Z/<=>$a=~/\.h\Z/} @IncHeaders;
            
            # sort by name
            @IncHeaders = sort {sortHeaders($a, $b)} @IncHeaders;
            
            # sort by library name
            sortByWord(\@IncHeaders, parse_libname($LName, "shortest", $OStarget));
            
            if(is_abs($IncHeaders[0]) or -f $IncHeaders[0]) {
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
            
            # system
            if(my @SearchHeaders = sort keys(%{$SysDescriptor{"SearchHeaders"}})) {
                push(@Content, "<search_headers>\n    ".join("\n    ", @SearchHeaders)."\n</search_headers>");
            }
            if(my @SearchLibs = sort keys(%{$SysDescriptor{"SearchLibs"}})) {
                push(@Content, "<search_libs>\n    ".join("\n    ", @SearchLibs)."\n</search_libs>");
            }
            if(my @Tools = sort keys(%{$SysDescriptor{"Tools"}})) {
                push(@Content, "<tools>\n    ".join("\n    ", @Tools)."\n</tools>");
            }
            if(my $Prefix = $SysDescriptor{"CrossPrefix"}) {
                push(@Content, "<cross_prefix>\n    $Prefix\n</cross_prefix>");
            }
            
            # library
            my (@Skip, @SkipInc, @AddIncPath, @SkipIncPath,
            @SkipTypes, @SkipSymb, @Preamble, @Defines, @CompilerOpts) = ();
            
            my @TryNames = ();
            if(my $Ver = $SysLibVersion{$LName})
            {
                if($LSName."-".$Ver ne $LName_Short) {
                    push(@TryNames, $LName_Short."-".$Ver);
                }
            }
            push(@TryNames, $LName_Short);
            if($LSName ne $LName_Short) {
                push(@TryNames, $LSName);
            }
            
            # common
            if(my $List = $SysCInfo->{"include_preamble"}) {
                push(@Preamble, @{$List});
            }
            if(my $List = $SysCInfo->{"skip_headers"}) {
                @Skip = (@Skip, @{$List});
            }
            if(my $List = $SysCInfo->{"skip_including"}) {
                @SkipInc = (@SkipInc, @{$List});
            }
            if(my $List = $SysCInfo->{"skip_symbols"}) {
                push(@SkipSymb, @{$List});
            }
            if(my $List = $SysCInfo->{"gcc_options"}) {
                push(@CompilerOpts, @{$List});
            }
            if($SysCInfo->{"defines"}) {
                push(@Defines, $SysCInfo->{"defines"});
            }
            
            # particular
            foreach (@TryNames)
            {
                if(my $List = $SysInfo->{$_}{"include_preamble"}) {
                    push(@Preamble, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"skip_headers"}) {
                    @Skip = (@Skip, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"skip_including"}) {
                    @SkipInc = (@SkipInc, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"add_include_paths"}) {
                    @AddIncPath = (@AddIncPath, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"skip_include_paths"}) {
                    @SkipIncPath = (@SkipIncPath, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"skip_symbols"}) {
                    push(@SkipSymb, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"skip_types"}) {
                    @SkipTypes = (@SkipTypes, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"gcc_options"}) {
                    push(@CompilerOpts, @{$List});
                }
                if(my $List = $SysInfo->{$_}{"defines"}) {
                    push(@Defines, $List);
                }
                if($SysInfo->{$_}{"cxx_incompatible"}) {
                    $CxxIncompat_L{$LName} = 1;
                }
            }
            
            # common other
            if($LSName=~/\AlibX\w+\Z/)
            { # add Xlib.h for libXt, libXaw, libXext and others
                push(@Preamble, "Xlib.h", "X11/Intrinsic.h");
            }
            if($SkipDHeaders{$LSName}) {
                @SkipInc = (@SkipInc, @{$SkipDHeaders{$LSName}});
            }
            if($SysDescriptor{"Defines"}) {
                push(@Defines, $SysDescriptor{"Defines"});
            }
            
            # add sections
            if(@Preamble) {
                push(@Content, "<include_preamble>\n    ".join("\n    ", @Preamble)."\n</include_preamble>");
            }
            if(@Skip) {
                push(@Content, "<skip_headers>\n    ".join("\n    ", @Skip)."\n</skip_headers>");
            }
            if(@SkipInc) {
                push(@Content, "<skip_including>\n    ".join("\n    ", @SkipInc)."\n</skip_including>");
            }
            if(@AddIncPath) {
                push(@Content, "<add_include_paths>\n    ".join("\n    ", @AddIncPath)."\n</add_include_paths>");
            }
            if(@SkipIncPath) {
                push(@Content, "<skip_include_paths>\n    ".join("\n    ", @SkipIncPath)."\n</skip_include_paths>");
            }
            if(@SkipSymb) {
                push(@Content, "<skip_symbols>\n    ".join("\n    ", @SkipSymb)."\n</skip_symbols>");
            }
            if(@SkipTypes) {
                push(@Content, "<skip_types>\n    ".join("\n    ", @SkipTypes)."\n</skip_types>");
            }
            if(@CompilerOpts) {
                push(@Content, "<gcc_options>\n    ".join("\n    ", @CompilerOpts)."\n</gcc_options>");
            }
            if(@Defines) {
                push(@Content, "<defines>\n    ".join("\n    ", @Defines)."\n</defines>");
            }
            
            writeFile($DPath, join("\n\n", @Content));
            $Generated{$LRelPath} = 1;
            
            # save header files to create visual diff later
            my $HSDir = $SYS_DUMP_PATH."/headers/".$LName;
            rmtree($HSDir);
            mkpath($HSDir);
            foreach my $H_P (@IncHeaders)
            {
                if(-f $H_P) {
                    copy($H_P, $HSDir);
                }
            }
        }
    }
    printMsg("INFO", "Created descriptors:     ".keys(%Generated)." ($SYS_DUMP_PATH/descriptors/)\n");
    
    if($Debug) {
        printMsg("INFO", localtime(time));
    }
    printMsg("INFO", "Dumping ABIs:");
    my %Dumped = ();
    my @Descriptors = cmd_find($SYS_DUMP_PATH."/descriptors","f","*.xml","1");
    if(-d $SYS_DUMP_PATH."/descriptors" and $#Descriptors==-1) {
        printMsg("ERROR", "internal problem with \'find\' utility");
    }
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
        my $ACC_dump = "perl $0";
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
        my $DumpPath = "$SYS_DUMP_PATH/abi_dumps/$LName.abi";
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
        if($CxxIncompat or $CxxIncompat_L{$LName}) {
            $ACC_dump .= " -cxx-incompatible";
        }
        if($SkipUnidentified) {
            $ACC_dump .= " -skip-unidentified";
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
        my $ErrCode = $?;
        appendFile("$SYS_DUMP_PATH/logs/$LName.txt", "The ACC parameters:\n  $ACC_dump\n");
        my $ErrCont = readFile("$TMP_DIR/$LName.stderr");
        if($ErrCont) {
            appendFile("$SYS_DUMP_PATH/logs/$LName.txt", $ErrCont);
        }
        
        if(filterError($ErrCont))
        {
            if(get_CodeError($ErrCode>>8) eq "Invalid_Dump") {
                printMsg("INFO", "Empty");
            }
            else {
                printMsg("INFO", "Errors (\'$SYS_DUMP_PATH/logs/$LName.txt\')");
            }
        }
        elsif(not -f $DumpPath) {
            printMsg("INFO", "Failed (\'$SYS_DUMP_PATH/logs/$LName.txt\')");
        }
        else
        {
            $Dumped{$LName}=1;
            printMsg("INFO", "Ok");
        }
    }
    printMsg("INFO", "\n");
    if(not $GroupByHeaders)
    { # general mode
        printMsg("INFO", "Total libraries:         ".keys(%TotalLibs));
        printMsg("INFO", "Skipped libraries:       ".keys(%Skipped)." ($SYS_DUMP_PATH/skipped.txt)");
        printMsg("INFO", "Failed to find headers:  ".keys(%Failed)." ($SYS_DUMP_PATH/failed.txt)");
    }
    printMsg("INFO", "Dumped ABIs:             ".keys(%Dumped)." ($SYS_DUMP_PATH/abi_dumps/)");
    printMsg("INFO", "The ".$SysDescriptor{"Name"}." system ABI has been dumped to:\n  $SYS_DUMP_PATH");
}

sub filterError($)
{
    my $Error = $_[0];
    
    if(not $Error) {
        return undef;
    }
    
    my @Err = ();
    foreach my $L (split(/\n/, $Error))
    {
        if($L!~/warning:/) {
            push(@Err, $L);
        }
    }
    
    return join("\n", @Err);
}

return 1;
