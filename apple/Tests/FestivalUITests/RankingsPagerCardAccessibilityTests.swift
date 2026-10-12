#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Pager and band cards on the row card (issue #467, for #319)

// #319 moved the leaderboard pager's arrows and `page / total` badge off an opaque navy
// plate onto the rows' translucent card (`festivalCardCapsule`, `festivalCard(cornerRadius:
// 12)`), and Player Bands' rows off a `List` onto separate band cards above the same pager.
// `RankingsPagerSurfaceTests` pins the pixels of the surface; `MaterialCardControlsAccessibilityTests`
// the pager's names, roles, states, order and targets; `BoardFooterFadeJourneyTests` the
// board at AX5 on iPhone. These hosted checks (`apple-ci`) pin what the card change
// meant for accessibility on every Apple platform that shares this SwiftUI:
//
// - each control's accessibility frame (focus ring, Voice Control target) is its own
//   drawn card, in every transparency and contrast mode;
// - on the opaque Reduce Transparency / Increase Contrast card the badge's text and the
//   enabled arrows keep their contrast over a white page, and a disabled glyph stays
//   visible but dimmer (the translucent card is measured on iPhone,
//   `PagerCardContrastJourneyTests`, because a hosted capture skips its blur);
// - Player Bands' cards are named buttons with a hint and a full-width target of at least
//   44 pt, one card per band, that open their band through AXPress (VoiceOver's VO-Space,
//   Voice Control, Switch Control), like the other band and member cards.

/// Transparency and contrast settings the pager's card draws differently for.
enum PagerCardMode: String, CaseIterable, CustomTestStringConvertible {
    /// The shipping translucent card.
    case material
    /// System Reduce Transparency: the opaque card.
    case systemReduceTransparency
    /// System Increase Contrast: the darker translucent tint.
    case systemIncreaseContrast
    /// The app's Reduce Transparency setting: the opaque card.
    case lessTransparency
    /// The app's Increase Contrast setting: the opaque card.
    case moreContrast

    var testDescription: String { rawValue }

    /// Whether the card draws its opaque fallback, so a capture shows exactly what the
    /// screen does. The hosted capture (`cacheDisplay`) skips Core Animation filters, the
    /// material's backdrop blur among them; the translucent card's rendered contrast is
    /// measured on iPhone instead (`PagerCardContrastJourneyTests`).
    var opaque: Bool { self == .systemReduceTransparency || self == .lessTransparency || self == .moreContrast }
}

/// Identifier prefix of the hosted pager.
private let pagerPrefix = "fst.test-pager"
/// The pager's controls in visual and reading order.
private let pagerControls = ["page-first", "page-previous", "page-info", "page-next", "page-last"]
    .map { "\(pagerPrefix).\($0)" }
/// A phone-width page with the pager pinned at its foot.
private let pagerPageSize = CGSize(width: 402, height: 220)
/// Saturated solid backdrop the card stands out from in every mode (`RankingsPagerSurfaceTests`).
private let solidBackdrop = Color(red: 0.85, green: 0.3, blue: 0.2)
/// The brightest page an opaque card can stand on.
private let whiteBackdrop = Color.white

/// One hosted pager and its window.
@MainActor
private struct HostedPager {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
    let storage: UserDefaults
    let suiteName: String

    /// Host ``RankingsPagerView`` on `page` of 3 at the foot of a page.
    ///
    /// - Parameters:
    ///   - mode: Transparency or contrast setting under test.
    ///   - page: Current page (1 dims First and Previous).
    ///   - backdrop: The page colour behind the pager.
    /// - Returns: The hosted pager; call ``close()`` when done.
    static func host(_ mode: PagerCardMode, page: Int, backdrop: Color = solidBackdrop) throws -> HostedPager {
        let suiteName = "fst.tests.pager-card.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(mode == .lessTransparency, forKey: "fst.accessibility.lessTransparency")
        storage.set(mode == .moreContrast, forKey: "fst.accessibility.moreContrast")
        let content = ZStack(alignment: .bottom) {
            backdrop
            RankingsPagerView(page: page, totalPages: 3, idPrefix: pagerPrefix) { _ in }
        }
        .environment(\._accessibilityReduceTransparency, mode == .systemReduceTransparency)
        .environment(\._colorSchemeContrast, mode == .systemIncreaseContrast ? .increased : .standard)
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        // The translucent card must draw for real; the opaque modes are pinned above.
        let host = nativeHostedView(AnyView(content), size: pagerPageSize, forceGlassFallback: false)
        let window = nativeHostedWindow(host, size: pagerPageSize)
        return HostedPager(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    func close() {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: suiteName)
    }

    /// The accessibility frame of `identifier`, in the host's top-left points.
    func frame(_ identifier: String) throws -> CGRect {
        host.layoutSubtreeIfNeeded()
        return try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) has a frame")
    }
}

