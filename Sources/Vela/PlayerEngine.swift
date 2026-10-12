import AppKit
import SwiftUI
import CLibVLC
import MediaPlayer

struct MediaItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: URL
    var displayTitle: String? = nil
    var options: [String]? = nil
    var extensionMetadata: [String:String]? = nil
    var extensionDuration: Double? = nil
    var title: String { displayTitle ?? (url.isFileURL ? url.lastPathComponent : url.absoluteString) }
}
struct Track: Identifiable, Equatable { let id: Int32; let name: String }
struct CastDevice: Identifiable, Equatable {let id: UInt64;let name:String;let type:String}
struct Chapter: Identifiable, Equatable { let id: Int32; let name: String; let time: Int64 }
struct DiscTitle:Identifiable,Equatable{let id:Int32;let name:String;let duration:Int64;let menu:Bool}
struct Bookmark: Identifiable, Codable { var id = UUID(); let media: URL; let name: String; let time: Int64 }
struct SavedPlaylist: Identifiable, Codable { var id = UUID(); var name: String; var items: [MediaItem] }
enum RepeatMode: String, CaseIterable { case off = "Off", all = "All", one = "One" }

@MainActor final class PlayerEngine: ObservableObject {
    private(set) var instance: OpaquePointer
    private(set) var player: OpaquePointer
    let videoView = NSView()
    @Published var queue: [MediaItem] = []
    @Published var currentID: UUID?
    @Published var state: Int32 = 0
    @Published var time: Int64 = 0
    @Published var length: Int64 = 0
    @Published var seekable = false
    @Published var volume: Double = UserDefaults.standard.object(forKey:"volume") as? Double ?? 100
    @Published var muted = false
    @Published var rate: Double = 1
    @Published var subtitleTracks: [Track] = []
    @Published var audioTracks: [Track] = []
    @Published var videoTracks: [Track] = []
    @Published var chapters: [Chapter] = []
    @Published var audioTrack: Int32 = -1
    @Published var subtitleTrack: Int32 = -1
    @Published var videoTrack: Int32 = -1
    @Published var chapter: Int32 = -1
    @Published var devices: [Track] = []
    @Published var outputDevices: [(id: String, name: String)] = []
    @Published var error: String?
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var bookmarks: [Bookmark] = []
    @Published var playlists: [SavedPlaylist] = []
    @Published var recent: [MediaItem] = []
    @Published var libraryItems:[MediaItem]=[]
    @Published var sleepUntil: Date?
    @Published var statistics = ""
    @Published var audioDelay: Double = 0
    @Published var subtitleDelay: Double = 0
    @Published var aspect = "Default"
    @Published var crop = "None"
    @Published var brightness: Double = 1
    @Published var contrast: Double = 1
    @Published var saturation: Double = 1
    @Published var gamma: Double = 1
    @Published var eqPreset = "Disabled"
    @Published var eqGains = Array(repeating: 0.0, count: 10)
    @Published var subtitleFont = UserDefaults.standard.string(forKey:"subtitleFont") ?? "Helvetica Neue"
    @Published var subtitleSize = UserDefaults.standard.string(forKey:"subtitleSize") ?? "Normal"
    @Published var conversionProgress = ""
    @Published var streamingURL = ""
    @Published var recording = false
    @Published var externalSubtitles: [URL] = []
    @Published var keepHistory: Bool = UserDefaults.standard.object(forKey: "keepHistory") as? Bool ?? true
    @Published var rememberPosition: Bool = UserDefaults.standard.object(forKey: "rememberPosition") as? Bool ?? true
    @Published var advancedOptions: String = UserDefaults.standard.string(forKey: "advancedOptions") ?? ""
    @Published var networkCache: Double = UserDefaults.standard.object(forKey: "networkCache") as? Double ?? 1000
    @Published var castDevices: [CastDevice] = []
    @Published var scanningCast = false
    @Published var selectedCast: UInt64 = 0
    @Published var compactMode = false
    @Published var discTitles:[DiscTitle]=[]
    @Published var discTitle:Int32 = -1
    let captureService=CaptureService()
    lazy var extensions=ExtensionManager(engine:self)
    lazy var extensionPlaylist=ExtensionPlaylist(self)
    private var extensionLastMetadata:[String:String]=[:]
    private var rawSource:OpaquePointer?
    private var rawToken:OpaquePointer?
    private var outputRawToken:OpaquePointer?
    private var exportJob:MediaExportJob?
    private var timer: Timer?
    private var media: OpaquePointer?
    private var outputPlayer: OpaquePointer?
    private var outputMedia: OpaquePointer?
    private var outputInstance: OpaquePointer?
    private var previousState: Int32 = 0
    private var ticks = 0
    private var pendingResume: Int64?
    private var positions: [String: Int64] = [:]
    private var autoAdvance = true
    private var rendererBrowser: OpaquePointer?
    private var remoteTargets:[(MPRemoteCommand,Any)] = []
    private(set) var testing=false
    private(set) var shuttingDown=false
    let storageURL: URL
    var current: MediaItem? { queue.first { $0.id == currentID } }
    var isPlaying: Bool { state == 3 }
    var hasMedia: Bool { current != nil }
    var isDisc:Bool{["dvd","dvdnav","bluray","cdda","vcd"].contains(current?.url.scheme ?? "")}
    var engineVersion: String { String(cString: libvlc_get_version()) }
    var equalizerPresets: [String] {
        (0..<libvlc_audio_equalizer_get_preset_count()).map { String(cString: libvlc_audio_equalizer_get_preset_name($0)) }
    }

