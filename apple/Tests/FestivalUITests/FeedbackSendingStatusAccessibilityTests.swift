#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Feedback sending status accessibility (issue #634)

/// What the feedback form's sending status exposes on every Apple platform (the same
/// SwiftUI runs on iPhone, iPad, iPhone Duo and Mac): one named busy indicator that keeps
/// its name through both stages, the stage title as a heading, the upload bar with its
/// value and Stop Sending as a 44 pt button, read in that order, with the other stage's
/// text out of the tree; the block centred horizontally and vertically in the sheet, and
/// still inside it with wrapped text at the largest accessibility size.
///
/// HIG Progress indicators: "When possible, use a determinate indicator"; HIG VoiceOver:
/// "Inform VoiceOver of visible content or layout changes"; HIG Accessibility: "Strive for
/// the platform's recommended minimum control size".
@MainActor
@Suite(.serialized)
struct FeedbackSendingStatusAccessibilityTests {
    // MARK: - Fixture

    static let statusID = "fst.settings.feedback.status"
    static let busyID = "fst.settings.feedback.busy"
    static let titleID = "fst.settings.feedback.status.title"
    static let subtitleID = "fst.settings.feedback.status.subtitle"
    static let progressID = "fst.settings.feedback.progress"
    static let stopID = "fst.settings.feedback.stop"
    /// About an iPhone sheet's content area below its navigation bar.
    static let size = CGSize(width: 390, height: 700)
    /// A narrow column (a folded Duo half, a compact Mac window) where the sentence wraps.
    static let narrow = CGSize(width: 220, height: 700)
    static let tolerance: CGFloat = 1

    /// Stop Sending presses.
    @MainActor final class StopRecorder {
        var stops = 0
    }

    /// One hosted status.
    @MainActor struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let recorder: StopRecorder

        func close() { window.orderOut(nil) }

        /// What VoiceOver reaches, in order, without containers (the accessibility
        /// children walk, not the indicators' private AppKit subviews).
        func readable() -> [MacAXNode] {
            nativeHostedReachableElements(host).map(\.node).filter {
                !["AXGroup", "AXScrollArea", "AXScrollBar", "AXValueIndicator", "AXOpaqueProviderGroup"]
                    .contains($0.role)
            }
        }

