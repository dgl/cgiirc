# $Id: Util.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
package IRC::Util;
use Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(is_vaild_channel is_vaild_nickname is_vaild_server make_lowercase check_mode match_mask fullhost2nick fullhost2host add_mode del_mode);

use strict;

sub is_vaild_channel {
   return 0 if length $_[0] > 64;
   return 0 if $_[0] =~ /[ ,]/;
   return 1 if $_[0] =~ /^[#&]/;
   return 0;
}

sub is_vaild_nickname {
   return 0 if length $_[0] > 32 or length $_[0] < 1;
   return 0 if $_[0] =~ /[^A-Za-z0-9-_\[\]\\\`\^\{\}]/;
   return 0 if $_[0] =~ /^[^A-Za-z_\\\[\]\`\^\{\}]/;
   return 1;
}

sub is_vaild_server {
   return 0 if $_[0] !~ /\./;
   return 0 if $_[0] =~ /[^A-Za-z0-9\.-_]/;
   return 1;
}

sub make_lowercase{
   my $lc = shift;
   $lc =~ tr/A-Z\[\]\\/a-z\{\}\|/;
   return $lc;
}

sub check_mode {
   my($mode,$bit) = @_;
   return 1 if $mode =~ /\S*\Q$bit\E/;
}

# should really split all the parts up...
sub match_mask {
   my($check,$mask) = @_;
   $mask = quotemeta $mask;
   $mask =~ s/\\\?/./g;
   $mask =~ s/\\\*/.*?/g;
   return 1 if $check =~ /$mask/;
   0;
}

sub fullhost2nick {
   my $host = shift;
   $host =~ s/!.*$//;
   return $host;
}

sub fullhost2host {
   my $host = shift;
   $host =~ s/^.*?!//;
   return $host;
}

sub add_mode{
   my($mode,$bit) = @_;
   return $mode if $mode =~ /^\S*$bit/;
   $mode =~ s/^(\S*)/$1$bit/;
   return $mode;
}

sub del_mode{
   my($mode,$bit) = @_;
   return $mode if $mode !~ /^\S*$bit/;
   $mode =~ s/^(\S*)$bit/$1/;
   return $mode;
}

1;
