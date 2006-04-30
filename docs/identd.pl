#!/usr/bin/perl -T
use strict;
use Socket;

# Basically you need to add a line like this to /etc/inetd.conf and
# run killall -HUP inetd.
# ident stream  tcp nowait  nobody  /usr/local/sbin/identd.pl /tmp/cgiirc-=nobody

# The parameter on the end is the location of the socket files and
# the user which CGI:IRC is running as, for example
# /tmp/cgiirc-=www-data means that CGI:IRC has the socket_prefix
# set to /tmp/cgiirc- and is running as user www-data. Multiple
# directories can be specified.

# How to deal with unknown requests:
# nouser reply with NO-USER
# reply:text reply with USERID 'text'
# linuxproc use /proc/net/tcp on linux to do 'real' identd replies
# forward:port forward to a real identd
my $reply = "nouser";

# Use custom ident (currently HTTP USER set by CGI:IRC).
my $customident = 0;

# Default:
my %cgiircprefixes = ( '/tmp/cgiirc-' => $<);

%cgiircprefixes = () if @ARGV;
for(@ARGV) {
  my($p, $u) = split /=/;
  $u = getpwnam($u) || $<;
  $cgiircprefixes{$p} = $u;
}

# Taken from midentd
my $in = '';
ret(0, 0, "ERROR : NO-USER") unless sysread STDIN, $in, 128;
my($local, $remote) = $in =~ /^\s*(\d+)\s*,\s*(\d+)/;

ret(0, 0, "ERROR : INVALID-PORT") unless defined $local && defined $remote;

$remote = 0 if $remote !~ /^([ \d])+$/;
$local = 0 if $local !~ /^([ \d])+$/;

if($remote<1 || $remote>65535 || $local<1 || $local>65535) {
   ret($local, $remote, "ERROR : INVALID-PORT")
}

my $socket = find_socket($local, $remote);

if(defined $socket) {
   my $user = encode_ip($socket);
   if($customident && -f "$socket/ident") {
     open(TMP, "<$socket/ident") or
       ret($local, $remote, "USERID : UNIX : $user");
     $user = <TMP>;
     chomp($user);
     $user ||= encode_ip($socket);
   }
   ret($local, $remote, "USERID : UNIX : $user");
} else {
   if($reply eq 'nouser') {
      ret($local, $remote, "ERROR : NO-USER");
   } elsif($reply =~ /reply:\s*(.*)/) {
      ret($local, $remote, "USERID : UNIX : $1");
   } elsif($reply eq 'linuxproc') {
      ret($local, $remote, linuxproc($local, $remote));
   } elsif($reply =~ /forward:\s*(.*)/) {
      print forward($1, $local, $remote);
      exit;
   }

   ret($local, $remote, "ERROR : INVALID-PORT");
}

sub ret{
   my($l, $r, $t) = @_;
   print "$l , $r : $t\r\n";
   exit;
}

sub find_socket {
   my($l, $r) = @_;
   foreach my $cgiircprefix (keys %cgiircprefixes) {
     (my $dir, my $prefix) = $cgiircprefix =~ /^(.*\/)([^\/]+)$/;
     opendir(TMPDIR, $dir) or return undef;
     for(readdir TMPDIR) {
        next unless /^\Q$prefix\E/;
        next unless -d $dir . $_ && -x $dir . $_;

        next unless $cgiircprefixes{$cgiircprefix} == (stat($dir . $_))[4];

        local *TMP;
        open(TMP, "<$dir$_/server") or next;
        chomp(my $tmp = <TMP>);
        next unless $tmp =~ /:$r$/;

        chomp($tmp = <TMP>);
        next unless $tmp =~ /:$l$/;
        close TMP;

        closedir TMPDIR;
        return $dir . $_;
     }
     closedir TMPDIR;
   }
   return undef;
}

sub encode_ip {
   my($socket) = @_;
   open(TMP, "<$socket/ip") or return 0;
   chomp(my $ip = <TMP>);
   close TMP;
   return join('', map(sprintf("%0.2x", $_), split(/\./, $ip)));
}

sub linuxproc {
   my($l, $r) = @_;
   open(PNT, "</proc/net/tcp") or return "ERROR : NO-USER";
   $_=<PNT>;
   while(<PNT>) {
      s/^\s+//;
      s/\s+/ /g;
      my($sl,$local,$remote,$st,$queue,$tr,$retrnsmt,$uid,$timeout,$inode) = split(/\s/);
      next unless decode_port($local) == $l && decode_port($remote) == $r;
      return "USERID : UNIX : " . getusername($uid);
   }
   close(PNT);
   return "ERROR : NO-USER";

}

sub decode_port{
   return hex((split(/:/,shift,2))[1]);
}

sub getusername{
   my $uid = shift;
   if(my $u=(getpwuid($uid))[0]) {
      return $u;
   } else {
      return $uid;
   }
}

sub forward {
   my($where, $l, $r) = @_;
   eval("use IO::Socket;");
   my $forward = IO::Socket::INET->new($where =~ /:/ ? $where : '127.0.0.1:' . $where);
   return "$l , $r : ERROR : NO-USER\r\n" unless ref $forward;
   print $forward "$l , $r\r\n";
   return scalar <$forward>;
}
