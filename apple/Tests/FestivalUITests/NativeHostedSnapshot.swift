#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import FestivalUI

// MARK: - Hosting

/// Root wrapper every `nativeHostedView` installs around the screen under test.
///
/// Any **tinted** Liquid Glass (`Glass.regular.tint(_)`, which every
/// `festivalGlass(.card/.overlay)` surface uses on macOS 26+) makes the *entire*
/// `NSHostingView` capture fully transparent through both `cacheDisplay` and
/// `CALayer.render(in:)` — backgrounds and text included, whether or not the
/// host has a window. Untinted, shaped, interactive and container glass capture
/// normally. The wrapper therefore forces the product's own Reduce Transparency
/// fallback (the same branch as Settings' Increase Contrast / Less Transparency),
/// whatever `defaultAppStorage` a test injects further down.
struct NativeHostedRoot<Content: View>: View {
    /// The screen under test.
    let content: Content
    /// Whether to force the deterministic glass fallback (see type docs).
    let forceGlassFallback: Bool

    var body: some View {
        // Captures are synchronous: never let `festivalFadeIn` leave content mid-fade.
        Group {
            if forceGlassFallback {
                content.environment(\._accessibilityReduceTransparency, true)
            } else {
                content
            }
        }
        .environment(\.festivalFadeInEnabled, false)
    }
}

/// The realized accessibility element with `identifier` under `host`, if any.
///
/// - Parameters:
///   - identifier: The element's accessibility identifier.
///   - host: The window's hosting view (call `nativeHostedEnableAccessibility()` first).
/// - Returns: The element, or nil when no realized element has the identifier.
@MainActor
func nativeHostedAccessibilityElement(_ identifier: String, in host: NSView) -> NSObject? {
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) -> NSObject? {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return nil }
        if read(object, "accessibilityIdentifier") as? String == identifier { return object }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            if let found = walk(child, depth: depth + 1) { return found }
        }
        if let view = object as? NSView {
            for subview in view.subviews {
                if let found = walk(subview, depth: depth + 1) { return found }
            }
        }
        return nil
    }
    return walk(host, depth: 0)
}

