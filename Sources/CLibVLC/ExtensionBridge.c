#include "include/ExtensionBridge.h"
#include "vlc.h"
#include "libs.h"
#include "libs/misc.h"
#include "libs/input.h"
#define N_(s) (s)
#include "libvlc_internal.h"
#include "media_player_internal.h"
#include "media_internal.h"
#include <vlc_aout.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netdb.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <crt_externs.h>
const char vlc_module_name[]="vela-extensions";
int vela_save_config(libvlc_instance_t*instance){return config_SaveConfigFile((vlc_object_t*)instance->p_libvlc_int);}
static atomic_int live_extensions=0;
int vela_extension_live_count(void){return atomic_load(&live_extensions);}
struct VelaExtension{lua_State*L;vela_extension_command command;void*context;char*error;_Atomic double deadline;atomic_int active,watch_stop;pthread_t watchdog;bool watch_ready;atomic_int cancelled;size_t memory;int sockets[128];int socket_count;libvlc_instance_t*instance;libvlc_media_player_t*player;VelaDiscovery*discovery;vlclua_dtable_t dtable;bool fd_ready;};
void vlclua_set_object(lua_State*L,void*id,void*value){lua_pushlightuserdata(L,id);lua_pushlightuserdata(L,value);lua_rawset(L,LUA_REGISTRYINDEX);}
void*vlclua_get_object(lua_State*L,void*id){lua_pushlightuserdata(L,id);lua_rawget(L,LUA_REGISTRYINDEX);void*p=lua_touserdata(L,-1);lua_pop(L,1);return p;}
#undef vlclua_set_this
void vlclua_set_this(lua_State*L,vlc_object_t*obj){vlclua_set_object(L,vlclua_set_this,obj);}
vlc_object_t*vlclua_get_this(lua_State*L){return vlclua_get_object(L,vlclua_set_this);}
playlist_t*vlclua_get_playlist_internal(lua_State*L){return vlclua_get_object(L,vlclua_get_playlist_internal);}
int vlclua_push_ret(lua_State*L,int result){lua_pushinteger(L,result);lua_pushstring(L,vlc_error(result));return 2;}
int vlclua_dir_list(const char*name,char***result){char**dirs=calloc(4,sizeof(char*));if(!dirs)return VLC_ENOMEM;char*roots[]={config_GetUserDir(VLC_DATA_DIR),config_GetLibDir(),config_GetDataDir()};int n=0;for(int i=0;i<3;i++){if(roots[i]){asprintf(&dirs[n++],"%s/lua/%s",roots[i],name);free(roots[i]);}}*result=dirs;return VLC_SUCCESS;}
void vlclua_dir_list_free(char**dirs){if(!dirs)return;for(int i=0;dirs[i];i++)free(dirs[i]);free(dirs);}
static void*allocated(void*context,void*ptr,size_t old,size_t size){VelaExtension*e=context;size_t previous=ptr?old:0;if(!size){free(ptr);e->memory-=previous;return NULL;}if(size>64*1024*1024 || e->memory-previous>64*1024*1024-size)return NULL;void*result=realloc(ptr,size);if(result)e->memory=e->memory-previous+size;return result;}
static int valid_socket(VelaExtension*e,int fd){for(int i=0;i<e->socket_count;i++)if(e->sockets[i]==fd)return 1;return 0;}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static VelaExtension*owner(lua_State*L){lua_getfield(L,LUA_REGISTRYINDEX,"vela.owner");VelaExtension*e=lua_touserdata(L,-1);lua_pop(L,1);return e;}
/* Preserve Lua 5.1's encoded wait status while making shell waits cancellable. */
static int execute_command(lua_State*L){if(lua_isnoneornil(L,1)){lua_pushinteger(L,access("/bin/sh",X_OK)==0);return 1;}const char*command=luaL_checkstring(L,1);VelaExtension*e=owner(L);if(atomic_load(&e->cancelled))return luaL_error(L,"Extension is closed");posix_spawnattr_t attributes;posix_spawnattr_init(&attributes);posix_spawnattr_setflags(&attributes,POSIX_SPAWN_SETPGROUP);posix_spawnattr_setpgroup(&attributes,0);pid_t pid;char*args[]={"sh","-c",(char*)command,NULL};int result=posix_spawn(&pid,"/bin/sh",NULL,&attributes,args,*_NSGetEnviron());posix_spawnattr_destroy(&attributes);if(result){lua_pushinteger(L,-1);return 1;}int status=0;for(;;){pid_t waited=waitpid(pid,&status,WNOHANG);if(waited==pid){lua_pushinteger(L,status);return 1;}if(waited<0&&errno!=EINTR){lua_pushinteger(L,-1);return 1;}if(atomic_load(&e->cancelled)||now()>atomic_load(&e->deadline)){kill(-pid,SIGTERM);double until=now()+0.25;while(now()<until){waited=waitpid(pid,&status,WNOHANG);if(waited==pid|| (waited<0&&errno!=EINTR))break;usleep(10000);}kill(-pid,SIGKILL);if(waited!=pid)while(waitpid(pid,&status,0)<0&&errno==EINTR){}return luaL_error(L,"Extension command cancelled or timed out");}usleep(10000);}}
input_thread_t*vela_current_input(lua_State*L){VelaExtension*e=owner(L);if(!e->player)return NULL;pthread_mutex_lock(&e->player->input.lock);input_thread_t*input=e->player->input.p_thread;if(input)vlc_object_hold(input);pthread_mutex_unlock(&e->player->input.lock);return input;}
audio_output_t*vela_current_aout(lua_State*L){VelaExtension*e=owner(L);return e->player?input_resource_HoldAout(e->player->input.p_resource):NULL;}
static audio_output_t*vela_aout(lua_State*L){return vela_current_aout(L);}
int vela_player_input_state(libvlc_media_player_t*player){pthread_mutex_lock(&player->input.lock);input_thread_t*input=player->input.p_thread;if(input)vlc_object_hold(input);pthread_mutex_unlock(&player->input.lock);if(!input)return -1;int state=var_GetInteger(input,"state");vlc_object_release(input);return state;}

