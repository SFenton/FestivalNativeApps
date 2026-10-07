import SwiftUI

// MARK: - Policy

/// Where the Songs "Filter Songs" field sits on each device (issue #333).
///
/// iPhone, iPad and Mac keep the inline `.searchable` field pinned under the title
/// (`page-tools-and-nav-chrome` R2). On iPhone Duo, folded or unfolded, the owner chose
/// a field at the bottom of the page, within thumb reach ("Filter Songs should be at
/// bottom of screen on Duo for ease of use"; HIG Search fields: "Place search at the
/// bottom if there's room; this keeps priority search easy to reach"). Across a
/// vertical hinge (book or flat landscape on the inner display) it lies on the
/// trailing page, clear of the fold (HIG Designing for iPhone Duo: "use reserved-region
/// APIs to keep important elements clear of the center").
enum SongsFilterFieldPlacement: Equatable {
    /// The system `.searchable` field: the navigation-bar drawer under the title on
    /// iOS, the toolbar on the Mac (``SongsScreen/filterFieldPlacement``).
    case system
    /// The page's own field in its bottom safe area (iPhone Duo).
    case bottom

    /// Standard gap between the field and the page or hinge edges (the rows' margin).
    nonisolated static let margin: CGFloat = 16

    /// Narrowest trailing page the field moves to; a narrower one keeps the full width.
    nonisolated static let minimumPageWidth: CGFloat = 200

    /// The placement for a device pose.
    ///
    /// - Parameter pose: The window's ``DeviceLayout/pose``; only iPhone Duo reports
    ///   anything but `.standard`.
    /// - Returns: `.bottom` on iPhone Duo, else `.system`.
    nonisolated static func resolve(pose: DeviceLayout.Pose) -> SongsFilterFieldPlacement {
        pose == .standard ? .system : .bottom
    }

    /// Horizontal padding that keeps the bottom field on the trailing page.
    ///
    /// Without a vertical hinge crossing the field's row (folded, inner portrait), both
    /// sides get the standard ``margin``. With one, the leading padding reaches past
    /// the hinge, so the field starts a margin beyond it: the right page in a
    /// left-to-right layout, the left page right-to-left.
    ///
    /// - Parameters:
    ///   - container: The field row's frame, in window (global) points.
    ///   - hinge: ``DeviceLayout/splitHinge`` in the same space, if any.
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

// MARK: - Field

/// The iPhone Duo bottom "Filter Songs" field (issue #333): the shared
/// ``GlobalSearchField`` on the floating-control surface, in the page's bottom safe
/// area and, across a vertical hinge, on the trailing page.
///
/// It edits the same tab-owned text as the `.searchable` field it replaces, so the
/// 250 ms debounce, sort, filters and the A–Z scrubber behave unchanged; as a bottom
/// safe-area inset it rises with the keyboard, plus any measured
/// ``SongsFilterFieldPlacement/keyboardLift(rowBottom:keyboardTop:fieldBottomPadding:gap:)``
/// the system leaves it short. It reports its top for the list's
/// ``SwiftUI/View/bottomChromeFade(chromeTop:distance:in:)``.
struct SongsBottomFilterField: View {
    @Binding var text: String
    /// ``DeviceLayout/splitHinge`` (window points).
    let hinge: CGRect?
    /// Coordinate space shared with the faded list.
    let space: String
    /// Receives the field's top in `space`.
    let chromeTopChanged: (CGFloat?) -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var rowFrame = CGRect.zero
    /// The software keyboard's top in screen points (an iPhone window fills its
    /// screen, so global points), or `nil` while it is hidden.
    @State private var keyboardTop: CGFloat?

    var body: some View {
        let padding = SongsFilterFieldPlacement.horizontalPadding(
            container: rowFrame, hinge: hinge, layoutDirection: layoutDirection
        )
        let lift = SongsFilterFieldPlacement.keyboardLift(
            rowBottom: rowFrame.maxY, keyboardTop: keyboardTop
        )
        GlobalSearchField(
            text: $text, prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
            identifier: "fst.songs.filter-field", clearIdentifier: "fst.songs.filter-clear",
            focusesOnAppear: false, surface: .floating
        )
        .reportsBottomChromeTop(in: space, chromeTopChanged)
        .padding(.leading, padding.leading)
        .padding(.trailing, padding.trailing)
        .padding(.top, 8)
        .padding(.bottom, 8 + lift)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowFrame = frame
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

// MARK: - Modifiers

/// The system `.searchable` Filter Songs field, left off where the page shows its own
/// bottom field (iPhone Duo, issue #333).
struct SongsSystemFilterField: ViewModifier {
    @Binding var text: String
    /// Whether this window uses the system field (``SongsFilterFieldPlacement/system``).
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(
                text: $text, placement: SongsScreen.filterFieldPlacement,
                prompt: Text("Filter Songs")
            )
        } else {
            content
        }
    }
}

/// The Songs list's fade above the iPhone Duo bottom Filter field: the shared
/// ``SwiftUI/View/bottomChromeFade(chromeTop:distance:in:)`` (scroll-edge R1).
///
/// The scroll-driven fade height lives here, not on ``SongsScreen``, so the last
/// fade-height of scrolling re-renders only this modifier, never the page's
/// filter/sort pipeline (issues #8, #325).
struct SongsBottomFieldFade: ViewModifier {
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
