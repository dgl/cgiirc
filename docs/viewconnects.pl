#!/usr/bin/perl
# CGI:IRC - http://cgiirc.sourceforge.net/
# Copyright (C) 2000-2002 David Leadbeater <http://contact.dgl.cx/>
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
use vars qw($VERSION);
use Socket;

($VERSION =
 '$Name:  $ 0_5_CVS $Id: viewconnects.pl,v 1.3 2004/02/03 14:36:35 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;
$VERSION =~ s/_/./g;

# Change these if needed.
my $cgiircprefix="/tmp/cgiirc-";
my $resolve = 1;

if($ENV{GATEWAY_INTERFACE} =~ /CGI/) { # We aren't really a CGI script..
   print "Content-type: text/plain\n\n";
}

my @connects = list_connects();

if(!@connects) {
   print "No connections found.\n";
   exit;
}

my $format = "%-9.9s %-15.15s " . 
   ($resolve ? "%-38.38s" : "%-15.15s") . 
   " %-9.9s %-5.5s\n";

printf($format, "1st Nick", "Server", "Client", "Login", "Idle");

for my $u(@connects) {
   my %user;
   @user{qw/remoteip localip server nick clientip forwardedip ltime idle/} = @$u;
   if($resolve) {
      $user{clientip} = gethostbyaddr(inet_aton($user{clientip}), AF_INET) . " ($user{clientip})";
   }
   printf($format, @user{qw/nick server clientip ltime idle/});
}

sub list_connects {
   my @connects;
   (my $dir, my $prefix) = $cgiircprefix =~ /^(.*\/)([^\/]+)$/;
   opendir(TMPDIR, $dir) or return undef;
   for my $path(readdir TMPDIR) {
      my @u;
      next unless $path =~ /^\Q$prefix\E/;
      $path = $dir . $path;
      next unless -d $path;

      local *TMP;
      open(TMP, "<$path/server") or next;
      @u = <TMP>;
      chomp(@u);
      close(TMP);

      open(TMP, "<$path/ip") or next;
      for my $n(0..1) {
         chomp($_ = <TMP>);
         $u[$n + 4] = $_;
      }
      close(TMP);

      # login time
      my @t = localtime((stat("$path/sock"))[8]);
      my @today = localtime();
      my @days = qw/Sun Mon Tue Wed Thu Fri Sat/;
      # anyone logged on for longer than a week/(since sun) will be wrong
      # too bad eh?
      if($t[6] == $today[6]) {
         $u[6] = sprintf '%02d:%02d', $t[2], $t[1];
      }else{
         $u[6] = "$days[$t[6]] " . ($t[2] > 11 ? $t[2] - 12 . 'pm' : "$t[2]am");
      }
      
      # idle time
      @t = gmtime(time - (stat("$path/sock"))[9]);
      $u[7] = sprintf '%02d:%02d', $t[2] + $t[7] * 24, $t[1];

      push(@connects, \@u);
   }
   return @connects;
}