/// Composited RGB pixels of a capture, read top-down in points.
private struct PagerPixels {
    let width: Int
    let height: Int
    /// Pixels per point.
    let scale: CGFloat
    private let bytes: [UInt8]

    init(_ image: CGImage, size: CGSize) throws {
        width = image.width
        height = image.height
        scale = CGFloat(image.height) / size.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.bytes = bytes
    }

    /// The pixel at a point (top-left origin).
    func rgb(_ point: CGPoint) -> (Int, Int, Int) {
        let x = min(width - 1, max(0, Int((point.x * scale).rounded(.down))))
        // The bitmap's first row is the image's top edge.
        let y = min(height - 1, max(0, Int((point.y * scale).rounded(.down))))
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// WCAG relative luminance of every pixel inside `rect` (points).
    func luminances(in rect: CGRect) -> [Double] {
        let minX = max(0, Int((rect.minX * scale).rounded(.up)))
        let maxX = min(width, Int((rect.maxX * scale).rounded(.down)))
        let minY = max(0, Int((rect.minY * scale).rounded(.up)))
        let maxY = min(height, Int((rect.maxY * scale).rounded(.down)))
        var values: [Double] = []
        for y in minY..<maxY {
            for x in minX..<maxX {
                let i = (y * width + x) * 4
                values.append(relativeLuminance(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])))
            }
        }
        return values
    }
}

/// WCAG 2 relative luminance of an sRGB pixel.
private func relativeLuminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
    func channel(_ value: Int) -> Double {
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
}

/// Largest per-channel difference between two pixels.
private func channelDistance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
    max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
}

/// Rendered contrast of the bright glyphs in `rect` against their card: the median pixel
/// is the surface, the 99th-percentile pixel the glyph core
/// (`SongsUITestSupport.measuredTextContrast`, testing/apple/accessibility.md).
///
/// - Parameters:
///   - pixels: The capture.
///   - rect: A region of one control that its card fills.
/// - Returns: The ratio and how many pixels are glyph (at least 1.5:1 brighter than the surface).
private func glyphContrast(_ pixels: PagerPixels, in rect: CGRect) -> (ratio: Double, glyphPixels: Int, surface: Double) {
    let values = pixels.luminances(in: rect).sorted()
    guard !values.isEmpty else { return (0, 0, 0) }
    let surface = values[values.count / 2]
    let glyph = values[values.count * 99 / 100]
    let glyphPixels = values.filter { ($0 + 0.05) / (surface + 0.05) >= 1.5 }.count
    return ((glyph + 0.05) / (surface + 0.05), glyphPixels, surface)
}

/// The part of a control its card always fills: the badge's rounded rectangle less its
/// corners, or the square inscribed in an arrow's 44 pt circle.
private func cardInterior(_ frame: CGRect, badge: Bool) -> CGRect {
    if badge { return frame.insetBy(dx: 6, dy: 3) }
    let inset = frame.width / 2 * (1 - 1 / 2.0.squareRoot()) + 1
    return frame.insetBy(dx: inset, dy: inset)
}

/// Routes a hosted stack pushed.
@MainActor
private final class OpenedRoutes {
    var routes: [AppRoute] = []
}

// MARK: - Tests

