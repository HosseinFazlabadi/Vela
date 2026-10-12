#ifndef VELA_DISCOVERY_BRIDGE_H
#define VELA_DISCOVERY_BRIDGE_H
#include "vlc/vlc.h"
typedef struct VelaDiscovery VelaDiscovery;
VelaDiscovery*vela_discovery_new(libvlc_instance_t*);
void vela_discovery_retain(VelaDiscovery*);
void vela_discovery_release(VelaDiscovery*);
void*vela_discovery_object(VelaDiscovery*);
char*vela_discovery_uri(VelaDiscovery*,int);
void vela_discovery_hide(VelaDiscovery*,int);

#endif
