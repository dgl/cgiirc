   my($self, $cgi, $config) = @_;
   my $string;
   for(keys %$cgi) {
      next if $_ eq 'item';
	  $string .= main::cgi_encode($_) . '=' . main::cgi_encode($cgi->{$_}).'&';
   }
   $string =~ s/\&$//;

print $standardheader;
print q~
<html>
<head>
<script language="JavaScript">
<!--
// This javascript code is released under the same terms as CGI:IRC itself
// http://cgiirc.org/
// Copyright (C) 2000-2003 David Leadbeater <http://dgl.cx>

//               none      joins    talk       directed talk
var activity = ['#000000','#000099','#990000', '#009999'];

var Witems = {};
var options = {};
var currentwindow = '';
var lastwindow = '';
var connected = 0;
var mynickname = '';
var prefixchars = '@%+ ';

.$just ie
document.onselectstart = function() { return false; }
document.onmouseup = function() {
   if(event.button != 2) return true;
   event.returnVal = false;
   return false;
}
document.oncontextmenu = function() {
   return false;
}
document.onhelp = function() {
   sendcmd('/help');
   return false;
}
.$end

function witemadd(name, channel) {
   if(Witems[name] || findwin(name)) return;
   name = name.replace(/\"/g, '&quot;');
   Witems[ name ] = { activity: 0, text: new Array, channel: channel, speak: 1,  info: 0 };
   if(channel) {
      Witems[name].users = {};
	  Witems[name].topic = '';
   }
   if(!currentwindow) currentwindow = name;
   wlistredraw();
}

function witemnospeak(name) {
   if(!Witems[name] && !(name = findwin(name))) return;
   Witems[name].speak = 0;
}

function witeminfo(name) {
   if(!Witems[name] && !(name = findwin(name))) return;
   Witems[name].info = 1;
}

function witemdel(name) {
   if(!Witems[name] && !(name = findwin(name))) return;
   if(name == 'Status') return;
   delete Witems[name];
   if(currentwindow == name) witemchg(lastwindow ? lastwindow : 'Status');
}

function witemclear(name) {
   if(!Witems[name] && !(name = findwin(name))) return;
   Witems[name].text.length = 0;
   witemredraw();
}


function channeladdusers(channel, users) {
   for(var i = 0;i < users.length;i++) {
      channeladduser(channel, users[i]);
   }
   userlist();
}

function channeladduser(channel, user) {
   var o = user.substr(0,1)
   if(prefixchars.lastIndexOf(o) != -1) {
      user = user.substr(1)
      while(prefixchars.lastIndexOf(user.substr(0,1)) != -1)
         user = user.substr(1)
   }

   if(!Witems[channel] && !(channel = findwin(channel))) return;

   Witems[channel].users[user] = { };

   if(o == '@') Witems[channel].users[user].op = 1;
   else if(o == '%') Witems[channel].users[user].halfop = 1;
   else if(o == '+') Witems[channel].users[user].voice = 1;
   else if(prefixchars.lastIndexOf(o) != -1)
      Witems[channel].users[user].other = o;
}

function channelsdeluser(channels, user) {
   if(channels == '-all-') {
      for(var i in Witems) {
         if(!Witems[i].channel) continue;
         if(!Witems[i].users[user]) continue;
         channeldeluser(i, user);
      }
      return;
   }
   for(var i = 0;i < channels.length; i++) {
      channeldeluser(channels[i], user);
   }
   userlist();
}

function channeldeluser(channel, user) {
   if(!Witems[channel] && !(channel = findwin(channel))) return;
   delete Witems[channel].users[user];
   userlist();
}

function channelsusernick(olduser, newuser) {
   for(var channel in Witems) {
      if(!Witems[channel].channel) continue;
      for(var nick in Witems[channel].users) {
	      if(nick == olduser) {
            Witems[channel].users[newuser] = Witems[channel].users[olduser];
            delete Witems[channel].users[olduser];
		   }
	   }
   }
   userlist();
}

function channelusermode(channel, user, action, type) {
   if(!Witems[channel] && !(channel = findwin(channel))) return;
   if(!Witems[channel].users[user]) return;

   if(action == '+') {
      Witems[channel].users[user][type] = 1;
   }else{
      delete(Witems[channel].users[user][type]);
   }
   userlist();
}

function channellist(channel) {
   if(!Witems[channel] && !(channel = findwin(channel))) return;
   var users = new Array();

   for (var i in Witems[channel].users) {
      var user = Witems[channel].users[i];
      if(user.other) i = user.other + i;
     else if(user.op == 1) i = '@' + i
	  else if(user.halfop == 1) i = '%' + i;
	  else if(user.voice == 1) i = '+' + i;
     else   i = ' ' + i;

      users[users.length] = i;
   }

   users = users.sort(usersort);
   return users;
}

function usersort(user1,user2) {
   var m1 = user1.substr(0,1);
   var m2 = user2.substr(0,1);

   if(m1 == m2) {
      if(user1.toUpperCase() < user2.toUpperCase()) return -1
	   return 1
   }

   if(prefixchars.lastIndexOf(m1) < prefixchars.lastIndexOf(m2)) return -1
   return 1
}

function witemchg(name) {
   if(!Witems[name] && !(name = findwin(name))) name = 'Status';
   if(Witems[name].activity > 0) Witems[name].activity = 0;
   lastwindow = (Witems[currentwindow] ? currentwindow : 'Status');
   currentwindow = name;
   wlistredraw();
   witemredraw();
   formfocus();
   userlist();
   retitle();
}

function retitle() {
   parent.document.title = 'CGI:IRC - ' + (Witems[currentwindow].info ? currentwindow.substr(1) : currentwindow) + (Witems[currentwindow].channel == 1 ? ' [' + countit(Witems[currentwindow].users) + '] ' : '');
}

function setoption(option, value) {
   options[option] = value;
   if(option == 'shownick' && value == 1)
      mynick(mynickname)
   else if(option == 'shownick') {
      if(parent.fform && parent.fform.nickchange) parent.fform.nickchange('');
   }else if(option == 'font')
      fontset(value)
.$just ie
   else if((option == 'actsound' || option == 'joinsound') && value == 1)
   	enable_sounds();
.$end
}

function mynick(mynick) {
   mynickname = mynick;
   if(options.shownick != 1) return;
   if(parent.fform && parent.fform.nickchange) parent.fform.nickchange(mynick);
}

function maincolor(bg, fg) {
   var maindoc = parent.fmain.document;
   if(!maindoc) return;
   maindoc.bgColor = bg;
   maindoc.fgColor = fg;
}

function prefix(chars) {
   if(!/ /.test(chars))
      chars += ' '
   prefixchars = chars;
}

function witemchgnum(num) {
   var count = 1;
   for(var name in Witems) {
      if(count++ == num) return name;
   }
   return false;
}

function countit(obj) {
   var i = 0;
   for(var foo in obj) i++;
   return i;
}

function witemaddtext(name, text, activity, redraw) {
   if(name == '-all') {
      for(var window in Witems) {
        if(window == '-all') return
        if(Witems[window].info) continue;
	     witemaddtext(window, text, activity, redraw);
	  }
      return;
   }
   if(name == '-active') name = currentwindow

   if(!Witems[name] && !(name = findwin(name))) {
      if(!Witems["Status"]) return;
	  name = "Status";
   }
   
   if(options["timestamp"] == 1 && !Witems[name].info) {
      var D = new Date();
      text = '[' + (D.getHours() < 10 ? '0' + D.getHours() : D.getHours()) + ':' + (D.getMinutes() < 10 ? '0' + D.getMinutes() : D.getMinutes()) + '] ' + text;
   }
  
   if(options["scrollback"] == 0)
      Witems[name].text = Witems[name].text.slice(Witems[name].text.length - 200);
   if(!Witems[name].info)
      text = "<div class='main-item'>" + text + "</div>";
   Witems[name].text[Witems[name].text.length] = text;

   if(options["actsound"] == 1 && activity >= 3)
      playsound("actmsg");

   if(currentwindow != name && activity > Witems[name].activity)
       witemact(name, activity);
   if(redraw != 0 && currentwindow == name) witemredraw();
}

function witemact(name, activity) {
   if(!Witems[name] && !(name = findwin(name))) return;
   Witems[name].activity = activity;
   wlistredraw();
}

function witemredraw() {
   if(!parent.fmain.document) {
      setTimeout("witemredraw()", 1000);
	  return;
   }
   var doc = parent.fmain.document.body;
   var scrollok = 1;
   if(!currentwindow) currentwindow = 'Status';
.$just ie
   if(doc.scrollTop < (doc.scrollHeight - doc.clientHeight - 5))
      scrollok = 0;
.$end
   parent.fmain.document.getElementById('text').innerHTML = Witems[currentwindow].text.join('');
   if(Witems[currentwindow].info == 1) return;
.$just ie
   var count = 0;
   if(scrollok == 1)
      while(doc.scrollTop < doc.scrollHeight && count < 20) {
         doc.scrollTop = doc.scrollHeight;
         count++;
      }
.$else
   var span = parent.fmain.document.getElementById('text')
   if (span) {
     var count = 0;
     while(span.scrollTop < span.scrollHeight && count < 20) {
       span.scrollTop = span.scrollHeight;
       count++;
     }
   } else {
     var doc = parent.fmain.window;
     var scroll = -1;
     while(doc.scrollY > scroll) {
            scroll = doc.scrollY;
            doc.scrollBy(0, 500);
     }
  }
.$end
}

function wlistredraw() {
   var output='';
   for (var i in Witems) {
      output += '<span class="' + (i == currentwindow ? 'wlist-active' : 'wlist-chooser') + '" style="color: ' + activity[Witems[i].activity] + ';" onclick="witemchg(\'' + (i == currentwindow ? escapejs(lastwindow) : escapejs(i)) + '\')" onmouseover="this.className = \'wlist-mouseover\'" onmouseout="this.className = \'' + (i == currentwindow ? 'wlist-active' : 'wlist-chooser') + '\'">' + escapehtml(Witems[i].info ? i.substr(1) : i) + '</span>\r\n';
   }
   document.getElementById('windowlist').innerHTML = output;
}

function findwin(name) {
   var wname = new String(name);
   wname = wname.replace(/\"/g, '&quot;');
   for (var i in Witems) {
      if (i.toUpperCase() == wname.toUpperCase())
	     return i;
   }
   return false;
}

function escapejs(string) {
   out = string.replace(/\\\\/g,'\\\\\\\\').replace(/\\'/g, '\\\\\\'').replace(/\"/g, '&quot;');
   return out;
}

function escapehtml(string) {
   var out = string;
   out = out.replace(/</g, '&lt;');
   out = out.replace(/>/g, '&gt;');
   out = out.replace(/\"/g, '&quot;');
   return out;
}

function reconnect() {
	  do_quit();
     Witems = { };
     if(document.getElementById('iframe').src.match(/\&token=/)) {
       window.location.reload()
     } else {
       document.getElementById('iframe').src = document.getElementById('iframe').src + '&xx=yy';
     }
}

function sendcmd(cmd) {
   if(cmd.substr(0, 10) == '/reconnect') {
      reconnect();
      return;
   }

   if(!connected && cmd.substr(0,5) != '/quit') {
	  alert('Not connected to IRC!');
	  return;
   }
   if(Witems[currentwindow] && !Witems[currentwindow].speak && cmd.substr(0,1) != '/') return;
   sendcmd_real('say', cmd, currentwindow);
}

function sendcmd_userlist(action, user) {
   if(!Witems[currentwindow].channel) return;
   if(!connected) {
      alert('Not connected to IRC!');
      return;
   }
   sendcmd_real('say', '/' + action + ' ' + user, currentwindow);
}

function sendcmd_real(type, say, target) {
   send_make({ item: 'say', cmd: type, say: say, target: target })
}

function senditem(item) {
   send_make({ item: item })
}

function send_option(name, value) {
   send_make({ cmd: 'options', name: name, value: value })
}

function send_make(data) {
.$just ie mozilla
   var xmlhttp = xmlhttp_new()
.$else
   var xmlhttp = 0
.$end

   if(xmlhttp) {
     try {
       xmlhttp_send(xmlhttp, data)
     } catch(e) {
       xmlhttp = 0
     }
   }

   if(!xmlhttp) {
      for(var i in data) {
         document.hsubmit[i].value = data[i]
      }
      document.hsubmit.submit();
      for(var i in data) {
         document.hsubmit[i].value = ""
      }
   }
}

function userlist() {
   if(!parent.fuserlist.userlist) {
      setTimeout(1000, "userlist()");
      return;
   }
   if(Witems[currentwindow] && Witems[currentwindow].channel == 1) {
      userlistupdate(channellist(currentwindow));
   }else{
      userlistupdate([' No channel']);
   }
   retitle();
}

function userlistupdate(list) {
   if(!parent.fuserlist.userlist) return;
   parent.fuserlist.userlist(list);
}

function formfocus() {
   if(parent.fform.location) parent.fform.fns();
}

function disconnected() {
   if(connected == 1) {
	  connected = 0;
	  do_quit();
	  witemaddtext('-all', '<b>Disconnected</b>', 1, 1);
   }
}

function doinfowin(name, text) {
   witemadd(name, 0);
   witemnospeak(name);
   witeminfo(name);
   witemclear(name);
   witemaddtext(name, text, 0, 1);
   witemchg(name);
}

function fontset(font) {
   if(parent.frames.fmain.document.getElementById('text')) {
      parent.frames.fmain.document.getElementById('text').style.fontFamily = font;
   }
}

function playsound(soundname) {
.$just ie
   var sound = document.getElementById("sound-" + soundname);
   if(sound)
      sound.play();
   else
.$end
      top.window.focus();
}

function joinsound() {
   if(options["joinsound"] == 1)
      playsound("join");
}

~;
# ' (fix syntax hilight)
print <<EOF;
imghelpdn = new Image();
imghelpdn.src = "$config->{image_path}/helpdn.gif";
imghelpup = new Image();
imghelpup.src = "$config->{image_path}/helpup.gif";

imgoptionsdn = new Image();
imgoptionsdn.src = "$config->{image_path}/optionsdn.gif";
imgoptionsup = new Image();
imgoptionsup.src = "$config->{image_path}/optionsup.gif";

imgclosedn = new Image();
imgclosedn.src = "$config->{image_path}/closedn.gif";
imgcloseup = new Image();
imgcloseup.src = "$config->{image_path}/closeup.gif";

function do_quit() {
   var i = new Image();
   i.src = "$config->{script_form}?R=$cgi->{R}&cmd=quit";
}
.$just ie mozilla
function xmlhttp_new() {
   if(window.XMLHttpRequest)
      xmlhttp = new XMLHttpRequest()
   else if (window.ActiveXObject)
      xmlhttp = new ActiveXObject("Microsoft.XMLHTTP")
   return xmlhttp
}

function xmlhttp_send(xmlhttp, data) {
   var send = "";
   xmlhttp.open("POST", "$config->{script_form}", 1)
   xmlhttp.setRequestHeader("Content-type", "application/x-www-form-urlencoded; charset=utf-8")
   xmlhttp.onreadystatechange = post_results
   data.R = "$cgi->{R}";
   data.xmlhttp = 1; // should be header (needs client.cgi proto changes...)
   for(var i in data)
     send += i + "=" + escape(data[i]).replace('+', '%2b') + "&"
   xmlhttp.send(send)
   return false
}

function post_results() {
   if(xmlhttp.readyState < 4)
      return

   if(xmlhttp.status != 200) {
      var w = window.open()
      w.document.write(xmlhttp.responseText)
      w.document.close()
      return
   }
}
.$end
// -->
</script>
<link rel="stylesheet" href="$config->{script_login}?interface=**BROWSER&item=style&style=$cgi->{style}" />
</head>
<body onload="wlistredraw()" onkeydown="formfocus()" onbeforeunload="do_quit()" onunload="do_quit()" class="wlist-body">
<noscript>Scripting is required for this interface</noscript>
<table class="wlist-table">
<tr><td width="1">
<iframe src="$config->{script_nph}?$string" id="iframe" width="1" height="1" style="display:none;border:0;" ></iframe>

<iframe src="$config->{script_login}?interface=**BROWSER&item=blank" width="1" height="1" style="display:none; border:0; " name="hiddenframe"></iframe>
</td>
<td id="windowlist" class="wlist-container">
</td><td class="wlist-buttons">
<img src="$config->{image_path}/helpup.gif" onclick="if(connected == 0)return;sendcmd('/help');" class="wlist-button" onmousedown="this.src=imghelpdn.src" onmouseup="this.src=imghelpup.src;" onmouseout="this.src=imghelpup.src;" title="Help">
</td><td class="wlist-buttons">
<img src="$config->{image_path}/optionsup.gif" onclick="senditem('options');" class="wlist-button" onmousedown="if(connected == 0)return;this.src=imgoptionsdn.src" onmouseup="this.src=imgoptionsup.src;" onmouseout="this.src=imgoptionsup.src;" title="Options">
</td><td class="wlist-buttons">
<img src="$config->{image_path}/closeup.gif" onclick="if(connected == 0)return;if(currentwindow != 'Status'){sendcmd('/winclose')}else if(confirm('Are you sure you want to quit?')){do_quit();parent.location='$config->{script_login}'}" class="wlist-button" onmousedown="this.src=imgclosedn.src" onmouseup="this.src=imgcloseup.src;" onmouseout="this.src=imgcloseup.src;" title="Close">
</td></tr></table>

<form name="hsubmit" method="post" action="$config->{script_form}" target="hiddenframe">
<input type="hidden" name="R" value="$cgi->{R}">
<input type="hidden" name="cmd" value="say">
<input type="hidden" name="item" value="say">
<input type="hidden" name="say" value="">
<input type="hidden" name="target" value="">
<input type="hidden" name="name" value="">
<input type="hidden" name="value" value="">
</form>
.$just ie
<span style="display:none" id="sounds"></span>
<script>
function enable_sounds() {
   if(document.getElementById('sounds').innerHTML == "")
      document.getElementById('sounds').innerHTML = "<embed src='$config->{image_path}/join.wav' hidden='false' loop='false' autostart='false' type='audio/x-wav' id='sound-join'><embed src='$config->{image_path}/actmsg.wav' hidden='false' loop='false' autostart='false' type='audio/x-wav' id='sound-actmsg'>"
}
</script>
.$end
</body></html>
EOF

