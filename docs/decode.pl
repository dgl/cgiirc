#!/usr/bin/perl
# (C) 2000 David Leadbeater (cgiirc@dgl.cx)
# cgi-irc comes with ABSOLUTELY NO WARRANTY
# This is free software, and you are welcome to redistribute it
# under certain conditions; read the file COPYING for details

# Decode hex ip addresses as found in CGI:IRC whois (realname) output with the 
# encode ip addresses option turned on

use strict;
my($input,$output);

print "Type the Hex IP to decode into a normal IP address\n";
$input=<>;

for(substr($input,0,2),substr($input,2,2),
	  substr($input,4,2),substr($input,6,2)){
   $output .= hex("$_").".";
}

$output=~ s/\.$//;
print "IP: $output\n";

