import SwiftUI
import AppKit
import CLibVLC
import Darwin

struct InstalledExtension:Identifiable,Codable{var id=UUID();var name:String;var file:String;var enabled=false;var version=""}
struct ExtensionChoice:Identifiable{let id:Int;let text:String}
struct ExtensionWidget:Identifiable{let id:Int;let kind:String;var text:String;let row:Int;let col:Int;var checked:Bool;var value:Int;let values:[ExtensionChoice];let enabled:Bool;var selected:Set<Int>;var span=1;var rowspan=1;var width=0;var height=0;var animating=false;var spinLoops = -1;var animationToken:Double=0}
struct ExtensionPresentation{var title="Extension";var visible=false;var widgets:[ExtensionWidget]=[];var logs:[String]=[];var menus:[ExtensionChoice]=[];var error:String?;var deactivationRequested=false;var revision=0;var editAck:[String:Int]=[:];var partial=false}

final class ExtensionCommands:@unchecked Sendable{
    weak var engine:PlayerEngine?
    let directory:URL
    var onUpdate:(@Sendable(String)->Void)?
    init(engine:PlayerEngine,directory:URL){self.engine=engine;self.directory=directory}
    func handle(_ action:String,_ arg:String)->String?{
        if action=="dialog:update"{onUpdate?(arg);return nil}
        if action=="stream"{
            guard let url=URL(string:arg)else{return "{\"error\":\"Invalid URL\"}"}
            if url.isFileURL{do{return Self.json(["data":try Data(contentsOf:url).base64EncodedString()])}catch{return Self.json(["error":error.localizedDescription])}}
            guard ["http","https"].contains(url.scheme ?? "")else{return Self.json(["error":"Unsupported stream protocol"])}
            let semaphore=DispatchSemaphore(value:0);let box=ResultBox();var request=URLRequest(url:url);request.timeoutInterval=10
            let task=URLSession.shared.dataTask(with:request){data,_,error in box.value=error.map{Self.json(["error":$0.localizedDescription])} ?? Self.json(["data":(data ?? Data()).base64EncodedString()]);semaphore.signal()};task.resume()
            if semaphore.wait(timeout:.now()+11) == .timedOut{task.cancel();return Self.json(["error":"Network request timed out"])};return box.value
        }
        if action=="stat"{let a=try? FileManager.default.attributesOfItem(atPath:arg);return Self.json(["size":a?[.size] as? Int ?? 0,"type":a?[.type] as? String ?? "","mtime":(a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0])}
        if action=="urlparse"{let u=URLComponents(string:arg);return Self.json(["protocol":u?.scheme ?? "","host":u?.host ?? "","port":u?.port ?? 80,"path":u?.path ?? "","option":u?.query ?? ""])}
        if action=="decodeuri"{return arg.removingPercentEncoding ?? arg}
        if action=="encodeuri"{return arg.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? arg}
        if action=="makeuri"{return URL(string:arg)?.scheme != nil ? arg : URL(fileURLWithPath:arg).absoluteString}
        if action=="makepath"{return URL(string:arg)?.path ?? arg}
        if action=="gettext"{return NSLocalizedString(arg,comment:"")}
        if action=="userdatadir"{return directory.deletingLastPathComponent().path}
        if action=="datadir"{return Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VLC/share").path}
        if action=="cachedir"{let url=directory.deletingLastPathComponent().appendingPathComponent("cache");try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url.path}
        var result:String?
        DispatchQueue.main.sync{MainActor.assumeIsolated{
            guard let e=self.engine,!e.shuttingDown else{return}
            if action=="homedir"{result=e.testing ? e.storageURL.path:FileManager.default.homeDirectoryForCurrentUser.path;return}
            if action.hasPrefix("playlist:") || action.hasPrefix("sd:") || action=="current"{result=e.extensionPlaylist.handle(action,arg);return}
            switch action{
            case "playlistvar:get":result=String(arg=="random" ? e.shuffle : e.repeatMode==(arg=="repeat" ? .one:.all))
            case "var:sync":if let data=arg.data(using:.utf8),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let kind=obj["kind"] as? String,let name=obj["name"] as? String{if kind=="input",name=="rate",let v=obj["value"] as? Double,v.isFinite{e.rate=v;libvlc_media_player_set_rate(e.player,Float(v))};if kind=="vout",name=="fullscreen",let requested=obj["value"] as? Bool,let window=e.videoView.window,window.styleMask.contains(.fullScreen) != requested{window.toggleFullScreen(nil)};if kind=="vout",let v=obj["value"] as? String{if name=="aspect-ratio"{e.aspect=v.isEmpty ? "Default":v};if name=="crop"{e.crop=v.isEmpty ? "None":v}};if kind=="aout",name=="mute",let value=obj["value"] as? Bool{e.muted=value}}
            case "config:sync":if let data=arg.data(using:.utf8),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],obj["name"] as? String=="network-caching",let v=obj["value"] as? Double{e.networkCache=v};_ = vela_save_config(e.instance)
            case "video:is_fullscreen":result=e.videoView.window.map{String($0.styleMask.contains(.fullScreen))}
            case "video:fullscreen":if let window=e.videoView.window{let requested=arg=="true";if window.styleMask.contains(.fullScreen) != requested{window.toggleFullScreen(nil)}}
            case "quit":NSApp.terminate(nil)
            case "uri":result=e.current?.url.absoluteString ?? ""
            case "name":result=e.current?.title ?? ""
            case "current":result=e.currentID == nil ? "-1" : "1"
            case "status":result=e.isPlaying ? "playing" : (e.state==4 ? "paused" : "stopped")
            case "get:time":result=String(e.time*1000)
            case "get:length":result=String(e.length*1000)
            case "get:position":result=String(e.length>0 ? Double(e.time)/Double(e.length):0)
            case "get:volume":result=String(e.volume)
            case "get:rate":result=String(e.rate)
            case "get:state":result=String(e.state)
            case "set:time":if let v=Double(arg),v.isFinite{e.seek(Int64(max(0,min(v/1000,Double(Int64.max)/2))))}
            case "set:position":if let v=Double(arg),v.isFinite{e.seek(Int64(max(0,min(1,v))*Double(e.length)))}
            case "set:volume":if let v=Double(arg){e.setVolume(v)}
            case "set:rate":if let v=Double(arg){e.setRate(v)}
            case "volume:delta":if let v=Double(arg){e.setVolume(e.volume+v)}
            case "metadata":result=Self.json(e.currentMetadata())
            case "metadata:set":if let data=arg.data(using:.utf8),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:String],let key=obj["key"],let value=obj["value"]{e.setMetadata(key,value:value)}
            case "playlist:play":if !e.isPlaying{e.togglePlay()}
            case "playlist:pause":if e.isPlaying{e.togglePlay()}
            case "playlist:stop":e.stop()
            case "playlist:next":e.next()
            case "playlist:prev":e.next(backwards:true)
            case "playlist:clear":e.stop();e.queue=[];e.currentID=nil
            case "playlist:add","playlist:enqueue":if let data=arg.data(using:.utf8),let items=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]]{e.enqueue(items.compactMap{($0["path"] as? String).flatMap{URL(string:$0)}},play:action=="playlist:add")}
            case "playlist:get":result=Self.json(["children":e.queue.enumerated().map{["id":$0.offset+1,"name":$0.element.title,"path":$0.element.url.absoluteString] as [String:Any]}])
            case "goto":if let id=Int(arg),e.queue.indices.contains(id-1){e.start(e.queue[id-1])}
            case "subtitle":if let url=URL(string:arg){e.addSubtitle(url.scheme == nil ? URL(fileURLWithPath:arg):url)}
            case "config:get":result=UserDefaults.standard.string(forKey:"extension."+arg) ?? ""
            case "config:set":if let data=arg.data(using:.utf8),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let key=obj["key"] as? String{UserDefaults.standard.set(obj["value"],forKey:"extension."+key)}
            default:result=nil
            }
        }}
        return result
    }
    static func json(_ value:Any)->String{guard let data=try? JSONSerialization.data(withJSONObject:value)else{return "{}"};return String(decoding:data,as:UTF8.self)}
    private final class ResultBox:@unchecked Sendable{var value:String?}
}
private let extensionCallback:@convention(c)(UnsafeMutableRawPointer?,UnsafePointer<CChar>?,UnsafePointer<CChar>?)->UnsafeMutablePointer<CChar>?={context,action,arg in
    guard let context,let action else{return nil};let handler=Unmanaged<ExtensionCommands>.fromOpaque(context).takeUnretainedValue()
    return handler.handle(String(cString:action),arg.map{String(cString:$0)} ?? "").flatMap{strdup($0)}
}

