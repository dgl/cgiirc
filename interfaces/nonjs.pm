package nonjs;
use strict;
use vars qw/@ISA/;

use default;
@ISA = qw/default/;

sub new {
   my($self,$event) = @_;
   return bless {};
}

sub _out {
   print "$_[0]<script>s();</script>\r\n";
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub header {
   my($self, $config, $cgi) = @_;
   print <<EOF;
<html><head>
<title>CGI:IRC</title>
<script><!--
function s() {
   window.scrollBy(0,2000);
}
function u() {
   parent.fuserlist.window.location = "$config->{script_form}?interface=$cgi->{interface}&R=$cgi->{R}&s=userlist";
}
function f() {
   parent.fform.window.location = "$config->{script_form}?interface=$cgi->{interface}&R=$cgi->{R}&s=form";
}
//-->
</script>
</head>
<body bgcolor="#ffffff" text="#000000">
EOF
}

sub line {
   my($self, $info, $html) = @_;
   my $target = $info->{target};
   $target ||= 'Status';
   if(not exists $self->{lc $target}) {
      if(defined $info && ref $info && exists $info->{create} &&
	    $info->{create}) {
	     $self->add($target, $info->{type} eq 'join' ? 1 : 0);
      }
   }
	  
   _out($html . '<br>');
}

sub add {
   my($self, $name, $param) = @_;
   $self->{lc $name} = $param;
   _out('<script>u();f();</script>');
}

sub error {
   my($self,$message) = @_;
   $self->line({ target => 'Status'}, $message);
}

sub frameset {
   my($self, $scriptname, $config, $random, $out, $interface) = @_;
print <<EOF;
<html>

<head>
<title>CGI:IRC</title>
</head>

<frameset rows="*,40" framespacing="0" border="0" frameborder="0">
<frameset cols="*,100" framespacing="0" border="0" frameborder="0">
<frame name="fmain" src="$config->{script_nph}?$out" scrolling="yes">
<frame name="fuserlist" src="$scriptname?item=fuserlist&interface=$interface&R=$random" scrolling="no">
</frameset>
<frame name="fform" src="$scriptname?item=fform&interface=$interface&R=$random" scrolling="no">
<noframes>
This interface requires a browser that supports frames such as internet
explorer, netscape or mozilla.
</noframes>

</frameset>
</html>
EOF
}

sub fuserlist {
   my($self, $cgi, $config) = @_;
print <<EOF;
<html><head>
<noscript><meta http-equiv="Refresh" content="15;URL=$config->{script_form}?R=$cgi->{R}&s=userlist"></noscript>
</head><body bgcolor="#ffffff" text="#000000">
Loading..
</body></html>
EOF
}

sub userlist {
   return 'moo';
}

sub fform {
   my($self, $cgi, $config) = @_;
   print _form_out($cgi->{R}, $config->{script_form}, []);
}

sub form {
   my($self, $cgi, $irc, $config) = @_;
   return _form_out($cgi->{R}, $config->{script_form}, [keys %$self]);
}

sub _form_out {
   my($rand, $script, $targets) = @_;
my $out = <<EOF;
<html>
<head>
<html><head>
<script><!--
function fns(){
   if(!document.myform["say"]) return;
   document.myform["say"].focus();
}
//-->
</script>
</head>
<body onload="fns()" onfocus="fns()" bgcolor="#ffffff" text="#000000">

<form name="myform" method="post" action="$script">
<input type="hidden" name="R" value="$rand">
<input type="hidden" name="s" value="form">
<input type="hidden" name="cmd" value="say">
<select name="target">
EOF
if(ref $targets eq 'ARRAY') {
   for(@$targets) {
      $out .= "<option>$_</option>\n";
   }
}
$out .= <<EOF;
</select>
<input type="text" class="say" name="say" autocomplete="off" size="60">
<input type="submit" value=" Say ">
</form>

</body>
</html>
EOF

return $out;
}

1;
