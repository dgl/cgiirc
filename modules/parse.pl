#### Parsing Functions
use strict;

## Reads a config file from the filename passed to it, returns a reference to
## a hash containing the name=value pairs in the file.
sub parse_config {
   my %config;
   open(CONFIG, "<$_[0]") or error("Opening config file '$_[0]': $!");
   eval { local $SIG{__DIE__}; binmode CONFIG, ':utf8'; };
   while(<CONFIG>) {
      s/(\015\012|\012)$//; # Be forgiving for poor windows users
      next if /^\s*[#;]/; # Comments
      next if !/=/;

      my($key,$value) = split(/\s*=\s*/, $_, 2);
      $config{$key} = defined $value ? $value : '';
   }
   close(CONFIG);
   return \%config;
}

sub make_utf8 {
	# Use perl's unicode support assuming we have 5.6 and Encode
	return pack("U", hex($_[0])) if $] >= 5.006 && $::ENCODE;
	# From http://www1.tip.nl/~t876506/utf8tbl.html
   my $chr = unpack("n", pack("H*", shift));
   return chr $chr if $chr < 0x7F;
   return chr(192 + int($chr / 64)) . chr(128 + $chr % 64) if $chr <= 0x7FF;
   return chr(224 + int($chr / 4096)) . chr(128 + int($chr / 64) % 64) .
      chr(128 + $chr % 64) if $chr <= 0xFFFF;
   return chr(240 + int($chr / 262144)) . chr(128 + int($chr / 4096) % 64) .
      chr(128 + int($chr / 64) % 64) . chr(128 + $chr % 64) if $chr <= 0x1FFFFF;
   return "";
}

## Parses a CGI input, returns a hash reference to the value within it.
## The clever regexp bit is from cgi-lib.pl
## This now also removes certain characters that might not be a good idea.
## $ext (bitmask): 1 to *NOT* remove \n etc, 2 to treat input as xmlhttp
## (different encoding for +).
sub parse_query {
   my($query, $ext) = @_;
   return {} unless defined $query and length $query;

   return {
	  map {
	     s/\+/ /g unless defined $ext and $ext & 2;
	     my($key, $val) = split(/=/,$_,2);
	     $val = "" unless defined $val;

	     $key =~ s/%([A-Fa-f0-9]{2})/pack("c",hex($1))/ge;
	     $key =~ s/[\r\n\0\001]//g;

        # Modified from unescape as found in CGI::Util
		  # (can't use CGI::Util due to + oddity from XMLHTTP).
		  $val =~ s{%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))}
		    {
				 if(defined($1)) {
					 if(defined($ext) && $ext & 2 and hex($1) > 0x7F) {
						 make_utf8("00$1");
					 }else{
						 pack("C", hex($1));
					 }
				 }else{
					 make_utf8($2);
				 }
			}ge;

        if(defined $ext and $ext & 1) {
           $val =~ s/[\0\001]//g;
        }else{
           $val =~ s/[\r\n\0\001]//g;
        }

		  Encode::_utf8_on($val) if $::ENCODE;

	     $key => $val; # Return a hash element to map.
      } split(/[&;]/, $query)
   };
}

sub parse_cookie {
   if(exists $ENV{HTTP_COOKIE} && $ENV{HTTP_COOKIE} =~ /cgiircauth/) {
	  for(split /;/, $ENV{HTTP_COOKIE}) {
		 s/^\s+//;
		 my($name,$value) = split(/=/,$_,2);
		 return $value if $name eq "cgiircauth";
	  }
   }
   return 0;
}

sub parse_interface_cookie {
   my %tmp = ( );
   if(exists $ENV{HTTP_COOKIE} && $ENV{HTTP_COOKIE} =~ /cgiirc/) {
      for(split /;/, $ENV{HTTP_COOKIE}) {
         s/^\s+//;
         my($name,$value) = split(/=/,$_,2);
         next if $name =~ /[^a-z]/i;
         next unless $name =~ s/^cgiirc//;
         next if $name eq 'auth';
         $tmp{$name} = $value;
      }
   }
   return \%tmp;
}

sub escape_html {
   my($html) = @_;
   $html =~ s/&/&amp;/g;
   $html =~ s/>/&gt;/g;
   $html =~ s/</&lt;/g;
   $html =~ s/"/&quot;/g;
   return $html;
}

1;
