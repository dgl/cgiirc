package opera;
use strict;
use vars qw/@ISA $standardheader/;

$standardheader = <<EOF;
<!-- This is part of CGI:IRC 0.5
  == http://cgiirc.sourceforge.net/
  == Copyright (C) 2000-2002 David Leadbeater <cgiirc\@dgl.cx>
  == Released under the GNU GPL
  -->
EOF

use nonjs;
@ISA = qw/nonjs/;

sub _out {
   print "$_[1]\r\n";
}

sub header {
   my($self, $config, $cgi) = @_;
   print <<EOF;
$standardheader
<html><head>
<script language="JavaScript"><!--
// opera scrolling fix - thanks to Helge Laurisch
scrolling=true;
function moves() {
   if (scrolling != false) {
      s();
   }
   window.setTimeout('moves()', 100);
}
moves();

function s() {
   window.scrollBy(1, 50000);
}
function u() {
   parent.fuserlist.window.location = "$config->{script_form}?interface=$cgi->{interface}&R=$cgi->{R}&item=userlist";
}
function f() {
   parent.fform.window.location = "$config->{script_form}?interface=$cgi->{interface}&R=$cgi->{R}&item=form";
}
//-->
</script>
</head>
<body bgcolor="#ffffff" text="#000000" 
onfocus="scrolling=true" onblur="scrolling=false" onmouseover="scrolling=true"
onmouseout="scrolling=false">
EOF
}

1;
