#include <vlc/vlc.h>
#include <stdint.h>
typedef struct VelaRendererBrowser VelaRendererBrowser;
VelaRendererBrowser *vela_renderer_browser_new(libvlc_instance_t *instance);
void vela_renderer_browser_release(VelaRendererBrowser *browser);
char *vela_renderer_browser_snapshot(VelaRendererBrowser *browser);
int vela_renderer_browser_select(VelaRendererBrowser *browser,libvlc_media_player_t *player,uint64_t identifier);
