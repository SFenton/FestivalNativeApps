#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Player profile top accessibility (issue #97, backfilled by #446)

// #97 removed the avatar-and-name card from the top of `PlayerProfileContent`: the
// navigation title alone names the player, and a card is drawn only while a
// selection-pause notice or a Select/Switch error applies. These hosted checks (macOS
// host, `apple-ci`) pin what that region exposes to VoiceOver on every Apple platform,
// since the page is the same SwiftUI on iPhone, iPad, iPhone Duo and Mac: the player's
// name is read once (by the title), the content starts at its first heading, a pause
// notice reads before it as plain text, and the notice wraps whole at the largest text
// size in a narrow column.

// MARK: - Fixture

/// The shared loopback fixture service (`tools/mock_service.py`) as an unpinned service:
/// the publication reports pinning off and the compact player read carries no
/// publication header, like a service before the edge enables pinning.
///
/// The read then proves no publication (`PlayerProfilePayload.publicationId == nil`), so
/// the page shows the `.unverified` pause notice (`PlayerProfileIdentityNotice`).
private struct HeaderlessPlayerTransport: HTTPTransport {
    let base = URLSessionHTTPTransport()

    /// Forward a public GET; turn pinning off in `/api/publication` and strip
    /// `X-FST-Publication-Id` from `/api/player/{id}`.
    ///
    /// - Parameter request: A keyless public read.
    /// - Returns: The fixture response, unpinned for the publication and player reads.
    /// - Throws: Transport errors from the loopback service, or a malformed publication.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let result = try await base.send(request)
        if request.url?.path == "/api/publication" {
            var object = try #require(try JSONSerialization.jsonObject(with: result.data) as? [String: Any])
            object["readyForPinning"] = false
            object["pinningEnabled"] = false
            return HTTPResult(status: result.status, data: try JSONSerialization.data(withJSONObject: object))
        }
        let prefix = "/api/player/"
        guard let path = request.url?.path, path.hasPrefix(prefix),
              !path.dropFirst(prefix.count).contains("/") else { return result }
        var headers: [String: String] = [:]
        if let type = result.header("Content-Type") { headers["Content-Type"] = type }
        return HTTPResult(status: result.status, data: result.data, headers: headers)
    }
}

/// Fixture player's display name (`tools/mock_service.py`).
private let a11yPlayerName = "Fixture Player 1"
/// The page's first section heading (`PlayerProfileContent.overallSection`).
private let a11yFirstHeading = "Global Statistics"

