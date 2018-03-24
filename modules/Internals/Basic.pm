###########################################################################
# A module with simple functions
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
use Config;
use Fcntl;

my %Cache;

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

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    
    if(my $Dir = getDirname($Path)) {
        mkpath($Dir);
    }
    
    open(FILE, ">>", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    
    if(my $Dir = getDirname($Path)) {
        mkpath($Dir);
    }
    
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    
    open(FILE, $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    
    if($Path!~/\.(tu|class|abi)\Z/) {
        $Content=~s/\r/\n/g;
    }
    
    return $Content;
}

sub getFilename($)
{ # much faster than basename() from File::Basename module
    if(defined $Cache{"getFilename"}{$_[0]}) {
        return $Cache{"getFilename"}{$_[0]};
    }
    if($_[0] and $_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return ($Cache{"getFilename"}{$_[0]}=$1);
    }
    return ($Cache{"getFilename"}{$_[0]}="");
}

sub getDirname($)
{ # much faster than dirname() from File::Basename module
    if(defined $Cache{"getDirname"}{$_[0]}) {
        return $Cache{"getDirname"}{$_[0]};
    }
    if($_[0] and $_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return ($Cache{"getDirname"}{$_[0]}=$1);
    }
    return ($Cache{"getDirname"}{$_[0]}="");
}

sub sepPath($) {
    return (getDirname($_[0]), getFilename($_[0]));
}

sub escapeArg($)
{
    my $Str = $_[0];
    $Str=~s/([()\[\]{}$ &'"`;,<>\+])/\\$1/g;
    return $Str;
}

sub readLineNum($$)
{
    my ($Path, $Num) = @_;
    
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

sub isAbsPath($) {
    return ($_[0]=~/\A(\/|\w+:[\/\\])/);
}

sub specChars($)
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
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    return $Str;
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

sub getDepth($)
{
    if(defined $Cache{"getDepth"}{$_[0]}) {
        return $Cache{"getDepth"}{$_[0]};
    }
    return ($Cache{"getDepth"}{$_[0]} = ($_[0]=~tr![\/\\]|\:\:!!));
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

sub isDump($)
{
    if(getFilename($_[0])=~/\A(.+)\.(abi|abidump|dump)((\.tar\.gz|\.tgz)(\.\w+|)|\.zip|\.xml|)\Z/)
    { # NOTE: name.abi.tar.gz.amd64 (dh & cdbs)
        return $1;
    }
    return 0;
}

sub isDump_U($)
{
    if(getFilename($_[0])=~/\A(.+)\.(abi|abidump|dump)(\.xml|)\Z/) {
        return $1;
    }
    return 0;
}

sub cutPrefix($$)
{
    my ($Path, $Prefix) = @_;
    if(not $Prefix) {
        return $Path;
    }
    $Prefix=~s/[\/\\]+\Z//;
    $Path=~s/\A\Q$Prefix\E([\/\\]+|\Z)//;
    return $Path;
}

sub sortByWord($$)
{
    my ($ArrRef, $W) = @_;
    if(length($W)<2) {
        return;
    }
    @{$ArrRef} = sort {getFilename($b)=~/\Q$W\E/i<=>getFilename($a)=~/\Q$W\E/i} @{$ArrRef};
}

sub showPos($)
{
    my $N = $_[0];
    if(not $N) {
        $N = 1;
    }
    else {
        $N = int($N)+1;
    }
    if($N>3) {
        return $N."th";
    }
    elsif($N==1) {
        return "1st";
    }
    elsif($N==2) {
        return "2nd";
    }
    elsif($N==3) {
        return "3rd";
    }
    
    return $N;
}

sub isCyclical($$)
{
    my ($Stack, $Value) = @_;
    return (grep {$_ eq $Value} @{$Stack});
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

sub formatVersion($$)
{ # cut off version digits
    my ($V, $Digits) = @_;
    my @Elems = split(/\./, $V);
    return join(".", splice(@Elems, 0, $Digits));
}

sub showNum($)
{
    if($_[0])
    {
        my $Num = cutNum($_[0], 2, 0);
        if($Num eq "0")
        {
            foreach my $P (3 .. 7)
            {
                $Num = cutNum($_[0], $P, 1);
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

sub cutNum($$$)
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

sub isBuiltIn($) {
    return ($_[0] and $_[0]=~/\<built\-in\>|\<internal\>|\A\./);
}

sub checkWin32Env()
{
    if(not $ENV{"VCINSTALLDIR"}
    or not $ENV{"INCLUDE"}) {
        exitStatus("Error", "can't start without VC environment (vcvars64.bat)");
    }
}

sub symbolParts($)
{
    my $S = $_[0];
    
    if(index($S, '@')==-1
    and index($S, '$')==-1) {
        return ($S, "", "");
    }
    
    if($S=~/\A([^\@\$\?]+)([\@\$]+)([^\@\$]+)\Z/) {
        return ($1, $2, $3);
    }
    
    return ($S, "", "");
}

sub getOSgroup()
{
    my $N = $Config{"osname"};
    my $G = undef;
    
    if($N=~/macos|darwin|rhapsody/i) {
        $G = "macos";
    }
    elsif($N=~/freebsd|openbsd|netbsd/i) {
        $G = "bsd";
    }
    elsif($N=~/haiku|beos/i) {
        $G = "beos";
    }
    elsif($N=~/symbian|epoc/i) {
        $G = "symbian";
    }
    elsif($N=~/win/i) {
        $G = "windows";
    }
    elsif($N=~/solaris/i) {
        $G = "solaris";
    }
    else
    { # linux, unix-like
        $G = "linux";
    }
    
    return $G;
}

sub getLibExt($$)
{
    my ($Target, $Static) = @_;
    
    my $LType = "dynamic";
    
    if($Static) {
        $LType = "static";
    }
    
    if(my $Ex = $OS_LibExt{$LType}{$Target}) {
        return $Ex;
    }
    return $OS_LibExt{$LType}{"default"};
}

sub isAnon($)
{ # "._N" or "$_N" in older GCC versions
    return ($_[0] and $_[0]=~/(\.|\$)\_\d+|anon\-/);
}

sub checkCmd($)
{
    my $Cmd = $_[0];

    foreach my $Path (sort {length($a)<=>length($b)} split(/:/, $ENV{"PATH"}))
    {
        if(-x $Path."/".$Cmd) {
            return 1;
        }
    }

    return 0;
}

sub checkList($$)
{
    my ($Item, $Skip) = @_;
    if(not $Skip) {
        return 0;
    }
    foreach my $P (@{$Skip})
    {
        my $Pattern = $P;
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
        or getFilename($Item) eq $Pattern)
        { # by name
            return 1;
        }
    }
    return 0;
}

sub getArExt($)
{
    my $Target = $_[0];
    if($Target eq "windows") {
        return "zip";
    }
    return "tar.gz";
}

sub cutAttrs($)
{
    if($_[0]=~s/(\))((| (const volatile|const|volatile))(| \[static\]))\Z/$1/) {
        return $2;
    }
    return "";
}

sub splitSignature($)
{
    my $Signature = $_[0];
    if(my $ShortName = substr($Signature, 0, findCenter($Signature, "(")))
    {
        $Signature=~s/\A\Q$ShortName\E\(//g;
        cutAttrs($Signature);
        $Signature=~s/\)\Z//;
        return ($ShortName, $Signature);
    }
    
    # error
    return ($Signature, "");
}

sub sepParams($$$)
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

sub findCenter($$)
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

sub deleteKeywords($)
{
    my $TypeName = $_[0];
    $TypeName=~s/\b(enum|struct|union|class) //g;
    return $TypeName;
}

sub readBytes($)
{
    sysopen(FILE, $_[0], O_RDONLY);
    sysread(FILE, my $Header, 4);
    close(FILE);
    my @Bytes = map { sprintf('%02x', ord($_)) } split (//, $Header);
    return join("", @Bytes);
}

sub isElf($)
{
    my $Path = $_[0];
    return (readBytes($Path) eq "7f454c46");
}

return 1;
