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
        swizzleAnimationState()
        swizzleTabs()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { flush() }
        }
    }


    nonisolated(unsafe) static var inFlight: [ObjectIdentifier: String] = [:]
    nonisolated(unsafe) static var balance: [ObjectIdentifier: Int] = [:]
    nonisolated(unsafe) static var total = 0

    static func describe(_ object: AnyObject?) -> String {
        guard let a = object as? CAAnimation else { return "nil-animation" }
        return "\(type(of: a)) kp=\((a as? CAPropertyAnimation)?.keyPath ?? "") d=\(a.duration) rep=\(a.repeatCount)"
    }

    static func swizzleAnimationState() {
        guard let cls = NSClassFromString("UIViewAnimationState") else { return write("no UIViewAnimationState") }
        typealias StartFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        typealias StopFn = @convention(c) (AnyObject, Selector, AnyObject?, Bool) -> Void
        let startSel = NSSelectorFromString("animationDidStart:")
        let stopSel = NSSelectorFromString("animationDidStop:finished:")
        if let m = class_getInstanceMethod(cls, startSel) {
            let original = unsafeBitCast(method_getImplementation(m), to: StartFn.self)
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { state, animation in
                let id = ObjectIdentifier(state)
                balance[id, default: 0] += 1
                total += 1
                let all = Thread.callStackSymbols
                let deep = all.contains { $0.contains("FloatingTabBar") }
                let stack = all.dropFirst(1).prefix(deep ? 40 : 12).map { String($0.dropFirst(4).prefix(170)) }
                    .filter { !deep || !($0.contains("block_destroy_helper") || $0.contains("closure_destructor") || $0.contains("swift_memcpy") || $0.contains("libdispatch") || $0.contains("AnimationKit")) }
                    .joined(separator: "\n      ")
                if inFlight[id] == nil {
                    inFlight[id] = describe(animation)
                    write(String(format: "%.3f", Date().timeIntervalSince1970) + " STATE-START \(id) \(describe(animation)) open=\(inFlight.count) total=\(total)\n      \(stack)")
                } else {
                    write(String(format: "%.3f", Date().timeIntervalSince1970) + " STATE-START+ \(id) \(describe(animation)) bal=\(balance[id] ?? 0) total=\(total)")
                }
                original(state, startSel, animation)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        if let m = class_getInstanceMethod(cls, stopSel) {
            let original = unsafeBitCast(method_getImplementation(m), to: StopFn.self)
            let block: @convention(block) (AnyObject, AnyObject?, Bool) -> Void = { state, animation, finished in
                original(state, stopSel, animation, finished)
                let id = ObjectIdentifier(state)
                total -= 1
                balance[id, default: 0] -= 1
                if balance[id] ?? 0 <= 0 { inFlight.removeValue(forKey: id); balance.removeValue(forKey: id) }
                write(String(format: "%.3f", Date().timeIntervalSince1970) + " STATE-STOP \(id) \(describe(animation)) finished=\(finished) open=\(inFlight.count) total=\(total)")
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
    }

    static func ts() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    static func swizzleTabs() {
        typealias SetFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        typealias VoidFn = @convention(c) (AnyObject, Selector) -> Void
        if #available(iOS 18.0, *), let m = class_getInstanceMethod(UITab.self, NSSelectorFromString("setAccessibilityAttributedLabel:")) {
            let original = unsafeBitCast(method_getImplementation(m), to: SetFn.self)
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { tab, value in
                guard #available(iOS 18.0, *), let t = tab as? UITab else { return }
                let old = t.accessibilityAttributedLabel?.string ?? "nil"
                let new = (value as? NSAttributedString)?.string ?? "nil"
                let attrs = (value as? NSAttributedString).map { a -> String in
                    var keys: [String] = []
                    a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { d, _, _ in keys.append(contentsOf: d.keys.map(\.rawValue)) }
                    return keys.joined(separator: ",")
                } ?? ""
                write(ts() + " TAB-AXLABEL id=\(t.identifier) title=\(t.title) old=\(old) new=\(new) same=\(old == new) attrs=\(attrs) eq=\((t.accessibilityAttributedLabel as AnyObject?)?.isEqual(value) ?? false)")
                original(tab, NSSelectorFromString("setAccessibilityAttributedLabel:"), value)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        if let cls = NSClassFromString("_UIFloatingTabBar"), let m = class_getInstanceMethod(cls, NSSelectorFromString("_updatePaginationIfNeeded")) {
            let original = unsafeBitCast(method_getImplementation(m), to: VoidFn.self)
            let block: @convention(block) (AnyObject) -> Void = { bar in
                let v = bar as! UIView
                let before = v.subviews.map { "\(type(of: $0))" }.joined(separator: ",")
                original(bar, NSSelectorFromString("_updatePaginationIfNeeded"))
                let pages = count(v, matching: "PageButton")
                write(ts() + " PAGINATE bounds=\(v.bounds) window=\(v.window != nil) super=\(v.superview.map { "\(type(of: $0))" } ?? "nil") anim=\(UIView.inheritedAnimationDuration) pageButtons=\(pages) items=\(count(v)) size=\(v.traitCollection.preferredContentSizeCategory.rawValue) hsc=\(v.traitCollection.horizontalSizeClass.rawValue) subviewsBefore=[\(before.prefix(200))]")
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        } else { write("no _UIFloatingTabBar pagination") }
    }

    static func count(_ view: UIView, matching name: String) -> Int {
        view.subviews.reduce(0) { $0 + ("\(type(of: $1))".contains(name) ? 1 : 0) + count($1, matching: name) }
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
        counts = [:]
        for (id, d) in inFlight { lines.append("  OPEN \(id) bal=\(balance[id] ?? 0) \(d)") }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                lines.append("  window \(type(of: window)) key=\(window.isKeyWindow) focus=\(String(describing: scene.focusSystem?.focusedItem.map { type(of: $0) }))")
                if let f = scene.focusSystem?.focusedItem as? UIView {
                    var c: [String] = []; var v: UIView? = f
                    while let x = v, c.count < 8 { c.append("\(type(of: x))#\(x.accessibilityIdentifier ?? "")"); v = x.superview }
                    lines.append("    FOCUS " + c.joined(separator: "<"))
                }
                bars(window, into: &lines)
            }
        }
        write(lines.joined(separator: "\n"))
    }

    static func bars(_ view: UIView, into lines: inout [String]) {
        let name = "\(type(of: view))"
        if name.contains("FloatingTabBar") && !name.contains("ItemView") || name == "UITabBar" {
            var hiddenChain: [String] = []; var v: UIView? = view
            while let x = v { if x.isHidden || x.alpha < 0.01 { hiddenChain.append("\(type(of: x))(h=\(x.isHidden) a=\(x.alpha))") }; v = x.superview }
            lines.append("    BAR \(name) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alpha) subviews=\(view.subviews.count) items=\(count(view)) hiddenAncestors=\(hiddenChain)")
        }
        for sub in view.subviews { bars(sub, into: &lines) }
    }

    static func count(_ view: UIView) -> Int {
        view.subviews.reduce(0) { $0 + ("\(type(of: $1))".contains("FloatingTabBarItemView") ? 1 : 0) + count($1) }
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
