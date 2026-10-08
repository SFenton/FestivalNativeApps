import SwiftUI
import FestivalDesign
#if os(macOS)
import AppKit
#endif

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

// MARK: - Full-screen presentation

/// How much of the window a Festival modal covers.
enum FestivalModalCoverage: Sendable, Equatable {
    /// The system sheet (the default everywhere, modal-shell R1).
    case sheet
    /// The whole window: a `fullScreenCover` on iOS/iPadOS, a sheet the size of the
    /// window on macOS, which has no full-screen cover (HIG Sheets: "Consider
    /// alternatives for complex or prolonged flows: a full-screen modal … in iOS and
    /// iPadOS for media…"). Used by What's New on iPhone and Paths on the iPhone Duo
    /// inner display, iPad and Mac (owner, issue #368).
    case fullScreen
}

extension EnvironmentValues {
    /// The coverage of the modal this view is presented in, so content can stand in for
    /// gestures a cover lacks (``PullDownToDismiss``). `.sheet` outside a modal.
    @Entry var festivalModalCoverage: FestivalModalCoverage = .sheet
}

extension View {
    /// Present a Festival modal as a sheet or over the whole window, chosen from the
    /// window's layout when it opens and kept until it closes, so folding or unfolding an
    /// iPhone Duo (or resizing an iPad window) never re-presents it, runs `onDismiss`
    /// early or loses its state (HIG Designing for iPhone Duo: "Preserve functionality,
    /// element state, hierarchy, and access across displays/poses").
    ///
    /// A cover is opaque (`BrandTokens.cardBackground`): nothing behind it should show.
    /// It keeps the shared modal's Close; it has no system swipe-down, so content that can
    /// offers ``PullDownToDismiss`` (read ``SwiftUI/EnvironmentValues/festivalModalCoverage``).
    ///
    /// - Parameters:
    ///   - isPresented: Presentation binding.
    ///   - onDismiss: Runs after the presentation closes.
    ///   - coverage: The coverage for the window's current layout.
    ///   - content: The modal, built from ``FestivalModal``.
    /// - Returns: The view with the presentation attached.
    func festivalModalPresentation<Content: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        coverage: @escaping (DeviceLayout) -> FestivalModalCoverage,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(FestivalModalPresentation(
            isPresented: isPresented, onDismiss: onDismiss, coverage: coverage, modal: content
        ))
    }
}

/// Latched sheet-or-cover presentation (see
/// ``SwiftUI/View/festivalModalPresentation(isPresented:onDismiss:coverage:content:)``).
private struct FestivalModalPresentation<Modal: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let coverage: (DeviceLayout) -> FestivalModalCoverage
    let modal: () -> Modal
    @Environment(\.deviceLayout) private var layout
    /// The coverage latched while presented; nil while closed.
    @State private var latched: FestivalModalCoverage?
    #if os(macOS)
    /// The presenter's window, which a full-window Mac sheet matches.
    @State private var host = MacHostWindow()
    #endif

    private var current: FestivalModalCoverage { latched ?? coverage(layout) }

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .fullScreenCover(
                isPresented: Binding(get: { isPresented && current == .fullScreen }, set: { isPresented = $0 }),
                onDismiss: onDismiss
            ) {
                modal()
                    .environment(\.festivalModalCoverage, .fullScreen)
                    .presentationBackground(BrandTokens.cardBackground)
            }
            .sheet(
                isPresented: Binding(get: { isPresented && current == .sheet }, set: { isPresented = $0 }),
                onDismiss: onDismiss, content: modal
            )
            #else
            .background(MacHostWindowReader(host: host))
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                if current == .fullScreen {
                    MacWindowSizedSheet(window: host.window ?? NSApp.mainWindow, content: modal)
                        .environment(\.festivalModalCoverage, .fullScreen)
                } else {
                    modal()
                }
            }
            #endif
            .onChange(of: isPresented, initial: true) { _, presented in
                latched = presented ? coverage(layout) : nil
            }
    }
}

// MARK: - Pull down to dismiss

