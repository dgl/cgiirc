# $Id: Event.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
package Event;
use strict;
my($currentevent,$currenteventid,$stop);

sub new {
   my $self = bless { }, shift;
   %$self = @_;
   return $self;
}

sub add {
   my($self,$event,%option) = @_;
   return unless $event;
   $self->{$event} ||= [ ];

   push(@{$self->{$event}}, bless ( {
       priority => $option{priority} || 5,
	   code => $option{code},
	   data => $option{data},
	   'package' => (caller)[0],
	   _self => $self,
	 } ) );
   $self->sortpri($event);
}

sub delete {
   my($self,$event,%option) = @_;
   if(defined $currentevent) {
      $self = $self->{_self};
      splice( @{ $self->{$currentevent} }, $currenteventid, 1);
      $self->sortpri($currentevent);
   } else {
      my $count = 0;
      for my $item(@{ $self->{$event} } ) {
         if((exists $option{code} && $item->{code} eq $option{code}) || (exists $option{data} && $item->{data} eq $option{data})) {
	        splice( @{ $self->{$event} }, $count, 1);
	     }
	     $count++;
      }
      $self->sortpri($event);
   }
}

sub remove_package {
   my($self, $package) = @_;
   for my $event (keys %$self) {
      next unless ref $self->{$event};
      my $count = 0;
      for my $item(@{ $self->{$event} } ) {
	     if($item->{package} eq $package) {
		    splice( @{ $self->{$event} }, $count, 1);
		 }
		 $count++;
      }
   }   
}

# Make sure the array for the event is sorted on priority
sub sortpri {
   my($self,$event) = @_;
   return unless $event;

   if($#{$self->{$event}} == -1) {
      delete($self->{$event});
   } else {
      @{$self->{$event}} = (sort {$a->{priority} <=> $b->{priority}} @{$self->{$event}});
   }
}

sub handle {
   my($self,$event,@param) = @_;
   print("Event: $event, @param\n") if $self->{_DEBUG};
   $currentevent = $event;
   $currenteventid = 0;
   for my $item(@{$self->{$event}} ) {
      my($tmpevent,$tmpid) = ($currentevent,$currenteventid);
      $item->{code}->($item,@param);
	  ($currentevent,$currenteventid) = ($tmpevent,$tmpid);
	  $currenteventid++;
	  if($stop) {
	     $stop = 0;
		 last;
	  }
   }
   if(!scalar @{$self->{$event}} && $event ne "unhandled") {
      $self->handle('unhandled', $event, @param);
   }
   $currenteventid = $currentevent = undef;
}

sub stop {
   my($self) = @_;
   $stop = 1 if defined $currentevent;
}

sub getevent {
   my($self) = @_;
   return defined $currentevent ? $currentevent : undef;
}

sub exists {
   my($self,$event) = @_;
   return 1 if exists $self->{$event};
   0;
}

1;