    init(testing: Bool = false) {
        self.testing=testing
        storageURL = testing ? URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("Vela-tests-"+UUID().uuidString) : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vela")
        try? FileManager.default.createDirectory(at:storageURL,withIntermediateDirectories:true)
        let runtime = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VLC")
        setenv("VLC_PLUGIN_PATH", runtime.appendingPathComponent("plugins").path, 1)
        setenv("VLC_DATA_PATH", runtime.appendingPathComponent("share").path, 1)
        let initialFont=UserDefaults.standard.string(forKey:"subtitleFont") ?? "Helvetica Neue"
        let initialSize=UserDefaults.standard.string(forKey:"subtitleSize") ?? "Normal"
        let options = ["--no-ignore-config","--config=\(storageURL.appendingPathComponent("vlcrc").path)","--no-video-title-show",  "--freetype-font=\(initialFont)", "--freetype-rel-fontsize=\(Self.subtitleSizeValue(initialSize))"]
        let pointers = options.map { strdup($0)! }
        var argv = pointers.map { UnsafePointer<CChar>($0) as UnsafePointer<CChar>? }
        let result = argv.withUnsafeMutableBufferPointer { libvlc_new(Int32($0.count), $0.baseAddress) }
        pointers.forEach { free($0) }
        guard let result, let mp = libvlc_media_player_new(result) else { fatalError("Could not initialize bundled libVLC") }
        instance = result; player = mp
        libvlc_audio_set_volume(player,Int32(volume));libvlc_audio_set_mute(player,muted ? 1:0)
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        libvlc_media_player_set_nsobject(player, Unmanaged.passUnretained(videoView).toOpaque())
        if !testing { loadLibrary() }
        if !testing {installRemoteControls()}
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let timer {RunLoop.main.add(timer,forMode:.common);RunLoop.main.add(timer,forMode:.modalPanel)}
    }

    func shutdown() {
        guard !shuttingDown else{return};shuttingDown=true
        timer?.invalidate(); timer = nil
        extensions.shutdown();extensionPlaylist.shutdown()
        clearRawCapture()
        savePosition(); saveLibrary()
        stopOutput()
        libvlc_media_player_set_renderer(player,nil)
        if let rendererBrowser {vela_renderer_browser_release(rendererBrowser)}
        for (command,target) in remoteTargets {command.removeTarget(target)}
        if !testing {MPNowPlayingInfoCenter.default().nowPlayingInfo=nil}
        libvlc_media_player_stop(player)
        libvlc_media_player_set_nsobject(player, nil)
        libvlc_media_player_release(player)
        if let media { libvlc_media_release(media) }
        libvlc_release(instance)
    }

    func addToLibrary(_ items:[MediaItem]){for item in items where !libraryItems.contains(where:{$0.url==item.url}){libraryItems.append(item)};saveLibrary()}
    func chooseLibraryFiles(){let panel=NSOpenPanel();panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;if panel.runModal() == .OK{addToLibrary(panel.urls.map{MediaItem(url:$0)})}}
    func playLibraryItem(_ item:MediaItem){if !queue.contains(where:{$0.id==item.id}){queue.append(item)};start(item)}
    func enqueue(_ urls: [URL], play: Bool = true) {
        let expanded = urls.flatMap { url -> [URL] in
            guard url.isFileURL, ["m3u","m3u8","pls"].contains(url.pathExtension.lowercased()),
                  let text = try? String(contentsOf:url,encoding:.utf8), !text.contains("#EXT-X-") else { return [url] }
            let entries = text.split(whereSeparator:\.isNewline).compactMap { line -> String? in
                let value = line.trimmingCharacters(in:.whitespacesAndNewlines)
                if url.pathExtension.lowercased() == "pls" {
                    guard value.lowercased().hasPrefix("file"),let split=value.firstIndex(of:"=") else{return nil}
                    return String(value[value.index(after:split)...])
                }
                return value.isEmpty || value.hasPrefix("#") ? nil : value
            }
            return entries.map { entry in
                if let absolute=URL(string:entry),absolute.scheme != nil {return absolute}
                return entry.hasPrefix("/") ? URL(fileURLWithPath:entry) : url.deletingLastPathComponent().appendingPathComponent(entry)
            }
        }
        let items = expanded.map { MediaItem(url: $0) }
        queue += items
        if play, let first = items.first { start(first) }
        saveLibrary()
    }

