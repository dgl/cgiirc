#! /usr/bin/perl -w
# CGI:IRC - http://cgiirc.sourceforge.net/
# Copyright (C) 2000-2002 David Leadbeater <cgiirc@dgl.cx>

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
use lib qw/modules interfaces/;
use vars qw(
	  $VERSION @handles %inbuffer $select_bits
	  $unixfh $ircfh $cookie $ctcptime
	  $timer $event $config $cgi $irc $format $interface
   );

($VERSION =
'$Name:  $ 0_5_CVS $Id: nph-irc.cgi,v 1.20 2002/03/27 17:46:37 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;
$VERSION =~ s/_/./g;

use Socket;
use Symbol; # gensym
$|++;
# Check for IPV6. Bit yucky but avoids errors when module isn't present
BEGIN {
   eval('use Socket6; $::IPV6++ if defined $Socket6::VERSION');
   unless(defined $::IPV6) {
      $::IPV6 = 0;
	  eval('sub AF_INET6 {0}');
   }
}

# My own Modules
use Timer;
use Event;
use IRC;
use Command;
require 'parse.pl';

my $needtodie = 0;
$SIG{HUP} = $SIG{INT} = $SIG{TERM} = $SIG{PIPE} = sub { $needtodie = 1 };

$SIG{__DIE__} = sub { 
   error("Program ending: @_");
   irc_close();
};

# DEBUG
#use Carp;
#$SIG{__DIE__} = \&confess;

#### Network Functions

## Returns the address of a host (handles both IPv4 and IPv6)
## Return value: (ipv4,ipv6)
sub net_hostlookup {
   my($host) = @_;

   if($::IPV6) {
      my($family,$socktype, $proto, $saddr, $canonname, @res) = 
      getaddrinfo($host,undef, AF_UNSPEC, SOCK_STREAM);
      return undef unless $family;

	  if($family == AF_INET) {
        return (unpack_sockaddr_in($saddr))[1];
	  }elsif($family == AF_INET6) {
        return (undef,(unpack_sockaddr_in6($saddr))[1]);
	  }
   }else{ # IPv4
      return (gethostbyname($host))[4];
   }
}

## Figures out if it's IPv4 or IPv6 and makes a human readable IP address
sub net_ntoa {
   my($n) = @_;
   return inet_ntoa($n) if length $n == 4;
   return inet_ntop(AF_INET6, $n) if length $n > 4 && $::IPV6;
   0;
}

## Connects a tcp socket and returns the file handle
## inet_addr should be the output of net_gethostbyname, family is either
## AF_INET or AF_INET6. 1 on sucess, 0 on failure
sub net_tcpconnect {
   my($inet_addr, $port, $family) = @_;
   my $fh = Symbol::gensym;
   
   my $saddr;
   if($family == AF_INET) {
	  $saddr = sockaddr_in($port, $inet_addr);
   }elsif($family == AF_INET6) {
	  $saddr = sockaddr_in6($port, $inet_addr);
   }else{
	  return 0;
   }

   socket($fh, $family, SOCK_STREAM, getprotobyname('tcp')) or return(0, $!);
   setsockopt($fh, SOL_SOCKET, SO_KEEPALIVE, pack("l", 1)) or return(0, $!);
   connect($fh, $saddr) or return (0,$!);

   select($fh);
   $|++;
   select(STDOUT);

   return $fh;
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

   return $fh;
}

## Send data to specific filehandle
sub net_send {
   my($fh,$data) = @_;
   syswrite($fh, $data, length $data);
}

#### Select Helper Functions
## Code adapted from IO::Select.pm by Graham Barr

## Adds file handle into @handles and fileno into the bit vector
sub select_add {
   my($fh) = @_;
   my $fileno = select_fileno($fh);
   
   if(defined $handles[$fileno]) {
      $handles[$fileno] = $fh;
	  return;
   } else {
      $handles[$fileno] = $fh;
   }

   $select_bits = '' unless defined $select_bits;
   vec($select_bits, $fileno, 1) = 1;
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

   splice(@handles, $fileno, 1);
   vec($select_bits, $fileno, 1) = 0;
}

## Returns a fileno
sub select_fileno {
   fileno(shift);
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
   my $formatname = $config->{format};
   if($cgi->{format} && $cgi->{format} !~ /[^A-Za-z0-9]/) {
	  $formatname = $cgi->{format};
   }
   return parse_config('formats/' . $formatname);
}

## Prints a nicely formatted line
## the format is the format name to use, taken from the %format hash
## the params are passed to the format
sub format_out {
   my($formatname, $info, @params) = @_;
   return unless exists $format->{$formatname};

   my $line = format_parse($format->{$formatname}, $info, @params);
   $line = format_colourhtml($line);
   interface_lineout($info, $line);
}

sub message {
   my($formatname, @params) = @_;
   my $info = { target => 'Status', activity => 1 };
   format_out($formatname, $info, @params);
}

## Formats IRC Colours and Styles into HTML and makes URLs clickable
sub format_colourhtml {
   my($line) = @_;

   $line =~ s/\&/\&amp;/g;
   $line =~ s/</\&lt;/g;
   $line =~ s/>/\&gt;/g;
   $line =~ s/"/\&quot;/g;
   $line =~ s!((https?|ftp):\/\/[^$ ]+)!<a href="@{[format_remove($1)]}" target="cgiirc@{[int(rand(200000))]}">$1</a>!gi;
   $line =~ s!(^|\s|\()(www\..*?)(\.?($|\s)|\))!$1<a href="http://@{[format_remove($2)]}" target="cgiirc@{[int(rand(200000))]}">$2</a>$3!gi;

   return format_remove($line) if $config->{removecolour};

   $line=~ s/\003(\d{1,2})(\,(\d{1,2})|)([^]*|.*?$)/
	  my $me = "<font ";
      my $fg = sprintf("%0.2d",$1);
	  my $bg = length $3 ? sprintf("%0.2d",$3) : '';

      if(length $bg) {
		 $me .= "style=\"background: ".$format->{$bg}."\" "
	  }

	  $me .= "color=\"$format->{$fg}\">$4<\/font>";
	  $me
   /eg;
   $line=~ s/\002(.*?)(\002|$)/<b>$1<\/b>/g;
   $line=~ s/\022(.*?)(\022|$)/<u>$1<\/u>/g;
   $line=~ s/\037(.*?)(\037|$)/<u>$1<\/u>/g; 

   return format_remove($line);
}

## Removes all IRC formating characters
sub format_remove {
   my($line) = @_;
   $line =~ s/\003(\d{1,2})(\,(\d{1,2})|)//g;
   $line =~ s/[\x00-\x1f]//g;
   return $line;
}

## Lowlevel code that deals with the format parsing
## This is probably rather ugly, but it works :)
sub format_parse {
   my($line, $info, @params) = @_;
   return unless defined $line;
   # l == last char
   # f == char that ends current look
   # s == current look
   # c == contents of current look
   # o == overall output
   # r == count of bracket matching
   my($l,$f,$s,$c,$o,$r) = ('','','','','','');

   for my $b((split //, $line),'') {
      if(!$s && ($b eq '$' || $b eq '%')) { # Sets variables for a $ or %
         $s = $b;
         $f = ' ';
      }elsif(!$s && $b eq '{') { # Sets a {
         $s = '{';
         $f = '}';
	   # Figures out when a $ or { ends
      }elsif($b eq $f || !length $b || (($s eq '%' || $s eq '$') && $b =~ /[^a-zA-Z0-9,_-]/)) {
         if($s eq '$') {
			$o .= format_varexpand($c, $info, @params);
            $s = $f = $c = '';
			if($b eq '$' || $b eq '%') {
			   $s = $b;
			   $f = ' ';
			}else{
               $o .= $b;
			}
	     }elsif($s eq '%') {
			if($c eq '_') {
			   $o .= "\002";
			}elsif($c eq 'n') {
			   $o .= "\003$format->{fg},$format->{bg}";
			} else {
			   $o .= "\003$c";
			}
			$s = $f = $c = '';
			if($b eq '$' || $b eq '%') {
			   $s = $b;
			   $f = ' ';
			}else{
			   $o .= $b;
			}
         }elsif($s eq '{' && $r) { # bracket matching stuff
            $r--;
            $c .= $b;
         }elsif($s eq '{') {
            # actual end of a {format}, recurses back into this sub
            $c =~ /([^ ]+) ?(.*)?/;
			# map stuff is to translate $0 and so on the params
            $o .= format_parse($format->{$1}, $info, map{ s/^\$([A-Z0-9-]+)/format_varexpand($1, $info, @params)/eg; $_ } split(/ /, $2));
            $s = $f = $c = '';
         } else {
			$s = $f = $c = '';
			$o .= $b;
		 }
      }elsif($b eq '{' && $s eq '{') {
         $r++;
         $c .= $b;
      }elsif($s) { # When $s (item being parsed is set, add to $c)
         $c .= $b;
      }else{ # Normal - add direct to output
         $o .= $b;
      }
      $l = $b;
   } # }}} stop bracket matching in vim messing up :)

   return $o;
}

sub format_varexpand {
   my($c, $info, @params) = @_;
   return '' unless defined $c;
   local $^W = 0;
   my $o = '';
   if($c =~ /^(\d+)\-$/) {
      $o = join(' ', @params[$1 .. $#params]);
   }elsif($c !~ /\D/ && defined $params[$c]) { # Normal Params
      $o = $params[$c];
   }elsif($c eq 'VERSION') {
      $o = $VERSION;
   }elsif($c eq 'T' && exists $info->{target}) {
      $o = $info->{target};
      # ..add more special variables here..
   }
   return $o;
}

#### Interface Functions

## Loads the default interface.
sub load_interface {
   my $name = defined $cgi->{interface} ? $cgi->{interface} : 'default';
   $name =~ s/[^a-z]//gi;
   require('interfaces/' . $name . '.pm');
   $interface = $name->new($event,$timer, $config);
   $interface->header($config, $cgi);

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
   $interface->line($type, $target, $html);
}

#### Unix Domain Socket Functions

## Opens the listening socket
sub load_socket {   
   error('Communication socket name is invalid')
      if !$cgi->{R} or $cgi->{R} =~ /[^A-Za-z0-9]/;
   error('Communication socket already exists')
      if -e $config->{socket_prefix}.$cgi->{R};

   mkdir($config->{socket_prefix}.$cgi->{R}, 0700) or error("Mkdir error: $!");

   open(IP, ">$config->{socket_prefix}$cgi->{R}/ip") or error("Open error: $!");
   print IP "$ENV{REMOTE_ADDR}\n";
   print IP "$ENV{HTTP_X_FORWARDED_FOR}\n" if exists $ENV{HTTP_X_FORWARDED_FOR};
   close(IP);

   my($socket,$error) = 
	  net_unixconnect($config->{socket_prefix}.$cgi->{R}.'/sock');

   error("Error opening socket: $error") unless ref $socket;

   select_add($socket);

   return $socket;
}

sub unix_in {
   my($fh, $line) = @_;
   my $input = parse_query($line);
   
   if($cookie && (!defined $input->{COOKIE} || $input->{COOKIE} ne $cookie)) {
      select_close($fh);
      return;
   }

   if($input->{cmd}) {
	  input_command($input->{cmd}, $input);
   }

   if(defined $input->{s} && $input->{s} =~ /^\w+$/) {
	  net_send($fh, interface_show($input->{s}, $input));
   }

   select_close($fh);
}

sub input_command {
   my($command, $params) = @_;
   if($command eq 'say') {
	  say_command($params->{say}, $params->{target});
   }elsif($command eq 'quit') {
	  irc_close();
   }
}

sub say_command {
   my($say, $target) = @_;
   return unless length $say;
   $say =~ s/(\n|\r|\0)//sg;
   $target =~ s/(\n|\r|\0)//sg;
   $say =~ s/\%C/\003/g;
   $say =~ s/\%B/\002/g;
   $say =~ s/\%U/\022/g;
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
   my($ip) = $ENV{REMOTE_ADDR};
   return  1 unless config_set('ip_access_file');

   open(IP, "<$config->{ip_access_file}") or return 1;
   my %ips = list_connected_ips();
   while(<IP>) {
	  next if /^(#|\s*$)/;
	  s/\s+#.*$//g;
	  my($check,$limit) = split(' ', $_, 2);
	  $check =~ s/\./\\./g;
	  $check =~ s/\*/\\d+/g;
	  if($ip =~ /^$check$/) {
		 return 1 unless defined $limit;
		 if($limit == 0) {
		    message('access denied', 'No connections allowed');
			exit;
		 }elsif($ips{$ip} >= $limit) {
		    message('access denied', 'Too many connections');
			exit;
		 }
		 return 1;
	  }
   }
   close(IP);

   message('access denied', 'No connections allowed');
   exit;
}

sub list_connected_ips {
   my %ips = ();
   (my $dir, my $prefix) = $config->{socket_prefix} =~ /^(.*\/)([^\/]+)$/;
   opendir(TMPDIR, "$dir") or return ();
   for(readdir TMPDIR) {
	  next unless /^\Q$prefix\E/;
	  next unless -o $dir . $_ && -d $dir . $_;
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
   return 0 unless config_set('allow_non_default') &&config_set("access_$type");

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

#### IRC Functions

## Opens the connection to IRC
sub irc_connect {
   my($server, $port) = @_;
   message('looking up', $server);

   my($ipv4,$ipv6) = net_hostlookup($server);
   unless(defined $ipv4 or defined $ipv6) {
	  error("Looking up address: $!");
   }

   message('connecting', $server, net_ntoa($ipv4 ? $ipv4 : $ipv6), $port);
   my($fh,$error) = net_tcpconnect($ipv4 ? $ipv4 : $ipv6, $port, $ipv4 ? AF_INET : AF_INET6);
   
   error("Connecting to IRC: $error") unless ref $fh;
   select_add($fh);
   return $fh;
}

## Sends data to the irc connection
sub irc_out {
   my($event,$fh,$data) = @_;
   $data = $fh, $fh = $event if !$data;
#message('default', "-> Server: $data");
   net_send($fh, $data . "\r\n");
}

sub irc_close {
   exit unless ref $unixfh;
   close($unixfh);
   my $t = $config->{socket_prefix} . $cgi->{R};
   unlink("$t/sock", "$t/ip", "$t/server");
   exit unless rmdir($t);
   exit unless ref $ircfh;
   net_send($ircfh, "QUIT :CGI:IRC $VERSION [EOF]\r\n");
   format_out('irc close', { target => '-all', activity => 1 });
   $interface->end if ref $interface;
   sleep 1;
   close($ircfh);
   exit;
}

sub irc_connected {
   my($event, $self, $server, $nick) = @_;
   open(S, ">$config->{socket_prefix}$cgi->{R}/server") or error("Server file: $!");
   print S "$server\n";
   close(S);
   my $key;
   $key = $1 if $cgi->{chan} =~ s/ (.+)$//;
   unless(access_configcheck('channel', $cgi->{chan})) {
	  message('access channel denied', $cgi->{chan});
	  $cgi->{chan} = (split /,/, $config->{default_channel})[0];
   }
   $irc->join($cgi->{chan} . (defined $key ? ' ' . $key : ''));
}

sub irc_send_message {
   my($target, $text) = @_;
   $event->handle('message ' .
		($irc->is_channel($target) ? 'public' : 'private' . ($interface->query ? ' window ' : '')) . ' own', 
		{ target => $target }, $irc->{nick}, $irc->{myhost}, $text);
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
	  @params = (join(' ', defined $params->{params}->[2] ? @{$params->{params}}[2 .. @{$params->{params}} - 1] : ''),
		defined $params->{text} ? $params->{text} : '');
   }elsif($name =~ /^ctcp/) {
	  return irc_ctcp($name, $info, @params);
   }elsif($name eq 'message public' && $params[2] =~ /^\Q$irc->{nick}\E\W/i) {
	  $info->{activity} = 3;
	  $name = 'message public hilight';
   }elsif($name eq 'message private' && $interface->query) {
	  $name = 'message private window';
   }

   if(exists $format->{$name}) {
	  format_out($name, $info, @params);
   }else{
      format_out('default', $info, @params);
   }
}

sub irc_ctcp {
   my($name, $info, $nick, $host, $command, $params) = @_;
   if($name eq 'ctcp own msg') {
	  format_out('ctcp own msg', $info, $nick, $host, $command, $params);
   }elsif($name =~ /^ctcp msg /) {
	  if(uc($command) eq 'KILL') {
		 return;
	  }elsif(uc($command) eq 'ACTION' && $irc->is_channel($info->{target})) {
	     format_out('action public', $info, $nick, $host, $params);
		 return;
	  }elsif(uc($command) eq 'ACTION') {
		 format_out('action private', $info, $nick, $host, $params);
		 return;
	  }else{
	     format_out('ctcp msg', $info, $nick, $host, $command, $params);
	  }

	  if($ctcptime > time-4) {
		 $ctcptime = time;
		 return;
	  }
	  $ctcptime = time;
	  
	  if(uc($command) eq 'VERSION') {
		 $irc->ctcpreply($nick, $command,
			 "CGI:IRC $VERSION - http://cgiirc.sf.net/");
	  }elsif(uc($command) eq 'PING') {
		 return if $params =~ /[^0-9 ]/ || length $params > 50;
		 $irc->ctcpreply($nick, $command, $params);
	  }elsif(uc($command) eq 'USERINFO') {
		 $irc->ctcpreply($nick, $command,
			 "$ENV{REMOTE_ADDR} - $ENV{HTTP_USER_AGENT}");
	  }elsif(uc($command) eq 'TIME') {
		 $irc->ctcpreply($nick, $command,
			   scalar localtime());
	  }
   }else{
	  if(uc($command) eq 'PING') {
		 $params = time - $params . " seconds";
	  }
	  format_out('ctcp reply', $info, $nick, $host, $command, $params);
   }
}


#### prints a very simple header
sub header {
   print join("\r\n",
		 'HTTP/1.0 200 OK',
		 'Content-type: text/html',
         'Pragma: no-cache',
		 'Cache-control: must-revalidate, no-cache, no-store',
         'Expires: -1',
		 "\r\n");
}


#### Error Reporting
sub error {
   my $message = "@_";
   header() unless $config;
   if(defined $interface && ref $interface) {
     if(ref $format) {
        my $format = format_parse($format->{error}, {}, $message);
        $format = format_colourhtml($format);
        $interface->error($format);
     }else{
	     $interface->error("Error: $message");
     }
   }else{
      print "An error occured: $message\n";
	  print STDERR "An error occured: $message\n";
   }
   exit;
}

#### Init

sub init {
   $timer = new Timer;
   $event = new Event;
   $timer->addforever(interval => 15, code => \&interface_keepalive);
   $event->add('irc out', code => \&irc_out);
   $event->add('unhandled', code => \&irc_event);
   $event->add('server connected', code => \&irc_connected);

   $config = parse_config('cgiirc.config');
   $config->{socket_prefix} ||= '/tmp/cgiirc-';
   $config->{encoded_ip} = 2 unless exists $config->{encoded_ip};
   $config->{access_command} = '!quote' unless exists $config->{access_command};
   $config->{format} ||= 'default';

   header();

   $cgi = parse_query($ENV{QUERY_STRING});
   $cookie = parse_cookie();

   error('No CGI Input') unless keys %$cgi;
   $cgi->{serv} ||= (split /,/, $config->{default_server})[0];
   $cgi->{chan} ||= (split /,/, $config->{default_channel})[0];
   $cgi->{port} ||= $config->{default_port};
   $cgi->{nick} ||= $config->{default_nick};
   $cgi->{name} ||= $config->{default_name};

   $cgi->{nick} =~ s/\?/int rand 10/eg;

   $interface = load_interface();
   $format = load_format($cgi->{format});
 
   access_ipcheck();

   unless(access_configcheck('server', $cgi->{serv})) {
	  message('access server denied', $cgi->{serv});
	  $cgi->{serv} = (split /,/, $config->{default_server})[0];
   }

   if(config_set('encoded_ip')) {
	  $cgi->{name} = '[' .
        ($config->{encoded_ip} <= 2 ? # The real IP in realname if set to 3.
          encode_ip($ENV{REMOTE_ADDR}) : $ENV{REMOTE_ADDR})
       . '] ' . $cgi->{name};
   }

   $unixfh = load_socket();

   message('cgiirc welcome') if exists $format->{'cgiirc welcome'};

   $ircfh = irc_connect($cgi->{serv}, $cgi->{port});
   $irc = IRC->new(
		 event => $event,
		 timer => $timer,
		 fh => $ircfh,
		 nick => $cgi->{nick},
		 server => $cgi->{serv},
		 password => defined $cgi->{pass} ? $cgi->{pass} : (config_set('server_password') ? $config->{server_password} : ''),
		 realname => $cgi->{name},
		 user => config_set('encoded_ip') && $config->{encoded_ip} > 1 ? encode_ip($ENV{REMOTE_ADDR}) : (config_set('default_user') ? $config->{default_user} : 'cgiirc'),
   );
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
#message('default', "<- Server: $theline");
				  $irc->in($theline);
			   }else{
				  unix_in($fh,$theline);
			   }
			}
		 }
	  }
	  irc_close() if $needtodie;
	  $timer->run;
   }
}

init();
main_loop();