/// Frame, in the host's top-left points, of the accessibility element with `identifier`.
///
/// - Parameters:
///   - identifier: The element's accessibility identifier.
///   - host: The window's hosting view (call `nativeHostedEnableAccessibility()` first).
/// - Returns: The element's frame, or nil when no realized element has the identifier.
@MainActor
func nativeHostedAccessibilityFrame(_ identifier: String, in host: NSView) -> CGRect? {
    guard let element = nativeHostedAccessibilityElement(identifier, in: host),
          element.responds(to: NSSelectorFromString("accessibilityFrame")),
          let frame = (element.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue,
          let window = host.window else { return nil }
    let local = host.convert(window.convertFromScreen(frame), from: nil)
    return host.isFlipped ? local : CGRect(
        x: local.minX, y: host.bounds.height - local.maxY, width: local.width, height: local.height
    )
}

/// Ask SwiftUI to build its accessibility tree inside this test process.
///
/// SwiftUI on macOS creates no accessibility nodes under an `NSHostingView`
/// (`accessibilityChildren()` stays empty) until an assistive client announces
/// itself. Setting `AXEnhancedUserInterface` on the in-process `NSApplication`
/// is that announcement; unlike the AX client API it needs no Accessibility
/// (TCC) permission. Idempotent.
@MainActor
func nativeHostedEnableAccessibility() {
    guard !nativeHostedAccessibilityEnabled else { return }
    nativeHostedAccessibilityEnabled = true
    let app = NSApplication.shared
    let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
    if app.responds(to: selector) {
        _ = app.perform(selector, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }
}

@MainActor private var nativeHostedAccessibilityEnabled = false

/// Keep real AppKit-backed controls in a sized native host for fixture tests.
///
/// - Parameters:
///   - content: SwiftUI screen with its actual native pickers and text fields.
///   - size: Window-like content dimensions in points, not backing pixels.
///   - forceGlassFallback: Keep true unless a test proves real glass on purpose;
///     tinted Liquid Glass captures as a fully transparent page (see `NativeHostedRoot`).
/// - Returns: Offscreen native host that can survive asynchronous state changes.
@MainActor
func nativeHostedView<Content: View>(
    _ content: Content, size: CGSize, forceGlassFallback: Bool = true
) -> NSHostingView<NativeHostedRoot<Content>> {
    nativeHostedEnableAccessibility()
    let host = NSHostingView(rootView: NativeHostedRoot(
        content: content, forceGlassFallback: forceGlassFallback
    ))
    // The app is dark-only; AppKit-backed controls follow the view's appearance rather than
    // `preferredColorScheme`, so pin it instead of inheriting the machine's system appearance.
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    return host
}

/// Realize lazy AppKit List rows without presenting a window to the operator.
///
/// - Parameters:
///   - host: Already sized native SwiftUI host.
///   - size: Matching content dimensions in points.
/// - Returns: A never-shown offscreen window the caller retains while capturing rows.
@MainActor
func nativeHostedWindow<Content: View>(
    _ host: NSHostingView<Content>, size: CGSize
) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(
            x: -10_000, y: -10_000, width: size.width, height: size.height
        ),
        styleMask: .borderless, backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    window.orderOut(nil)
    host.layoutSubtreeIfNeeded()
    return window
}

/// Capture native widgets instead of ImageRenderer's yellow AppKit placeholders.
///
/// - Parameter host: The same retained host after the state being asserted has settled.
/// - Returns: Composited pixels at the host's backing scale, but never below 2x so the stride-sampled
///   pixel thresholds hold on 1x headless CI displays as on a Retina Mac.
/// - Throws: An unavailable native bitmap or missing image.
@MainActor
func nativeHostedImage<Content: View>(_ host: NSHostingView<Content>) throws -> CGImage {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    return try nativeHostedCache(host, in: host.bounds)
}

/// Capture only `rect` of the host, at least 2x like ``nativeHostedImage(_:)``.
///
/// A whole-host capture of a page with pinned material chrome (Full Rankings' footer,
/// the band board's pager) takes about a second alone, which used most of a short
/// animation-evidence deadline; one row's rect takes a tenth of that (issue #327).
/// Sample it with `nativeHostedBrightSamples(in: CGRect(origin: .zero, size: rect.size),
/// of: image, hostSize: rect.size)`.
///
/// - Parameters:
///   - host: The same retained host, in its window.
///   - rect: The region, in the host's top-left points (an accessibility frame).
/// - Returns: The region's composited pixels.
/// - Throws: An unavailable native bitmap or missing image.
@MainActor
func nativeHostedImage<Content: View>(_ host: NSHostingView<Content>, in rect: CGRect) throws -> CGImage {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let local = host.isFlipped ? rect : CGRect(
        x: rect.minX, y: host.bounds.height - rect.maxY, width: rect.width, height: rect.height
    )
    return try nativeHostedCache(host, in: local)
}

/// Cache `local` (view coordinates) of a laid-out, displayed host at no less than 2x.
@MainActor
private func nativeHostedCache(_ host: NSView, in local: CGRect) throws -> CGImage {
    var bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: local))
    if CGFloat(bitmap.pixelsWide) < local.width * 2 {
        let colorSpace = bitmap.colorSpace
        let scaled = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((local.width * 2).rounded(.up)),
            pixelsHigh: Int((local.height * 2).rounded(.up)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: bitmap.colorSpaceName, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap = scaled.retagging(with: colorSpace) ?? scaled
        bitmap.size = local.size
    }
    host.cacheDisplay(in: local, to: bitmap)
    return try #require(bitmap.cgImage)
}

/// Visit every fourth pixel per axis with the components `NSBitmapImageRep.colorAt` reports.
///
/// Reads 8-bit RGBA captures (what `cacheDisplay` produces) straight from the
/// backing bytes, un-premultiplying like `colorAt`, instead of allocating an
/// `NSColor` per sample: the `colorAt` loop cost ~0.2 s per wide capture and,
/// summed across the parallel bundle, starved the shared main actor. Other
/// layouts fall back to `colorAt`.
///
/// - Parameters:
///   - image: Native AppKit capture.
///   - body: Receives red, green and blue in the capture's own color space, 0–1.
@MainActor
func nativeHostedForEachSample(
    _ image: CGImage, _ body: (CGFloat, CGFloat, CGFloat) -> Void
) {
    let alpha = image.alphaInfo
    let rgbaLayout = image.bitsPerComponent == 8 && image.bitsPerPixel == 32
        && image.byteOrderInfo == .orderDefault
        && [.premultipliedLast, .last, .noneSkipLast].contains(alpha)
        && image.colorSpace?.model == .rgb
    guard rgbaLayout, let data = image.dataProvider?.data,
          let base = CFDataGetBytePtr(data) else {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                body(color.redComponent, color.greenComponent, color.blueComponent)
            }
        }
        return
    }
    let rowBytes = image.bytesPerRow
    let premultiplied = alpha == .premultipliedLast
    for y in stride(from: 0, to: image.height, by: 4) {
        for x in stride(from: 0, to: image.width, by: 4) {
            let pixel = base + y * rowBytes + x * 4
            var red = CGFloat(pixel[0]) / 255
            var green = CGFloat(pixel[1]) / 255
            var blue = CGFloat(pixel[2]) / 255
            let opacity = CGFloat(pixel[3]) / 255
            if premultiplied && opacity > 0 && opacity < 1 {
                red /= opacity
                green /= opacity
                blue /= opacity
            }
            body(red, green, blue)
        }
    }
}