private final class LuaSession:@unchecked Sendable{
    let queue=DispatchQueue(label:"Vela.Extension",qos:.userInitiated)
    private let lock=NSLock();private var vm:OpaquePointer?
    private let commands:ExtensionCommands
    private let initialInstance:OpaquePointer
    private let initialPlayer:OpaquePointer
    private let initialDiscovery:OpaquePointer
    private final class Binding:@unchecked Sendable{let instance:OpaquePointer;let player:OpaquePointer;let discovery:OpaquePointer;@MainActor init(_ engine:PlayerEngine){instance=engine.instance;player=engine.player;discovery=engine.extensionPlaylist.discovery;vela_discovery_retain(discovery);libvlc_retain(instance);libvlc_media_player_retain(player)};deinit{vela_discovery_release(discovery);libvlc_media_player_release(player);libvlc_release(instance)}}
    private var disposed=false
    private var capabilities:Set<String>=[]
    @MainActor init(engine:PlayerEngine,directory:URL){commands=ExtensionCommands(engine:engine,directory:directory);initialInstance=engine.instance;initialPlayer=engine.player;initialDiscovery=engine.extensionPlaylist.discovery;vela_discovery_retain(initialDiscovery);libvlc_retain(initialInstance);libvlc_media_player_retain(initialPlayer)}
    deinit{vela_discovery_release(initialDiscovery);libvlc_media_player_release(initialPlayer);libvlc_release(initialInstance)}
    func open(_ path:URL,completion:@escaping @Sendable(ExtensionPresentation,[String:Any])->Void){queue.async{
        let runtime=Bundle.main.resourceURL!.appendingPathComponent("ExtensionRuntime").path
        let value=vela_extension_new(path.path,runtime,self.initialInstance,self.initialPlayer,self.initialDiscovery,extensionCallback,Unmanaged.passUnretained(self.commands).toOpaque())
        self.lock.lock();self.vm=value;self.lock.unlock()
        guard let value else{completion(ExtensionPresentation(error:"Could not create the Lua interpreter"),[:]);return}
        self.commands.onUpdate={json in guard let data=json.data(using:.utf8),let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any]else{return};completion(self.presentationObject(obj,error:nil,menus:[],partial:true),[:])}
        let descriptor=self.consume(vela_extension_descriptor(value))
        self.capabilities=Set(descriptor["capabilities"] as? [String] ?? [])
        if vela_extension_error(value)==nil{_ = self.consume(vela_extension_call(value,self.capabilities.contains("trigger") ? "trigger":"activate"))}
        completion(self.presentation(value),descriptor)
    }}
    func call(_ function:String,value:Double?=nil,completion:@escaping @Sendable(ExtensionPresentation)->Void){queue.async{guard let vm=self.vm,!self.disposed else{return};let capability=["input_changed":"input-listener","playing_changed":"playing-listener","meta_changed":"meta-listener"][function];if let capability,!self.capabilities.contains(capability){return};_ = self.consume(value.map{vela_extension_call_number(vm,function,$0)} ?? vela_extension_call(vm,function));completion(self.presentation(vm))}}
    func widget(_ id:Int,text:String,value:Int,click:Bool=false,sequence:Int=0,completion:@escaping @Sendable(ExtensionPresentation)->Void){queue.async{guard let vm=self.vm,!self.disposed else{return};let data=click ? vela_extension_click(vm,Int32(id)):vela_extension_set(vm,Int32(id),text,Int32(value),Int32(sequence));_ = self.consume(data);completion(self.presentation(vm))}}
    func menu(_ id:Int,completion:@escaping @Sendable(ExtensionPresentation)->Void){queue.async{guard let vm=self.vm,!self.disposed else{return};_ = self.consume(vela_extension_trigger_menu(vm,Int32(id)));completion(self.presentation(vm))}}
    @MainActor func rebind(_ engine:PlayerEngine){let binding=Binding(engine);queue.async{if let vm=self.vm,!self.disposed{vela_extension_bind(vm,binding.instance,binding.player,binding.discovery)}}}
    func close(){lock.lock();if let vm{vela_extension_cancel(vm)};lock.unlock();queue.async{
        self.disposed=true;self.commands.onUpdate=nil;self.lock.lock();let value=self.vm;self.vm=nil;self.lock.unlock();if let value{vela_extension_finish(value);vela_extension_release(value)}
    }}
    private func consume(_ p:UnsafeMutablePointer<CChar>?)->[String:Any]{guard let p else{return[:]};defer{free(p)};guard let data=String(cString:p).data(using:.utf8)else{return[:]};return (try? JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]}
    private func presentation(_ vm:OpaquePointer)->ExtensionPresentation{
        let obj=consume(vela_extension_snapshot(vm))
        let menus=consume(vela_extension_menu(vm)).compactMap{key,value -> ExtensionChoice? in guard let id=Int(key),let title=value as? String else{return nil};return ExtensionChoice(id:id,text:title)}.sorted{$0.id<$1.id}
        return presentationObject(obj,error:vela_extension_error(vm).map{String(cString:$0)},menus:menus)
    }
    private func presentationObject(_ obj:[String:Any],error:String?,menus:[ExtensionChoice],partial:Bool=false)->ExtensionPresentation{
        let widgets=(obj["widgets"] as? [[String:Any]] ?? []).filter{!($0["deleted"] as? Bool ?? false)}.map{w in ExtensionWidget(id:w["id"] as? Int ?? 0,kind:w["kind"] as? String ?? "label",text:w["text"] as? String ?? "",row:max(1,min(10000,w["row"] as? Int ?? 1)),col:max(1,min(512,w["col"] as? Int ?? 1)),checked:w["checked"] as? Bool ?? false,value:w["value"] as? Int ?? 0,values:(w["values"] as? [[String:Any]] ?? []).map{ExtensionChoice(id:$0["id"] as? Int ?? 0,text:$0["text"] as? String ?? "")},enabled:w["enabled"] as? Bool ?? true,selected:Set((w["selection"] as? [String:Bool] ?? [:]).filter{$0.value}.keys.compactMap{Int($0)}),span:max(1,min(512,w["span"] as? Int ?? 1)),rowspan:max(1,min(10000,w["rowspan"] as? Int ?? 1)),width:max(0,min(16384,w["width"] as? Int ?? 0)),height:max(0,min(16384,w["height"] as? Int ?? 0)),animating:w["animating"] as? Bool ?? false,spinLoops:w["spinLoops"] as? Int ?? -1,animationToken:w["animationToken"] as? Double ?? 0)}
        return ExtensionPresentation(title:obj["title"] as? String ?? "Extension",visible:obj["visible"] as? Bool ?? false,widgets:widgets,logs:obj["logs"] as? [String] ?? [],menus:menus,error:error,deactivationRequested:obj["deactivationRequested"] as? Bool ?? false,revision:obj["revision"] as? Int ?? 0,editAck:obj["editAck"] as? [String:Int] ?? [:],partial:partial)
    }
}