/// A session over the fixture service; `selected` stores the fixture player as selected,
/// `headerless` drops the player read's publication header.
@MainActor
private func profileA11ySession(selected: Bool, headerless: Bool) async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let transport: any HTTPTransport = headerless ? HeaderlessPlayerTransport() : URLSessionHTTPTransport()
    let client = try FestivalAPI(baseURL: baseURL, transport: transport)
    let defaults = try #require(UserDefaults(suiteName: "fst.tests.profile-a11y.\(UUID().uuidString)"))
    if selected {
        defaults.set(
            Data(#"{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}"#.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

/// One hosted profile page.
@MainActor
private struct HostedProfile {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
}

/// Host `PlayerProfileContent` for the fixture player and wait until it has loaded.
///
/// - Parameters:
///   - session: Fixture session.
///   - width: Window width (402 pt is an iPhone; 320 pt the narrowest column).
///   - dynamicTypeSize: Text size the page is drawn at.
///   - ready: Text that must be readable before the tree is read.
/// - Returns: The host and its window (order it out when done).
@MainActor
private func hostProfile(
    _ session: FestivalSession, width: CGFloat = 402,
    dynamicTypeSize: DynamicTypeSize = .large, ready: [String]
) async throws -> HostedProfile {
    let size = CGSize(width: width, height: 1400)
    let host = nativeHostedView(
        AnyView(
            NavigationStack {
                PlayerProfileContent(session: session, accountId: "fixture-player-1", routeDisplayName: nil)
            }
            .dynamicTypeSize(dynamicTypeSize)
            .preferredColorScheme(.dark)
        ),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    _ = try await nativeHostedSettle(host, untilText: ready, excluding: ["Loading Profile"], timeout: .seconds(60))
    return HostedProfile(host: host, window: window)
}

/// Elements VoiceOver speaks inside the profile's scroll content (`fst.player.available`),
/// in reading order: named elements only, so an unnamed grouping container (a section's
/// `AXGroup`) does not count as a stop.
///
/// - Parameters:
///   - nodes: The hosted tree (``macAccessibilityTree(_:)``).
///   - namedOnly: Pass `false` for every element, unnamed ones included (findings).
/// - Returns: The elements inside the page content.
private func profileContentElements(_ nodes: [MacAXNode], namedOnly: Bool = true) -> [MacAXNode] {
    guard let start = nodes.firstIndex(where: { $0.identifier == "fst.player.available" }) else { return [] }
    let depth = nodes[start].depth
    var content: [MacAXNode] = []
    for node in nodes[(start + 1)...] {
        if node.depth <= depth { break }
        if node.isElement, !namedOnly || !node.spokenName.isEmpty { content.append(node) }
    }
    return content
}

// MARK: - Tests

/// Accessibility of the top of the player profile after #97.
///
/// HIG VoiceOver: "Use titles and headings to convey hierarchy"; HIG Layout: "Place
/// important content toward the top/leading side in reading order"; HIG Accessibility:
/// text enlargement "of at least 200%".
@MainActor
@Suite(.serialized)
struct PlayerProfileAccessibilityTests {
    /// The selected player's page (Statistics root and the pushed route alike) names the
    /// player only in its title: the content's first element is the Global Statistics
    /// heading, and no avatar image, name text or empty notice card comes before it.
    @Test func profileContentStartsAtFirstHeadingWithoutNameCard() async throws {
        let session = try await profileA11ySession(selected: true, headerless: false)
        let page = try await hostProfile(session, ready: [a11yFirstHeading])
        defer { page.window.orderOut(nil) }
        let nodes = macAccessibilityTree(page.host)
        macAccessibilityDump(nodes, name: "profile-selected")
        let content = profileContentElements(nodes)
        try #require(!content.isEmpty, "profile content is in the tree: \(nodes)")
        let first = try #require(content.first)
        #expect(first.role == "AXHeading" && first.spokenName == a11yFirstHeading,
                "content starts at \(a11yFirstHeading): \(content.prefix(4))")
        #expect(!nodes.contains { $0.identifier == "fst.player.name" }, "no name card")
        #expect(!content.contains { $0.spokenName == a11yPlayerName }, "the name is not read again under the title")
        for id in ["fst.player.unverified", "fst.player.preview-changed", "fst.player.action-error"] {
            #expect(!nodes.contains { $0.identifier == id }, "no \(id) without a pause")
        }
        #expect(macAccessibilityFindings(profileContentElements(nodes, namedOnly: false)) == [])
    }

    /// A viewed player whose read proves no publication shows the pause notice first: one
    /// static text with the whole message, nothing actionable in its card, then the Global
    /// Statistics heading. The name is still not repeated under the title.
    @Test func pauseNoticeReadsBeforeFirstHeading() async throws {
        let session = try await profileA11ySession(selected: false, headerless: true)
        let message = PlayerProfileIdentityNotice.unverified.message
        let page = try await hostProfile(session, ready: [message, a11yFirstHeading])
        defer { page.window.orderOut(nil) }
        let nodes = macAccessibilityTree(page.host)
        macAccessibilityDump(nodes, name: "profile-unverified")
        let content = profileContentElements(nodes)
        try #require(content.count >= 2, "profile content is in the tree: \(nodes)")
        #expect(content[0].identifier == PlayerProfileIdentityNotice.unverified.accessibilityIdentifier
                && content[0].role == "AXStaticText" && content[0].spokenName == message,
                "the notice reads first, as text: \(content.prefix(4))")
        #expect(content[1].role == "AXHeading" && content[1].spokenName == a11yFirstHeading,
                "then \(a11yFirstHeading): \(content.prefix(4))")
        #expect(content.filter { $0.spokenName == message }.count == 1, "the notice is read once")
        #expect(!content.contains { $0.spokenName == a11yPlayerName }, "no name card")
        #expect(macAccessibilityFindings(profileContentElements(nodes, namedOnly: false)) == [])
    }

    /// At AX5 in the narrowest column the notice wraps whole: its gold ink (the notice is
    /// the only gold text above the first heading) covers as many lines as the message
    /// needs at its width, inside the window, and ends above the heading, so a line limit
    /// or a clipped card would fail.
    @Test func pauseNoticeWrapsWholeAtLargestTextInNarrowColumn() async throws {
        let session = try await profileA11ySession(selected: false, headerless: true)
        let notice = PlayerProfileIdentityNotice.unverified
        let width: CGFloat = 320
        let page = try await hostProfile(
            session, width: width, dynamicTypeSize: .accessibility5, ready: [notice.message, a11yFirstHeading]
        )
        defer { page.window.orderOut(nil) }
        let frame = try #require(nativeHostedAccessibilityFrame(notice.accessibilityIdentifier, in: page.host))
        let heading = try #require(nativeHostedAccessibilityElement(in: page.host) {
            nativeHostedAccessibilityString($0, "accessibilityLabel") == a11yFirstHeading
        })
        let headingFrame = try #require(nativeHostedAccessibilityFrame(of: heading, in: page.host))
        #expect(frame.minX >= 0 && frame.maxX <= width, "notice inside the window: \(frame)")
        let font = NSFont.preferredFont(forTextStyle: .footnote)
        let needed = (notice.message as NSString).boundingRect(
            with: CGSize(width: frame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height
        let neededLines = Int((needed / (font.ascender - font.descender + font.leading)).rounded())
        try #require(neededLines >= 2, "the message wraps at \(frame.width) pt")
        let above = CGRect(x: 0, y: 0, width: width, height: headingFrame.minY)
        let ink = try goldInkLines(page.host, in: above)
        #expect(ink.lines == neededLines, "notice shows \(ink.lines) of \(neededLines) lines")
        #expect(ink.bottom > 0 && ink.bottom <= headingFrame.minY, "notice ink ends above the heading")
    }
}

/// Gold text lines (``BrandTokens/gold``, the notice colour) inside `rect` of a capture.
///
/// - Parameters:
///   - host: The hosted page.
///   - rect: Region in the host's top-left points.
/// - Returns: Separate runs of pixel rows holding gold ink, and the last such row in points.
/// - Throws: An unavailable capture.
@MainActor
private func goldInkLines<Content: View>(
    _ host: NSHostingView<Content>, in rect: CGRect
) throws -> (lines: Int, bottom: CGFloat) {
    let image = try nativeHostedImage(host, in: rect)
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
    try #require(drawn, "capture of \(rect)")
    var lines = 0
    var last = -1
    var inLine = false
    for y in 0..<height {
        let gold = (0..<width).contains { x in
            let pixel = (y * width + x) * 4
            return bytes[pixel] > 180 && bytes[pixel + 1] > 140 && bytes[pixel + 2] < 90
        }
        if gold, !inLine { lines += 1 }
        if gold { last = y }
        inLine = gold
    }
    return (lines, last < 0 ? 0 : CGFloat(last + 1) * rect.height / CGFloat(height))
}
#endif