/// Recognize real bright labels and selected controls without exact ColorSync RGB guesses.
///
/// - Parameter image: Native AppKit bitmap at its actual backing scale.
/// - Returns: Sampled bright text, selected blue and yellow pixels. A view with
///   intentional gold content cannot treat every yellow pixel as a placeholder.
@MainActor
func nativeHostedControlPixels(_ image: CGImage) -> (
    bright: Int, selected: Int, placeholder: Int
) {
    var bright = 0
    var selected = 0
    var placeholder = 0
    nativeHostedForEachSample(image) { red, green, blue in
        if min(red, green, blue) > 0.7 { bright += 1 }
        if blue > 0.6 && green > 0.25 && red < 0.55
            && blue > red * 1.3 { selected += 1 }
        if red > 0.8 && green > 0.6 && blue < 0.25 { placeholder += 1 }
    }
    return (bright, selected, placeholder)
}

/// Read visible status fills on native Shop cards and selected Songs rows.
///
/// - Parameter image: AppKit-hosted content over an opaque native surface.
/// - Returns: Sampled gold, green and red pixels after host color conversion.
@MainActor
func nativeHostedStatusPixels(_ image: CGImage) -> (
    gold: Int, green: Int, red: Int
) {
    var gold = 0
    var green = 0
    var red = 0
    nativeHostedForEachSample(image) { r, g, b in
        if r > 0.7 && g > 0.5 && b < 0.25 { gold += 1 }
        if g > 0.55 && g > r * 1.4 && g > b * 1.2 { green += 1 }
        if r > 0.5 && g < 0.3 && b < 0.35 { red += 1 }
    }
    return (gold, green, red)
}

/// Optionally retain synthetic native screenshots outside the source worktree.
///
/// - Parameters:
///   - image: AppKit-hosted bitmap to encode as PNG.
///   - filename: Deterministic evidence name for this view and state.
///   - environment: Optional private output directory variable.
/// - Returns: PNG bytes for deterministic state comparison.
/// - Throws: Missing PNG data or an explicitly requested output-write failure.
@MainActor
func nativeHostedPNG(
    _ image: CGImage, filename: String, environment: String
) throws -> Data {
    let png = try #require(
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    )
    if let directory = ProcessInfo.processInfo.environment[environment] {
        try png.write(
            to: URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(filename),
            options: .atomic
        )
    }
    return png
}

/// Bright (text/glyph) samples inside `rect`, in host points, of a capture of `host`:
/// every second pixel per axis whose red, green and blue average above `threshold`.
///
/// - Parameters:
///   - rect: Region in the host's top-left points.
///   - image: Native capture of the host.
///   - hostSize: The host's size in points.
///   - threshold: Minimum mean channel value, 0–255.
/// - Returns: The number of bright samples.
@MainActor
func nativeHostedBrightSamples(
    in rect: CGRect, of image: CGImage, hostSize: CGSize, threshold: Int = 150
) -> Int {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return 0 }
    let scale = CGFloat(width) / hostSize.width
    let minX = max(0, Int(rect.minX * scale)), maxX = min(width, Int(rect.maxX * scale))
    let minY = max(0, Int(rect.minY * scale)), maxY = min(height, Int(rect.maxY * scale))
    var count = 0
    for y in stride(from: minY, to: maxY, by: 2) {
        for x in stride(from: minX, to: maxX, by: 2) {
            let pixel = (y * width + x) * 4
            if Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2]) > 3 * threshold { count += 1 }
        }
    }
    return count
}

// MARK: - Settling

/// Whether the test process runs in a virtual machine (`kern.hv_vmm_present`),
/// read once per process.
let nativeHostedIsVirtualMachine: Bool = {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
}()

/// Factor applied to readiness budgets inside a virtual machine.
let nativeHostedVirtualMachineTimeoutScale = 4

