import SwiftUI

// MARK: - Placement

/// Where the iPhone Duo bottom search fields and their companion controls sit across
/// the hinge: the Songs Filter field (issue #333) and the Search tab's field and scope
/// bar (issue #349).
///
/// Owner (#349): "search bar when keyboard is closed and unfolded should take full
/// bottom width. Can stay on right side if hinge is unfolded but device is not
/// completely unfolded". So the column spans the full width (16 pt margins) unless an
/// active fold divides the inner display (book pose), when it moves to the trailing
/// page, a margin clear of the fold (HIG Designing for iPhone Duo: "use reserved-region
/// APIs to keep important elements clear of the center").
enum BottomSearchFieldPlacement {
    /// Standard gap between the field and the page or hinge edges (the rows' margin).
    nonisolated static let margin: CGFloat = 16

    /// Narrowest trailing page the field moves to; a narrower one keeps the full width.
    nonisolated static let minimumPageWidth: CGFloat = 200

    /// The hinge the column steps past: the fold while the inner display is partially
    /// folded (book pose), else nil, so a flat display keeps the full width.
    ///
    /// - Parameter layout: The window's layout.
    /// - Returns: ``DeviceLayout/splitHinge`` when the pose is
    ///   ``DeviceLayout/Pose/partiallyFolded``, otherwise nil.
    nonisolated static func pageHinge(for layout: DeviceLayout) -> CGRect? {
        layout.pose == .partiallyFolded ? layout.splitHinge : nil
    }

    /// Horizontal padding that keeps a bottom field (or a control aligned with it) on
    /// the trailing page.
    ///
    /// Without a vertical hinge crossing the row (flat, folded, inner portrait), both
    /// sides get the standard ``margin``. With one, the leading padding reaches past
    /// the hinge, so the row starts a margin beyond it: the right page in a
    /// left-to-right layout, the left page right-to-left.
    ///
    /// - Parameters:
    ///   - container: The row's frame, in window (global) points.
    ///   - hinge: ``pageHinge(for:)`` in the same space, if any.
    ///   - layoutDirection: The row's layout direction.
    /// - Returns: Leading and trailing padding, in points.
    nonisolated static func horizontalPadding(
        container: CGRect, hinge: CGRect?, layoutDirection: LayoutDirection = .leftToRight
    ) -> (leading: CGFloat, trailing: CGFloat) {
        let standard = (leading: margin, trailing: margin)
        guard let hinge, container.width > 0,
              hinge.height >= hinge.width,
              hinge.midX > container.minX, hinge.midX < container.maxX,
              hinge.minY < container.maxY, hinge.maxY > container.minY
        else { return standard }
        let leading = layoutDirection == .leftToRight
            ? hinge.maxX - container.minX + margin
            : container.maxX - hinge.minX + margin
        guard container.width - leading - margin >= minimumPageWidth else { return standard }
        return (leading: max(margin, leading), trailing: margin)
    }

    /// Extra lift that keeps the bottom field above the software keyboard.
    ///
    /// The field's safe-area inset already rises with the keyboard, but on the iPhone
    /// Duo outer display the system under-reports the narrower, inset keyboard's height
    /// and leaves the field behind it (issue #333). The lift closes only that measured
    /// gap: it is zero when the keyboard is hidden, hardware or already clear.
    ///
    /// The row's bottom does not depend on the lift (the inset grows upwards from it),
    /// so the result never feeds back into its own input.
    ///
    /// - Parameters:
    ///   - rowBottom: The field row's bottom edge, in window (global) points; the
    ///     field ends `fieldBottomPadding` above it.
    ///   - keyboardTop: The keyboard's top in the same space, or `nil` when hidden.
    ///   - fieldBottomPadding: The row's padding under the field.
    ///   - gap: Clearance between the field and the keyboard.
    /// - Returns: The extra bottom padding, in points (never negative).
    nonisolated static func keyboardLift(
        rowBottom: CGFloat, keyboardTop: CGFloat?, fieldBottomPadding: CGFloat = 8,
        gap: CGFloat = 8
    ) -> CGFloat {
        guard let keyboardTop else { return 0 }
        return max(0, (rowBottom - fieldBottomPadding) - (keyboardTop - gap)).rounded(.up)
    }

    // MARK: Search button alignment (#358)

