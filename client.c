/* CGI:IRC C Helper CGI
 * Copyright (c) David Leadbeater 2002-2007
 * Released Under the GNU GPLv2 or Later
 * NO WARRANTY - See GNU GPL for more
 * $Id$
 */
/* To compile: cc -O2 -o client.cgi client.c */
/* Add -lsocket on Solaris */

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

/******************************************************************************
 * Stralloc (from libowfat(-ish))
 * If you'd rather use dietlibc/libowfat:
 * diet -Os gcc -include stralloc.h -o client.cgi client.c -lowfat */

#ifndef STRALLOC_H
typedef struct stralloc {
  char* s;
  unsigned long int len;
  unsigned long int a;
} stralloc;

int stralloc_ready(stralloc *sa,unsigned long int len) {
  register int wanted=len+(len>>3)+30; /* heuristic from djb */
  if(!sa->s || sa->a<len) {
    register char* tmp;
    if (!(tmp=realloc(sa->s,wanted)))
      return 0;
    sa->a=wanted;
    sa->s=tmp;
  }
  return 1;
}

int stralloc_readyplus(stralloc *sa,unsigned long len) {
  if (sa->s) {
    if (sa->len + len < len) return 0;  /* catch integer overflow */
    return stralloc_ready(sa,sa->len+len);
  } else
    return stralloc_ready(sa,len);
}

int stralloc_catb(stralloc *sa,const char *buf,unsigned long int len) {
  if (stralloc_readyplus(sa,len)) {
    memcpy(sa->s+sa->len,buf,len);
    sa->len+=len;
    return 1;
  }
  return 0;
}

int stralloc_cats(stralloc *sa,const char *buf) {
  return stralloc_catb(sa,buf,strlen(buf));
}

int stralloc_cat(stralloc *sa,stralloc *sa2) {
  return stralloc_catb(sa,sa2->s,sa2->len);
}

int stralloc_append(stralloc *sa,const char *in) {
  if (stralloc_readyplus(sa,1)) {
    sa->s[sa->len]=*in;
    ++sa->len;
    return 1;
  }
  return 0;
}

#define stralloc_0(sa) stralloc_append(sa,"")

#endif
/******************************************************************************/

int unix_connect(stralloc *where);
int error(char *error);
void readinput(stralloc *);
void get_rand(stralloc *, stralloc *);
void get_cookie(stralloc *);

int main(void) {
  int fd, sz;
  char tmp[2048];
  stralloc params = {0}, random = {0}, cookie = {0};

  readinput(&params);

  if(!params.len)
    error("No input found");

  stralloc_0(&params);

  get_rand(&params, &random);

  if(!random.len)
    error("Random value not found");

  params.len--;

  get_cookie(&cookie);

  if(cookie.len) {
    stralloc_cats(&params, "&COOKIE=");
    stralloc_cat(&params, &cookie);
  }

  fd = unix_connect(&random);
  send(fd, params.s, params.len, 0);
  send(fd, "\n", 1, 0);

  while((sz = read(fd, tmp, sizeof tmp)) > 0) {
    write(STDOUT_FILENO, tmp, sz);
  }

  return 0;
}

int error(char *error) {
  puts("Content-type: text/html\n");
  puts("An error occurred:");
  puts(error);
  exit(1);
}

void readinput(stralloc *input) {
  char *method = getenv("REQUEST_METHOD");
  if(!method) return;

  if(strcmp(method, "GET") == 0) {
    char *query = getenv("QUERY_STRING");
    if(query)
      stralloc_cats(input, query);
  }else if(strcmp(method, "POST") == 0) {
    int length;
    char *ctlength = getenv("CONTENT_LENGTH");
    size_t sz;
    if(!ctlength) return;
    length = atoi(ctlength);

    /* Hopefully noone will need to send more than 5KB */
    if(length <= 0 || length > (1024*5)) return;
    stralloc_ready(input, length);
    sz = read(STDIN_FILENO, input->s, length);
    if(sz <= 0) return;
    input->len = sz;
  }
}

void get_rand(stralloc *params, stralloc *random) { 
  char *ptr = strstr(params->s, "R=");

  if(!ptr)
    return;

  ptr += 2;

  while(ptr < params->s + params->len) {
    if(!isalpha((unsigned char)*ptr) && !isdigit((unsigned char)*ptr))
      break;
    stralloc_append(random, ptr++);
  }
}

void get_cookie(stralloc *cookie) {
  char *httpcookie;
  char *sptr, *end_ptr;

  httpcookie = getenv("HTTP_COOKIE");
  if(!httpcookie) return;

#define COOKIE_NAME "cgiircauth="
  sptr = strstr(httpcookie, COOKIE_NAME);
  if(sptr == NULL) return;
  sptr += strlen(COOKIE_NAME);
  if(!*sptr) return;

  end_ptr = strchr(sptr, ';');
  if(end_ptr == NULL)
    end_ptr = sptr + strlen(sptr) - 1;

  stralloc_catb(cookie, sptr, 1 + end_ptr - sptr);
}

#ifndef SUN_LEN
#define SUN_LEN(x) (sizeof(*(x)) - sizeof((x)->sun_path) + strlen((x)->sun_path))
#endif

int unix_connect(stralloc *where) {
  stralloc filename = {0}, errmsg = {0};
  struct sockaddr_un saddr;
  int sock;

  stralloc_cats(&filename, TMPLOCATION);
  stralloc_cat(&filename, where);
  stralloc_cats(&filename, "/sock");
  stralloc_0(&filename);

  sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if(sock == -1) error("socket() error");

  saddr.sun_family = AF_UNIX;
  strncpy(saddr.sun_path, filename.s, sizeof(saddr.sun_path));
  saddr.sun_path[sizeof(saddr.sun_path) - 1] = '\0';

  if(connect(sock, (struct sockaddr *)&saddr, SUN_LEN(&saddr)) == -1) {
    stralloc_cats(&errmsg, "connect(): ");
    stralloc_cats(&errmsg, strerror(errno));
    stralloc_0(&errmsg);
    error(errmsg.s);
  }

  return sock;
}

