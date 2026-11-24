import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Arc spinner metrics (#635)

/// ``FestivalLoadingView`` draws the web `ArcSpinner` (`@festival/theme` `Spinner`
/// tokens) instead of the system spokes indicator; these pin the tokens it uses.
struct ArcSpinnerMetricsTests {
    @Test func sizesMirrorTheWebSpinnerTokens() {
        #expect(FestivalArcMetrics.small == .init(diameter: 24, lineWidth: 3))
        #expect(FestivalArcMetrics.medium == .init(diameter: 36, lineWidth: 3))
        #expect(FestivalArcMetrics.large == .init(diameter: 48, lineWidth: 4))
        #expect(FestivalArcMetrics.period == 0.8)
        #expect(FestivalArcMetrics.sweep == 0.25)
    }

    @Test func controlSizeChoosesTheWebSize() {
        #expect(FestivalArcMetrics.size(for: .mini) == FestivalArcMetrics.small)
        #expect(FestivalArcMetrics.size(for: .small) == FestivalArcMetrics.small)
        #expect(FestivalArcMetrics.size(for: .regular) == FestivalArcMetrics.medium)
        #expect(FestivalArcMetrics.size(for: .large) == FestivalArcMetrics.large)
        #expect(FestivalArcMetrics.size(for: .extraLarge) == FestivalArcMetrics.large)
    }

    @Test func trackIsTenPercentWhiteAndBrighterUnderIncreaseContrast() {
        #expect(FestivalArcMetrics.trackOpacity(.standard) == 0.10)
        #expect(FestivalArcMetrics.trackOpacity(.increased) == 0.25)
    }

    /// Every spinner reads the same wall clock, so two on screen turn in phase.
    @Test func angleFollowsTheWallClockAndWraps() {
        #expect(FestivalArcMetrics.angle(at: 0) == 0)
        #expect(abs(FestivalArcMetrics.angle(at: 0.2) - 90) < 1e-9)
        #expect(abs(FestivalArcMetrics.angle(at: 0.6) - 270) < 1e-9)
        #expect(abs(FestivalArcMetrics.angle(at: 0.8)) < 1e-9 || abs(FestivalArcMetrics.angle(at: 0.8) - 360) < 1e-9)
        #expect(abs(FestivalArcMetrics.angle(at: -0.2) - 270) < 1e-9)
        let now = 812_345_678.123
        #expect(abs(FestivalArcMetrics.angle(at: now) - FestivalArcMetrics.angle(at: now + FestivalArcMetrics.period * 1_000)) < 1e-3)
        #expect((0..<360).contains(FestivalArcMetrics.angle(at: now)))
    }

    /// The arc holds still only under the Debug UI-test still override, so XCUITest can
    /// idle during a slow load (#690); otherwise it turns, Reduce Motion included (#635).
    @Test func turnsUnlessTheUITestStillOverrideIsOn() {
        #expect(FestivalArcMetrics.turns(still: false))
        #expect(!FestivalArcMetrics.turns(still: true))
    }

    @Test func loadingRegionIntersectsSafeAreaBeforeChoosingAFoldSide() {
        let viewport = CGRect(x: 100, y: 80, width: 800, height: 600)
        let usable = CGRect(x: 132, y: 130, width: 736, height: 470)
        let fold = CGRect(x: 500, y: 0, width: 24, height: 760)
        let region = LoadingRegionPolicy.region(viewport: viewport, usable: usable, fold: fold)
        #expect(region == CGRect(x: 32, y: 50, width: 368, height: 470))
        #expect(!region.intersects(fold.offsetBy(dx: -viewport.minX, dy: -viewport.minY)))
    }

    @Test func loadingRegionKeepsFlatAndClippedPanesWhole() {
        let page = CGRect(x: 0, y: 100, width: 860, height: 530)
        let flat = CGRect(x: 0, y: 120, width: 860, height: 480)
        #expect(LoadingRegionPolicy.region(viewport: page, usable: flat, fold: nil)
            == CGRect(x: 0, y: 20, width: 860, height: 480))

        let pane = CGRect(x: 540, y: 100, width: 352, height: 530)
        let fold = CGRect(x: 500, y: 0, width: 24, height: 760)
        #expect(LoadingRegionPolicy.region(viewport: pane, fold: fold)
            == CGRect(origin: .zero, size: pane.size), "A pane already beside the fold stays centred in its own viewport")
    }

    @Test func loadingRegionChoosesTheLowerSideOfAHorizontalFold() {
        let viewport = CGRect(x: 0, y: 40, width: 760, height: 820)
        let fold = CGRect(x: 0, y: 360, width: 760, height: 24)
        #expect(LoadingRegionPolicy.region(viewport: viewport, fold: fold)
            == CGRect(x: 0, y: 344, width: 760, height: 476))
    }
}