float vela_volume_get(lua_State*L){audio_output_t*aout=vela_aout(L);if(!aout)return -1;float v=aout_VolumeGet(aout);vlc_object_release(aout);return v;}
int vela_volume_set(lua_State*L,float value){audio_output_t*aout=vela_aout(L);if(!aout)return -1;int ret=aout_VolumeSet(aout,value);vlc_object_release(aout);return ret;}
int vela_volume_up(lua_State*L,int step,float*out){audio_output_t*aout=vela_aout(L);if(!aout)return -1;int ret=aout_VolumeUpdate(aout,step,out);vlc_object_release(aout);return ret;}
VelaDiscovery*vela_current_discovery(lua_State*L){return owner(L)->discovery;}
int vela_discovery_lua_get(lua_State*,VelaDiscovery*,const char*);
int vela_discovery_lua_roots(lua_State*,VelaDiscovery*);
static int get_roots(lua_State*L){return vela_discovery_lua_roots(L,owner(L)->discovery);}
static int get_discovery(lua_State*L){return vela_discovery_lua_get(L,owner(L)->discovery,luaL_checkstring(L,1));}
static int object_kind(lua_State*L){vlc_object_t**object=luaL_checkudata(L,1,"vlc_object");VelaExtension*e=owner(L);const char*kind="other";if(*object==vela_discovery_object(e->discovery))kind="playlist";audio_output_t*held_aout=vela_current_aout(L);if(held_aout){if(*object==(vlc_object_t*)held_aout)kind="aout";vlc_object_release(held_aout);}input_thread_t*input=vela_current_input(L);if(input){if(*object==(vlc_object_t*)input)kind="input";audio_output_t*aout=input_GetAout(input);vout_thread_t*vout=input_GetVout(input);if(aout){if(*object==(vlc_object_t*)aout)kind="aout";vlc_object_release(aout);}if(vout){if(*object==(vlc_object_t*)vout)kind="vout";vlc_object_release(vout);}vlc_object_release(input);}lua_pushstring(L,kind);return 1;}
static int is_playlist(lua_State*L){vlc_object_t**obj=luaL_checkudata(L,1,"vlc_object");lua_pushboolean(L,obj&&*obj==vela_discovery_object(owner(L)->discovery));return 1;}
void vela_media_metadata(libvlc_media_t*media,const char*name,const char*value){input_item_t*item=media->p_input_item;
#define FIELD(x,k) if(!strcmp(name,k)){input_item_SetMeta(item,vlc_meta_##x,value);return;}
FIELD(Title,"title") FIELD(Artist,"artist") FIELD(Genre,"genre") FIELD(Copyright,"copyright") FIELD(Album,"album") FIELD(TrackNumber,"track_number") FIELD(Description,"description") FIELD(Rating,"rating") FIELD(Date,"date") FIELD(Setting,"setting") FIELD(URL,"url") FIELD(Language,"language") FIELD(NowPlaying,"now_playing") FIELD(Publisher,"publisher") FIELD(EncodedBy,"encoded_by") FIELD(ArtworkURL,"artwork_url") FIELD(TrackID,"track_id") FIELD(TrackTotal,"track_total") FIELD(Director,"director") FIELD(Season,"season") FIELD(Episode,"episode") FIELD(ShowName,"show_name") FIELD(Actors,"actors") FIELD(AlbumArtist,"album_artist") FIELD(DiscNumber,"disc_number") FIELD(DiscTotal,"disc_total")
#undef FIELD
vlc_mutex_lock(&item->lock);if(!item->p_meta)item->p_meta=vlc_meta_New();vlc_meta_AddExtra(item->p_meta,name,value);vlc_mutex_unlock(&item->lock);}
void vela_media_duration(libvlc_media_t*media,double seconds){input_item_SetDuration(media->p_input_item,(int64_t)(seconds*1000000));}
void vela_media_copy_item(libvlc_media_t*from,libvlc_media_t*to){input_item_t*a=from->p_input_item,*b=to->p_input_item;input_item_SetDuration(b,input_item_GetDuration(a));for(int i=0;i<VLC_META_TYPE_COUNT;i++){char*s=input_item_GetMeta(a,i);if(s){input_item_SetMeta(b,i,s);free(s);}}vlc_mutex_lock(&a->lock);if(a->p_meta){char**names=vlc_meta_CopyExtraNames(a->p_meta);for(int i=0;names[i];i++){vela_media_metadata(to,names[i],vlc_meta_GetExtra(a->p_meta,names[i]));free(names[i]);}free(names);}vlc_mutex_unlock(&a->lock);}
static int make_item(lua_State*L){VelaExtension*e=owner(L);int id=(int)luaL_checkinteger(L,1);char*current=e->command(e->context,"current","");bool active=current&&atoi(current)==id;free(current);if(active){input_thread_t*input=vela_current_input(L);if(input){vlclua_input_item_get(L,input_GetItem(input));vlc_object_release(input);return 1;}}char arg[32];snprintf(arg,sizeof arg,"%d",id);char*value=e->command(e->context,"playlist:media",arg);libvlc_media_t*media=value?(libvlc_media_t*)(uintptr_t)strtoull(value,NULL,16):NULL;free(value);if(!media){lua_pushnil(L);return 1;}vlclua_input_item_get(L,media->p_input_item);libvlc_media_release(media);return 1;}

