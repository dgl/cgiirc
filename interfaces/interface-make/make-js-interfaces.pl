#!/usr/bin/perl
# CGI:IRC JavaScript Interface builder
# Copyright (C) 2002 David Leadbeater (cgiirc@dgl.cx)
# Licensed under the GPLv2
use Symbol;
use IO::Handle;

my(%fd, %current);
my @browsers = qw/ie mozilla konqueror opera7/;
@current{@browsers} = @browsers;

for(@browsers) {
   $fd{$_} = Symbol::gensym;
   open($fd{$_}, ">../$_.pm") or die "Out to ../$_.pm: $!";
#?   $fd{$_}->autoflush(1);
}

open(IN, "main.pm");
my @in = <IN>; # don't use while - bug in perl?
close(IN);
parse_line($_) for @in;

close($fd{$_}) for @browsers;

sub parse_line {
   $_ = $_[0];
   if(/^\.\$?(\w+)(?: (.*))?/) {
        # The $ is so the variables get syntax hilighted :)
      my($cmd, $param) = ($1, $2);
      my @params = split(' ', $param);

      if($cmd eq 'include') {
         open(INC, $param) or die "$param: $!";
         parse_line($_) while <INC>;
         close(INC);
      }elsif($cmd eq 'sub') {
         out_cur("sub $param {\n");
         open(SUB, "$param.pm") or die "$param: $!";
         parse_line($_) while <SUB>;
         close(SUB);
         out_cur("}\n");
      }elsif($cmd eq 'just') {
         for my $current (keys %current) {
            $current{$current} = 0;
            if(scalar(grep(/$current/, @params))) {
               $current{$current} = 1;
            }
         }
      }elsif($cmd eq 'not') {
         for my $current (keys %current) {
            $current{$current} = 1;
            if(scalar(grep(/$current/, @params))) {
               $current{$current} = 0;
            }
         }
      }elsif($cmd eq 'end') {
         @current{keys %current} = keys %current;
      }elsif($cmd eq 'else') {
         for(keys %current) {
            $current{$_} = $current{$_} ? 0 : 1;
         }
      }else{
         print "urm? $cmd isn't valid\n";
      }
      
   }else{
      out_cur($_);
   }
}

sub out_cur {
   $_ = $_[0];
   for my $b(keys %current) {
      my $x = $_;
      $x =~ s/\*\*BROWSER/$b/g;
      my $fh = $fd{$b}; # cry :(
      print $fh $x if $current{$b};
   }
}

