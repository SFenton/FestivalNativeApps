#if os(macOS)
import AppKit
#endif
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// One decoded comparison for the rival song row (issue #558).
///
/// - Parameters:
///   - instrument: Chart instrument; an unknown value hides the instrument icon.
///   - delta: `rankDelta`, positive when the player leads.
/// - Returns: The comparison.
private func songComparison(instrument: String = "Solo_Guitar", delta: Int) -> RivalSongComparison {
    let json = """
    {"songId":"fixture-pulse","title":"Pulse","artist":"Fixture Band","instrument":"\(instrument)",
     "userInstrument":null,"rivalInstrument":null,
     "userRank":12,"rivalRank":\(12 + delta),"rankDelta":\(delta),"userScore":100,"rivalScore":90}
    """
    return try! JSONDecoder().decode(RivalSongComparison.self, from: Data(json.utf8))
}

// MARK: - Standing and label (pattern rival-rows R3/R5)

@Test func rivalSongStandingFollowsRankDelta() {
    #expect(RivalSongStanding(rankDelta: 3) == .playerAhead)
    #expect(RivalSongStanding(rankDelta: -1) == .rivalAhead)
    #expect(RivalSongStanding(rankDelta: 0) == .tied)

    #expect(RivalSongStanding.playerAhead.playerTint == BrandTokens.statusGreen)
    #expect(RivalSongStanding.playerAhead.rivalTint == BrandTokens.statusRed)
    #expect(RivalSongStanding.rivalAhead.playerTint == BrandTokens.statusRed)
    #expect(RivalSongStanding.rivalAhead.rivalTint == BrandTokens.statusGreen)
    #expect(RivalSongStanding.tied.playerTint == FestivalText.primary)
    #expect(RivalSongStanding.tied.rivalTint == FestivalText.primary)
}

/// Colour is never the only signal: the label names who leads (HIG Color).
@Test func rivalSongRowLabelReadsSongRanksAndLeader() {
    #expect(
        RivalSongRowContent.accessibilityLabel(for: songComparison(delta: 1), rivalName: "Ava")
            == "Pulse, you rank 12, Ava ranks 13, you lead"
    )
    #expect(
        RivalSongRowContent.accessibilityLabel(for: songComparison(delta: -2), rivalName: "Ava")
            == "Pulse, you rank 12, Ava ranks 10, Ava leads"
    )
    #expect(
        RivalSongRowContent.accessibilityLabel(for: songComparison(delta: 0), rivalName: "Ava")
            == "Pulse, you rank 12, Ava ranks 12, tied"
    )
}

#if os(macOS)
// MARK: - Hosted layout

/// Any unexpected request fails, so hosted rows never use the network.
@MainActor
private func offlineRowSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// A solid magenta image, a colour no other part of the row draws.
private func magentaArtwork() -> CGImage {
    let context = CGContext(
        data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    return context.makeImage()!
}

/// Host one row at a fixed height; the row's centre alignment centres its content.
@MainActor
private func hostedRow(
    _ song: RivalSongComparison, rivalName: String = "Ava", height: CGFloat = 140,
    typeSize: DynamicTypeSize = .large
) -> NSHostingView<NativeHostedRoot<some View>> {
    nativeHostedView(
        RivalSongRowContent(
            song: song, albumArt: nil, session: offlineRowSession(),
            playerName: "SFentonX", rivalName: rivalName, previewArtwork: magentaArtwork()
        )
        .padding(.horizontal, 16)
        .frame(width: 390, height: height)
        .background(BrandTokens.surfaceFrosted)
        .dynamicTypeSize(typeSize)
        .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: height)
    )
}

/// Vertical extent of the magenta artwork, in host points (top-left origin).
@MainActor
private func artworkRows(in image: CGImage, hostHeight: CGFloat) -> ClosedRange<CGFloat>? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let scale = CGFloat(image.height) / hostHeight
    var top: Int?
    var bottom: Int?
    for y in 0..<image.height {
        for x in stride(from: 0, to: min(image.width, Int(120 * scale)), by: 2) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if color.redComponent > 0.8 && color.greenComponent < 0.3 && color.blueComponent > 0.8 {
                top = top ?? y
                bottom = y
                break
            }
        }
    }
    guard let top, let bottom else { return nil }
    return (CGFloat(top) / scale)...(CGFloat(bottom + 1) / scale)
}