    func start(_ item: MediaItem, resume: Bool = true, extraOptions: [String] = []) {
        if item.url.scheme == "vela-capture" {NotificationCenter.default.post(name:Notification.Name("VelaCommand"),object:"capture");return}
        clearRawCapture()
        savePosition(); libvlc_media_player_stop(player)
        if recording { stopOutput() }
        if let media { libvlc_media_release(media) }
        let newMedia=extensionPlaylist.acquire(item)
        guard let newMedia else { error = "This media could not be opened."; media = nil; return }
        media = newMedia; currentID = item.id
        time = 0; length = 0; state = 0; previousState = 0
        subtitleTracks = []; audioTracks = []; videoTracks = []; chapters = []; externalSubtitles = []
        audioDelay = 0; subtitleDelay = 0
        pendingResume = rememberPosition && resume ? positions[item.url.absoluteString] : nil
        libvlc_media_add_option(newMedia, ":network-caching=\(Int(networkCache.isFinite ? min(60000,max(0,networkCache)):1000))")
        for option in advancedOptions.split(separator: "\n").map(String.init) + (item.options ?? []) + extraOptions {
            let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { libvlc_media_add_option(newMedia, trimmed.hasPrefix(":") ? trimmed : ":" + trimmed) }
        }
        libvlc_media_player_set_media(player, newMedia)
        libvlc_video_set_mouse_input(player,1);libvlc_video_set_key_input(player,1)
        libvlc_audio_set_volume(player, Int32(volume)); libvlc_audio_set_mute(player, muted ? 1 : 0)
        if libvlc_media_player_play(player) != 0 { error = "VLC could not start playback." }
        if keepHistory && !["avcapture","qtsound"].contains(item.url.scheme ?? "") { recent.removeAll { $0.url == item.url }; recent.insert(item, at: 0); recent = Array(recent.prefix(50)) }
        saveLibrary()
        extensions.notify("input_changed")
    }