/// Accessibility of the pager on the rows' translucent card (#319).
///
/// HIG Accessibility: "Strive to meet color contrast minimum standards"; "Prefer
/// system-defined colors" and "Convey information with more than color alone"; iOS
/// default control size "44x44pt". HIG Materials: "In visionOS, iOS, iPadOS, macOS and
/// tvOS, … use vibrant colors on top of materials for legibility" and "Consider contrast
/// and visual separation when choosing a material"; Reduce Transparency and Increase
/// Contrast must keep content legible. WCAG 2.2 1.4.3 (text 4.5:1) and 1.4.11 (non-text 3:1).
@MainActor
@Suite(.serialized)
struct RankingsPagerCardAccessibilityTests {
    /// WCAG 1.4.3 minimum for the badge's text.
    static let textContrast = 4.5
    /// WCAG 1.4.11 minimum for an enabled arrow's glyph (a graphic needed to identify it).
    static let glyphContrastMinimum = 3.0

    @Test("Each pager control's accessibility frame is its drawn card, so its focus ring and target sit on the card",
          arguments: PagerCardMode.allCases)
    func accessibilityFramesAreTheCards(mode: PagerCardMode) throws {
        let hosted = try HostedPager.host(mode, page: 2)
        defer { hosted.close() }
        let pixels = try PagerPixels(try nativeHostedImage(hosted.host), size: pagerPageSize)
        let backdrop = pixels.rgb(CGPoint(x: 2, y: 2))
        func isCard(_ point: CGPoint) -> Bool { channelDistance(pixels.rgb(point), backdrop) > 24 }

        var previous: CGRect?
        for id in pagerControls {
            let frame = try hosted.frame(id)
            #expect(frame.width >= 43.5 && frame.height >= 43.5, "\(id) target \(frame)")
            // On the card just inside each edge's midpoint, off it just outside.
            let inside = [
                CGPoint(x: frame.minX + 2, y: frame.midY), CGPoint(x: frame.maxX - 2, y: frame.midY),
                CGPoint(x: frame.midX, y: frame.minY + 2), CGPoint(x: frame.midX, y: frame.maxY - 2),
            ]
            let outside = [
                CGPoint(x: frame.minX - 2.5, y: frame.midY), CGPoint(x: frame.maxX + 2.5, y: frame.midY),
                CGPoint(x: frame.midX, y: frame.minY - 2.5), CGPoint(x: frame.midX, y: frame.maxY + 2.5),
            ]
            for point in inside {
                #expect(isCard(point), "\(mode): \(id) frame \(frame) is off its card at \(point): \(pixels.rgb(point))")
            }
            for point in outside {
                #expect(!isCard(point), "\(mode): \(id) card reaches past its frame \(frame) at \(point): \(pixels.rgb(point))")
            }
            // Separate cards, not one plate: the backdrop shows between neighbours.
            if let previous {
                let gap = CGPoint(x: (previous.maxX + frame.minX) / 2, y: frame.midY)
                #expect(frame.minX - previous.maxX >= 8, "\(id) spacing")
                #expect(!isCard(gap), "\(mode): one plate joins \(id) to its neighbour at \(gap)")
            }
            previous = frame
        }
    }

