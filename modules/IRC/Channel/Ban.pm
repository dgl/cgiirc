# $Id: Ban.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
package IRC::Channel::Ban;
use strict;

sub new {
   my $class = shift;
   my $self = bless { }, $class;
   %$self = @_;
   $self->{'time'} = time unless $self->{'time'};
   return $self;
}

# Maybe i'll add some functions here, one day...

1;
