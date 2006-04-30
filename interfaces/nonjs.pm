package nonjs;
use strict;
use vars qw/@ISA $standardheader/;

$standardheader = <<EOF;
<!-- This is part of CGI:IRC 0.5
  == http://cgiirc.sourceforge.net/
  == Copyright (C) 2000-2006 David Leadbeater <cgiirc\@dgl.cx>
  == Released under the GNU GPL
  -->
EOF

# nonjs always uses first server..
if(defined $::config->{balance_servers}) {
  my @s = split /,\s*/, $::config->{balance_servers};
  $::config->{script_form} = "$s[0]/$::config->{script_form}";
  $::config->{script_nph} = "$s[0]/$::config->{script_nph}";
}

use default;
@ISA = qw/default/;

sub new {
   my($class,$event,$timer, $config, $icookies) = @_;
   my $self = bless {}, $class;
   $timer->addforever(code => \&todo, data => $self, interval => 10);
   $event->add('user 005', code => sub { $self->{':_prefix'} = "$_[1] " } );
   $self->{':_timestamp'} = 0;
   $self->{':_timestamp'}++ if exists $icookies->{timestamp} &&
        $icookies->{timestamp};
   return $self;
}

sub _out {
   unless(print "$_[1]<script>s();</script>\r\n") {
      $::needtodie++;
   }
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
   $self->{':_reload'} = $w;
}

sub todo {
   my($timer, $self) = @_;
   if(defined $self->{':_reload'} && $self->{':_reload'}) {
	  _reloadreal($self->{':_reload'});
      delete($self->{':_reload'});
   }
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub query {
   return 0;
}

sub smilie {
   shift;
   return "<img src=\"$_[0]\" alt=\"$_[2]\">";
}

sub link {
   shift;
   return "<a href=\"$_[0]\" target=\"cgiirc". int(rand 10000) ."\">$_[1]</a>";
}

sub header {
   my($self, $config, $cgi, $bg, $fg) = @_;
   print <<EOF;
$standardheader
<html><head>
<title>CGI:IRC</title>
<script language="JavaScript"><!--
function s() {
   window.scrollBy(0,2000);
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
<body bgcolor="$bg" text="$fg">
EOF
}

sub makeline {
   my($self, $info, $html) = @_;
   my $target = $info->{target};
   $target ||= 'Status';
   if(not exists $self->{lc $target} && $target ne 'Status') {
      if(defined $info && ref $info && exists $info->{create} &&
	    $info->{create}) {
	     $self->add($target, $info->{type} eq 'join' ? 1 : 0);
      }
   }elsif($info->{type} eq 'join') {
      $self->reload('u');
   }

   if($self->{':_timestamp'}) {
      my($sec,$min,$hour) = localtime;
      $html = sprintf("[%02d:%02d] %s", $hour, $min, $html);
   }
	  
   return $html . '<br>';
}

sub lines {
   my($self, @lines) = @_;
   $self->_out($_) for @lines;
}

sub line {
   my($self, $line) = @_;
   $self->_out($self->makeline({}, $line));
}

sub add {
   my($self, $name, $param) = @_;
   $self->{':_target'} ||= lc $name;
   $self->{lc $name} = $param;
   $self->_out('<script>u();f();</script>');
}

sub del {
   my($self, $name) = @_;
   delete($self->{$name});
   $self->reload('f');
}

sub active {
   my($self, $name) = @_;
   $self->{':_target'} = $name;
   $self->reload('f');
}

sub error {
   my($self,$message) = @_;
   $self->line($message);
}

sub help {
   my($self) = shift;
   $self->line("Full help can be found at http://cgiirc.sourceforge.net/docs/usage.php");
}

sub frameset {
   my($self, $scriptname, $config, $random, $out, $interface) = @_;
print <<EOF;
$standardheader
<html>

<head>
<title>CGI:IRC</title>
</head>

<frameset rows="*,60" framespacing="0" border="0" frameborder="0">
<frameset cols="*,120" framespacing="0" border="0" frameborder="0">
<frame name="fmain" src="$config->{script_nph}?$out" scrolling="yes">
<frame name="fuserlist" src="$scriptname?item=fuserlist&interface=$interface&R=$random" scrolling="yes">
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
$standardheader
<html><head>
<noscript><meta http-equiv="Refresh" content="15;URL=$config->{script_form}?R=$cgi->{R}&item=userlist"></noscript>
</head><body bgcolor="#ffffff" text="#000000">
Loading..
</body></html>
EOF
}

sub _page {
   return '<html><head></head><body bgcolor="#ffffff">' . $_[0]
   . "</body></html>\r\n";
}

sub userlist {
   my($self, $input, $irc, $config) = @_;
   if(!defined $self->{':_target'} || !$irc->is_channel($self->{':_target'})) {
      return _page('No channel');
   }

   my $channel = $irc->channel($self->{':_target'});
   return _page('No channel') unless ref $channel;

   my $output = 'Users in <b>' . _escape($channel->{name}) . '</b><br>';

   my @users = map($channel->get_umode($_) . $_, $channel->nicks);
   my $umap = '@%+ ';
   if($self->{':_prefix'}) {
      $umap = $self->{':_prefix'};
   }

   for(sort { # (I think this is clever :-)
        my($am,$bm) = (substr($a, 0, 1), substr($b, 0, 1));
		return $a cmp $b if ($am eq $bm);
		return index($umap, $am) <=> index($umap, $bm);
      } @users) {
	  $output .= "<a href=\"$config->{script_form}?R=$input->{R}&item=userlist&cmd=say&say=/query+" . substr($_, 1) . "\">$_</a><br>";
   }

   return _page($output);
}

sub fform {
   my($self, $cgi, $config) = @_;
   print _form_out($cgi->{R}, $config->{script_form}, undef, {});
}

sub form {
   my($self, $cgi, $irc, $config) = @_;
   if(defined $cgi->{target} && $cgi->{target} && $cgi->{target} ne $self->{':_target'}) {
      $self->{':_target'} = $cgi->{target};
      $self->reload('u');
   }
   return _form_out($cgi->{R}, $config->{script_form}, $self->{':_target'}, $self);
}

sub _form_out {
   my($rand, $script, $target, $targets) = @_;
my $out = <<EOF;
<html>
<head>
<html><head>
<script language="JavaScript"><!--
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
<input type="hidden" name="item" value="form">
<input type="hidden" name="cmd" value="say">
<select name="target">
EOF
if(ref $targets) {
   for(keys %$targets) {
      next if /^:_/;
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
