import SwiftUI
import AppKit
import CLibVLC

@MainActor struct Inspector: View {
    @ObservedObject var engine: PlayerEngine
    let panel: Panel
    let onPanel: (Panel) -> Void
    let openSettings: () -> Void
    @Binding var showStats: Bool
    private var family: [Panel] {
        switch panel {
        case .queue,.bookmarks,.chapters:return [.queue,.bookmarks,.chapters]
        case .audio,.video,.subtitles:return [.video,.audio,.subtitles]
        default:return [.playback,.videoSettings,.audioSettings,.subtitleSettings]
        }
    }
    private func title(_ p:Panel)->String {
        switch p {case .queue:return "Queue";case .bookmarks:return "Bookmarks";case .chapters:return "Chapters";case .video,.videoSettings:return "Video";case .audio,.audioSettings:return "Audio";case .subtitles,.subtitleSettings:return "Subtitles";case .playback:return "Playback"}
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                ForEach(family,id:\.self) {p in
                    Button {onPanel(p)} label:{Text(title(p)).font(Design.font(12)).foregroundStyle(panel == p ? Design.foreground : Design.secondary).frame(maxWidth:.infinity).padding(.vertical,14).overlay(alignment:.bottom){if panel == p {Design.accent.frame(height:2)}}}.buttonStyle(.plain)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    switch panel {
                    case .queue: queue
                    case .bookmarks: bookmarks
                    case .chapters: chapters
                    case .video: tracks("Embedded Tracks",items:engine.videoTracks,selected:engine.videoTrack,select:engine.selectVideo)
                    case .audio:
                        tracks("Embedded Tracks",items:engine.audioTracks,selected:engine.audioTrack,select:engine.selectAudio)
                        section("Output Device") {
                            if engine.outputDevices.isEmpty { Text("System default").foregroundStyle(Design.secondary) }
                            ForEach(engine.outputDevices,id:\.id) {device in Button(device.name){engine.setDevice(device.id)}.buttonStyle(.plain) }
                        }
                    case .subtitles:
                        tracks("Embedded / Loaded Tracks",items:engine.subtitleTracks,selected:engine.subtitleTrack,select:engine.selectSubtitle)
                        section("External Tracks") {
                            Button("+  Add Subtitle File…"){engine.openSubtitle()}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
                            ForEach(engine.externalSubtitles,id:\.self){url in Text(url.lastPathComponent).lineLimit(1)}
                        }
                    case .playback: playback
                    case .videoSettings: videoSettings
                    case .audioSettings: audioSettings
                    case .subtitleSettings: subtitleSettings
                    }
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            }
            Spacer(minLength:0)
            Button("Show Preferences"){openSettings()}.buttonStyle(VelaButtonStyle()).padding(20)
        }.frame(maxHeight:.infinity).background(Design.panel.opacity(0.9),in:RoundedRectangle(cornerRadius:10)).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:10)).overlay{RoundedRectangle(cornerRadius:10).stroke(Design.divider,lineWidth:1)}
    }
    private var queue: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text("\(engine.queue.count) items").foregroundStyle(Design.secondary);Spacer();Button("+ Add"){engine.openFiles()}.buttonStyle(.plain)}
            HStack {Toggle("Shuffle",isOn:$engine.shuffle);Picker("Repeat",selection:$engine.repeatMode){ForEach(RepeatMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}}.font(Design.font(12))
            if engine.queue.isEmpty {Text("Open files to build your queue.").foregroundStyle(Design.secondary)}
            ForEach(engine.queue){item in
                HStack(spacing:10) {
                    Button {engine.start(item)} label:{HStack{Text(item.id == engine.currentID ? "▶" : "").foregroundStyle(Design.accent).frame(width:12);Text(item.title).lineLimit(1).truncationMode(.middle)}}.buttonStyle(.plain)
                    Spacer(minLength:0)
                    Button {engine.remove(item)} label:{Image(systemName:"xmark").font(.system(size:10))}.buttonStyle(.plain).help("Remove from queue")
                }.padding(.vertical,6)
            }
        }
    }
    private var bookmarks: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{Text("Bookmarks").foregroundStyle(Design.secondary);Spacer();Button("+ Add"){engine.addBookmark()}.buttonStyle(.plain).disabled(!engine.hasMedia)}
            let marks=engine.bookmarks.filter{$0.media == engine.current?.url}
            if marks.isEmpty {Text("Save a moment to return to it later.").foregroundStyle(Design.secondary)}
            ForEach(marks){mark in
                HStack {Button {engine.seek(mark.time)} label:{HStack{Text(mark.name);Spacer();Text(PlayerEngine.timestamp(mark.time)).monospacedDigit().foregroundStyle(Design.secondary)}}.buttonStyle(.plain)
                    Button {engine.bookmarks.removeAll{$0.id == mark.id};engine.saveLibrary()} label:{Image(systemName:"minus")}.buttonStyle(.plain)}
            }
        }
    }
    private var chapters: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Chapters").foregroundStyle(Design.secondary)
            if engine.chapters.isEmpty {Text("This media has no chapters.").foregroundStyle(Design.secondary)}
            ForEach(engine.chapters){chapter in Button {engine.selectChapter(chapter.id)} label:{HStack{Text("\(chapter.id+1)").foregroundStyle(Design.accent);Text(chapter.name);Spacer();Text(PlayerEngine.timestamp(chapter.time)).foregroundStyle(Design.secondary)}}.buttonStyle(.plain).padding(.vertical,4)}
        }
    }
    private func tracks(_ name:String,items:[Track],selected:Int32,select:@escaping(Int32)->Void)->some View {
        VStack(alignment:.leading,spacing:16) {
            Text(name).font(Design.font(12)).foregroundStyle(Design.secondary)
            if items.isEmpty {Text("No tracks available").foregroundStyle(Design.secondary)}
            ForEach(items){track in Button {select(track.id)} label:{HStack(spacing:12){Image(systemName:selected == track.id ? "checkmark" : "").foregroundStyle(Design.accent).frame(width:16);Text(track.name);Spacer()}}.buttonStyle(.plain)}
        }
    }
    private var playback: some View {
        VStack(alignment:.leading,spacing:24) {
            Toggle("Show Statistics",isOn:$showStats).toggleStyle(.switch)
            HStack {Text("Sleep Timer");Spacer();Menu {Button("Off"){engine.sleepUntil=nil};ForEach([15,30,60,90],id:\.self){minutes in Button("\(minutes) minutes"){engine.sleepUntil=Date().addingTimeInterval(Double(minutes*60))}}} label:{Text(engine.sleepUntil.map{ $0.formatted(date:.omitted,time:.shortened)} ?? "Off")}}
            valueSlider("Speed",value:Binding(get:{engine.rate},set:{engine.setRate($0)}),range:0.25...4,suffix:"×")
            HStack {Button("−10 seconds"){engine.skip(-10)};Button("+10 seconds"){engine.skip(10)}}.buttonStyle(VelaButtonStyle()).disabled(!engine.seekable)
            Button("Next Frame"){libvlc_media_player_next_frame(engine.player)}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
            Button("Stop Playback"){engine.stop()}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
            HStack {Toggle("Shuffle",isOn:$engine.shuffle);Picker("Repeat",selection:$engine.repeatMode){ForEach(RepeatMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}}
        }
    }
    private var videoSettings: some View {
        VStack(alignment:.leading,spacing:20) {
            Picker("Aspect Ratio",selection:Binding(get:{engine.aspect},set:{engine.setAspect($0)})){ForEach(["Default","16:9","4:3","1:1","16:10","2.21:1","2.35:1"],id:\.self){Text($0)}}
            Picker("Crop",selection:Binding(get:{engine.crop},set:{engine.setCrop($0)})){ForEach(["None","16:9","4:3","1:1","16:10","2.35:1"],id:\.self){Text($0)}}
            valueSlider("Brightness",value:Binding(get:{engine.brightness},set:{engine.brightness=$0;engine.setAdjustments()}),range:0...2)
            valueSlider("Contrast",value:Binding(get:{engine.contrast},set:{engine.contrast=$0;engine.setAdjustments()}),range:0...2)
            valueSlider("Saturation",value:Binding(get:{engine.saturation},set:{engine.saturation=$0;engine.setAdjustments()}),range:0...3)
            valueSlider("Gamma",value:Binding(get:{engine.gamma},set:{engine.gamma=$0;engine.setAdjustments()}),range:0.1...3)
            Menu("Deinterlace") {Button("Off"){libvlc_video_set_deinterlace(engine.player,nil)};ForEach(["blend","bob","yadif","yadif2x"],id:\.self){mode in Button(mode){libvlc_video_set_deinterlace(engine.player,mode)}}}
            Button("Take Snapshot…"){engine.snapshot()}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
            Button("Reset Video Settings"){engine.brightness=1;engine.contrast=1;engine.saturation=1;engine.gamma=1;engine.setAdjustments();engine.setAspect("Default");engine.setCrop("None")}.buttonStyle(.plain)
        }
    }
    private var audioSettings: some View {
        VStack(alignment:.leading,spacing:20) {
            valueSlider("Audio Delay",value:Binding(get:{engine.audioDelay},set:{engine.setAudioDelay($0)}),range:-10...10,suffix:" s")
            Picker("Equalizer",selection:Binding(get:{engine.eqPreset},set:{engine.setEqualizer($0)})){Text("Disabled").tag("Disabled");Text("Custom").tag("Custom");ForEach(engine.equalizerPresets,id:\.self){Text($0).tag($0)}}
            section("10-band Equalizer") {
                HStack(spacing:10) {
                    ForEach(0..<10,id:\.self){i in
                        VStack(spacing:8) {
                            Slider(value:Binding(get:{engine.eqGains[i]},set:{engine.eqGains[i]=$0;engine.setCustomEqualizer()}),in:-20...20).frame(width:120).rotationEffect(.degrees(-90)).frame(width:20,height:120)
                            Text(["60","170","310","600","1k","3k","6k","12k","14k","16k"][i]).font(Design.font(9))
                        }
                    }
                }.padding(.vertical,10)
            }
            Menu("Stereo Mode") {ForEach([(1,"Stereo"),(2,"Reverse Stereo"),(3,"Left"),(4,"Right"),(5,"Dolby Surround")],id:\.0){id,name in Button(name){libvlc_audio_set_channel(engine.player,Int32(id))}}}
            Button("Reset Audio Settings"){engine.setAudioDelay(0);engine.eqGains=Array(repeating:0,count:10);engine.setEqualizer("Disabled")}.buttonStyle(.plain)
        }
    }
    private var subtitleSettings: some View {
        VStack(alignment:.leading,spacing:20) {
            valueSlider("Subtitle Delay",value:Binding(get:{engine.subtitleDelay},set:{engine.setSubtitleDelay($0)}),range:-10...10,suffix:" s")
            TextField("Font",text:$engine.subtitleFont)
            Picker("Text Size",selection:$engine.subtitleSize){ForEach(["Small","Normal","Large","Extra Large"],id:\.self){Text($0)}}
            Text("Use Apply & Reopen Media to activate font and size.").font(Design.font(12)).foregroundStyle(Design.secondary)
            Button("Apply & Reopen Media"){engine.applyMediaSettings()}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
            Button("Add Subtitle File…"){engine.openSubtitle()}.buttonStyle(VelaButtonStyle()).disabled(!engine.hasMedia)
        }
    }
    private func section<Content:View>(_ name:String,@ViewBuilder content:()->Content)->some View {VStack(alignment:.leading,spacing:14){Text(name).font(Design.font(12)).foregroundStyle(Design.secondary);content()}.frame(maxWidth:.infinity,alignment:.leading)}
    private func valueSlider(_ name:String,value:Binding<Double>,range:ClosedRange<Double>,suffix:String="")->some View {
        VStack(spacing:10){HStack{Text(name);Spacer();Text(String(format:"%.2f",value.wrappedValue)+suffix).monospacedDigit().padding(.horizontal,10).padding(.vertical,4).background(Design.field,in:RoundedRectangle(cornerRadius:4))};Slider(value:value,in:range).tint(Design.accent)}
    }
}
