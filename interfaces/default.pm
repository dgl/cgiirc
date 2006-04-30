package default;
use vars qw/$standardheader/;
use strict;
$standardheader = <<EOF;
<!-- This is part of CGI:IRC 0.5
  == http://cgiirc.sourceforge.net/
  == Copyright (C) 2000-2005 David Leadbeater <cgiirc\@dgl.cx>
  == Released under the GNU GPL
  -->
EOF

sub new {
   return bless {};
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub makeline {
   my($self, $type, $target, $html) = @_;
   return "$html<br>\n";
}

sub lines {
   my($self, @lines);
   unless(print @lines) {
      $::needtodie++;
   }
}

sub header {
   print "\n";
}

sub keepalive {
   unless(print "<!-- nothing comment -->\r\n") {
      $::needtodie++;
   }
}

sub error {
   my($self, $error) = @_;
   $self->line({}, '', $error);
}

sub form { 'DUMMY' }

sub add { 'DUMMY' }

sub del { 'DUMMY' }

sub clear { 'DUMMY' }

sub end { 'DUMMY' }

sub options { 'DUMMY' }

sub setoption { 'DUMMY' }

# not supported by default interface
sub ctcpping { 0 }
sub ping { 0 }

sub login {
   my($self, $this, $interface, $copy, $config, $order, $items, $adv) = @_;
   my $notsupported = 0;
   # Seems to work on Safari 2 (WebKit >=4xx):
   # http://developer.apple.com/internet/safari/uamatrix.html
   if ($ENV{HTTP_USER_AGENT} =~ /konqueror.2|Mozilla\/4.\d+ \[|OmniWeb|Safari\/(\d{2}|[1-3]\d{2})(\D|$)|Mozilla\/4.\d+ .*Mac_PowerPC/i) {
      $notsupported++;
   }

print <<EOF;
$standardheader
<html>
<head>
<link rel="SHORTCUT ICON" href="$config->{image_path}/favicon.ico">
<script language="JavaScript"><!--
EOF
if($interface eq 'default') {
print <<EOF;
function setjs() {
 if(navigator.product == 'Gecko') {
   document.loginform["interface"].value = 'mozilla';
 }else if(window.opera && document.childNodes) {
   document.loginform["interface"].value = 'opera7';
 }else if(navigator.appName == 'Microsoft Internet Explorer' &&
    navigator.userAgent.indexOf("Mac_PowerPC") > 0) {
    document.loginform["interface"].value = 'konqueror';
 }else if(navigator.appName == 'Microsoft Internet Explorer' &&
 document.getElementById && document.getElementById('ietest').innerHTML) {
   document.loginform["interface"].value = 'ie';
 }else if(navigator.appName == 'Konqueror') {
    document.loginform["interface"].value = 'konqueror';
 }else if(window.opera) {
   document.loginform["interface"].value = 'opera';
 }
}
EOF
}else{ # dummy functions
print <<EOF;
function setjs() {
   return true;
}
EOF
}
print <<EOF;
function setcharset() {
	if(document.charset && document.loginform["Character set"])
		document.loginform['Character set'].value = document.charset
}
//-->
</script>
<title>CGI:IRC Login</title>
</head>
<body bgcolor="#ffffff" text="#000000" onload="setcharset();">
EOF
if($notsupported) {
	print "<font size=\"+1\" color=\"red\">This web-based IRC interface probably won't work well or at all with your browser.</font>\n<br /><b>You could try a <a href=\"http://irchelp.org\">non web-based IRC client</a> or a browser such as <a href=\"http://www.getfirefox.com/\">Mozilla Firefox</a>.</b><br /><br />\n";
}
print <<EOF;
<form method="post" action="$this" name="loginform" onsubmit="setjs()">
EOF
print "<input type=\"hidden\" name=\"interface\" value=\"" . 
   ($interface eq 'default' ? 'nonjs' : $interface) . "\">\n";
print <<EOF;
<table border="0" cellpadding="5" cellspacing="0">
<tr><td colspan="2" align="center" bgcolor="#c0c0dd"><b>CGI:IRC
Login</b></td></tr>
EOF
for(@$order) {
   my $item = $$items{$_};
   next unless defined $item;
   print "<tr><td align=\"right\" bgcolor=\"#f1f1f1\">$_</td><td align=\"left\"
bgcolor=\"#f1f1f1\">";
   if(ref $item eq 'ARRAY') {
      print "<select name=\"$_\" style=\"width: 100%\">";
      print "<option>$_</option>" for @$item;
      print "</select>";
   }elsif($item eq '-PASSWORD-') {
      print "<input type=\"password\" name=\"$_\" value=\"\">";
   }else{
      my $tmp = '';
      if($item =~ s/^-DISABLED- //) {
         $tmp = " disabled=\"1\"";
      }
      print "<input type=\"text\" name=\"$_\" value=\"$item\"$tmp>";
   }
   print "</td></tr>\n";
}
print <<EOF;
<tr><td align="left" bgcolor="#d9d9d9">
EOF
if($adv) {
   print <<EOF;
<small><a href="$this?adv=1">Advanced..</a></small>
EOF
}
print <<EOF;
</td><td align="right" bgcolor="#d9d9d9">
<input type="submit" value="Login" style="background-color: #d9d9d9">
</td></tr></table></form>

<small id="ietest">$copy</small>
</body></html>
EOF
}

1;
