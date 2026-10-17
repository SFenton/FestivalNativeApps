#if DEBUG
import UIKit

// PROBE665 (temporary): logs every touch, its hit view and the recognizers that saw it.
final class ZZTouchProbeRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    static var path: String? { ProcessInfo.processInfo.environment["FST_DEBUG_TOUCH_LOG"] }
    static func log(_ s: String) {
        guard let path else { return }
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + s + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8)) }
    }
    static func install() {
        ZZStallSwizzle.install()
        guard path != nil else { return }
        log("install pid=\(ProcessInfo.processInfo.processIdentifier)")
        NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? UIWindow, !(w.gestureRecognizers ?? []).contains(where: { $0 is ZZTouchProbeRecognizer }) else { return }
            let r = ZZTouchProbeRecognizer(target: nil, action: nil)
            r.cancelsTouchesInView = false; r.delaysTouchesBegan = false; r.delaysTouchesEnded = false
            r.delegate = r
            w.addGestureRecognizer(r)
            log("window \(type(of: w)) \(w.frame)")
        }
    }
    private var seen: [UIGestureRecognizer] = []
    private func chain(_ v: UIView?) -> String {
        var out: [String] = []; var v = v; var n = 0
        while let x = v, n < 6 { out.append("\(type(of: x))\(x.isUserInteractionEnabled ? "" : "[noUI]")"); v = x.superview; n += 1 }
        return out.joined(separator: "<")
    }
    private func states() -> String {
        seen.map { "\(type(of: $0))=\($0.state.rawValue)\($0.isEnabled ? "" : "[off]")" }.joined(separator: ",")
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches {
            let p = t.location(in: view)
            seen = t.gestureRecognizers ?? []
            let hit = view?.hitTest(p, with: event)
            Self.log("BEGAN \(p) view=\(chain(t.view)) hit=\(chain(hit)) grs=\(states())")
            if let sv = sequence(first: t.view, next: { $0?.superview }).compactMap({ $0 as? UIScrollView }).first {
                Self.log("  scroll dragging=\(sv.isDragging) decel=\(sv.isDecelerating) tracking=\(sv.isTracking) off=\(sv.contentOffset)")
            }
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { Self.log("MOVED \(t.location(in: view))") }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { Self.log("ENDED \(t.location(in: view)) grs=\(states())") }
        let snapshot = seen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            Self.log("  +0.2 grs=\(snapshot.map { "\(type(of: $0))=\($0.state.rawValue)" }.joined(separator: ","))")
            _ = self
        }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        Self.log("CANCELLED grs=\(states())"); state = .failed
    }
    override func reset() { super.reset() }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

import ObjectiveC
enum ZZStallSwizzle {
    static var ms: Double { Double(ProcessInfo.processInfo.environment["FST_DEBUG_STALL_SWITCH_MS"] ?? "") ?? 0 }
    static func install() {
        guard ms > 0 || ZZTouchProbeRecognizer.path != nil, let a = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let b = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.zz_sendEvent(_:))) else { return }
        method_exchangeImplementations(a, b)
        if let c = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
           let d = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.zz_appSendEvent(_:))) {
            method_exchangeImplementations(c, d)
        }
        ZZTouchProbeRecognizer.log("stall swizzle \(ms)ms")
    }
}
extension UIApplication {
    @objc func zz_appSendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            for t in touches {
                ZZTouchProbeRecognizer.log("APP phase=\(t.phase.rawValue) win=\(t.window.map { "\(type(of: $0))" } ?? "nil") loc=\(t.location(in: nil))")
            }
        }
        zz_appSendEvent(event)
    }
}
extension UIWindow {
    @objc func zz_sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            for t in touches {
                var chain: [String] = []; var v = t.view; var n = 0
                while let x = v, n < 5 { chain.append("\(type(of: x))"); v = x.superview; n += 1 }
                ZZTouchProbeRecognizer.log("SEND phase=\(t.phase.rawValue) win=\(type(of: self)) key=\(isKeyWindow) loc=\(t.location(in: self)) view=\(chain.joined(separator: "<"))")
            }
            for t in touches where t.phase == .began && ZZStallSwizzle.ms > 0 {
                if sequence(first: t.view, next: { $0?.superview }).contains(where: { $0 is UISwitch }) {
                    ZZTouchProbeRecognizer.log("STALL before began \(ZZStallSwizzle.ms)ms")
                    Thread.sleep(forTimeInterval: ZZStallSwizzle.ms / 1000)
                }
            }
        }
        zz_sendEvent(event)
    }
}
#endif