/// Readiness budget for one hosted wait.
///
/// The `apple-ci` VM (~3 cores) runs the whole parallel hosted bundle on one main
/// actor, so a wait that takes 4–7 s alone can take over a minute there (a
/// different test times out on each saturated run). A budget is only an upper
/// bound, so scaling it costs nothing when the content arrives.
///
/// - Parameters:
///   - timeout: The test's budget on a physical Mac.
///   - inVirtualMachine: Whether the process runs in a VM.
/// - Returns: `timeout`, scaled by `nativeHostedVirtualMachineTimeoutScale` in a VM.
func nativeHostedReadinessBudget(
    _ timeout: Duration, inVirtualMachine: Bool = nativeHostedIsVirtualMachine
) -> Duration {
    inVirtualMachine ? timeout * nativeHostedVirtualMachineTimeoutScale : timeout
}

/// A readiness bound measured in a wait's own time rather than wall-clock time.
///
/// Every hosted test shares one main actor. Under `swift test --parallel` it runs
/// ~99% busy, so a poll that asks for 250 ms resumes seconds later and the screen's
/// own `.task` loads advance just as slowly. A wall-clock bound then fails whichever
/// test settles last (three Leaderboards spotlight tests hit 62–80 s against a 60 s
/// bound) although nothing is wrong. This budget charges the sleeps the wait requested
/// plus the wait's own work between them (layout, accessibility walks, captures), and
/// leaves out only the queueing delay before each poll resumes. Starvation therefore
/// stretches the wait without spending its budget, while a loop whose own polls are
/// expensive still ends after about `limit` of its own time.
struct NativeHostedPollBudget {
    /// The wait's own time allowed (already scaled for a VM).
    let limit: Duration
    /// Requested sleeps plus the wait's own work so far.
    private(set) var spent: Duration = .zero
    /// When the last poll resumed; the work since then is charged on the next sleep.
    private var resumedAt: ContinuousClock.Instant?

    /// - Parameters:
    ///   - timeout: The wait's budget on a physical Mac.
    ///   - inVirtualMachine: Whether the process runs in a VM (see `nativeHostedReadinessBudget`).
    init(_ timeout: Duration, inVirtualMachine: Bool = nativeHostedIsVirtualMachine) {
        limit = nativeHostedReadinessBudget(timeout, inVirtualMachine: inVirtualMachine)
    }

    /// Whether the wait's own time has passed the limit.
    var isExhausted: Bool { spent > limit }

    /// Charge the work since the last poll, then sleep one interval and charge it,
    /// but not the delay before the poll resumes.
    ///
    /// Main-actor isolated so the resume instant is taken back on the main actor;
    /// a nonisolated method would resume on the cooperative pool and charge the hop back.
    ///
    /// - Parameter interval: Requested poll interval.
    /// - Throws: Cancellation.
    @MainActor
    mutating func sleep(for interval: Duration) async throws {
        let clock = ContinuousClock()
        if let resumedAt { spent += clock.now - resumedAt }
        try await Task.sleep(for: interval)
        spent += interval
        resumedAt = clock.now
    }
}

/// Main-actor resume lag above which a host counts as starved for animation evidence
/// (issue #327): SwiftUI then evaluates almost no animation frames, and an animated
/// commit can render straight at its final value without calling its curve.
let nativeHostedStarvedLag: Duration = .milliseconds(250)

/// Wait, for at most `limit` of wall-clock time, until the shared main actor wakes
/// promptly: `streak` consecutive 10 ms sleeps each resume within `lag` of their deadline
/// (issue #327).
///
/// The whole UI bundle runs in parallel on one main actor. At its peak a 20 ms poll
/// resumes about once a second, SwiftUI evaluates almost no animation frames, and an
/// animated commit can render straight at its final value. A test whose evidence is an
/// animation's rendered frames (not merely its end state) waits here first, about a third
/// of a second on a responsive host. The deadline is short and wall-clock: a hosted
/// runner can stay starved for minutes (an unbounded or 10-minute wait before each case
/// hung `apple-ci` until its job timeout), so after `limit` the test proceeds and treats
/// its animation evidence as inconclusive. Each probe sleeps; nothing holds the main
/// actor while it polls.
///
/// - Parameters:
///   - lag: How late a wake-up may be and still count as prompt.
///   - streak: Prompt wake-ups in a row that make the host responsive.
///   - limit: The longest wait, in wall-clock time, before proceeding regardless.
/// - Returns: Whether the host became responsive before `limit`.
/// - Throws: Cancellation.
@MainActor
@discardableResult
func nativeHostedAwaitResponsiveMainActor(
    lag: Duration = .milliseconds(25), streak: Int = 25, limit: Duration = .seconds(5)
) async throws -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + limit
    let interval = Duration.milliseconds(10)
    var prompt = 0
    while prompt < streak {
        guard clock.now < end else { return false }
        let asleep = clock.now
        try await Task.sleep(for: interval, tolerance: .milliseconds(1))
        prompt = clock.now - asleep <= interval + lag ? prompt + 1 : 0
    }
    return true
}

