#include "include/RendererBridge.h"
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

struct VelaRendererBrowser {
    pthread_mutex_t mutex;
    libvlc_renderer_discoverer_t *discoverers[16];
    size_t discoverer_count;
    libvlc_renderer_item_t *items[128];
    size_t count;
};
static void renderer_event(const libvlc_event_t *event,void *context) {
    VelaRendererBrowser *browser=context;
    pthread_mutex_lock(&browser->mutex);
    if(event->type==libvlc_RendererDiscovererItemAdded) {
        libvlc_renderer_item_t *item=event->u.renderer_discoverer_item_added.item;
        int duplicate=0;
        for(size_t i=0;i<browser->count;i++) if(browser->items[i]==item) duplicate=1;
        if(!duplicate && browser->count<128) browser->items[browser->count++]=libvlc_renderer_item_hold(item);
    } else if(event->type==libvlc_RendererDiscovererItemDeleted) {
        libvlc_renderer_item_t *item=event->u.renderer_discoverer_item_deleted.item;
        for(size_t i=0;i<browser->count;i++) if(browser->items[i]==item) {
            libvlc_renderer_item_release(item);
            browser->items[i]=browser->items[--browser->count];
            break;
        }
    }
    pthread_mutex_unlock(&browser->mutex);
}
VelaRendererBrowser *vela_renderer_browser_new(libvlc_instance_t *instance) {
    VelaRendererBrowser *browser=calloc(1,sizeof(*browser));
    if(!browser) return NULL;
    pthread_mutex_init(&browser->mutex,NULL);
    libvlc_rd_description_t **services=NULL;
    size_t count=libvlc_renderer_discoverer_list_get(instance,&services);
    for(size_t i=0;i<count && browser->discoverer_count<16;i++) {
        libvlc_renderer_discoverer_t *d=libvlc_renderer_discoverer_new(instance,services[i]->psz_name);
        if(!d) continue;
        libvlc_event_manager_t *events=libvlc_renderer_discoverer_event_manager(d);
        libvlc_event_attach(events,libvlc_RendererDiscovererItemAdded,renderer_event,browser);
        libvlc_event_attach(events,libvlc_RendererDiscovererItemDeleted,renderer_event,browser);
        if(libvlc_renderer_discoverer_start(d)==0) browser->discoverers[browser->discoverer_count++]=d;
        else {
            libvlc_event_detach(events,libvlc_RendererDiscovererItemAdded,renderer_event,browser);
            libvlc_event_detach(events,libvlc_RendererDiscovererItemDeleted,renderer_event,browser);
            libvlc_renderer_discoverer_release(d);
        }
    }
    if(services) libvlc_renderer_discoverer_list_release(services,count);
    return browser;
}
void vela_renderer_browser_release(VelaRendererBrowser *browser) {
    if(!browser) return;
    for(size_t i=0;i<browser->discoverer_count;i++) {
        libvlc_renderer_discoverer_t *d=browser->discoverers[i];
        libvlc_renderer_discoverer_stop(d);
        libvlc_event_manager_t *events=libvlc_renderer_discoverer_event_manager(d);
        libvlc_event_detach(events,libvlc_RendererDiscovererItemAdded,renderer_event,browser);
        libvlc_event_detach(events,libvlc_RendererDiscovererItemDeleted,renderer_event,browser);
        libvlc_renderer_discoverer_release(d);
    }
    for(size_t i=0;i<browser->count;i++) libvlc_renderer_item_release(browser->items[i]);
    pthread_mutex_destroy(&browser->mutex);free(browser);
}
char *vela_renderer_browser_snapshot(VelaRendererBrowser *browser) {
    if(!browser) return strdup("");
    pthread_mutex_lock(&browser->mutex);
    size_t capacity=1;
    for(size_t i=0;i<browser->count;i++) capacity+=strlen(libvlc_renderer_item_name(browser->items[i]))+strlen(libvlc_renderer_item_type(browser->items[i]))+40;
    char *text=calloc(capacity,1);
    if(text) {
        size_t offset=0;
        for(size_t i=0;i<browser->count;i++) {
            char *name=strdup(libvlc_renderer_item_name(browser->items[i]));
            if(!name) continue;
            for(char *p=name;*p;p++) if(*p=='\n'||*p=='\t') *p=' ';
            offset+=snprintf(text+offset,capacity-offset,"%" PRIu64 "\t%s\t%s\n",(uint64_t)(uintptr_t)browser->items[i],libvlc_renderer_item_type(browser->items[i]),name);
            free(name);
        }
    }
    pthread_mutex_unlock(&browser->mutex);return text;
}
int vela_renderer_browser_select(VelaRendererBrowser *browser,libvlc_media_player_t *player,uint64_t identifier) {
    if(identifier==0) return libvlc_media_player_set_renderer(player,NULL);
    if(!browser) return -1;
    int result=-1;
    pthread_mutex_lock(&browser->mutex);
    for(size_t i=0;i<browser->count;i++) if((uint64_t)(uintptr_t)browser->items[i]==identifier) {result=libvlc_media_player_set_renderer(player,browser->items[i]);break;}
    pthread_mutex_unlock(&browser->mutex);return result;
}