/// Art alone is vertically centred; with an instrument icon it sits above it (owner, #558).
@MainActor
@Test func rivalSongRowCentresArtAloneAndStacksItAboveTheIcon() throws {
    let height: CGFloat = 140
    let alone = try #require(artworkRows(
        in: try nativeHostedImage(hostedRow(songComparison(instrument: "Unknown", delta: 1))),
        hostHeight: height
    ))
    let withIcon = try #require(artworkRows(
        in: try nativeHostedImage(hostedRow(songComparison(delta: 1))),
        hostHeight: height
    ))
    let size = RivalSongRowContent.artSize
    #expect(abs((alone.upperBound - alone.lowerBound) - size) <= 2)
    #expect(abs((alone.lowerBound + alone.upperBound) / 2 - height / 2) <= 2)
    // The art + 6 pt + 22 pt icon column is centred, so the art's centre sits 14 pt above.
    #expect(abs((withIcon.lowerBound + withIcon.upperBound) / 2 - (height / 2 - 14)) <= 2)
}

/// The leader's pill is green and the trailer's red; a tie draws neither status colour.
@MainActor
@Test func rivalSongRowTintsStandingPills() throws {
    let ahead = nativeHostedStatusPixels(try nativeHostedImage(hostedRow(songComparison(delta: 1))))
    let behind = nativeHostedStatusPixels(try nativeHostedImage(hostedRow(songComparison(delta: -1))))
    let tied = nativeHostedStatusPixels(try nativeHostedImage(hostedRow(songComparison(delta: 0))))
    #expect(ahead.green > 0 && ahead.red > 0)
    #expect(behind.green > 0 && behind.red > 0)
    #expect(tied.green == 0 && tied.red == 0)
}

// MARK: - Hosted accessibility

/// The realized element carrying the row's combined label, and its frame.
@MainActor
private func rowElement(in host: NSView) -> (label: String, frame: CGRect)? {
    // Hosted macOS SwiftUI surfaces a combined text element's label as its value.
    func spoken(_ object: NSObject) -> String {
        ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
            .map { nativeHostedAccessibilityString(object, $0) }
            .first { !$0.isEmpty } ?? ""
    }
    guard let element = nativeHostedAccessibilityElement(in: host, where: {
        spoken($0).contains("you rank 12")
    }) else { return nil }
    return (
        spoken(element),
        nativeHostedAccessibilityFrame(of: element, in: host) ?? .zero
    )
}

/// One element reads the song, both ranks and the leader; the art is hidden and the row
/// keeps a 44 pt target. At accessibility sizes the pills take a line each (and wrap), so
/// the row grows instead of truncating (HIG Typography). macOS does not scale fonts with
/// Dynamic Type, so the growth measured here is the stacking alone.
@MainActor
@Test func rivalSongRowIsOneLabelledElementAndGrowsAtAccessibilitySizes() async throws {
    // No instrument icon, so the text column (not the 72 pt art + icon column) sets the height.
    let song = songComparison(instrument: "Unknown", delta: -2)
    let name = "Ava"
    let regularHost = hostedRow(song, rivalName: name, height: 400)
    let regularWindow = nativeHostedWindow(regularHost, size: CGSize(width: 390, height: 400))
    defer { regularWindow.contentView = nil }
    try await nativeHostedSettle(regularHost, untilText: ["you rank 12"])
    let regular = try #require(rowElement(in: regularHost))
    #expect(regular.label == RivalSongRowContent.accessibilityLabel(for: song, rivalName: name))
    #expect(regular.frame.height >= 44)
    #expect(!nativeHostedAccessibility(regularHost).texts.contains { $0 == "#12 SFentonX" })

    let largeHost = hostedRow(song, rivalName: name, height: 400, typeSize: .accessibility5)
    let largeWindow = nativeHostedWindow(largeHost, size: CGSize(width: 390, height: 400))
    defer { largeWindow.contentView = nil }
    try await nativeHostedSettle(largeHost, untilText: ["you rank 12"])
    let large = try #require(rowElement(in: largeHost))
    #expect(large.label == regular.label)
    #expect(large.frame.height > regular.frame.height + 8)
}
#endif
