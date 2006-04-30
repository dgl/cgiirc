# $Id: RawCommands.pm,v 1.29 2006/04/30 13:09:43 dgl Exp $
package IRC::RawCommands;
use strict;

use IRC::Util;
# Don't be fooled by the fact it's a package.. the self in the subroutines is
# actually the one from Client.pm!

my %raw = (
   'nick' => sub {
      my($event,$self,$params) = @_;
	  my $newnick = $params->{params}->[1] || $params->{text};
	  if(lc $params->{nick} eq lc $self->{nick}) {
        $self->{nick} = $newnick;
        $self->{event}->handle('user self', $newnick);
     }

	  my @channels = $self->find_nick_channels($params->{nick});
	  for my $channel(@channels) {
		 $self->{_channels}->{$channel}->chgnick($params->{nick},$newnick);
	  }
	  $self->{event}->handle('user change nick', $params->{nick}, $newnick, \@channels);
	  $self->{event}->handle('nick', _info(\@channels, 1),
	     $params->{nick}, $params->{host}, $newnick);
   },
   'quit' => sub {
      my($event,$self,$params) = @_;
	  my @channels = $self->find_nick_channels($params->{nick});
	  for my $channel(@channels) {
		 $self->{_channels}->{$channel}->delnick($params->{nick});
	  }
	  $self->{event}->handle('user del', $params->{nick}, '-all-');
	  $self->{event}->handle('quit', _info(\@channels, 1), $params->{nick}, $params->{host}, $params->{text});
   },
   'join' => sub {
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[1] || $params->{text};
	  if($params->{nick} eq $self->{nick}) { # It's me!
	     $self->{_channels}->{$channel} = IRC::Channel->new( name => $channel );
		 $self->sync_channel($channel);
		 if(!$self->{myhost}) {
		    $self->{myhost} = $params->{host};
		 }
	  }
	  if(!$self->{_channels}->{$channel}) {
		 return;
	  }

	  $self->{_channels}->{$channel}->addnick($params->{nick},
	      host => $params->{host}
	  );
	  $self->{event}->handle('user add', [$params->{nick}], [$channel]);

	  $self->{event}->handle('join', _info($channel, 1, 1), $params->{nick}, $params->{host});
   },
   'part' => sub {
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[1];
     if(!$channel && $params->{text}) { # b0rked servers here we come
        $channel = $params->{text};
        $params->{text} = '';
     }
	  $self->{_channels}->{$channel}->delnick($params->{nick}) if exists $self->{_channels}->{$channel}->{_users}->{$params->{nick}};

	  if($params->{nick} eq $self->{nick}) { # It's me!
	     delete($self->{_channels}->{$channel});
		 #$self->{event}->handle('message part_self',$params);
	  }
	  $self->{event}->handle('user del', $params->{nick}, [$channel]);

	  $self->{event}->handle('part', _info($channel, 1), $params->{nick}, $params->{host}, $params->{text});
   },
   'mode' => sub {
      my($event,$self,$params) = @_;
	  @{$params->{params}} = split(/ /, join(' ',@{$params->{params}},$params->{text} ? $params->{text} : ''));
	  my $to = $params->{params}->[1];
	  my $mode = $params->{params}->[2];

      my $action = substr($mode,0,1) || '+';
	  my $num = 3;
      
	  if($self->is_nickname($to)) {
	     return unless $to eq $self->{nick};
		 for(split //, $mode) {
		    if(/([+-])/) {
			  $action = $1;
			}elsif($action eq '+') {
			   $self->{mode} = add_mode($self->{mode},$_);
			}elsif($action eq '-') {
			   $self->{mode} = del_mode($self->{mode},$_);
			}
		 }
		 $self->{event}->handle('user mode', _info($to, 1),
		     $params->{nick}, $params->{host},
		   (join(' ',@{$params->{params}}[2.. @{$params->{params}} - 1])));
	  }elsif($self->is_channel($to)) {
	     return unless $self->{_channels}->{$to};
		 my $channel = $self->{_channels}->{$to};
		 my %tmpevents;
		 for(split //, $mode) {
		    if(/([+-])/) {
			   $action = $1;
			}elsif($action eq '-' && /[ilkmnpst$self->{modes}->{toggle}]/) {
			   $channel->{mode} = del_mode($channel->{mode}, $_);
			   $channel->{ {k => 'key',l => 'limit'}->{$_} } = undef if /[lk]/;
			   $num++ if $_ eq 'k';
			}elsif($action eq '+' && /[ilkmnpst$self->{modes}->{toggle}]/) {
			   $channel->{mode} = add_mode($channel->{mode}, $_);
			   $channel->{ {k => 'key',l => 'limit'}->{$_} } = $params->{params}->[$num] if /[lk]/;
			   $num++;
			}elsif(/[hov$self->{prefixmode}]/) {
			   my $nick = $params->{params}->[$num];
            next unless ref $channel->nick($nick);
			   $channel->nick($nick)->{
			        ($_ =~ /[hov]/ ? {o => 'op',h => 'halfop', v => 'voice'}->{$_}
                 : $_)
			   } = ($action eq '+' ? 1 : 0);
			   $tmpevents{$_}{$nick} = (defined $tmpevents{$_}{$nick} && $tmpevents{$_}{$nick} eq '+') ? undef : '-' if $action eq '+';
			   $tmpevents{$_}{$nick} = (defined $tmpevents{$_}{$nick} && $tmpevents{$_}{$nick} eq '-') ? undef : '+' if $action eq '-';
			   $num++;
			}elsif(/b/) {
			   $num++;
			}
		 }
		 if(%tmpevents) {
		    for(keys %tmpevents) {
			   for my $who(keys %{$tmpevents{$_}}) {
			      next unless defined $tmpevents{$_}{$who};
				  $self->{event}->handle('user change', $who, $channel->{name}, $tmpevents{$_}{$who} eq '+' ? '-' : '+', ({'h' => 'halfop','o' => 'op', 'v' => 'voice'}->{$_}));
			   }
			}
		 }
	     $self->{event}->handle('mode', _info($to, 1),
		    $params->{nick}, $params->{host}, (join(' ',@{$params->{params}}[2 ..  @{$params->{params}} - 1])));
	  }
   },
   'topic' => sub {
      my($event,$self,$params) = @_;
	  $self->{_channels}->{$params->{params}->[1]}->{topic} = $params->{text};
	  $self->{_channels}->{$params->{params}->[1]}->{topicby} = $params->{nick};
	  $self->{_channels}->{$params->{params}->[1]}->{topictime} = time;
	  $self->{event}->handle('topic', _info($params->{params}->[1], 1),
		 $params->{nick}, $params->{host}, $params->{text} );
   },
   'invite' => sub {
      my($event,$self,$params) = @_;
	  $self->{event}->handle('invite', _info($params->{nick}, 1),
	     $params->{nick}, $params->{host}, $params->{text} || $params->{params}->[1]);
   },
   'kick' => sub {
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[1];
	  my $kick = $params->{params}->[2];

	  $self->{_channels}{$channel}->delnick($kick);
	  $self->{event}->handle('user del', $kick, [$channel]);
	  
	  $self->{event}->handle('kick', _info($channel, 1),
		  $params->{nick}, $params->{host}, $kick, $params->{text});
   },
   'privmsg' => sub {
      my($event,$self,$params) = @_;
     return if exists $self->{ignore}->{$params->{nick}};
	  my $to = $params->{params}->[1];

	  if(substr($params->{text},0,1) eq "\001") {
	     $self->{event}->handle('ctcp msg', $self, $params->{nick}, $params->{host}, $to, $params->{text});
	  }elsif($self->is_channel($to)) {
	     $self->{event}->handle('message public', _info($to, 2),
			 $params->{nick}, $params->{host}, $params->{text});
	  }elsif($to =~ /^[+@%]/) {
	      my $target = $to;
		  $target =~ s/^[+@%]//g;
		  $self->{event}->handle('message special', _info($target, 2),
		     $params->{nick}, $params->{host}, $to, $params->{text});
	  }elsif(is_valid_server($params->{nick})) {
	     $self->{event}->handle('message server', _info($to, 2),
			 $params->{nick}, $params->{host}, $params->{text});
	  }else{
		  #return unless $self->find_nick_channels($params->{nick});
	     $self->{event}->handle('message private', _info($params->{nick}, 3, 1),
			 $params->{nick}, $params->{host}, $params->{text});
	  }
   },
   'notice' => sub {
      my($event,$self,$params) = @_;
     return if exists $self->{ignore}->{$params->{nick}};
	  my $to = $params->{params}->[1];
	  if(substr($params->{text},0,1) eq "\001") {
	     $self->{event}->handle('ctcp reply', $self, $params->{nick}, $params->{host}, $to, $params->{text});
	  }elsif($self->is_channel($to)) {
	     $self->{event}->handle('notice public', _info($to, 1),
			 $params->{nick}, $params->{host}, $params->{text});
	  }elsif($to =~ /^[+@%]/) {
	      my $target = $to;
		  $target =~ s/^[+@%]+//;
		  $self->{event}->handle('notice special', _info($target, 1),
		     $params->{nick}, $params->{host}, $to, $params->{text});
	  }elsif(is_valid_server($params->{nick})) {
	     $self->{event}->handle('notice server', _info('Status', 1),
			 $params->{nick}, $params->{host}, $params->{text});
	  }else{
	     $self->{event}->handle('notice private', _info($params->{nick}, 1),
			 $params->{nick}, $params->{host}, $params->{text});
	  }
   },
   'kill' => sub {
      my($event,$self,$params) = @_;
   },
   'pong' => sub {
      my($event,$self,$params) = @_;
	  $self->{event}->handle('pong', _info($params->{nick}, 1),
	     $params->{nick}, $params->{params}->[1], $params->{text});
   },

# -- numeric replies --

# Client-server connection information (001 -> 099)
   '001' => sub { # RPL_WELCOME
      my($event,$self,$params) = @_;
	  
	  $self->{connected} = 1;
	  $self->{nick} = $params->{params}->[1];
	  $self->{server} = $params->{nick};
	  $self->{connect_time} = time;
	  $self->{event}->handle('server connected',$self, $self->{server},$self->{nick}, $params->{text});
     $self->{event}->handle('user self', $self->{nick});
	  $self->{event}->handle('reply welcome', _info('Status', 1), $params->{text});
   },
   '002' => sub { # RPL_YOURHOST
      my($event,$self,$params) = @_;
      $self->{event}->handle('reply yourhost', _info('Status', 1), $params->{text});
   },
   '003' => sub { # RPL_CREATED
      my($event,$self,$params) = @_;
      $self->{event}->handle('reply created', _info('Status', 1), $params->{text});
   },
   '004' => sub { # RPL_MYINFO
      my($event,$self,$params) = @_;
	  $self->{capab}->{server_version} = $params->{params}->[3];
	  $self->{capab}->{user_modes} = $params->{params}->[4];
	  $self->{capab}->{channel_modes} = $params->{params}->[5];
      $self->{event}->handle('reply myinfo', _info('Status', 1), @{$params->{params}}[3..5]);
   },
   '005' => sub { # RPL_PROTOCTL
      my($event,$self,$params) = @_;
      for(@{$params->{params}}[2.. @{$params->{params}} - 1]) {
	     my($key,$value) = split(/=/, $_, 2);
		 $value ||= 1;
		 $self->{capab}->{lc $key} = $value;
	  }

     if(exists $self->{capab}->{prefix} && $self->{capab}->{prefix} =~ /^\(([^\)]+)\)(.*)$/) {
        $self->{prefixmodes} = $1;
        $self->{prefixchars} = $2;
     }elsif(exists $self->{capab}->{ircx}) {
        $self->{prefixmodes} = "qov";
        $self->{prefixchars} = ".@+";
     }

     if(exists $self->{prefixchars} && $self->{prefixchars}) {
        $self->{event}->handle('user 005', $self->{prefixchars});
     }

     if(exists $self->{capab}->{chanmodes}) {
        my @modes = split /,/, $self->{capab}->{chanmodes};
        @{$self->{modes}}{qw/masks param param_add toggle/} = @modes;
     }else{
        @{$self->{modes}}{qw/masks param param_add toggle/} = '';
     }

      $self->{event}->handle('reply protoctl', _info('Status', 1),
	    join(' ',@{$params->{params}}[2.. @{$params->{params}} - 1], defined $params->{text} ? $params->{text} : ''));
   },
   
