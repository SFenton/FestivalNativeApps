#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Page loading placement

/// Loading in a bounded result region, with unequal chrome insets and active folds.
@Suite(.serialized)
struct FillingLoadingAccessibilityTests {
    /// Window and result geometry for one phone, tablet, desktop or foldable state.
    struct RegionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let size: CGSize
        let content: CGRect
        let hinge: HingeState?
        let fold: CGRect?
        let expected: CGRect

        var testDescription: String { name }

        var layout: DeviceLayout {
            DeviceLayout.resolve(LayoutSignals(
                size: size, widthClass: size.width < 600 ? .compact : .regular,
                hinge: hinge, divisions: hinge == .partiallyOpen ? fold.map { [$0] } ?? [] : [],
                hinges: fold.map { [$0] } ?? []
            ))
        }
    }

    /// A card's default indicator stays intrinsic even when the page has an active fold.
    @Test @MainActor
    func inlineSpinnerKeepsItsNativeSizeAndSingleBusyRole() async throws {
        let size = CGSize(width: 96, height: 96)
        let host = nativeHostedView(
            FestivalLoadingView(accessibilityLabel: "Loading scores")
                .accessibilityIdentifier("fst.loading-test.inline")
                .frame(width: size.width, height: size.height)
                .environment(\.deviceLayout, Self.cases[4].layout)
                .environment(\.dynamicTypeSize, .accessibility5),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement("fst.loading-test.inline", in: host) != nil
        }
        let nodes = ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(host))
        #expect(nodes.count == 1)
        #expect(nodes.first?.label == "Loading scores")
        let frame = try #require(nativeHostedAccessibilityFrame("fst.loading-test.inline", in: host))
        #expect(frame.width < 44 && frame.height < 44, "A noninteractive busy indicator is not a padded touch target")
        #expect(abs(frame.midX - 48) < 1 && abs(frame.midY - 48) < 1)
    }

    /// Folding only moves the indicator: it keeps its accessibility identity and does
    /// not reveal content or restart the load sequence.
    @Test @MainActor
    func foldingRepositionsTheSameBusyIndicatorInPlace() async throws {
        let state = Self.cases[3]
        let model = LoadingLayoutModel(layout: state.layout)
        let host = nativeHostedView(
            LoadingLayoutEnvironment(model: model, content: page(state)),
            size: state.size
        )
        let window = nativeHostedWindow(host, size: state.size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement("fst.loading-test.spinner", in: host) != nil
        }
        let original = try #require(nativeHostedAccessibilityElement("fst.loading-test.spinner", in: host))
        for index in [4, 3, 5, 3] {
            let next = Self.cases[index]
            model.layout = next.layout
            let expected = FoldAvoidingPlacement.region(container: state.content, fold: next.layout.splitHinge)
                .offsetBy(dx: state.content.minX, dy: state.content.minY)
            try await nativeHostedSettle(host) {
                guard let frame = nativeHostedAccessibilityFrame("fst.loading-test.spinner", in: host) else { return false }
                return abs(frame.midX - expected.midX) < 1 && abs(frame.midY - expected.midY) < 1
            }
            let current = try #require(nativeHostedAccessibilityElement("fst.loading-test.spinner", in: host))
            #expect(current === original, "Folding preserves the one named busy indicator")
            #expect(ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(host)).count == 1)
        }
    }

    static let cases: [RegionCase] = [
        RegionCase(
            name: "iPhone", size: CGSize(width: 402, height: 874),
            content: CGRect(x: 0, y: 106, width: 402, height: 650),
            hinge: nil, fold: nil,
            expected: CGRect(x: 0, y: 106, width: 402, height: 650)
        ),
        RegionCase(
            name: "iPad or Mac beside sidebar", size: CGSize(width: 1100, height: 760),
            content: CGRect(x: 220, y: 100, width: 880, height: 530),
            hinge: nil, fold: nil,
            expected: CGRect(x: 220, y: 100, width: 880, height: 530)
        ),
        RegionCase(
            name: "Duo cover beside vertical bar", size: CGSize(width: 680, height: 460),
            content: CGRect(x: 0, y: 20, width: 584, height: 420),
            hinge: .closed, fold: nil,
            expected: CGRect(x: 0, y: 20, width: 584, height: 420)
        ),
        RegionCase(
            name: "Duo flat ignores inactive hinge", size: CGSize(width: 1000, height: 760),
            content: CGRect(x: 32, y: 100, width: 860, height: 530),
            hinge: .fullyOpen, fold: CGRect(x: 500, y: 0, width: 24, height: 760),
            expected: CGRect(x: 32, y: 100, width: 860, height: 530)
        ),
        RegionCase(
            name: "Duo book wider left", size: CGSize(width: 1000, height: 760),
            content: CGRect(x: 32, y: 100, width: 860, height: 530),
            hinge: .partiallyOpen, fold: CGRect(x: 500, y: 0, width: 24, height: 760),
            expected: CGRect(x: 32, y: 100, width: 468, height: 530)
        ),
        RegionCase(
            name: "Duo book wider right", size: CGSize(width: 1000, height: 760),
            content: CGRect(x: 108, y: 100, width: 860, height: 530),
            hinge: .partiallyOpen, fold: CGRect(x: 400, y: 0, width: 24, height: 760),
            expected: CGRect(x: 424, y: 100, width: 544, height: 530)
        ),
        RegionCase(
            name: "Duo horizontal fold", size: CGSize(width: 760, height: 1000),
            content: CGRect(x: 0, y: 100, width: 760, height: 750),
            hinge: .partiallyOpen, fold: CGRect(x: 0, y: 400, width: 760, height: 24),
            expected: CGRect(x: 0, y: 424, width: 760, height: 426)
        ),
        RegionCase(
            name: "Split detail already beside fold", size: CGSize(width: 1000, height: 760),
            content: CGRect(x: 540, y: 100, width: 352, height: 530),
            hinge: .partiallyOpen, fold: CGRect(x: 500, y: 0, width: 24, height: 760),
            expected: CGRect(x: 540, y: 100, width: 352, height: 530)
        ),
    ]

    /// The actual reload gate centres its one named busy indicator below the heading
    /// and above lower chrome, avoiding an active fold without subtracting chrome twice.
    @Test(arguments: cases, [DynamicTypeSize.large, .accessibility5])
    @MainActor
    func pageSpinnerCentresInItsVisibleRegion(_ state: RegionCase, _ textSize: DynamicTypeSize) async throws {
        let host = nativeHostedView(
            page(state)
                .environment(\.deviceLayout, state.layout)
                .environment(\.dynamicTypeSize, textSize)
                .environment(\._accessibilityReduceMotion, true)
                .environment(\._accessibilityReduceTransparency, true),
            size: state.size
        )
        let window = nativeHostedWindow(host, size: state.size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement("fst.loading-test.spinner", in: host) != nil
        }

        let spinner = try #require(nativeHostedAccessibilityElement("fst.loading-test.spinner", in: host))
        #expect(nativeHostedAccessibilityString(spinner, "accessibilityRole") == "AXBusyIndicator")
        #expect(nativeHostedAccessibilityString(spinner, "accessibilityLabel") == "Loading song")
        let nodes = ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(host))
        #expect(nodes.count == 1, "One spinner, never a named wrapper and an unnamed indicator")
        let frame = try #require(nativeHostedAccessibilityFrame(of: spinner, in: host))
        #expect(abs(frame.midX - state.expected.midX) < 1, "\(state.name): \(frame) in \(state.expected)")
        #expect(abs(frame.midY - state.expected.midY) < 1, "\(state.name): \(frame) in \(state.expected)")
        #expect(state.expected.contains(frame), "The indicator stays inside the visible region")
        if state.hinge == .partiallyOpen, let fold = state.fold {
            #expect(!frame.intersects(fold), "No part of the indicator lies on the fold")
        }
        let order = macAccessibilityTree(host)
            .filter { $0.isElement && $0.identifier.hasPrefix("fst.loading-test.") }
            .map(\.identifier)
        #expect(order == ["fst.loading-test.heading", "fst.loading-test.spinner", "fst.loading-test.footer"])
    }

    /// A real gate between page chrome; the insets model safe areas and a split pane.
    ///
    /// - Parameter state: The window and result rectangles.
    /// - Returns: A loading page with a heading and footer outside its gate.
    @MainActor private func page(_ state: RegionCase) -> some View {
        VStack(spacing: 0) {
            Text("Song Details")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.loading-test.heading")
                .frame(height: state.content.minY)
            HStack(spacing: 0) {
                Color.clear.frame(width: state.content.minX).accessibilityHidden(true)
                FestivalReloadGate(
                    key: 0, isLoading: true, spinnerLabel: "Loading song",
                    spinnerIdentifier: "fst.loading-test.spinner"
                ) {
                    Text("Loaded song")
                }
                .frame(width: state.content.width, height: state.content.height)
                Color.clear.frame(width: state.size.width - state.content.maxX).accessibilityHidden(true)
            }
            Text("Page controls")
                .accessibilityIdentifier("fst.loading-test.footer")
                .frame(height: state.size.height - state.content.maxY)
        }
        .frame(width: state.size.width, height: state.size.height)
    }
}

/// Layout signals that change without replacing a loading page.
@MainActor @Observable
private final class LoadingLayoutModel {
    var layout: DeviceLayout

    /// - Parameter layout: Initial window and fold signals.
    init(layout: DeviceLayout) { self.layout = layout }
}

/// Publish the fixture's changing fold signals from SwiftUI's observation scope.
private struct LoadingLayoutEnvironment<Content: View>: View {
    let model: LoadingLayoutModel
    let content: Content

    var body: some View {
        content.environment(\.deviceLayout, model.layout)
    }
}
#endif
