# $Id: UniqueHash.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
#!/usr/bin/perl
# from pircd, edited by david leadbeater..
# 
# IRCUniqueHash.pm
# Created: Wed Apr 21 09:44:03 1999 by jay.kominek@colorado.edu
# Revised: Wed Apr 21 09:59:55 1999 by jay.kominek@colorado.edu
# Copyright 1999 Jay F. Kominek (jay.kominek@colorado.edu)
#
# Consult the file 'LICENSE' for the complete terms under which you
# may use self file.
#
#####################################################################
# A hash class which enforces IRC-style unique name spaces
#####################################################################

package IRC::UniqueHash;
use strict;
my(@tmp);

sub TIEHASH {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = { };

  bless $self, $class;
  return $self;
}

sub FETCH {
  my($self,$key) = @_;

  #print STDERR "FETCH: '$key' => '".$self->{data}->{irclc($key)}->{value}."'\n";
  return $self->{data}->{irclc($key)}->{value};
}

sub STORE {
  my($self,$key,$value) = @_;
  
  my $name = irclc($key);
  #print STDERR "STORE: '$key' ($name) => '$value'\n";
  $self->{data}->{$name}->{name} = $key;
  $self->{data}->{$name}->{value} = $value;
}

sub DELETE {
  my($self,$key) = @_;

  #print "DELETE: $key\n";
  delete($self->{data}->{irclc($key)});
}

sub CLEAR {
  my $self = shift;

  #print "CLEAR";
  %$self = ( );
}

sub EXISTS {
  my($self,$key) = @_;

  #print "EXISTS: $key\n";
  return exists $self->{data}->{irclc($key)};
}

sub FIRSTKEY {
  my $self = shift;

  @{$self->{_tmp}} = keys %{$self->{data}};
  #print STDERR "FIRSTKEY @{$self->{_tmp}}->[0]\n";
  
  return $self->{data}->{shift @{$self->{_tmp}}}->{name};
}

sub NEXTKEY {
  my ($self,$lastkey) = @_;

  return undef unless @{$self->{_tmp}};
  #print "NEXTKEY: @{$self->{_tmp}}->[0]\n";
  return $self->{data}->{shift @{$self->{_tmp}}}->{name};

#  return $self->{each %$self}->{name}
}

sub irclc {
  return $_[0]
}

1;