    @Test("On the opaque card the badge's text and the enabled arrows keep their contrast over a white page",
          arguments: PagerCardMode.allCases.filter(\.opaque))
    func badgeAndArrowsKeepContrastOnTheOpaqueCard(mode: PagerCardMode) async throws {
        let hosted = try HostedPager.host(mode, page: 2, backdrop: whiteBackdrop)
        defer { hosted.close() }
        let pixels = try PagerPixels(try await nativeHostedSettle(hosted.host), size: pagerPageSize)
        for id in pagerControls {
            let isBadge = id.hasSuffix("page-info")
            let measured = glyphContrast(pixels, in: cardInterior(try hosted.frame(id), badge: isBadge))
            let minimum = isBadge ? Self.textContrast : Self.glyphContrastMinimum
            #expect(measured.glyphPixels >= 20, "\(mode): \(id) has no glyph pixels (\(measured))")
            #expect(measured.ratio >= minimum,
                    "\(mode): \(id) renders \(String(format: "%.2f", measured.ratio)):1 on its card, below \(minimum):1 (\(measured))")
        }
    }

    @Test("On the opaque card a disabled arrow's glyph shows, visibly dimmer than an enabled one",
          arguments: PagerCardMode.allCases.filter(\.opaque))
    func disabledArrowsLookDisabled(mode: PagerCardMode) async throws {
        let hosted = try HostedPager.host(mode, page: 1, backdrop: whiteBackdrop)
        defer { hosted.close() }
        let pixels = try PagerPixels(try await nativeHostedSettle(hosted.host), size: pagerPageSize)
        func contrast(_ suffix: String) throws -> Double {
            glyphContrast(pixels, in: cardInterior(try hosted.frame("\(pagerPrefix).\(suffix)"), badge: false)).ratio
        }
        for (disabled, enabled) in [("page-first", "page-last"), ("page-previous", "page-next")] {
            let dim = try contrast(disabled), bright = try contrast(enabled)
            #expect(dim >= 1.3, "\(mode): disabled \(disabled) glyph vanished (\(dim):1)")
            #expect(bright >= dim * 1.5, "\(mode): \(disabled) \(dim):1 is not dimmer than \(enabled) \(bright):1")
        }
    }

    @Test("Player Bands' cards are named buttons with a hint and a full-width target, one card per band")
    func playerBandsCardsAreNamedButtons() async throws {
        let fixture = try await bandsFixtureSession()
        let payload = try await fixture.session.playerBands(
            accountId: "fixture-player-1", group: .all, page: 1, pageSize: 25
        )
        let entries = payload.list.entries
        let size = CGSize(width: 402, height: 900)
        let opened = OpenedRoutes()
        let host = nativeHostedView(
            NavigationStack {
                PlayerBandsScreen(session: fixture.session, accountId: "fixture-player-1", displayName: "Fixture Player 1")
                    .navigationDestination(for: AppRoute.self) { route in
                        Text("Band").onAppear { opened.routes.append(route) }
                    }
            }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame("fst.player-bands.row.\(entries[0].id)", in: host) != nil
                && nativeHostedAccessibilityFrame("fst.player-bands.page-last", in: host) != nil
        }
        let nodes = macAccessibilityTree(host)
        let tree = nodes.map(\.description).joined(separator: "\n")

        var frames: [CGRect] = []
        for entry in entries {
            let id = "fst.player-bands.row.\(entry.id)"
            guard let node = nodes.first(where: { $0.identifier == id && $0.isElement }),
                  let frame = nativeHostedAccessibilityFrame(id, in: host),
                  frame.maxY <= size.height - 60 else { continue }
            #expect(node.role == NSAccessibility.Role.button.rawValue, "\(id) is a button: \(node)")
            #expect(node.spokenName == PlayerBandRow.spokenLabel(entry), "\(id) reads its members: \(node)")
            #expect(node.help == "Opens band", "\(id) hint: \(node)")
            #expect(node.isEnabled, "\(id) enabled")
            #expect(frame.height >= 43.5, "\(id) target \(frame)")
            // Full width between the 16 pt margins; the Mac may reserve its legacy
            // scroller's gutter (up to 17 pt) on the trailing side.
            #expect(abs(frame.minX - 16) <= 1 && frame.maxX <= size.width - 15 && frame.maxX >= size.width - 16 - 18,
                    "\(id) spans the page between 16 pt margins: \(frame)")
            frames.append(frame)
        }
        #expect(frames.count >= 3, "visible band cards in:\n\(tree)")
        // One card per band: the page shows between cards (the leaderboard rows' gap).
        for (above, below) in zip(frames, frames.dropFirst()) {
            #expect(abs(below.minY - above.maxY - 8) <= 1, "card gap \(above) → \(below)")
        }
        // No card adds an unnamed element of its own; the chevron is hidden.
        #expect(macAccessibilityFindings(nodes) == [], "unnamed controls or images:\n\(tree)")
        #expect(!nodes.contains { $0.isElement && $0.identifier.isEmpty && $0.label == "chevron.forward" })

        // AXPress opens the band, as a tap does.
        try pressCard("fst.player-bands.row.\(entries[0].id)", in: host)
        _ = try await nativeHostedSettle(host, timeout: .seconds(30)) { !opened.routes.isEmpty }
        let entry = entries[0]
        #expect(opened.routes == [
            .band(bandId: entry.bandId, name: entry.membersLabel, bandType: entry.bandType, teamKey: entry.teamKey),
        ], "AXPress opens the card's band")
    }

    // MARK: - The other band and member cards (same card-link structure)

    @Test("Band Detail's member cards and song rows open through AXPress",
          arguments: ["fst.band.member.fixture-band-1-a", "fst.band.song-row.fixture-pulse"])
    func bandDetailCardsOpenThroughAXPress(identifier: String) async throws {
        let fixture = try await bandsFixtureSession()
        let size = CGSize(width: 402, height: 2000)
        let opened = OpenedRoutes()
        let host = nativeHostedView(
            NavigationStack {
                BandDetailScreen(
                    session: fixture.session, bandId: "fixture-band-1", name: "Band 1 Member A + Band 1 Member B",
                    bandType: "Band_Duets", teamKey: "fixture-team-1"
                )
                .navigationDestination(for: AppRoute.self) { route in
                    Text("Destination").onAppear { opened.routes.append(route) }
                }
            }
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, untilText: ["Five Worst Songs", "Fixture Pulse"])
        let node = try #require(macAccessibilityTree(host).first { $0.identifier == identifier && $0.isElement })
        #expect(node.role == NSAccessibility.Role.button.rawValue, "\(identifier) is a button: \(node)")
        try pressCard(identifier, in: host)
        _ = try await nativeHostedSettle(host, timeout: .seconds(30)) { !opened.routes.isEmpty }
        switch opened.routes.first {
        case let .player(accountId, _)? where identifier.hasPrefix("fst.band.member."):
            #expect(accountId == "fixture-band-1-a")
        case let .songDetail(song)? where identifier.hasPrefix("fst.band.song-row."):
            #expect(song.songId == "fixture-pulse")
        default:
            Issue.record("AXPress on \(identifier) opened \(opened.routes)")
        }
    }

    @Test("Song Detail's band preview card opens its band through AXPress")
    func songBandPreviewCardOpensThroughAXPress() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "contracts/fixtures/song-band-leaderboards-demo.json"))
        let response = try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: data)
        let entry = try #require(response.preview(for: .duets).entries.first)
        let size = CGSize(width: 402, height: 300)
        let opened = OpenedRoutes()
        let host = nativeHostedView(
            NavigationStack {
                VStack {
                    SongBandPreviewRow(entry: entry, highlighted: false)
                        .accessibilityIdentifier("fst.test.band-preview")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .navigationDestination(for: AppRoute.self) { route in
                    Text("Destination").onAppear { opened.routes.append(route) }
                }
            }
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host) {
            nativeHostedAccessibilityFrame("fst.test.band-preview", in: host) != nil
        }
        let node = try #require(macAccessibilityTree(host).first { $0.identifier == "fst.test.band-preview" && $0.isElement })
        #expect(node.role == NSAccessibility.Role.button.rawValue, "the card is a button: \(node)")
        #expect(node.spokenName == SongBandPreviewText.spokenLabel(entry, selected: false))
        try pressCard("fst.test.band-preview", in: host)
        _ = try await nativeHostedSettle(host, timeout: .seconds(30)) { !opened.routes.isEmpty }
        #expect(opened.routes == [SongBandRowNavigation.bandRoute(entry)], "AXPress opens the card's band")
    }

    /// Press a card the way VoiceOver (VO-Space), Voice Control and Switch Control do:
    /// its AXPress action (`SongBandFooterAccessibilityTests.press`).
    ///
    /// - Parameters:
    ///   - identifier: The card's identifier.
    ///   - host: The hosting view.
    /// - Throws: A missing card or one without a press action.
    private func pressCard(_ identifier: String, in host: NSView) throws {
        let card = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(card.responds(to: press), "\(identifier) offers a press action")
        _ = card.perform(press)
    }
}
#endif
