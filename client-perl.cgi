#! /usr/bin/perl -w
# CGI:IRC - http://cgiirc.sourceforge.net/
# Copyright (C) 2000-2004 David Leadbeater <cgiirc@dgl.cx>
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

use strict;
use lib qw/modules/;
use vars qw($VERSION $PREFIX);

# change this if needed
$PREFIX = "/tmp/cgiirc-";

($VERSION =
'$Name:  $ 0_5_CVS $Id: client-perl.cgi,v 1.9 2005/06/19 18:07:36 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;
$VERSION =~ s/_/./g;

use Socket;
use Symbol;
$|++;
require 'parse.pl';

sub net_unixconnect {
   my($local) = @_;
   my $fh = Symbol::gensym;

   socket($fh, PF_UNIX, SOCK_STREAM, 0) or return (0, $!);
   connect($fh, sockaddr_un($local)) or return (0, $!);

   return $fh;
}

sub net_send {
   my($fh,$data) = @_;
   syswrite($fh, $data, length $data);
}

sub error {
   my($message) = @_;
   print "Content-type: text/html\r\n\r\n";
   print "An error occurred: $message\n";
   exit;
}

my $cookie = parse_cookie();
my($input,$rand) = cgi_read();
error("Invalid random value") if !defined $rand || $rand =~ /[^a-z0-9]/i;

my($fh,$error) = net_unixconnect($PREFIX . $rand . '/sock');
error("Connection to unix-domain socket($PREFIX$rand/sock): $error") if $fh == 0;

net_send($fh, "COOKIE=$cookie&$input\n");
print while(<$fh>);
exit;

sub cgi_read {
   return (undef,undef) unless defined $ENV{REQUEST_METHOD};
   if($ENV{REQUEST_METHOD} eq 'GET' && $ENV{QUERY_STRING}) {
      my $cgi = parse_query($ENV{QUERY_STRING});
	  return($ENV{QUERY_STRING},$cgi->{R});
   }elsif($ENV{REQUEST_METHOD} eq 'POST' && $ENV{CONTENT_LENGTH}) {
      my $tmp;
      read(STDIN, $tmp, $ENV{CONTENT_LENGTH});
      my $cgi = parse_query($tmp);
	  return($tmp,$cgi->{R});
   }
}

