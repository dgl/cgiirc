   my($self, $cgi, $config) = @_;
print <<EOF;
$standardheader
<html><head>
<link rel="stylesheet" href="$config->{script_login}?interface=**BROWSER&item=style&style=$cgi->{style}" />
</head>
<body class="main-body"
onkeydown="if((event && ((event.keyCode < 30 || event.keyCode > 40) && !event.ctrlKey)) && parent.fform.location) parent.fform.fns();">

<span class="main-span" id="text"></span>
</body></html>
EOF
