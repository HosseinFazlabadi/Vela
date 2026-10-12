import SwiftUI
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CLibVLC

final class ScreenFrames:NSObject,SCStreamOutput,@unchecked Sendable {
    let source:OpaquePointer;let width:Int;let height:Int
    init(source:OpaquePointer,width:Int,height:Int){self.source=source;self.width=width;self.height=height;vela_raw_hold(source)}
    deinit{vela_raw_release(source)}
    func stream(_ stream:SCStream,didOutputSampleBuffer buffer:CMSampleBuffer,of type:SCStreamOutputType){
        if type == .audio{receiveAudio(buffer);return}
        guard type == .screen,CMSampleBufferIsValid(buffer),let image=CMSampleBufferGetImageBuffer(buffer) else{return}
        guard CVPixelBufferGetWidth(image)==width,CVPixelBufferGetHeight(image)==height else{return}
        if let attachments=CMSampleBufferGetSampleAttachmentsArray(buffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],let raw=attachments.first?[.status] as? Int,raw != SCFrameStatus.complete.rawValue{return}
        CVPixelBufferLockBaseAddress(image,.readOnly);defer{CVPixelBufferUnlockBaseAddress(image,.readOnly)}
        if let pixels=CVPixelBufferGetBaseAddress(image){_ = vela_raw_push(source,pixels,CVPixelBufferGetBytesPerRow(image))}
    }
    func receiveAudio(_ sample:CMSampleBuffer){guard CMSampleBufferIsValid(sample),CMSampleBufferDataIsReady(sample),CMSampleBufferGetNumSamples(sample)>0,CMSampleBufferGetNumSamples(sample)<=96000,let description=CMSampleBufferGetFormatDescription(sample),let audio=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(cmAudioFormatDescription:description),frameCapacity:AVAudioFrameCount(CMSampleBufferGetNumSamples(sample)))else{return};audio.frameLength=audio.frameCapacity;guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample,at:0,frameCount:Int32(audio.frameLength),into:audio.mutableAudioBufferList)==noErr else{return};pushAudio(audio)}
    func pushAudio(_ audio:AVAudioPCMBuffer){guard audio.format.sampleRate==48000,audio.format.channelCount==2,let channels=audio.floatChannelData else{return};let count=Int(audio.frameLength);guard count>0 && count<=96000 else{return};var samples=[Float](repeating:0,count:count*2);if audio.format.isInterleaved{samples.withUnsafeMutableBufferPointer{$0.baseAddress!.update(from:channels[0],count:count*2)}}else{for n in 0..<count{samples[n*2]=channels[0][n];samples[n*2+1]=channels[1][n]}};samples.withUnsafeBufferPointer{_ = vela_raw_push_audio(source,$0.baseAddress,count)}}

}
@MainActor final class CaptureService {
    private var stream:SCStream?
    private var frames:ScreenFrames?
    private var source:OpaquePointer?
    private var synthetic:DispatchSourceTimer?
    var displays:[SCDisplay]=[]
    func listDisplays() async throws -> [SCDisplay]{let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true);displays=content.displays;return displays}
    func startScreen(display:SCDisplay,width:Int=1280,height:Int=720,fps:Int=30,captureAudio:Bool=true) async throws -> OpaquePointer {
        stop()
        guard let raw=vela_raw_new(UInt32(width),UInt32(height),Double(fps))else{throw NSError(domain:"Capture",code:1,userInfo:[NSLocalizedDescriptionKey:"Could not allocate capture frames."])}
        if captureAudio && vela_raw_enable_audio(raw) != 0{vela_raw_release(raw);throw NSError(domain:"Capture",code:2,userInfo:[NSLocalizedDescriptionKey:"Could not allocate captured audio."])}
        let config=SCStreamConfiguration();config.capturesAudio=captureAudio;config.sampleRate=48000;config.channelCount=2;config.excludesCurrentProcessAudio=true;config.width=width;config.height=height;config.minimumFrameInterval=CMTime(value:1,timescale:Int32(fps));config.pixelFormat=kCVPixelFormatType_32BGRA;config.queueDepth=3;config.showsCursor=true
        let filter=SCContentFilter(display:display,excludingWindows:[])
        let capture=SCStream(filter:filter,configuration:config,delegate:nil);let receiver=ScreenFrames(source:raw,width:width,height:height)
        do{let handler=DispatchQueue(label:"Vela.ScreenFrames");try capture.addStreamOutput(receiver,type:.screen,sampleHandlerQueue:handler);if captureAudio{try capture.addStreamOutput(receiver,type:.audio,sampleHandlerQueue:handler)};try await capture.startCapture()}
        catch{vela_raw_finish(raw);vela_raw_release(raw);throw error}
        stream=capture;frames=receiver;source=raw;return raw
    }
    func startSynthetic(audio:Bool=false)->OpaquePointer {
        stop();let raw=vela_raw_new(640,360,30)!
        source=raw
        if audio{_ = vela_raw_enable_audio(raw)}
        let timer=DispatchSource.makeTimerSource(queue:DispatchQueue(label:"Vela.TestCapture"))
        let audioReceiver=ScreenFrames(source:raw,width:640,height:360)
        var tick=0;var pixels=[UInt8](repeating:0,count:640*360*4)
        timer.setEventHandler {
            for y in 0..<360 {for x in 0..<640{let p=(y*640+x)*4;pixels[p]=UInt8((x+tick)%256);pixels[p+1]=UInt8(y%256);pixels[p+2]=UInt8((tick*3)%256);pixels[p+3]=255}}
            pixels.withUnsafeBytes{_ = vela_raw_push(raw,$0.baseAddress,640*4)}
            if audio,let sound=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,frameCapacity:1600),let channels=sound.floatChannelData{sound.frameLength=1600;for n in 0..<1600{let value=Float(sin(Double(tick*1600+n)*2*Double.pi*440/48000))*0.15;channels[0][n]=value;channels[1][n]=value};audioReceiver.pushAudio(sound)};tick+=1
        }
        timer.setCancelHandler{vela_raw_release(raw)}
        timer.schedule(deadline:.now(),repeating:1.0/30);timer.resume();synthetic=timer;return raw
    }
    func stop(){
        if let source{vela_raw_finish(source)}
        if let synthetic{synthetic.cancel();self.synthetic=nil;source=nil;return}
        if let stream,let source{
            let receiver=frames
            self.stream=nil;self.frames=nil;self.source=nil
            Task{try? await stream.stopCapture();withExtendedLifetime(receiver){};vela_raw_release(source)}
        }
    }
}

