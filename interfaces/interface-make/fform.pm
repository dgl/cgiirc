   my($self, $cgi, $config) = @_;
print <<EOF;
$standardheader
<html>
<head>
<html><head>
<script language="JavaScript"><!--
var shistory = [ ];
var hispos;
var tabtmp = [ ];
var tabpos;
var tablen;
var tabinc;

function fns(){
   if(!document.myform.say) return;
   document.myform.say.focus();
}

function t(item,text) {
   if(item.style.display == 'none') {
      item.style.display = 'inline';
	  text.value = '>>';
	  document.myform.say.style.width='40%'
   }else{
      item.style.display = 'none';
	  text.value = '<<';
	  document.myform.say.style.width='90%'
   }
   fns();
}

function load() {
   fns();
   document.getElementById('extra').style.display = 'none';
.$just ie konqueror
   document.onkeydown = enter_key_trap;
.$else
   document.onkeypress = enter_key_trap;
.$end
}

function append(a) {
   document.myform["say"].value += a;
   fns();
}

function cmd() {
   if(document.myform["say"].value.length < 1) return false;
   hisadd();
   tabpos = 0;
   tabtmp = [];
   parent.fwindowlist.sendcmd(document.myform["say"].value);
   document.myform["say"].value = ''
   return false;
}

function nickchange(nick) {
   if(document.getElementById('nickname'))
      document.getElementById('nickname').innerHTML = nick;
}

function hisadd() {
   shistory[shistory.length] = document.myform["say"].value;
   hispos = shistory.length;
}

function hisdo() {
   if(shistory[hispos]) {
      document.myform["say"].value = shistory[hispos];
   }else{
      document.myform["say"].value = '';
   }
}

function enter_key_trap(e) {
   if(e == null) { // MSIE
      return keypress(event.srcElement, event);
   }else{ // Mozilla, Netscape, W3C
      return keypress(e.target, e);
   }
}

