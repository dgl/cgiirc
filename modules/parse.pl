#### Parsing Functions

## Reads a config file from the filename passed to it, returns a reference to
## a hash containing the name=value pairs in the file.
sub parse_config {
   my %config;
   open(CONFIG, '<' . shift) or error("opening config: $!");
   while(<CONFIG>) {
	  s/(\015\012|\012)$//; # Be forgiving for poor windows users
      next if /^\s*[#;]/; # Comments
      next if !/=/;

      my($key,$value) = split(/\s*=\s*/, $_, 2);
      $config{$key} = $value;
   }
   close(CONFIG);
   return \%config;
}

## Parses a CGI input, returns a hash reference to the value within it.
## The clever regexp bit is from cgi-lib.pl
sub parse_query {
   my($query) = @_;
   return {} unless defined $query and length $query;

   return {
	  map {
	     s/\+/ /g;
	     my($key, $val) = split(/=/,$_,2);
	     $key =~ s/%([A-Fa-f0-9]{2})/pack("c",hex($1))/ge;
	     $val =~ s/%([A-Fa-f0-9]{2})/pack("c",hex($1))/ge;
	     $key => $val; # Return a hash element to map.
      } split(/[&;]/, $query)
   };
}

1;
