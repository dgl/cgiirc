#!/usr/bin/perl -wT
# You'll need to add this line to /etc/inetd.conf and change the line that is
# already there to begin with ident2 then edit /etc/services and add port 114
# as ident2 (for example), this means the idents can be forwarded.
# ident	stream	tcp	nowait	nobody	/usr/local/irc/identd.pl
use strict;
use Socket;

# Prefix/tmp directory that CGI:IRC uses
my $cgiircprefix="/tmp/cgiirc-";

# How to deal with unknown requests:
# nouser reply with NO-USER
# reply:text reply with USERID 'text'
# linuxproc use /proc/net/tcp on linux to do 'real' identd relies 
my $reply = "nouser";

# Taken from midentd
my $in = '';
ret(0,0, "ERROR : NO-USER") unless sysread STDIN, $in, 128;
my($local, $remote) = split /[\,\r\n{*}]/, $in;

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
   }elsif($reply =~ /reply:(.*)/) {
      ret($local, $remote, "USERID : UNIX : $1");
   }elsif($reply eq 'linuxproc') {
      ret($local, $remote, linuxproc($local, $remote));
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

sub linuxproc { 'TODO' }