// MARK: - Animation-evidence deadline

/// The one short wall-clock deadline every phase of an animation-evidence journey shares
/// (issue #327): the responsive wait, page loads, the arrival and the settling. Each poll
/// sleeps through it and records how late it resumed.
///
/// A hosted runner can starve the shared main actor for the whole run, so no phase may
/// wait longer than the journey's few seconds. Alone a journey takes about 4 s, so
/// ``limit`` is unscaled in a VM. When it passes, ``check(_:)`` throws
/// ``NativeHostedEvidenceExpired``; the caller's `defer` releases anything it holds and
/// ``nativeHostedRecordExpired(_:sourceLocation:)`` judges it: a starved journey proves
/// nothing (an intermittent known issue), a responsive one that ran out of time fails.
struct NativeHostedEvidenceDeadline {
    /// The longest one animation-evidence journey may take, in wall-clock time.
    static let limit: Duration = .seconds(10)
    /// The longest the responsive wait may take, inside ``limit``.
    static let responsiveLimit: Duration = .seconds(5)

    /// When the journey must end.
    let end: ContinuousClock.Instant
    /// Whether the shared main actor responded before the journey started.
    private(set) var responsive = true
    /// The longest a poll resumed past its requested interval.
    private(set) var worstLag: Duration = .zero
    /// Polls' late resumption, summed over the stalls (a poll over ``stallLag`` late).
    /// Prompt polls are left out: a 20 ms poll on a responsive Mac resumes about 5 ms late,
    /// which over a 10 s journey sums past a second.
    private(set) var stalled: Duration = .zero
    /// How late a poll resumes before it counts as a stall.
    static let stallLag: Duration = .milliseconds(50)

    /// Start the deadline now.
    ///
    /// - Parameter limit: The journey's wall-clock length (``limit``; tests of the helper
    ///   pass less).
    init(limit: Duration = Self.limit) {
        end = ContinuousClock.now + limit
    }

    /// Whether the deadline has passed.
    var isExpired: Bool { ContinuousClock.now >= end }

    /// Why the host was too starved for its rendered frames to show an animation, or nil
    /// while it stayed responsive: the responsive wait gave up, one poll resumed more than
    /// `nativeHostedStarvedLag` late, or the stalls summed to over a second.
    var starved: String? {
        if !responsive { return "the main actor was still slow to resume after the bounded wait" }
        if worstLag > nativeHostedStarvedLag { return "a poll resumed \(worstLag) late" }
        if stalled > .seconds(1) { return "polls stalled for \(stalled) in all" }
        return nil
    }

    /// Wait until the shared main actor responds (`nativeHostedAwaitResponsiveMainActor`),
    /// for at most ``responsiveLimit`` of this deadline; record whether it did.
    ///
    /// - Throws: Cancellation.
    @MainActor
    mutating func awaitResponsiveMainActor() async throws {
        let left = end - ContinuousClock.now
        responsive = try await nativeHostedAwaitResponsiveMainActor(
            limit: max(.zero, min(Self.responsiveLimit, left))
        )
    }

    /// Throw ``NativeHostedEvidenceExpired`` once the deadline has passed.
    ///
    /// - Parameter waiting: What the journey was still waiting for (the failure message).
    /// - Throws: ``NativeHostedEvidenceExpired``.
    func check(_ waiting: @autoclosure () -> String) throws {
        guard isExpired else { return }
        throw NativeHostedEvidenceExpired(waiting: waiting(), starved: starved)
    }

    /// Sleep one poll interval and record how late it resumed.
    ///
    /// Main-actor isolated so the resume instant is taken back on the main actor.
    ///
    /// - Parameter interval: Requested poll interval.
    /// - Throws: Cancellation.
    @MainActor
    mutating func sleep(for interval: Duration) async throws {
        let asleep = ContinuousClock.now
        try await Task.sleep(for: interval)
        record(lateBy: ContinuousClock.now - asleep - interval)
    }

    /// Record one poll that resumed `lag` past its requested interval.
    ///
    /// - Parameter lag: How late the poll resumed (negative counts as on time).
    mutating func record(lateBy lag: Duration) {
        let lag = max(.zero, lag)
        worstLag = max(worstLag, lag)
        if lag > Self.stallLag { stalled += lag }
    }
}

