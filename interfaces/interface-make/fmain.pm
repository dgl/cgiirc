   my($self, $cgi, $config) = @_;

# evil.
sub regexp_parse {
  my $have_entities = eval { require HTML::Entities; };

  my $string = shift;

  $string =~ s/(?<!\\)\[([^^])[^\]]+\]/$1/g;
  $string =~ s/[\x01-\x20]//g;
  $string =~ s/\(\?[^:].*?\)//g;
  $string =~ s/\((?:\?:)?(.*?)(?:\|.*?)?\)/$1/g;
  $string =~ s/(\\.|.)\?/$1/g;
  $string =~ s/(?<!\\)[*+]//;
  $string =~ s/\\\d+//g;
  $string =~ s/\\(\W)/$1/g;
  return $have_entities ? HTML::Entities::decode_entities($string) : $string;
}
print <<EOF;
$standardheader
<html><head>
<link rel="stylesheet" href="$config->{script_login}?interface=**BROWSER&item=style&style=$cgi->{style}" />
<script>
EOF

if($::config->{smilies_popup}) {
  my $smilies = ::parse_config($::config->{smilies});
  my %smilies;
  for(keys %$smilies) {
    $smilies{regexp_parse($_)} = $smilies->{$_};
  }
  $smilies = _outputhash(\%smilies);

print <<EOF;
var swin;
function smilies() {
  if(!swin) {
    swin = document.createElement("table");
    swin.className = "main-smilies";
    var smilies = $smilies;

    var c = 0, tr;
    for(var i in smilies) {
      if((c++ % 2) == 0) {
        tr = document.createElement("tr");
        swin.appendChild(tr);
      }
      var cont = document.createElement("td");
      var p = document.createElement("img");
      p.title = i;
      p.src = "$config->{image_path}/" + smilies[i] + ".gif";
      cont.appendChild(p);
      cont.onclick = function() {
        parent.fform.append(this.firstChild.title + " ");
        this.parentNode.parentNode.style.display = 'none';
      }
      cont.appendChild(document.createTextNode(" " +
        smilies[i].substr(0,1).toUpperCase() + smilies[i].substr(1)));
      tr.appendChild(cont);
    }
    document.body.appendChild(swin);
  } else {
    swin.style.display = 'block';
  }
}
</script>
EOF
}
print <<EOF;
</head>
<body class="main-body"
onkeydown="if((event && ((event.keyCode < 30 || event.keyCode > 40) && (event.keyCode < 112 || event.keyCode > 123) && !event.ctrlKey)) && parent.fform.location) { parent.fform.fns(); return false; }"
.$just mozilla
onkeypress="if((event && ((event.keyCode < 30 || event.keyCode > 40) && (event.keyCode < 112 || event.keyCode > 123) && !event.ctrlKey)) && parent.fform.location) { parent.fform.fns(); return false; }"
.$end
><div class="main-span" id="text"></div></body></html>
EOF
