# $Id: IRC.pm,v 1.2 2002/03/06 20:39:59 dgl Exp $
package IRC;
use strict;
use IRC::UniqueHash;
use IRC::Util;
use IRC::Channel;
use IRC::RawCommands;
use IRC::CTCP;

sub new {
   my $class = shift;
   my $self = bless {}, $class;
   %$self = @_;
   return undef unless $self->{event} and $self->{timer};

   $self->{_channels} = { };
   tie %{$self->{_channels}}, 'IRC::UniqueHash';
   
   $self->{_tmp} = { };
   $self->{fh} ||= 1;
   $self->{mode} ||= '+';

   $self->{_rawcmd} = IRC::RawCommands->new($self,$self->{event});
   $self->{_ctcp} = IRC::CTCP->new($self->{event});

   if($self->{nick}) {
      $self->connect(@_);
   }

   return $self;
}

sub in {
   my($self,$line) = @_;
   $line =~ s/(\015\012|\012|\015)$//;

   if($line =~ /^(PING|NOTICE|ERROR) /i){
      if($line =~ /^PING (.*)$/i) {
	     $self->out("PONG $1");
	  }elsif($line =~ /^NOTICE ([^ ]+) :?(.*)$/i) {
	     $self->{event}->handle('notice server', {target => $1},
		 , $self->{server}, $self->{server}, $2);
	  }elsif($line =~ /^ERROR :([^:]+):(.*)$/i) {
	     $self->{event}->handle('disconnect', {target => 'Status'}, $1, $2);
	  }
   }elsif(
     my($host,$params,$text) = $line =~ /^:([^ ]+) +((?:[^ ]+(?: +)?)+?)(?:(?<= ):(.*))?$/) {
	  $params =~ s/^ +//;
	  my @params = split(/ /,$params);
	  $self->{event}->handle('raw ' . lc $params[0], $self, {
	      host => fullhost2host($host),
		  nick => fullhost2nick($host),
		  params => [ @params ],
		  text => $text
	  } );
   }else{
      warn "Parse error in: '$line'";
   }
}

sub out {
   my($self,$line) = @_;
   $self->{event}->handle('irc out',$self->{fh}, $line);
}

sub find_nick_channels {
   my($self,$nick) = @_;
   my @tmp;
   for my $channel(keys %{$self->{_channels}}) {
      push @tmp, $channel if $self->{_channels}->{$channel}->nick($nick);
   }
   return @tmp;
}

sub connect {
   my($self,%connect) = @_;
   $self->{alternick} ||= $connect{alternick} || $connect{nick} . '_';
   $self->out("PASS $self->{password}") if $self->{password};
   $self->out('NICK '.($connect{nick} || $ENV{IRC_NICK} || $ENV{USER}));
   $self->out('USER '.($connect{user} || $ENV{USER}) . ' localhost ' .
   ($connect{server} || 'irc') . ' :' . ($connect{realname} || 'unknown'));
}

sub channel {
   my($self,$channel) = @_;
   return $self->{_channels}->{$channel};
}

sub channels {
   my $self = shift;
   return values %{$self->{_channels}};
}

sub is_channel {
   my($self,$channel) = @_;
   return is_vaild_channel($channel);
}

sub sync_channel {
   my($self,$channel) = @_;
   $self->channel($channel)->{mode_sync} = 1;
   $self->out("MODE $channel");
   $self->channel($channel)->{modeb_sync} = 1;
   $self->out("MODE $channel b");
   $self->channel($channel)->{who_sync} = 1;
   $self->out("WHO $channel");
}

sub join {
   my($self, $channel, $key) = @_;
   $self->out("JOIN " . (ref $channel ? $channel->{name} : $channel) . ($key ? ' ' . $key : ''));
}

sub part {
   my($self,$channel,$reason) = @_;
   $self->out("PART " . ref $channel ? $channel->{name} : $channel . ($reason ? " :$reason" : ''));
}

sub nick {
   my($self,$nick) = @_;
   $self->out("NICK $nick");
}

sub quit {
   my($self,$reason, $priority) = @_;
   $self->out("QUIT :$reason");
}

sub mode {
   my($self, $channel, $mode) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("MODE $channel $mode");
}

sub topic {
   my($self, $channel, $message) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("TOPIC $channel :$message");
}

sub invite {
   my($self, $channel, $nick) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("INVITE $channel $nick");
}

sub kick {
   my($self, $channel, $nick, $message) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("KICK $channel $nick :$message");
}

sub notice {
   my($self, $channel, $message) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("NOTICE $channel :$message");
}

sub msg {
   my($self, $channel, $message) = @_;
   $self->privmsg(@_[1..3]);
}

sub privmsg {
   my($self, $channel, $message) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("PRIVMSG $channel :$message");
}

sub ctcp {
   my($self, $channel, $text) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("PRIVMSG $channel :\001$text\001");
}

sub ctcpreply {
   my($self, $channel, $text) = @_;
   $channel = $channel->{name} if ref $channel;
   $self->out("NOTICE $channel :\001$text\001");
}

1;