#if os(iOS)
import FestivalCore
import UIKit

// MARK: - UIKit spinner motion

@MainActor
struct UIKitArcSpinnerTests {
    /// Adding another spinner while the first is running must not restart the rotation phase.
    @Test func staggeredSpinnersUseTheSameWallClockPhase() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        let first = UKArcView(size: .large)
        window.addSubview(first)
        try await Task.sleep(for: .milliseconds(170))
        let second = UKArcView(size: .large)
        window.addSubview(second)
        defer { window.isHidden = true }

        let wallTime = Date.timeIntervalSinceReferenceDate
        let mediaTime = CACurrentMediaTime()
        let expected = FestivalArcMetrics.angle(at: wallTime)
        for spinner in [first, second] {
            let layer = try #require(spinner.layer.sublayers?.first { $0.animation(forKey: "spin") != nil })
            let animation = try #require(layer.animation(forKey: "spin") as? CABasicAnimation)
            let elapsed = layer.convertTime(mediaTime, from: nil) - animation.beginTime
            let phase = elapsed.truncatingRemainder(dividingBy: animation.duration) / animation.duration * 360
            let error = abs((phase - expected).remainder(dividingBy: 360))
            #expect(animation.beginTime > 0, "Core Animation must not start a new phase at attachment")
            #expect(error < 6, "The spinner should stay within one 60 Hz frame of the shared phase")
        }
    }

    /// A raw, full-page UIKit wrapper uses the safe-area intersection and places the
    /// accessibility identifier on the actual arc's indicator.
    @Test func fillingSpinnerUsesTheSafeViewportAndActualBusyFrame() throws {
        let windowFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let window = UIWindow(frame: windowFrame)
        let controller = UIViewController()
        controller.view.frame = windowFrame
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 96, left: 24, bottom: 72, right: 8)
        let loading = UKLoadingView(
            accessibilityLabel: "Loading song", placement: .fill, identifier: "fst.loading-test.uikit"
        )
        controller.view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            loading.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            loading.topAnchor.constraint(equalTo: controller.view.topAnchor),
            loading.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        loading.layoutIfNeeded()

        let indicator = try #require(Self.indicators(in: loading).first)
        #expect(indicator.accessibilityIdentifier == "fst.loading-test.uikit")
        #expect(loading.accessibilityIdentifier == nil, "The wrapper is not the AX busy element")
        let actual = indicator.convert(indicator.bounds, to: window)
        let viewport = loading.convert(loading.bounds, to: window)
        let usable = loading.convert(loading.safeAreaLayoutGuide.layoutFrame, to: window)
        let expected = LoadingRegionPolicy.region(viewport: viewport, usable: usable, fold: nil)
        #expect(abs(actual.midX - (viewport.minX + expected.midX)) < 1)
        #expect(abs(actual.midY - (viewport.minY + expected.midY)) < 1)
    }

    /// A reload gate and the direct Song Detail form share the same raw-host region
    /// contract and emit only one named activity indicator.
    @Test func gateAndDirectSpinnerShareOneRegionContract() throws {
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let window = UIWindow(frame: frame)
        let controller = UIViewController()
        controller.view.frame = frame
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 110, left: 0, bottom: 64, right: 0)
        let gate = UKReloadGate(
            key: 0, isLoading: true, spinnerLabel: "Loading songs", spinnerIdentifier: "fst.loading-test.gate"
        )
        controller.view.addSubview(gate)
        gate.ukPin(to: controller.view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        gate.layoutIfNeeded()

        let indicators = Self.indicators(in: gate)
        #expect(indicators.count == 1)
        let indicator = try #require(indicators.first)
        #expect(indicator.accessibilityIdentifier == "fst.loading-test.gate")
        let actual = indicator.convert(indicator.bounds, to: window)
        let expectedViewport = gate.convert(gate.bounds, to: window)
        let usable = gate.convert(gate.safeAreaLayoutGuide.layoutFrame, to: window)
        let expected = LoadingRegionPolicy.region(viewport: expectedViewport, usable: usable, fold: nil)
        #expect(abs(actual.midX - (expectedViewport.minX + expected.midX)) < 1)
        #expect(abs(actual.midY - (expectedViewport.minY + expected.midY)) < 1)
    }

    /// A non-scrolling accessibility holder is not the page scroller; its collection is.
    @Test func pageScrollViewportFindsTheNestedCollection() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let holder = UIScrollView(frame: host.bounds)
        holder.isScrollEnabled = false
        let collection = UICollectionView(
            frame: holder.bounds,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        host.addSubview(holder)
        holder.addSubview(collection)
        #expect(UKPageScrollViewport.scrollingDescendant(in: host) === collection)
    }

    /// The content stack's 16 pt margin is the only gap after a newly registered
    /// scroller accounts for the navigation bar's adjusted inset.
    @Test func pageScrollStartsAtAdjustedTopInsteadOfAddingABlankInset() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let controller = UIViewController()
        controller.view.frame = window.bounds
        let scrollView = UIScrollView(frame: window.bounds)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(top: 94, left: 0, bottom: 44, right: 0)
        scrollView.contentOffset = .zero
        controller.view.addSubview(scrollView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #expect(UKPageScrollViewport.placeAtInitialTop(scrollView))
        #expect(scrollView.contentOffset.y == -94)
    }

    /// Song Detail adds artist/year to the existing bar title without changing board
    /// captions, the combined spoken name or the Large Content Viewer string.
    @Test func songBarTitleKeepsCombinedDetailAndBoardIdentities() throws {
        let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:9")!)
        let session = FestivalSession(factory: { client })
        func song(year: Int?) -> Song {
            Song(
                songId: "fixture-song", title: "Fixture Pulse", artist: "Synthetic Quartet",
                album: nil, year: year, durationSeconds: 180, albumArt: nil, difficulty: nil,
                pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
            )
        }
        let withYear = song(year: 2026)
        let detail = UKSongBarTitleView(
            song: withYear, session: session,
            caption: UKSongBarTitleView.detailCaption(for: withYear), identifier: "fst.test.detail-title"
        )
        #expect(detail.accessibilityLabel == "Fixture Pulse, Synthetic Quartet · 2026")
        #expect(detail.largeContentTitle == detail.accessibilityLabel)

        let noYear = song(year: nil)
        #expect(UKSongBarTitleView.detailCaption(for: noYear) == "Synthetic Quartet")
        let board = UKSongBarTitleView(song: withYear, session: session, caption: "Lead · 42 entries")
        #expect(board.accessibilityLabel == "Fixture Pulse, Lead · 42 entries")
        #expect(board.largeContentTitle == board.accessibilityLabel)
    }

    private static func indicators(in view: UIView) -> [UIActivityIndicatorView] {
        var found = view.subviews.compactMap { $0 as? UIActivityIndicatorView }
        for subview in view.subviews { found += indicators(in: subview) }
        return found
    }
}
#endif

