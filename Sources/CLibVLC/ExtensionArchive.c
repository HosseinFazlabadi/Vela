#include "include/ExtensionBridge.h"
#include <archive.h>
#include <archive_entry.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
static int parents(char *path){for(char*p=path+1;*p;p++){if(*p=='/'){*p=0;if(mkdir(path,0700)<0&&errno!=EEXIST){*p='/';return -1;}*p='/';}}return 0;}
char*vela_extension_unpack(const char*input,const char*destination){struct archive*a=archive_read_new();archive_read_support_format_zip(a);archive_read_support_filter_all(a);char*error=NULL;unsigned count=0;size_t total=0;
 if(archive_read_open_filename(a,input,16384)!=ARCHIVE_OK){error=strdup(archive_error_string(a));goto done;}
 struct archive_entry*entry;int status;
 while((status=archive_read_next_header(a,&entry))==ARCHIVE_OK){const char*name=archive_entry_pathname(entry);mode_t type=archive_entry_filetype(entry);if(!name||name[0]=='/'||strchr(name,'\\')||archive_entry_symlink(entry)||archive_entry_hardlink(entry)||(type!=AE_IFREG&&type!=AE_IFDIR)||++count>4096){error=strdup("Invalid extension package entry.");break;}
  char*relative=strdup(name),*part,*save=NULL;bool bad=false;for(part=strtok_r(relative,"/",&save);part;part=strtok_r(NULL,"/",&save)){if(!strcmp(part,".."))bad=true;}free(relative);if(bad){error=strdup("Package paths must remain inside the extension directory.");break;}
  char*path;asprintf(&path,"%s/%s",destination,name);if(parents(path)<0){free(path);error=strdup("Could not create extension directory.");break;}
  if(type==AE_IFDIR){if(mkdir(path,0700)<0&&errno!=EEXIST)error=strdup("Could not create extension directory.");free(path);if(error)break;continue;}
  int fd=open(path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);free(path);if(fd<0){error=strdup("Duplicate or invalid extension file.");break;}
  char buffer[16384];ssize_t n;size_t bytes=0;while((n=archive_read_data(a,buffer,sizeof buffer))>0){bytes+=(size_t)n;total+=(size_t)n;if(bytes>32*1024*1024||total>128*1024*1024){error=strdup("Extension package exceeds its size limit.");break;}ssize_t offset=0;while(offset<n){ssize_t written=write(fd,buffer+offset,(size_t)(n-offset));if(written<=0){error=strdup("Could not write extension file.");break;}offset+=written;}if(error)break;}
  close(fd);if(n<0&&!error)error=strdup(archive_error_string(a));if(error)break;
 }
 if(status!=ARCHIVE_EOF&&!error)error=strdup(archive_error_string(a)?archive_error_string(a):"Invalid ZIP package.");
 done:archive_read_free(a);return error;}
