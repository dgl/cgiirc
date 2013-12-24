#!/usr/bin/perl
# CGI:IRC - http://cgiirc.org/
# Copyright (C) 2000-2006 David Leadbeater <http://dgl.cx/>
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

require 5.004;
use strict;
use lib qw{./modules ./interfaces};
use vars qw(
      $VERSION @handles %inbuffer $select_bits @output
      $unixfh $ircfh $cookie $ctcptime $intime $pingtime
      $timer $event $config $cgi $irc $format $formatname $interface $ioptions
      $regexpicon %regexpicon
      $config_path $help_path
   );

($VERSION =
'0.5.11 $Id$'
) =~ s/^.*?(\d\S+) .*?([0-9a-f]{4}).*/$1 . (index($1, "g") > 0 ? "$2" : "")/e;

use Socket;
use Symbol; # gensym
$|++;
# Check for IPV6. Bit yucky but avoids errors when module isn't present
BEGIN {
   eval('use Socket6; $::IPV6++ if defined $Socket6::VERSION');
   unless(defined $::IPV6) {
      $::IPV6 = 0;
      eval('sub AF_INET6 {0};sub NI_NUMERICHOST {0};sub NI_NUMERICSERV {}');
   }
   # then check for Encode
   $::ENCODE = 0;
   eval("use Encode;");
   $::ENCODE = 1 unless $@;
}

# My own Modules
use Timer;
use Event;
use IRC;
use Command;
require 'parse.pl';

for('', '/etc/cgiirc/', '/etc/') {
   last if -r ($config_path = $_) . 'cgiirc.config';
}

for('docs/', '/usr/share/doc/cgiirc/') {
   last if -r ($help_path = $_) . 'help.html';
}

my $needtodie = 0;

# DEBUG
#use Carp;
#$SIG{__DIE__} = \&confess;

#### Network Functions

## Returns the address of a host (handles both IPv4 and IPv6)
## Return value: (ipv4,ipv6)
sub net_hostlookup {
   my($host) = @_;

   if($::IPV6) {
      my ($ipv6, $ipv4);

      my @res = getaddrinfo($host, undef, AF_UNSPEC, SOCK_STREAM);
      while (scalar(@res) >= 5) {
         (my $family, undef, undef, my $saddr, undef, @res) = @res;
         my ($ipaddr, undef) = getnameinfo( $saddr, NI_NUMERICHOST | NI_NUMERICSERV);

         $ipv4 = $ipaddr unless ($family != AF_INET || defined $ipv4);
         $ipv6 = $ipaddr unless ($family != AF_INET6 || defined $ipv6);
      }

      return undef unless (defined $ipv4 || $ipv6);
      return config_set('prefer_v4')
         ? ($ipv4 ? $ipv4 : $ipv6)
         : ($ipv6 ? $ipv6 : $ipv4);
   }else{ # IPv4
      my $ip = (gethostbyname($host))[4];
      return $ip ? inet_ntoa($ip) : undef;
   }
}

## Connects a tcp socket and returns the file handle
## inet_addr should be the output of net_gethostbyname
sub net_tcpconnect {
   my($inet_addr, $port) = @_;
   my $fh = Symbol::gensym;
   my $family = ($inet_addr !~ /:/ ? AF_INET : AF_INET6);
   
   socket($fh, $family, SOCK_STREAM,
         getprotobyname('tcp')) or return(0, $!);
   setsockopt($fh, SOL_SOCKET, SO_KEEPALIVE, pack("l", 1)) or return(0, $!);

   my $saddr;
   if($inet_addr !~ /:/) {
      $saddr = sockaddr_in($port, inet_aton($inet_addr));
      if(config_set('vhost')) {
         (my $vhost) = $config->{vhost} =~ /(.*)/; # untaint
         my @vhosts = split /,\s*/, $vhost;
         bind($fh, pack_sockaddr_in(0, inet_aton($vhosts[rand @vhosts])));
      }else{
         bind($fh, pack_sockaddr_in(0, inet_aton('0.0.0.0')));
      }
   }else{
      $saddr = sockaddr_in6($port, inet_pton(AF_INET6, $inet_addr));
      if(config_set('vhost6')) {
         # this needs testing...
         (my $vhost) = $config->{vhost6} =~ /([^ ]+)/;
         bind($fh, pack_sockaddr_in6(0, inet_pton(AF_INET6, $vhost)));
      }
   }

   if($family == AF_INET) {
      my($localport,$localip) = sockaddr_in(getsockname $fh);
      irc_write_server(inet_ntoa($localip), $localport, $inet_addr, $port);
   }else{
      my($localport,$localip) = sockaddr_in6(getsockname $fh);
      irc_write_server(inet_pton(AF_INET6, $localip), $localport, $inet_addr, $port);
   }

   $SIG{ALRM} = sub { die "xtimeout" };
   eval {
      local $SIG{__DIE__} = undef;
      alarm 60;
      connect($fh, $saddr) or die "$!\n";
   };
   alarm 0;

   if($@ =~ /xtimeout/) {
      return(0, "Connection timed out (60 seconds)");
   }elsif($@) {
      chomp(my $error = $@);
      return(0, "$error connecting to $inet_addr:$port");
   }

   net_autoflush($fh);

   return($fh);
}

## Opens a UNIX Domain Listening socket
## Passed just the filename, returns 1 on success, 0 on failure
sub net_unixconnect {
   my($local) = @_;
   my $fh = Symbol::gensym;

   if(-e $local) {
      return 0 unless unlink $local;
   }

   socket($fh, PF_UNIX, SOCK_STREAM, 0) or return (0, $!);
   bind($fh, sockaddr_un($local)) or return (0, $!);
   listen($fh, SOMAXCONN) or return (0, $!);

   net_autoflush($fh);

   return $fh;
}

