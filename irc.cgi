#!/usr/bin/perl
use strict;
use vars qw($VERSION);
use lib qw/modules interfaces/;

($VERSION =
 '$Name:  $ $Id: irc.cgi,v 1.2 2002/03/05 16:43:11 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;

require 'parse.pl';

print "Content-type: text/html
Pragma: no-cache
Cache-control: must-revalidate, no-cache
Expires: -1\n\n";

my $copy = <<EOF;
<a href="http://cgiirc.sourceforge.net/">CGI:IRC</a> $VERSION<br />
&copy;David Leadbeater 2000-2002
EOF

my $scriptname = $ENV{SCRIPT_NAME} || $0;
$scriptname =~ s!^.*/!!;

my $config = parse_config('cgiirc.config');
require('interfaces/' . $config->{interface} . '.pm');
my $interface = $config->{interface};
my $cgi = cgi_read();

if(ref $cgi && defined $cgi->{item}) {
   my $name = $cgi->{item};
   exit unless $interface->exists($name);
   $interface->$name($cgi, $config, 0);
}elsif(ref $cgi && defined $cgi->{Nickname}) {
   my $r = join('',map(('a'..'z','0'..'9')[int rand 62], 0..15));

   my $p = { Nickname => 'nick', 
	         Channel => 'chan',
			 Port => 'port',
			 Server => 'serv',
			 Realname => 'name',
			 Password => 'pass'};
   my $out;
   for(keys %$p) {
	  next unless exists $cgi->{$_};
	  $out .= cgi_encode($p->{$_}) . '=' . cgi_encode($cgi->{$_}) . '&';
   }
   $out .= "R=$r";
   $out =~ s/\&$//;
   $interface->frameset($scriptname, $config, $r, $out);
}else{
   my(%items,@order);

   $items{Nickname} = $config->{default_nick};
   $items{Nickname} =~ s/\?/int rand 10/eg;
   $items{Channel} = dolist($config->{default_channel});
   $items{Server} = dolist($config->{default_server});
   $items{Port} = $config->{default_port};
   $items{Password} = '';
   $items{Realname} = $config->{default_name};

   if(ref $cgi && $cgi->{adv}) {
	  if($config->{'login advanced'}) {
		 @order = split(' ', $config->{'login advanced'});
	  }else{
		 @order = qw/Nickname Realname Server Port Channel Password/;
	  }
   }else{
	  if($config->{'login basic'}) {
		 @order = split(' ', $config->{'login basic'});
	  }else{
		 @order = qw/Nickname Server Channel/;
	  }
   }
   $interface->login($scriptname, $copy, $config, \@order, \%items);
}

sub dolist {
   my($var) = @_;
   my @tmp = split(/,\s*/, $var);
   return [@tmp] if $#tmp;
   return $tmp[0];
}

sub cgi_read { 
   if($ENV{REQUEST_METHOD} eq 'GET' && $ENV{QUERY_STRING}) {
	  return parse_query($ENV{QUERY_STRING});
   }elsif($ENV{REQUEST_METHOD} eq 'POST' && $ENV{CONTENT_LENGTH}) {
	  my $tmp;
	  read(STDIN, $tmp, $ENV{CONTENT_LENGTH});
	  return parse_query($tmp);
   }
}

sub cgi_encode { # from CGI.pm
   my $toencode = shift;
   $toencode=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/eg;
   return $toencode;
}