    /// Diameter of the system Search button in the iPhone Duo vertical bar (measured
    /// folded portrait and inner landscape, iOS 27.1 simulator).
    nonisolated static let railSearchButtonSize: CGFloat = 48

    /// Gap between the vertical bar's Search button and the window's bottom edge.
    nonisolated static let railSearchButtonBottomInset: CGFloat = 24

    /// Diameter of the tab bar's Search button on the iPhone Duo inner display in
    /// portrait, the one pose with a horizontal tab bar.
    nonisolated static let tabBarSearchButtonSize: CGFloat = 62

    /// Padding above and below the field in its safe-area row.
    nonisolated static let rowPadding: CGFloat = 8

    /// The field's minimum height: the system Search button's in the same pose
    /// (owner, issue #358: "align with Search button vertically (in height too)").
    ///
    /// - Parameter chrome: The window's section chrome.
    /// - Returns: The vertical bar's Search button size beside a vertical bar, else
    ///   the tab bar's.
    nonisolated static func fieldHeight(for chrome: DeviceLayout.SectionChrome) -> CGFloat {
        chrome.isVerticalBar ? railSearchButtonSize : tabBarSearchButtonSize
    }

    /// Whether the software keyboard covers the bottom of the window.
    ///
    /// - Parameters:
    ///   - keyboardTop: The keyboard's top in window (screen) points, or `nil` while hidden.
    ///   - windowBottom: The window's bottom edge in the same space.
    /// - Returns: False when hidden, or for a hardware keyboard's off-screen frame.
    nonisolated static func keyboardCovers(keyboardTop: CGFloat?, windowBottom: CGFloat) -> Bool {
        guard let keyboardTop else { return false }
        return windowBottom <= 0 || keyboardTop < windowBottom
    }

    /// Padding under the field that centres it on the vertical bar's Search button
    /// (issue #358), or `nil` to keep the standard row.
    ///
    /// Beside a vertical bar (folded in every rotation, inner display in landscape) the
    /// system Search button's centre lies ``railSearchButtonBottomInset`` plus half
    /// ``railSearchButtonSize`` above the window's bottom; the row's own bottom is the
    /// page's bottom safe area, 10–34 pt higher, so the padding can be negative
    /// (the field reaches into the home-indicator area, level with the button). Only
    /// while the keyboard is hidden: above the keyboard the standard row and
    /// ``keyboardLift(rowBottom:keyboardTop:fieldBottomPadding:gap:)`` apply. With no
    /// vertical bar (inner portrait) the Search button sits in the tab bar, which the
    /// field must not cover, so the row stays above the bar.
    ///
    /// The row's bottom is the safe-area inset's anchor and does not depend on this
    /// padding, so the result never feeds back into its own input.
    ///
    /// - Parameters:
    ///   - chrome: The window's section chrome.
    ///   - rowBottom: The field row's bottom edge, in window (global) points.
    ///   - windowBottom: The window's bottom edge in the same space (measured past the
    ///     bottom safe area: ``DeviceLayout/size`` stops at it on iPhone Duo).
    ///   - fieldHeight: The field's measured height (taller than the button at large
    ///     Dynamic Type sizes; it stays centred).
    ///   - keyboardTop: The keyboard's top in the same space, or `nil` while hidden.
    /// - Returns: The bottom padding, in points, or `nil` for the standard row.
    nonisolated static func searchButtonAlignedBottomPadding(
        chrome: DeviceLayout.SectionChrome, rowBottom: CGFloat, windowBottom: CGFloat,
        fieldHeight: CGFloat, keyboardTop: CGFloat?
    ) -> CGFloat? {
        guard chrome.isVerticalBar, rowBottom > 0, windowBottom >= rowBottom, fieldHeight > 0,
              !keyboardCovers(keyboardTop: keyboardTop, windowBottom: windowBottom)
        else { return nil }
        let centre = windowBottom - railSearchButtonBottomInset - railSearchButtonSize / 2
        return (rowBottom - (centre + fieldHeight / 2)).rounded()
    }