sub net_autoflush {
   my $fh = shift;
   select $fh;
   $| = 1;
   select STDOUT;
}

## Send data to specific filehandle (and deal with encodings for irc)..
sub net_send {
   my($fh,$data) = @_;
   if($::ENCODE && $fh == $ircfh) {
      my $output = Encode::encode($config->{'irc charset'}, $data);
      $output = $data unless defined $output;
      syswrite($fh, $output, length $output);
   }elsif($::ENCODE) {
      my $output = Encode::encode('utf8', $data);
      $output = $data unless defined $output;
      syswrite($fh, $output, length $output);
   }else{
      syswrite($fh, $data, length $data);
   }
}

#### Select Helper Functions
## Code adapted from IO::Select.pm by Graham Barr

## Adds file handle into @handles and fileno into the bit vector
sub select_add {
   my($fh) = @_;
   my $fileno = select_fileno($fh);
   $handles[$fileno] = $fh;
   select_makebits();
}

## Deletes the filehandle and fileno
sub select_del {
   my($fh) = @_;
   my $fileno = select_fileno($fh);
   if(!$fileno) {
      for(0 .. $#handles) {
         $fileno = $_, last if $handles[$_] == $fh;
      }
   }
   return unless defined $handles[$fileno];
   
   $handles[$fileno] = undef;
   select_makebits();
}

## Returns a fileno
sub select_fileno {
   fileno(shift);
}

sub select_makebits {
   $select_bits = '';
   for(2 .. $#handles) {
      next unless defined $handles[$_] && ref $handles[$_];
      vec($select_bits, select_fileno($handles[$_]), 1) = 1;
   }
}

## Returns list of handles with input waiting
sub select_canread {
   my($timeout) = @_;
   my $read = $select_bits;
   
   if(select($read, undef, undef, $timeout) > 0) {
      my @out;
      for(0 .. $#handles) {
         push(@out, $handles[$_]) if vec($read, $_, 1);
      }
      return @out;
   }
   return ();
}

## Closes and deletes a filehandle
sub select_close {
   my($fh) = @_;
   return irc_close() if $ircfh == $fh;
   select_del($fh);
   close($fh);
}

#### Format Functions

## Loads the format given to it, or the default
sub load_format {
   $formatname = $config->{format};
   if($cgi->{format} && $cgi->{format} !~ /[^A-Za-z0-9]/) {
      $formatname = $cgi->{format};
   }
   return parse_config($config_path . 'formats/' . $formatname);
}

## Prints a nicely formatted line
## the format is the format name to use, taken from the %format hash
## the params are passed to the format
sub format_out {
   my($formatname, $info, $params) = @_;
   return unless exists $format->{$formatname};
   return unless $format->{$formatname};

   my $line = format_parse($format->{$formatname}, $info, $params);

   my $try = 0;
   # If there is malformed UTF8 various regexes under here can die for odd
   # reasons (which I don't fully understand) therefore wrap in an eval.
   OUTPUT: eval {
      $line = format_colourhtml($line);
      interface_lineout($info, $line);
   };

   if($@) {
      print STDERR "Output failed with: $@\n";
      # Try again without UTF8 (treat as binary, probably only does something
      # vaguely useful for latin characters?)
      Encode::_utf8_off($line) if $::ENCODE;
      goto OUTPUT unless $try++;
   }
}

sub message {
   my($formatname, @params) = @_;
   my $info = { target => 'Status', activity => 1, type => $formatname };
   format_out($formatname, $info, \@params);
}

## Formats IRC Colours and Styles into HTML and makes URLs clickable
sub format_colourhtml {
   my($line) = @_;

   # Used as a token for replaces 
   my $tok = "\004";

   $line =~ s/$tok//g;

   $line =~ s/\&/$tok\&amp;$tok/g;
   $line =~ s/</$tok\&lt;$tok/g;
   $line =~ s/>/$tok\&gt;$tok/g;
   $line =~ s/"/$tok\&quot;$tok/g;

   $line =~ s{((https?|ftp):\/\/[^$ ]+)(?![^<]*>)}{$interface->link(format_remove($1), format_linkshorten($1))}gie;
   $line =~ s{(^|\s)(www\..*?)([\.,]?($|\s)|\)|\002)(?![^<]*>)}{"$1" . $interface->link(format_remove("http://$2"), $2) . $3}gie;

   if(exists $ioptions->{smilies} && $ioptions->{smilies}) {
      $line =~ s{(?<![^\.a-zA-Z_ ])$regexpicon(?![^<]*>)}{
         my($sm, $tmp) = ($1, $1);
         for(keys %regexpicon) {
            next unless $sm =~ /^$_$/;
            $tmp = $interface->smilie("$config->{image_path}/$regexpicon{$_}.gif", $regexpicon{$_}, $sm);
            last;
         }
         $tmp
      }ge;
   }

   $line =~ s/$tok//g;
   $line =~ s/( {2,})/'&nbsp;' x (length $1)/eg;

   return format_remove($line) if $config->{removecolour};

   if($line =~ /[\002\003\017\022\037]/) {
      $line=~ s/\003(\d{1,2})(\,(\d{1,2})|)([^\003\017]*|.*?$)/
         my $me = "<font ";
         my $fg = sprintf("%0.2d",$1);
         my $bg = (defined $3 && length $3) ? sprintf("%0.2d",$3) : '';

         if(length $bg) {
            $me .= "style=\"background: ".$format->{$bg}."\" "
         }
         
         $me .= "color=\"$format->{$fg}\">$4<\/font>";
         $me
      /eg;
      $line =~ s/\002(.*?)(\002|\017|$)/<b>$1<\/b>/g;
      $line =~ s/\022(.*?)(\022|\017|$)/<u>$1<\/u>/g;
      $line =~ s/\037(.*?)(\037|\017|$)/<u>$1<\/u>/g;
   }

   return format_remove($line);
}

