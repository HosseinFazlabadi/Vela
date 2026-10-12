#include <stdlib.h>
#include "vlc/vlc.h"
#include "DiscoveryBridge.h"
typedef struct VelaExtension VelaExtension;
typedef char *(*vela_extension_command)(void *context,const char *command,const char *argument);
VelaExtension *vela_extension_new(const char *path,const char *runtime,libvlc_instance_t *instance,libvlc_media_player_t *player,VelaDiscovery *discovery,vela_extension_command command,void *context);
char *vela_extension_call(VelaExtension *extension,const char *function);
char *vela_extension_click(VelaExtension *extension,int identifier);
char *vela_extension_set(VelaExtension *extension,int identifier,const char *text,int value,int sequence);
char *vela_extension_snapshot(VelaExtension *extension);
char *vela_extension_descriptor(VelaExtension *extension);
const char *vela_extension_error(VelaExtension *extension);
void vela_extension_cancel(VelaExtension *extension);
int vela_extension_live_count(void);
void vela_extension_release(VelaExtension *extension);

char *vela_extension_menu(VelaExtension *extension);
char *vela_extension_trigger_menu(VelaExtension *extension,int identifier);
void vela_extension_finish(VelaExtension *extension);

void vela_extension_bind(VelaExtension*,libvlc_instance_t*,libvlc_media_player_t*,VelaDiscovery*);
char *vela_extension_call_number(VelaExtension*,const char*,double);

char *vela_extension_unpack(const char *input,const char *destination);

void vela_media_metadata(libvlc_media_t*,const char*,const char*);
void vela_media_duration(libvlc_media_t*,double);
void vela_media_copy_item(libvlc_media_t*,libvlc_media_t*);

int vela_player_input_state(libvlc_media_player_t*);

int vela_save_config(libvlc_instance_t*);
