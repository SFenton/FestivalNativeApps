import Foundation

// MARK: - InstrumentSelection

/// The web's `InstrumentSelector` behaviour (`components/common/InstrumentSelector.tsx`)
/// as pure, testable rules, independent of any drawing.
///
/// The selector is a row of instrument circles. Tapping one selects it; tapping the
/// selected one deselects it unless the selector is ``required``. Hidden instruments are
/// left out entirely; disabled ones are drawn but cannot be chosen (and are skipped when
/// cycling); muted ones are drawn greyed as a conflict yet stay selectable. When the row
/// is too narrow for every button it switches to a compact mode: previous/next arrows
/// around one centre button. With ``deferSelection`` and nothing selected, the arrows
/// move a local preview and tapping the centre commits it.
public struct InstrumentSelection: Equatable, Sendable {
    /// How one button is drawn.
    public enum ButtonState: Equatable, Sendable {
        /// Unselected and choosable.
        case normal
        /// The current selection.
        case selected
        /// Drawn greyed as a conflict, still choosable (web `mutedInstruments`).
        case muted
        /// Drawn faint and not choosable (web `disabledInstruments`).
        case disabled
    }

    /// Arrow direction in compact mode.
    public enum Direction: Int, Sendable {
        case previous = -1
        case next = 1
    }

    /// What a compact arrow press does.
    public enum CycleResult: Equatable, Sendable {
        /// Nothing to do (no selectable instrument).
        case none
        /// Select this instrument (web `onSelect`).
        case select(Instrument)
        /// Move the local preview to this index of ``available`` (``deferSelection``).
        case preview(Int)
    }

    /// Source list in display order.
    public var instruments: [Instrument]
    /// Left out of the row without changing the source list (web `hiddenInstruments`).
    public var hidden: Set<Instrument>
    /// Drawn but never selectable (web `disabledInstruments`).
    public var disabled: Set<Instrument>
    /// Drawn as conflicting but selectable (web `mutedInstruments`).
    public var muted: Set<Instrument>
    /// Tapping the selected instrument keeps it selected (web `required`).
    public var required: Bool
    /// Compact arrows move a local preview while nothing is selected (web `deferSelection`).
    public var deferSelection: Bool

    /// Describe a selector.
    ///
    /// - Parameters:
    ///   - instruments: Source list in display order.
    ///   - hidden: Instruments to leave out.
    ///   - disabled: Instruments drawn but not selectable.
    ///   - muted: Instruments drawn as conflicting.
    ///   - required: Whether a selection can be cleared by tapping it again.
    ///   - deferSelection: Whether compact arrows preview before committing.
    public init(
        instruments: [Instrument], hidden: Set<Instrument> = [], disabled: Set<Instrument> = [],
        muted: Set<Instrument> = [], required: Bool = false, deferSelection: Bool = false
    ) {
        self.instruments = instruments
        self.hidden = hidden
        self.disabled = disabled
        self.muted = muted
        self.required = required
        self.deferSelection = deferSelection
    }

    // MARK: Row contents

    /// Instruments actually drawn, in source order.
    public var available: [Instrument] { instruments.filter { !hidden.contains($0) } }

    /// The selection as drawn: nil when the bound value is hidden or not in the list.
    ///
    /// - Parameter selected: The bound selection.
    /// - Returns: `selected` when it is drawn, else nil.
    public func effectiveSelection(_ selected: Instrument?) -> Instrument? {
        guard let selected, available.contains(selected) else { return nil }
        return selected
    }

    /// How a button is drawn: selection wins, then disabled, then muted.
    ///
    /// - Parameters:
    ///   - instrument: The button's instrument.
    ///   - selected: The bound selection.
    /// - Returns: Its drawing state.
    public func state(of instrument: Instrument, selected: Instrument?) -> ButtonState {
        if effectiveSelection(selected) == instrument { return .selected }
        if disabled.contains(instrument) { return .disabled }
        if muted.contains(instrument) { return .muted }
        return .normal
    }

    // MARK: Full row