sub format_init_smilies {
   if(config_set('smilies')) {
      %regexpicon = %{parse_config($config_path . $config->{smilies})};
   } else {
      %regexpicon = (
         '\;-?\)'        => 'wink',
         '\;-?D'         => 'grin',
         ':\'\(?'        => 'cry',
         ':-?/(?!\S)'    => 'notsure',
         ':-?[xX]'       => 'confused',
         ':-?\]'         => 'embarassed',
         ':-?\*'         => 'love',
         ':-?[pP]'       => 'tongue',
         ':-?\)'         => 'happy',
         '\:-?D'         => 'cheesy',
         ':-?\('         => 'unhappy',
         ':-[oO]'        => 'surprised',
         '8-?\)'         => 'cool',
         ':-?\|'         => 'flat',
         ':\'\)\)?'      => 'happycry',
   "\004\&gt;\004:-?/"   => 'hmmm',
   "\004\&gt;\004:-?\\(" => 'angry',
         ':-?\*\*'       => 'kiss',
         ':-z'           => 'sleep',
         ':-\.'          => 'sorry',
         '8-@'           => 'what',
      );
   }
   $regexpicon = '(' . join('|', sort { length $b <=> length $a } keys %regexpicon) . ')';
}

sub format_linkshorten {
   my $link = shift;
   if(config_set('linkshorten')) {
      return substr($link, 0, $config->{linkshorten})
         . (length $link > $config->{linkshorten} ? '...' : '');
   }else{
      return substr($link, 0, 120)
         . (length $link > 120 ? '...' : '');
   }
}

## Removes all IRC formating characters
sub format_remove {
   my($line) = @_;
   $line =~ s/\003(\d{1,2})(\,(\d{1,2})|)//g;
   $line =~ s/[\x00-\x1f]//g;
   return $line;
}

## Lowlevel code that deals with the format parsing
## No longer supports nested 
sub format_parse {
   my($line, $info, $params) = @_;
   return unless defined $line;

   my($match, $name, $param);

   $line =~ s{
      ( # format
         \{
           ([^\}\s]+)
           \s?([^\}]+)?
         \}
          # variables
       | (\$[A-Za-z0-9-]+)
       | (\%(?:\d{1,2}|n|_|%))
      )
    }{
      ($match, $name, $param) = ($1, $2, $3);
      if($match =~ /^[\$%]/) {
         format_varexpand($match, $info, $params);
      }elsif(!exists $format->{$name}) {
         error("Invalid format ($name) called: $line");
      }else{ 
         format_parse($format->{$name}, $info,
               [map {format_varexpand($_, $info, $params)} split / /,
                  defined $param ? $param : '']);
      }
   }egx;
   
   return $line;
}

sub format_varexpand {
   $_ = shift;
   my($info, $params) = @_;
   return '' unless defined;

   if(s/^\$//) {
      if(ref $params && /^(\d+)\-$/) {
         return join(' ', @$params[$1 .. @$params - 1]);
      }elsif(!/\D/) {
         return $params->[$_] if ref $params && defined $params->[$_];
         return '';
      }elsif(/^VERSION$/) {
         return $VERSION;
      }elsif(/^T$/ && exists $info->{target}) {
         return $info->{target};
      }elsif(/^N$/) {
         return $irc->{nick}
      }elsif(/^S$/) {
         return $irc->{server};
      }
   }elsif(s/^%//) {
      if(/^_$/) {
         return "\002";
      }elsif(/^n$/) {
         return "\003$format->{fg},$format->{bg}";
      }elsif(/^%$/) {
         return "%";
      }elsif(/^\d+$/) {
         return "\003$_";
      }
      return "\%$_";
   }
   return $_;
}

#### Interface Functions

## Loads the default interface.
sub load_interface {
   my $name = defined $cgi->{interface} ? $cgi->{interface} : 'default';
   ($name) = $name =~ /([a-z0-9]+)/i;
   require("./interfaces/$name.pm");

   $ioptions = parse_interface_cookie();
   for(keys %$config) {
      next unless s/^interface //;
      next if exists $ioptions->{$_};
      $ioptions->{$_} = $config->{"interface $_"};
   }

   $interface = $name->new($event,$timer, $config, $ioptions);
   my $bg = $format->{$format->{bg}};
   my $fg = $format->{$format->{fg}};
   $interface->header($config, $cgi, $bg, $fg);

   return $interface;
}

sub interface_show {
   my($show, $input) = @_;
   return '' unless $interface->exists($show);

   return $interface->$show($input, $irc, $config);
}

sub interface_keepalive {
   $interface->keepalive($irc, $config);
}

sub interface_lineout {
   my($type, $target, $html) = @_;
   push(@output, $interface->makeline($type, $target, $html));
}

#### Unix Domain Socket Functions

## Opens the listening socket
sub load_socket {   
   error('Communication socket name is invalid')
      if !$cgi->{R} or $cgi->{R} =~ /[^A-Za-z0-9]/;
   ($cgi->{R}) = $cgi->{R} =~ /([A-Za-z0-9]+)/;
   error('Communication socket already exists')
      if -e $config->{socket_prefix}.$cgi->{R};

   mkdir($config->{socket_prefix}.$cgi->{R}, 0700) or error("Mkdir error: $!");

   open(IP, ">$config->{socket_prefix}$cgi->{R}/ip") or error("Open error: $!");
   print IP "$ENV{REMOTE_ADDR}\n";

   my $client_ip = $ENV{HTTP_X_FORWARDED_FOR};
   $client_ip = $ENV{HTTP_CLIENT_IP} unless defined $client_ip;

   print IP "$client_ip\n" if defined $client_ip;
   close(IP);

   my($socket,$error) = 
      net_unixconnect($config->{socket_prefix}.$cgi->{R}.'/sock');

   error("Error opening socket: $error") unless ref $socket;

   select_add($socket);

   return $socket;
}

