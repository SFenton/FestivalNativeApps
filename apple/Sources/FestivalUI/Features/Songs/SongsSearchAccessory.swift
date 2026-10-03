import SwiftUI
import FestivalDesign

// MARK: - Rules

/// The Songs list search when it leads the iOS 26.1+ page-tools dock (issues #42, #89).
///
/// The dock shows a field-shaped button; tapping it opens ``SongsSearchBar``, a
/// focused field that rides just above the keyboard (HIG Search fields: a bottom field
/// "animates above the keyboard when tapped"). A `TextField` inside the system tab-bar
/// accessory (issue #42's first home) did not take focus and stayed under the keyboard on iOS 26.5
/// (`.agents/design/apple/nav-accessories.md`). The text is the same Songs filter the
/// `.searchable` field edits on earlier iOS, the iPhone Duo rail, iPad and Mac.
enum SongsSearchAccessory {
    /// Placeholder naming what the field searches (web `songs.searchPlaceholder`).
    static let prompt = "Search songs or artists"
    /// Placeholder when the dock beside the minimized tab bar has no room for ``prompt``.
    static let shortPrompt = "Search"
    /// VoiceOver name of the accessory button and the field.
    static let accessibilityLabel = "Search Songs"

    /// What the accessory button shows.
    ///
    /// - Parameter query: The current Songs search text.
    /// - Returns: The query while one is entered, otherwise nil (show the prompt).
    static func displayedQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : query
    }

    /// Whether the Clear button shows beside the accessory button.
    ///
    /// - Parameter query: The current Songs search text.
    /// - Returns: True when any text, even whitespace, is entered.
    static func showsClear(_ query: String) -> Bool {
        !query.isEmpty
    }

    /// Whether the search bar should close after a focus change: only when the field
    /// loses focus it had (the keyboard was dismissed by scrolling or another control),
    /// never before the first focus lands.
    ///
    /// - Parameters:
    ///   - wasFocused: Focus before the change.
    ///   - isFocused: Focus after the change.
    /// - Returns: True when the field just lost focus.
    static func closesOnFocusChange(wasFocused: Bool, isFocused: Bool) -> Bool {
        wasFocused && !isFocused
    }
}

// MARK: - Accessory button

/// The Songs search in the page-tools dock: a field-shaped button showing the
/// prompt or the current query, plus Clear while text is entered. Both are separate
/// VoiceOver elements with 44 pt hit targets.
struct SongsSearchAccessoryButton: View {
    let query: String
    let open: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                    label
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(FestivalText.primary)
            .accessibilityLabel(SongsSearchAccessory.accessibilityLabel)
            .accessibilityValue(SongsSearchAccessory.displayedQuery(query) ?? "")
            .accessibilityHint("Opens a search field above the keyboard")
            .accessibilityIdentifier("fst.songs.search.open")
            .accessibilityShowsLargeContentViewer {
                Label(SongsSearchAccessory.accessibilityLabel, systemImage: "magnifyingglass")
            }
            if SongsSearchAccessory.showsClear(query) {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FestivalText.primary)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("fst.songs.search.clear")
                .accessibilityShowsLargeContentViewer()
            }
        }
    }

    /// The query, or the prompt shortened (or dropped) to fit beside the minimized tab bar.
    @ViewBuilder private var label: some View {
        if let shown = SongsSearchAccessory.displayedQuery(query) {
            Text(shown).lineLimit(1)
        } else {
            // Beside the minimized tab bar the field can shrink to its magnifier alone
            // (HIG Search fields: "choose an expanded field or button according to
            // available space"); VoiceOver still reads "Search Songs".
            ViewThatFits(in: .horizontal) {
                Text(SongsSearchAccessory.prompt).lineLimit(1)
                Text(SongsSearchAccessory.shortPrompt).lineLimit(1)
                Color.clear.frame(width: 0, height: 0)
            }
            .opacity(0.8)
        }
    }
}

// MARK: - Search bar

/// The focused Songs search field shown above the keyboard while searching from the
/// page-tools dock (which steps aside meanwhile). Return keeps the query and closes the bar; Cancel clears it.
/// The list filters as you type, behind the keyboard.
struct SongsSearchBar: View {
    @Binding var text: String
    /// Close the bar (the query stays).
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        FestivalGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityHidden(true)
                    TextField(
                        SongsSearchAccessory.accessibilityLabel, text: $text,
                        prompt: Text(SongsSearchAccessory.prompt)
                    )
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(close)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityIdentifier("fst.songs.search.field")
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityLabel("Clear Search")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, text.isEmpty ? 14 : 2)
                .frame(minHeight: 48)
                .festivalGlassCapsule(.control, interactive: true)
                Button {
                    text = ""
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FestivalText.primary)
                .festivalGlassCapsule(.control, interactive: true)
                .accessibilityLabel("Cancel Search")
                .accessibilityIdentifier("fst.songs.search.cancel")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task {
            // Focus once the bar is in the hierarchy; focusing during insertion is ignored.
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
        .onChange(of: focused) { was, now in
            if SongsSearchAccessory.closesOnFocusChange(wasFocused: was, isFocused: now) {
                close()
            }
        }
    }
}