#if os(macOS)
import AppKit

// MARK: - Arc spinner drawing and accessibility (#635)

/// The shared spinner draws a white quarter arc on a faint full ring at the web size for
/// its placement, while assistive technology still meets one named busy indicator
/// (empty-error-states R6, #431). HIG Progress indicators: indeterminate indicators on
/// "all platforms spin a circle"; HIG Accessibility: provide a higher-contrast scheme
/// when Increase Contrast is on.
@MainActor
@Suite(.serialized)
struct ArcSpinnerAccessibilityTests {
    /// One placement and the web size it must draw.
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let name: String
        let fill: Bool
        let controlSize: ControlSize
        let expected: FestivalArcMetrics.Size

        var testDescription: String { name }
    }

    nonisolated static let sizes: [SizeCase] = [
        SizeCase(name: "card or row (MD)", fill: false, controlSize: .regular, expected: FestivalArcMetrics.medium),
        SizeCase(name: "small row (SM)", fill: false, controlSize: .small, expected: FestivalArcMetrics.small),
        SizeCase(name: "What's New (LG)", fill: false, controlSize: .large, expected: FestivalArcMetrics.large),
        SizeCase(name: "page gate (LG)", fill: true, controlSize: .regular, expected: FestivalArcMetrics.large),
    ]

    static let side: CGFloat = 120
    static let identifier = "fst.arc-test.spinner"

    /// Host one spinner on black, as the app's dark pages are.
    private func host(_ view: some View, contrast: ColorSchemeContrast = .standard) -> NSHostingView<NativeHostedRoot<some View>> {
        nativeHostedView(
            view
                .frame(width: Self.side, height: Self.side)
                .background(Color.black)
                .environment(\._colorSchemeContrast, contrast),
            size: CGSize(width: Self.side, height: Self.side)
        )
    }

    @Test(arguments: sizes)
    func drawsTheWebSizeAsOneNamedBusyIndicator(_ state: SizeCase) async throws {
        let spinner = FestivalLoadingView(
            accessibilityLabel: "Loading scores", placement: state.fill ? .fill : .inline
        )
        .controlSize(state.controlSize)
        .accessibilityIdentifier(Self.identifier)
        let host = host(spinner)
        let window = nativeHostedWindow(host, size: CGSize(width: Self.side, height: Self.side))
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement(Self.identifier, in: host) != nil
        }
        let nodes = ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(host))
        #expect(nodes.count == 1, "one busy indicator, nothing else: \(nodes)")
        #expect(nodes.first?.label == "Loading scores")
        #expect(nodes.first?.identifier == Self.identifier)

        let ring = try Self.ring(in: host, diameter: state.expected.diameter)
        #expect(ring.lit == ring.samples, "\(state.name): a faint track all the way round: \(ring)")
        #expect((4...9).contains(ring.white), "\(state.name): a quarter of the ring is the white arc: \(ring)")
        #expect(ring.centre < 10, "\(state.name): the ring is hollow, not spokes: \(ring)")
        #expect(ring.outside < 10, "\(state.name): nothing drawn beyond the web diameter: \(ring)")
    }

    /// Under Increase Contrast the track brightens; the arc stays white.
    @Test func trackBrightensUnderIncreaseContrast() async throws {
        func trackLevel(_ contrast: ColorSchemeContrast) async throws -> Int {
            let host = host(FestivalLoadingView().accessibilityIdentifier(Self.identifier), contrast: contrast)
            let window = nativeHostedWindow(host, size: CGSize(width: Self.side, height: Self.side))
            defer { window.orderOut(nil) }
            try await nativeHostedSettle(host) {
                nativeHostedAccessibilityElement(Self.identifier, in: host) != nil
            }
            return try Self.ring(in: host, diameter: FestivalArcMetrics.medium.diameter).dimmest
        }
        let standard = try await trackLevel(.standard)
        let increased = try await trackLevel(.increased)
        #expect(standard > 10 && standard < 60, "10% white track: \(standard)")
        #expect(increased > standard + 15, "brighter track under Increase Contrast: \(standard) → \(increased)")
    }

    /// A form's status row shows its text beside a small arc and reads as one busy
    /// indicator named by that text (Android's feedback status row).
    @Test func statusRowReadsItsTextAsOneBusyIndicator() async throws {
        let host = host(
            FestivalLoadingView(status: "Adding media…").accessibilityIdentifier(Self.identifier)
        )
        let window = nativeHostedWindow(host, size: CGSize(width: Self.side, height: Self.side))
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement(Self.identifier, in: host) != nil
        }
        let nodes = ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(host))
        #expect(nodes.count == 1, "\(nodes)")
        #expect(nodes.first.map { $0.label.isEmpty ? $0.title : $0.label } == "Adding media…", "\(nodes)")
        let reachable = ReloadGateAccessibilityTests.reachable(host)
        #expect(!reachable.contains { $0.role == "AXStaticText" && $0.label == "Adding media…" },
                "the status text is the indicator's name, not a second stop: \(reachable)")
    }

    // MARK: Pixels

    /// Brightness around the arc's stroke circle, at the centre and just outside.
    struct Ring: CustomStringConvertible {
        var samples = 0
        /// Samples brighter than black (track or arc).
        var lit = 0
        /// Samples that are near white (the arc).
        var white = 0
        var dimmest = 255
        var centre = 0
        var outside = 0

        var description: String {
            "lit \(lit)/\(samples), white \(white), dimmest \(dimmest), centre \(centre), outside \(outside)"
        }
    }

    /// Sample 24 points on the stroke's centre circle of a spinner centred in the host.
    ///
    /// - Parameters:
    ///   - host: The hosted spinner on black.
    ///   - diameter: The size it should draw.
    /// - Returns: The ring's brightness profile.
    /// - Throws: An unavailable capture.
    static func ring<Content: View>(in host: NSHostingView<Content>, diameter: CGFloat) throws -> Ring {
        let image = try nativeHostedImage(host)
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
        try #require(drawn)
        let scale = CGFloat(width) / side
        func level(_ x: CGFloat, _ y: CGFloat) -> Int {
            let px = min(max(Int(x * scale), 0), width - 1), py = min(max(Int(y * scale), 0), height - 1)
            let pixel = (py * width + px) * 4
            return (Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2])) / 3
        }
        let centre = side / 2
        let lineWidth = diameter >= 48 ? 4.0 : 3.0
        let radius = (diameter - lineWidth) / 2
        var ring = Ring()
        for step in 0..<24 {
            let angle = Double(step) / 24 * 2 * .pi
            let value = level(centre + radius * cos(angle), centre + radius * sin(angle))
            ring.samples += 1
            if value > 8 { ring.lit += 1 }
            if value > 200 { ring.white += 1 }
            ring.dimmest = min(ring.dimmest, value)
            ring.outside = max(ring.outside, level(
                centre + (diameter / 2 + 3) * cos(angle), centre + (diameter / 2 + 3) * sin(angle)
            ))
        }
        ring.centre = level(centre, centre)
        return ring
    }
}
#endif