    func togglePlay() {
        if !hasMedia { openFiles(); return }
        if state == 5 || state == 6 || state == 7, let current { start(current, resume: false) }
        else { libvlc_media_player_set_pause(player, isPlaying ? 1 : 0) }
    }
    func stop() { savePosition();clearRawCapture(); if recording {stopOutput()}; libvlc_media_player_stop(player);extensions.notify("input_changed"); time = 0; state = 5 }
    func seek(_ milliseconds: Int64) { guard seekable else { return }; libvlc_media_player_set_time(player, max(0, min(length, milliseconds))) }
    func skip(_ seconds: Int64) { seek(time + seconds * 1000) }
    func setVolume(_ value: Double) {guard value.isFinite else{return};volume = min(200,max(0,value));libvlc_audio_set_volume(player, Int32(volume))}
    func toggleMute() { muted.toggle(); libvlc_audio_set_mute(player, muted ? 1 : 0) }
    func setRate(_ value: Double) {
        guard value.isFinite,(0.25...4).contains(value)else{return}
        if libvlc_media_player_set_rate(player, Float(value)) == 0 { rate = value }
        else { error = "This input does not support changing playback speed." }
    }
    func next(backwards: Bool = false) {
        guard !queue.isEmpty else { return }
        if shuffle && !backwards { if let item = queue.filter({ $0.id != currentID }).randomElement() { start(item) }; return }
        let index = queue.firstIndex { $0.id == currentID } ?? (backwards ? 1 : -1)
        let nextIndex = index + (backwards ? -1 : 1)
        if queue.indices.contains(nextIndex) { start(queue[nextIndex]) }
        else if repeatMode == .all { start(backwards ? queue.last! : queue.first!) }
    }
    func remove(_ item: MediaItem) { if item.id == currentID { stop(); currentID = nil }; queue.removeAll { $0.id == item.id }; saveLibrary() }
    func openFiles(folder: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = folder; panel.canChooseFiles = !folder
        panel.allowsMultipleSelection = true; panel.message = folder ? "Choose a media folder" : "Open media with the VLC engine"
        if panel.runModal() == .OK {
            if folder {
                let ext: Set<String> = ["mp4","mkv","avi","mov","webm","m4v","ts","m2ts","mpg","mpeg","wmv","flv","ogv","mp3","flac","wav","aac","m4a","ogg","opus","aiff","wma","vob"]
                let urls = panel.urls.flatMap { url -> [URL] in
                    (FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []).filter { ext.contains($0.pathExtension.lowercased()) }
                }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                enqueue(urls)
            } else { enqueue(panel.urls) }
        }
    }
    func openSubtitle() {
        guard hasMedia else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { addSubtitle(url) }
    }
    func addSubtitle(_ url: URL) {
        let result = libvlc_media_player_add_slave(player, libvlc_media_slave_type_subtitle, url.absoluteString, true)
        if result != 0 { error = "Could not load this subtitle file." }
        else { externalSubtitles.append(url) }
    }
    func selectAudio(_ id: Int32) { libvlc_audio_set_track(player, id); audioTrack = id }
    func selectSubtitle(_ id: Int32) { libvlc_video_set_spu(player, id); subtitleTrack = id }
    func selectVideo(_ id: Int32) { libvlc_video_set_track(player, id); videoTrack = id }
    func selectChapter(_ id: Int32) { libvlc_media_player_set_chapter(player, id) }
    func setAudioDelay(_ seconds: Double) {guard seconds.isFinite else{return};audioDelay=min(3600,max(-3600,seconds));libvlc_audio_set_delay(player,Int64(audioDelay*1_000_000))}
    func setSubtitleDelay(_ seconds: Double) {guard seconds.isFinite else{return};subtitleDelay=min(3600,max(-3600,seconds));libvlc_video_set_spu_delay(player,Int64(subtitleDelay*1_000_000))}
    func setAspect(_ value: String) { aspect = value; libvlc_video_set_aspect_ratio(player, value == "Default" ? nil : value) }
    func setCrop(_ value: String) { crop = value; libvlc_video_set_crop_geometry(player, value == "None" ? nil : value) }
    func setAdjustments() {
        libvlc_video_set_adjust_int(player, 0, 1)
        libvlc_video_set_adjust_float(player, 1, Float(contrast))
        libvlc_video_set_adjust_float(player, 2, Float(brightness))
        libvlc_video_set_adjust_float(player, 4, Float(saturation))
        libvlc_video_set_adjust_float(player, 5, Float(gamma))
    }
    func setEqualizer(_ name: String) {
        if name == "Custom" {setCustomEqualizer();return}
        eqPreset = name
        guard let index = equalizerPresets.firstIndex(of: name) else { libvlc_media_player_set_equalizer(player, nil); return }
        if let eq = libvlc_audio_equalizer_new_from_preset(UInt32(index)) {
            libvlc_media_player_set_equalizer(player, eq); libvlc_audio_equalizer_release(eq)
        }
    }
    func setCustomEqualizer() {
        eqPreset = "Custom"
        if let eq = libvlc_audio_equalizer_new() {
            for (index,value) in eqGains.enumerated() { libvlc_audio_equalizer_set_amp_at_index(eq, Float(value), UInt32(index)) }
            libvlc_media_player_set_equalizer(player, eq); libvlc_audio_equalizer_release(eq)
        }
    }
    func applyMediaSettings() {
        let liveSource=rawSource
        let item=current
        savePosition()
        let options=["--no-video-title-show","--freetype-font=\(subtitleFont)","--freetype-rel-fontsize=\(Self.subtitleSizeValue(subtitleSize))"]
        guard let newInstance=Self.makeInstance(["--no-ignore-config","--config=\(storageURL.appendingPathComponent("vlcrc").path)"]+options) else {error="Could not apply the new playback settings.";return}
        guard let newPlayer=libvlc_media_player_new(newInstance) else {libvlc_release(newInstance);error="Could not create a new playback session.";return}
        stopOutput();if let rawToken{vela_raw_cancel(rawToken);self.rawToken=nil};libvlc_media_player_stop(player)
        libvlc_media_player_set_renderer(player,nil)
        if let rendererBrowser{vela_renderer_browser_release(rendererBrowser)}
        rendererBrowser=nil;scanningCast=false;castDevices=[];selectedCast=0
        libvlc_media_player_set_nsobject(player,nil);libvlc_media_player_release(player)
        if let media{libvlc_media_release(media)};media=nil
        libvlc_release(instance);instance=newInstance;player=newPlayer
        extensions.rebind()
        libvlc_media_player_set_nsobject(player,Unmanaged.passUnretained(videoView).toOpaque())
        if let liveSource{media=vela_raw_media(instance,liveSource,&rawToken);if let media{libvlc_media_player_set_media(player,media);libvlc_audio_set_volume(player,Int32(volume));libvlc_audio_set_mute(player,muted ? 1:0);_ = libvlc_media_player_play(player)}}else if let item{start(item)}
        saveLibrary()
    }
    private static func subtitleSizeValue(_ name:String)->Int { ["Small":20,"Normal":16,"Large":12,"Extra Large":8][name] ?? 16 }
    private static func makeInstance(_ options:[String])->OpaquePointer? {
        let arguments=options.contains("--no-ignore-config") ? options:["--ignore-config"]+options
        let strings=arguments.map{strdup($0)!};defer{strings.forEach{free($0)}}
        var args=strings.map{UnsafePointer<CChar>($0) as UnsafePointer<CChar>?}
        return args.withUnsafeMutableBufferPointer{libvlc_new(Int32($0.count),$0.baseAddress)}
    }
    func addBookmark() {
        guard let current else { return }
        bookmarks.append(Bookmark(media: current.url, name: "Bookmark \(bookmarks.filter { $0.media == current.url }.count + 1)", time: time)); saveLibrary()
    }
    func savePlaylist(name: String) { playlists.append(SavedPlaylist(name: name, items: queue)); saveLibrary() }
    func exportPlaylist() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Playlist.m3u8"
        if panel.runModal() == .OK, let url = panel.url {
            let text = "#EXTM3U\n" + queue.map { "#EXTINF:-1,\($0.title)\n\($0.url.isFileURL ? $0.url.path : $0.url.absoluteString)" }.joined(separator: "\n")
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
    func snapshot() {
        guard hasMedia else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Snapshot.png"
        if panel.runModal() == .OK, let url = panel.url {
            if libvlc_video_take_snapshot(player, 0, url.path, 0, 0) != 0 { error = "A video frame is needed before taking a snapshot." }
        }
    }
    func convert(to url: URL, format: String) {
        guard let current else { return }
        guard !current.url.isFileURL || current.url.standardizedFileURL.resolvingSymlinksInPath() != url.standardizedFileURL.resolvingSymlinksInPath() else { error="Choose an output file different from the source media."; return }
        if current.url.isFileURL || ["http","https","rtsp","rtmp"].contains(current.url.scheme ?? ""){startHelperOutput(current.url,to:url,audioOnly:format=="Audio (WAV)",recording:false);return}
        let vcodec = format == "Audio (WAV)" ? "none" : "mp4v"
        let acodec = format == "Audio (WAV)" ? "s16l" : "mp4a"
        let mux = format == "Audio (WAV)" ? "wav" : "mp4"
        // Quote and escape the destination inside VLC's sout grammar, independently of shell syntax.
        let destination = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let encoder = format == "Audio (WAV)" ? "" : ",venc=avcodec,vb=6000"
        startOutput(current.url, options: [":avcodec-hw=none", ":sout-mux-caching=30000", ":sout=#transcode{vcodec=\(vcodec)\(encoder),acodec=\(acodec),ab=192}:std{access=file,mux=\(mux),dst=\"\(destination)\"}", ":sout-keep"], recording: false)
    }
    func startRecording(to url: URL) {
        guard let current else { return }
        guard !current.url.isFileURL || current.url.standardizedFileURL.resolvingSymlinksInPath() != url.standardizedFileURL.resolvingSymlinksInPath() else { error="Choose an output file different from the source media."; return }
        if rawSource == nil && (current.url.isFileURL || ["http","https","rtsp","rtmp"].contains(current.url.scheme ?? "")){startHelperOutput(current.url,to:url,audioOnly:false,recording:true);return}
        let destination = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let output = rawSource != nil ? ":sout=#transcode{vcodec=h264,venc=x264{preset=ultrafast,tune=zerolatency,keyint=30},vb=6000,acodec=mp4a}:std{access=file,mux=mkv,dst=\"\(destination)\"}" : ":sout=#transcode{vcodec=mp4v,venc=avcodec,vb=6000,acodec=mp4a}:duplicate{dst=display,dst=std{access=file,mux=mkv,dst=\"\(destination)\"}}"
        var options=[":sout-x264-options=repeat-headers=1",":vout=dummy",":aout=auhal",":file-caching=0",":clock-jitter=0",":avcodec-hw=none",":sout-mux-caching=30000",output,":sout-keep",":sout-all"]
        if rawSource == nil {options.append(":start-time=\(Double(time)/1000)")}
        startOutput(current.url,options:options,recording:true)
    }
    func startStream(protocolName:String,host:String,port:Int,path:String,transcode:Bool){
        guard let current,["HTTP","UDP","RTP"].contains(protocolName), (1024...65535).contains(port), !host.isEmpty, host.range(of:"^[A-Za-z0-9.-]+$",options:.regularExpression) != nil,
              path.range(of:"^/[A-Za-z0-9/_-]*$",options:.regularExpression) != nil else{error="Use a valid host, port (1024–65535), and path.";return}
        let destination=host+":"+String(port)+(protocolName=="HTTP" ? path:"")
        let output=protocolName=="RTP" ? "rtp{mux=ts,dst=\(host),port=\(port)}" : "std{access=\(protocolName=="HTTP" ? "http":"udp"),mux=ts,dst=\(destination)}"
        let encode=rawSource != nil ? "transcode{vcodec=h264,venc=x264{preset=ultrafast,tune=zerolatency,keyint=30},vb=4000,acodec=mp4a,ab=192}:" : (transcode ? "transcode{vcodec=mp4v,venc=avcodec,vb=2500,acodec=mpga,ab=192}:" : "")
        startOutput(current.url,options:[":sout-x264-options=repeat-headers=1",":sout-ts-use-key-frames=1",":sout=#"+encode+"duplicate{dst=display,dst="+output+"}",":sout-keep",":sout-all",":sout-mux-caching=500",":sout-http-mime=video/MP2T",":input-repeat=65535"],recording:false)
        if outputPlayer != nil{streamingURL=protocolName=="HTTP" ? "http://"+destination : (protocolName=="UDP" ? "udp://@"+destination:"rtp://@"+destination);conversionProgress="Streaming…"}
    }
    private func startHelperOutput(_ input:URL,to output:URL,audioOnly:Bool,recording:Bool){
        stopOutput()
        guard exportJob==nil else{error="Please wait for the previous export to finish.";return}
        do{exportJob=try MediaExportJob(input:input,output:output,audioOnly:audioOnly,recording:recording,start:seekable ? time:0,duration:length,storage:storageURL);self.recording=recording;conversionProgress=recording ? "Recording…":"Converting…";error=nil}catch{self.error=error.localizedDescription}
    }
    private func startOutput(_ url: URL, options: [String], recording: Bool) {
        stopOutput()
        guard exportJob==nil else{error="Please wait for the previous export to finish.";return}
        guard let outputEngine=Self.makeInstance(["--vout=dummy","--aout=auhal","--codec=avcodec","--avcodec-hw=none","--sout-mux-caching=30000"]) else{error="Could not initialize the export engine.";return}
        outputInstance=outputEngine
        if let rawSource {outputMedia=vela_raw_media(outputEngine,rawSource,&outputRawToken)}
        else {outputMedia = url.isFileURL ? libvlc_media_new_path(outputEngine, url.path) : libvlc_media_new_location(outputEngine, url.absoluteString)}
        guard let outputMedia, let mp = libvlc_media_player_new(outputEngine) else { error = "Could not start media export."; stopOutput();return }
        outputPlayer = mp
        libvlc_audio_set_volume(mp,0);libvlc_audio_set_mute(mp,1)
        for option in options { libvlc_media_add_option(outputMedia, option) }
        libvlc_media_player_set_media(mp, outputMedia)
        if libvlc_media_player_play(mp) != 0 { error = "Could not start media export."; stopOutput(); return }
        self.recording = recording; conversionProgress = recording ? "Recording…" : "Converting…"
    }
    func stopOutput() {
        if let exportJob{exportJob.stop();recording=false;conversionProgress="Finishing…";return}
        if let outputRawToken{vela_raw_cancel(outputRawToken);self.outputRawToken=nil}
        if let outputPlayer { libvlc_media_player_stop(outputPlayer); libvlc_media_player_release(outputPlayer) }
        if let outputMedia { libvlc_media_release(outputMedia) }
        if let outputInstance {libvlc_release(outputInstance)}
        streamingURL=""
        outputPlayer = nil; outputMedia = nil; outputInstance=nil;recording = false; conversionProgress = ""
    }
    func poll() {
        guard !shuttingDown else{return}
        state = Int32(libvlc_media_player_get_state(player).rawValue)
        time = max(0, libvlc_media_player_get_time(player)); length = max(0, libvlc_media_player_get_length(player))
        seekable = libvlc_media_player_is_seekable(player) != 0
        if let resume = pendingResume, seekable, length > 0 {
            pendingResume = nil
            if resume > 3000 && resume < length - 5000 { seek(resume) }
        }
        if state == 3 {
            let actualVolume=libvlc_audio_get_volume(player)
            if actualVolume>=0 && actualVolume != Int32(volume){volume=Double(actualVolume)}
            let actualMute=libvlc_audio_get_mute(player)
            if actualMute>=0 && (actualMute != 0) != muted{muted=actualMute != 0}
        }
        if state == 3, previousState != 3 {
            setRate(rate); setAspect(aspect); setCrop(crop); setEqualizer(eqPreset)
            if brightness != 1 || contrast != 1 || saturation != 1 || gamma != 1 { setAdjustments() }
        }
        if state == 6 && previousState != 6 && autoAdvance {
            if let current { positions.removeValue(forKey: current.url.absoluteString) }
            if repeatMode == .one, let current { start(current, resume: false) }
            else { next() }
        }
        if state == 7 && previousState != 7 { error = "VLC could not play this input. Check that the file exists or the stream is available." }
        let metadata=currentMetadata();if let title=metadata["title"],!title.isEmpty,let index=queue.firstIndex(where:{$0.id==currentID}),queue[index].displayTitle != title{queue[index].displayTitle=title};if metadata != extensionLastMetadata{extensionLastMetadata=metadata;extensions.notify("meta_changed")}
        if previousState != state {let native=vela_player_input_state(player);let fallback:[Int32:Int32]=[0:0,1:1,2:2,3:2,4:3,5:4,6:4,7:5];extensions.notify("playing_changed",value:Double(native>=0 ? native:fallback[state] ?? 0))}
        previousState = state; ticks += 1
        if ticks % 5 == 0 {
            subtitleTracks = tracks(libvlc_video_get_spu_description(player))
            audioTracks = tracks(libvlc_audio_get_track_description(player))
            videoTracks = tracks(libvlc_video_get_track_description(player))
            audioTrack = libvlc_audio_get_track(player); subtitleTrack = libvlc_video_get_spu(player); videoTrack = libvlc_video_get_track(player)
            chapter = libvlc_media_player_get_chapter(player)
            refreshDiscTitles()
            var list: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_chapter_description_t>?>?
            let count = libvlc_media_player_get_full_chapter_descriptions(player, libvlc_media_player_get_title(player), &list)
            if count > 0, let list {
                chapters = (0..<count).compactMap { i -> Chapter? in
                    guard let p = list[Int(i)] else { return nil }
                    return Chapter(id: i, name: p.pointee.psz_name.map { String(cString: $0) } ?? "Chapter \(i+1)", time: p.pointee.i_time_offset)
                }; libvlc_chapter_descriptions_release(list, UInt32(count))
            } else { chapters = [] }
            if let media { var stats = libvlc_media_stats_t(); if libvlc_media_get_stats(media, &stats) != 0 { statistics = "Decoded video: \(stats.i_decoded_video)\nDisplayed frames: \(stats.i_displayed_pictures)\nLost frames: \(stats.i_lost_pictures)\nDecoded audio: \(stats.i_decoded_audio)\nInput bitrate: \(String(format: "%.1f", stats.f_input_bitrate * 8000)) kb/s" } }
            refreshDevices()
            if scanningCast {refreshCastDevices()}
            if !testing {updateNowPlaying()}
        }
        if ticks % 25 == 0 { savePosition(); saveLibrary() }
        if let sleepUntil, Date() >= sleepUntil { stop(); self.sleepUntil = nil }
        if let job=exportJob {
            if !job.process.isRunning{let failure=job.finish();exportJob=nil;recording=false;if let failure{error=failure;conversionProgress="Export failed"}else{conversionProgress=job.stopped && !job.recording ? "Export stopped":"Export complete"}}
            else if !job.stopped && !job.recording && job.duration>0{conversionProgress="Converting \(min(99,Int(Double(job.elapsed)/Double(job.duration)*100)))%"}
        }
        if let outputPlayer {
            let outputState = libvlc_media_player_get_state(outputPlayer).rawValue
            if outputState == 7 { error = "Media export failed."; stopOutput() }
            else if outputState == 6 { stopOutput(); conversionProgress = "Export complete" }
            else if !recording && streamingURL.isEmpty { conversionProgress = "Converting \(Int(libvlc_media_player_get_position(outputPlayer) * 100))%" }
        }
    }
    private func tracks(_ head: UnsafeMutablePointer<libvlc_track_description_t>?) -> [Track] {
        var p = head; var result: [Track] = []
        while let node = p { result.append(Track(id: node.pointee.i_id, name: node.pointee.psz_name.map { String(cString: $0) } ?? "Track \(node.pointee.i_id)")); p = node.pointee.p_next }
        if let head { libvlc_track_description_list_release(head) }; return result
    }
    func refreshDevices() {
        let head = libvlc_audio_output_device_enum(player); var p = head; var result: [(String,String)] = []
        while let node = p {
            if let id = node.pointee.psz_device { result.append((String(cString: id), node.pointee.psz_description.map { String(cString: $0) } ?? String(cString: id))) }; p = node.pointee.p_next
        }
        if let head { libvlc_audio_output_device_list_release(head) }
        outputDevices = result
    }
    func setDevice(_ id: String) { libvlc_audio_output_device_set(player, nil, id) }
    func currentMetadata()->[String:String]{
        guard let media else{return[:]};var result:[String:String]=[:]
        let keys=["title","artist","genre","copyright","album","track_number","description","rating","date","setting","url","language","now_playing","publisher","encoded_by","artwork_url","track_id"]
        for(i,key)in keys.enumerated(){if let value=libvlc_media_get_meta(media,libvlc_meta_t(rawValue:UInt32(i))){result[key]=String(cString:value);libvlc_free(value)}}
        return result
    }
    func setMetadata(_ key:String,value:String){
        let keys=["title","artist","genre","copyright","album","track_number","description","rating","date","setting","url","language","now_playing","publisher","encoded_by","artwork_url","track_id"]
        if let media,let index=keys.firstIndex(of:key){libvlc_media_set_meta(media,libvlc_meta_t(rawValue:UInt32(index)),value)}
    }
    func startRawCapture(_ source:OpaquePointer,title:String){
        clearRawCapture(stopService:false);stopOutput();libvlc_media_player_stop(player)
        if let media{libvlc_media_release(media)};media=nil
        vela_raw_hold(source);rawSource=source
        guard let captureMedia=vela_raw_media(instance,source,&rawToken)else{clearRawCapture();error="Could not create the capture input.";return}
        let item=MediaItem(url:URL(string:"vela-capture://live")!,displayTitle:title)
        queue.removeAll{$0.url.scheme == "vela-capture"};queue.append(item);currentID=item.id;media=captureMedia
        state=0;previousState=0;time=0;length=0;seekable=false
        libvlc_media_player_set_media(player,captureMedia);libvlc_audio_set_mute(player,muted ? 1 : 0)
        if libvlc_media_player_play(player) != 0{error="Could not start live capture."};extensions.notify("input_changed")
    }
    private func clearRawCapture(stopService:Bool=true){
        if let rawToken{vela_raw_cancel(rawToken);self.rawToken=nil}
        if let rawSource{vela_raw_finish(rawSource);vela_raw_release(rawSource);self.rawSource=nil}
        if stopService{captureService.stop()}
    }
    func navigateDisc(_ direction:UInt32){libvlc_media_player_navigate(player,direction)}
    func selectDiscTitle(_ id:Int32){libvlc_media_player_set_title(player,id);discTitle=id}
    func refreshDiscTitles(){
        guard isDisc else{discTitles=[];discTitle = -1;return}
        var titles:UnsafeMutablePointer<UnsafeMutablePointer<libvlc_title_description_t>?>?
        let count=libvlc_media_player_get_full_title_descriptions(player,&titles)
        if count>0,let titles{
            discTitles=(0..<count).compactMap{i -> DiscTitle? in guard let t=titles[Int(i)]else{return nil};return DiscTitle(id:i,name:t.pointee.psz_name.map{String(cString:$0)} ?? "Title \(i+1)",duration:t.pointee.i_duration,menu:(t.pointee.i_flags & 1) != 0)}
            libvlc_title_descriptions_release(titles,UInt32(count))
        }else{discTitles=[]}
        discTitle=libvlc_media_player_get_title(player)
    }
    func scanCastDevices() {
        if rendererBrowser == nil {rendererBrowser=vela_renderer_browser_new(instance)}
        scanningCast = rendererBrowser != nil
    }
    func refreshCastDevices() {
        guard let rendererBrowser,let snapshot=vela_renderer_browser_snapshot(rendererBrowser) else{return}
        let text=String(cString:snapshot);free(snapshot)
        castDevices=text.split(whereSeparator:\.isNewline).compactMap {line in
            let parts=line.split(separator:"\t",maxSplits:2).map(String.init)
            guard parts.count==3,let id=UInt64(parts[0]) else{return nil}
            return CastDevice(id:id,name:parts[2],type:parts[1])
        }
    }
    func cast(to id:UInt64) {
        if let rawSource{let previous=selectedCast;if let rawToken{vela_raw_cancel(rawToken);self.rawToken=nil};libvlc_media_player_stop(player);if vela_renderer_browser_select(rendererBrowser,player,id)==0{selectedCast=id}else{_ = vela_renderer_browser_select(rendererBrowser,player,previous);error="The casting device is no longer available. Live capture continues on the previous output."};if let media{libvlc_media_release(media)};media=vela_raw_media(instance,rawSource,&rawToken);if let media{libvlc_media_player_set_media(player,media);_ = libvlc_media_player_play(player)};return}
        let position=time;let previous=selectedCast
        savePosition();libvlc_media_player_stop(player)
        if vela_renderer_browser_select(rendererBrowser,player,id)==0 {selectedCast=id;if let current {start(current);pendingResume=position}}
        else{_ = vela_renderer_browser_select(rendererBrowser,player,previous);if let current{start(current);pendingResume=position};error="The casting device is no longer available. Playback continues on the previous output."}
    }
    func stopCastScan(){
        if selectedCast != 0 {cast(to:0)}
        if let rendererBrowser{vela_renderer_browser_release(rendererBrowser)}
        rendererBrowser=nil;scanningCast=false;castDevices=[]
    }
    private func savePosition() { if rememberPosition, let current, time > 3000, length > time + 5000 { positions[current.url.absoluteString] = time } }
    private func installRemoteControls(){
        let center=MPRemoteCommandCenter.shared()
        func add(_ command:MPRemoteCommand,_ action:@escaping @MainActor ()->Void){
            let target=command.addTarget{_ in Task{@MainActor in action()};return .success}
            remoteTargets.append((command,target))
        }
        add(center.togglePlayPauseCommand){[weak self] in self?.togglePlay()}
        add(center.playCommand){[weak self] in if let self,!self.isPlaying{self.togglePlay()}}
        add(center.pauseCommand){[weak self] in if let self,self.isPlaying{self.togglePlay()}}
        add(center.stopCommand){[weak self] in self?.stop()}
        add(center.nextTrackCommand){[weak self] in self?.next()}
        add(center.previousTrackCommand){[weak self] in self?.next(backwards:true)}
        center.skipForwardCommand.preferredIntervals=[10];center.skipBackwardCommand.preferredIntervals=[10]
        add(center.skipForwardCommand){[weak self] in self?.skip(10)}
        add(center.skipBackwardCommand){[weak self] in self?.skip(-10)}
        let positionTarget=center.changePlaybackPositionCommand.addTarget{[weak self] event in
            guard let event=event as? MPChangePlaybackPositionCommandEvent else{return .commandFailed}
            let milliseconds=Int64(event.positionTime*1000)
            Task{@MainActor in self?.seek(milliseconds)};return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand,positionTarget))
    }
    private func updateNowPlaying(){
        guard let current else{return}
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[MPMediaItemPropertyTitle:current.title,MPMediaItemPropertyPlaybackDuration:Double(length)/1000,MPNowPlayingInfoPropertyElapsedPlaybackTime:Double(time)/1000,MPNowPlayingInfoPropertyPlaybackRate:isPlaying ? rate : 0]
        MPNowPlayingInfoCenter.default().playbackState=isPlaying ? .playing : (state == 4 ? .paused : .stopped)
    }
    private struct Library: Codable { var items:[MediaItem]?=nil; var bookmarks: [Bookmark]; var playlists: [SavedPlaylist]; var recent: [MediaItem]; var positions: [String: Int64] }
    func saveLibrary() {
        if !testing {
        UserDefaults.standard.set(keepHistory, forKey: "keepHistory"); UserDefaults.standard.set(rememberPosition, forKey: "rememberPosition")
        UserDefaults.standard.set(advancedOptions, forKey: "advancedOptions"); UserDefaults.standard.set(networkCache, forKey: "networkCache")
        }
        if !testing {UserDefaults.standard.set(volume,forKey:"volume")}
        if !testing {UserDefaults.standard.set(subtitleFont,forKey:"subtitleFont");UserDefaults.standard.set(subtitleSize,forKey:"subtitleSize")}
        do { try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Library(items:libraryItems,bookmarks: bookmarks, playlists: playlists, recent: keepHistory ? recent : [], positions: rememberPosition ? positions : [:]))
            try data.write(to: storageURL.appendingPathComponent("library.json"), options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    private func loadLibrary() {
        guard let data = try? Data(contentsOf: storageURL.appendingPathComponent("library.json")), let library = try? JSONDecoder().decode(Library.self, from: data) else { return }
        libraryItems=library.items ?? [];bookmarks = library.bookmarks; playlists = library.playlists; recent = keepHistory ? library.recent : []; positions = library.positions
    }
    static func timestamp(_ ms: Int64) -> String { let seconds = max(0, ms)/1000; return String(format: "%02d:%02d:%02d", seconds/3600, (seconds/60)%60, seconds%60) }
}