/// Dismiss when a scroll view is pulled down past its top by ``threshold`` points and
/// released, standing in for the swipe-down a sheet gets for free in a full-screen cover
/// (What's New on iPhone; Paths over the whole window, issue #368).
///
/// Uses iOS/macOS 18 scroll geometry and phase observation; a no-op before that, where Close
/// and Dismiss remain.
struct PullDownToDismiss: ViewModifier {
    /// Overscroll distance that counts as a deliberate pull.
    static let threshold: CGFloat = 80

    /// Off where the system sheet's own swipe-down already dismisses.
    var isEnabled = true
    let action: () -> Void
    @State private var maxPull: CGFloat = 0
    @State private var fired = false

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if #available(iOS 18.0, macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    -(geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, pull in
                    maxPull = max(maxPull, pull)
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if newPhase == .interacting {
                        maxPull = 0
                    } else if oldPhase == .interacting {
                        if Self.shouldDismiss(pull: maxPull), !fired {
                            fired = true
                            action()
                        }
                        maxPull = 0
                    }
                }
        } else {
            content
        }
    }

    /// Whether a released pull dismisses.
    ///
    /// - Parameter pull: Largest overscroll above the top during the drag, in points.
    /// - Returns: True at or past ``threshold``.
    static func shouldDismiss(pull: CGFloat) -> Bool {
        pull >= threshold
    }
}

#if os(macOS)
/// A Mac sheet as large as its parent window's content area, standing in for the
/// full-screen cover macOS lacks (owner, issue #368: "a Mac-appropriate full-window
/// presentation"). The size is read from the presenter's window when the sheet opens;
/// the sheet can still shrink to ``minimumSize``.
struct MacWindowSizedSheet<Content: View>: View {
    /// Smallest size the sheet keeps, the Paths viewer's former default.
    static var minimumSize: CGSize { CGSize(width: 560, height: 480) }

    /// The parent window, if known.
    let window: NSWindow?
    let content: () -> Content

    var body: some View {
        let size = Self.size(window: window?.contentLayoutRect.size)
        content()
            .frame(
                minWidth: Self.minimumSize.width, idealWidth: size.width, maxWidth: .infinity,
                minHeight: Self.minimumSize.height, idealHeight: size.height, maxHeight: .infinity
            )
            .background(MacHostWindowReader(host: MacHostWindow()) { sheet in
                // SwiftUI adds the sheet's button bar outside the fitted frame, so match
                // the sheet window to the parent's content area once it is attached.
                let target = Self.size(window: window?.contentLayoutRect.size)
                guard window != nil, sheet.frame.size != target else { return }
                sheet.setContentSize(target)
            })
    }

    /// The sheet's size for a window.
    ///
    /// - Parameter window: The parent window's content layout size (below its toolbar), if known.
    /// - Returns: That size, at least ``minimumSize``; ``minimumSize`` without a window.
    static func size(window: CGSize?) -> CGSize {
        guard let window else { return minimumSize }
        return CGSize(width: max(minimumSize.width, window.width), height: max(minimumSize.height, window.height))
    }
}

/// Weak reference to the window hosting a presenter (``MacHostWindowReader``).
@MainActor
final class MacHostWindow {
    /// The window, once the presenter is in one.
    weak var window: NSWindow?
}

/// Records the window its presenter lives in. `NSApp.mainWindow` is nil while the app
/// is inactive, and on the Mac a pane, not the window, publishes the layout.
struct MacHostWindowReader: NSViewRepresentable {
    let host: MacHostWindow
    /// Runs on the next main-queue turn after the probe enters a window.
    var onWindow: ((NSWindow) -> Void)?

    func makeNSView(context: Context) -> NSView { Probe(host: host, onWindow: onWindow) }

    func updateNSView(_ view: NSView, context: Context) {}

    /// Zero-size view that reports its window when it moves into one.
    final class Probe: NSView {
        let host: MacHostWindow
        let onWindow: ((NSWindow) -> Void)?

        init(host: MacHostWindow, onWindow: ((NSWindow) -> Void)?) {
            self.host = host
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.window = window
            guard let window, let onWindow else { return }
            DispatchQueue.main.async { onWindow(window) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
