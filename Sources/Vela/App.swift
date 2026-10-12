import AppKit
import SwiftUI
import CLibVLC

@main struct VelaMain {
    @MainActor static func main() {
        let app=NSApplication.shared
        let delegate=AppDelegate()
        app.delegate=delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate){}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var engine:PlayerEngine!
    var window:NSWindow!
    var keyMonitor:Any?
    var commandObserver:Any?
    var normalFrame:NSRect?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let testing=CommandLine.arguments.contains("--engine-test")
        engine=PlayerEngine(testing:testing)
        makeMenu()
        let visible=NSRect(x:0,y:0,width:1280,height:760)
        window=NSWindow(contentRect:visible,styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="Vela";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
        window.backgroundColor=NSColor(calibratedRed:0.106,green:0.106,blue:0.106,alpha:1)
        window.minSize=NSSize(width:1060,height:560);window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:PlayerView(engine:engine).ignoresSafeArea())
        window.center();window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        commandObserver=NotificationCenter.default.addObserver(forName:.velaCommand,object:nil,queue:.main){[weak self] note in
            if note.object as? String == "mini" {MainActor.assumeIsolated{self?.toggleMini()}}
        }
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self,NSApp.keyWindow === self.window, !(self.window.firstResponder is NSTextView), !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else{return event}
            switch event.keyCode {
            case 49:self.engine.togglePlay();return nil
            case 123:if self.engine.isDisc{self.engine.navigateDisc(3)}else{self.engine.skip(-10)};return nil
            case 124:if self.engine.isDisc{self.engine.navigateDisc(4)}else{self.engine.skip(10)};return nil
            case 125:if self.engine.isDisc{self.engine.navigateDisc(2)}else{self.engine.setVolume(max(0,self.engine.volume-5))};return nil
            case 126:if self.engine.isDisc{self.engine.navigateDisc(1)}else{self.engine.setVolume(min(200,self.engine.volume+5))};return nil
            case 36:if self.engine.isDisc{self.engine.navigateDisc(0);return nil};return event
            case 53:if self.window.styleMask.contains(.fullScreen){self.window.toggleFullScreen(nil);return nil};return event
            default:return event
            }
        }
        if testing,let index=CommandLine.arguments.firstIndex(of:"--engine-test"), CommandLine.arguments.indices.contains(index+1) {
            Task {await EngineTests.run(engine:engine,directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))}
        } else {
            let inputs=CommandLine.arguments.dropFirst().filter{!$0.hasPrefix("-")}.map{URL(fileURLWithPath:$0)}
            if !inputs.isEmpty{engine.enqueue(inputs)}
        }
    }
    func application(_ application:NSApplication,open urls:[URL]){engine?.enqueue(urls)}
    func windowWillClose(_ notification:Notification){if let closing=notification.object as? NSWindow,closing===window{NSApp.terminate(nil)}}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationWillTerminate(_ notification:Notification){if let keyMonitor{NSEvent.removeMonitor(keyMonitor)};if let commandObserver{NotificationCenter.default.removeObserver(commandObserver)};engine?.shutdown()}
    private func toggleMini(){
        if window.styleMask.contains(.fullScreen){window.toggleFullScreen(nil);return}
        engine.compactMode.toggle()
        if engine.compactMode {
            normalFrame=window.frame;window.minSize=NSSize(width:420,height:270);window.level = .floating
            window.setContentSize(NSSize(width:480,height:340))
        }else{
            window.level = .normal;window.minSize=NSSize(width:1060,height:560)
            if let normalFrame{window.setFrame(normalFrame,display:true,animate:true)}
        }
    }
    private func makeMenu() {
        let main=NSMenu()
        func submenu(_ name:String,_ items:[(String,String,String)]) {
            let parent=NSMenuItem(title:name,action:nil,keyEquivalent:"");let menu=NSMenu(title:name)
            for (title,key,command) in items {
                if title == "-" {menu.addItem(.separator());continue}
                let item=NSMenuItem(title:title,action:#selector(AppDelegate.command(_:)),keyEquivalent:key);item.target=self;item.representedObject=command
                if command == "play"{item.keyEquivalentModifierMask=[]}
                menu.addItem(item)
            }
            parent.submenu=menu;main.addItem(parent)
        }
        submenu("Vela",[("About Vela","","about"),("Settings…",",","settings"),("-","",""),("Hide Vela","h","hideApp"),("Quit Vela","q","quit")])
        submenu("File",[("Open File(s)…","o","open"),("Open Folder…","","folder"),("Open Network Stream…","n","network"),("Open Capture Source…","","capture"),("Open Disc…","","disc"),("-","",""),("Add Subtitle File…","","subtitle"),("Convert / Export…","","convert"),("Export Playlist…","","exportPlaylist"),("Close Window","w","close")])
        submenu("Tools",[("Stream Media…","","streaming"),("Extensions…","","extensions"),("Casting…","","casting"),("Disc Controls…","","discControls"),("Media Information…","","mediaInfo")])
        submenu("Playback",[("Play / Pause"," ","play"),("Stop",".","stop"),("Previous Item","","previous"),("Next Item","","next"),("-","",""),("Back 10 Seconds","","back"),("Forward 10 Seconds","","forward"),("Jump to Time…","j","jump"),("Normal Speed","","normal"),("Add Bookmark","b","bookmark"),("-","",""),("Start / Stop Recording…","","record")])
        submenu("Audio",[("Mute","m","mute"),("Increase Volume","","volumeUp"),("Decrease Volume","","volumeDown")])
        submenu("Video",[("Full Screen","f","fullscreen"),("Take Snapshot…","","snapshot")])
        submenu("View",[("Queue / Bookmarks / Chapters","l","queue"),("Mini Player","p","mini"),("Hide / Show Controls","\\","hide")])
        submenu("Window",[("Minimize","","minimize"),("Zoom","","zoom")])
        NSApp.mainMenu=main
    }
    @objc private func command(_ sender:NSMenuItem) {
        guard let action=sender.representedObject as? String else{return}
        switch action{
        case "open":engine.openFiles()
        case "folder":engine.openFiles(folder:true)
        case "subtitle":engine.openSubtitle()
        case "play":engine.togglePlay()
        case "stop":engine.stop()
        case "previous":engine.next(backwards:true)
        case "next":engine.next()
        case "back":engine.skip(-10)
        case "forward":engine.skip(10)
        case "normal":engine.setRate(1)
        case "bookmark":engine.addBookmark()
        case "snapshot":engine.snapshot()
        case "exportPlaylist":engine.exportPlaylist()
        case "mute":engine.toggleMute()
        case "volumeUp":engine.setVolume(min(200,engine.volume+5))
        case "volumeDown":engine.setVolume(max(0,engine.volume-5))
        case "fullscreen":window.toggleFullScreen(nil)
        case "minimize":window.miniaturize(nil)
        case "zoom":window.zoom(nil)
        case "mini":toggleMini()
        case "close":NSApp.keyWindow?.close()
        case "hideApp":NSApp.hide(nil)
        case "quit":NSApp.terminate(nil)
        case "about":NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Vela",.applicationVersion:"1.0 • libVLC \(engine.engineVersion)"])
        default:NotificationCenter.default.post(name:.velaCommand,object:action)
        }
    }
}
