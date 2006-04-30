#! /usr/bin/perl -w
# CGI:IRC - http://cgiirc.sourceforge.net/
# Copyright (C) 2000-2006 David Leadbeater <http://contact.dgl.cx/>
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
use vars qw($VERSION $config $config_path);
use lib qw/modules interfaces/;
no warnings 'uninitialized';

($VERSION =
 '$Name:  $ 0_5_CVS $Id: irc.cgi,v 1.39 2006/04/30 16:09:28 dgl Exp $'
) =~ s/^.*?(\d\S+) .*?(\d{4}\/\S+) .*$/$1/;
$VERSION .= " ($2)";
$VERSION =~ s/_/./g;

require 'parse.pl';

my $cgi = cgi_read();

for('', '/etc/cgiirc/', '/etc/') {
   last if -r ($config_path = $_) . 'cgiirc.config';
}

$config = parse_config($config_path . 'cgiirc.config');

if(!parse_cookie()) {
   print "Set-cookie: cgiircauth=". random(25) .";path=/\r\n";
}
print join("\r\n",
# Hack to make sure we print the correct type for stylesheets too..
	  'Content-type: text/' . (ref $cgi && defined $cgi->{item} &&
        $cgi->{item} eq 'style' ? 'css' : 'html')
# We need this for some JavaScript magic that detects the character set.
# Basically don't send a character set for the login page..
         . (ref $cgi && ($cgi->{item} || $cgi->{Nickname}) ? '; charset=utf-8' : ''),
      'Pragma: no-cache',
      'Cache-control: must-revalidate, no-cache',
      'Expires: -1') . "\r\n";

# Please leave this.
my $copy = <<EOF;
<a href="http://cgiirc.sourceforge.net/">CGI:IRC</a> $VERSION<br />
EOF

my $scriptname = $config->{script_login} || 'irc.cgi';

my $interface = ref $cgi && defined $cgi->{interface} ? $cgi->{interface} : 'default';
$interface =~ /^([a-z0-9]+)/;
$interface = $1;
require($interface . '.pm');

if(ref $cgi && defined $cgi->{item}) {
   print "\r\n"; # send final header
   my $name = $cgi->{item};
   exit unless $interface->exists($name);
   $interface->$name($cgi, $config, 0);
}elsif(ref $cgi && defined $cgi->{Nickname}) {
   print "\r\n"; # send final header
   my $r = random();
   my($format, $style);
   
   my %p = ( 
         Nickname => 'nick', 
         Channel => 'chan',
         Port => 'port',
         Server => 'serv',
         Realname => 'name',
         interface => 'interface',
         Password => 'pass',
         Format => 'format',
         'Character set' => 'charset',
      );
   my $out;
   for(keys %p) {
     if(exists $cgi->{"${_}_text"}) {
       if(!defined $cgi->{$_} or $cgi->{$_} eq '') {
         $cgi->{$_} = $cgi->{"${_}_text"};
       }
     }      
	  next unless exists $cgi->{$_};
	  $out .= cgi_encode($p{$_}) . '=' . cgi_encode($cgi->{$_}) . '&';
   }

   $format = exists $cgi->{Format}
            ? $cgi->{Format} 
            : $config->{format} || 'default';
   $format =~ s/[^a-z]//gi;
   $format = parse_config($config_path . "formats/$format");
   $style = exists $format->{style} ? $format->{style} : 'default';

   $out .= "R=$r";

   if(defined $config->{'login secret'}) {
      require Digest::MD5;
      my $t = time;
      my $token = Digest::MD5::md5_hex($t . $config->{'login secret'} . $r);
      $out .= "&token=$token&time=$t";
   }

   $interface->frameset($scriptname, $config, $r, $out, $interface, $style);

}elsif(defined $config->{form_redirect}) {
   print join("\r\n",
         "Status: 302",
         "Location: $config->{form_redirect}",
         "",
         $config->{form_redirect});
}else{
   print "\r\n"; # send final header

   my $have_entities = 0;
   eval { require HTML::Entities; $have_entities = 1; };

   my(%items,@order);

   my $server = dolist($config->{default_server});
   my $channel = dolist($config->{default_channel});
   my $port = dolist($config->{default_port});
   
   my $charset = [ $config->{'irc charset'} ];
   if(defined $ENV{HTTP_ACCEPT_CHARSET}) {
      for(split ',', $ENV{HTTP_ACCEPT_CHARSET}) {
         next if /;q=0($|\.0$)/ or /\*/;
         s/;.*//;
         push @$charset, $_; 
      }
   }
   if(@$charset == 1) {
      $charset = $charset->[0];
      $charset = '' unless defined $charset;
   }

   if(ref $cgi && $cgi->{chan}) {
      $channel = $cgi->{chan};
   }

   if(!defined $config->{allow_non_default} || !$config->{allow_non_default}) {
       add_disabled($server);
       add_disabled($channel);
       add_disabled($port);
   }else{
       add_disabled($server) unless defined $config->{access_server};
       add_disabled($port) unless defined $config->{access_port};
       add_disabled($channel) unless defined $config->{access_channel};
   }

   opendir(FORMATS, $config_path . "formats");
   my @formats;
   for(sort readdir FORMATS) {
      next unless !/^\./ && -f $config_path . "formats/$_";
      if($_ eq ($config->{format} || 'default')) {
         unshift(@formats, $_);
      }else{
         push(@formats, $_);
      }
   }
   closedir(FORMATS);

   %items = (
      Nickname => $ENV{REMOTE_USER} || $config->{default_nick},
      Channel => $channel,
      Server => $server,
      Port => $port,
      Password => '-PASSWORD-',
      Realname => $config->{default_name},
      Format => \@formats,
      'Character set' => $charset
   );

   my $func = \&escape_html;
   $func = \&HTML::Entities::encode_entities if $have_entities;
   @items{keys %items} = map { ref $_
         ? [map { $func->($_) } @$_]
         : $func->($_) }
      values %items;

   $items{Nickname} =~ s/\?/int rand 10/eg;

   if(ref $cgi && $cgi->{adv}) {
	  if($config->{'login advanced'}) {
		 @order = split(/,\s*/, $config->{'login advanced'});
	  }else{
		 @order = qw/Nickname Realname Server Port Channel Password Format/;
       push @order, 'Character set';
	  }
   }else{
	  if($config->{'login basic'}) {
		 @order = split(/,\s*/, $config->{'login basic'});
	  }else{
		 @order = qw/Nickname Server Channel/;
	  }
   }
   $interface->login($scriptname, $interface, $copy, $config, 
         \@order, \%items,
         (ref $cgi && $cgi->{adv} ? 0 : 1));
}

sub random {
   return join('',map(('a'..'z','0'..'9')[int rand 62], 0..($_[0] || 15)));
}

sub dolist {
   my($var) = @_;
   my @tmp = split(/,\s*/, $var);
   return [@tmp] if $#tmp > 0;
   return $var;
}

sub add_disabled {
   if(ref $_[0]) {
      unshift @{$_[0]}, "-DISABLED-";
   } else {
      $_[0] = "-DISABLED- $_[0]";
   }
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

sub error {
   die(@_);
}