# Command Replies (200 -> 399)
   
   301 => sub { # RPL_AWAY
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply away', _info($params->{params}->[2], 1), $params->{text});
   },
   302 => sub { # RPL_USERHOST
      my($event,$self,$params) = @_;
	  my($nick,$oper,$away,$host) = $params->{text} =~ /^([^=*]+)(\*)?\=(.*)$/;
	  $self->{event}->handle('reply userhost', _info($nick, 1), $nick,$oper,$away,$host);
   },
   303 => sub { # RPL_ISON
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply ison', _info('Status', 1), $params->{text});
   },
   305 => sub { # RPL_UNAWAY
      my($event,$self,$params) = @_;
	  $self->{away} = 0;
	  $self->{event}->handle('reply unaway', _info('Status', 1));
   },
   306 => sub { # RPL_NOWAWAY
      my($event,$self,$params) = @_;
	  $self->{away} = 1;
	  $self->{event}->handle('reply nowaway', _info('Status', 1));
   },
   
   # whois replies
   307 => sub { # RPL_USERIP -OR- RPL_WHOISREGNICK
      my($event,$self,$params) = @_;
	  if($params->{params}->[2]) { # RPL_WHOISREGNICK
	     $self->{event}->handle('reply whois regnick', _info($params->{params}->[2], 1), $params->{text});
	  }else{ # RPL_USERIP (same format as userhost, except ip)
	     $self->{event}->handle('reply userip', _info('Status', 1), $params->{text});
	  }
   },
   311 => sub { # RPL_WHOISUSER
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whois user', _info($params->{params}->[2], 1), @{$params->{params}}[3..4], $params->{text});
   },
   312 => sub { # RPL_WHOISSERVER
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whois server', _info($params->{params}->[2], 1), $params->{params}->[3], $params->{text});
   },
   313 => sub { # RPL_WHOISOPERATOR
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whois operator', _info($params->{params}->[2], 1), $params->{text});
   },
   314 => sub { # RPL_WHOWASUSER
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whowas user', _info($params->{params}->[2], 1), $params->{text});
   },
   317 => sub { # RPL_WHOISIDLE
      my($event,$self,$params) = @_;
      my $time = ::format_parse($format->{time}, {}, [gmtime $params->{params}->[3]]);
	  $self->{event}->handle('reply whois idle', _info($params->{params}->[2], 1), $time, scalar gmtime($params->{params}->[4]), $params->{text});
   },
   319 => sub { # RPL_WHOISCHANNELS
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whois channel', _info($params->{params}->[2], 1), $params->{text});
   },

   318 => sub { # RPL_ENDOFWHOIS
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whois end', _info($params->{params}->[2], 1), $params->{text});
   },
   369 => sub { # RPL_ENDOFWHOWAS
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply whowas end', _info($params->{params}->[2], 1), $params->{text});
   },

   # list
   321 => sub { # RPL_LISTSTART (you can't rely on this being sent anymore)
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply list start', _info('Status', 1),$params->{text});
   },
   322 => sub { # RPL_LIST
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply list', _info('Status', 1), @{$params->{params}}[2..3],$params->{text});
   },
   323 => sub { # RPL_LISTEND
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply list end', _info('Status', 1), $params->{text});
   },
  
   # channel mode
   324 => sub { # RPL_CHANNELMODEIS
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  my $mode = $params->{params}->[3];
	  if(ref $self->{_channels}->{$channel} eq "IRC::Channel") {
	     $self->{_channels}->{$channel}->{mode} = $mode;
		 my $tmp = 4;
		 my %tmp;
		 for(split //,$mode) {
		    next unless /^[lk]$/;
			$tmp{$_} = $params->{params}->[$tmp];
			$tmp++;
	     }
		 
		 if($self->{_channels}->{$channel}->has_mode('k')) {
		    $self->{_channels}->{$channel}->{key} = $tmp{'k'};
		 }
		 if($self->{_channels}->{$channel}->has_mode('l')) {
		    $self->{_channels}->{$channel}->{limit} = $tmp{'l'};
		 }
	  }

      if(exists $self->{_channels}->{$channel} &&
		 $self->{_channels}->{$channel}->{mode_sync}) {
		   delete($self->{_channels}->{$channel}->{mode_sync});
		   return;
      }
	  
	  $self->{event}->handle('reply channel mode', _info($channel, 1), @{$params->{params}}[2.. @{$params->{params}} - 1]);
   },
   329 => sub { # RPL_CREATIONTIME
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  if($self->{_channels}->{$channel}) {
	     $self->{_channels}->{$channel}->{created} = $params->{params}->[3];
	  }
	  $self->{event}->handle('reply channel time', _info($channel, 1), scalar localtime($params->{params}->[3])); 
   },
  
   # onjoin / topic

   331 => sub { # RPL_NOTOPIC
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  $self->{_channels}->{$channel}->{topic} = undef;
	  $self->{_channels}->{$channel}->{topicby} = undef;
	  $self->{_channels}->{$channel}->{topictime} = undef;
	  $self->{event}->handle('reply notopic', _info($channel, 1));
   },
   
   332 => sub { # RPL_TOPIC
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  $self->{_channels}->{$channel}->{topic} = $params->{text};
	  $self->{event}->handle('reply topic', _info($channel, 1), $params->{text});
   },

   333 => sub { # RPL_TOPICWHOTIME
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  $self->{_channels}->{$channel}->{topicby} = $params->{params}->[3];
	  $self->{_channels}->{$channel}->{topictime} = $params->{params}->[4];
	  $self->{event}->handle('reply topicwhotime', _info($channel, 1), $params->{params}->[3], scalar gmtime $params->{params}->[4]);
   },

   # who reply
   352 => sub { # RPL_WHOREPLY
      my($event,$self,$params) = @_;
	  my($channel,$user,$host,$server,$nick,$bits,$realname) =
	     (@{$params->{params}}[2..7], $params->{text});
	  my($op,$voice,$halfop,$hops) = 0;
	  
	  $hops = $1 if $realname =~ s/^(\d+) //;
	  $op = 1 if $bits =~ /\@/;
	  $voice = 1 if $bits =~ /\%/;
	  $halfop = 1 if $bits =~ /\+/;

	  if(defined $self->{_channels}->{$channel} 
	      && ref $self->{_channels}->{$channel} ne 'HASH'
	      && $self->{_channels}->{$channel}->nick($nick)) {
	     $self->{_channels}->{$channel}->{_nicks}->{$nick} = {
		     name => $nick,
			 op => $op,
			 voice => $voice,
			 halfop => $halfop,
			 host => $user . '@' . $host,
			 server => $server,
			 realname => $realname,
			 hops => $hops
		 };
	  }else{
	  }

	  return if $self->{_channels}->{$channel} && $self->{_channels}->{$channel}->{who_sync};

	  $self->{event}->handle('reply who', _info($channel, 1), $channel,$user,$host,$server,$nick,$bits,$hops,$realname);
   },

   315 => sub { # RPL_ENDOFWHO
      my($event,$self,$params) = @_;
	  if(exists $self->{_channels}->{$params->{params}->[2]} &&
	    $self->{_channels}->{$params->{params}->[2]}->{who_sync}) {
		 delete($self->{_channels}->{$params->{params}->[2]}->{who_sync});
		 return;
	  }
	  $self->{event}->handle('reply who end', $params, $params->{params}->[2]);
   },
   
   # onjoin / names
   353 => sub { # RPL_NAMREPLY
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[3];
	  
	  if(exists $self->{_channels}->{$channel} && ref $self->{_channels}->{$channel}) {
	     for(split / /,$params->{text}) {
	        my ($op,$halfop,$voice) = 0;
		    $op = 1 if s/\@//;
		    $voice = 1 if s/\+//;
		    $halfop = 1 if s/\%//;
          if(exists $self->{prefixchars} && $self->{prefixchars}) {
             my $prefix = "[" . quotemeta($self->{prefixchars}) . "]+";
             s/^$prefix//;
          }
			
		    $self->{_channels}->{$channel}->addnick($_,
            op => $op,
            halfop => $halfop,
            voice => $voice,
	       );
	     }
	     $self->{event}->handle('user add', [split(/ /, $params->{text})], $channel);
	  }
	  
	  $self->{event}->handle('reply names', _info($channel, 1), $params->{text});
   },

   366 => sub { # RPL_ENDOFNAMES
      my($event,$self,$params) = @_;
	   #return unless $self->{_channels}->{$params->{params}->[2]};
   },

   367 => sub { # RPL_BANLIST
      my($event,$self,$params) = @_;
	  my $channel = $params->{params}->[2];
	  $self->{event}->handle('reply ban', _info($channel, 1),$channel,@{$params->{params}}[3..5]);
   },
   368 => sub { # RPL_ENDOFBANLIST
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply ban end', _info($params->{params}->[2], 1),$params->{params}->[2],$params->{text});
   },

   372 => sub { # RPL_MOTD
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply motd',_info('Status', 1, undef, 'motd'),$params->{text});
   },
   375 => sub { # RPL_MOTDSTART
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply motd start', _info('Status', 1), $params->{text});
   },
   376 => sub { # RPL_ENDOFMOTD
      my($event,$self,$params) = @_;
	  if(!$self->{connected}) {
	     $self->{nick} = $params->{params}->[1];
		 $self->{server} = $params->{nick};
		 $self->{connect_time} = time;
		 $self->{event}->handle('server connected',$self, $self->{server},$self->{nick});
	  }
	  $self->{event}->handle('reply motd end',_info('Status', 1),$params->{text});
   },
   391 => sub { # RPL_TIME
      my($event,$self,$params) = @_;
	  $self->{event}->handle('reply time',_info('Status', 1),$params->{text});
   },
   401 => sub {
      my($event,$self,$params) = @_;
	  $self->{event}->handle('error nosuchnick', _info($params->{params}->[2], 1));
   },
   433 => sub {
      my($event,$self,$params) = @_;
	  $self->{event}->handle('error nickinuse', _info('Status', 1), $params->{params}->[2]);
   },

);

sub ctcpmsg {
   my($event, $irc, $nick, $host, $to, $text, $type) = @_;
   $type = 'ctcp msg' unless defined $type;

   if($text =~ /^\001([^ \001]+)(?: (.*?))?\001?$/) {
      my($command,$params) = ($1,$2);

      $irc->{event}->handle($type . ' ' . lc $command,
        _info($irc->is_channel($to) ? $to : $nick, 1), $to,
        $nick, $host, $command, $params);

   }else{
      return undef;
   }
}

sub ctcpreply {
   ctcpmsg(@_, 'ctcp reply');
}

sub new {
   my($class,$self,$event) = @_;
   for(keys %raw) {
      next if $event->exists('raw '. $_);
      $event->add('raw '. $_, code => $raw{$_});
   }
   for(['ctcp msg',\&ctcpmsg] , ['ctcp reply', \&ctcpreply]) {
	  next if $event->exists($_->[0]);
	  $event->add($_->[0], code => $_->[1]);
   }				   
   return bless {}, shift;
}

sub _info {
   return { target => $_[0], activity => $_[1], create => (defined $_[2] ? 1 : 0), style => (defined $_[3] ? $_[3] : '')};
}

1;
