import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - InstrumentSelector

/// The web's reusable `InstrumentSelector` (`components/common/InstrumentSelector.tsx`): a
/// centred row of instrument circles with an optional panel that expands below it while
/// something is selected.
///
/// Every web mode is supported; the rules live in ``InstrumentSelection`` (FestivalCore):
///
/// - **Optional or required:** tapping the selected circle clears it unless `required`.
/// - **Hidden / disabled / muted** instruments: left out; drawn faint and inert; drawn
///   greyed as a conflict but still selectable.
/// - **Compact mode:** when the row cannot fit every 64 pt circle (web
///   `Layout.demoInstrumentBtn` + `Gap.md`), previous/next arrows flank one centre circle.
///   `compact` forces it on or off; nil measures the row like the web's `ResizeObserver`.
/// - **Deferred selection:** in compact mode with nothing selected, the arrows move a
///   local preview and tapping the centre commits it.
/// - **Two looks:** `.filter` (web `filterStyles`: a green disc scales in behind the
///   selected icon) and `.graph` (web `GraphCard` `selectorStyles`: unselected icons dim,
///   the selected one sits on a solid green disc).
///
/// Accessibility: each circle is a button labelled with the instrument, with the
/// Selected trait when chosen; disabled circles are not actionable; the compact arrows are
/// labelled "Previous Instrument" / "Next Instrument" (or the caller's labels).
struct InstrumentSelector<Panel: View>: View {
    /// Web looks.
    enum Look {
        /// `FilterModal` / `SuggestionsFilterModal` / Paths: green disc scales in.
        case filter
        /// `GraphCard` charts: dimmed icons, solid green disc behind the selection.
        case graph
    }

    /// Web `Layout.demoInstrumentBtn`.
    static var buttonSize: CGFloat { 64 }
    /// Web `Size.iconInstrument` (`InstrumentSize.md`).
    static var iconSize: CGFloat { 48 }
    /// Web `Gap.md` between circles.
    static var gap: CGFloat { 12 }

    private let selection: InstrumentSelection
    @Binding private var selected: Instrument?
    private let compact: Bool?
    private let look: Look
    private let keyboardIcon: Bool
    private let labels: (previous: String, next: String)
    private let identifier: String
    private let panel: () -> Panel

