#!/usr/bin/perl -T
# Basically you need to add a line like this to /etc/inetd.conf and 
# kill -HUP inetd
# ident	stream	tcp	nowait	nobody	/usr/local/sbin/identd.pl
# see the advanced section of the docs for more details about this.
use strict;
use Socket;

# Prefix/tmp directory that CGI:IRC uses
my $cgiircprefix="/tmp/cgiirc-";

# How to deal with unknown requests:
# nouser reply with NO-USER
# reply:text reply with USERID 'text'
# linuxproc use /proc/net/tcp on linux to do 'real' identd relies 
# forward:port forward to a real identd
my $reply = "nouser";

# Taken from midentd
my $in = '';
ret(0,0, "ERROR : NO-USER") unless sysread STDIN, $in, 128;
my($local, $remote) = $in =~ /^\s*(\d+)\s*,\s*(\d+)/;

ret(0,0, "ERROR : INVALID-PORT") unless defined $local && defined $remote;

$remote = 0 if $remote !~ /^([ \d])+$/;
$local = 0 if $local !~ /^([ \d])+$/;

if($remote<1 || $remote>65535 || $local<1 || $local>65535) {
   ret($local, $remote, "ERROR : INVALID-PORT")
}

my $randomvalue = find_socket($local, $remote);

if(defined $randomvalue) {
   my $user = encode_ip($randomvalue);
	ret($local, $remote, "USERID : UNIX : $user");
}else{
   if($reply eq 'nouser') {
      ret($local, $remote, "ERROR : NO-USER");
   }elsif($reply =~ /reply:\s*(.*)/) {
      ret($local, $remote, "USERID : UNIX : $1");
   }elsif($reply eq 'linuxproc') {
      ret($local, $remote, linuxproc($local, $remote));
   }elsif($reply =~ /forward:\s*(.*)/) {
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
   (my $dir, my $prefix) = $cgiircprefix =~ /^(.*\/)([^\/]+)$/;
   opendir(TMPDIR, $dir) or return undef;
   for(readdir TMPDIR) {
      next unless /^\Q$prefix\E/;
      next unless -o $dir . $_ && -d $dir . $_;
      
      local *TMP;
      open(TMP, "<$dir$_/server") or next;
      chomp(my $tmp = <TMP>);
      next unless $tmp =~ /:$r$/;
      
      chomp($tmp = <TMP>);
      next unless $tmp =~ /:$l$/;
      close TMP;

      $_ = $dir . $_;
      s/^\Q$cgiircprefix\E//;
      return $_;
   }
   closedir TMPDIR;
   return undef;
}

sub encode_ip {
   my($rand) = @_;
   open(TMP, "<$cgiircprefix$rand/ip") or return 0;
   chomp(my $ip = <TMP>);
   close TMP;
   return join('',map(sprintf("%0.2x", $_), split(/\./, $ip)));
}

sub linuxproc {
   my($l, $r) = @_;
   open(PNT,"</proc/net/tcp") or return "ERROR : NO-USER";
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
   if($_=(getpwuid($uid))[0]) {
      return $_;
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