sub unix_in {
   my($fh, $line) = @_;

   my $input = parse_query($line, ($line =~ /&xmlhttp/ ? 2 : 0));
   
   if($cookie && (!defined $input->{COOKIE} || $input->{COOKIE} ne $cookie)) {
      net_send($fh, "Content-type: text/html\r\n\r\nInvalid cookie\r\n");
      select_close($fh);
      return;
   }

   $pingtime = time;
   $intime = $pingtime if $input->{cmd} eq 'say'
       && $input->{say} ne '/noop';

   if($input->{cmd}) {
      my $now = time;
      utime($now, $now, "$config->{socket_prefix}$cgi->{R}/sock");
      input_command($input->{cmd}, $input, $fh, $line);
   }

   net_send($fh, "Content-type: text/html\r\n\r\n");

   if(defined $input->{item} && $input->{item} =~ /^\w+$/) {
      net_send($fh, interface_show($input->{item}, $input));
   }

   select_close($fh);
}

sub input_command {
   my($command, $params, $fh, $line) = @_;
   if($command eq 'say') {
      say_command($params->{say}, $params->{target});
   }elsif($command eq 'paste') {
      $params = parse_query($line, 1 + ($line =~ /&xmlhttp/ ? 2 : 0));
      for(split /\n/, $params->{say}) {
         s/\r$//;
         next unless $_;
         say_command($_, $params->{target});
      }
   }elsif($command eq 'quit') {
      net_send($fh, "Content-type: text/html\r\n\r\nquit\r\n"); # avoid errors
      irc_close("");
   }elsif($command eq 'options' && length $params->{name} && length $params->{value}) {
      $ioptions->{$params->{name}} = $params->{value};
      $interface->setoption($params->{name}, $params->{value});
# write proper cookie code one day.
      net_send($fh, "Set-Cookie: cgiirc$params->{name}=$params->{value}; path=/; expires=Fri, 01-Jan-2021 00:00:00 GMT\r\n");
   }
}

sub say_command {
   my($say, $target) = @_;
   return unless length $say;
   $say =~ s/(\n|\r|\0|\001)//sg;
   $target =~ s/(\n|\r|\0|\001)//sg;
   if(!config_set('disable_format_input')) {
      $say =~ s/\%C/\003/g;
      $say =~ s/\%B/\002/g;
      $say =~ s/\%U/\037/g;
   }
   if($say =~ m!^/!) {
      if($say =~ s!^/ /!/!) {
         irc_send_message($target, $say);
      }else{
         (my $command, my $params) = $say =~ m|^/([^ ]+)(?: (.+))?$|;
         unless(defined $command && length $command) {
            return;
         }
         
         $command = Command->expand($command);
         unless(access_command($command)) {
            message('command denied', $command);
            return;
         }
         
         my $error = Command->run($event, $irc, $command, $target, defined $params ? $params : '', $config, $interface);
         return 1 if $error == 100;
         
         if($error == 2) {
            message('command notparams', $error);
         }else{
            message('command error', $error);
         }
         return 0;
      }
   }else{
      irc_send_message($target, $say);
   }
}

#### Access Checking Functions

sub config_set {
   my($option) = @_;
   return 1 if defined $config->{$option} && $config->{$option};
   0;
}