    @State private var measuredWidth: CGFloat = 0
    @State private var previewIndex = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    /// Create a selector whose panel expands while something is selected.
    ///
    /// - Parameters:
    ///   - instruments: Source list in display order.
    ///   - selected: The selection (nil for none).
    ///   - hidden: Instruments to leave out.
    ///   - disabled: Instruments drawn but not selectable.
    ///   - muted: Instruments drawn as conflicting.
    ///   - required: Tapping the selection keeps it.
    ///   - compact: Force compact (true) or full (false) mode; nil measures the row.
    ///   - deferSelection: Compact arrows preview before committing.
    ///   - look: Web style variant.
    ///   - keyboardIcon: Use the keys icon for Lead/Pro Lead (song `sig == "Keyboard"`).
    ///   - labels: Spoken compact arrow labels.
    ///   - identifier: Accessibility identifier prefix (`<prefix>.<Instrument>`,
    ///     `<prefix>.previous`, `<prefix>.next`, `<prefix>.centre`).
    ///   - panel: Content that expands below the row while something is selected.
    init(
        instruments: [Instrument], selected: Binding<Instrument?>,
        hidden: Set<Instrument> = [], disabled: Set<Instrument> = [], muted: Set<Instrument> = [],
        required: Bool = false, compact: Bool? = nil, deferSelection: Bool = false,
        look: Look = .filter, keyboardIcon: Bool = false,
        labels: (previous: String, next: String) = ("Previous Instrument", "Next Instrument"),
        identifier: String, @ViewBuilder panel: @escaping () -> Panel
    ) {
        selection = InstrumentSelection(
            instruments: instruments, hidden: hidden, disabled: disabled, muted: muted,
            required: required, deferSelection: deferSelection
        )
        _selected = selected
        self.compact = compact
        self.look = look
        self.keyboardIcon = keyboardIcon
        self.labels = labels
        self.identifier = identifier
        self.panel = panel
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    private var isCompact: Bool {
        guard !selection.available.isEmpty else { return false }
        return compact ?? selection.needsCompact(
            width: Double(measuredWidth), buttonWidth: Double(Self.buttonSize), gap: Double(Self.gap)
        )
    }

    private var effective: Instrument? { selection.effectiveSelection(selected) }

    var body: some View {
        VStack(spacing: 12) {
            // The row is drawn over a full-width, fixed-height slot so a row wider than
            // the screen can never widen the page; the slot's width decides compact mode.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonSize)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { measuredWidth = $0 }
                .overlay {
                    if measuredWidth > 0 || compact != nil {
                        if isCompact {
                            compactRow
                        } else {
                            fullRow
                        }
                    }
                }
            if effective != nil, Panel.self != EmptyView.self {
                panel()
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: effective)
        .onChange(of: selection.available) { _, _ in previewIndex = 0 }
    }

    // MARK: Full row

    /// Every circle in one centred row (web `flexWrap: wrap`, which the auto-compact
    /// rule keeps to a single line).
    private var fullRow: some View {
        HStack(spacing: Self.gap) {
            ForEach(selection.available) { instrument in
                circle(instrument, state: selection.state(of: instrument, selected: selected)) {
                    if let next = selection.pressing(instrument, selected: selected) { selected = next }
                }
                .accessibilityIdentifier("\(identifier).\(instrument.rawValue)")
            }
        }
    }

    // MARK: Compact row

    private var compactRow: some View {
        let centre = selection.compactCentre(selected: selected, previewIndex: previewIndex)
        return HStack(spacing: Self.gap) {
            arrow(.previous)
            if let centre {
                circle(centre, state: selection.state(of: centre, selected: selected)) {
                    if let next = selection.pressingCentre(selected: selected, previewIndex: previewIndex) {
                        selected = next
                    }
                }
                .accessibilityIdentifier("\(identifier).centre")
            }
            arrow(.next)
        }
    }

    /// A 44 pt outlined arrow circle (web `CompactArrowButton` / `circleBtn`).
    ///
    /// - Parameter direction: Which way it cycles.
    /// - Returns: The arrow button.
    private func arrow(_ direction: InstrumentSelection.Direction) -> some View {
        Button {
            switch selection.cycle(direction, selected: selected, previewIndex: previewIndex) {
            case .none: break
            case let .select(instrument): selected = instrument
            case let .preview(index): previewIndex = index
            }
        } label: {
            Image(systemName: direction == .previous ? "chevron.backward" : "chevron.forward")
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(BrandTokens.glassBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .accessibilityLabel(direction == .previous ? labels.previous : labels.next)
        .accessibilityIdentifier("\(identifier).\(direction == .previous ? "previous" : "next")")
    }

    // MARK: Circle

    /// One instrument circle in the chosen look.
    ///
    /// - Parameters:
    ///   - instrument: Its instrument.
    ///   - state: How it is drawn.
    ///   - action: Tap handler.
    /// - Returns: The button.
    private func circle(
        _ instrument: Instrument, state: InstrumentSelection.ButtonState, action: @escaping () -> Void
    ) -> some View {
        let isSelected = state == .selected
        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(BrandTokens.statusGreen)
                    .scaleEffect(look == .filter ? (isSelected ? 1 : 0.001) : 1)
                    .opacity(look == .graph && !isSelected ? 0 : 1)
                InstrumentIcon(
                    instrument, keyboard: keyboardIcon && (instrument == .lead || instrument == .proLead),
                    size: Self.iconSize
                )
                .accessibilityHidden(true)
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .opacity(opacity(for: state))
            .saturation(state == .muted || state == .disabled ? 0 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(state == .disabled)
        .accessibilityLabel(instrument.label)
        .accessibilityHint(state == .muted ? "Conflicts with the current choice" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Web opacities: muted 0.42, disabled 0.28, `.graph` unselected `Opacity.disabled` (0.5).
    ///
    /// - Parameter state: Button state.
    /// - Returns: The circle's opacity.
    private func opacity(for state: InstrumentSelection.ButtonState) -> Double {
        switch state {
        case .selected: 1
        case .disabled: 0.28
        case .muted: 0.42
        case .normal: look == .graph ? 0.5 : 1
        }
    }
}

extension InstrumentSelector where Panel == EmptyView {
    /// Create a selector with no expanding panel.
    ///
    /// - Parameters:
    ///   - instruments: Source list in display order.
    ///   - selected: The selection (nil for none).
    ///   - hidden: Instruments to leave out.
    ///   - disabled: Instruments drawn but not selectable.
    ///   - muted: Instruments drawn as conflicting.
    ///   - required: Tapping the selection keeps it.
    ///   - compact: Force compact (true) or full (false) mode; nil measures the row.
    ///   - deferSelection: Compact arrows preview before committing.
    ///   - look: Web style variant.
    ///   - keyboardIcon: Use the keys icon for Lead/Pro Lead.
    ///   - labels: Spoken compact arrow labels.
    ///   - identifier: Accessibility identifier prefix.
    init(
        instruments: [Instrument], selected: Binding<Instrument?>,
        hidden: Set<Instrument> = [], disabled: Set<Instrument> = [], muted: Set<Instrument> = [],
        required: Bool = false, compact: Bool? = nil, deferSelection: Bool = false,
        look: Look = .filter, keyboardIcon: Bool = false,
        labels: (previous: String, next: String) = ("Previous Instrument", "Next Instrument"),
        identifier: String
    ) {
        self.init(
            instruments: instruments, selected: selected, hidden: hidden, disabled: disabled,
            muted: muted, required: required, compact: compact, deferSelection: deferSelection,
            look: look, keyboardIcon: keyboardIcon, labels: labels, identifier: identifier
        ) { EmptyView() }
    }

    /// A required selector over a non-optional selection (web `required`, e.g. charts).
    ///
    /// - Parameters:
    ///   - instruments: Source list in display order.
    ///   - selection: The always-present selection.
    ///   - hidden: Instruments to leave out.
    ///   - compact: Force compact (true) or full (false) mode; nil measures the row.
    ///   - look: Web style variant.
    ///   - keyboardIcon: Use the keys icon for Lead/Pro Lead.
    ///   - identifier: Accessibility identifier prefix.
    init(
        instruments: [Instrument], required selection: Binding<Instrument>,
        hidden: Set<Instrument> = [], compact: Bool? = nil, look: Look = .filter,
        keyboardIcon: Bool = false, identifier: String
    ) {
        self.init(
            instruments: instruments,
            selected: Binding(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } }),
            hidden: hidden, required: true, compact: compact, look: look,
            keyboardIcon: keyboardIcon, identifier: identifier
        )
    }
}
