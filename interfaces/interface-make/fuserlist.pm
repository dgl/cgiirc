   my($self, $cgi, $config) = @_;
print <<EOF;
$standardheader
<html>
<head>
<script language="JavaScript">
<!--
var selected;

function fsubmit(form) {
   var action = form.action.options[form.action.selectedIndex].value;
   var user = form.user.value;

   if(!user || !action) {
      alert("No user or action selected");
      return false;
   }
   user = user.replace(/^[@%+ ]/, '');
   parent.fwindowlist.sendcmd_userlist(action, user);
   return false;
}

function deselect() {
   if(!selected) return;
   selected.className = 'userlist-item';
}

function userlist(users) {
   var tmp = '<table class="userlist-table">';
   for(var i = 0;i < users.length; i++) {
      var status = users[i].substr(0, 1);
      var user = users[i].substr(1);

      tmp += '<tr><td class="userlist-status"> ' + statushtml(status) + ' </td>'
          + '<td class="userlist-item" ' + 
        (user != 'No channel' ? 
          ' onmouseout="this.className=(this == selected ?'
          + '\\'userlist-selected\\':\\'userlist-item\\')"'
          + ' onmouseover="this.className=\\'userlist-hover\\'"'
          + ' onclick="' + 'this.className=\\'userlist-selected\\';'
          + 'deselect();selected = this;document.mform.user.value = \\''
          + parent.fwindowlist.escapejs(user) + '\\';return false;" ondblclick="fsubmit(document.mform);"'
          : '') + '>' + user + '</td></tr>';
   }
   tmp += '</table>';
   document.getElementById('usertable').innerHTML = tmp;
   document.mform.user.value = '';
}

function statushtml(status) {
   if(status == "@") {
      return '<div class="userlist-op">@</div>';
   }else if(status == "+") {
      return '<div class="userlist-voice">+</div>';
   }else if(status == "%") {
      return '<div class="userlist-halfop">%</div>';
   }else if(status == ' ') {
      return '';
   }else{
      return '<div class="userlist-other">' + status + '</div>';
   }
}

.$just ie
document.onselectstart = function() { return false; }
.$end
// -->
</script>
<link rel="stylesheet" href="$config->{script_login}?interface=**BROWSER&item=style&style=$cgi->{style}" />
</head>

<body class="userlist-body">

<div class="userlist-div" id="usertable">

<table class="userlist-table">
<tr><td class="userlist-status"></td>
<td class="userlist-item">No channel</td></tr>
</table>

</div>

<form name="mform" onsubmit="return fsubmit(this)" class="userlist-form">
<input type="hidden" name="user">
<select name="action" class="userlist-select">
<option value="query">Query</option>
<option value="whois">Whois</option>
<option value="kick">Kick</option>
</select>
<input type="submit" class="userlist-btn" value="&gt;&gt;">
</form>

</body>
</html>
EOF
