import SwiftUI

// MARK: - Policy

/// Where the Songs "Filter Songs" field sits on each device (issue #333).
///
/// iPhone, iPad and Mac keep the inline `.searchable` field pinned under the title
/// (`page-tools-and-nav-chrome` R2). On iPhone Duo, folded or unfolded, the owner chose
/// a field at the bottom of the page, within thumb reach ("Filter Songs should be at
/// bottom of screen on Duo for ease of use"; HIG Search fields: "Place search at the
/// bottom if there's room; this keeps priority search easy to reach"). Across a
/// book-pose fold it lies on the trailing page, clear of the fold; a flat display keeps
/// the full width (issue #349): the shared ``BottomSearchField`` and
/// ``BottomSearchFieldPlacement``.
enum SongsFilterFieldPlacement: Equatable {
    /// The system `.searchable` field: the navigation-bar drawer under the title on
    /// iOS, the toolbar on the Mac (``SongsScreen/filterFieldPlacement``).
    case system
    /// The page's own field in its bottom safe area (iPhone Duo).
    case bottom

    /// The placement for a device pose.
    ///
    /// - Parameter pose: The window's ``DeviceLayout/pose``; only iPhone Duo reports
    ///   anything but `.standard`.
    /// - Returns: `.bottom` on iPhone Duo, else `.system`.
    nonisolated static func resolve(pose: DeviceLayout.Pose) -> SongsFilterFieldPlacement {
        pose == .standard ? .system : .bottom
    }
}

// MARK: - Modifiers

/// The system `.searchable` Filter Songs field, left off where the page shows its own
/// bottom field (iPhone Duo, issue #333).
///
/// On iOS the drawer field keeps its capsule while Song Detail is pushed or popped
/// (``SearchDrawerTransitionFill``, issue #544).
struct SongsSystemFilterField: ViewModifier {
    @Binding var text: String
    /// Whether this window uses the system field (``SongsFilterFieldPlacement/system``).
    let enabled: Bool
    /// The Songs List's scroll view, used to tell whether rows are under the bar.
    let listNudger: ListScrollNudger

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(
                text: $text, placement: SongsScreen.filterFieldPlacement,
                prompt: Text("Filter Songs")
            )
            #if os(iOS)
            .modifier(SearchDrawerTransitionFill { [listNudger] in
                SearchDrawerTransitionFill.isContentUnderBar(listNudger.scrollView)
            })
            #endif
        } else {
            content
        }
    }
}
