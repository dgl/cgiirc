/* CGI:IRC C Helper CGI
 * Copyright (c) David Leadbeater 2002
 * Released Under the GNU GPLv2 or Later
 * NO WARRANTY - See GNU GPL for more
 * $Id: client.c,v 1.3 2002/03/10 14:35:26 dgl Exp $
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

/* Change this to the tmpfile path set in the CGI:IRC Config */
#define TMPLOCATION "/tmp/cgiirc-"

int main(void) {
   int fd;
   char params[2048]; /* Keep input in here */
   char rand[50]; /* Random value - used for the socket location */
   char tmp[2048];
   
   printf("Content-type: text/html\n\n");
   if(!readinput(params)) error("No input found\n");
   if(!get_rand(params, rand)) error("Random Value not found\n");

   fd = unix_connect(rand);
   send(fd, params, strlen(params), 0);
   send(fd, "\n", 1, 0);

   while(read(fd, tmp, 2048) > 0) {
	  printf("%s",tmp);
   }

   return 1;
}

int error(char *error) {
   printf("An error occured: %s\n",error);
   fwrite(error, strlen(error), 1, stderr);
   exit(1);
}

int readinput(char *params) {
   char request[10];

   if(!getenv("REQUEST_METHOD")) return;
   strncpy(request, getenv("REQUEST_METHOD"), 9);
   request[9] = 0;
   if(!strlen(request)) return 0;

   if(strncmp(request, "GET", 3) == 0) {
	  strncpy(params, getenv("QUERY_STRING"), 2048);
	  params[2048] = 0;
	  if(!strlen(params)) return 0;
      return 1;
   }else if(strncmp(request, "POST", 4) == 0) {
	  int length;
	  if(!getenv("CONTENT_LENGTH")) return 0;
	  length = atoi(getenv("CONTENT_LENGTH"));
	  if(!length || length == 0) return 0;
	  fread(params, length > 2048 ? 2048 : length, 1, stdin);
	  params[length] = 0;
	  return 1;
   }else{
	  return 0;
   }
}

int get_rand(char *params, char *rand) { 
   char *ptr, *end_ptr;
   int r = 0, i = 0;
   ptr = params;
   end_ptr = ptr + strlen(ptr);

   for(;ptr < end_ptr; ptr++) {
	  if(r == 1) {
		 if(*ptr == '&') break;
		 if(i > 48) break;
		 if(isalpha(*ptr) || isdigit(*ptr)) {
		    rand[i] = *ptr;
		    i++;
		 }
	  }else if(*ptr == 'R' && *(++ptr) == '=') {
		 r = 1;
	  }
   }
   rand[i] = 0;

   if(r == 1 && strlen(rand)) return 1;
   return 0;
}

int unix_connect(char *where) {
   /*size_t size;*/
   struct sockaddr_un saddr;
   int sock, len;
   char filename[100], errmsg[50];

   len = strlen(TMPLOCATION) + strlen(where);
   if(len > 100) return;
   snprintf(filename, 100, "%s%s/sock", TMPLOCATION, where);
   filename[len] = 0;

   sock = socket(AF_UNIX, SOCK_STREAM, 0);
   if(sock == -1) error("socket() error\n");

   saddr.sun_family = AF_UNIX;
   strcpy(saddr.sun_path, filename);

   if(connect(sock, &saddr, SUN_LEN(&saddr)) == -1) {
          switch(errno) {
             case EACCES:
                error("Access Denied in connect()\n");
             case ENOENT:
                error("No such file in connect()\n");
             default:
				snprintf(errmsg, 50, "Unhandled error in connect(): %d\n", errno);
                error(errmsg);
          }
   }

   return sock;
}

