#!/usr/bin/perl
# (C) 2000 David Leadbeater (http://contact.dgl.cx/)
# cgi-irc comes with ABSOLUTELY NO WARRANTY
# This is free software, and you are welcome to redistribute it
# under certain conditions; read the file COPYING for details

# Decode hex ip addresses as found in CGI:IRC whois (realname) output with the 
# encode ip addresses option turned on

# Now i understand wtf pack and unpack do:
# perl -le'print join ".", unpack "C*",pack "H*", $ARGV[0]'

use strict;
use Socket;
my($input,$output);

print "Type the Hex IP to decode into a normal IP address\n";
$input=<>;
$input =~ s/[^a-z0-9]//gi;

$output = pack "H*", $input;

print "IP: " . join(".", unpack "C*", $output) . "\n";
print "Host: " . scalar gethostbyaddr($output, AF_INET) . "\n";