static int keepalive(lua_State*L){owner(L)->deadline=now()+15;return 0;}
static void register_core(VelaExtension*e){lua_State*L=e->L;vlclua_set_this(L,(vlc_object_t*)e->instance->p_libvlc_int);vlclua_set_object(L,vlclua_get_playlist_internal,vela_discovery_object(e->discovery));lua_newtable(L);luaopen_config(L);luaopen_input(L);luaopen_object(L);luaopen_stream(L);luaopen_strings(L);luaopen_variables(L);luaopen_xml(L);luaopen_vlcio(L);luaopen_errno(L);luaopen_vlm(L);luaopen_volume(L);luaopen_osd(L);luaopen_video(L);luaopen_sd_intf(L);if(vlclua_fd_init(L,&e->dtable)==VLC_SUCCESS)e->fd_ready=true;lua_setglobal(L,"_vela_vlc");lua_pushcfunction(L,keepalive);lua_setglobal(L,"_vela_keepalive");lua_pushcfunction(L,make_item);lua_setglobal(L,"_vela_item");lua_pushcfunction(L,is_playlist);lua_setglobal(L,"_vela_is_playlist");lua_pushcfunction(L,object_kind);lua_setglobal(L,"_vela_object_kind");lua_pushcfunction(L,get_discovery);lua_setglobal(L,"_vela_sd_get");lua_pushcfunction(L,get_roots);lua_setglobal(L,"_vela_sd_roots");}
static void hook(lua_State*L,lua_Debug*d){(void)d;VelaExtension*e=owner(L);if(atomic_load(&e->cancelled)||now()>e->deadline)luaL_error(L,"Extension execution cancelled or timed out");}
static int native(lua_State*L){VelaExtension*e=owner(L);if(atomic_load(&e->cancelled))return luaL_error(L,"Extension is closed");const char*action=luaL_checkstring(L,1);const char*arg=luaL_optstring(L,2,"");char*result=e->command?e->command(e->context,action,arg):NULL;if(result){lua_pushstring(L,result);free(result);}else lua_pushnil(L);return 1;}
static int tcp_connect(lua_State*L){const char*host=luaL_checkstring(L,1);char port[12];snprintf(port,sizeof port,"%d",(int)luaL_checkinteger(L,2));struct addrinfo hints={0},*list=NULL;hints.ai_socktype=SOCK_STREAM;int fd=-1;if(getaddrinfo(host,port,&hints,&list)==0){for(struct addrinfo*p=list;p;p=p->ai_next){fd=socket(p->ai_family,p->ai_socktype,p->ai_protocol);if(fd<0)continue;struct timeval timeout={3,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof yes);if(connect(fd,p->ai_addr,p->ai_addrlen)==0)break;close(fd);fd=-1;}freeaddrinfo(list);}VelaExtension*e=owner(L);if(fd>=0){if(e->socket_count<128)e->sockets[e->socket_count++]=fd;else{close(fd);fd=-1;}}lua_pushinteger(L,fd);return 1;}
static int tcp_send(lua_State*L){int fd=(int)luaL_checkinteger(L,1);size_t size;const char*text=luaL_checklstring(L,2,&size);if(!valid_socket(owner(L),fd))return luaL_error(L,"Invalid extension socket");ssize_t n=send(fd,text,size,0);lua_pushinteger(L,n);return 1;}
static int tcp_recv(lua_State*L){int fd=(int)luaL_checkinteger(L,1);size_t size=(size_t)luaL_optinteger(L,2,4096);if(size>1024*1024)return luaL_error(L,"Receive buffer too large");if(!valid_socket(owner(L),fd))return luaL_error(L,"Invalid extension socket");char*b=malloc(size?size:1);if(!b)return luaL_error(L,"Out of memory");ssize_t n=recv(fd,b,size,0);if(n>0)lua_pushlstring(L,b,(size_t)n);else lua_pushnil(L);free(b);return 1;}
static int tcp_close(lua_State*L){int fd=(int)luaL_checkinteger(L,1);VelaExtension*e=owner(L);for(int i=0;i<e->socket_count;i++){if(e->sockets[i]==fd){close(fd);e->sockets[i]=e->sockets[--e->socket_count];break;}}return 0;}
static int tcp_poll(lua_State*L){luaL_checktype(L,1,LUA_TTABLE);struct pollfd fds[64];int count=0;lua_pushnil(L);while(lua_next(L,1)&&count<64){fds[count].fd=(int)lua_tointeger(L,-2);fds[count].events=(short)lua_tointeger(L,-1);fds[count].revents=0;count++;lua_pop(L,1);}int timeout=(int)luaL_optinteger(L,2,1000000)/1000;if(timeout<0||timeout>3000)timeout=3000;int ready=poll(fds,count,timeout);for(int i=0;i<count;i++){lua_pushinteger(L,fds[i].revents);lua_rawseti(L,1,fds[i].fd);}lua_pushinteger(L,ready);return 1;}
static int vela_lua_mdate(lua_State*L){lua_pushnumber(L,now()*1e6);return 1;}
static int vela_lua_mwait(lua_State*L){double until=luaL_checknumber(L,1)/1e6;VelaExtension*e=owner(L);while(now()<until){if(atomic_load(&e->cancelled)||now()>e->deadline)return luaL_error(L,"Extension wait cancelled");usleep(10000);}return 0;}
static void error_set(VelaExtension*e){free(e->error);const char*message=lua_tostring(e->L,-1);e->error=strdup(message?message:"Extension error");lua_pop(e->L,1);}
static void*watch(void*context){VelaExtension*e=context;while(!atomic_load(&e->watch_stop)){if(atomic_load(&e->active)&&now()>e->deadline){atomic_store(&e->cancelled,1);if(e->fd_ready)vlclua_fd_interrupt(&e->dtable);}usleep(50000);}return NULL;}
static int protected(VelaExtension*e,int args,int results){e->deadline=now()+15;atomic_store(&e->active,1);int result=lua_pcall(e->L,args,results,0);atomic_store(&e->active,0);if(result!=0){error_set(e);return-1;}return 0;}
static char*json_global(VelaExtension*e,const char*name){lua_getglobal(e->L,"_vela_encode");lua_getglobal(e->L,name);if(protected(e,1,1))return NULL;const char*s=lua_tostring(e->L,-1);char*out=s?strdup(s):NULL;lua_pop(e->L,1);return out;}
VelaExtension*vela_extension_new(const char*path,const char*runtime,libvlc_instance_t*instance,libvlc_media_player_t*player,VelaDiscovery*discovery,vela_extension_command fn,void*context){VelaExtension*e=calloc(1,sizeof(*e));if(!e)return NULL;e->L=lua_newstate(allocated,e);if(!e->L){free(e);return NULL;}e->discovery=discovery;vela_discovery_retain(discovery);atomic_fetch_add(&live_extensions,1);e->instance=instance;e->player=player;libvlc_retain(instance);libvlc_media_player_retain(player);e->command=fn;e->context=context;atomic_init(&e->cancelled,0);luaL_openlibs(e->L);lua_getglobal(e->L,"os");lua_pushcfunction(e->L,execute_command);lua_setfield(e->L,-2,"execute");lua_pop(e->L,1);lua_pushlightuserdata(e->L,e);lua_setfield(e->L,LUA_REGISTRYINDEX,"vela.owner");lua_sethook(e->L,hook,LUA_MASKCOUNT,10000);lua_pushcfunction(e->L,native);lua_setglobal(e->L,"_vela_native");lua_pushstring(e->L,runtime);lua_setglobal(e->L,"_vela_runtime");lua_pushcfunction(e->L,tcp_connect);lua_setglobal(e->L,"_tcp_connect");lua_pushcfunction(e->L,tcp_send);lua_setglobal(e->L,"_tcp_send");lua_pushcfunction(e->L,tcp_recv);lua_setglobal(e->L,"_tcp_recv");lua_pushcfunction(e->L,tcp_close);lua_setglobal(e->L,"_tcp_close");lua_pushcfunction(e->L,tcp_poll);lua_setglobal(e->L,"_tcp_poll");lua_pushcfunction(e->L,vela_lua_mdate);lua_setglobal(e->L,"_mdate");lua_pushcfunction(e->L,vela_lua_mwait);lua_setglobal(e->L,"_mwait");lua_pushstring(e->L,path);lua_setglobal(e->L,"_vela_extension_path");register_core(e);atomic_init(&e->active,0);atomic_init(&e->watch_stop,0);e->watch_ready=pthread_create(&e->watchdog,NULL,watch,e)==0;char*boot=NULL;asprintf(&boot,"%s/bootstrap.lua",runtime);if(luaL_loadfile(e->L,boot)!=0){error_set(e);free(boot);return e;}free(boot);if(protected(e,0,0))return e;if(luaL_loadfile(e->L,path)!=0){error_set(e);return e;}if(protected(e,0,0))return e;lua_getglobal(e->L,"descriptor");if(lua_isfunction(e->L,-1)){if(!protected(e,0,1))lua_setglobal(e->L,"_vela_descriptor");}else lua_pop(e->L,1);return e;}
char*vela_extension_call(VelaExtension*e,const char*name){if(!e)return NULL;lua_getglobal(e->L,name);if(!lua_isfunction(e->L,-1)){lua_pop(e->L,1);return vela_extension_snapshot(e);}protected(e,0,0);return vela_extension_snapshot(e);}
char*vela_extension_click(VelaExtension*e,int id){lua_getglobal(e->L,"_vela_click");lua_pushinteger(e->L,id);protected(e,1,0);return vela_extension_snapshot(e);}
char*vela_extension_set(VelaExtension*e,int id,const char*text,int value,int sequence){lua_getglobal(e->L,"_vela_set");lua_pushinteger(e->L,id);lua_pushstring(e->L,text);lua_pushinteger(e->L,value);lua_pushinteger(e->L,sequence);protected(e,4,0);return vela_extension_snapshot(e);}
char*vela_extension_snapshot(VelaExtension*e){return e?json_global(e,"_vela_model"):NULL;}
char*vela_extension_descriptor(VelaExtension*e){return e?json_global(e,"_vela_descriptor"):NULL;}
const char*vela_extension_error(VelaExtension*e){return e?e->error:"Could not allocate extension interpreter";}
void vela_extension_cancel(VelaExtension*e){if(e){atomic_store(&e->cancelled,1);if(e->fd_ready)vlclua_fd_interrupt(&e->dtable);}}
void vela_extension_release(VelaExtension*e){if(!e)return;atomic_store(&e->watch_stop,1);if(e->watch_ready)pthread_join(e->watchdog,NULL);for(int i=0;i<e->socket_count;i++)close(e->sockets[i]);lua_close(e->L);if(e->fd_ready)vlclua_fd_cleanup(&e->dtable);libvlc_media_player_release(e->player);libvlc_release(e->instance);vela_discovery_release(e->discovery);free(e->error);atomic_fetch_sub(&live_extensions,1);free(e);}

