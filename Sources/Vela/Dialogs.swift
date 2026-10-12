import SwiftUI
import AppKit

@MainActor struct NetworkView: View {
    @ObservedObject var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var urls = ""
    @State private var name = ""
    @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack{Text("Open Network Stream").font(.title3);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
            Text("Network URL").font(.headline)
            Text("Enter one stream URL per line. HTTP, HTTPS, RTSP, RTMP, UDP and other VLC inputs are supported.").foregroundStyle(.secondary)
            TextEditor(text:$urls).font(.system(.body,design:.monospaced)).scrollContentBackground(.hidden).padding(12).background(Design.field,in:RoundedRectangle(cornerRadius:8)).frame(height:170)
            TextField("Playlist name (optional)",text:$name).textFieldStyle(.roundedBorder)
            if !error.isEmpty{Text(error).foregroundStyle(.red)}
            HStack{Button("Cancel"){dismiss()};Spacer();Button("Open"){open()}.buttonStyle(.borderedProminent).disabled(urls.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        }.padding(28).frame(width:620).background(Design.background).tint(Design.accent).foregroundStyle(Design.foreground)
    }
    private func open(){
        let lines=urls.split(whereSeparator:\.isNewline).map{String($0).trimmingCharacters(in:.whitespaces)}
        let parsed=lines.compactMap{URL(string:$0)}
        guard parsed.count == lines.count,parsed.allSatisfy({$0.scheme != nil})else{error="Enter complete URLs, including the protocol.";return}
        engine.enqueue(parsed)
        if !name.isEmpty{engine.playlists.append(SavedPlaylist(name:name,items:parsed.map{MediaItem(url:$0)}));engine.saveLibrary()}
        dismiss()
    }
}

@MainActor struct ConvertView: View {
    @ObservedObject var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var format="Video (MP4)"
    var body: some View {
        VStack(alignment:.leading,spacing:24){
            Text("Convert / Export").font(.title2)
            Text(engine.current?.title ?? "Open media first").lineLimit(2).foregroundStyle(.secondary)
            Picker("Output Format",selection:$format){Text("Video (MP4)").tag("Video (MP4)");Text("Audio (WAV)").tag("Audio (WAV)")}
            Text("Conversion runs separately from playback.").foregroundStyle(.secondary)
            HStack{Button("Cancel"){dismiss()};Spacer();Button("Choose Destination…"){
                let panel=NSSavePanel();panel.nameFieldStringValue=format == "Audio (WAV)" ? "Converted.wav" : "Converted.mp4"
                if panel.runModal() == .OK,let url=panel.url{engine.convert(to:url,format:format);dismiss()}
            }.buttonStyle(.borderedProminent).disabled(!engine.hasMedia)}
        }.padding(28).frame(width:500).tint(Design.accent)
    }
}

@MainActor struct SettingsView: View {
    @ObservedObject var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var category="General"
    let categories=["General","Playback","Video","Audio","Subtitles","Network","Advanced"]
    var body: some View {
        HStack(spacing:0){
            List(categories,id:\.self,selection:$category){Text($0).padding(.vertical,8)}.listStyle(.sidebar).frame(width:180)
            VStack(alignment:.leading,spacing:24){
                HStack{Text(category+" Settings").font(.title2);Spacer();Button{engine.saveLibrary();dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
                Form {
                    switch category{
                    case "General":
                        Section("Library & Privacy"){
                            Toggle("Keep recently opened media",isOn:$engine.keepHistory)
                            Button("Clear Recent History"){engine.recent=[];engine.saveLibrary()}
                            Text("Library and bookmarks stay on this Mac.").foregroundStyle(.secondary)
                        }
                        Section("Engine"){LabeledContent("VLC version",value:engine.engineVersion);LabeledContent("App version",value:"1.0");Text("The VLC runtime is included in Vela.").foregroundStyle(.secondary)}
                    case "Playback":
                        Toggle("Resume where I left off",isOn:$engine.rememberPosition)
                        Toggle("Shuffle queue",isOn:$engine.shuffle)
                        Picker("Repeat",selection:$engine.repeatMode){ForEach(RepeatMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                        HStack{Text("Playback Speed");Slider(value:Binding(get:{engine.rate},set:{engine.setRate($0)}),in:0.25...4);Text(String(format:"%.2f×",engine.rate)).monospacedDigit()}
                    case "Video":
                        Picker("Aspect Ratio",selection:Binding(get:{engine.aspect},set:{engine.setAspect($0)})){ForEach(["Default","16:9","4:3","1:1","16:10","2.35:1"],id:\.self){Text($0)}}
                        Picker("Crop",selection:Binding(get:{engine.crop},set:{engine.setCrop($0)})){ForEach(["None","16:9","4:3","1:1","16:10","2.35:1"],id:\.self){Text($0)}}
                        Button("Take Snapshot…"){engine.snapshot()}.disabled(!engine.hasMedia)
                    case "Audio":
                        Slider(value:Binding(get:{engine.volume},set:{engine.setVolume($0)}),in:0...200){Text("Volume")}
                        Picker("Equalizer",selection:Binding(get:{engine.eqPreset},set:{engine.setEqualizer($0)})){Text("Disabled").tag("Disabled");Text("Custom").tag("Custom");ForEach(engine.equalizerPresets,id:\.self){Text($0)}}
                        HStack{Text("Audio Delay (seconds)");TextField("Delay",value:Binding(get:{engine.audioDelay},set:{engine.setAudioDelay($0)}),format:.number).frame(width:100)}
                    case "Subtitles":
                        TextField("Font",text:$engine.subtitleFont)
                        Picker("Text Size",selection:$engine.subtitleSize){ForEach(["Small","Normal","Large","Extra Large"],id:\.self){Text($0)}}
                        HStack{Text("Subtitle Delay (seconds)");TextField("Delay",value:Binding(get:{engine.subtitleDelay},set:{engine.setSubtitleDelay($0)}),format:.number).frame(width:100)}
                        Button("Add Subtitle File…"){engine.openSubtitle()}.disabled(!engine.hasMedia)
                        Button("Apply Font & Reopen Media"){engine.applyMediaSettings()}.disabled(!engine.hasMedia)
                    case "Network":
                        HStack{Text("Network Cache (ms)");TextField("Milliseconds",value:$engine.networkCache,format:.number).frame(width:120)}
                        Text("Cache changes apply to the next input. Higher values can help unstable streams.").foregroundStyle(.secondary)
                    default:
                        Text("VLC Media Options").font(.headline)
                        Text("One media option per line, for example :avcodec-hw=none or :file-caching=1000. Options apply when the media is reopened.").foregroundStyle(.secondary)
                        TextEditor(text:$engine.advancedOptions).font(.system(.body,design:.monospaced)).frame(height:150)
                        Button("Apply & Reopen Media"){engine.applyMediaSettings()}.disabled(!engine.hasMedia)
                    }
                }.formStyle(.grouped)
                Spacer(minLength:0)
            }.padding(24).frame(maxWidth:.infinity)
        }.frame(width:820,height:560).tint(Design.accent).onDisappear{engine.saveLibrary()}
    }
}