/// An animation-evidence journey that reached its ``NativeHostedEvidenceDeadline``.
struct NativeHostedEvidenceExpired: Error, CustomStringConvertible {
    /// What the journey was still waiting for.
    let waiting: String
    /// Why the host was starved, or nil when it stayed responsive.
    let starved: String?

    var description: String {
        "\(waiting) when the \(NativeHostedEvidenceDeadline.limit) evidence deadline passed"
            + (starved.map { " (starved host: \($0))" } ?? " on a responsive host")
    }
}

/// Report an expired animation-evidence journey: on a starved host an intermittent known
/// issue (it proves neither the animation nor its absence), on a responsive host a
/// failure (the journey should end in about 4 s).
///
/// - Parameters:
///   - expired: The expiry.
///   - sourceLocation: Where the issue is reported.
func nativeHostedRecordExpired(
    _ expired: NativeHostedEvidenceExpired, sourceLocation: SourceLocation = #_sourceLocation
) {
    if expired.starved != nil {
        withKnownIssue("A starved host's journey proves nothing", isIntermittent: true) {
            Issue.record("\(expired)", sourceLocation: sourceLocation)
        }
    } else {
        Issue.record("\(expired)", sourceLocation: sourceLocation)
    }
}

/// Wait for asynchronously loaded content, then capture it once it stops changing.
///
/// Replaces fixed `Task.sleep` waits: `.task` fixture loads finish at
/// host-load-dependent times (the whole UI bundle runs in parallel on the main
/// actor), and a capture taken too early paints only the loading spinner while
/// the test still passes. Each poll yields the main actor (so `.task` work and
/// observation updates run), lays the host out, and checks the cheap `ready`
/// predicate; only then is a capture taken. Once ready, two consecutive
/// identical captures end the wait; content that keeps animating (a spinner in
/// a loading-state test) ends it after `animationGrace` instead. Polling backs
/// off from 20 ms to 250 ms so dozens of concurrently settling tests do not
/// starve the main actor they are waiting on. The timeout counts the wait's own
/// time (`NativeHostedPollBudget`), so a saturated parallel run cannot exhaust it.
///
/// - Parameters:
///   - host: Sized host, usually attached to `nativeHostedWindow`.
///   - timeout: Upper bound, in the wait's own time, for `ready` to become true on a
///     physical Mac (scaled in a VM, see `nativeHostedReadinessBudget`).
///   - animationGrace: How long a ready-but-still-changing capture may keep changing.
///   - sourceLocation: Where a readiness timeout is reported.
///   - ready: Fixture-specific readiness, e.g. a session state or visible text.
/// - Returns: The settled capture (the last capture after a recorded timeout).
/// - Throws: An unavailable native bitmap.
@MainActor
@discardableResult
func nativeHostedSettle<Content: View>(
    _ host: NSHostingView<Content>,
    timeout: Duration = .seconds(20),
    animationGrace: Duration = .seconds(1),
    sourceLocation: SourceLocation = #_sourceLocation,
    until ready: @MainActor () -> Bool = { true }
) async throws -> CGImage {
    let clock = ContinuousClock()
    let start = clock.now
    var budget = NativeHostedPollBudget(timeout)
    var interval = Duration.milliseconds(20)
    var readySince: ContinuousClock.Instant?
    var previous: Int?
    while true {
        try await budget.sleep(for: interval)
        interval = min(interval * 3 / 2, .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard ready() else {
            readySince = nil
            previous = nil
            if budget.isExhausted {
                let wall = clock.now - start
                Issue.record(
                    "Hosted view never became ready within \(budget.limit) of polling (\(wall) wall-clock)",
                    sourceLocation: sourceLocation
                )
                return try nativeHostedImage(host)
            }
            continue
        }
        let image = try nativeHostedImage(host)
        let signature = nativeHostedSignature(image)
        let since = readySince ?? clock.now
        readySince = since
        if signature == previous || clock.now - since > animationGrace {
            return image
        }
        previous = signature
        interval = .milliseconds(20)
    }
}

/// Wait until every string is present (and every excluded one absent) in the
/// host's accessibility text.
///
/// - Parameters:
///   - host: Sized host, usually attached to `nativeHostedWindow`.
///   - texts: Substrings that must each appear in some label, title or value.
///   - excluding: Substrings that must not appear anywhere (e.g. `"Loading"`).
///   - timeout: Upper bound for the text to appear.
///   - sourceLocation: Where a timeout is reported.
/// - Returns: The settled capture.
/// - Throws: An unavailable native bitmap.
@MainActor
@discardableResult
func nativeHostedSettle<Content: View>(
    _ host: NSHostingView<Content>, untilText texts: [String],
    excluding: [String] = [],
    timeout: Duration = .seconds(20),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> CGImage {
    try await nativeHostedSettle(host, timeout: timeout, sourceLocation: sourceLocation) {
        let accessibility = nativeHostedAccessibility(host)
        return texts.allSatisfy(accessibility.contains)
            && !excluding.contains(where: accessibility.contains)
    }
}

/// Cheap exact signature used to detect a settled frame.
///
/// - Parameter image: Native capture.
/// - Returns: Hash of the capture's backing bytes (no redraw).
func nativeHostedSignature(_ image: CGImage) -> Int {
    var hasher = Hasher()
    hasher.combine(image.width)
    hasher.combine(image.height)
    if let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) {
        hasher.combine(bytes: UnsafeRawBufferPointer(start: base, count: CFDataGetLength(data)))
    }
    return hasher.finalize()
}

// MARK: - Content measurement

/// Raw sRGB RGBA8 copy of a capture, for fast deterministic sampling.
struct NativeHostedPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Redraw the capture into a known sRGB, premultiplied RGBA8 layout.
    ///
    /// - Parameters:
    ///   - image: Native capture at backing scale.
    ///   - sampling: Keep every `sampling`-th pixel per axis (nearest neighbour),
    ///     so measurement cost stays small in unoptimized test builds.
    init(_ image: CGImage, sampling: Int = 1) {
        let width = max(1, image.width / sampling), height = max(1, image.height / sampling)
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        bytes = buffer
    }

    /// Borrow the RGBA bytes (row-major, top-down, 4 bytes per pixel).
    ///
    /// - Parameter body: Reader over the raw buffer.
    /// - Returns: Whatever `body` returns.
    func withBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        try bytes.withUnsafeBufferPointer(body)
    }
}

