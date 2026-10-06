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
            song: song(title), session: try offlineSession(), onHeightChange: { _ in }
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

    // MARK: Scrolled away

    @Test func scrollAwayPolicyWaitsForTheHeadersBottomEdge() {
        #expect(!SongHeaderScrollAway.isHidden(offset: 0, headerBottom: 120))
        #expect(!SongHeaderScrollAway.isHidden(offset: 119, headerBottom: 120))
        #expect(SongHeaderScrollAway.isHidden(offset: 120, headerBottom: 120))
        #expect(SongHeaderScrollAway.isHidden(offset: 400, headerBottom: 120))
        #expect(!SongHeaderScrollAway.isHidden(offset: 400, headerBottom: 0), "unmeasured header")
        #expect(!SongHeaderScrollAway.isHidden(offset: .infinity, headerBottom: 120))
    }

    /// Scrolled under the bar, a board's header is reported hidden (the boards then
    /// build the pinned ``SongBarTitleToolbarItem``); scrolled back, shown again. Covers
    /// the Song Leaderboard's `List`, whose recycled header row once never reported it,
    /// and the Band Song Leaderboard's `ScrollView`, on both reading paths.
    @Test(arguments: [false, true], [false, true])
    func boardHeaderReportsWhenItScrollsAway(inList: Bool, legacy: Bool) async throws {
        final class State { var hidden: Bool? }
        let state = State()
        let size = CGSize(width: rowWidth, height: 300)
        let host = nativeHostedView(
            SongHeaderScrollAwayProbe(
                song: song(long), session: try offlineSession(), inList: inList, legacy: legacy
            ) {
                state.hidden = $0
            },
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host)
        let scroll = try #require(Self.scrollView(in: host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 30))
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host)
        #expect(state.hidden != true, "still under the header's bottom edge")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host) { state.hidden == true }
        #expect(state.hidden == true)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host) { state.hidden == false }
        #expect(state.hidden == false)
    }

    /// Song Details' hero reports its title's bottom edge in the scroll content, so the
    /// threshold stays put while the page scrolls (scroll-view coordinates move with
    /// the bar, which hid the pinned title again in a loop), and the page pins the
    /// title once that edge passes the top.
    @Test(arguments: [false, true])
    func heroTitleBottomIsMeasuredInTheContent(legacy: Bool) async throws {
        final class State { var hidden: Bool?; var bottoms: [CGFloat] = [] }
        let state = State()
        let size = CGSize(width: rowWidth, height: 300)
        let host = nativeHostedView(
            SongDetailHeroScrollAwayProbe(
                title: long, legacy: legacy,
                onBottom: { state.bottoms.append($0) }, action: { state.hidden = $0 }
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host) { !state.bottoms.isEmpty }
        let bottom = try #require(state.bottoms.last)
        #expect(bottom > 16 && bottom < 120, "title bottom below the 16 pt padding: \(bottom)")
        let scroll = try #require(Self.scrollView(in: host))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom - 10))
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host)
        #expect(state.hidden != true, "title still partly below the top")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)
        _ = try await nativeHostedSettle(host) { state.hidden == true }
        #expect(state.hidden == true)
        #expect(state.bottoms.last == bottom, "scrolling moved the threshold: \(state.bottoms)")
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
            SongHeaderRow(song: song(long), session: try offlineSession(), onHeightChange: { _ in }) {
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

    // MARK: Pinned bar title

    /// Lay out the pinned bar title in the width a bar offers its title slot.
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - offered: Width the bar offers.
    ///   - size: Dynamic Type size.
    /// - Returns: The title's laid-out size.
    private func barTitleSize(
        _ title: String, offered: CGFloat, _ size: DynamicTypeSize = .large
    ) throws -> CGSize {
        let probe = SizeProbe()
        let host = NSHostingView(rootView: SongBarTitle(song: song(title), session: try offlineSession(), caption: "Lead")
            .onGeometryChange(for: CGSize.self) { $0.size } action: { probe.size = $0 }
            .environment(\.dynamicTypeSize, size)
            .environment(\.marqueeAnimationEnabled, false)
            .frame(width: offered, alignment: .leading))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return probe.size
    }

    /// Size measured by the probe after layout.
    private final class SizeProbe { var size: CGSize = .zero }

    /// R4: an overflowing bar title takes every point the bar offers (no fixed cap, so
    /// it scrolls only once that space runs out), on a phone-width bar and a wide iPad
    /// or Mac bar alike; a short one keeps its own width so the bar centres it.
    @Test(arguments: [258, 640] as [CGFloat])
    func barTitleFillsTheOfferedWidth(offered: CGFloat) throws {
        let longer = "\(long), \(long)"
        let measured = try barTitleSize(longer, offered: offered).width
        // A clipped line ends on a whole glyph, so it can stop a few points short.
        #expect(measured > offered - 12 && measured <= offered, "\(measured)")
        #expect(measured > 240, "the former fixed cap")
        #expect(try barTitleSize("One", offered: offered).width < 120)
    }

    /// R4: the bar title stays on one line at accessibility sizes.
    @Test func barTitleStaysOnOneLineAtAccessibilitySizes() throws {
        let longer = "\(long), \(long)"
        #expect(
            try barTitleSize(longer, offered: 258, .accessibility5).height
                == barTitleSize("One", offered: 258, .accessibility5).height
        )
    }
}

/// A board's scroll content (the Song Leaderboard's `List` or the Band Song
/// Leaderboard's `ScrollView`): the song header 20 pt below the top, then rows, with
/// ``SwiftUI/View/songHeaderScrollAway(headerBottom:legacy:action:)`` following the
/// header's measured height, like the boards.
private struct SongHeaderScrollAwayProbe: View {
    let song: Song
    let session: FestivalSession
    let inList: Bool
    let legacy: Bool
    let action: (Bool) -> Void
    @State private var headerHeight: CGFloat = 0

    private var header: some View {
        SongHeaderRow(song: song, session: session, onHeightChange: { headerHeight = $0 }) {
            Text("Duos")
        }
    }

    var body: some View {
        Group {
            if inList {
                List {
                    header.listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
                    Color.clear.frame(height: 1_600)
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        header.padding(.top, 20)
                        Color.clear.frame(height: 1_600)
                    }
                }
            }
        }
        .songHeaderScrollAway(headerBottom: 20 + headerHeight, legacy: legacy, action: action)
    }
}
/// Song Details' scroll content in miniature: the hero ``SongHeaderText`` reporting its
/// title's bottom edge in ``SwiftUI/View/songHeaderContentSpace()``, which drives
/// ``SwiftUI/View/songHeaderScrollAway(headerBottom:legacy:action:)``.
private struct SongDetailHeroScrollAwayProbe: View {
    let title: String
    let legacy: Bool
    let onBottom: (CGFloat) -> Void
    let action: (Bool) -> Void
    @State private var titleBottom: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SongHeaderText(
                    title: title, artist: "Synthetic Quartet", titleFont: .title.bold(), spacing: 8,
                    onTitleBottomChange: { titleBottom = $0; onBottom($0) }
                ) {
                    Text("2026")
                }
                Color.clear.frame(height: 1_600)
            }
            .padding(16)
            .songHeaderContentSpace()
        }
        .songHeaderScrollAway(headerBottom: titleBottom, legacy: legacy, action: action)
    }
}
#endif
