import Foundation
import CLibVLC

/// Frontend playlist and service discovery are owned by Vela, while input items
/// and playback are owned by VLC. IDs are monotonic and never follow row indices.
@MainActor final class ExtensionPlaylist {
    unowned let engine:PlayerEngine
    private var ids:[UUID:Int]=[:];private var serial=10
    private var services:[String:OpaquePointer]=[:]
    private var mediaItems:[UUID:OpaquePointer]=[:]
    private var knownItems:[UUID:MediaItem]=[:]
    private var discoveredIDs:[String:UUID]=[:]
    var discovery:OpaquePointer
    init(_ engine:PlayerEngine){self.engine=engine;discovery=vela_discovery_new(engine.instance)!}
    deinit{vela_discovery_release(discovery)}
    func id(_ item:MediaItem)->Int{knownItems[item.id]=item;if let id=ids[item.id]{return id};serial+=1;ids[item.id]=serial;return serial}
    func acquire(_ item:MediaItem)->OpaquePointer?{if let media=mediaItems[item.id]{libvlc_media_retain(media);return media};guard let media=item.url.isFileURL ? libvlc_media_new_path(engine.instance,item.url.path):libvlc_media_new_location(engine.instance,item.url.absoluteString)else{return nil};vela_media_metadata(media,"title",item.displayTitle ?? item.title);for(key,value)in item.extensionMetadata ?? [:]{vela_media_metadata(media,key,value)};if let duration=item.extensionDuration,duration.isFinite{vela_media_duration(media,duration)};mediaItems[item.id]=media;for option in item.options ?? []{libvlc_media_add_option(media,option)};if item.url.isFileURL{libvlc_media_parse_with_options(media,libvlc_media_parse_local,1000)};libvlc_media_retain(media);return media}
    func rebind(){let oldDiscovery=discovery;discovery=vela_discovery_new(engine.instance)!;vela_discovery_release(oldDiscovery);let old=mediaItems;mediaItems=[:];for (uuid,media)in old{if let item=(engine.queue+engine.libraryItems+engine.recent).first(where:{$0.id==uuid}),let replacement=acquire(item){vela_media_copy_item(media,replacement);libvlc_media_release(replacement)};libvlc_media_release(media)};stopServices()}
    private func stopServices(){for service in services.values{libvlc_media_discoverer_stop(service);libvlc_media_discoverer_release(service)};services=[:]}
    func shutdown(){for media in mediaItems.values{libvlc_media_release(media)};mediaItems=[:];stopServices()}
    func handle(_ action:String,_ arg:String)->String?{
        let e=engine
        let args=(arg.data(using:.utf8).flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [Any]) ?? []
        let number=(args.first as? NSNumber)?.intValue ?? -1
        func item(_ n:Int)->MediaItem?{(e.queue+e.libraryItems).first{self.id($0)==n}}
        func row(_ x:MediaItem)->[String:Any]{let cached=mediaItems[x.id];let nativeTitle=cached.flatMap{libvlc_media_get_meta($0,libvlc_meta_Title)};let title=nativeTitle.map{String(cString:$0)} ?? x.title;if let nativeTitle{libvlc_free(nativeTitle)};return ["id":id(x),"name":title,"path":x.url.absoluteString,"duration":x.extensionDuration ?? (x.id==e.currentID ? Double(e.length)/1000 : -1),"flags":[String:Bool](),"nb_played":x.id==e.currentID ? 1:0,"metas":x.extensionMetadata ?? [:]]}
        func root(_ rows:[MediaItem])->[String:Any]{["id":1,"name":"Playlist","flags":[String:Bool](),"children":rows.map(row)]}
        func json(_ value:Any)->String{ExtensionCommands.json(value)}
        switch action{
        case "playlist:media":guard let number=Int(arg),let item=(e.queue+e.libraryItems+e.recent+Array(knownItems.values)).first(where:{id($0)==number}),let media=acquire(item)else{return nil};return String(UInt(bitPattern:media),radix:16)
        case "current":return e.current.map{String(id($0))} ?? "-1"
        case "playlist:add","playlist:enqueue":
            guard let data=arg.data(using:.utf8),let values=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]]else{return "0"}
            let items=values.compactMap{v->MediaItem? in guard let path=v["path"] as? String else{return nil};let url=URL(string:path).flatMap{$0.scheme==nil ? nil:$0} ?? URL(fileURLWithPath:path);var metadata=v["meta"] as? [String:String] ?? [:];let aliases=["tracknum":"track_number","nowplaying":"now_playing","encodedby":"encoded_by","arturl":"artwork_url","trackid":"track_id"];for key in ["title","artist","genre","copyright","album","tracknum","description","rating","date","setting","url","language","nowplaying","publisher","encodedby","arturl","trackid","director","season","episode","show_name","actors"]{if let value=v[key] as? String,!value.isEmpty{metadata[aliases[key] ?? key]=value}};return MediaItem(url:url,displayTitle:v["name"] as? String,options:v["options"] as? [String],extensionMetadata:metadata,extensionDuration:v["duration"] as? Double)}
            e.queue+=items;if action=="playlist:add",let first=items.first{e.start(first)};return String(items.count)
        case "playlist:get":
            if args.first is NSNumber{if number==2{return json(["id":2,"name":"Media Library","children":e.libraryItems.map(row)])};return item(number).map{json(row($0))} ?? (number==1 ? json(root(e.queue)):"{}")}
            let name=(args.first as? String ?? "root").lowercased()
            if ["ml","media library"].contains(name){return json(["id":2,"name":"Media Library","children":e.libraryItems.map(row)])}
            if ["root","normal","playlist"].contains(name){return json(root(e.queue))}
            if let service=services[name],let list=libvlc_media_discoverer_media_list(service){defer{libvlc_media_list_release(list)};libvlc_media_list_lock(list);defer{libvlc_media_list_unlock(list)};var found:[MediaItem]=[];for index in 0..<libvlc_media_list_count(list){if let media=libvlc_media_list_item_at_index(list,index){defer{libvlc_media_release(media)};if let mrl=libvlc_media_get_mrl(media){defer{free(mrl)};if let url=URL(string:String(cString:mrl)){let key=name+"|"+url.absoluteString;let uuid=discoveredIDs[key] ?? UUID();discoveredIDs[key]=uuid;let entry=MediaItem(id:uuid,url:url);knownItems[uuid]=entry;if mediaItems[uuid]==nil{libvlc_media_retain(media);mediaItems[uuid]=media};found.append(entry)}}}};return json(root(found))};return "{}"
        case "playlist:search":return json(root(e.queue.filter{arg.isEmpty || $0.title.localizedCaseInsensitiveContains(arg) || $0.url.absoluteString.localizedCaseInsensitiveContains(arg)}))
        case "playlist:gotoitem","goto":if number>=1000000,let uri=vela_discovery_uri(discovery,Int32(number)){defer{free(uri)};if let url=URL(string:String(cString:uri)){e.enqueue([url]);return "0"}};guard let x=item(number)else{return "-1"};e.playLibraryItem(x);return "0"
        case "playlist:delete":if number>=1000000,let uri=vela_discovery_uri(discovery,Int32(number)){free(uri);vela_discovery_hide(discovery,Int32(number));return "0"};guard let x=item(number)else{return "-1"};if x.id==e.currentID{e.stop();e.currentID=nil};e.queue.removeAll{$0.id==x.id};e.libraryItems.removeAll{$0.id==x.id};e.saveLibrary();return "0"
        case "playlist:move":guard let x=item(number),let target=args.dropFirst().first as? Int else{return "-1"};if target==2{e.queue.removeAll{$0.id==x.id};e.addToLibrary([x]);return "0"};if target==1{e.libraryItems.removeAll{$0.id==x.id};e.saveLibrary();e.queue.removeAll{$0.id==x.id};e.queue.insert(x,at:0);return "0"};guard let t=item(target),t.id != x.id else{return "-1"};e.queue.removeAll{$0.id==x.id};if let pos=e.queue.firstIndex(where:{$0.id==t.id}){e.queue.insert(x,at:pos+1)};return "0"
        case "playlist:skip":if let index=e.queue.firstIndex(where:{$0.id==e.currentID}),!e.queue.isEmpty{let n=((index+number)%e.queue.count+e.queue.count)%e.queue.count;e.start(e.queue[n])};return "0"
        case "playlist:sort":
            let key=args.first as? String ?? "title";let descending=args.dropFirst().first as? Bool ?? false
            guard ["id","title","title nodes first","artist","genre","random","duration","title numeric","album"].contains(key)else{return "-1"}
            if key=="random"{e.queue.shuffle()}else{e.queue.sort{a,b in let less:Bool;if key=="id"{less=id(a)<id(b)}else if key=="duration"{less=(a.extensionDuration ?? -1)<(b.extensionDuration ?? -1)}else{let left=["artist","genre","album"].contains(key) ? a.extensionMetadata?[key] ?? "":a.title;let right=["artist","genre","album"].contains(key) ? b.extensionMetadata?[key] ?? "":b.title;let cmp=left.compare(right,options:key=="title numeric" ? [.numeric,.caseInsensitive]:[.caseInsensitive]);if cmp == .orderedSame{return descending ? id(a)>id(b):id(a)<id(b)};return descending ? cmp == .orderedDescending:cmp == .orderedAscending};return descending ? (key=="id" ? id(a)>id(b):(a.extensionDuration ?? -1)>(b.extensionDuration ?? -1)):less}};return "0"
        case "playlist:repeat","playlist:loop","playlist:random":
            let old=action=="playlist:random" ? e.shuffle : e.repeatMode==(action=="playlist:repeat" ? .one:.all)
            let value=arg=="toggle" ? !old:(["true","on"].contains(arg) ? true:(["false","off"].contains(arg) ? false:old))
            if action=="playlist:random"{e.shuffle=value}else if value{e.repeatMode=action=="playlist:repeat" ? .one:.all}else if old{e.repeatMode = .off};return String(value)
        case "playlist:play":if !e.isPlaying{if e.hasMedia{e.togglePlay()}else if let first=e.queue.first{e.start(first)}};return "0"
        case "playlist:pause":e.togglePlay();return "0"
        case "playlist:stop":e.stop();return "0"
        case "playlist:next":e.next();return "0"
        case "playlist:prev":e.next(backwards:true);return "0"
        case "playlist:clear":e.stop();e.queue=[];e.currentID=nil;return "0"
        case "sd:list":var result:[String:String]=[:];for category in UInt32(0)...UInt32(3){var list:UnsafeMutablePointer<UnsafeMutablePointer<libvlc_media_discoverer_description_t>?>?;let count=libvlc_media_discoverer_list_get(e.instance,libvlc_media_discoverer_category_t(rawValue:category),&list);if count>0,let list{for index in 0..<count{if let d=list[index]?.pointee{result[String(cString:d.psz_name)]=String(cString:d.psz_longname)}};libvlc_media_discoverer_list_release(list,count)}};return json(result)
        case "sd:loaded":return String(services[arg].map{libvlc_media_discoverer_is_running($0) != 0} ?? false)
        case "sd:add":if services[arg] != nil{return "0"};guard let service=libvlc_media_discoverer_new(e.instance,arg)else{return "-1"};guard libvlc_media_discoverer_start(service)==0 else{libvlc_media_discoverer_release(service);return "-1"};services[arg]=service;return "0"
        case "sd:remove":guard let service=services.removeValue(forKey:arg)else{return "-1"};libvlc_media_discoverer_stop(service);libvlc_media_discoverer_release(service);return "0"
        default:return nil
        }
    }
}
