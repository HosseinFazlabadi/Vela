import SwiftUI
import AppKit
import CLibVLC

enum Panel: String { case queue, bookmarks, chapters, audio, video, subtitles, playback, videoSettings, audioSettings, subtitleSettings }
enum LibraryTab: String, CaseIterable { case library = "Library", recent = "Recent", queue = "Queue", playlists = "Playlists" }

@MainActor struct PlayerView: View {
    @ObservedObject var engine: PlayerEngine
    @State private var sidebar = false
    @State private var libraryTab: LibraryTab = .queue
    @State private var panel: Panel?
    @State private var settings = false
    @State private var network = false
    @State private var convert = false
    @State private var capture = false
    @State private var disc = false
    @State private var discControls = false
    @State private var casting = false
    @State private var extensions = false
    @State private var streaming = false
    @State private var mediaInfo = false
    @State private var savePlaylist = false
    @State private var playlistName = ""
    @State private var search = ""
    @State private var hideControls = false
    @State private var showStats = false
    @State private var remainingTime = false
    @State private var jump = false
    @State private var jumpTime = "00:00:00"
    var body: some View {
        VStack(spacing:0) {
            if !hideControls { if engine.compactMode {compactTopbar}else{topbar} }
            HStack(spacing:0) {
                if sidebar && !engine.compactMode { library.frame(width:377).transition(.move(edge:.leading)) }
                ZStack(alignment:.topTrailing) {
                    if engine.hasMedia {
                        VideoSurface(engine:engine).background(.black).clipShape(RoundedRectangle(cornerRadius:12))
                    }else{
                        emptyState.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black).clipShape(RoundedRectangle(cornerRadius:12))
                    }
                    if showStats { Text(engine.statistics.isEmpty ? "No playback statistics" : engine.statistics).font(Design.font(12)).padding(16).background(Design.panel.opacity(0.9)).padding(20) }
                    if let panel,!engine.compactMode { Inspector(engine:engine,panel:panel,onPanel:{self.panel=$0},openSettings:{settings=true},showStats:$showStats).frame(width:400).padding(20) }
                    if !engine.conversionProgress.isEmpty {
                        HStack { Text(engine.conversionProgress); if engine.recording || !engine.streamingURL.isEmpty || engine.conversionProgress.hasPrefix("Converting") { Button("Stop") {engine.stopOutput()} } }
                            .font(Design.font(12)).padding(12).background(Design.panel,in:RoundedRectangle(cornerRadius:6)).frame(maxHeight:.infinity,alignment:.bottom).padding(20)
                    }
                }.padding(hideControls ? 0 : 10)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            if !hideControls {if engine.compactMode {compactControls}else{controlbar}}
        }
        .background(Design.background).foregroundStyle(Design.foreground).font(Design.font())
        .preferredColorScheme(.dark)
        .tint(Design.accent)
        .sheet(isPresented:$settings) { SettingsView(engine:engine) }
        .sheet(isPresented:$network) { NetworkView(engine:engine) }
        .sheet(isPresented:$convert) { ConvertView(engine:engine) }
        .sheet(isPresented:$capture){CaptureView(engine:engine)}
        .sheet(isPresented:$disc){DiscView(engine:engine)}
        .sheet(isPresented:$discControls){DiscControlsView(engine:engine)}
        .sheet(isPresented:$casting){CastingView(engine:engine)}
        .sheet(isPresented:$streaming){StreamingView(engine:engine)}
        .sheet(isPresented:$extensions){ExtensionsView(manager:engine.extensions)}
        .sheet(isPresented:$mediaInfo){MediaInfoView(engine:engine)}
        .alert("Save Playlist",isPresented:$savePlaylist) {
            TextField("Playlist name",text:$playlistName)
            Button("Save") { engine.savePlaylist(name:playlistName.isEmpty ? "Playlist" : playlistName) }
            Button("Cancel",role:.cancel) {}
        }
        .alert("Jump to Time",isPresented:$jump) {
            TextField("HH:MM:SS",text:$jumpTime)
            Button("Jump") { let fields=jumpTime.split(separator:":",omittingEmptySubsequences:false);let parts=fields.compactMap{Double($0)};if (1...3).contains(parts.count),parts.count==fields.count,parts.allSatisfy({$0.isFinite && $0>=0 && $0<1_000_000}){let milliseconds=parts.reduce(0){$0*60+$1}*1000;if milliseconds<Double(Int64.max){engine.seek(Int64(milliseconds))}} }
            Button("Cancel",role:.cancel) {}
        }
        .alert("Playback",isPresented:Binding(get:{engine.error != nil},set:{if !$0 {engine.error=nil}})) { Button("OK") {engine.error=nil} } message: { Text(engine.error ?? "") }
        .onDrop(of:["public.file-url"],isTargeted:nil) { providers in
            for provider in providers { _ = provider.loadObject(ofClass:URL.self) { url,_ in if let url { Task { @MainActor in if ["srt","ass","ssa","vtt","sub"].contains(url.pathExtension.lowercased()) && engine.hasMedia {engine.addSubtitle(url)} else {engine.enqueue([url])} } } } }; return true
        }
        .onReceive(NotificationCenter.default.publisher(for:.velaCommand)) { n in
            guard let action=n.object as? String else{return}
            switch action {
            case "network":network=true
            case "settings":settings=true
            case "convert":convert=true
            case "queue":panel=panel == .queue ? nil : .queue
            case "hide":hideControls.toggle()
            case "jump":jump=true
            case "record":record()
            case "capture":capture=true
            case "disc":disc=true
            case "discControls":discControls=true
            case "casting":casting=true
            case "streaming":streaming=true
            case "extensions":extensions=true
            case "mediaInfo":mediaInfo=true
            default:break
            }
        }
        .contextMenu {
            Button(engine.isPlaying ? "Pause" : "Play") {engine.togglePlay()}
            Button("Stop") {engine.stop()}
            Button("Next Item") {engine.next()}
            Button("Previous Item") {engine.next(backwards:true)}
            Divider()
            Button("Take Snapshot") {engine.snapshot()}.disabled(!engine.hasMedia)
            Button("Add Subtitle File…") {engine.openSubtitle()}.disabled(!engine.hasMedia)
            Button("Hide / Show UI") {hideControls.toggle()}
            Button("Settings…") {settings=true}
        }
    }
    private var topbar: some View {
        ZStack {
            Text(engine.current?.title ?? "Vela Media Player").font(Design.font(14)).lineLimit(1).frame(maxWidth:500).padding(.horizontal,240)
            HStack(spacing:10) {
                // Native macOS traffic lights occupy the first 76 points.
                Color.clear.frame(width:76)
                Menu {
                    Button("Open File(s)…") {engine.openFiles()}
                    Button("Open Folder…") {engine.openFiles(folder:true)}
                    Button("Open Network Stream…") {network=true}
                    Button("Open Disc…") {disc=true}
                    Button("Open Capture Source…"){capture=true}
                    Button("Stream Media…"){streaming=true}
                    Button("Extensions…"){extensions=true}
                    Button("Disc Controls…"){discControls=true}
                    Divider()
                    Button("Convert / Export…") {convert=true}.disabled(!engine.hasMedia)
                    Button("Export Playlist…") {engine.exportPlaylist()}
                    Button("Settings…") {settings=true}
                    Button("About Vela") {about()}
                    Divider()
                    Button("Mini Player") {NotificationCenter.default.post(name:.velaCommand,object:"mini")}
                    Menu("Cast to Device") {
                        Button("Manage Casting…"){casting=true}
                        Button("This Mac"){engine.cast(to:0)}
                        Button("Scan for Devices…"){engine.scanCastDevices()}
                        ForEach(engine.castDevices){device in Button(device.name){engine.cast(to:device.id)}}
                        if engine.scanningCast && engine.castDevices.isEmpty {Text("Searching the local network…")}
                    }
                } label:{DesignIcon(file:"vela-mark.png")}.menuStyle(.borderlessButton).fixedSize().help("Open media and settings")
                IconButton(file:"d7959.svg",title:"More options") { settings=true }
                IconButton(file:"b130a.svg",title:"Toggle Library",active:sidebar) {withAnimation(.easeInOut(duration:0.15)){sidebar.toggle()}}
                Rectangle().fill(Design.divider).frame(width:1,height:18)
                Button {engine.openFiles(folder:true)} label:{HStack(spacing:4){DesignIcon(file:"cf6e1.svg");Text("Videos").font(Design.font(14))}}.buttonStyle(.plain)
                Spacer()
                IconButton(file:"d41b8.svg",title:"Full Screen") {NSApp.keyWindow?.toggleFullScreen(nil)}
            }.padding(.horizontal,8)
        }.frame(height:40).background(Design.background)
    }
    private var controlbar: some View {
        HStack(spacing:20) {
            HStack(spacing:8) {
                IconButton(file:"1f761.svg",title:"Previous Item") {engine.next(backwards:true)}
                Button {engine.togglePlay()} label:{DesignIcon(file:engine.isPlaying ? "24411.svg" : "4ecaf.svg").frame(width:54,height:28).background(Design.accent,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain).help(engine.isPlaying ? "Pause (Space)" : "Play (Space)").accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                IconButton(file:"617e8.svg",title:"Next Item") {engine.next()}
            }
            HStack(spacing:8) {
                Button {jump=true} label:{Text(PlayerEngine.timestamp(engine.time)).font(Design.font(15)).monospacedDigit().frame(width:76)}.buttonStyle(.plain).help("Jump to Time")
                SeekBar(value:engine.length > 0 ? Double(engine.time)/Double(engine.length) : 0,enabled:engine.seekable) {engine.seek(Int64($0*Double(engine.length)))}
                Button {remainingTime.toggle()} label:{Text((remainingTime ? "−" : "")+PlayerEngine.timestamp(remainingTime ? engine.length-engine.time : engine.length)).font(Design.font(15)).monospacedDigit().frame(width:76)}.buttonStyle(.plain).help("Toggle remaining time")
            }.frame(maxWidth:.infinity)
            VolumeControl(engine:engine)
            HStack(spacing:12) {
                IconButton(file:"432a4.svg",title:"Audio Tracks",active:panel == .audio) {toggle(.audio)}
                IconButton(file:"3ffd5.svg",title:"Subtitle Tracks",active:panel == .subtitles) {toggle(.subtitles)}
                IconButton(file:"e80b5.svg",title:"Playback Settings",active:panel == .playback) {toggle(.playback)}
            }
            IconButton(file:"0eda2.svg",title:"Queue / Bookmarks / Chapters",active:[.queue,.bookmarks,.chapters].contains(panel)) {toggle(.queue)}
        }.padding(.horizontal,20).frame(height:54).background(Design.background).overlay(alignment:.top){Design.divider.frame(height:1)}
    }
    private var emptyState: some View {
        VStack(spacing:20) {
            Image(nsImage:NSImage(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("Assets/vela-mark.png"))!).resizable().scaledToFit().frame(width:88,height:88).accessibilityHidden(true)
            Text("Vela").font(Design.font(36,weight:.medium)).foregroundStyle(Color("DarkFG1"))
            Text("Your media. The VLC engine. A new view.").font(Design.font(15))
            Button("Open File(s)…") {engine.openFiles()}.buttonStyle(VelaButtonStyle(prominent:true))
            Button("Open Network Stream…") {network=true}.buttonStyle(.plain).font(Design.font(13))
            Text("Drop video, audio, or a playlist here").font(Design.font(12)).foregroundStyle(Design.secondary)
        }
    }
    private var compactTopbar: some View {
        HStack {Color.clear.frame(width:76);Text(engine.current?.title ?? "Vela").font(Design.font(12)).lineLimit(1);Spacer();Button {NotificationCenter.default.post(name:.velaCommand,object:"mini")} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.buttonStyle(.plain).help("Return to Full Player")}.padding(.horizontal,10).frame(height:36)
    }
    private var compactControls: some View {
        HStack(spacing:12){Button{engine.togglePlay()}label:{Image(systemName:engine.isPlaying ? "pause.fill" : "play.fill")}.buttonStyle(.plain).foregroundStyle(Design.accent);Text(PlayerEngine.timestamp(engine.time)).font(Design.font(11));SeekBar(value:engine.length > 0 ? Double(engine.time)/Double(engine.length) : 0,enabled:engine.seekable){engine.seek(Int64($0*Double(engine.length)))};Button{engine.toggleMute()}label:{Image(systemName:engine.muted ? "speaker.slash" : "speaker.wave.2")}.buttonStyle(.plain)}.padding(.horizontal,16).frame(height:44)
    }
    private var library: some View {
        HStack(spacing:0) {
            VStack(spacing:14) {
                IconButton(file:"b130a.svg",title:"Media Library",active:libraryTab == .library){libraryTab = .library}
                IconButton(file:"27471.svg",title:"Recent",active:libraryTab == .recent){libraryTab = .recent}
                IconButton(file:"b610e.svg",title:"Queue",active:libraryTab == .queue){libraryTab = .queue}
                IconButton(file:"c9326.svg",title:"Network Stream"){network=true}
                IconButton(file:"50e8b.svg",title:"Playlists",active:libraryTab == .playlists){libraryTab = .playlists}
                IconButton(file:"1b0f7.svg",title:"Settings"){settings=true}
                IconButton(file:"bfdda.svg",title:"Open Files"){engine.openFiles()}
                Spacer()
            }.padding(8).frame(width:50).background(Color("DarkBGA4"))
            VStack(alignment:.leading,spacing:16) {
                HStack {Text(libraryTab.rawValue);Spacer();Menu {ForEach(LibraryTab.allCases,id:\.self){tab in Button(tab.rawValue){libraryTab=tab}}} label:{DesignIcon(file:"d7959.svg")}.menuStyle(.borderlessButton).fixedSize()}
                TextField("Search",text:$search).textFieldStyle(.plain).padding(8).background(Design.field,in:RoundedRectangle(cornerRadius:4))
                if libraryTab == .playlists {
                    Button("+  Create playlist") {savePlaylist=true}.buttonStyle(.plain)
                    List {
                        ForEach(engine.playlists.filter {search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)}) {list in
                            Button(list.name) {engine.queue=list.items;if let first=list.items.first{engine.start(first)}}.buttonStyle(.plain)
                                .contextMenu{Button("Delete",role:.destructive){engine.playlists.removeAll{$0.id == list.id};engine.saveLibrary()}}
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                } else {
                    let items=libraryTab == .library ? engine.libraryItems : (libraryTab == .recent ? engine.recent : engine.queue)
                    Text("\(items.count) items").font(Design.font(12)).foregroundStyle(Design.secondary)
                    List {
                        ForEach(items.filter {search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}) {item in
                            Button {if libraryTab == .library{engine.playLibraryItem(item)}else if libraryTab == .recent {engine.enqueue([item.url])} else {engine.start(item)}} label:{HStack{Text(item.id == engine.currentID ? "▶" : "").foregroundStyle(Design.accent).frame(width:16);Text(item.title).lineLimit(1).truncationMode(.middle)}}.buttonStyle(.plain)
                                .contextMenu{Button("Add to Library"){engine.addToLibrary([item])};Button("Remove"){if libraryTab == .library{engine.libraryItems.removeAll{$0.id==item.id};engine.saveLibrary()}else if libraryTab == .recent {engine.recent.removeAll{$0.id == item.id};engine.saveLibrary()}else{engine.remove(item)}}}
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                    HStack {Button("Add Files…"){if libraryTab == .library{engine.chooseLibraryFiles()}else{engine.openFiles()}};Spacer();Button("Save…"){savePlaylist=true}}.buttonStyle(.plain).font(Design.font(12))
                }
            }.padding(20).frame(maxHeight:.infinity).background(Design.panel)
        }
    }
    private func toggle(_ p: Panel) {panel = panel == p ? nil : p}
    private func openDisc() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.message="Choose a DVD disc or VIDEO_TS folder"
        if panel.runModal() == .OK,let url=panel.url {engine.enqueue([URL(string:"dvdnav://"+url.path.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!)!])}
    }
    private func record() {
        if engine.recording {engine.stopOutput();return}
        let panel=NSSavePanel();panel.nameFieldStringValue="Recording.mkv"
        if panel.runModal() == .OK,let url=panel.url {engine.startRecording(to:url)}
    }
    private func about(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Vela",.applicationVersion:"1.0 • libVLC \(engine.engineVersion)",.credits:NSAttributedString(string:"Personal player based on the VLC Redesign Figma community design.\nVLC engine © VideoLAN and contributors.\nThis is an independent app.")])}
}

extension Notification.Name {static let velaCommand=Notification.Name("VelaCommand")}
