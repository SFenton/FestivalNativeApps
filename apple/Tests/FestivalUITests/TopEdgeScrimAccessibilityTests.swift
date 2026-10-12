#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Top scrim under the iPhone Duo vertical bar: accessibility (issue #476, for #335)

/// #335 spread the page's top legibility gradient (`TopEdgeScrim`) under the horizontal
/// safe areas, so the art under the iPhone Duo vertical bar is darkened like the page
/// beside it. These hosted checks pin what that wider gradient must never do to
/// assistive technologies, on every Apple platform (the same SwiftUI runs on iPhone,
/// iPad, iPhone Duo and Mac), with a horizontal safe-area inset standing in for the bar
/// on either edge:
///
/// - it is decoration: the page's accessibility tree (roles, names, identifiers, order and
///   frames) is the same with and without it, and nothing in it is an element;
/// - it never takes a touch or VoiceOver focus: a hit test at a page control in the
///   gradient beside the bar's edge, and at a control in the bar itself, finds that control,
///   which keeps its 44 pt target and acts on AXPress;
/// - the page still reads heading → page tool → rows;
/// - with the system's or the app's Reduce Transparency or Increase Contrast it still
///   darkens the bar like the page, and the page header resolves the hard edge
///   (scroll-edge R7).
///
/// The real vertical bar and Dynamic Type exist only on the device (macOS ignores
/// `dynamicTypeSize`): the iPhone Duo AX5 audit is `TopEdgeScrimDuoJourneyTests`.
///
/// HIG VoiceOver: "Mark decorative images as decorative." HIG Accessibility: iOS/iPadOS
/// default control size 44×44 pt. HIG for iPhone Duo (`duo-checklist.md` §3): "Vertical
/// bars get a background under Reduce Transparency, so custom content must stay legible
/// there."
@MainActor
@Suite(.serialized)
struct TopEdgeScrimAccessibilityTests {
    // MARK: - Fixture

    static let size = CGSize(width: 466, height: 678)
    /// The stand-in vertical bar's width, as the folded Duo's trailing bar.
    static let barWidth: CGFloat = 60
    static let headingID = "fst.tests.top-scrim.heading"
    static let toolID = "fst.tests.top-scrim.tool"
    static let barButtonID = "fst.tests.top-scrim.bar-button"
    static let rowPrefix = "fst.tests.top-scrim.row."

    /// Presses each control received, by identifier.
    @MainActor final class PressRecorder {
        var pressed: [String] = []
    }

    /// The top-edge style the page header resolved.
    @MainActor final class EdgeReading {
        var edge: PageTopScrollEdge?
    }

    /// A page beside a stand-in Duo vertical bar: a bright backdrop under everything, a
    /// heading and a 44 pt page tool at the top (inside the gradient, the tool beside the
    /// bar's edge), rows below, and one 44 pt bar button inside the inset.
    struct Page: View {
        let barEdge: HorizontalEdge
        let scrim: Bool
        let recorder: PressRecorder
        var edgeReading: EdgeReading?

        var body: some View {
            ZStack {
                Color(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1).ignoresSafeArea()
                content
            }
            .safeAreaInset(edge: barEdge, spacing: 0) {
                VStack {
                    Button("Settings") { recorder.pressed.append(TopEdgeScrimAccessibilityTests.barButtonID) }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier(TopEdgeScrimAccessibilityTests.barButtonID)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(width: TopEdgeScrimAccessibilityTests.barWidth)
            }
        }

        @ViewBuilder private var content: some View {
            let page = VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    if barEdge == .leading { tool }
                    Text("Songs")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(TopEdgeScrimAccessibilityTests.headingID)
                        .frame(maxWidth: .infinity, alignment: barEdge == .leading ? .trailing : .leading)
                    if barEdge == .trailing { tool }
                }
                ForEach(0..<4, id: \.self) { row in
                    Text("Song \(row + 1)")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("\(TopEdgeScrimAccessibilityTests.rowPrefix)\(row)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            if scrim {
                page
                    .modifier(TopEdgeScrim())
                    .onPreferenceChange(PageTopScrollEdgeKey.self) { edge in
                        MainActor.assumeIsolated { edgeReading?.edge = edge }
                    }
            } else {
                page
            }
        }

        /// A page tool (Filter) in the gradient, flush with the bar's inner edge.
        private var tool: some View {
            Button { recorder.pressed.append(TopEdgeScrimAccessibilityTests.toolID) } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Filter")
            .accessibilityIdentifier(TopEdgeScrimAccessibilityTests.toolID)
        }
    }