/// How much of a capture is something other than its background.
struct NativeHostedContent: CustomStringConvertible {
    /// Fraction of sampled pixels that differ visibly from the dominant (background) color.
    let nonBackgroundFraction: Double
    /// Fraction of sampled pixels with strong luminance contrast against the background
    /// (text, glyphs, icons, chart strokes).
    let inkFraction: Double
    /// Dominant sampled color, premultiplied RGBA 0–255.
    let background: (r: Int, g: Int, b: Int, a: Int)

    var description: String {
        String(
            format: "non-background %.1f%%, ink %.2f%%, background rgba(%d,%d,%d,%d)",
            nonBackgroundFraction * 100, inkFraction * 100,
            background.r, background.g, background.b, background.a
        )
    }
}

/// Measure non-background and ink coverage on a sparse (every 4th pixel) grid.
///
/// The background is the most common 4-bit-per-channel color bucket (alpha
/// included, so a transparent unpainted host counts as background), averaged
/// over its members. A pixel is content when any channel differs from it by
/// more than 10/255; it is ink when its luminance sum differs by more than
/// 180/765 from an opaque background.
///
/// - Parameter image: Native capture.
/// - Returns: Coverage fractions and the detected background.
func nativeHostedContent(_ image: CGImage) -> NativeHostedContent {
    let pixels = NativeHostedPixels(image, sampling: 4)
    let width = pixels.width, height = pixels.height, step = 1
    return pixels.withBytes { bytes -> NativeHostedContent in
        var counts = [Int](repeating: 0, count: 1 << 16)
        var samples = 0
        func bucket(_ i: Int) -> Int {
            Int(bytes[i] >> 4) << 12 | Int(bytes[i + 1] >> 4) << 8
                | Int(bytes[i + 2] >> 4) << 4 | Int(bytes[i + 3] >> 4)
        }
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                counts[bucket((y * width + x) * 4)] += 1
                samples += 1
            }
        }
        guard samples > 0 else {
            return NativeHostedContent(nonBackgroundFraction: 0, inkFraction: 0, background: (0, 0, 0, 0))
        }
        var dominant = 0
        for index in counts.indices where counts[index] > counts[dominant] { dominant = index }
        var sum = (r: 0, g: 0, b: 0, a: 0)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let i = (y * width + x) * 4
                guard bucket(i) == dominant else { continue }
                sum.r += Int(bytes[i]); sum.g += Int(bytes[i + 1])
                sum.b += Int(bytes[i + 2]); sum.a += Int(bytes[i + 3])
            }
        }
        let members = counts[dominant]
        let background = (
            r: sum.r / members, g: sum.g / members, b: sum.b / members, a: sum.a / members
        )
        let backgroundLuma = background.a > 128 ? background.r + background.g + background.b : 0
        var content = 0, ink = 0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let i = (y * width + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1])
                let b = Int(bytes[i + 2]), a = Int(bytes[i + 3])
                if abs(r - background.r) > 10 || abs(g - background.g) > 10
                    || abs(b - background.b) > 10 || abs(a - background.a) > 10 {
                    content += 1
                }
                if a > 128 && abs(r + g + b - backgroundLuma) > 180 { ink += 1 }
            }
        }
        return NativeHostedContent(
            nonBackgroundFraction: Double(content) / Double(samples),
            inkFraction: Double(ink) / Double(samples),
            background: background
        )
    }
}

