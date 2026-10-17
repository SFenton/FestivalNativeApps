#if DEBUG
import ObjectiveC
import UIKit

// PROBE665 (temporary): logs every CALayer animation the app adds, summarised every 2 s,
// plus a snapshot of finite animations still attached, to FST_DEBUG_ANIM_LOG.
enum ZZAnimProbe {
    nonisolated(unsafe) static var counts: [String: Int] = [:]
    nonisolated(unsafe) static var samples: [String: String] = [:]
    static var path: String? { ProcessInfo.processInfo.environment["FST_DEBUG_ANIM_LOG"] }

    static func install() {
        guard path != nil else { return }
        let original = class_getInstanceMethod(CALayer.self, #selector(CALayer.add(_:forKey:)))!
        let replacement = class_getInstanceMethod(CALayer.self, #selector(CALayer.zz665_add(_:forKey:)))!
        method_exchangeImplementations(original, replacement)
        write("install pid=\(ProcessInfo.processInfo.processIdentifier)")
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { flush() }
        }
    }

    static func owner(_ layer: CALayer) -> String {
        var chain: [String] = []
        var view = layer.delegate as? UIView
        if view == nil { chain.append("layer:\(type(of: layer))") }
        var depth = 0
        while let v = view, depth < 5 {
            chain.append("\(type(of: v))")
            view = v.superview
            depth += 1
        }
        return chain.joined(separator: "<")
    }

    static func record(_ animation: CAAnimation, key: String?, layer: CALayer) {
        let id = "\(owner(layer)) key=\(key ?? "nil") \(type(of: animation)) kp=\((animation as? CAPropertyAnimation)?.keyPath ?? "") d=\(animation.duration) rep=\(animation.repeatCount)"
        counts[id, default: 0] += 1
        if samples[id] == nil {
            samples[id] = "frame=\(layer.frame) speed=\(layer.speed) begin=\(animation.beginTime) removed=\(animation.isRemovedOnCompletion) delegate=\(animation.delegate.map { "\(type(of: $0))" } ?? "-")"
        }
    }

    @MainActor static func flush() {
        var lines = [String(format: "--- %.3f adds in 2s: %d", Date().timeIntervalSince1970, counts.values.reduce(0, +))]
        for (id, n) in counts.sorted(by: { $0.value > $1.value }).prefix(25) {
            lines.append("  ADD x\(n) \(id) \(samples[id] ?? "")")
        }
        counts = [:]
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                lines.append("  window \(type(of: window)) key=\(window.isKeyWindow) focus=\(String(describing: scene.focusSystem?.focusedItem.map { type(of: $0) }))")
                walk(window.layer, into: &lines)
            }
        }
        write(lines.joined(separator: "\n"))
    }

    static func walk(_ layer: CALayer, into lines: inout [String]) {
        for key in layer.animationKeys() ?? [] {
            guard let a = layer.animation(forKey: key), a.duration.isFinite, a.repeatCount.isFinite else { continue }
            lines.append("    LIVE \(owner(layer)) key=\(key) \(type(of: a)) kp=\((a as? CAPropertyAnimation)?.keyPath ?? "") d=\(a.duration) rep=\(a.repeatCount) begin=\(a.beginTime) now=\(CACurrentMediaTime())")
        }
        for sub in layer.sublayers ?? [] { walk(sub, into: &lines) }
    }

    static func write(_ text: String) {
        guard let path else { return }
        let data = Data((text + "\n").utf8)
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); h.closeFile() }
        else { FileManager.default.createFile(atPath: path, contents: data) }
    }
}

extension CALayer {
    @objc func zz665_add(_ animation: CAAnimation, forKey key: String?) {
        ZZAnimProbe.record(animation, key: key, layer: self)
        zz665_add(animation, forKey: key)
    }
}
#endif