function keypress(srcEl, event) {
   if (srcEl.tagName != 'INPUT' || srcEl.name.toLowerCase() != 'say')
       return true;
   var charCode = event.charCode; // MSIE: undef, Mozilla: different when shifted
   var keyCode = event.keyCode; // the only one in MSIE, Mozilla: only special keys (up, down, etc)
   var which = event.which; // the only one in NN

   if(keyCode == null) { // NN
      charCode = which;
      if(which < 32) keyCode = which;
      // NN only has charcodes (and some special keys below 32, i.e. Esc)
   }
   if(charCode == null) charCode = keyCode; // MSIE

   if((charCode == 66 || charCode == 98) && event.ctrlKey) {
       // in NN/Mozilla charcodes are case sensitive
       append('\%B');
   }else if((charCode == 67 || charCode == 99) && event.ctrlKey) {
       append('\%C');
   }else if(keyCode == 9) { // TAB
       var tabIndex = srcEl.value.lastIndexOf(' ');
	   var tabStr = srcEl.value.substr(tabIndex+1 || tabIndex).toLowerCase();

       if(tabpos == tabIndex && !tabStr && tabtmp.length) {
	      if(tabinc >= tabtmp.length) tabinc = 0;
	      for(var i = (tabinc > 0 ? tabinc : 0); i < tabtmp.length;i++) {
			 srcEl.value = srcEl.value.substr(0, tabIndex - tablen) + 
			       tabtmp[i] + (tabIndex == tablen ? ': ' : ' ');
			 tabpos = (tabIndex == -1 ? 0 : tabIndex) + tabtmp[i].length - tablen + (tabIndex == tablen ? 1 : 0);
			 tablen = tabtmp[i].length + (tabIndex == tablen ? 1 : 0);
			 tabinc++;
			 break;
		  }
	   }else{
	      tabtmp = [];
	      var list = parent.fwindowlist.channellist(parent.fwindowlist.currentwindow);
		  for(var i = 0;i < list.length; i++) {
		     var item = list[i].replace(/^[+%@ ]/,'');
		     if(item.substr(0, tabStr.length).toLowerCase() == tabStr) {
			    tabtmp[tabtmp.length] = item;
			 }
		  }
		  if(!tabtmp[0]) {
		     for(var i in parent.fwindowlist.Witems) {
			    if(i.substr(0, tabStr.length).toLowerCase() == tabStr) {
               if(parent.fwindowlist.Witems[i].speak)
				      tabtmp[tabtmp.length] = i;
				}   
			 }
		  }
		  if(!tabtmp[0]) return false;
		  srcEl.value = srcEl.value.substr(0, tabIndex) + 
		        (tabIndex > 0 ? ' ' : '') + tabtmp[0] + (tabIndex == -1 ? ': ' : ' ');
		  tablen = tabtmp[0].length + (tabIndex == -1 ? 1 : 0);
		  tabpos = (tabIndex == -1 ? 0 : tabIndex + 1) + tablen;
		  tabinc = 1;
	   }
   }else if(keyCode == 38) { // UP, doesn't work in NN
       if(!shistory[hispos]) {
	      if(document.myform["say"].value) hisadd();
		  hispos = shistory.length;
	   }
	   hispos--;
	   hisdo();
   }else if(keyCode == 40) { // DOWN, dito
       if(!shistory[hispos]) {
	      if(document.myform["say"].value) hisadd();
		  document.myform["say"].value = '';
		  return false;
	   }
	   hispos++;
	   hisdo();
   }else if(((event.altKey && !event.ctrlKey) || (!event.altKey && event.ctrlKey)) && charCode > 47 && charCode < 58) {
       // Alt or Ctrl + number is often bound to browser functions
       // Ctrl+Alt is totally equal to AltGr on Windows (strange!)
       // so use Ctrl+num or Alt+num, whatever the browser passes through
       var num = charCode - 48;
	   if(num == 0) num = 10;

	   var name = parent.fwindowlist.witemchgnum(num);
	   if(!name) return false;
	   parent.fwindowlist.witemchg(name);
   }else if(keyCode == 27) { // ignore escape (to stop..)
   }else{
       return true;
   }
   return false;
}

function pastedata(text) {
   var paste = text.split("\\n");
   if(paste.length == 1)
      return true;
   if(paste.length > 20) {
      alert("You can't paste more than 20 lines");
      return false;
   }

   if(paste.length < 5 ||
     confirm("Are you sure you want to paste " + paste.length + " lines?")) {
      parent.fwindowlist.sendcmd_real('paste', text, parent.fwindowlist.currentwindow);
      return false;
   }
}

//-->
</script>
<link rel="stylesheet" href="$config->{script_login}?interface=**BROWSER&item=style&style=$cgi->{style}" />
</head>
<body onload="load()" onfocus="fns()" class="form-body">
<form name="myform" onSubmit="return cmd();" class="form-form">
<span id="nickname" class="form-nickname"></span>
<input type="text" class="form-say" name="say" autocomplete="off"
  onpaste="return pastedata(window.clipboardData.getData('Text',''));"
.$just konqueror
 size="100"
.$end
>
</form>
EOF

if($ENV{HTTP_USER_AGENT} !~ /Mac_PowerPC/) {
print <<EOF;
<span class="form-econtain">
<input type="button" class="form-expand" onclick="t(document.getElementById('extra'),this);" value="&lt;&lt;">
<span id="extra" class="form-extra">
<input type="button" class="form-boldbutton" value="B" onclick="append('\%B')">
<input type="button" class="form-boldbutton" value="_" onclick="append('\%U')">
EOF
for(sort {$a <=> $b} keys %colours) {
   print "<input type=\"button\" style=\"background: $colours{$_}\" value=\"&nbsp;&nbsp;\" onclick=\"append('\%C$_')\">\n";
}
print <<EOF;
</span>
</span>
EOF
}
print <<EOF;
</body>
</html>
EOF
