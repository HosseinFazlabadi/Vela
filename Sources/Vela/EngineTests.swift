import AppKit
import CLibVLC
import AVFoundation

@MainActor enum EngineTests {
    static func run(engine:PlayerEngine,directory:URL) async {
        var checks:[String:Bool]=[:]
        func wait(_ seconds:Double) async {try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
        func check(_ name:String,_ result:Bool){checks[name]=result;print("\(result ? "PASS" : "FAIL") \(name)");fflush(stdout)}
        engine.setVolume(0)
        for file in ["test.mp4","test.mkv","test.webm","test.avi","test.wav","test.flac","test.mp3","test.ogg"] {
            engine.enqueue([directory.appendingPathComponent(file)])
            var started=false
            for _ in 0..<40 {
                await wait(0.1)
                if libvlc_media_player_is_playing(engine.player) != 0 && libvlc_media_player_get_time(engine.player)>150{started=true;break}
                if libvlc_media_player_get_state(engine.player) == libvlc_Error{break}
            }
            check("play \(file)",started)
            if let media=libvlc_media_player_get_media(engine.player){var stats=libvlc_media_stats_t();libvlc_media_get_stats(media,&stats);check("decode \(file)",stats.i_decoded_audio>0 || stats.i_decoded_video>0)}
            engine.stop()
        }
        engine.enqueue([directory.appendingPathComponent("test.mkv")])
        await wait(1.5);engine.poll()
        check("multiple audio tracks",engine.audioTracks.filter{$0.id >= 0}.count == 2)
        check("embedded subtitles",engine.subtitleTracks.contains{$0.id >= 0})
        check("chapters",engine.chapters.count == 2)
        if let audio=engine.audioTracks.filter({$0.id >= 0}).last {engine.selectAudio(audio.id);check("audio selection",libvlc_audio_get_track(engine.player) == audio.id)}
        if let sub=engine.subtitleTracks.first(where:{$0.id >= 0}) {engine.selectSubtitle(sub.id);check("subtitle selection",libvlc_video_get_spu(engine.player) == sub.id)}
        engine.setAudioDelay(0.25);engine.setSubtitleDelay(-0.5)
        check("audio delay",libvlc_audio_get_delay(engine.player) == 250000)
        check("subtitle delay",libvlc_video_get_spu_delay(engine.player) == -500000)
        engine.togglePlay();await wait(0.3)
        check("pause",libvlc_media_player_get_state(engine.player) == libvlc_Paused)
        let paused=libvlc_media_player_get_time(engine.player);await wait(0.4)
        check("paused clock",abs(libvlc_media_player_get_time(engine.player)-paused)<150)
        engine.seek(4000);await wait(0.3)
        check("seek while paused",abs(libvlc_media_player_get_time(engine.player)-4000)<800)
        engine.togglePlay();await wait(0.3)
        engine.setRate(1.5);check("speed",abs(libvlc_media_player_get_rate(engine.player)-1.5)<0.01)
        engine.setVolume(65);await wait(0.3);check("volume",libvlc_audio_get_volume(engine.player) == 65)
        engine.toggleMute();await wait(0.2);check("mute",libvlc_audio_get_mute(engine.player) != 0)
        engine.toggleMute();engine.setVolume(0)
        engine.setEqualizer("Rock");check("equalizer",engine.eqPreset == "Rock")
        engine.setAspect("4:3");if let ratio=libvlc_video_get_aspect_ratio(engine.player){check("aspect ratio",String(cString:ratio) == "4:3");libvlc_free(ratio)}else{check("aspect ratio",false)}
        engine.brightness=1.1;engine.setAdjustments();check("video adjustments",abs(libvlc_video_get_adjust_float(engine.player,2)-1.1)<0.01)
        engine.addBookmark();check("bookmark",engine.bookmarks.count == 1)
        let snapshot=directory.appendingPathComponent("snapshot.png")
        let result=libvlc_video_take_snapshot(engine.player,0,snapshot.path,0,0)
        await wait(0.5);check("snapshot",result == 0 && FileManager.default.fileExists(atPath:snapshot.path))
        engine.addSubtitle(directory.appendingPathComponent("external.srt"));await wait(0.3)
        check("external subtitles",!engine.externalSubtitles.isEmpty)
        engine.subtitleFont="Menlo";engine.subtitleSize="Large";engine.applyMediaSettings();await wait(0.8)
        check("reconfigure playback engine",libvlc_media_player_is_playing(engine.player) != 0)
        engine.enqueue([URL(string:"http://127.0.0.1:18763/network.mp4")!]);await wait(2)
        check("HTTP playback",libvlc_media_player_is_playing(engine.player) != 0 && engine.time>0)
        engine.enqueue([directory.appendingPathComponent("test.mp4")]);await wait(0.7)
        engine.convert(to:directory.appendingPathComponent("test.mp4"),format:"Video (MP4)")
        check("source overwrite rejected",engine.error?.contains("different")==true && engine.conversionProgress.isEmpty);engine.error=nil
        engine.startStream(protocolName:"HTTP",host:"127.0.0.1",port:18764,path:"/vela",transcode:true)
        await wait(0.7)
        let streamPath=directory.appendingPathComponent("streaming.ts").path
        await Task.detached {let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/curl");task.arguments=["--silent","--max-time","3","http://127.0.0.1:18764/vela","-o",streamPath];try? task.run();task.waitUntilExit()}.value
        check("HTTP streaming output",((try? FileManager.default.attributesOfItem(atPath:streamPath)[.size] as? Int) ?? 0)>1000 && !engine.streamingURL.isEmpty)
        engine.stopOutput();check("stream server stop",engine.streamingURL.isEmpty)
        let output=directory.appendingPathComponent("converted.mp4")
        engine.convert(to:output,format:"Video (MP4)")
        for _ in 0..<150 {await wait(0.1);if engine.conversionProgress == "Export complete"{break}}
        let size=(try? output.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
        check("conversion",size>1000 && engine.conversionProgress == "Export complete")
        engine.enqueue([output]);await wait(1.5)
        check("converted duration",engine.length>9000 && engine.length<11000)
        let wav=directory.appendingPathComponent("converted.wav")
        engine.convert(to:wav,format:"Audio (WAV)")
        for _ in 0..<100{await wait(0.1);if engine.conversionProgress=="Export complete"{break}}
        check("WAV conversion",((try? wav.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)>1000 && engine.conversionProgress=="Export complete")
        engine.enqueue([wav]);await wait(0.7)
        check("WAV export replay",engine.isPlaying && engine.length>9000 && engine.length<11000)
        engine.enqueue([directory.appendingPathComponent("test.mp4")]);await wait(0.5)
        let recording=directory.appendingPathComponent("recording.mkv")
        engine.startRecording(to:recording);await wait(1.2);engine.stopOutput();await wait(0.5)
        let recordedSize=(try? recording.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
        check("recording",recordedSize>1000)
        engine.enqueue([recording]);await wait(0.8)
        check("recorded duration",engine.length>500 && engine.length<5000)
        let playlist=directory.appendingPathComponent("queue.m3u8")
        try! "#EXTM3U\ntest.mp4\ntest.flac\n".write(to:playlist,atomically:true,encoding:.utf8)
        let before=engine.queue.count
        engine.enqueue([playlist],play:false)
        check("playlist import",engine.queue.count == before+2)
        engine.enqueue([directory.appendingPathComponent("test.mp4")]);await wait(1)
        engine.cast(to:UInt64.max);await wait(0.8)
        check("cast unavailable device recovers playback",engine.isPlaying && engine.selectedCast==0)
        engine.error=nil
        engine.cast(to:0);await wait(0.8)
        check("cast local output",engine.isPlaying && engine.selectedCast==0)
        let dvd=URL(string:"dvdnav://"+directory.appendingPathComponent("test-dvd").path)!
        engine.enqueue([dvd]);await wait(1.5);engine.refreshDiscTitles()
        check("DVD authored folder playback",engine.isPlaying)
        check("DVD titles",engine.discTitles.filter{!$0.menu}.count>=2)
        check("DVD chapters",engine.chapters.count>=2)
        if let title=engine.discTitles.last(where:{!$0.menu}){engine.selectDiscTitle(title.id);await wait(0.5);check("DVD title selection",libvlc_media_player_get_title(engine.player)==title.id)}
        engine.navigateDisc(5);await wait(0.3)
        check("DVD navigation dispatch",engine.state != 7)
        engine.stop()
        engine.startRawCapture(engine.captureService.startSynthetic(),title:"Capture Test")
        await wait(1.5)
        check("live synthetic capture playback",engine.isPlaying && engine.time>0)
        let captureRecording=directory.appendingPathComponent("capture-recording.mkv")
        engine.startRecording(to:captureRecording);await wait(2);engine.stopOutput()
        check("capture recording",((try? captureRecording.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)>1000)
        engine.cast(to:UInt64.max);await wait(0.6);engine.poll()
        check("live capture unavailable cast recovers",engine.isPlaying && engine.selectedCast==0)
        engine.error=nil;engine.cast(to:0);await wait(0.6);engine.poll()
        check("live capture local output restart",engine.isPlaying)
        engine.applyMediaSettings();await wait(0.8);engine.poll()
        check("live capture engine reconfiguration",engine.isPlaying)
        engine.stop()
        check("capture stop",libvlc_media_player_get_state(engine.player)==libvlc_Stopped)
        engine.startRawCapture(engine.captureService.startSynthetic(audio:true),title:"Audio Capture Test");await wait(1)
        engine.startRecording(to:directory.appendingPathComponent("capture-audio.mkv"));await wait(2);engine.stopOutput()
        engine.startStream(protocolName:"HTTP",host:"127.0.0.1",port:18764,path:"/capture",transcode:true);await wait(0.7)
        let liveStream=directory.appendingPathComponent("capture-streaming.mkv").path
        let liveReceiver=Process();liveReceiver.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/Export/ffmpeg");liveReceiver.arguments=["-hide_banner","-loglevel","error","-rw_timeout","7000000","-i","http://127.0.0.1:18764/capture","-ss","0.5","-t","2","-map","0","-c","copy","-y",liveStream];try? liveReceiver.run();await Task.detached{liveReceiver.waitUntilExit()}.value
        check("live audio video HTTP delivery",((try? FileManager.default.attributesOfItem(atPath:liveStream)[.size] as? Int) ?? 0)>1000 && liveReceiver.terminationStatus==0)
        engine.stopOutput();engine.stop()
        engine.enqueue([directory.appendingPathComponent("capture-audio.mkv")]);await wait(1);engine.poll()
        check("captured audio and video replay",engine.isPlaying && engine.audioTracks.contains{$0.id>=0} && engine.videoTracks.contains{$0.id>=0})
        engine.stop()
        if let raw=vela_raw_new(640,360,30){let pixels=[UInt8](repeating:120,count:640*360*4);pixels.withUnsafeBytes{_ = vela_raw_push(raw,$0.baseAddress,640*4)};engine.startRawCapture(raw,title:"Static Screen Test");await wait(0.5);engine.startRecording(to:directory.appendingPathComponent("capture-static.mkv"));await wait(1.5);engine.stopOutput();engine.stop();vela_raw_release(raw);engine.enqueue([directory.appendingPathComponent("capture-static.mkv")]);await wait(0.7);check("static screen frame pacing",engine.isPlaying && engine.length>1000)}
        
        engine.enqueue([captureRecording]);await wait(1)
        check("capture recording replay",engine.isPlaying && engine.length>500)
        engine.enqueue([directory.appendingPathComponent("test.mp4")]);await wait(0.5)
        let manager=engine.extensions
        do{
            let id=try manager.install(directory.appendingPathComponent("test-extension.lua"));manager.activate(id,showWindow:false)
            for _ in 0..<50{await wait(0.1);if manager.presentations[id] != nil{break}}
            check("extension install and activation",manager.installed.contains{$0.id==id && $0.enabled})
            check("native extension widgets",manager.presentations[id]?.widgets.count==5)
            if let input=manager.presentations[id]?.widgets.first(where:{$0.kind=="text_input"}){manager.widget(id,input,text:"edited")}
            if let drop=manager.presentations[id]?.widgets.first(where:{$0.kind=="dropdown"}){manager.widget(id,drop,value:2)}
            if let checkBox=manager.presentations[id]?.widgets.first(where:{$0.kind=="checkbox"}){manager.widget(id,checkBox,value:0)}
            if let button=manager.presentations[id]?.widgets.first(where:{$0.kind=="button"}){manager.widget(id,button,click:true)}
            await wait(0.5)
            check("extension native widget callbacks",manager.presentations[id]?.widgets.first(where:{$0.kind=="label"})?.text=="edited:false:2")
            check("extension controls VLC engine",engine.volume==37)
            check("extension native menu",manager.presentations[id]?.menus.first?.text=="Refresh")
            manager.menu(id,1);await wait(0.3)
            check("extension menu callback",manager.presentations[id]?.widgets.first(where:{$0.kind=="label"})?.text=="Menu invoked")
            manager.menu(id,2);await wait(0.3)
            check("extension requested deactivation",!manager.installed.contains{$0.id==id && $0.enabled})
            manager.deactivate(id);check("extension deactivation",!manager.installed.contains{$0.id==id && $0.enabled})
            let vlsub=directory.appendingPathComponent("VLSub.lua")
            if FileManager.default.fileExists(atPath:vlsub.path){let id=try manager.install(vlsub);manager.activate(id,showWindow:false);for _ in 0..<80{await wait(0.1);if manager.presentations[id] != nil{break}};check("VLSub native interface activation",manager.presentations[id]?.error==nil && (manager.presentations[id]?.widgets.count ?? 0)>5);if let error=manager.presentations[id]?.error{print("VLSub: \(error)")};manager.deactivate(id)}
        }catch{check("extension install and activation",false);print(error)}
        do {
            if let current=engine.current{engine.start(current,resume:false)};await wait(0.5)
            let id=try manager.install(directory.appendingPathComponent("api-contract.lua"));manager.activate(id,showWindow:false)
            for _ in 0..<200{await wait(0.1);if (manager.presentations[id]?.widgets.filter{$0.text.hasPrefix("PASS ") || $0.text.hasPrefix("FAIL ")}.count ?? 0)>=15{break}}
            if let result=manager.presentations[id]{for widget in result.widgets where widget.text.hasPrefix("PASS ") || widget.text.hasPrefix("FAIL "){check("extension API "+String(widget.text.dropFirst(5)).components(separatedBy:": ")[0],widget.text.hasPrefix("PASS "));if widget.text.hasPrefix("FAIL "){print(widget.text)}};check("extension expanded layout presentation",result.widgets.contains{$0.text=="Wide extension" && $0.col==16 && $0.row==120 && $0.width==3000 && $0.height==2100});check("extension API execution",result.error==nil && result.widgets.count>=15);if let error=result.error{print(error)}}else{check("extension API execution",false)}
            manager.notify("playing_changed",value:2);manager.notify("meta_changed");await wait(0.3)
            check("extension playing numeric event",manager.presentations[id]?.widgets.contains{$0.text=="EVENT playing number"}==true)
            check("extension VLC state enum",manager.presentations[id]?.widgets.contains{$0.text=="EVENT state 2"}==true)
            check("extension metadata event",manager.presentations[id]?.widgets.contains{$0.text=="EVENT meta"}==true)
            engine.applyMediaSettings();await wait(1);manager.menu(id,1);await wait(0.4)
            check("extension engine rebind",manager.presentations[id]?.widgets.contains{$0.text=="REBIND OK"}==true)
            manager.deactivate(id)
            let compiled=try manager.install(directory.appendingPathComponent("compiled-extension.luac"));manager.activate(compiled,showWindow:false);await wait(0.5);check("VLC bytecode extension",manager.presentations[compiled]?.widgets.first?.text=="BYTECODE OK" && manager.presentations[compiled]?.error==nil);manager.deactivate(compiled)
            let packaged=try manager.install(directory.appendingPathComponent("test-package.vle"));manager.activate(packaged,showWindow:false);for _ in 0..<50{await wait(0.1);if manager.presentations[packaged] != nil{break}}
            check("VLE package and module",manager.presentations[packaged]?.widgets.first?.text=="PACKAGE OK" && manager.presentations[packaged]?.error==nil);manager.deactivate(packaged)
            do{_ = try manager.install(directory.appendingPathComponent("unsafe-package.vle"));check("VLE traversal rejected",false)}catch{check("VLE traversal rejected",true)}
            for file in ["blocked-extension.lua","busy-extension.lua","command-extension.lua"]{await wait(0.5);let baseline=vela_extension_live_count();let cancelled=try manager.install(directory.appendingPathComponent(file));manager.activate(cancelled,showWindow:false);for _ in 0..<50{await wait(0.1);if manager.presentations[cancelled] != nil{break}};manager.deactivate(cancelled);for _ in 0..<30{await wait(0.1);if vela_extension_live_count()==baseline{break}};check("extension cancellation "+file,vela_extension_live_count()==baseline)}
            let trigger=try manager.install(directory.appendingPathComponent("trigger-extension.lua"));manager.activate(trigger,showWindow:false);await wait(0.5);check("trigger-only extension",manager.presentations[trigger]?.widgets.first?.text=="TRIGGER OK");manager.deactivate(trigger)
        }catch{check("extension extended contracts",false);print(error)}
        engine.stop();let libraryItem=MediaItem(url:directory.appendingPathComponent("test.mp4"),displayTitle:"Permanent library item");engine.addToLibrary([libraryItem,libraryItem]);engine.recent=[];engine.saveLibrary()
        check("library independent of history",engine.libraryItems.count==1 && engine.recent.isEmpty)
        let saved=try? Data(contentsOf:engine.storageURL.appendingPathComponent("library.json"));let object=saved.flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any]
        check("library persistence",(object?["items"] as? [[String:Any]])?.count==1)
        engine.playLibraryItem(libraryItem);await wait(0.5);engine.poll();check("library playback",engine.isPlaying && engine.currentID==libraryItem.id)
        if let tree=engine.extensionPlaylist.handle("playlist:get","[\"ml\"]"),let data=tree.data(using:.utf8),let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any]{check("extension real media library",(root["children"] as? [[String:Any]])?.count==1)}else{check("extension real media library",false)}
        for file in ["vlc_speed_controller.lua","vlc_playlist_tracker.lua"]{
            let path=directory.appendingPathComponent(file);guard FileManager.default.fileExists(atPath:path.path)else{continue}
            do{let id=try manager.install(path);manager.activate(id,showWindow:false);for _ in 0..<80{await wait(0.1);if manager.presentations[id] != nil{break}};let model=manager.presentations[id];check("third party activation "+file,model != nil && model?.error==nil && manager.installed.contains{$0.id==id && $0.enabled})
                if file=="vlc_speed_controller.lua"{if let button=model?.widgets.first(where:{$0.kind=="button" && $0.text=="1.50"}){manager.widget(id,button,click:true);await wait(0.3);check("third party speed callback",abs(libvlc_media_player_get_rate(engine.player)-1.5)<0.01)}else{check("third party speed callback",false)};if let settings=model?.widgets.first(where:{$0.kind=="button" && $0.text=="Settings"}){manager.widget(id,settings,click:true);await wait(0.4);check("third party dynamic settings dialog",manager.presentations[id]?.title=="Speed Settings" && manager.presentations[id]?.error==nil)}}else{manager.notify("input_changed");await wait(0.3)}
                if let error=manager.presentations[id]?.error{print("COMPATIBILITY "+file+": "+error)};manager.deactivate(id);await wait(0.5)
                check("third party persistence "+file,FileManager.default.fileExists(atPath:engine.storageURL.appendingPathComponent(file=="vlc_speed_controller.lua" ? "vlcsc":"vlc_playlist_state.json").path))
            }catch{check("third party activation "+file,false);print(error)}
        }
        engine.setVolume(Double.nan);check("nonfinite volume rejected",engine.volume.isFinite)
        engine.setVolume(999);check("volume clamp",engine.volume==200)
        engine.stop()
        let data=try! JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys])
        try! data.write(to:directory.appendingPathComponent("results.json"))
        print("\(checks.values.filter{$0}.count)/\(checks.count) checks passed");fflush(stdout)
        // Terminate through AppKit so the renderer and engine are released in order.
        NSApp.terminate(nil)
    }
}
