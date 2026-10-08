#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Item Shop list row accessibility (issue #18, backfilled by #397)

/// Item Shop list rows render the shared Songs ``SongRowView`` with the Shop decoration
/// (issue #18). These hosted checks pin what that row exposes to VoiceOver, Voice Control
/// and Dynamic Type on every Apple platform (the row is the same SwiftUI on iPhone,
/// iPad, iPhone Duo and Mac): names, roles and Shop state, reading order, the official
/// bag's 44 pt target and the accessibility-size layout. HIG Accessibility: "Provide
/// VoiceOver descriptions for all interface elements"; "Never rely on color alone";
/// iOS/iPadOS default control size 44×44 pt; HIG Typography: "Keep text truncation to a
/// minimum as font size increases".
@MainActor
@Suite(.serialized)
struct ShopRowAccessibilityTests {
    // MARK: - Fixture

    /// A display-only offer (no catalogue song) whose title and artist overflow the row.
    static let unlisted = (
        id: "fixture-unlisted",
        title: "Fixture Unlisted Encore With A Deliberately Long Title That Runs Well Past The Row Edge",
        artist: "Synthetic Ensemble Featuring A Long List Of Guest Performers"
    )

    /// The checked-in Shop fixture (Fixture Pulse New, Fixture Orbit Leaving Tomorrow)
    /// plus one plain offer missing from the catalogue.
    ///
    /// - Returns: Shop envelope bytes.
    /// - Throws: Missing or malformed checked-in fixture.
    static func offersBytes() throws -> Data {
        let bytes = try shopFixtureBytes().offers
        var root = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var songs = try #require(root["songs"] as? [[String: Any]])
        var extra = try #require(songs.first)
        extra["songId"] = unlisted.id
        extra["title"] = unlisted.title
        extra["artist"] = unlisted.artist
        extra["shopUrl"] = "https://www.fortnite.com/item-shop/jam-tracks/\(unlisted.id)"
        extra["isNew"] = false
        extra["leavingTomorrow"] = false
        songs.append(extra)
        root["songs"] = songs
        root["count"] = songs.count
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// One hosted Item Shop list over the fixture transport.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    /// Host the Shop list on a phone-width page at a Dynamic Type size and wait for
    /// all three offers.
    ///
    /// - Parameter typeSize: Dynamic Type size for the whole page.
    /// - Returns: The settled host, its window and storage.
    /// - Throws: Missing fixture or an unavailable capture.
    static func hostList(_ typeSize: DynamicTypeSize) async throws -> Hosted {
        let catalogue = try shopFixtureBytes().catalogue
        let suiteName = "fst-shop-row-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        storage.set(ShopViewMode.list.rawValue, forKey: "fst.shop.viewMode")
        let transport = HostedShopTransport(scenario: .populated, offers: try offersBytes(), catalogue: catalogue)
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let size = CGSize(width: 390, height: 1100)
        let host = nativeHostedView(
            AnyView(
                NavigationStack { ShopScreen(session: session, isVisible: true) }
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let bags = ["fixture-orbit", "fixture-pulse", unlisted.id].map { "fst.shop.external.\($0)" }
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            bags.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    /// The display-only offer's row: the element whose label carries its full title.
    static func unlistedRowFrame(in host: NSView) -> CGRect? {
        nativeHostedAccessibilityElement(in: host) { element in
            // Plain static text may carry its words as the value rather than the label.
            let name = ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                .map { nativeHostedAccessibilityString(element, $0) }.first { !$0.isEmpty } ?? ""
            return nativeHostedAccessibilityString(element, "accessibilityIdentifier").isEmpty
                && name.contains(unlisted.title) && !name.contains("Open Official Item Shop")
        }.flatMap { nativeHostedAccessibilityFrame(of: $0, in: host) }
    }

    // MARK: - Names, roles and state

    /// Each matched row is one button named by its title, artist line and Shop state
    /// (New / Leaving Tomorrow spoken, not only the gold/red border); a display-only
    /// offer is static text with its full (marquee-scrolled) title; every official bag
    /// says what it opens; the art and chevron stay out of the tree.
    @Test func shopRowsNameTheirActionsAndShopState() async throws {
        let hosted = try await Self.hostList(.large)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "shop-rows-large")
        func node(_ id: String) throws -> MacAXNode {
            try #require(nodes.first { $0.identifier == id && $0.isElement }, "\(id) in\n\(nodes.map(\.description).joined(separator: "\n"))")
        }

        let pulse = try node("fst.shop.song.fixture-pulse")
        let orbit = try node("fst.shop.song.fixture-orbit")
        for (row, title) in [(pulse, "Fixture Pulse"), (orbit, "Fixture Orbit")] {
            #expect(row.role == "AXButton", "\(title) row opens Song Detail: \(row)")
            #expect(row.spokenName.contains(title) && row.spokenName.contains("Synthetic Quartet"), "\(row)")
        }
        #expect(pulse.spokenName.contains(ShopHighlight.new.label), "New is spoken: \(pulse)")
        #expect(!pulse.spokenName.contains(ShopHighlight.leavingTomorrow.label), "\(pulse)")
        #expect(orbit.spokenName.contains(ShopHighlight.leavingTomorrow.label), "Leaving Tomorrow is spoken: \(orbit)")
        #expect(!orbit.spokenName.contains(ShopHighlight.new.label), "\(orbit)")

        // No catalogue song: no Detail button, but the whole title and artist are read.
        #expect(!nodes.contains { $0.identifier == "fst.shop.song.\(Self.unlisted.id)" })
        let plain = try #require(nodes.first {
            $0.isElement && $0.identifier.isEmpty && $0.spokenName.contains(Self.unlisted.title)
        }, "display-only row")
        // Static text at every size, not an unknown element (the marquee used to drop the role).
        #expect(plain.role == "AXStaticText", "a display-only row is text, not an action: \(plain)")
        #expect(plain.spokenName.contains(Self.unlisted.artist), "\(plain)")
        for label in [ShopHighlight.new.label, ShopHighlight.leavingTomorrow.label] {
            #expect(!plain.spokenName.contains(label), "a plain offer has no Shop badge: \(plain)")
        }

        for (id, title) in [("fixture-pulse", "Fixture Pulse"), ("fixture-orbit", "Fixture Orbit"), (Self.unlisted.id, Self.unlisted.title)] {
            let bag = try node("fst.shop.external.\(id)")
            #expect(["AXLink", "AXButton"].contains(bag.role), "\(bag)")
            #expect(bag.spokenName == "\(title), Open Official Item Shop", "\(bag)")
        }

        let symbolNames: Set<String> = ["bag", "bag.fill", "chevron.forward", "clock", "sparkles", "Forward"]
        #expect(!nodes.contains { $0.isElement && symbolNames.contains($0.spokenName) },
                "no symbol or chevron exposed on its own")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// Rows read top to bottom in the sorted (Title A–Z) order, each row before its own
    /// official bag; every bag is a 44×44 pt target inside its row's trailing edge, and
    /// at standard sizes the long title scrolls on one line instead of growing its row.
    @Test func shopRowsReadInVisualOrderWithFullSizeBagTargets() async throws {
        let hosted = try await Self.hostList(.large)
        defer { hosted.close() }
        let host = hosted.host
        let order = macAccessibilityTree(host).filter(\.isElement)
        func index(_ match: (MacAXNode) -> Bool, _ what: String) throws -> Int {
            let found = order.firstIndex(where: match)
            return try #require(found, "\(what) in the reading order")
        }
        var sequence: [Int] = []
        for id in ["fixture-orbit", "fixture-pulse"] {
            sequence.append(try index({ $0.identifier == "fst.shop.song.\(id)" }, "\(id) row"))
            sequence.append(try index({ $0.identifier == "fst.shop.external.\(id)" }, "\(id) bag"))
        }
        sequence.append(try index({ $0.identifier.isEmpty && $0.spokenName.contains(Self.unlisted.title) }, "unlisted row"))
        sequence.append(try index({ $0.identifier == "fst.shop.external.\(Self.unlisted.id)" }, "unlisted bag"))
        #expect(sequence == sequence.sorted() && Set(sequence).count == sequence.count,
                "row, bag, row, bag… in reading order: \(sequence)")

        let rows = try [
            #require(nativeHostedAccessibilityFrame("fst.shop.song.fixture-orbit", in: host)),
            #require(nativeHostedAccessibilityFrame("fst.shop.song.fixture-pulse", in: host)),
            #require(Self.unlistedRowFrame(in: host)),
        ]
        #expect(rows[0].maxY <= rows[1].minY + 0.5 && rows[1].maxY <= rows[2].minY + 0.5,
                "rows stack in reading order: \(rows)")
        for (row, id) in zip(rows, ["fixture-orbit", "fixture-pulse", Self.unlisted.id]) {
            let bag = try #require(nativeHostedAccessibilityFrame("fst.shop.external.\(id)", in: host))
            #expect(bag.width >= ShopRowMetrics.bagSlot - 0.5 && bag.height >= ShopRowMetrics.bagSlot - 0.5,
                    "\(id) bag is a 44 pt target: \(bag)")
            #expect(bag.minY >= row.minY - 0.5 && bag.maxY <= row.maxY + 0.5, "\(id) bag sits on its row: \(bag) in \(row)")
            #expect(bag.maxX <= row.maxX + 0.5 && bag.midX > row.midX, "\(id) bag is at the trailing edge: \(bag) in \(row)")
        }
        // A wrapped line would add at least a caption line (~15 pt); allow sub-line rounding.
        #expect(abs(rows[2].height - rows[0].height) < 4,
                "the long title marquees on one line at standard sizes: \(rows[2].height) vs \(rows[0].height)")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the title and artist wrap (the long offer's
    /// row grows instead of clipping), and each official bag becomes a full-width,
    /// at least 44 pt tall action under its row, still read right after it.
    @Test func shopRowsWrapAndKeepTheBagReachableAtAccessibilitySizes() async throws {
        let standard = try await Self.hostList(.large)
        let standardHeight = try #require(nativeHostedAccessibilityFrame("fst.shop.song.fixture-orbit", in: standard.host)).height
        standard.close()

        let hosted = try await Self.hostList(.accessibility5)
        defer { hosted.close() }
        let host = hosted.host
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "shop-rows-ax5")
        let order = nodes.filter(\.isElement)
        for (id, title) in [("fixture-orbit", "Fixture Orbit"), ("fixture-pulse", "Fixture Pulse")] {
            let row = try #require(nativeHostedAccessibilityFrame("fst.shop.song.\(id)", in: host))
            let bag = try #require(nativeHostedAccessibilityFrame("fst.shop.external.\(id)", in: host))
            #expect(bag.minY >= row.maxY - 0.5, "\(id) bag moves below its row: \(bag) under \(row)")
            #expect(bag.height >= ShopRowMetrics.bagSlot - 0.5, "\(id) bag keeps a 44 pt target: \(bag)")
            #expect(bag.width >= row.width * 0.9, "\(id) bag spans the row: \(bag) vs \(row)")
            #expect(row.height > standardHeight + 10, "\(id) row restacks at AX5: \(row.height) vs \(standardHeight)")
            let rowIndex = try #require(order.firstIndex { $0.identifier == "fst.shop.song.\(id)" })
            let bagIndex = try #require(order.firstIndex { $0.identifier == "fst.shop.external.\(id)" })
            #expect(bagIndex > rowIndex, "\(id) bag reads after its row")
            #expect(order[rowIndex].spokenName.contains(title))
            #expect(order[bagIndex].spokenName == "\(title), Open Official Item Shop")
        }
        let orbit = try #require(nativeHostedAccessibilityFrame("fst.shop.song.fixture-orbit", in: host))
        let long = try #require(Self.unlistedRowFrame(in: host), "display-only row at AX5")
        let plain = try #require(order.first { $0.identifier.isEmpty && $0.spokenName.contains(Self.unlisted.title) })
        #expect(plain.role == "AXStaticText", "the display-only row stays static text at AX5: \(plain)")
        #expect(long.height > orbit.height + 10,
                "the long title and artist wrap instead of clipping: \(long.height) vs \(orbit.height)")
        #expect(macAccessibilityFindings(nodes) == [])
    }
}
#endif