        func frame(_ identifier: String) throws -> CGRect {
            try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) frame")
        }
    }

    /// Host the status settled at a stage.
    ///
    /// - Parameters:
    ///   - stage: The stage shown.
    ///   - kind: Bug report or feature request.
    ///   - progress: Upload progress.
    ///   - typeSize: Dynamic Type size.
    /// - Returns: The settled host.
    static func host(
        _ stage: FeedbackSendingStage, kind: FeedbackKind = .bug, progress: Double = 0.4,
        typeSize: DynamicTypeSize = .large, size: CGSize = FeedbackSendingStatusAccessibilityTests.size
    ) async throws -> Hosted {
        let recorder = StopRecorder()
        let host = nativeHostedView(
            AnyView(
                FeedbackSendingStatusView(
                    kind: kind, presentation: .status(stage),
                    progress: progress, onStop: { recorder.stops += 1 }
                )
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityFrame(titleID, in: host) != nil
        }
        return Hosted(host: host, window: window, recorder: recorder)
    }

    // MARK: - Upload stage

    /// Uploading Media reads the busy indicator, the heading, the bar with its value and
    /// Stop Sending, in that order; the filing text is out of the tree.
    @Test func uploadReadsSpinnerTitleBarThenStop() async throws {
        let hosted = try await Self.host(.uploading)
        defer { hosted.close() }
        let nodes = hosted.readable()
        let dump = nodes.map(\.description).joined(separator: "\n")
        #expect(nodes.map(\.identifier) == [Self.busyID, Self.titleID, Self.progressID, Self.stopID], "\(dump)")
        #expect(nodes.filter { $0.role == "AXBusyIndicator" }.count == 1, "one busy indicator:\n\(dump)")
        #expect(nodes[0].role == "AXBusyIndicator" && nodes[0].label == "Sending your issue", "\(dump)")
        #expect(nodes[1].role == "AXHeading" && nodes[1].spokenName == "Uploading Media", "\(dump)")
        #expect(nodes[2].role == "AXProgressIndicator" && nodes[2].label == "Upload progress", "\(dump)")
        // The value is a number, which the reachable walk doesn't read as a string.
        let bar = macAccessibilityTree(hosted.host).first { $0.identifier == Self.progressID }
        #expect(bar?.value == "0.4", "the bar reads the upload's progress: \(String(describing: bar))")
        #expect(nodes[3].role == "AXButton" && nodes[3].spokenName == "Stop Sending", "\(dump)")
        #expect(!dump.contains("Filing"), "the filing text is hidden:\n\(dump)")
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host)) == [])
    }

    /// A feature request's upload keeps the shared title and names the request's spinner.
    @Test func uploadForRequestNamesTheRequest() async throws {
        let hosted = try await Self.host(.uploading, kind: .feature)
        defer { hosted.close() }
        let nodes = hosted.readable()
        #expect(nodes.first { $0.identifier == Self.titleID }?.spokenName == "Uploading Media")
        #expect(nodes.first { $0.role == "AXBusyIndicator" }?.label == "Sending your request")
        #expect(nodes.contains { $0.identifier == Self.progressID })
    }

    /// Stop Sending meets the Mac's 28 pt default control size (the iOS label frame gives
    /// 44 pt) and stops through the accessibility press.
    @Test func stopIsATargetThatStops() async throws {
        let hosted = try await Self.host(.uploading)
        defer { hosted.close() }
        let stop = try hosted.frame(Self.stopID)
        #expect(stop.height >= 28 - Self.tolerance && stop.width >= 28 - Self.tolerance, "stop: \(stop)")
        let element = try #require(nativeHostedAccessibilityElement(Self.stopID, in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(element.responds(to: press), "stop offers a press action")
        _ = element.perform(press)
        try await nativeHostedSettle(hosted.host) { hosted.recorder.stops > 0 }
        #expect(hosted.recorder.stops == 1)
    }

    // MARK: - Filing stage

    /// Filing Issue reads the same busy indicator, the heading and the owner's sentence;
    /// the bar and Stop Sending are gone.
    @Test func filingReadsSpinnerTitleThenSentence() async throws {
        let hosted = try await Self.host(.filing)
        defer { hosted.close() }
        let nodes = hosted.readable()
        let dump = nodes.map(\.description).joined(separator: "\n")
        #expect(nodes.map(\.identifier) == [Self.busyID, Self.titleID, Self.subtitleID], "\(dump)")
        #expect(nodes[0].role == "AXBusyIndicator" && nodes[0].label == "Sending your issue", "\(dump)")
        #expect(nodes[1].role == "AXHeading" && nodes[1].spokenName == "Filing Issue", "\(dump)")
        #expect(nodes[2].spokenName == "We\u{2019}re filing your issue. Please wait while we upload it.", "\(dump)")
        #expect(!nodes.contains { $0.identifier == Self.stopID || $0.identifier == Self.progressID }, "\(dump)")
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host)) == [])
    }

    // MARK: - Placement and text scaling

    /// The block is centred horizontally and vertically in the sheet, and the spinner sits
    /// in the same place in both stages (the text swaps beneath it).
    @Test func statusIsCentredAndTheSpinnerStaysPut() async throws {
        let uploading = try await Self.host(.uploading)
        defer { uploading.close() }
        let filing = try await Self.host(.filing)
        defer { filing.close() }
        // Both stages' text is laid out under the spinner, so the block is the union of
        // what each stage shows.
        let block = try uploading.frame(Self.statusID).union(filing.frame(Self.statusID))
        #expect(abs(block.midX - Self.size.width / 2) <= Self.tolerance, "centred across: \(block)")
        #expect(abs(block.midY - Self.size.height / 2) <= Self.tolerance, "centred down: \(block)")
        let spinner = try uploading.frame(Self.busyID)
        #expect(abs(spinner.midX - Self.size.width / 2) <= Self.tolerance, "spinner centred: \(spinner)")
        let filingSpinner = try filing.frame(Self.busyID)
        #expect(abs(filingSpinner.midY - spinner.midY) <= Self.tolerance,
                "the spinner doesn't move between stages: \(spinner) vs \(filingSpinner)")
    }

    /// At the largest accessibility size in a narrow column the text wraps, centred,
    /// inside the width, and every element stays reachable.
    @Test func largestTextWrapsInsideTheSheet() async throws {
        let hosted = try await Self.host(.filing, typeSize: .accessibility5, size: Self.narrow)
        defer { hosted.close() }
        let title = try hosted.frame(Self.titleID)
        let subtitle = try hosted.frame(Self.subtitleID)
        for frame in [title, subtitle] {
            #expect(frame.minX >= -Self.tolerance && frame.maxX <= Self.narrow.width + Self.tolerance,
                    "inside the width: \(frame)")
            #expect(abs(frame.midX - Self.narrow.width / 2) <= Self.tolerance, "centred: \(frame)")
        }
        #expect(subtitle.height > title.height, "the sentence wraps: \(subtitle) vs \(title)")
        #expect(hosted.readable().map(\.identifier) == [Self.busyID, Self.titleID, Self.subtitleID])
    }
}
#endif
