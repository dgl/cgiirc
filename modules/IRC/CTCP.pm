# $Id: CTCP.pm,v 1.1 2002/03/05 16:34:19 dgl Exp $
package IRC::CTCP;
use strict;

sub new {
   my($class,$event) = @_;
   for(['ctcp msg',\&msg] , ['ctcp reply', \&reply]) {
      next if $event->exists($_->[0]);
	  $event->add($_->[0], code => $_->[1]);
   }
   return bless {}, shift;
}

sub msg {
   my($event,$ircevent,$type) = @_;
   $type = 'ctcpmsg' unless defined $type;
   
   if($ircevent->{message} =~ /^\001([^ ]+)(?: (.*?))?\001?$/) {
      my($command,$params) = ($1,$2);

      $ircevent->{server}->{event}->handle('ctcp '. ($type eq 'ctcpmsg' ? 'msg' : 'reply') . ' '. lc $command,
         IRC::Event->new($ircevent->{server},
	       type => $type,
		   nick => $ircevent->{nick},
		   host => $ircevent->{host},
		   target => $ircevent->{target},
		   params => $params,
	     )
      );

   }else{
      return undef;
   }
}

sub reply {
   msg(@_[0..1],'ctcpreply');
}

1;