    /// The row's padding under the field: centred on the vertical bar's Search button
    /// while the keyboard is hidden, else the standard ``rowPadding`` plus any
    /// ``keyboardLift(rowBottom:keyboardTop:fieldBottomPadding:gap:)``.
    ///
    /// - Parameters:
    ///   - chrome: The window's section chrome.
    ///   - rowBottom: The field row's bottom edge, in window (global) points.
    ///   - windowBottom: The window's bottom edge in the same space.
    ///   - fieldHeight: The field's measured height.
    ///   - keyboardTop: The keyboard's top in the same space, or `nil` while hidden.
    /// - Returns: The bottom padding, in points.
    nonisolated static func bottomPadding(
        chrome: DeviceLayout.SectionChrome, rowBottom: CGFloat, windowBottom: CGFloat,
        fieldHeight: CGFloat, keyboardTop: CGFloat?
    ) -> CGFloat {
        if let aligned = searchButtonAlignedBottomPadding(
            chrome: chrome, rowBottom: rowBottom, windowBottom: windowBottom,
            fieldHeight: fieldHeight, keyboardTop: keyboardTop
        ) {
            return aligned
        }
        return rowPadding + keyboardLift(
            rowBottom: rowBottom, keyboardTop: keyboardTop, fieldBottomPadding: rowPadding
        )
    }
}

// MARK: - Column

/// Pads a full-width row into the bottom search field's column
/// (``BottomSearchFieldPlacement/horizontalPadding(container:hinge:layoutDirection:)``),
/// so a control above the content (Search's scope bar, issue #349) shares the field's
/// leading and trailing edges in every pose.
struct BottomSearchFieldColumn: ViewModifier {
    /// ``BottomSearchFieldPlacement/pageHinge(for:)`` (window points).
    let hinge: CGRect?
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var rowFrame = CGRect.zero

    func body(content: Content) -> some View {
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: rowFrame, hinge: hinge, layoutDirection: layoutDirection
        )
        content
            .frame(maxWidth: .infinity)
            .padding(.leading, padding.leading)
            .padding(.trailing, padding.trailing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                rowFrame = frame
            }
    }
}

extension View {
    /// Lays this full-width row out in the iPhone Duo bottom search field's column:
    /// 16 pt margins, or the trailing page across a book-pose fold
    /// (``BottomSearchFieldColumn``).
    ///
    /// - Parameter hinge: ``BottomSearchFieldPlacement/pageHinge(for:)``.
    /// - Returns: The padded row.
    func bottomSearchFieldColumn(hinge: CGRect?) -> some View {
        modifier(BottomSearchFieldColumn(hinge: hinge))
    }
}

// MARK: - Field

/// The iPhone Duo bottom search field: the shared ``GlobalSearchField`` on Liquid
/// Glass (owner, issue #358), in a page's bottom safe area, in the
/// ``BottomSearchFieldColumn`` (full width, or the trailing page across a book fold).
///
/// Used by Songs' Filter field (issue #333) and the Search tab on the inner display
/// (issue #349). It is as tall as the system Search button in the same pose and, beside
/// the vertical bar with the keyboard hidden, centred on it
/// (``BottomSearchFieldPlacement/bottomPadding(chrome:rowBottom:windowBottom:fieldHeight:keyboardTop:)``).
/// As a bottom safe-area inset it rises with the keyboard, plus any measured
/// ``BottomSearchFieldPlacement/keyboardLift(rowBottom:keyboardTop:fieldBottomPadding:gap:)``
/// the system leaves it short. It can report its top for a list's
/// ``SwiftUI/View/bottomChromeFade(chromeTop:distance:in:)``.
struct BottomSearchField: View {
    @Binding var text: String
    let prompt: String
    /// Spoken name of the field.
    let accessibilityLabel: String
    /// UI-test identifier of the text field.
    let identifier: String
    /// UI-test identifier of the clear button.
    let clearIdentifier: String
    /// ``BottomSearchFieldPlacement/pageHinge(for:)`` (window points).
    let hinge: CGRect?
    /// Focus the field (keyboard up) when it appears and whenever this turns on.
    var focusesOnAppear = false
    /// Return/Search was pressed.
    var submit: () -> Void = {}
    /// Coordinate space shared with a faded list, if any.
    var space: String?
    /// Receives the field's top in `space`.
    var chromeTopChanged: (CGFloat?) -> Void = { _ in }
    @State private var rowBottom: CGFloat = 0
    /// The software keyboard's top in screen points (an iPhone window fills its
    /// screen, so global points), or `nil` while it is hidden.
    @State private var keyboardTop: CGFloat?
    /// The field's height (the Search button's, or taller at large Dynamic Type sizes).
    @State private var fieldHeight: CGFloat = 0
    /// The window's bottom edge in global points, past the bottom safe area
    /// (``WindowBottomProbe``).
    @State private var windowBottom: CGFloat = 0
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        let minHeight = BottomSearchFieldPlacement.fieldHeight(for: layout.sectionChrome)
        let bottom = BottomSearchFieldPlacement.bottomPadding(
            chrome: layout.sectionChrome, rowBottom: rowBottom, windowBottom: windowBottom,
            fieldHeight: max(fieldHeight, minHeight), keyboardTop: keyboardTop
        )
        GlobalSearchField(
            text: $text, prompt: prompt, accessibilityLabel: accessibilityLabel,
            identifier: identifier, clearIdentifier: clearIdentifier,
            focusesOnAppear: focusesOnAppear, surface: .floating, minHeight: minHeight,
            submit: submit
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            fieldHeight = height
        }
        .modifier(BottomChromeTopReport(space: space, changed: chromeTopChanged))
        .bottomSearchFieldColumn(hinge: hinge)
        .padding(.top, BottomSearchFieldPlacement.rowPadding)
        .padding(.bottom, bottom)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
            rowBottom = bottom
        }
        .background { WindowBottomProbe { windowBottom = $0 } }
        #if os(iOS)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        ) { note in
            let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            keyboardTop = end.map(\.minY)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            keyboardTop = nil
        }
        #endif
    }
}