char*vela_extension_menu(VelaExtension*e){lua_getglobal(e->L,"_vela_getmenu");if(!lua_isfunction(e->L,-1)){lua_pop(e->L,1);return strdup("{}");}if(protected(e,0,1))return NULL;lua_setglobal(e->L,"_vela_menu");return json_global(e,"_vela_menu");}
char*vela_extension_trigger_menu(VelaExtension*e,int id){lua_getglobal(e->L,"trigger_menu");if(lua_isfunction(e->L,-1)){lua_pushinteger(e->L,id);protected(e,1,0);}else lua_pop(e->L,1);return vela_extension_snapshot(e);}
void vela_extension_finish(VelaExtension*e){if(!e)return;atomic_store(&e->cancelled,0);char*s=vela_extension_call(e,"close");free(s);s=vela_extension_call(e,"deactivate");free(s);atomic_store(&e->cancelled,1);}

void vela_extension_bind(VelaExtension*e,libvlc_instance_t*instance,libvlc_media_player_t*player,VelaDiscovery*discovery){if(!e)return;vela_discovery_retain(discovery);vela_discovery_release(e->discovery);e->discovery=discovery;libvlc_retain(instance);libvlc_media_player_retain(player);libvlc_media_player_release(e->player);libvlc_release(e->instance);e->instance=instance;e->player=player;vlclua_set_this(e->L,(vlc_object_t*)instance->p_libvlc_int);vlclua_set_object(e->L,vlclua_get_playlist_internal,vela_discovery_object(discovery));}
char*vela_extension_call_number(VelaExtension*e,const char*name,double value){lua_getglobal(e->L,name);if(lua_isfunction(e->L,-1)){lua_pushnumber(e->L,value);protected(e,1,0);}else lua_pop(e->L,1);return vela_extension_snapshot(e);}
