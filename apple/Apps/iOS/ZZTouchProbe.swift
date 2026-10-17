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
        ZZAnimDump.start()
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
            if let sw = sequence(first: t.view, next: { $0?.superview }).compactMap({ $0 as? UISwitch }).first {
                ZZSwitchProbe.began(sw)
            }
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
// PROBE665 (temporary): a UISwitch press: its recognizers, their state changes, its
// layers' animations and main run-loop gaps over the next 600 ms.
@MainActor
final class ZZSwitchProbe: NSObject {
    static let shared = ZZSwitchProbe()
    static var stallMs: Double { Double(ProcessInfo.processInfo.environment["FST_DEBUG_STALL_AFTER_BEGAN_MS"] ?? "") ?? 0 }
    private var observer: CFRunLoopObserver?
    private var last: CFAbsoluteTime = 0
    private var lastActivity: CFRunLoopActivity = .entry
    private var until: CFAbsoluteTime = 0
    private var hooked = Set<ObjectIdentifier>()
    static func began(_ sw: UISwitch) { shared.start(sw) }
    private func start(_ sw: UISwitch) {
        var lines: [String] = ["SWITCH on=\(sw.isOn) enabled=\(sw.isEnabled) ui=\(sw.isUserInteractionEnabled) tracking=\(sw.isTracking) style=\(sw.style.rawValue)"]
        var views: [UIView] = [sw]
        var i = 0
        while i < views.count { views.append(contentsOf: views[i].subviews); i += 1 }
        for v in views {
            for g in v.gestureRecognizers ?? [] {
                var d = "  GR \(type(of: g)) on \(type(of: v)) state=\(g.state.rawValue) en=\(g.isEnabled) del=\(g.delegate.map { "\(type(of: $0))" } ?? "-") cancels=\(g.cancelsTouchesInView) delaysB=\(g.delaysTouchesBegan)"
                if let lp = g as? UILongPressGestureRecognizer { d += " minDur=\(lp.minimumPressDuration) move=\(lp.allowableMovement)" }
                lines.append(d)
                if !hooked.contains(ObjectIdentifier(g)) {
                    hooked.insert(ObjectIdentifier(g))
                    g.addTarget(self, action: #selector(fired(_:)))
                }
            }
            if let keys = v.layer.animationKeys(), !keys.isEmpty {
                lines.append("  ANIM \(type(of: v)) \(keys.map { k in "\(k):\(v.layer.animation(forKey: k).map { "\($0.duration)/\($0.beginTime)" } ?? "")" })")
            }
            for sub in v.layer.sublayers ?? [] where !(sub.animationKeys() ?? []).isEmpty {
                lines.append("  SUBANIM \(type(of: sub)) of \(type(of: v)) \(sub.animationKeys() ?? [])")
            }
        }
        lines.append("  now=\(CACurrentMediaTime()) layerTime=\(sw.layer.convertTime(CACurrentMediaTime(), from: nil)) speed=\(sw.layer.speed) winSpeed=\(sw.window?.layer.speed ?? -1)")
        ZZTouchProbeRecognizer.log(lines.joined(separator: "\n"))
        last = CFAbsoluteTimeGetCurrent()
        until = last + 0.6
        if observer == nil {
            let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.allActivities.rawValue, true, 0) { [weak self] _, activity in
                MainActor.assumeIsolated { self?.tick(activity) }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
            observer = obs
        }
        if Self.stallMs > 0 {
            let ms = Self.stallMs
            DispatchQueue.main.async {
                ZZTouchProbeRecognizer.log("STALL after began \(ms)ms")
                Thread.sleep(forTimeInterval: ms / 1000)
            }
        }
    }
    private func tick(_ activity: CFRunLoopActivity) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now <= until else { return }
        let gap = (now - last) * 1000
        if gap > 6 && lastActivity != .beforeWaiting {
            ZZTouchProbeRecognizer.log("  RLBUSY \(Int(gap))ms between activity=\(lastActivity.rawValue) and \(activity.rawValue)")
        }
        last = now
        lastActivity = activity
    }
    @objc private func fired(_ g: UIGestureRecognizer) {
        ZZTouchProbeRecognizer.log("  FIRED \(type(of: g)) state=\(g.state.rawValue)")
    }
}

// PROBE665 (temporary): logs every layer with running animations, every 4 s.
@MainActor
enum ZZAnimDump {
    static func start() {
        guard let path = ProcessInfo.processInfo.environment["FST_DEBUG_ANIM_LOG"] else { return }
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { dump(path) }
        }
    }
    static func dump(_ path: String) {
        var lines: [String] = [String(format: "--- %.3f", Date().timeIntervalSince1970)]
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows {
                lines.append("window \(type(of: w)) key=\(w.isKeyWindow) hidden=\(w.isHidden) focus=\(String(describing: w.windowScene?.focusSystem?.focusedItem.map { type(of: $0) }))")
                walk(w.layer, depth: 0, into: &lines)
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile() }
        else { FileManager.default.createFile(atPath: path, contents: Data(text.utf8)) }
    }
    static func walk(_ layer: CALayer, depth: Int, into lines: inout [String]) {
        if let keys = layer.animationKeys(), !keys.isEmpty {
            let owner = layer.delegate.map { "\(type(of: $0))" } ?? "-"
            let desc = keys.prefix(6).map { k -> String in
                guard let a = layer.animation(forKey: k) else { return k }
                return "\(k)[\(type(of: a)) d=\(a.duration) rep=\(a.repeatCount) kp=\((a as? CAPropertyAnimation)?.keyPath ?? "")]"
            }.joined(separator: " ")
            var chain: [String] = []
            var v = layer.delegate as? UIView; var n = 0
            while let x = v?.superview, n < 4 { chain.append("\(type(of: x))"); v = x; n += 1 }
            lines.append("  d\(depth) \(type(of: layer)) owner=\(owner) up=\(chain.joined(separator: "<")) frame=\(layer.frame) \(desc)")
        }
        for sub in layer.sublayers ?? [] { walk(sub, depth: depth + 1, into: &lines) }
    }
}
#endif
