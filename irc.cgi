#! /usr/bin/perl -w
# CGI:IRC - http://cgiirc.sourceforge.net/
# Copyright (C) 2000-2002 David Leadbeater <cgiirc@dgl.cx>
# vim:set ts=3 expandtab shiftwidth=3 cindent:

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Uncomment this if the server doesn't chdir (Boa).
# BEGIN { (my $dir = $0) =~ s|[^/]+$||; chdir($dir) }

use strict;
use vars qw($VERSION);
use lib qw/modules interfaces/;

($VERSION =
 '$Name:  $ 0_5_CVS $Id: irc.cgi,v 1.11 2002/04/15 22:18:00 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;
$VERSION =~ s/_/./g;

require 'parse.pl';

if(!parse_cookie()) {
   print "Set-cookie: cgiircauth=". random(25) .";path=/\n";
}
print join("\r\n", 
	  'Content-type: text/html',
      'Pragma: no-cache',
      'Cache-control: must-revalidate, no-cache',
      'Expires: -1',
	  "\r\n");

my $copy = <<EOF;
<a href="http://cgiirc.sourceforge.net/">CGI:IRC</a> $VERSION<br />
&copy;David Leadbeater 2000-2002
EOF

my $scriptname = $ENV{SCRIPT_NAME} || $0;
$scriptname =~ s!^.*/!!;

my $config = parse_config('cgiirc.config');
my $cgi = cgi_read();

my $interface = ref $cgi && defined $cgi->{interface} ? $cgi->{interface} : 'default';
$interface =~ s/[^a-z]//gi;
require('interfaces/' . $interface . '.pm');

if(ref $cgi && defined $cgi->{item}) {
   my $name = $cgi->{item};
   exit unless $interface->exists($name);
   $interface->$name($cgi, $config, 0);
}elsif(ref $cgi && defined $cgi->{Nickname}) {
   my $r = random();

   my %p = ( 
         Nickname => 'nick', 
         Channel => 'chan',
         Port => 'port',
         Server => 'serv',
         Realname => 'name',
         interface => 'interface',
         Password => 'pass'
      );
   my $out;
   for(keys %p) {
	  next unless exists $cgi->{$_};
	  $out .= cgi_encode($p{$_}) . '=' . cgi_encode($cgi->{$_}) . '&';
   }
   $out .= "R=$r";
   $out =~ s/\&$//;
   $interface->frameset($scriptname, $config, $r, $out, $interface);
}else{
   my(%items,@order);

   my $server = dolist($config->{default_server});
   my $channel = dolist($config->{default_channel});
   my $port = $config->{default_port};

   if(!defined $config->{allow_non_default} || !$config->{allow_non_default}) {
       $server = "-DISABLED- $server" unless ref $server;
       $channel = "-DISABLED- $channel" unless ref $channel;
       $port = "-DISABLED- $port";
   }elsif(!defined $config->{access_server} || !$config->{access_server}) {
       $server = "-DISABLED- $server" unless ref $server;
   }
   
   %items = (
      Nickname => $config->{default_nick},
      Channel => $channel,
      Server => $server,
      Port => $port,
      Password => '-PASSWORD-',
      Realname => $config->{default_name},
   );

   $items{Nickname} =~ s/\?/int rand 10/eg;

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
   $interface->login($scriptname, $interface, $copy, $config, \@order, \%items);
}

sub random {
   return join('',map(('a'..'z','0'..'9')[int rand 62], 0..($_[0] || 15)));
}

sub dolist {
   my($var) = @_;
   my @tmp = split(/,\s*/, $var);
   return [@tmp] if $#tmp > 0;
   return $tmp[0];
}

sub cgi_read { 
   return unless defined $ENV{REQUEST_METHOD};
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

