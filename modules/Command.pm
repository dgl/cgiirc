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
  wi => 'whois',
  whois => sub {
     $params = $irc->{nick} unless $params;
     $irc->out("WHOIS $params");
  },
  j => 'join',
  'join' => sub {
     my @channels = (split(/,/, (split(' ', $params, 2))[0]));
	 for(@channels) {
	    main::access_configcheck('channel', $_);
		message('access channel denied', $_);
		return;
	 }
     $irc->join($params);
  },
  l => 'part',
  part => sub {
     if(!$params) {
	    $irc->part($target);
	 }else{
	    my($atarget, $text) = split(' ', $params, 2);
		if($irc->is_channel($atarget)) {
		   $irc->part($atarget, $text);
		}else{
		   $irc->part($target, $atarget . ' ' . $text);
		}
	 }
  },
  nick => sub {
     $irc->nick($params);
  },
  quit => sub {
     $irc->quit($params ? $params : "CGI:IRC $main::VERSION");
  },
  mode => sub {
    my($atarget, $text) = split(' ', $params, 2);
	if($atarget =~ /^[+-]/) {
	   $irc->mode($target, $params);
	}else{
	   $irc->mode($atarget, $text);
	}
  },
  umode => sub {
     $irc->mode($irc->{nick}, $params);
  },
  usermode => 'umode',
  t => 'topic',
  topic => sub {
     my($atarget, $text) = split(' ', $params, 2);
     if(!$params) {
	    $irc->topic($target);
	 }elsif($irc->is_channel($atarget)) {
	    $irc->topic($atarget, $text);
	 }else{
	    $irc->topic($target, $params);
	 }
  },
  invite => sub {
     my($atarget, $text) = split(' ', $params, 2);
	 if($text) {
	    $irc->invite($atarget, $text);
	 }else{
	    $irc->invite($target, $params);
	 }
  },
  k => 'kick',
  kick => sub {
     my($atarget, $tnick, $text) = split(' ', $params, 3);
	 if($irc->is_channel($atarget)) {
	    $irc->kick($atarget, $tnick, $text);
	 }else{
	    $irc->kick($target, $atarget, $tnick .(defined $text ? " $text" : ''));
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
  version => sub {
     if($params) {
	    $irc->out("VERSION $params");
	 }else{
	    message('default',"CGI:IRC $main::VERSION by David Leadbeater (dgl\@dgl.cx)");
		$irc->out('VERSION');
	 }
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
      $irc->out(uc($command) . ' ' . ($params =~ / / ? ':' : '') . $params);
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