// MARK: - Accessibility text

/// Text and identifiers SwiftUI exposes to assistive technology for a hosted view.
struct NativeHostedAccessibility {
    /// Every non-empty label, title and string value, in tree order.
    let texts: [String]
    /// Every non-empty accessibility identifier, in tree order.
    let identifiers: [String]

    /// Whether any text contains `needle`.
    ///
    /// - Parameter needle: Case-sensitive substring.
    /// - Returns: True when some label, title or value contains it.
    func contains(_ needle: String) -> Bool {
        texts.contains { $0.contains(needle) }
    }
}

/// Walk the hosted accessibility tree (requires `nativeHostedEnableAccessibility`,
/// which `nativeHostedView` calls).
///
/// Follows both accessibility children and AppKit subviews (List rows live in
/// nested `NSTableView` cell hosts). Uses selector-checked KVC rather than
/// `NSAccessibilityProtocol` members,
/// whose optional-requirement imports are ambiguous in Swift and which
/// SwiftUI's private node classes implement informally.
///
/// - Parameter view: Hosting view (or any AppKit view) to read.
/// - Returns: Texts and identifiers in depth-first order.
@MainActor
func nativeHostedAccessibility(_ view: NSView) -> NativeHostedAccessibility {
    var texts: [String] = []
    var identifiers: [String] = []
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let text = read(object, key) as? String, !text.isEmpty { texts.append(text) }
        }
        if let identifier = read(object, "accessibilityIdentifier") as? String,
           !identifier.isEmpty {
            identifiers.append(identifier)
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        // AppKit-backed `List`/`Form` rows (NSTableView cells) are not reachable
        // through the SwiftUI root's accessibility children; follow the views too.
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(view, depth: 0)
    return NativeHostedAccessibility(texts: texts, identifiers: identifiers)
}

// MARK: - Assertions

/// Fail when a hosted page captured blank, spinner-only or without its key text.
///
/// Use on every full-page hosted render that is counted as visual evidence.
/// A page that genuinely cannot render hosted must say so in its test and not
/// call this (see `.agents/testing/apple/hosted-snapshots.md`).
///
/// - Parameters:
///   - host: The host the capture came from (for accessibility text).
///   - image: Settled capture, normally from `nativeHostedSettle`.
///   - minimumNonBackgroundFraction: Share of pixels that must differ from the background.
///   - minimumInkFraction: Share of pixels that must be high-contrast text/glyph ink.
///   - texts: Substrings that must appear in the accessibility text.
///   - absent: Substrings that must not appear (e.g. a loading label).
///   - sourceLocation: Where failures are reported.
/// - Returns: The measured coverage, for further state-specific assertions.
@MainActor
@discardableResult
func assertRendersContent<Content: View>(
    _ host: NSHostingView<Content>, image: CGImage,
    minimumNonBackgroundFraction: Double = 0.01,
    minimumInkFraction: Double = 0.002,
    containing texts: [String] = [],
    notContaining absent: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) -> NativeHostedContent {
    let content = nativeHostedContent(image)
    #expect(
        content.nonBackgroundFraction >= minimumNonBackgroundFraction,
        "Hosted page looks blank: \(content)", sourceLocation: sourceLocation
    )
    #expect(
        content.inkFraction >= minimumInkFraction,
        "Hosted page paints no text/glyph ink: \(content)", sourceLocation: sourceLocation
    )
    if !texts.isEmpty || !absent.isEmpty {
        let accessibility = nativeHostedAccessibility(host)
        for text in texts {
            #expect(
                accessibility.contains(text),
                "Hosted page is missing \"\(text)\"; saw \(accessibility.texts.prefix(30))",
                sourceLocation: sourceLocation
            )
        }
        for text in absent {
            #expect(
                !accessibility.contains(text),
                "Hosted page unexpectedly shows \"\(text)\"; saw \(accessibility.texts.prefix(30))",
                sourceLocation: sourceLocation
            )
        }
    }
    return content
}
#endif
