# $Id: Nick.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
package IRC::Channel::Nick;
use strict;

sub new {
   my $class = shift;
   my $self = bless { }, $class;
   %$self = @_;
   return $self;
}

# Maybe i'll add some functions here, one day...

1;
