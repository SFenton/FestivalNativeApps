import SwiftUI

// MARK: - Shared modal

/// The one container every Festival modal is built from (issue #23): a `NavigationStack`
/// with an inline title and the system Close (``FestivalSheetCloseItem``) at the top
/// trailing edge. Its content fades out as it scrolls under that header
/// (``ModalTopEdgeFadeModifier``, issue #94).
///
/// HIG (Toolbars): "Close dismisses a modal; prefer their standard symbols without text
/// labels." Sheets therefore never draw their own ✕, a text "Close"/"Done" or a bottom
/// Close: they put their content in `FestivalModal` and keep any extra toolbar items,
/// `.searchable` or `.navigationDestination` on that content. Presentation styling stays
/// separate: apply ``SwiftUI/View/festivalSheet(_:sizing:)`` (or a modal's own detents) to
/// the result as before.
///
/// ```swift
/// FestivalModal("Find Rival", closeIdentifier: "fst.rivals.findRival.close", path: $path) {
///     list.navigationDestination(for: AppRoute.self) { … }
/// }
/// .festivalSheet(.large)
/// ```
struct FestivalModal<Content: View>: View {
    private let title: String?
    private let closeIdentifier: String
    private let path: Binding<[AppRoute]>?
    private let onClose: (() -> Void)?
    private let content: Content
    @Environment(\.dismiss) private var dismiss

    /// Create a modal.
    ///
    /// - Parameters:
    ///   - title: Inline navigation title, which VoiceOver announces first; `nil` only for a
    ///     modal whose content carries its own heading (every current modal, the first-run
    ///     guide included since issue #24, passes one).
    ///   - closeIdentifier: Accessibility identifier of the Close button (existing modals
    ///     keep theirs so UI tests stay stable).
    ///   - path: Navigation path for modals that push routes inside themselves; `nil` for a
    ///     plain stack.
    ///   - onClose: Runs instead of the environment `dismiss` when the presenter owns the
    ///     closing (for example to record what was seen); `nil` dismisses.
    ///   - content: The modal's root view, placed inside the navigation stack.
    init(
        _ title: String?, closeIdentifier: String, path: Binding<[AppRoute]>? = nil,
        onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.closeIdentifier = closeIdentifier
        self.path = path
        self.onClose = onClose
        self.content = content()
    }

    @Environment(\.festivalModalPreview) private var isPreview

    var body: some View {
        if isPreview {
            content
        } else if let path {
            NavigationStack(path: path) { chrome }
        } else {
            NavigationStack { chrome }
        }
    }

    private var chrome: some View {
        content
            // Content fades out under the header rather than drawing behind it (#94).
            .modifier(ModalTopEdgeFadeModifier())
            .modifier(FestivalModalTitle(title: title))
            .toolbar {
                FestivalSheetCloseItem(identifier: closeIdentifier, action: close)
            }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

extension EnvironmentValues {
    /// Whether a ``FestivalModal`` shows only its content, with no navigation stack, title or
    /// Close: a real sheet embedded as a picture inside another modal, such as a first-run
    /// demo (issue #25). SwiftUI merges a nested `NavigationStack`'s title and toolbar into
    /// the enclosing one, so a live modal there would replace the outer title and add a
    /// second, working Close to the outer navigation bar.
    @Entry var festivalModalPreview = false
}

/// Inline title (iOS) when the modal has one.
private struct FestivalModalTitle: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } else {
            content
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}