@MainActor struct CaptureView:View {
    @ObservedObject var engine:PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var kind="Camera"
    @State private var camera=""
    @State private var microphone="None"
    @State private var cameras:[AVCaptureDevice]=[]
    @State private var microphones:[AVCaptureDevice]=[]
    @State private var displays:[SCDisplay]=[]
    @State private var displayID:UInt32=0
    @State private var fps=30
    @State private var captureAudio=true
    @State private var busy=false
    @State private var message=""
    var body:some View{
        VStack(alignment:.leading,spacing:22){
            HStack{Text("Capture Source").font(.title2);Spacer();Button{dismiss()}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
            Picker("Source",selection:$kind){ForEach(["Camera","Microphone","Screen","Test Pattern"],id:\.self){Text($0)}}.pickerStyle(.segmented)
            if kind == "Camera" {
                Picker("Video Device",selection:$camera){ForEach(cameras,id:\.uniqueID){Text($0.localizedName).tag($0.uniqueID)}}
                if cameras.isEmpty{Text("No camera is connected.").foregroundStyle(.secondary)}
                audioPicker
            }else if kind == "Microphone"{audioPicker}
            else if kind == "Screen"{
                Button("Choose a Display…") {Task{busy=true;defer{busy=false};do{displays=try await engine.captureService.listDisplays();displayID=displays.first?.displayID ?? 0}catch{message=error.localizedDescription}}}
                Picker("Display",selection:$displayID){ForEach(displays,id:\.displayID){Text("Display \($0.displayID) • \($0.width)×\($0.height)").tag($0.displayID)}}
                Picker("Frame Rate",selection:$fps){ForEach([15,24,30,60],id:\.self){Text("\($0) fps").tag($0)}}
                Toggle("Capture System Audio",isOn:$captureAudio)
                Text("macOS will ask you to allow screen recording. Camera and microphone permission are requested only when you open those sources.").foregroundStyle(.secondary)
            }else{Text("A generated live source tests capture, playback and recording without using your camera, microphone or screen.").foregroundStyle(.secondary)}
            if !message.isEmpty{Text(message).foregroundStyle(.red)}
            HStack{Button("Cancel"){dismiss()};Spacer();if busy{ProgressView().controlSize(.small)};Button("Open Capture"){Task{await open()}}.buttonStyle(.borderedProminent).disabled(busy || (kind == "Camera" && camera.isEmpty) || (kind == "Microphone" && microphone == "None") || (kind == "Screen" && displayID==0))}
        }.padding(28).frame(width:640).tint(Design.accent).onAppear{
            cameras=AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.external,.continuityCamera],mediaType:.video,position:.unspecified).devices
            microphones=AVCaptureDevice.DiscoverySession(deviceTypes:[.microphone,.external],mediaType:.audio,position:.unspecified).devices
            camera=cameras.first?.uniqueID ?? ""
        }
    }
    private var audioPicker:some View{Picker("Microphone",selection:$microphone){Text("None").tag("None");ForEach(microphones,id:\.uniqueID){Text($0.localizedName).tag($0.uniqueID)}}}
    private func open()async{
        busy=true;defer{busy=false}
        if kind == "Test Pattern"{engine.startRawCapture(engine.captureService.startSynthetic(audio:true),title:"Test Pattern");dismiss();return}
        if kind == "Screen",let display=displays.first(where:{$0.displayID==displayID}){
            do{let raw=try await engine.captureService.startScreen(display:display,fps:fps,captureAudio:captureAudio);engine.startRawCapture(raw,title:"Display \(displayID)");dismiss()}catch{message=error.localizedDescription};return
        }
        if kind == "Camera", !(await AVCaptureDevice.requestAccess(for:.video)){message="Camera access was denied. Enable Vela in System Settings → Privacy & Security → Camera.";return}
        if microphone != "None", !(await AVCaptureDevice.requestAccess(for:.audio)){message="Microphone access was denied. Enable Vela in System Settings → Privacy & Security → Microphone.";return}
        let uri=kind == "Microphone" ? "qtsound://\(microphone)" : "avcapture://\(camera)"
        guard let url=URL(string:uri)else{message="Invalid device identifier.";return}
        let item=MediaItem(url:url);engine.queue.append(item)
        engine.start(item,resume:false,extraOptions:kind == "Camera" && microphone != "None" ? [":input-slave=qtsound://\(microphone)"] : [])
        dismiss()
    }
}