/// Reports the window's bottom edge in global points: the edge the system Search button
/// is placed from (issue #358).
///
/// On iPhone Duo the SwiftUI hierarchy ends at the bottom safe area (the root measures
/// 644 pt of a 678 pt folded window), so even a probe that ignores the safe area stops
/// short; iOS reads the hosting `UIWindow`'s bounds instead (window points, which are
/// SwiftUI's global points on iPhone). Elsewhere (the macOS hosted tests) a full-bleed
/// SwiftUI probe suffices.
private struct WindowBottomProbe: View {
    let changed: (CGFloat) -> Void

    var body: some View {
        #if os(iOS)
        WindowBoundsReader(changed: changed)
            .accessibilityHidden(true)
        #else
        Color.clear
            .ignoresSafeArea(.container, edges: .bottom)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
                changed(bottom)
            }
            .accessibilityHidden(true)
        #endif
    }
}

#if os(iOS)
/// A zero-content UIKit view that reports its window's bottom whenever it moves to a
/// window or is laid out again (rotation, fold and unfold re-lay the row out).
private struct WindowBoundsReader: UIViewRepresentable {
    let changed: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.changed = changed
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.changed = changed
        view.report()
    }

    /// Posts the window's bottom after layout, only when it changes.
    final class ProbeView: UIView {
        var changed: ((CGFloat) -> Void)?
        private var reported: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        /// Report `window.bounds.maxY` if it differs from the last report.
        func report() {
            guard let window, window.bounds.maxY != reported else { return }
            let bottom = window.bounds.maxY
            reported = bottom
            let changed = changed
            // Never mutate SwiftUI state during its own layout pass.
            DispatchQueue.main.async { changed?(bottom) }
        }
    }
}
#endif

/// Reports the field's top for a faded list when the page shares a coordinate space.
private struct BottomChromeTopReport: ViewModifier {
    let space: String?
    let changed: (CGFloat?) -> Void

    func body(content: Content) -> some View {
        if let space {
            content.reportsBottomChromeTop(in: space, changed)
        } else {
            content
        }
    }
}

// MARK: - Fade

/// A list's fade above the iPhone Duo bottom search field: the shared
/// ``SwiftUI/View/bottomChromeFade(chromeTop:distance:in:)`` (scroll-edge R1), used by
/// Songs (issue #333) and Search's results (issue #349).
///
/// The scroll-driven fade height lives here, not on the page, so the last fade-height
/// of scrolling re-renders only this modifier, never the page's filter/sort pipeline
/// (issues #8, #325).
struct BottomSearchFieldFade: ViewModifier {
    /// The field's top, read in the page's `body` (issue #294).
    let chromeTop: CGFloat?
    /// Whether the page shows the bottom field.
    let enabled: Bool
    /// Coordinate space shared with the field.
    let space: String
    @State private var distance = 0.0

    func body(content: Content) -> some View {
        if enabled {
            content.bottomChromeFade(chromeTop: chromeTop, distance: $distance, in: space)
        } else {
            content
        }
    }
}