    /// One hosted page.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suite: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suite)
        }
    }

    /// Host the page and wait until its heading, tool and bar button are in the tree.
    ///
    /// - Parameters:
    ///   - barEdge: The edge the stand-in bar sits on.
    ///   - scrim: Whether the page wears `TopEdgeScrim`.
    ///   - mode: The accessibility setting under test (scroll-edge R7).
    ///   - typeSize: Dynamic Type size for the page.
    ///   - recorder: Records AXPress activations.
    ///   - edgeReading: Receives the page header's resolved top edge.
    /// - Returns: The settled host.
    static func host(
        barEdge: HorizontalEdge, scrim: Bool = true, mode: BottomChromeFadeMode = .standard,
        typeSize: DynamicTypeSize = .large, recorder: PressRecorder = PressRecorder(),
        edgeReading: EdgeReading? = nil
    ) async throws -> Hosted {
        let (storage, suite) = mode.storage()
        let content = mode.system(
            Page(barEdge: barEdge, scrim: scrim, recorder: recorder, edgeReading: edgeReading)
                .environment(\.dynamicTypeSize, typeSize)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
        )
        // The gradient must render as drawn in each mode, not under the forced glass fallback.
        let host = nativeHostedView(AnyView(content), size: size, forceGlassFallback: false)
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            [headingID, toolID, barButtonID].allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return Hosted(host: host, window: window, storage: storage, suite: suite)
    }

    /// The page's elements in tree order, with their frames, for comparing two hosts.
    static func elements(in host: NSView) -> [String] {
        macAccessibilityTree(host, navigationOrder: true).filter(\.isElement).map { node in
            let frame = nativeHostedAccessibilityFrame(node.identifier, in: host).map {
                " @\(Int($0.minX.rounded())),\(Int($0.minY.rounded())) \(Int($0.width.rounded()))×\(Int($0.height.rounded()))"
            } ?? ""
            return node.description.trimmingCharacters(in: .whitespaces) + (node.identifier.isEmpty ? "" : frame)
        }
    }

    /// The accessibility element at a host point, as VoiceOver's touch exploration and
    /// the pointer find it, walked up to the first one that carries an identifier.
    static func hitIdentifier(at point: CGPoint, in host: NSView) throws -> String {
        let window = try #require(host.window)
        let local = host.isFlipped ? point : CGPoint(x: point.x, y: host.bounds.height - point.y)
        let screen = window.convertPoint(toScreen: host.convert(local, to: nil))
        var hit: Any? = host.accessibilityHitTest(screen)
        for _ in 0..<12 {
            guard let object = hit as? NSObject else { break }
            let identifier = nativeHostedAccessibilityString(object, "accessibilityIdentifier")
            if !identifier.isEmpty { return identifier }
            hit = object.responds(to: NSSelectorFromString("accessibilityParent"))
                ? object.value(forKey: "accessibilityParent") : nil
        }
        return ""
    }

    /// Press a control as VoiceOver, Voice Control and Switch Control do (AXPress).
    static func press(_ identifier: String, in host: NSView) throws {
        let control = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: press), "\(identifier) offers a press action")
        _ = control.perform(press)
    }

    /// Mean channel value (0–1) of the host's capture at a point.
    static func luminance(_ image: CGImage, at point: CGPoint) throws -> CGFloat {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(image.width) / size.width
        let color = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }

    /// The stand-in bar's inner edge, in host points.
    static func barInnerEdge(_ barEdge: HorizontalEdge) -> CGFloat {
        barEdge == .trailing ? size.width - barWidth : barWidth
    }

    // MARK: - Decoration

    /// The scrim adds nothing to the tree: the same elements, names, roles, order and
    /// frames as the page without it, with the bar on either edge, and no unnamed control
    /// or repeated image (HIG VoiceOver: "Mark decorative images as decorative").
    @Test(arguments: [HorizontalEdge.trailing, .leading])
    func scrimUnderTheBarIsDecoration(barEdge: HorizontalEdge) async throws {
        let plain = try await Self.host(barEdge: barEdge, scrim: false)
        let expected = Self.elements(in: plain.host)
        plain.close()
        let scrimmed = try await Self.host(barEdge: barEdge)
        defer { scrimmed.close() }
        let nodes = macAccessibilityTree(scrimmed.host, navigationOrder: true)
        #expect(Self.elements(in: scrimmed.host) == expected)
        #expect(macAccessibilityFindings(nodes) == [])
        #expect(!nodes.contains {
            $0.isElement && ($0.role == "AXImage" || $0.role == "AXGroup") && $0.subrole != "AXHostingView"
                && $0.spokenName.isEmpty
        },
                "no unnamed image or group from the gradient:\n\(nodes.map(\.description).joined(separator: "\n"))")
    }

    // MARK: - Touch, focus and order

    /// A page tool in the gradient beside the bar's edge and a control in the bar itself
    /// keep their name, button role, 44 pt target, hit test and AXPress, and the page reads
    /// heading → tool → rows in visual order.
    @Test(arguments: [HorizontalEdge.trailing, .leading])
    func controlsBesideAndInTheBarStayReachable(barEdge: HorizontalEdge) async throws {
        let recorder = PressRecorder()
        let hosted = try await Self.host(barEdge: barEdge, recorder: recorder)
        defer { hosted.close() }
        let host = hosted.host
        let nodes = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        let tool = try #require(nodes.first { $0.identifier == Self.toolID })
        #expect(tool.role == "AXButton" && tool.spokenName == "Filter", "\(tool)")
        let bar = try #require(nodes.first { $0.identifier == Self.barButtonID })
        #expect(bar.role == "AXButton" && bar.spokenName == "Settings", "\(bar)")
        let heading = try #require(nodes.first { $0.identifier == Self.headingID })
        #expect(heading.role == "AXHeading" || heading.subrole == "AXHeading" || heading.role == "AXStaticText", "\(heading)")
        #expect(heading.spokenName == "Songs")

        let scrimHeight = TopEdgeScrim.maxHeight
        let edge = Self.barInnerEdge(barEdge)
        for id in [Self.toolID, Self.barButtonID] {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host))
            #expect(frame.width >= 44 - 0.5 && frame.height >= 44 - 0.5, "\(id) keeps a 44 pt target: \(frame)")
            #expect(frame.minY < scrimHeight, "\(id) sits inside the gradient: \(frame)")
            #expect(try Self.hitIdentifier(at: CGPoint(x: frame.midX, y: frame.midY), in: host) == id,
                    "the gradient never takes \(id)'s touch or focus")
        }
        let toolFrame = try #require(nativeHostedAccessibilityFrame(Self.toolID, in: host))
        #expect(abs((barEdge == .trailing ? toolFrame.maxX : toolFrame.minX) - edge) <= 8.5,
                "the tool sits beside the bar's edge: \(toolFrame)")

        let order = nodes.map(\.identifier).filter { $0 == Self.headingID || $0 == Self.toolID || $0.hasPrefix(Self.rowPrefix) }
        let expectedOrder = barEdge == .trailing
            ? [Self.headingID, Self.toolID] : [Self.toolID, Self.headingID]
        #expect(order == expectedOrder + (0..<4).map { "\(Self.rowPrefix)\($0)" }, "\(order)")

        try Self.press(Self.toolID, in: host)
        try Self.press(Self.barButtonID, in: host)
        #expect(recorder.pressed == [Self.toolID, Self.barButtonID])
    }

    // MARK: - Transparency and contrast

    /// With each R7 setting the gradient still darkens under the bar exactly as on the
    /// page beside it (no brighter strip behind the bar's controls), the page header asks
    /// for the hard edge, and the tree is unchanged (scroll-edge R7; HIG for iPhone Duo:
    /// custom content under a vertical bar "must stay legible" under Reduce Transparency).
    @Test(arguments: BottomChromeFadeMode.allCases)
    func scrimDarkensUnderTheBarInEveryAccessibilityMode(mode: BottomChromeFadeMode) async throws {
        let reading = EdgeReading()
        let hosted = try await Self.host(barEdge: .trailing, mode: mode, edgeReading: reading)
        defer { hosted.close() }
        #expect(reading.edge == (mode.hardEdge ? .hard : .soft), "\(mode): \(String(describing: reading.edge))")

        let image = try nativeHostedImage(hosted.host)
        let edge = Self.barInnerEdge(.trailing)
        // Below the bar button (which ends 52 pt down) and clear of the page's tool.
        let underBar = edge + Self.barWidth / 2, besideBar = edge - 60
        for y: CGFloat in [4, 70] {
            let bar = try Self.luminance(image, at: CGPoint(x: underBar, y: y))
            let page = try Self.luminance(image, at: CGPoint(x: besideBar, y: y))
            #expect(page < 0.85, "\(mode) y \(y): the gradient dims the 0.9 backdrop (\(page))")
            #expect(abs(bar - page) < 0.02, "\(mode) y \(y): bar \(bar) vs page \(page)")
        }
        #expect(macAccessibilityTree(hosted.host).contains { $0.identifier == Self.barButtonID && $0.isElement })
        #expect(try Self.hitIdentifier(
            at: try #require(nativeHostedAccessibilityFrame(Self.toolID, in: hosted.host)).center, in: hosted.host
        ) == Self.toolID)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
#endif
