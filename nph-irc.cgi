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

require 5.004;
use strict;
use lib qw/modules interfaces/;
use vars qw(
	  $VERSION @handles %inbuffer $select_bits
	  $unixfh $ircfh
	  $timer $event $config $cgi $irc $format $interface
   );

($VERSION =
'$Name:  $ $Id: nph-irc.cgi,v 1.5 2002/03/08 18:06:20 dgl Exp $'
) =~ s/^.*?(\d\S+) .*$/$1/;

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
   $format = parse_config($config->{format_dir} . '/' . $formatname);
}

## Prints a nicely formatted line
## the format is the format name to use, taken from the %format hash
## the params are passed to the format
## TODO document formats
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
   my $tmp = '/';
   $line =~ s/((https?|ftp):\/\/[^$ ]*)/<a href="@{[format_remove($1)]}" target="cgiirc@{[int(rand(200000))]}">$1<${tmp}a>/g;
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
   my $o;
   if($c !~ /\D/ && defined $params[$c]) { # Normal Params
      $o = $params[$c];
   }elsif($c =~ /(\d+)-\z/) {
      $o = join(' ', @params[$1 .. $#params]);
   }elsif($c eq 'VERSION') {
      $o = $VERSION;
   }elsif($c eq 'T' && exists $info->{target}) {
      $o = $info->{target};
      # ..add more special variables here..
   }else{
      $o = '';
   }
   return $o;
}

#### Interface Functions

## Loads the default interface.
sub load_interface {
   my $name = defined $cgi->{interface} ? $cgi->{interface} : 'default';
   $name =~ s/[^a-z]//gi;
   require('interfaces/' . $name . '.pm');
   $interface = $name->new($event);
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
   
   my($socket,$error) = net_unixconnect($config->{socket_prefix}.$cgi->{R});
   error("Error opening socket: $error") unless ref $socket;

   select_add($socket);

   return $socket;
}

sub unix_in {
   my($fh, $line) = @_;
   my $input = parse_query($line);
   
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
   $command =~ s/[\n\r\0]//g;
   $params =~ s/[\n\r\0]//g;
   if($command eq 'say') {
	  say_command($params->{say}, $params->{target});
   }elsif($command eq 'quit') {
	  irc_close();
   }
}

sub say_command {
   my($say, $target) = @_;
   if($say =~ m!^/!) {
	  if($say =~ s!^/ /!/!) {
		 irc_send_message($target, $say);
	  }else{
		 (my $command, my $params) = $say =~ m:^/([^ ]+)( (.+))?$:;
		 unless(defined $command && length $command) {
			return;
		 }

		 $command = Command->expand($command);
		 unless(access_command($command)) {
			message('command denied', $command);
			return;
		 }

		 my $error = Command->run($event, $irc, $command, $target, defined $params ? $params : '');
		 return 1 if $error == 100;
		 message('command error', $error);
		 return 0;
	  }
   }else{
	  irc_send_message($target, $say);
   }
}

#### Access Checking Functions

sub access_ipcheck {
   my($ip) = @_;
   open(IP, "<ipaccess") or return 1;
   while(<IP>) {
	  next if /^#/;
	  s/\./\\./g;
	  s/\*/.*/g;
	  return 0 if $ip =~ /^$_$/;
   }
   close(IP);
   return 1;
}

sub access_configcheck { 
   my($type, $check) = @_;
   if(exists $config->{"default_$type"}) {
	  my %tmp;
	  @tmp{split /,\s*/, lc $config->{"default_$type"}} = 1;
	  return 1 if exists $tmp{lc $check};
   }
   return 0 unless $config->{allow_non_default} && $config->{"access_$type"};

   return 1 if $check =~ /^$config->{"access_$type"}$/i;

   0;
}

sub access_command {
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
   net_send($fh, $data . "\r\n");
}

sub irc_send_message {
   my($target, $text) = @_;
   $event->handle('message ' .
		($irc->is_channel($target) ? 'public' : 'private') . ' own', 
		{ target => $target }, $irc->{nick}, $irc->{myhost}, $text);
   $irc->msg($target,$text);
}


sub irc_event {
   my($event, $name, $info, @params) = @_;
   $info->{type} = $name;

   if($name =~ /^raw/) {
	  my $params = $params[0];
	  $info->{activity} = 1;
	  $info->{target} = defined $params->{params}->[2] ? $params->{params}->[2] : 'Status';
	  @params = (join(' ', defined $params->{params}->[2] ? @{$params->{params}}[2 .. @{$params->{params}} - 1] : ''),
		defined $params->{text} ? $params->{text} : '');
   }

   if(exists $format->{$name}) {
	  format_out($name, $info, @params);
   }else{
      format_out('default', $info, @params);
   }
}

sub irc_close {
   exit unless ref $unixfh;
   close($unixfh);
   unlink($config->{socket_prefix}.$cgi->{R});
   exit unless ref $ircfh;
   syswrite($ircfh, "QUIT :CGI:IRC $VERSION [EOF]\r\n", length "QUIT :CGI:IRC $VERSION [EOF]\r\n");
   format_out('irc close', { target => '-all', activity => 1 });
   sleep 1;
   close($ircfh);
   exit;
}

sub irc_connected {
   my $key;
   $key = $1 if $cgi->{chan} =~ s/ (.+)$//;
   unless(access_configcheck('channel', $cgi->{chan})) {
	  message('access channel denied', $cgi->{chan});
	  $cgi->{chan} = (split /,/, $config->{default_channel})[0];
   }
   $irc->join($cgi->{chan} . (defined $key ? ' ' . $key : ''));
}

#### prints a very simple header
sub header {
   print "HTTP/1.0 200 OK\r\nContent-type: text/html\r\nPragma: no-cache\r\nCache-control: must-revalidate, no-cache\r\nExpires: -1\r\n\r\n";
}


#### Error Reporting
sub error {
   my($message) = @_;
   print "HTTP/1.0 200 OK\r\nContent-type: text/html\r\n\r\n" unless $config;
   if(defined $interface && ref $interface) {
	  $interface->error($message);
   }else{
      print "An error occured: $message\n";
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

   header();

   $cgi = parse_query($ENV{QUERY_STRING});

   error('No CGI Input') unless keys %$cgi;
   $cgi->{serv} ||= (split /,/, $config->{default_server})[0];
   $cgi->{chan} ||= (split /,/, $config->{default_channel})[0];
   $cgi->{port} ||= $config->{default_port};
   $cgi->{nick} ||= $config->{default_nick};
   $cgi->{name} ||= $config->{default_name};

   $cgi->{nick} =~ s/\?/int rand 10/eg;

   $interface = load_interface();
   $format = load_format($cgi->{format});

   message('access denied'),exit unless access_ipcheck($ENV{REMOTE_ADDR});

   unless(access_configcheck('server', $cgi->{serv})) {
	  message('access server denied', $cgi->{serv});
	  $cgi->{serv} = (split /,/, $config->{default_server})[0];
   }

   if($config->{encoded_ip}) {
	  $cgi->{name} = '[' . encode_ip($ENV{REMOTE_ADDR}) . '] ' . $cgi->{name};
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
		 password => defined $cgi->{pass} ? $cgi->{pass} : (defined $config->{server_password} ? $config->{server_password} : ''),
		 realname => $cgi->{name},
		 user => exists $config->{encoded_ip} && $config->{encoded_ip} > 1 ? encode_ip($ENV{REMOTE_ADDR}) : (exists $config->{default_user} ? $config->{default_user} : 'cgiirc'),
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

