import Foundation
import Darwin

@MainActor final class MediaExportJob {
    let process=Process()
    let output:URL
    let recording:Bool
    let duration:Int64
    let scratch:URL
    let progress:URL
    let log:URL
    private var logHandle:FileHandle?
    private(set)var stopped=false
    init(input:URL,output:URL,audioOnly:Bool,recording:Bool,start:Int64,duration:Int64,storage:URL)throws{
        self.output=output;self.recording=recording;self.duration=duration
        scratch=storage.appendingPathComponent("export-jobs/"+UUID().uuidString)
        try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
        progress=scratch.appendingPathComponent("progress");log=scratch.appendingPathComponent("errors")
        FileManager.default.createFile(atPath:log.path,contents:nil)
        logHandle=try FileHandle(forWritingTo:log)
        process.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/Export/ffmpeg")
        var args=["-hide_banner","-loglevel","error","-nostdin","-y","-progress",progress.path,"-nostats"]
        if recording{args.append("-re");if input.isFileURL && start>0{args += ["-ss",String(Double(start)/1000)]}}
        args += ["-i",input.isFileURL ? input.path:input.absoluteString]
        if audioOnly{args += ["-vn","-c:a","pcm_s16le","-f","wav"]}
        else{args += ["-map","0:v:0?","-map","0:a:0?","-c:v","libx264","-preset","veryfast","-crf","20","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k"]
            if recording{args += ["-f","matroska"]}else{args += ["-movflags","+faststart","-f","mp4"]}}
        args.append(output.path);process.arguments=args;process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=logHandle
        do{try process.run()}catch{try? logHandle?.close();try? FileManager.default.removeItem(at:scratch);throw error}
    }
    func stop(){guard process.isRunning else{return};stopped=true;kill(process.processIdentifier,SIGINT)}
    var elapsed:Int64{guard let data=try? Data(contentsOf:progress),let text=String(data:data.suffix(8192),encoding:.utf8)else{return 0};return text.split(separator:"\n").last(where:{$0.hasPrefix("out_time_us=")}).flatMap{Int64($0.dropFirst(12))}.map{$0/1000} ?? 0}
    func finish()->String?{
        try? logHandle?.close();logHandle=nil
        let size=(try? output.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
        if size>0 && (process.terminationStatus==0 || (stopped && elapsed>0 && (process.terminationStatus==255 || process.terminationStatus==SIGINT))){try? FileManager.default.removeItem(at:scratch);return nil}
        let data=(try? Data(contentsOf:log)) ?? Data();let message=String(decoding:data.suffix(2048),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        try? FileManager.default.removeItem(at:scratch)
        return message.isEmpty ? "The media export did not produce a usable file.":message
    }
}
