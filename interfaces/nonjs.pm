package nonjs;

use default;
@ISA = qw/default/;

sub new {
   my($self,$event) = @_;
   return bless {};
}

sub _out {
   print "<script>$_[0]</script>\r\n";
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub line {
   my($self, $info, $html) = @_;
   my $target = defined $info->{target} ? $info->{target} : 'Status';

   if(ref $target eq 'ARRAY') {
      my %tmp = %$info;
	  for(@$target) {
	     $tmp{target} = $_;
         $self->line(\%tmp, $html);
	  }
	  return;
   }

   if(not exists $self->{lc $target}) {
      if(defined $info && ref $info && defined $info->{type} &&
	    $info->{type} =~ /^(join|message private)$/) {
	     $self->add($target, $info->{type} eq 'join' ? 1 : 0);
	  }elsif($target ne '-all') {
         $target = 'Status';
	  }
   }
   _func_out('witemaddtext', $target, $html . '<br>', $info->{activity} || 0);
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

<frameset rows="40,*,25,0" framespacing="0" border="0" frameborder="0">
<frame name="fwindowlist" src="$scriptname?$out&item=fwindowlist" scrolling="no">
<frameset cols="*,100" framespacing="0" border="0" frameborder="0">
<frame name="fmain" src="$scriptname?item=fmain&interface=$interface" scrolling="yes">
<frame name="fuserlist" src="$scriptname?item=fuserlist&interface=$interface" scrolling="no">
</frameset>
<frame name="fform" src="$scriptname?item=fform&interface=$interface" scrolling="no">
<frame name="hiddenframe" src="about:blank" scrolling="no">
<noframes>
This interface requires a browser that supports frames and javascript.
</noframes>

</frameset>
</html>
EOF
}

sub fuserlist {
print <<EOF;
<html>
<head>
<style><!--
BODY { border-left: 1px solid #999999; margin: 0; }
SELECT { border: 0; padding: 0;width: 100%; height: 100%; }
// -->
</style>
</head>
<body>
<form name="mform">
<select size="2" name="userlist">
</select>
</form>
</body>
</html>
EOF
}

sub fmain {
print <<EOF;
<html><head></head>
<body>
<span id="text"></span>
</body></html>
EOF
}

sub fform {
print <<EOF;
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
<style><!--
BODY { border-top: 1px solid #999999;margin: 0; }
.say { border: 0; width: 80%; padding-left: 4px; }
// -->
</style>
</head>
<body onload="fns()" onfocus="fns()">

<form name="myform" class="myform">
<input type="text" class="say" name="say" autocomplete="off">
</form>

</body>
</html>
EOF
}

sub fwindowlist {
   my($self, $cgi, $config) = @_;
   my $string;
   for(keys %$cgi) {
      next if $_ eq 'item';
	  $string .= main::cgi_encode($_) . '=' . main::cgi_encode($cgi->{$_}).'&';
   }
   $string =~ s/\&$//;
}

1;
