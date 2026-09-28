import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Placement

extension View {
    /// Songs search, placed per `.agents/design/apple/nav-accessories.md`.
    ///
    /// - iOS 26.1+ with a horizontal tab bar: a "Search Songs" pill in the tab-bar
    ///   bottom accessory (Music's mini-player slot). Tapping it hides the tab bar and
    ///   raises a focused glass search field above the keyboard; losing focus returns
    ///   to the pill, which keeps showing the query with a clear button.
    /// - Elsewhere (iOS 17–26.0, iPhone Duo vertical bar, iPad/Mac): system `.searchable`.
    ///
    /// - Parameter text: Live search text (root-owned so it survives tab switches).
    /// - Returns: The Songs page with search attached.
    func songsSearch(text: Binding<String>) -> some View {
        modifier(SongsSearchPlacement(text: text))
    }
}

/// Implementation of `songsSearch(text:)`.
struct SongsSearchPlacement: ViewModifier {
    @Binding var text: String
    @Environment(\.isTabAccessoryAvailable) private var accessoryAvailable
    @State private var editing = false

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *), accessoryAvailable {
            content
                .festivalTabAccessory(token: editing, isEnabled: !editing) {
                    SongsSearchAccessory(text: $text) { editing = true }
                }
                .toolbar(editing ? .hidden : .automatic, for: .tabBar)
                .safeAreaBar(edge: .bottom) {
                    if editing {
                        SongsSearchBar(text: $text, submit: {
                            editing = false
                        }, close: {
                            text = ""
                            editing = false
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.25), value: editing)
        } else {
            content.searchable(text: $text, prompt: Text("Search"))
        }
        #else
        content.searchable(text: $text, prompt: Text("Search"))
        #endif
    }
}

// MARK: - Accessory

/// The resting search control in the tab-bar accessory: a field-shaped button showing
/// the prompt or the current query, plus a clear button once a query is applied.
struct SongsSearchAccessory: View {
    @Binding var text: String
    let activate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: activate) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityHidden(true)
                    Text(text.isEmpty ? "Search Songs" : text)
                        .foregroundStyle(text.isEmpty ? BrandTokens.textSecondary : BrandTokens.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search Songs")
            .accessibilityValue(text)
            .accessibilityHint("Opens the search field")
            .accessibilityIdentifier("fst.songs.search.open")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("fst.songs.search.clear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, text.isEmpty ? 16 : 4)
    }
}

// MARK: - Editing bar

/// The active search field, docked above the keyboard while the tab bar is hidden
/// (the system search tab's "field above the keyboard" shape).
struct SongsSearchBar: View {
    @Binding var text: String
    /// Return key: keep the query and hand back to the accessory pill.
    let submit: () -> Void
    /// Close button: clear the query and hand back to the accessory pill.
    let close: () -> Void
    /// Owned here, beside its `TextField`, so resigning is always observed.
    @FocusState private var focused: Bool

    var body: some View {
        FestivalGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .accessibilityHidden(true)
                    TextField("Search Songs", text: $text)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                        .autocorrectionDisabled()
                        .foregroundStyle(BrandTokens.textPrimary)
                        .accessibilityIdentifier("fst.songs.search")
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(BrandTokens.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .festivalGlassCapsule(.control, interactive: true)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTokens.textPrimary)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .festivalGlassCapsule(.control, interactive: true)
                .accessibilityLabel("Close Search")
                .accessibilityIdentifier("fst.songs.search.close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            // The field must be in the hierarchy before it can take focus.
            Task { @MainActor in focused = true }
        }
        .onChange(of: focused) { wasFocused, isFocused in
            // Keyboard dismissed another way (scroll, row tap): back to the pill.
            if wasFocused && !isFocused { submit() }
        }
    }
}
