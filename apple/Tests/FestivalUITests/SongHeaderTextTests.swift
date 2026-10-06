#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// The in-page song header's title fills the width beside the art on one line
/// (scrolling when it overflows) instead of wrapping beside empty space (issue #315),
/// and still wraps at accessibility text sizes.
@MainActor
struct SongHeaderTextTests {
    /// Width measured by the probe after layout.
    private final class Probe { var width: CGFloat = 0 }

    private let long = "Through the Fire and Flames and Several More Words"
    private let rowWidth: CGFloat = 320
    private let artWidth: CGFloat = 80
    private let spacing: CGFloat = 12

    /// Lay out a header row (art placeholder + text column) like Song Leaderboard's.
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - size: Dynamic Type size.
    ///   - probe: Receives the text column's laid-out width.
    /// - Returns: The row's fitting height.
    private func layout(_ title: String, _ size: DynamicTypeSize = .large, probe: Probe = Probe()) -> CGFloat {
        let host = NSHostingView(rootView: HStack(spacing: spacing) {
            Color.clear.frame(width: artWidth, height: 1)
            SongHeaderText(title: title, artist: "DragonForce", titleFont: .title3.bold(), spacing: 4) {
                EmptyView()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { probe.width = $0 }
        }
        .environment(\.dynamicTypeSize, size)
        .environment(\.marqueeAnimationEnabled, false)
        .frame(width: rowWidth))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test func longTitleStaysOnOneLine() {
        #expect(layout(long) == layout("One"), "a long title must not wrap at standard sizes")
    }

    @Test func columnFillsTheWidthBesideTheArt() {
        let probe = Probe()
        _ = layout("One", probe: probe)
        #expect(probe.width == rowWidth - artWidth - spacing)
    }

    @Test func wrapsAtAccessibilitySizes() {
        #expect(layout(long, .accessibility5) > layout("One", .accessibility5))
    }

    // MARK: Leaderboard header row

    /// A session whose client points at a closed loopback port; the rows below carry
    /// no artwork, so nothing is requested.
    private func offlineSession() throws -> FestivalSession {
        let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:9")!)
        return FestivalSession(factory: { client })
    }

    /// A song with no artwork.
    private func song(_ title: String) -> Song {
        Song(
            songId: "fixture-song", title: title, artist: "DragonForce", album: nil,
            year: 2006, durationSeconds: 441, albumArt: nil, difficulty: nil,
            pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
        )
    }

    /// Lay out the shared leaderboard header (Song Leaderboard, Band Song Leaderboard).
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - size: Dynamic Type size.
    ///   - probe: Receives the row's laid-out width.
    /// - Returns: The row's fitting height.
    private func rowLayout(
        _ title: String, _ size: DynamicTypeSize = .large, probe: Probe = Probe()
    ) throws -> CGFloat {
        let host = NSHostingView(rootView: SongHeaderRow(
            song: song(title), session: try offlineSession(), onScrolledAway: { _ in }
        ) {
            Text("Duos")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { probe.width = $0 }
        .environment(\.dynamicTypeSize, size)
        .environment(\.marqueeAnimationEnabled, false)
        .frame(width: rowWidth))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test func leaderboardHeaderKeepsALongTitleOnOneFullWidthLine() throws {
        #expect(try rowLayout(long) == rowLayout("One"), "a long title must not wrap at standard sizes")
        let probe = Probe()
        _ = try rowLayout("One", probe: probe)
        #expect(probe.width == rowWidth, "the header row must span the page width")
    }

    /// macOS fonts do not grow with Dynamic Type, so the title must wrap past the
    /// 80 pt art to change the row's height.
    @Test func leaderboardHeaderWrapsAtAccessibilitySizes() throws {
        let longer = "\(long), \(long)"
        #expect(try rowLayout(longer, .accessibility5) > rowLayout("One", .accessibility5))
        #expect(try rowLayout(longer) == rowLayout("One"))
    }

    /// Scrolled under the bar, the header reports it (the boards then build the pinned
    /// ``SongBarTitleToolbarItem``); scrolled back, it reports it again.
    @Test func leaderboardHeaderReportsWhenItScrollsAway() async throws {
        final class Hidden { var value: Bool? }
        let hidden = Hidden()
        let size = CGSize(width: rowWidth, height: 300)
        let session = try offlineSession()
        let host = nativeHostedView(
            ScrollView {
                VStack(spacing: 0) {
                    SongHeaderRow(song: song(long), session: session, onScrolledAway: {
                        hidden.value = $0
                    }) {
                        Text("Duos")
                    }
                    Color.clear.frame(height: 1_200)
                }
            },
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host) { hidden.value == false }
        let scroll = try #require(Self.scrollView(in: host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host) { hidden.value == true }
        #expect(hidden.value == true)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host) { hidden.value == false }
        #expect(hidden.value == false)
    }

    /// The first scroll view under `view`.
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = scrollView(in: subview) { return found }
        }
        return nil
    }

    /// VoiceOver meets the header as one heading that names the song once.
    @Test func leaderboardHeaderIsOneHeadingNamingTheSongOnce() throws {
        nativeHostedEnableAccessibility()
        let host = nativeHostedView(
            SongHeaderRow(song: song(long), session: try offlineSession(), onScrolledAway: { _ in }) {
                Text("Duos")
            }
            .accessibilityIdentifier("fst.test.song-header")
            .environment(\.marqueeAnimationEnabled, false),
            size: CGSize(width: rowWidth, height: 200)
        )
        let window = nativeHostedWindow(host, size: CGSize(width: rowWidth, height: 200))
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let tree = nativeHostedAccessibility(host)
        #expect(tree.identifiers.contains("fst.test.song-header"))
        #expect(tree.texts.filter { $0.contains(long) }.count == 1, "texts: \(tree.texts)")
        #expect(tree.contains("DragonForce") && tree.contains("Duos"))
    }
}
#endif
