import SwiftUI
import FestivalCore
import FestivalDesign

/// The Paths sheet's bottom row of native pop-up menus: instrument, difficulty and view.
///
/// One view for the sheet (``SongPathsSheet``) and the Song Details first-run demo, which
/// embeds it inert (issue #380: a demo shows the real control). Issue #88: the instrument is
/// a native menu like the other two, not the web's mobile accordion; pop-up-buttons › "a flat
/// list of mutually exclusive options".
struct SongPathsSelectorRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.deviceLayout) private var deviceLayout
    /// Icon side of the icon-only instrument selector (folded iPhone Duo, issue #360),
    /// scaled with Dynamic Type because no name carries the size there.
    @ScaledMetric(relativeTo: .body) private var iconOnlySide: CGFloat = InstrumentIcon.menuIconSide

    @Binding var instrument: Instrument
    @Binding var difficulty: PathDifficulty
    @Binding var display: PathDisplayMode
    /// Enabled path-capable instruments in source order.
    let instruments: [Instrument]
    /// Whether the song's Lead charts show the keys artwork.
    let songUsesKeyboardIcon: Bool

    private var selectorLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        selectorLayout {
            selectorMenu("Instrument", selection: $instrument, value: instrument.label) {
                ForEach(instruments) { choice in
                    Label {
                        Text(choice.label)
                    } icon: {
                        InstrumentIcon.menuImage(for: choice, keyboard: usesKeyboardIcon(choice))
                    }
                    .tag(choice)
                }
            } current: {
                // Every option has an icon (menus › "icons for all or none"). Folded iPhone
                // Duo shows the icon alone and names the instrument in the title instead
                // (owner, issue #360); VoiceOver still reads "Instrument, <name>".
                if SongPathsSheet.showsInstrumentName(pose: deviceLayout.pose) {
                    namedInstrumentLabel
                } else {
                    InstrumentIcon(instrument, keyboard: usesKeyboardIcon(instrument), size: iconOnlySide)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("fst.paths.instrument")
            selectorMenu("Difficulty", selection: $difficulty, value: difficulty.label) {
                ForEach(PathDifficulty.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } current: {
                Text(difficulty.label)
            }
            .accessibilityIdentifier("fst.paths.difficulty")
            selectorMenu("View", selection: $display, value: display.label) {
                ForEach(PathDisplayMode.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } current: {
                Text(display.label)
            }
            .accessibilityIdentifier("fst.paths.display")
        }
        .frame(maxWidth: .infinity)
    }

    /// The instrument selector's icon and name (every pose but folded iPhone Duo). The name
    /// keeps scaling with Dynamic Type, and long names such as "Pro Drums + Cymbals" wrap
    /// to a second line.
    private var namedInstrumentLabel: some View {
        HStack(spacing: 6) {
            InstrumentIcon(
                instrument, keyboard: usesKeyboardIcon(instrument), size: InstrumentIcon.menuIconSide
            )
            // Wrap only between words: the hidden longest word sets the name's minimum
            // width, so a narrow selector never splits "Lead" as "Lea/d".
            ZStack(alignment: .leading) {
                Text(SongPathsSheet.longestWord(in: instrument.label))
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                Text(instrument.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    /// Whether this chart shows the keys artwork (Lead/Pro Lead on a keyboard song).
    ///
    /// - Parameter choice: Path instrument.
    /// - Returns: True for Lead or Pro Lead when the song uses the keyboard icon.
    private func usesKeyboardIcon(_ choice: Instrument) -> Bool {
        songUsesKeyboardIcon && (choice == .lead || choice == .proLead)
    }

    /// A native pop-up menu of mutually exclusive options on a compact material capsule.
    ///
    /// iOS/iPadOS: a `Menu` holding an inline `Picker` (the system menu with a checkmark
    /// on the current option) whose label shows the current value; the 44 pt frame sits
    /// inside the label because a frame outside a `Menu` doesn't grow its tap area
    /// (accessibility › iOS, iPadOS 44×44 pt). macOS: the system pop-up button.
    ///
    /// - Parameters:
    ///   - title: Control name VoiceOver reads before the value.
    ///   - selection: The chosen option.
    ///   - value: Current option's name, read as the accessibility value.
    ///   - options: Tagged option rows.
    ///   - current: The collapsed control's view of the current option (iOS/iPadOS).
    /// - Returns: The menu control.
    @ViewBuilder
    private func selectorMenu<Value: Hashable, Options: View, Current: View>(
        _ title: String, selection: Binding<Value>, value: String,
        @ViewBuilder options: () -> Options, @ViewBuilder current: () -> Current
    ) -> some View {
        #if os(macOS)
        Picker(title, selection: selection, content: options)
            .pickerStyle(.menu)
            .tint(FestivalText.primary)
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .festivalCardCapsule()
        #else
        Menu {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                current()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.body)
            .lineLimit(1)
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
            .festivalCardCapsule()
        }
        // Keep options in source order when the menu opens upward from the bottom row.
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        #endif
    }
}
