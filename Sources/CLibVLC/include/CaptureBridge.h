#include <vlc/vlc.h>
#include <stddef.h>
typedef struct VelaRawSource VelaRawSource;
typedef struct VelaRawToken VelaRawToken;
VelaRawSource *vela_raw_new(unsigned width,unsigned height,double fps);
void vela_raw_hold(VelaRawSource *source);
void vela_raw_release(VelaRawSource *source);
void vela_raw_finish(VelaRawSource *source);
int vela_raw_push(VelaRawSource *source,const void *pixels,size_t stride);
libvlc_media_t *vela_raw_media(libvlc_instance_t *instance,VelaRawSource *source,VelaRawToken **token);
void vela_raw_cancel(VelaRawToken *token);

int vela_raw_enable_audio(VelaRawSource *source);
int vela_raw_push_audio(VelaRawSource *source,const float *samples,size_t frames);
