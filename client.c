/* CGI:IRC C Helper CGI
 * Copyright (c) David Leadbeater 2002
 * Released Under the GNU GPLv2 or Later
 * NO WARRANTY - See GNU GPL for more
 * $Id: client.c,v 1.10 2005/06/19 18:07:36 dgl Exp $
 */

#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

/* Change this to the tmpfile path set in the CGI:IRC Config */
#define TMPLOCATION "/tmp/cgiirc-"

int unix_connect(char *where);
int error(char *error);
int readinput(char *params);
int get_rand(char *params, char *rand);
int get_cookie(char *cookie);

int main(void) {
   int fd;
   char params[2048]; /* Keep input in here */
   char rand[50]; /* Random value - used for the socket location */
   char tmp[2148]; /* I decided to stop adding comments after here */
   char cookie[100];
   
   if(!readinput(params)) error("No input found\n");
   if(!get_rand(params, rand)) error("Random Value not found\n");

   if(get_cookie(cookie)) {
      char tmp2[2148]; /* I'm sure there's a better way of doing this.. */
      strncpy(tmp2, params, 2147);
      snprintf(params, 2148, "COOKIE=%s&%s", cookie, tmp2);
   }

   fd = unix_connect(rand);
   send(fd, params, strlen(params), 0);
   send(fd, "\n", 1, 0);

   while(read(fd, tmp, 2048) > 0) {
	  printf("%s",tmp);
   }

   return 1;
}

int error(char *error) {
   printf("Content-type: text/html\n\n");
   printf("An error occurred: %s\n",error);
   exit(1);
}

int readinput(char *params) {
   char request[10];

   if(!getenv("REQUEST_METHOD")) return 0;
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

int get_cookie(char *cookie) {
   char ctmp[1024];
   char *sptr, *end_ptr;
   int i;

   if(!getenv("HTTP_COOKIE")) return 0;
   strncpy(ctmp, getenv("HTTP_COOKIE"), 1023);

   sptr = strstr(ctmp, "cgiircauth=");
   if(sptr == NULL) return 0;
   if(strlen(sptr) < 12) return 0;
   sptr += 11;
   end_ptr = sptr + (strlen(sptr) < 99 ? strlen(sptr) : 99);

   i = 0;
   while((int)sptr < (int)end_ptr && *sptr != ';') {
      cookie[i] = *sptr;
      sptr++;
      i++;
   }
   cookie[i] = '\0';
   return 1;
}

int unix_connect(char *where) {
   /*size_t size;*/
   struct sockaddr_un saddr;
   int sock, len;
   char filename[100], errmsg[100];

   len = strlen(TMPLOCATION) + strlen(where) + 6;
   if(len > 100) error("Too long");
   snprintf(filename, len, "%s%s/sock", TMPLOCATION, where);
   filename[len] = 0;

   sock = socket(AF_UNIX, SOCK_STREAM, 0);
   if(sock == -1) error("socket() error\n");

   saddr.sun_family = AF_UNIX;
   strcpy(saddr.sun_path, filename);

   if(connect(sock, (struct sockaddr *)&saddr, SUN_LEN(&saddr)) == -1) {
          switch(errno) {
             case EACCES:
                error("Access Denied in connect()\n");
		     case ECONNREFUSED:
				error("Connection refused in connect()\n");
             case ENOENT:
                error("No such file in connect()\n");
             default:
                snprintf(errmsg, 99, "Unhandled error in connect(): %s\n", strerror(errno));
                error(errmsg);
          }
   }

   return sock;
}

