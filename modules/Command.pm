package Command;
my($package, $event, $irc, $command, $target, $params);

my %commands = (
  msg => sub {
     my($target, $text) = split(' ', $params, 2);
     $event->handle('message ' .
	    ($irc->is_channel($target) ? 'public' : 'private') . ' own',
		{ target => $target, create => 1 }, $irc->{nick}, $irc->{myhost}, $text);
	 $irc->msg($target,$text);
  },
  m => 'msg',
  privmsg => 'msg',
  whois => sub {
     $irc->out("WHOIS $params");
  },
  'join' => sub {
     my @channels = (split(/,/, (split(' ', $params, 2))[0]));
	 for(@channels) {
	    main::access_configcheck('channel', $_);
		message('access channel denied', $_);
		return;
	 }
     $irc->out("JOIN $params");
  },
  j => 'join',
  part => sub {
     if(!$params) {
	    $irc->part($target);
	 }else{
	    my($target, $text) = split(' ', $params, 2);
		$irc->part($target, $text);
	 }
  },
  notice => sub {
     my($target, $text) = split(' ', $params, 2);
     $event->handle('notice ' .
	    ($irc->is_channel($target) ? 'public' : 'private') . ' own',
		{ target => $target }, $irc->{nick}, $irc->{myhost}, $text);
	 $irc->notice($target,$text);
  },
  ctcp => sub {
     my($target, $text) = split(' ', $params, 2);
	 $event->handle('ctcp ' .
	   ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	   { target => $target }, $irc->{nick}, $irc->{myhost}, $text);
	 $irc->ctcp($target,$text);
  },
  ping => sub {
     $target = $params if $params;
	 $event->handle('ctcp ' .
	  ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	  { target => $target }, $irc->{nick}, $irc->{myhost}, $text);
	 $irc->ctcp($target, 'PING ' . time);
  },
  me => sub {
     $event->handle('action ' .
	  ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	  { target => $target }, $irc->{nick}, $irc->{myhost}, $text);
     $irc->ctcp($target, 'ACTION ' . $text);
  },
  action => sub {
     my($target, $text) = split(' ', $params, 2);
	 $event->handle('action ' .
	  ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	  { target => $target }, $irc->{nick}, $irc->{myhost}, $text);
	 $irc->ctcp($target, 'ACTION ' . $text);
  },
  quote => sub {
     $irc->out($params);
  },
);

sub expand {
   ($package, $command) = @_;
   $command = lc $command;
   if(exists $commands{$command}) {
      $command = _find_command($command);
	  return $command;
   }
   return $command;
}

sub run {
   ($package, $event, $irc, $command, $target, $params) = @_;

   if(exists $commands{$command}) {
      my $error = $commands{$command}->();
	  return $error ? $error : 100;
   }else{
      $irc->out(uc $command . ' ' . ($params =~ / / ? ':' : '') . $params);
      return 100;
   }

   return 1;
}

sub message {
   main::message(@_);
}

sub _find_command {
   my($fcommand) = @_;
   return '' unless exists $commands{$fcommand};
   return $fcommand if ref $commands{$fcommand};
   $fcommand = $commands{$fcommand};
   return _find_command($fcommand);
}

1;
