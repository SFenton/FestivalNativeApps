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

/// The iPhone Duo bottom search field: the shared ``GlobalSearchField`` on the
/// floating-control surface, in a page's bottom safe area, in the
/// ``BottomSearchFieldColumn`` (full width, or the trailing page across a book fold).
///
/// Used by Songs' Filter field (issue #333) and the Search tab on the inner display
/// (issue #349). As a bottom safe-area inset it rises with the keyboard, plus any
/// measured
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

    var body: some View {
        let lift = BottomSearchFieldPlacement.keyboardLift(
            rowBottom: rowBottom, keyboardTop: keyboardTop
        )
        GlobalSearchField(
            text: $text, prompt: prompt, accessibilityLabel: accessibilityLabel,
            identifier: identifier, clearIdentifier: clearIdentifier,
            focusesOnAppear: focusesOnAppear, surface: .floating, submit: submit
        )
        .modifier(BottomChromeTopReport(space: space, changed: chromeTopChanged))
        .bottomSearchFieldColumn(hinge: hinge)
        .padding(.top, 8)
        .padding(.bottom, 8 + lift)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
            rowBottom = bottom
        }
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