    /// The new selection after tapping a button in the full row (web
    /// `InstrumentSelectorButton`): the selected one clears unless ``required``.
    ///
    /// - Parameters:
    ///   - instrument: Tapped button.
    ///   - selected: The bound selection.
    /// - Returns: The selection to store, or nil for no change on a disabled button.
    public func pressing(_ instrument: Instrument, selected: Instrument?) -> Instrument?? {
        guard !disabled.contains(instrument), available.contains(instrument) else { return nil }
        let isSelected = effectiveSelection(selected) == instrument
        return .some(isSelected && !required ? nil : instrument)
    }

    // MARK: Compact mode

    /// Whether the full row does not fit (web auto-compact: width below
    /// `count × button + (count − 1) × gap`).
    ///
    /// - Parameters:
    ///   - width: Row width; 0 or less (not measured yet) keeps the full row.
    ///   - buttonWidth: One button's width.
    ///   - gap: Space between buttons.
    /// - Returns: True when the row should switch to arrows.
    public func needsCompact(width: Double, buttonWidth: Double, gap: Double) -> Bool {
        let count = available.count
        guard width > 0, count > 0 else { return false }
        let needed = Double(count) * buttonWidth + Double(count - 1) * gap
        return width < needed
    }

    /// The instrument on the compact centre button: the selection, else the preview.
    ///
    /// - Parameters:
    ///   - selected: The bound selection.
    ///   - previewIndex: Local preview index into ``available``.
    /// - Returns: The centre instrument, or nil for an empty row.
    public func compactCentre(selected: Instrument?, previewIndex: Int) -> Instrument? {
        if let current = effectiveSelection(selected) { return current }
        let items = available
        guard !items.isEmpty else { return nil }
        return items.indices.contains(previewIndex) ? items[previewIndex] : items[0]
    }

    /// The new selection after tapping the compact centre button (web
    /// `CompactPreviewButton`): with a selection, clear it unless ``required``; otherwise
    /// commit the previewed instrument.
    ///
    /// - Parameters:
    ///   - selected: The bound selection.
    ///   - previewIndex: Local preview index.
    /// - Returns: The selection to store, or nil for no change (disabled centre).
    public func pressingCentre(selected: Instrument?, previewIndex: Int) -> Instrument?? {
        if let current = effectiveSelection(selected) {
            return .some(required ? current : nil)
        }
        guard let centre = compactCentre(selected: nil, previewIndex: previewIndex),
              !disabled.contains(centre) else { return nil }
        return .some(centre)
    }

    /// What a compact arrow does (web `cycle`): move the selection to the next
    /// selectable instrument, wrapping and skipping disabled ones; with nothing selected,
    /// select the first (or last) selectable one, or with ``deferSelection`` move the
    /// preview instead.
    ///
    /// - Parameters:
    ///   - direction: Arrow pressed.
    ///   - selected: The bound selection.
    ///   - previewIndex: Local preview index.
    /// - Returns: The action to take.
    public func cycle(_ direction: Direction, selected: Instrument?, previewIndex: Int) -> CycleResult {
        let items = available
        guard !items.isEmpty else { return .none }
        let step = direction.rawValue
        guard let current = effectiveSelection(selected), let index = items.firstIndex(of: current) else {
            if deferSelection {
                return .preview((previewIndex + step + items.count) % items.count)
            }
            let edge = direction == .next ? -1 : 0
            return nextSelectable(from: edge, step: step, in: items).map { .select(items[$0]) } ?? .none
        }
        return nextSelectable(from: index, step: step, in: items).map { .select(items[$0]) } ?? .none
    }

    /// The web's `findNextSelectableIndex`: walk `step` at a time (wrapping) until a
    /// non-disabled instrument is found.
    ///
    /// - Parameters:
    ///   - start: Starting index (may be −1 for "before the first").
    ///   - step: +1 or −1.
    ///   - items: Drawn instruments.
    /// - Returns: The index found, or nil when every instrument is disabled.
    private func nextSelectable(from start: Int, step: Int, in items: [Instrument]) -> Int? {
        for offset in 1 ... items.count {
            let index = ((start + offset * step) % items.count + items.count) % items.count
            if !disabled.contains(items[index]) { return index }
        }
        return nil
    }
}
