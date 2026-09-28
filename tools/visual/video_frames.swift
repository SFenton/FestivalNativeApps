// Extract PNG frames from a screen recording at a fixed rate, with exact timestamps.
//
// Usage: xcrun swift tools/visual/video_frames.swift <video> <out-dir> <fps> <start> <end|-1> <scale>
//
// Frames are named `f<milliseconds, 6 digits>.png` so a directory listing is the
// timeline. `simctl io recordVideo` writes variable-frame-rate H.264 (frames only
// when the screen changes); AVAssetImageGenerator with zero tolerance returns the
// frame on screen at each requested time, which is what frame-stepping needs.
// Used by `python3 tools/pwa_ios.py frames|motion`.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 7,
      let fps = Double(arguments[3]), let start = Double(arguments[4]),
      let requestedEnd = Double(arguments[5]), let scale = Double(arguments[6]), fps > 0
else {
    FileHandle.standardError.write(Data("usage: video_frames.swift <video> <out> <fps> <start> <end|-1> <scale>\n".utf8))
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let semaphore = DispatchSemaphore(value: 0)
var status: Int32 = 0

Task {
    do {
        let duration = try await asset.load(.duration).seconds
        let end = requestedEnd < 0 ? duration : min(requestedEnd, duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            generator.maximumSize = CGSize(width: size.width * scale, height: size.height * scale)
        }
        var time = start
        var count = 0
        while time <= end {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            let name = String(format: "f%06d.png", Int((time * 1000).rounded()))
            let url = output.appendingPathComponent(name)
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            count += 1
            time += 1 / fps
        }
        print("\(count) frames \(String(format: "%.2f", start))-\(String(format: "%.2f", end))s of \(String(format: "%.2f", duration))s")
    } catch {
        FileHandle.standardError.write(Data("video_frames: \(error)\n".utf8))
        status = 1
    }
    semaphore.signal()
}
semaphore.wait()
exit(status)
