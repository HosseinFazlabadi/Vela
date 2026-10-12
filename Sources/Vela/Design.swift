import SwiftUI
import AppKit

enum Design {
    static let background = Color("DarkBGA3")
    static let panel = Color("DarkBGB1")
    static let field = Color("DarkBGB2")
    static let accent = Color("DarkAccentMain")
    static let accentBackground = Color("DarkBGAccentBright")
    static let foreground = Color("DarkFG1")
    static let secondary = Color("DarkFGA3")
    static let divider = Color("DarkDividerDim")
    static func font(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

struct DesignIcon: View {
    let file: String
    private static let symbols:[String:String] = [
        "d7959.svg":"ellipsis", "b130a.svg":"sidebar.left", "cf6e1.svg":"folder",
        "d41b8.svg":"arrow.up.left.and.arrow.down.right", "1f761.svg":"backward.end.fill",
        "617e8.svg":"forward.end.fill", "24411.svg":"pause.fill", "4ecaf.svg":"play.fill",
        "bf521.svg":"speaker.wave.2", "432a4.svg":"waveform", "3ffd5.svg":"captions.bubble",
        "e80b5.svg":"gearshape", "0eda2.svg":"list.bullet", "27471.svg":"clock",
        "b610e.svg":"list.bullet", "c9326.svg":"network", "50e8b.svg":"music.note.list",
        "1b0f7.svg":"gearshape", "bfdda.svg":"plus"
    ]
    private static func menuMark(_ url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        // AppKit menus use the image's intrinsic size rather than its SwiftUI frame.
        image.size = NSSize(width: 24, height: 24)
        return image
    }
    var body:some View{Group{if file=="vela-mark.png",let url=Bundle.main.url(forResource:"vela-mark",withExtension:"png",subdirectory:"Assets"),let mark=Self.menuMark(url){Image(nsImage:mark).resizable().scaledToFit().frame(width:24,height:24)}else{Image(systemName:Self.symbols[file] ?? "circle").font(.system(size:18,weight:.medium)).frame(width:24,height:24)}}.accessibilityHidden(true)}

}

struct IconButton: View {
    let file: String
    let title: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { DesignIcon(file: file).padding(4).background(active ? Design.accentBackground : .clear, in: RoundedRectangle(cornerRadius: 4)) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

struct VelaButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Design.font()).foregroundStyle(prominent ? Color.black : Design.foreground)
            .padding(.horizontal,16).padding(.vertical,8)
            .background(prominent ? Design.accent : Design.field, in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SeekBar: View {
    var value: Double
    var enabled = true
    let onChange: (Double) -> Void
    @State private var hover = false
    var body: some View {
        GeometryReader { proxy in
            let width = max(1,proxy.size.width-4)
            ZStack(alignment:.leading) {
                RoundedRectangle(cornerRadius:6).fill(Design.field)
                RoundedRectangle(cornerRadius:4).fill(Design.accentBackground).frame(width: max(0,width*min(1,max(0,value)))).padding(2)
                RoundedRectangle(cornerRadius:4).fill(Design.accent).frame(width:8,height:24).offset(x:max(2,min(width-6,width*value)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { if enabled { onChange(min(1,max(0,($0.location.x-2)/width))) } })
            .opacity(enabled ? 1 : 0.5)
            .accessibilityElement().accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(value*100)) percent")
            .accessibilityAdjustableAction { direction in if enabled { onChange(min(1,max(0,value + (direction == .increment ? 0.01 : -0.01)))) } }
        }.frame(height:28)
    }
}

struct VolumeControl: View {
    @ObservedObject var engine: PlayerEngine
    var body: some View {
        HStack(spacing:8) {
            IconButton(file:"bf521.svg",title:engine.muted ? "Unmute" : "Mute",active:engine.muted) { engine.toggleMute() }
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    Capsule().fill(Design.field).frame(height:6)
                    Capsule().fill(Design.accent).frame(width:proxy.size.width*min(1,max(0,engine.muted ? 0:engine.volume/200)),height:6)
                }.frame(maxHeight:.infinity)

                .contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { engine.setVolume(min(200,max(0,$0.location.x/proxy.size.width*200))) })
                .accessibilityElement().accessibilityLabel("Volume").accessibilityValue("\(Int(engine.volume)) percent")
                .accessibilityAdjustableAction { engine.setVolume(min(200,max(0,engine.volume + ($0 == .increment ? 5 : -5)))) }
            }.frame(width:89,height:28).help("Volume \(Int(engine.volume))%")
        }
    }
}

struct VideoSurface: NSViewRepresentable {
    let engine: PlayerEngine
    func makeNSView(context: Context) -> NSView { engine.videoView }
    func updateNSView(_ nsView: NSView, context: Context) { }
}