@MainActor final class ExtensionManager:NSObject,ObservableObject,NSWindowDelegate{
    @Published var installed:[InstalledExtension]=[]
    @Published var presentations:[UUID:ExtensionPresentation]=[:]
    @Published var error:String?
    @Published var busy:Set<UUID>=[]
    private weak var engine:PlayerEngine?
    private let directory:URL
    private var sessions:[UUID:LuaSession]=[:]
    private var windows:[UUID:NSWindow]=[:]
    private var drafts:[UUID:[Int:(sequence:Int,widget:ExtensionWidget)]]=[:]
    private var dropdownReaders:[UUID:[Int:()->Int?]]=[:]
    private var sequence=0
    init(engine:PlayerEngine){self.engine=engine;directory=engine.storageURL.appendingPathComponent("extensions");super.init();try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);if let data=try? Data(contentsOf:directory.appendingPathComponent("registry.json")){installed=(try? JSONDecoder().decode([InstalledExtension].self,from:data)) ?? []};for i in installed.indices{installed[i].enabled=false}}
    func install(_ url:URL) throws -> UUID{
        let folderURL=(try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true
        guard folderURL || ["lua","luac","vle","zip"].contains(url.pathExtension.lowercased())else{throw NSError(domain:"Extensions",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose a Lua script, VLE package, or a folder containing script.lua."])}
        var item=InstalledExtension(name:url.deletingPathExtension().lastPathComponent,file:"")
        let folder=directory.appendingPathComponent(item.id.uuidString)
        do{
            if folderURL{try FileManager.default.copyItem(at:url,to:folder)}else{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)}
            if ["vle","zip"].contains(url.pathExtension.lowercased()) && !folderURL{
                if let failure=vela_extension_unpack(url.path,folder.path){let message=String(cString:failure);free(failure);throw NSError(domain:"Extensions",code:2,userInfo:[NSLocalizedDescriptionKey:message])}
            }else if !folderURL{try FileManager.default.copyItem(at:url,to:folder.appendingPathComponent(url.lastPathComponent))}
            let script=folderURL || ["vle","zip"].contains(url.pathExtension.lowercased()) ? "script.lua":url.lastPathComponent
            guard FileManager.default.fileExists(atPath:folder.appendingPathComponent(script).path)else{throw NSError(domain:"Extensions",code:3,userInfo:[NSLocalizedDescriptionKey:"The package must contain script.lua at its root."])}
            item.file=item.id.uuidString+"/"+script;installed.append(item);save();return item.id
        }catch{try? FileManager.default.removeItem(at:folder);throw error}
    }
    func chooseInstall(){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.allowsMultipleSelection=true;if panel.runModal() == .OK{for url in panel.urls{do{_ = try install(url)}catch{self.error=error.localizedDescription}}}}

    func activate(_ id:UUID,showWindow:Bool=true){guard let item=installed.first(where:{$0.id==id}),let engine,sessions[id]==nil else{return};let session=LuaSession(engine:engine,directory:directory);sessions[id]=session;busy.insert(id)
        session.open(directory.appendingPathComponent(item.file)){[weak self] result,descriptor in Task{@MainActor in guard let self,self.sessions[id] != nil else{return};self.busy.remove(id);if result.deactivationRequested{self.deactivate(id);return};self.accept(result,id:id)
            if let index=self.installed.firstIndex(where:{$0.id==id}){self.installed[index].enabled=result.error==nil;if let title=descriptor["title"] as? String{self.installed[index].name=title};if let version=descriptor["version"] as? String{self.installed[index].version=version};self.save()}
            if result.error != nil{self.error=result.error}else if showWindow && result.visible{self.show(id)}
        }}
    }
    func show(_ id:UUID){if let window=windows[id]{window.makeKeyAndOrderFront(nil);return};let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:500),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.delegate=self;window.title=presentations[id]?.title ?? "Vela Extension";window.isReleasedWhenClosed=false;window.minSize=NSSize(width:420,height:300);window.contentView=NSHostingView(rootView:ExtensionDialog(manager:self,id:id));windows[id]=window;window.center();window.makeKeyAndOrderFront(nil)}
    func windowWillClose(_ notification:Notification){guard let window=notification.object as? NSWindow,let id=windows.first(where:{$0.value===window})?.key else{return};deactivate(id)}
    func installExample(){do{let id=try install(Bundle.main.resourceURL!.appendingPathComponent("ExtensionRuntime/examples/media-tools.lua"));activate(id)}catch{self.error=error.localizedDescription}}
    func deactivate(_ id:UUID){sessions.removeValue(forKey:id)?.close();windows.removeValue(forKey:id)?.close();presentations.removeValue(forKey:id);drafts.removeValue(forKey:id);dropdownReaders.removeValue(forKey:id);if let i=installed.firstIndex(where:{$0.id==id}){installed[i].enabled=false};busy.remove(id);save()}
    func remove(_ id:UUID){deactivate(id);if let item=installed.first(where:{$0.id==id}){do{_ = try FileManager.default.trashItem(at:directory.appendingPathComponent(item.id.uuidString),resultingItemURL:nil)}catch{self.error=error.localizedDescription;return}};installed.removeAll{$0.id==id};save()}
    func registerDropdown(_ id:UUID,_ widget:Int,_ control:NSPopUpButton){dropdownReaders[id,default:[:]][widget] = {[weak control] in control?.selectedItem?.tag}}
    private func flushDropdowns(_ id:UUID){for w in presentations[id]?.widgets ?? [] where w.kind=="dropdown"{if let value=dropdownReaders[id]?[w.id]?(),value != w.value{widget(id,w,value:value)}}}
    func widget(_ id:UUID,_ widget:ExtensionWidget,text:String="",value:Int=0,click:Bool=false){if click{flushDropdowns(id)};var edit=0;if !click{sequence+=1;edit=sequence;var pending=presentations[id]?.widgets.first(where:{$0.id==widget.id}) ?? widget;switch widget.kind{case "text_input","password":pending.text=text;case "checkbox":pending.checked=value != 0;case "dropdown":pending.value=value;case "list":if text=="true"{pending.selected.insert(value)}else{pending.selected.remove(value)};default:break};drafts[id,default:[:]][widget.id]=(edit,pending);if var model=presentations[id],let index=model.widgets.firstIndex(where:{$0.id==widget.id}){model.widgets[index]=pending;presentations[id]=model}}
        sessions[id]?.widget(widget.id,text:text,value:value,click:click,sequence:edit){[weak self] result in Task{@MainActor in guard let self,self.sessions[id] != nil else{return};if result.deactivationRequested{self.deactivate(id);return};self.accept(result,id:id);if !result.visible{self.windows[id]?.orderOut(nil)}}}}

    private func accept(_ value:ExtensionPresentation,id:UUID){guard value.revision >= (presentations[id]?.revision ?? 0)else{return};var result=value;if result.partial{result.menus=presentations[id]?.menus ?? []};for(widget,draft)in drafts[id] ?? [:]{if (result.editAck[String(widget)] ?? 0)>=draft.sequence{drafts[id]?.removeValue(forKey:widget)}else if let index=result.widgets.firstIndex(where:{$0.id==widget}){switch draft.widget.kind{case "text_input","password":result.widgets[index].text=draft.widget.text;case "checkbox":result.widgets[index].checked=draft.widget.checked;case "dropdown":result.widgets[index].value=draft.widget.value;case "list":result.widgets[index].selected=draft.widget.selected;default:break}}};presentations[id]=result;windows[id]?.title=result.title}

    func menu(_ id:UUID,_ choice:Int){flushDropdowns(id);sessions[id]?.menu(choice){[weak self] result in Task{@MainActor in guard let self,self.sessions[id] != nil else{return};if result.deactivationRequested{self.deactivate(id);return};self.accept(result,id:id);if result.visible{self.show(id)}}}}
    func rebind(){guard let engine else{return};engine.extensionPlaylist.rebind();for session in sessions.values{session.rebind(engine)}}
    func notify(_ callback:String,value:Double?=nil){for(id,session)in sessions{session.call(callback,value:value){[weak self] result in Task{@MainActor in guard let self,self.sessions[id] != nil else{return};if result.deactivationRequested{self.deactivate(id);return};self.accept(result,id:id)}}}}
    func shutdown(){for session in sessions.values{session.close()};for window in Array(windows.values){window.close()};sessions=[:];windows=[:]}
    private func save(){do{try JSONEncoder().encode(installed).write(to:directory.appendingPathComponent("registry.json"),options:.atomic)}catch{self.error=error.localizedDescription}}
}
@MainActor struct ExtensionsView:View{
    @ObservedObject var manager:ExtensionManager
    @Environment(\.dismiss)private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:20){HStack{Text("Extensions").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)};Text("Install Lua extensions and run them in native Vela windows. Extensions can access files and network services when activated.").foregroundStyle(.secondary)
        List(manager.installed){item in HStack{VStack(alignment:.leading){Text(item.name);Text(item.version).font(.caption).foregroundStyle(.secondary)};Spacer();if manager.busy.contains(item.id){ProgressView().controlSize(.small)};Button(item.enabled ? "Open" : "Activate"){if item.enabled{manager.show(item.id)}else{manager.activate(item.id)}};if item.enabled{Button("Deactivate"){manager.deactivate(item.id)}};Button("Remove"){manager.remove(item.id)}}}
        if let error=manager.error{Text(error).foregroundStyle(.red)}
        HStack{Button("Install Extension…"){manager.chooseInstall()};Button("Add Media Tools"){manager.installExample()};Spacer();Button("Done"){dismiss()}}
    }.padding(24).frame(width:760,height:500).tint(Design.accent)}
}
@MainActor private struct ExtensionDialog:View{
    @ObservedObject var manager:ExtensionManager;let id:UUID
    private var model:ExtensionPresentation{manager.presentations[id] ?? ExtensionPresentation()}
    var body:some View{VStack(alignment:.leading,spacing:16){HStack{Text(model.title).font(.title2);Spacer();if !model.menus.isEmpty{Menu("Actions"){ForEach(model.menus){choice in Button(choice.text){manager.menu(id,choice.id)}}}}};if let error=model.error{Text(error).foregroundStyle(.red)};ScrollView([.horizontal,.vertical]){ExtensionGrid{ForEach(model.widgets){widget in control(widget).frame(minWidth:widget.width>0 ? CGFloat(widget.width):nil,minHeight:widget.height>0 ? CGFloat(widget.height):nil).disabled(!widget.enabled).layoutValue(key:ExtensionPlacement.self,value:widget)}}};if !model.logs.isEmpty{DisclosureGroup("Extension Log"){ScrollView{Text(model.logs.joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled)}.frame(maxHeight:100)}}}.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).tint(Design.accent)}
    @ViewBuilder private func control(_ w:ExtensionWidget)->some View{
        switch w.kind{
        // Allow AppKit menu tracking to commit its selection before reading controls.
        case "button":Button(w.text){DispatchQueue.main.asyncAfter(deadline:.now()+0.15){manager.widget(id,w,click:true)}}.buttonStyle(.bordered)
        case "text_input","password":ExtensionTextInput(widget:w){manager.widget(id,w,text:$0)}
        case "spinner":ExtensionSpinner(widget:w)
        case "html":ExtensionHTML(text:w.text).frame(minHeight:CGFloat(max(80,w.height)))
        case "checkbox":Toggle(w.text,isOn:Binding(get:{w.checked},set:{manager.widget(id,w,value:$0 ? 1:0)}))
        case "dropdown":ExtensionPopup(widget:w,register:{manager.registerDropdown(id,w.id,$0)}){manager.widget(id,w,value:$0)}
        case "list":ScrollView{LazyVStack(alignment:.leading){ForEach(w.values){v in Toggle(v.text,isOn:Binding(get:{w.selected.contains(v.id)},set:{manager.widget(id,w,text:$0 ? "true":"false",value:v.id)})).toggleStyle(.checkbox)}}}.frame(height:CGFloat(w.height>0 ? w.height:180))
        case "image":if let image=NSImage(contentsOfFile:URL(string:w.text).flatMap{$0.isFileURL ? $0.path:nil} ?? w.text){Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:CGFloat(w.width>0 ? w.width:200),maxHeight:CGFloat(w.height>0 ? w.height:180))}else{Text("Image unavailable").foregroundStyle(.secondary)}
        default:Text(w.text.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&")).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
