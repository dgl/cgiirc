package Command;
use strict;
my($package, $event, $irc, $command, $target, $params, $config, $interface);

my %commands = (
  noop => sub {
     0;
  },
  msg => sub {
     my($target, $text) = split(' ', $params, 2);
	 return 2 unless(defined $text && defined $target);
	 main::irc_send_message($target, $text);
  },
  m => 'msg',
  privmsg => 'msg',
  say => sub {
     return 2 unless defined $params;
     main::irc_send_message($target, $params);
  },
  wi => 'whois',
  whois => sub {
     $params = $irc->{nick} unless $params;
     $irc->out("WHOIS $params");
  },
  j => 'join',
  'join' => sub {
    my($channels, $keys) = split(' ', $params, 2);
    my @channels = split /,/, $channels;
	 for(@channels) {
       $_ = "#$_" unless $irc->is_channel($_);
	    next if main::access_configcheck('channel', $_);
		 message('access channel denied', $_);
		 return;
	 }
    $irc->join(join(',', @channels) . (defined $keys ? " $keys" : ''));
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
	 return 1 unless defined $params;
     $irc->nick($params);
  },
  quit => sub {
     $irc->quit($params ? $params : (defined $config->{quit_message} ? 
	     $config->{quit_message} : "CGI:IRC $::VERSION"));
  },
  names => sub {
     $irc->out("NAMES " . ($params ? $params : $target));
  },
  mode => sub {
	return 2 unless defined $params;
    my($atarget, $text) = split(' ', $params, 2);
	if($atarget =~ /^[+-]/) {
	   $irc->mode($target, $params);
	}else{
	   $irc->mode($atarget, $text);
	}
  },
  umode => sub {
	 return 2 unless defined $params;
     $irc->mode($irc->{nick}, $params);
  },
  usermode => 'umode',
  op => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '+' . ('o' x scalar @{[split ' ', $params]}) ." $params");
  },
  halfop => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '+' . ('h' x scalar @{[split ' ', $params]}) ." $params");
  },
  voice => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '+' . ('v' x scalar @{[split ' ', $params]}) ." $params");
  },
  deop => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '-' . ('o' x scalar @{[split ' ', $params]}) ." $params");
  },
  dehalfop => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '+' . ('h' x scalar @{[split ' ', $params]}) ." $params");
  },
  devoice => sub {
     return 2 unless defined $params;
	 $irc->mode($target, '-' . ('v' x scalar @{[split ' ', $params]}) ." $params");
  },
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
	    $irc->invite($params, $target);
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
  ban => sub {
     return 2 unless defined $params;
     my $chan = $irc->channel($target);
     if($params =~ /\@/) {
        $irc->mode($target, "+b $params");
     }elsif(ref $chan && ref $chan->nick($params)) {
        my $host = $chan->nick($params)->{host};
        if($host =~ /\d$/) {
           $host =~ s/^\W([^\@]+)\@(.*?)\.\d+$/*!*$1\@$2.*/;
        }else{
           $host =~ s/^\W([^\@]+)\@[^\.]+\.(.*)$/*!*$1\@*.$2/;
        }
        $irc->mode($target, "+b $host");
     }else{
        return 1;
     }
  },
  ignore => sub {
      if($params) {
			$params =~ s/[!@].*//;
         $irc->ignore($params);
         message('ignored', $params);
      }else{
         for($irc->ignores) {
            message('ignore list', $_);
         }
      }
      return 0;
  },
  unignore => sub {
     return 2 unless defined $params;
     $irc->unignore($params);
     message('unignored', $params);
     return 0;
  },
  notice => sub {
     my($target, $text) = split(' ', $params, 2);
     my $display = $target;
     $display =~ s/^[+@]+//;
     $event->handle('notice ' .
	    ($irc->is_channel($display) ? 'public' : 'private') . ' own',
		 { target => $display }, $irc->{nick}, $irc->{myhost}, $text);

	  $irc->notice($target,$text);
  },
  ctcp => sub {
     my($target, $text) = split(' ', $params, 2);
	  $event->handle('ctcp own msg',
	    { target => $target }, $irc->{nick}, $irc->{myhost}, $text);
	  $irc->ctcp($target,$text);
  },
  ctcpreply => sub {
     my($target, $type, $text) = split(' ', $params, 3);
     $irc->ctcpreply($target, $type, $text);
  },
  ping => sub {
     $target = $params if $params;
	  $event->handle('ctcp own msg',
	    { target => $target }, $irc->{nick}, $irc->{myhost}, 'PING');
	  $irc->ctcp($target, 'PING ' . time);
  },
  me => sub {
     $event->handle('action ' .
	    ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	    { target => $target }, $irc->{nick}, $irc->{myhost}, $params);
     $irc->ctcp($target, 'ACTION ' . $params);
  },
  action => sub {
    my($target, $text) = split(' ', $params, 2);
	 $event->handle('action ' .
	   ($irc->is_channel($target) ? 'public' : 'private') . ' own',
	   { target => $target }, $irc->{nick}, $irc->{myhost}, $params);
	 $irc->ctcp($target, 'ACTION ' . $params);
  },
  quote => sub {
     $irc->out($params) if $params;
  },
  version => sub {
     if($params) {
	     $irc->out("VERSION $params");
	  }else{
	     message('default',"CGI:IRC $main::VERSION - David Leadbeater - http://cgiirc.sf.net/");
		  $irc->out('VERSION');
	  }
  },
  winclose => sub {
     my $c = $params ? $params : $target;
     $irc->part($c) if $irc->is_channel($c) && $irc->channel($c);
     $interface->del($c);
	  return 0;
  },
  'close' => 'winclose',
  'unquery' => 'winclose',
  'query' => sub {
     return 2 unless $params;
     my($target, $text) = split(' ', $params, 2);
     $interface->add($target);
     $interface->active($target);
     if(defined $text and $text) {
	 main::irc_send_message($target, $text);
     }
     return 0;
  },
  clear => sub {
     $interface->clear($params ? $params : $target);
	  return 0;
  },
  help => sub {
     $interface->help($config);
     return 0;
  },
  charset => sub {
     if(!$::ENCODE) {
	     message('default', 'Encode module is not loaded, character set conversion not available');
	  }else{
	     if(!$params) {
		     message('default', "Current encoding is: " . $config->{'irc charset'});
		  }else{
		     if(Encode::find_encoding($params)) {
			     message('default', "Encoding changed to $params");
				  $config->{'irc charset'} = $params;
			  }else{
			     message('default', 'Encoding not found');
			  }
		  }
	  }
	  return 0;
  },
);

my %lcs;
@lcs{qw/nickserv memoserv chanserv statserv cs ms ns ss away/} = 1;

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
   ($package, $event, $irc, $command, $target, $params, $config, $interface) = @_;

   if(exists $commands{$command}) {
      my $error = $commands{$command}->();
	  return $error ? $error : 100;
   }elsif(exists $lcs{$command}) {
      $irc->out(uc($command) . ' :' . $params);
      return 100;
   }elsif($command =~ /^:/) {
      ($command,$params) = $params =~ /^([^ ]+) ?(.*)$/;
	  return 1 unless exists $commands{lc $command};
	  my $error = $commands{lc $command}->();
	  return $error ? $error : 100;
   }else{
      $irc->out(uc($command) . ' ' . $params);
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
