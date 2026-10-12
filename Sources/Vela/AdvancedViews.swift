import SwiftUI
import AppKit
import CLibVLC

@MainActor struct DiscView:View{
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss)private var dismiss
    @State private var type="DVD"
    @State private var path=""
    @State private var title=0
    @State private var chapter=0
    @State private var menus=true
    @State private var message=""
    var body:some View{VStack(alignment:.leading,spacing:22){HStack{Text("Open Disc").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
        Picker("Disc Type",selection:$type){ForEach(["DVD","Blu-ray","Audio CD","Video CD"],id:\.self){Text($0)}}.pickerStyle(.segmented)
        HStack{TextField("Mounted disc, VIDEO_TS folder, or image path",text:$path).textFieldStyle(.roundedBorder);Button("Choose…"){let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=true;if panel.runModal() == .OK{path=panel.url?.path ?? ""}}}
        if type == "DVD"{Toggle("Use DVD menus",isOn:$menus)}
        HStack{Stepper("Title: \(title == 0 ? "Automatic" : String(title))",value:$title,in:0...999);Stepper("Chapter: \(chapter == 0 ? "Automatic" : String(chapter))",value:$chapter,in:0...999)}
        if !message.isEmpty{Text(message).foregroundStyle(.red)}
        Text("Mounted discs and unencrypted disc folders/images can be opened. Disc menu navigation uses the arrow keys and Return.").foregroundStyle(.secondary)
        HStack{Button("Cancel"){dismiss()};Spacer();Button("Open Disc"){open()}.buttonStyle(.borderedProminent).disabled(path.isEmpty)}
    }.padding(28).frame(width:680).tint(Design.accent)}
    private func open(){guard FileManager.default.fileExists(atPath:path)else{message="The disc path does not exist.";return};let scheme=type == "DVD" ? (menus ? "dvdnav" : "dvd") : (type == "Blu-ray" ? "bluray" : (type == "Audio CD" ? "cdda" : "vcd"));let suffix=(title>0 || chapter>0) ? "#\(title):\(chapter)" : "";guard let url=URL(string:scheme+"://"+(path.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed) ?? path)+suffix)else{message="Invalid disc path.";return};engine.enqueue([url]);dismiss()}
}
@MainActor struct DiscControlsView:View{
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss)private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:22){HStack{Text("Disc Controls").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
        if !engine.isDisc{Text("Open a disc to use its menu and titles.").foregroundStyle(.secondary)}
        HStack{Button("Root / Popup Menu"){engine.navigateDisc(5)};Button("Select"){engine.navigateDisc(0)}}.disabled(!engine.isDisc)
        HStack{ForEach([(1,"↑"),(3,"←"),(2,"↓"),(4,"→")],id:\.0){direction,label in Button(label){engine.navigateDisc(UInt32(direction))}.frame(width:50)}}.disabled(!engine.isDisc)
        Picker("Title",selection:Binding(get:{engine.discTitle},set:{engine.selectDiscTitle($0)})){ForEach(engine.discTitles){t in Text(t.name+(t.menu ? " (Menu)" : "")+" • "+PlayerEngine.timestamp(t.duration)).tag(t.id)}}
        List(engine.chapters){c in Button{engine.selectChapter(c.id)}label:{HStack{Text(c.name);Spacer();Text(PlayerEngine.timestamp(c.time))}}.buttonStyle(.plain)}
    }.padding(24).frame(width:620,height:500).tint(Design.accent)}
}
@MainActor struct CastingView:View{
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss)private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:20){HStack{Text("Casting").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
        Text("Select a VLC-compatible renderer on the same local network. Device discovery starts only when you press Scan.").foregroundStyle(.secondary)
        Button("This Mac\(engine.selectedCast == 0 ? " ✓" : "")"){engine.cast(to:0)}
        List(engine.castDevices){device in HStack{VStack(alignment:.leading){Text(device.name);Text(device.type).font(.caption).foregroundStyle(.secondary)};Spacer();Button(engine.selectedCast == device.id ? "Connected" : "Connect"){engine.cast(to:device.id)}.disabled(!engine.hasMedia)}}
        if engine.scanningCast && engine.castDevices.isEmpty{HStack{ProgressView().controlSize(.small);Text("Searching… No devices found yet.").foregroundStyle(.secondary)}}
        HStack{Button(engine.scanningCast ? "Stop Scan" : "Scan for Devices"){if engine.scanningCast{engine.stopCastScan()}else{engine.scanCastDevices()}};Spacer();Button("Done"){dismiss()}}
    }.padding(24).frame(width:640,height:460).tint(Design.accent)}
}
@MainActor struct MediaInfoView:View{
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss)private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:20){HStack{Text("Media Information").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)};Text(engine.current?.title ?? "No media opened").font(.headline);Text(engine.current?.url.absoluteString ?? "").font(.caption).textSelection(.enabled)
        Form{ForEach(engine.currentMetadata().sorted(by:{$0.key<$1.key}),id:\.key){key,value in LabeledContent(key.capitalized){Text(value).textSelection(.enabled)}};LabeledContent("Duration",value:PlayerEngine.timestamp(engine.length));LabeledContent("Engine",value:engine.engineVersion)}.formStyle(.grouped)
        Text(engine.statistics).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
    }.padding(24).frame(width:680,height:560)}
}

@MainActor struct StreamingView:View{
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss)private var dismiss
    @State private var protocolName="HTTP"
    @State private var host="127.0.0.1"
    @State private var port=8090
    @State private var path="/vela"
    @State private var transcode=true
    var body:some View{VStack(alignment:.leading,spacing:20){HStack{Text("Stream Media").font(.title2);Spacer();Button("Done"){dismiss()}}
        Text("Broadcast the current media with VLC’s streaming engine. For HTTP, the host is the address to listen on; use 0.0.0.0 to share on your local network. For UDP/RTP, enter the receiving device’s address.").foregroundStyle(.secondary)
        Picker("Protocol",selection:$protocolName){ForEach(["HTTP","UDP","RTP"],id:\.self){Text($0)}}.pickerStyle(.segmented)
        TextField("Host",text:$host).textFieldStyle(.roundedBorder)
        HStack{Text("Port");TextField("Port",value:$port,format:.number);if protocolName=="HTTP"{TextField("Path",text:$path)}}.textFieldStyle(.roundedBorder)
        Toggle("Convert to MPEG-4 / MPEG audio for compatibility",isOn:$transcode)
        if !engine.streamingURL.isEmpty{Text(engine.streamingURL).textSelection(.enabled);Button("Stop Streaming"){engine.stopOutput()}}
        if let error=engine.error{Text(error).foregroundStyle(.red)}
        HStack{Spacer();Button("Start Streaming"){engine.startStream(protocolName:protocolName,host:host,port:port,path:path,transcode:transcode)}.buttonStyle(.borderedProminent).disabled(!engine.hasMedia)}
    }.padding(24).frame(width:660).tint(Design.accent)}
}
