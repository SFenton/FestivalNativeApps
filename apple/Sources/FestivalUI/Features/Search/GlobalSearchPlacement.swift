// MARK: - Field placement

/// Where the Search tab's field sits (issue #349).
///
/// The system `.searchable` field everywhere but the iPhone Duo inner display. There,
/// beside the vertical tab bar, the system field took only the bottom trailing ~370 pt
/// and rose centred over the keyboard while the scope bar spanned the page. The owner
/// asked for a field across the full bottom width when flat, on the right page when
/// book-folded ("search bar when keyboard is closed and unfolded should take full
/// bottom width. Can stay on right side if hinge is unfolded but device is not
/// completely unfolded"), which no system search API sets, so the tab shows the shared
/// ``BottomSearchField`` (Songs' Duo field, issue #333) and the scope bar shares its
/// column. HIG Search fields: "Place search at the bottom if there's room; this keeps
/// priority search easy to reach". The folded outer display keeps the system field,
/// which already spans its bottom like an iPhone's.
enum GlobalSearchFieldPlacement: Equatable {
    /// The system `.searchable` field of the Search tab (or the iPad sidebar page).
    case system
    /// The tab's own ``BottomSearchField`` (iPhone Duo inner display).
    case bottom

    /// The placement for a device pose.
    ///
    /// - Parameters:
    ///   - pose: The window's ``DeviceLayout/pose``.
    ///   - asTab: Whether search is the phone Search tab (false: the iPad sidebar page).
    /// - Returns: `.bottom` for the Search tab on an unfolded or partially folded iPhone
    ///   Duo, else `.system`.
    nonisolated static func resolve(pose: DeviceLayout.Pose, asTab: Bool) -> GlobalSearchFieldPlacement {
        guard asTab else { return .system }
        switch pose {
        case .unfolded, .partiallyFolded: return .bottom
        case .standard, .folded: return .system
        }
    }
}

// MARK: - Title style

/// How the Search page draws its large "Search" title (issue #611).
///
/// The transient phone Search tab has nothing in its navigation bar (no drawer, bell or
/// Profile; HIG Search fields: a Search tab is "fast, transient search that returns to
/// the previous tab on exit"), so the standard large title left that bar's whole row
/// empty above it: a 54 pt dead band between the status bar and "Search" that every
/// other root fills with its drawer and Profile buttons. The tab draws the same large
/// system title inside that row instead (`ToolbarTitleDisplayMode.inlineLarge`), so the
/// scope bar sits directly under it. The iPad sidebar's Search page keeps the standard
/// large title: its row holds the bell and Profile.
enum GlobalSearchTitleStyle: Equatable {
    /// The large title inside the navigation bar's row (the phone Search tab).
    case inlineLarge
    /// The system default: the large title below the bar's row (iPad sidebar page).
    case standard

    /// The title style for a Search page.
    ///
    /// - Parameter asTab: Whether search is the phone Search tab (false: the iPad
    ///   sidebar page, whose bar row holds the account items).
    /// - Returns: `.inlineLarge` for the Search tab, else `.standard`.
    nonisolated static func resolve(asTab: Bool) -> GlobalSearchTitleStyle {
        asTab ? .inlineLarge : .standard
    }
}
