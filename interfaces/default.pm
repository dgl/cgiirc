package default;

sub new {
   return bless {};
}

sub exists {
   return 1 if defined &{__PACKAGE__ . '::' . $_[1]};
}

sub form { 
   return "MOO\n";
}

sub line {
   my($self, $type, $target, $html) = @_;
   print "$html<br>\n";
}

sub keepalive {
   print "<!-- nothing comment -->\r\n";
}

sub login {
   my($self, $this, $copy, $config, $order, $items) = @_;
print <<EOF;
<html>
<head>
<title>CGI:IRC Login</title>
</head><body bgcolor="#ffffff">
<form method="post" action="$this" name="loginform">
<table border="0" cellpadding="5" cellspacing="0">
<tr><td colspan="2" align="center" bgcolor="#c0c0dd"><b>CGI:IRC
Login</b></td></tr>
EOF
for(@$order) {
   my $item = $$items{$_};
   print "<tr><td align=\"right\" bgcolor=\"#f1f1f1\">$_</td><td align=\"left\"
bgcolor=\"#f1#f1#f1\">";
   if(ref $item eq 'ARRAY') {
      print "<select name=\"$_\" style=\"width: 100%\">";
      print "<option>$_</option>" for @$item;
      print "</select>";
   }else{
      print "<input type=\"text\" name=\"$_\" value=\"$item\">";
   }
   print "</td></tr>\n";
}
print <<EOF;
<tr><td align="left" bgcolor="#d9d9d9">
<small><a href="$this?adv=1">Advanced..</a></small>
</small></td><td align="right" bgcolor="#d9d9d9">
<input type="submit" value="Login">
</td></tr></table></form>

<small>$copy</small>

</body></html>
EOF
}

1;
