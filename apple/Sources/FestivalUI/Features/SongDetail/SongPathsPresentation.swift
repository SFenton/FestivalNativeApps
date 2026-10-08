import FestivalCore

// MARK: - View mode

/// What the Paths viewer shows: one of the two path forms the service publishes
/// (``PathDisplayMode``), or both side by side (owner, issue #368; native only, the web's
/// `PathsModal` has Image and Text). Settings' Path Default View stays Image or Text.
enum PathViewMode: String, CaseIterable, Identifiable, Sendable {
    /// The CHOpt path image.
    case image
    /// The activation table.
    case text
    /// The image beside (or, across a horizontal fold, above) the table.
    case sideBySide

    var id: Self { self }

    /// Title Case menu label.
    var label: String {
        switch self {
        case .image: "Image"
        case .text: "Text"
        case .sideBySide: "Side by Side"
        }
    }

    /// The mode showing one path form.
    ///
    /// - Parameter display: Image or text.
    init(_ display: PathDisplayMode) {
        switch display {
        case .image: self = .image
        case .text: self = .text
        }
    }

    /// The path forms this mode loads and shows, in reading order (image first).
    var displays: [PathDisplayMode] {
        switch self {
        case .image: [.image]
        case .text: [.text]
        case .sideBySide: [.image, .text]
        }
    }
}

// MARK: - Policy

/// Where and how Paths presents (owner-approved `modal-shell` variant, issue #368).
///
/// - iPhone, the folded iPhone Duo and a compact iPad window: today's large sheet with
///   Image and Text.
/// - The iPhone Duo inner display (flat or book pose), an iPad in the sidebar shell and
///   the Mac: over the whole window, with Image, Text and Side by Side.
/// - Book pose (the Duo partially folded): Side by Side only, the image and the table
///   on either side of the hinge (owner: "If partial fold, enforce side by side").
enum SongPathsPolicy {
    /// The presentation for the window's layout when Paths opens.
    ///
    /// - Parameter layout: The window's published layout.
    /// - Returns: `.fullScreen` on the Duo inner display, the iPad sidebar shell and the
    ///   Mac; `.sheet` elsewhere.
    nonisolated static func coverage(_ layout: DeviceLayout) -> FestivalModalCoverage {
        isWide(layout) ? .fullScreen : .sheet
    }

    /// The view modes the View menu offers for the current layout.
    ///
    /// - Parameter layout: The window's current layout (folding while open changes it).
    /// - Returns: Side by Side alone in book pose; all three where the viewer covers a
    ///   wide window; Image and Text elsewhere.
    nonisolated static func modes(for layout: DeviceLayout) -> [PathViewMode] {
        if isBookPose(layout) { return [.sideBySide] }
        return isWide(layout) ? PathViewMode.allCases : [.image, .text]
    }

    /// The mode shown for a selection in the current layout.
    ///
    /// A selection the layout doesn't offer is kept for later (folding then unfolding
    /// brings Side by Side back) and shown as its nearest offered mode: Side by Side
    /// in book pose, the Settings default when Side by Side doesn't fit.
    ///
    /// - Parameters:
    ///   - selection: The View menu's selection.
    ///   - layout: The window's current layout.
    ///   - fallback: Settings' Path Default View.
    /// - Returns: The mode to show.
    nonisolated static func resolve(
        _ selection: PathViewMode, layout: DeviceLayout, fallback: PathDisplayMode
    ) -> PathViewMode {
        let offered = modes(for: layout)
        if offered.contains(selection) { return selection }
        return offered.contains(.sideBySide) ? .sideBySide : PathViewMode(fallback)
    }

    /// Whether the View menu shows (hidden when book pose leaves one mode).
    ///
    /// - Parameter layout: The window's current layout.
    /// - Returns: True when more than one mode is offered.
    nonisolated static func showsViewMenu(_ layout: DeviceLayout) -> Bool {
        modes(for: layout).count > 1
    }

    /// The iPhone Duo partially folded (book pose) on its inner display.
    private nonisolated static func isBookPose(_ layout: DeviceLayout) -> Bool {
        layout.pose == .partiallyFolded && layout.windowWidthClass == .regular
    }

    /// A window wide enough for the full-window viewer: the iPad/Mac sidebar shell, or
    /// the iPhone Duo inner display (flat or book pose). Width class alone would also
    /// catch a large iPhone in landscape, which keeps the sheet.
    private nonisolated static func isWide(_ layout: DeviceLayout) -> Bool {
        if layout.sectionChrome == .sidebar { return true }
        return (layout.pose == .unfolded || layout.pose == .partiallyFolded)
            && layout.windowWidthClass == .regular
    }
}
