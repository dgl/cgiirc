package nonjs;
use strict;
use vars qw/@ISA/;

use default;
@ISA = qw/default/;

sub new {
   my($class,$event,$timer) = @_;
   my $self = bless {}, $class;
   $timer->addforever(code => \&todo, data => $self, interval => 10);
   return $self;
}

sub _out {
   print "$_[0]<script>s();</script>\r\n";
}

sub _reloadreal {
   my($w) = @_;
   print "<script>$w();</script>\r\n";
}

sub _escape {
   my($in) = @_;
   $in =~ s/</&lt;/g;
   $in =~ s/>/&gt;/g;
   $in =~ s/"/&quot;/g;
   return $in;
}

sub reload {
   my($self, $w) = @_;
   $self->{_reload} = $w;
}

sub todo {
   my($timer, $self) = @_;
   if(defined $self->{_reload} && $self->{_reload}) {
	  _reloadreal($self->{_reload});
      delete($self->{_reload});
   }
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub query {
   return 0;
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
   }elsif($info->{type} eq 'join') {
      $self->reload('u');
   }
	  
   _out($html . '<br>');
}

sub add {
   my($self, $name, $param) = @_;
   $self->{_target} ||= $name;
   $self->{lc $name} = $param;
   _out('<script>u();f();</script>');
}

sub active {
   my($self, $name) = @_;
   $self->{_target} = $name;
   $self->reload('f');
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

<frameset rows="*,50" framespacing="0" border="0" frameborder="0">
<frameset cols="*,120" framespacing="0" border="0" frameborder="0">
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

sub _page {
   return '<html><head></head><body bgcolor="#ffffff" text="#000000">' . $_[0]
   . "</body></html>\r\n";
}

sub userlist {
   my($self, $input, $irc, $config) = @_;
   if(!defined $self->{_target} || !$irc->is_channel($self->{_target})) {
      return _page('No channel');
   }

   my $channel = $irc->channel($self->{_target});
   return _page('No channel') unless ref $channel;

   my $output = 'Users in <b>' . _escape($channel->{name}) . '</b><br>';

   my @users = map($channel->get_umode($_) . $_, $channel->nicks);
   my $umap = '@%+ ';

   for(sort { # (I think this is clever :-)
        my($am,$bm) = (substr($a, 0, 1), substr($b, 0, 1));
		return $a cmp $b if ($am eq $bm);
		return index($umap, $am) <=> index($umap, $bm);
      } @users) {
	  $output .= "$_<br>";
   }

   return _page($output);
}

sub fform {
   my($self, $cgi, $config) = @_;
   print _form_out($cgi->{R}, $config->{script_form}, undef, []);
}

sub form {
   my($self, $cgi, $irc, $config) = @_;
   if(defined $cgi->{target} && $cgi->{target}) {
      $self->{_target} = $cgi->{target};
   }
   return _form_out($cgi->{R}, $config->{script_form}, $self->{_target}, [keys %$self]);
}

sub _form_out {
   my($rand, $script, $target, $targets) = @_;
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
      next if /^_/;
      $out .= "<option" . 
	    (defined $target && lc $target eq lc $_ ? ' selected="1"' : '') 
	  . ">" . _escape($_) . "</option>\n";
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