sub access_ipcheck {
   return unless config_set('ip_access_file') || config_set("max_users");

   my($ip, $hostname) = @_;
   my($ipn) = inet_aton($ip);
   my($ipaccess_match) = 0;
   my($limit) = undef;

   my %ips = list_connected_ips();
   my $total = 0;
   $total += $ips{$_} for keys %ips;
   if(config_set("max_users") && $total > $config->{max_users}) {
      message('access denied', 'Too many connections (global)');
      irc_close();
   }

   return unless config_set('ip_access_file');

   for my $ipaccess_file (split(',', $config->{ip_access_file})) {
      # If any of the files don't exist, we just skip them.
      open(IP, "<" . ($ipaccess_file =~ m!^/! ? '' : $config_path)
            . $ipaccess_file) or next;
      while(<IP>) {
         chomp;
         next if /^\s*(#|$)/;
         s/\s+#.*$//g;
         my($check);
         ($check, $limit) = split(' ', $_, 2);

         if ($check =~ /\//) {
            # IP address with subnet mask
            my($addr,$mask) = split('/', $check, 2);
            $mask = "1" x $mask . "0" x (32-$mask);
            $mask = pack ("B32", $mask);
            $mask = inet_ntoa($mask & $ipn);
            if($addr eq $mask) {
               $ipaccess_match = 1;
            }
         } else {
            # IP or hostname (we check both)
            # XXX: someone could make their hostname resolve to
            # 127.0.0.1.foobar.com and it would match eg 127.*.*.*
            # I don't think it's that serious and if it really is a
            # problem, 127.0.0.0/8 wouldn't match.
            $check =~ s/\./\\./g;
            $check =~ s/\?/./g;
            my $ipcheck = $check;
            $ipcheck =~ s/\*/\\d+/g;
            $check =~ s/\*/.*/g;

            if($ip =~ /^$ipcheck$/) {
               $ipaccess_match = 1;
            } elsif($hostname =~ /^$check$/i) {
               $ipaccess_match = 1;
            }
         }
         # We stop parsing, if this line matched.
         last if $ipaccess_match;
      }
      close(IP);
      # We don't parse more files, if a line in the last file matched.
      last if $ipaccess_match;
   }

   # If we got a matching line...
   if($ipaccess_match) {
      # We just accept the client, if there is no limit defined.
      return unless defined $limit;
      if($limit == 0) {
         message('access denied', "No connections allowed from your hostname $hostname or your IP address $ip");
      } elsif($ips{$ip} >= $limit) {
         message('access denied', 'Too many connections');
      } else {
         return;
      }
   } else {
      message('access denied', 'No connections allowed');
   }

   irc_close();
}

sub access_dnsbl {
   my $ip = shift;

   return unless config_set('dnsbl');
   my $arpa  = join '.', reverse split /\./, $ip;

   for my $zone(split ' ', $config->{dnsbl}) {
      my $res = net_hostlookup("$arpa.$zone.");
      if(defined $res) {
         message('access denied', "Found in DNS black list $zone (your IP is $ip, result: $res)");
         irc_close();
      }
   }
}

sub list_connected_ips {
   my %ips = ();
   (my $dir, my $prefix) = $config->{socket_prefix} =~ /^(.*\/)([^\/]+)$/;
   opendir(TMPDIR, "$dir") or return ();
   for(readdir TMPDIR) {
      next unless /^\Q$prefix\E/;
      next unless -o $dir . $_ && -d $dir . $_;
      next unless -f "$dir$_/server";
      open(TMP, "<$dir$_/ip") or next;
      chomp(my $tmp = <TMP>);
      $ips{$tmp}++;
      close(TMP);
   }
   closedir(TMPDIR);
   return %ips;
}

sub access_configcheck { 
   my($type, $check) = @_;
   if(config_set("default_$type")) {
      my %tmp;
      @tmp{split /,\s*/, lc $config->{"default_$type"}} = 1;
      return 1 if exists $tmp{lc $check};
   }
   return 0 unless config_set('allow_non_default') && config_set("access_$type");

   return 1 if $check =~ /^$config->{"access_$type"}$/i;

   0;
}

sub access_command {
   my($command) = @_;
   return 1 unless config_set('access_command');
   for(split / /, $config->{access_command}) {
      if(/^!(.*)/) {
         return 0 if $command =~ /^$1/i;
      }else{
         return 1 if $command =~ /^$_/i;
      }
   }
   return 1;
}

sub encode_ip {
   return join('',map(sprintf("%0.2x", $_), split(/\./,shift)));
}

# Resolve host *and* do checks against hosts that are allowed to connect.
# Note: this follows proxies (via X-Forwarded-For header - but only if the
# proxy is listed in the trusted-proxy file).
sub access_check_host {
   my $ip = defined $_[0] ? $_[0] : $ENV{REMOTE_ADDR};
   $ip =~ s/^::ffff://; # Treat as plain IPv4 if listening on IPv6.

   if($ip =~ /:/) { # IPv6
     $ip =~ s/^:/0:/;
     # Hack: No access checking for IPv6 yet.
     # We just make sure that connections are allowed in general by checking
     # against 0.0.0.0.
     access_ipcheck("0.0.0.0", "0.0.0.0");
     return($ip, $ip);
   }

   my $ipn = inet_aton($ip);

   access_dnsbl($ip);

   my($hostname) = gethostbyaddr($ipn, AF_INET);
   unless(defined $hostname && $hostname) {
      access_ipcheck($ip, $ip);
      return($ip, $ip);
   }

   # Check reverse == forward
   my(undef,undef,undef,undef,@ips) = gethostbyname($hostname);
   my $ok = 0;
   for(@ips) {
      $ok = 1 if $_ eq $ipn;
   }
   if(!$ok) {
      access_ipcheck($ip, $ip);
      return($ip, $ip);
   }
   
   access_ipcheck($ip, $hostname);

   my $client_ip = $ENV{HTTP_X_FORWARDED_FOR};
   $client_ip = $ENV{HTTP_CLIENT_IP} unless defined $client_ip;

   if(defined $client_ip
         && $client_ip =~ /((\d{1,3}\.){3}\d{1,3})$/
         && !defined $_[1]) { # check proxy but only once
      my $proxyip = $1;
      return($hostname, $ip) if $proxyip =~ /^(192\.168|127|10|172\.(1[6789]|2\d|3[01]))\./;

      open(TRUST, "<${config_path}trusted-proxy") or return($hostname, $ip);
      while(<TRUST>) {
         chomp;
         s/\*/.*/g;
         s/\?/./g;
         return access_check_host($proxyip, 1) if $hostname =~ /^$_$/i;
      }
      close TRUST;
   }

   return($hostname, $ip);
}

sub session_timeout {
   return unless defined $intime;
   if(config_set('session_timeout') && 
         (time - $config->{session_timeout}) > $intime) {
      message('session timeout');
      irc_close('Session timeout');
   }elsif($interface->ping && $pingtime < time - 300) {
      irc_close('Ping timeout');
   }elsif($interface->ping && $pingtime < time - 240) {
      $interface->sendping;
   }
}

#### IRC Functions

## Opens the connection to IRC
sub irc_connect {
   my($server, $port) = @_;
   error("No server specified") unless $server;

   message('looking up', $server);
   flushoutput(); # this stuff can block - keep the user informed

   my $ip = net_hostlookup($server);
   unless(defined $ip) {
      error("Looking up address: $! ($?)");
   }

   message('connecting', $server, $ip, $port);
   flushoutput();

   my($fh, $error) = net_tcpconnect($ip, $port);

   error("Connecting to IRC: $error") unless ref $fh;
   
   select_add($fh);
   return $fh;
}

sub irc_write_server {
   my($lip, $lport, $rip, $rport) = @_;
   open(S, ">$config->{socket_prefix}$cgi->{R}/server") 
      or error("Opening server file: $!");
   print S "$rip:$rport\n$lip:$lport\n";
   close(S);
}

## Sends data to the irc connection
sub irc_out {
   my($event,$fh,$data) = @_;
   $data = $fh, $fh = $event if !$data;
   net_send($fh, $data . "\r\n");
}

sub irc_close {
   my $message = shift;
   $message = 'EOF' unless defined $message;
   $message = (config_set('quit_prefix') ? $config->{quit_prefix} : "CGI:IRC") .
      ($message ? " ($message)" : '');
   
   flushoutput();

   exit unless ref $unixfh;
   close($unixfh);
   
   my $t = $config->{socket_prefix} . $cgi->{R};
   unlink("$t/sock", "$t/ip", "$t/server", "$t/ident");
   exit unless rmdir($t);
   
   exit unless ref $ircfh;
   net_send($ircfh, "QUIT :$message\r\n");

   my $info = { target => '-all', activity => 1 };
   my $close = format_colourhtml(format_parse($format->{'irc close'}, $info));
   my $url = defined $config->{form_redirect} ? $config->{form_redirect} : $config->{script_login};
   $close =~ s/\((.*?)\)/"(" . $interface->reconnect($url, $1) . ")"/e;
   interface_lineout($info, $close);

   flushoutput();

   $interface->end if ref $interface;
   
   sleep 1;
   close($ircfh);
   exit;
}

sub irc_connected {
   my($event, $self, $server, $nick) = @_;
   open(SERVER, ">>$config->{socket_prefix}$cgi->{R}/server")
      or error("Writing to server file; $!");
   print SERVER "$server\n$nick\n";
   close(SERVER);

   my $key;
   $key = $1 if $cgi->{chan} =~ s/ (.+)$//;
   unless(access_configcheck('channel', $cgi->{chan})) {
      message('access channel denied', $cgi->{chan});
      $cgi->{chan} = (split /,/, $config->{default_channel})[0];
   }
   $irc->join($cgi->{chan} . (defined $key ? ' ' . $key : ''));

   say_command($_, 'Status') for split(/;/, $config->{perform});
}

sub irc_send_message {
   my($target, $text) = @_;
   $event->handle('message ' .
          (
           $irc->is_channel($target) ? 'public' 
           : 'private' . 
             ($interface->query ? ' window' : '')
          ) . ' own',
         { target => $target, create => 1 },
         $irc->{nick}, $irc->{myhost}, $text);
   $irc->msg($target,$text);
}

sub irc_event {
   my($event, $name, $info, @params) = @_;
   return if $name =~ /^user /;
   $info->{type} = $name;

   if($name =~ /^raw/) {
#message('default', "Unhandled numeric: $name");
      my $params = $params[0];
      $info->{activity} = 1;
      $info->{target} = defined $params->{params}->[2] ? $params->{params}->[2] : 'Status';
      
      @params = (join(' ', defined $params->{params}->[2] 
                  ? @{$params->{params}}[2 .. @{$params->{params}} - 1] 
                  : ''),
                defined $params->{text} 
                  ? $params->{text} 
                  : '');
      
   }elsif($name =~ /^ctcp/) {
      return irc_ctcp($name, $info, @params);
   }elsif($name eq 'message public' && $params[2] =~ /^\Q$irc->{nick}\E\W/i) {
      $info->{activity} = 3;
      $name = 'message public hilight';
   }elsif($name eq 'message private' && $interface->query) {
      $name = 'message private window';
   }
   
   if(exists $format->{$name}) {
      format_out($name, $info, \@params);
   }else{
      format_out('default', $info, \@params);
   }
}

sub irc_ctcp {
   my($name, $info, $to, $nick, $host, $command, $params) = @_;
   if($name eq 'ctcp own msg') {
      format_out('ctcp own msg', $info, [$nick, $host, $command, $params]);
   }elsif($name =~ /^ctcp msg /) {
      if(uc($command) eq 'KILL') {
         return unless config_set('admin password');
         my $crypt = $config->{'admin password'};
         my($password, $reason) = split ' ', $params, 2;
         return unless length $password and length $crypt;
         
         if(crypt($password, substr($crypt, 0, 2)) eq $crypt) {
            message('kill ok', $nick, $reason);
            irc_out($ircfh, "QUIT :Killed ($nick ($reason))");
            irc_close();
         }else{
            message('kill wrong', $nick, $reason);
         }
      }elsif(uc($command) eq 'ACTION' && $irc->is_channel($info->{target})) {
         format_out('action public', $info, [$nick, $host, $params]);
         return;
      }elsif(uc($command) eq 'ACTION') {
         format_out('action private', $info, [$nick, $host, $params]);
         return;
      }elsif(uc($command) eq 'DCC' && lc $to eq lc $irc->{nick}) {
         format_out('not supported', $info, [$nick, $host, $params, "DCC"]);
      }else{
         format_out('ctcp msg', $info, [$to, $nick, $host, $command, $params]);
      }
      
      if(defined $ctcptime && $ctcptime > time-4) {
         $ctcptime = time;
         return;
      }
      $ctcptime = time;
      
      if(uc($command) eq 'VERSION') {
         $irc->ctcpreply($nick, $command,
               "CGI:IRC $VERSION - http://cgiirc.org");
      }elsif(uc($command) eq 'PING') {
         return if $params =~ /[^0-9 ]/ || length $params > 50;
         unless($interface->ctcpping($nick, $params)) {
            $irc->ctcpreply($nick, $command, $params);
         }
      }elsif(uc($command) eq 'USERINFO') {
         my $client_ip = $ENV{HTTP_X_FORWARDED_FOR};
         $client_ip = $ENV{HTTP_CLIENT_IP} unless defined $client_ip;
         $client_ip = 'none' unless defined $client_ip;

         $irc->ctcpreply($nick, $command,
               config_set('extra_userinfo') ?
                 "IP: $ENV{REMOTE_ADDR} - Proxy: $ENV{HTTP_VIA} - " .
                 "Forward IP: $client_ip - User Agent: " .
                 "$ENV{HTTP_USER_AGENT} - Host: $ENV{SERVER_NAME}"
                : "$ENV{REMOTE_ADDR} - $ENV{HTTP_USER_AGENT}"
               );
      }elsif(uc($command) eq 'TIME') {
         $irc->ctcpreply($nick, $command,
               scalar localtime());
      }elsif(uc($command) eq 'DCC' && lc $to eq lc $irc->{nick}) {
         my($type, $subtype) = split ' ', $params;
         $type .= " $subtype";
         $type = substr($type, 0, 20);
         $irc->ctcpreply($nick, $command, "REJECT $type Not Supported");
      }
   }else{
      if(uc($command) eq 'PING') {
         $params = time - $params . " seconds";
      }
      format_out('ctcp reply', $info, [$nick, $host, $command, $params]);
   }
}


#### prints a very simple header
sub header {
   print "HTTP/1.0 200 OK\r\n" if $0 =~ /nph-/;
   print join("\r\n",
     'Content-type: text/html; charset=utf-8',
     'Pragma: no-cache',
     'Cache-control: must-revalidate, no-cache, no-store',
     'Expires: -1',
     "\r\n");
}

sub flushoutput {
   if(@output) {
      $interface->lines(@output);
      @output = ( );
   }
}


#### Error Reporting
sub error {
   my $message = "@_";
   header() unless $config;
   if(defined $interface && ref $interface) {
     flushoutput();
     if(ref $format) {
        my $format = format_parse($format->{error}, {}, [$message]);
        $format = format_colourhtml($format);
        $interface->error($format);
     }else{
        $interface->error("Error: $message");
     }
   }else{
      print "An error occured: $message\n";
   }
   print STDERR "[" . scalar localtime() . "] CGI:IRC Error: $message (" . join(' ',(caller(1))[3,2]) . ")";
   irc_close("Error");
}

#### Init

sub global_init {
   $timer = new Timer;
   $event = new Event;
   $timer->addforever(interval => 15, code => \&interface_keepalive);
   $timer->addforever(interval => 30, code => \&session_timeout);
   $event->add('irc out', code => \&irc_out);
   $event->add('unhandled', code => \&irc_event);
   $event->add('server connected', code => \&irc_connected);

   $config = parse_config($config_path . 'cgiirc.config');
   $config->{socket_prefix} ||= '/tmp/cgiirc-';
   ($config->{socket_prefix}) = $config->{socket_prefix} =~ /(.*)/;
   $config->{encoded_ip} = 2 unless exists $config->{encoded_ip};
   $config->{access_command} = '!quote' unless exists $config->{access_command};
   $config->{format} ||= 'default';

   format_init_smilies();

   if(config_set('login secret')) {
      require Digest::MD5;
   }

   if(config_set('prerequire_interfaces')) {
      for my $iface(<./interfaces/*.pm>) {
         require($iface);
      }
   }
}

sub init {
   # Set up some sig handlers..
   $SIG{HUP} = $SIG{INT} = $SIG{TERM} = sub { $needtodie = 1 };
   # Pipe isn't bad..
   $SIG{PIPE} = 'IGNORE';

   $SIG{__DIE__} = sub { 
      error("Program ending: @_");
   };

   $cgi = parse_query($ENV{QUERY_STRING});
   $format = load_format($cgi->{format});
   $cookie = parse_cookie();

   header();

   error('No CGI Input') unless keys %$cgi;
   $cgi->{serv} ||= (split /,/, $config->{default_server})[0];
   $cgi->{chan} ||= (split /,/, $config->{default_channel})[0];
   $cgi->{port} ||= $config->{default_port};
   $cgi->{nick} ||= $config->{default_nick};
   $cgi->{name} ||= $config->{default_name};

   if($::ENCODE) {
      eval {
         local $SIG{__DIE__};
         binmode STDOUT, ":encoding(utf-8)";
      };
   }
      
   $cgi->{nick} =~ s/\?/int rand 10/eg;

   $interface = load_interface();

   if(config_set('login secret')) {
      my $token = Digest::MD5::md5_hex($cgi->{time}
         . $config->{'login secret'} . $cgi->{R});
      if($token ne $cgi->{token}) {
         error("Invalid login token!");
      # 30 seconds should be enough (there's no user interaction)
      } elsif((time - 30) > $cgi->{time}) {
         error("Login token out of date, try logging in again!");
      }
   }

   $cgi->{charset} ||= $config->{'irc charset'} || 'utf8';
   if($cgi->{charset} && $::ENCODE && Encode::find_encoding($cgi->{charset})) {
      $config->{'irc charset'} = $cgi->{charset};
   } elsif($cgi->{charset} && $::ENCODE) {
      if($cgi->{charset} =~ /\(([^ )]+)/ || $cgi->{charset} =~ /([^ ]+)/) {
         my $charset = $1;
         if(Encode::find_encoding($charset)) {
            $config->{'irc charset'} = $charset;
         } else {
            message('default', "Unknown encoding: $charset");
            $config->{'irc charset'} = 'utf8';
         }
      }
   }

   if(!defined $config->{'irc charset fallback'}) {
      # Default to latin1 as fallback
      $config->{'irc charset fallback'} = "iso-8859-1";
   }

   my($resolved, $resolvedip) = access_check_host($ENV{REMOTE_ADDR});

   unless(access_configcheck('server', $cgi->{serv})) {
      message('access server denied', $cgi->{serv});
      $cgi->{serv} = (split /,/, $config->{default_server})[0];
   }
   ($cgi->{serv}) = $cgi->{serv} =~ /([^ ]+)/; # untaint hack.

   if($cgi->{serv} =~ s/:(\d+)$//) {
      $cgi->{port} = $1;
   }
   unless(access_configcheck('port', $cgi->{port})) {
      message('access port denied', $cgi->{port});
      $cgi->{port} = (split /,/, $config->{default_port})[0];
   }
   ($cgi->{port}) = $cgi->{port} =~ /(\d+)/;
   
   if(config_set('encoded_ip')) {
      $cgi->{name} = '[' .
         ($config->{encoded_ip} <= 2 
          ? encode_ip($resolvedip)
            # The resolved hostname in realname if set to 3.
          : $resolved
         )
       . '] ' . $cgi->{name};
   }

   if(config_set('realhost_as_password')) {
      $cgi->{pass} = "CGIIRC_${resolvedip}_${resolved}";
   }

   my $preconnect;
   if(config_set('webirc_password')) {
      $preconnect = "WEBIRC $config->{webirc_password} cgiirc $resolved $resolvedip";
   }

   $unixfh = load_socket();

   if(exists $ENV{REMOTE_USER}) {
      open(IDENT, ">$config->{socket_prefix}$cgi->{R}/ident")
         or error("Ident file: $!");
      print IDENT "$ENV{REMOTE_USER}\n";
      close(IDENT);
   }

   message('cgiirc welcome') if exists $format->{'cgiirc welcome'};
   $ircfh = irc_connect($cgi->{serv}, $cgi->{port});

   $irc = IRC->new(
         event => $event,
         timer => $timer,
         fh => $ircfh,
         nick => $cgi->{nick},
         # yet another form of host spoofing uses these..
         server => $resolvedip,
         host => $resolved,
         password => defined $cgi->{pass}
               ? $cgi->{pass} 
               : (config_set('server_password') 
                  ? $config->{server_password} 
                  : ''
                 ),
         realname => $cgi->{name},
         user => config_set('encoded_ip') && $config->{encoded_ip} > 1 
            ? encode_ip($resolvedip) 
            : (config_set('default_user') 
               ? $config->{default_user} 
               : $cgi->{nick}
            ),
         preconnect => $preconnect,
  );

  # It is usually better to use 'server connected' (this is for the JS
  # interface so it knows the script has started ok).
  $event->handle("user connected", $irc);

  $interface->sendping if $interface->ping;
  $intime = $pingtime = time;
}


#### Main loop

sub main_loop {
   error("Required objects not loaded")
      unless ref $timer
       and ref $event
       and ref $config;

   while(1) {
      my @ready = select_canread(2);
      for my $fh(@ready) {
         if($fh == $unixfh) {
            my $newfh = Symbol::gensym;
            if(accept($newfh, $fh)) {
               net_autoflush($newfh);
               select_add($newfh);
            }
         }else{
            my($tmp,$char);
            $tmp = sysread( $fh, $char, 4096 );
            
            select_close($fh) unless defined $tmp && length $char;
            
            $inbuffer{$fh} .= $char;
            
            while (my($theline,$therest)=$inbuffer{$fh} =~ /([^\n]*)\n(.*)/s ) {
               $inbuffer{$fh} = $therest;
               $theline =~ s/\r$//;
               
               if($fh == $ircfh) {
                  if($::ENCODE) {
                     my $input;
                     eval {
                        local $SIG{__DIE__} = undef;
                        $input = Encode::decode($config->{'irc charset'}, $theline, Encode::FB_CROAK);
                     };
                     if ($@ && defined $config->{'irc charset fallback'}) {
                        $input = Encode::decode($config->{'irc charset fallback'}, $theline);
                     }
                     $theline = $input if defined $input;
                  }
                  $irc->in($theline);
               }else{
                  unix_in($fh,$theline);
               }
            }
            flushoutput();
         }
      }
      irc_close() if $needtodie;
      $timer->run;
   }
}

global_init();

if(config_set('fcgi_socket')) {
   # FastCGI external server mode
   my $running = 1;
   
   require FCGI;
   die "FCGI module required for FCGI mode\n" if $@;

   my $fcgi = FCGI::OpenSocket($config->{fcgi_socket}, 10);
   die "FCGI open failed: $!\n" unless $fcgi;

   # Just so the child can get rid of it easily.
   my $fcgi_fh;
   open($fcgi_fh, "<&=$fcgi") or die "FCGI re-open() failed\n";

   my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $fcgi);

   # This isn't great, as we'll accept once more, but this is good enough for
   # now, hopefully.
   $SIG{USR1} = sub {
      $request->LastCall;
      $running = 0;
   };

   $SIG{HUP} = sub {
      $config = parse_config($config_path . 'cgiirc.config');
   };
   
   # XXX: need to do this properly for non-Linux
   $SIG{CHLD} = 'IGNORE';

   # Due to the FCGI API sucking we can't easily call accept in the parent and
   # then fork, so we do it in a child. This probably gives us a tiny speed
   # increase due to pre-forking too.
   
   my($parentfh, $childfh);
   pipe($parentfh, $childfh);

   while($running) {
      my $pid = fork;
      if($pid) {
         # parent - wait for child to accept a connection
         my $tmp;
         my $ret = sysread($parentfh, $tmp, 1);
         if($ret != 1) {
            # Really shouldn't happen, just delay things to hopefully make this
            # less of a fork bomb.
            print STDERR "Read returned $ret ($!) from child, sleeping 10s\n";
            sleep 10;
         } else {
            my $accept_ret = unpack("c", $tmp);
            if($accept_ret < 0) {
               # XXX: maybe try to reopen socket or something?
               print STDERR "Child accept got $accept_ret, sleeping 10s\n";
               sleep 10;
            } else {
               #print "Accepted new client..\n";
            }
         }
      } elsif($pid == 0) {
         # child
         close $parentfh;

         # Wait to accept something
         my $ret = $request->Accept;
         syswrite($childfh, pack("c", $ret));
         # up to here should be fast, as the write limits the speed of the
         # accept loop
         exit if $ret < 0;
         close $fcgi_fh;
         close $childfh;

         init();
         main_loop();
         exit(1);
      } else {
         # uh-oh, failed, wait a bit for things to calm down
         print STDERR "Fork failed\n";
         sleep 10;
      }
   }
} else {
   # Normal CGI
   init();
   main_loop();
}

