# $Id: Timer.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
=head1 NAME

 Timer.pm

=head1 EXAMPLES

 use Timer;
 $timer = Timer->new;
 
 $timer->addonce(code => \&somesub, data => 'moo', interval => 10);
 sub somesub { print shift }
 
 $timer->add(code => sub { 
     my($timer,$data) = @_;
	 print "Called $timer->{id} with $data\n";
  }, data => 'oink', interval => 1, count => 10);
  
  # Obviously fit $timer->run into how your program needs to use it.
  sleep 1;
  sleep 1 while $timer->run;

=head1 METHODS

=head2 add
 
 add( code => \&codref, # \&code, sub { print blah..} etc..
     data => 'data',   # This data is passed back to the coderef when run
	 interval => num,  # Time between being run..
	 count => [num | undef ], # number of times to run, undef == forever
   );

=head2 addonce
 
 Wrapper to add, option count is already set to 1

=head2 addforever
 
 Wrapper to add, option count is set to undef

=head2 delete

delete($id);

=head2 get

 returns anon hash specified by $id
 
=head2 run
 
 checks for timers that need running, returns number actually run.

=head2 call
 
 used internally by run to call an timer when it needs running

=head2 exists

 returns true if the timer exists

=cut

package Timer;
use strict;

sub new {
   my $class = shift;
   # notice it's an array, not a hash
   return bless [], $class;
}

sub add {
   my($self,%timer) = @_;
   my $id = $self->_newid;
   $$self[$id] = 
      {
	     code => $timer{code},
		 data => $timer{data},
		 interval => $timer{interval},
		 nextexec => $timer{interval} + time,
		 count => $timer{count} || undef,
		 'package' => (caller)[0],
		 id => $id
	  };
   return $id;
}

sub remove_package {
   my($self, $package) = @_;
   for my $id(0 .. $#$self) {
      next unless ref($$self[$id]) eq 'HASH';
      if($$self[$id]->{package} eq $package) {
	     splice(@$self, $id, 1);
	  }
   }
}

# Finds the next free id (element) in the array
sub _newid {
   my $self = shift;
  for my $id(0 .. $#$self) {
     return $id unless ref($$self[$id]) eq 'HASH';
  }
   return scalar @$self;
}

sub addonce {
   my($self,%timer) = @_;
   $self->add(%timer,count => 1);
}

sub addforever {
   my($self,%timer) = @_;
   $self->add(%timer,count => undef);
}

sub delete {
   my($self,$id) = @_;
   return 0 unless $self->exists($id);
   $$self[$id] = undef;
}

sub get {
   my($self,$id) = @_;
   return $$self[$id];
}

sub run {
   my $self = shift;
   my $time = time;
   my $num = 0;
   for my $id(0 .. $#$self) {
      next unless ref($$self[$id]) eq 'HASH';
      if($time >= $$self[$id]->{nextexec}) {
	     $self->call($id);
		 $num++;
	  }
   }
   return $num;
}

sub call {
   my($self,$id) = @_;
   my $timer = $self->get($id);
   
   $timer->{count}-- if defined $timer->{count};
   $timer->{nextexec} = $timer->{interval} + time;

# TODO: Make $timer into an object so things like $timer->delete work within
# the timer.
   $timer->{code}->($timer,$timer->{data});
   
   if(defined $timer->{count} && $timer->{count} <= 0) {
      $self->delete($id);
	  return 0;
   }
   1;
}

sub exists {
   my($self,$id) = @_;
   return 1 if ref($$self[$id]) eq 'HASH';
   0;
}

1;
