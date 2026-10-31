#if os(iOS)
import CoreImage
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Circle button

/// One instrument button (64 x 64 pt): a green fill that scales in when selected and the
/// 48 pt icon, dimmed by state and desaturated when muted or disabled. Pressing dims it
/// to 78% (``HighContrastPagerStyle``).
final class UKInstrumentCircleButton: UIControl {
    private let fill = UIView()
    private let icon = UIImageView()
    private var baseAlpha: CGFloat = 1
    private static var greyCache: [String: UIImage] = [:]

    /// The instrument this button picks.
    let instrument: Instrument

    /// Creates a button.
    ///
    /// - Parameters:
    ///   - instrument: The instrument.
    ///   - keyboard: The keys variant of Lead and Pro Lead.
    init(instrument: Instrument, keyboard: Bool) {
        self.instrument = instrument
        self.keyboard = keyboard
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let side = InstrumentSelectorMetrics.buttonSize
        fill.backgroundColor = BrandUIColors.statusGreen
        fill.isUserInteractionEnabled = false
        fill.layer.cornerRadius = side / 2
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        for view in [fill, icon] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor), fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor), fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: InstrumentSelectorMetrics.iconSize),
            icon.heightAnchor.constraint(equalToConstant: InstrumentSelectorMetrics.iconSize),
        ])
        isAccessibilityElement = true
        accessibilityLabel = instrument.label
        accessibilityTraits = .button
        layer.cornerRadius = side / 2
    }

    private let keyboard: Bool

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = baseAlpha * (isHighlighted ? 0.78 : 1) }
    }

    /// Applies a state.
    ///
    /// - Parameters:
    ///   - state: The button's state.
    ///   - look: Filter (selected = green fill) or graph (selected = shown, others dim).
    func apply(_ state: InstrumentSelection.ButtonState, look: UKInstrumentSelectorView.Look) {
        let selected = state == .selected
        switch look {
        case .filter:
            fill.transform = selected ? .identity : CGAffineTransform(scaleX: 0.001, y: 0.001)
            fill.alpha = 1
        case .graph:
            fill.transform = .identity
            fill.alpha = selected ? 1 : 0
        }
        baseAlpha = CGFloat(InstrumentSelectorMetrics.opacity(for: state, graphLook: look == .graph))
        alpha = baseAlpha * (isHighlighted ? 0.78 : 1)
        let grey = state == .muted || state == .disabled
        icon.image = grey ? Self.greyscale(instrument, keyboard: keyboard) : UKInstrumentIconView.image(for: instrument, keyboard: keyboard)
        isEnabled = state != .disabled
        accessibilityHint = state == .muted ? "Conflicts with the current choice" : nil
        var traits: UIAccessibilityTraits = .button
        if selected { traits.insert(.selected) }
        if state == .disabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
    }

    private static func greyscale(_ instrument: Instrument, keyboard: Bool) -> UIImage? {
        let name = InstrumentIcon.assetName(for: instrument, keyboard: keyboard)
        if let cached = greyCache[name] { return cached }
        guard let source = UKInstrumentIconView.image(for: instrument, keyboard: keyboard), let input = CIImage(image: source),
              let filter = CIFilter(name: "CIColorControls") else { return UKInstrumentIconView.image(for: instrument, keyboard: keyboard) }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return source }
        let image = UIImage(cgImage: cg, scale: source.scale, orientation: .up)
        greyCache[name] = image
        return image
    }
}

// MARK: - Selector

/// The instrument filter / graph selector (``InstrumentSelector``): a row of 64 pt
/// instrument circles, or, when the row does not fit, previous / next arrows around a
/// centre circle. Selection rules come from ``InstrumentSelection``; an optional panel
/// opens below in the accordion choreography.
///
/// Identifiers: `<identifier>.<instrument raw value>`, `<identifier>.centre`,
/// `<identifier>.previous` and `<identifier>.next`.
final class UKInstrumentSelectorView: UIView {
    /// Filter or graph appearance (``InstrumentSelector/Look``).
    enum Look {
        /// Green fill on the chosen instrument.
        case filter
        /// Chosen instrument at full opacity on a shown green fill, others dimmed.
        case graph
    }

    private let identifier: String
    private let look: Look
    private let keyboardIcon: Bool
    private let labels: (previous: String, next: String)
    private let compactOverride: Bool?
    private let rowHolder = UIView()
    private var row: UIStackView?
    private var rowIsCompact: Bool?
    private var previewIndex = 0
    private var buttons: [UKInstrumentCircleButton] = []
    private var accordion: UKAccordionView<Instrument>?
    private var lastWidth: CGFloat = 0

    /// The selection rules; set to change the available instruments or states.
    var selection: InstrumentSelection { didSet { previewIndex = 0; rebuildRow(); accordion?.follow(effective) } }
    /// The chosen instrument.
    var selected: Instrument? { didSet { updateStates(animated: true); accordion?.follow(effective) } }
    /// Called with the new choice when the user presses a button or arrow.
    var onSelect: ((Instrument?) -> Void)?

    /// Creates a selector.
    ///
    /// - Parameters:
    ///   - instruments: Instruments in order.
    ///   - selected: The initial choice.
    ///   - hidden: Instruments Settings hides.
    ///   - disabled: Instruments that cannot be chosen.
    ///   - muted: Instruments that conflict with the choice.
    ///   - required: Whether one must stay chosen.
    ///   - compact: Force the arrow layout on or off; nil measures the width.
    ///   - deferSelection: Whether pressing only previews (``InstrumentSelection``).
    ///   - look: Filter or graph appearance.
    ///   - keyboardIcon: Draw the keys variant of Lead and Pro Lead.
    ///   - labels: Spoken names of the arrows.
    ///   - identifier: Accessibility identifier prefix.
    ///   - panel: Builds the accordion panel for the chosen instrument, if any.
    init(
        instruments: [Instrument], selected: Instrument?, hidden: Set<Instrument> = [], disabled: Set<Instrument> = [],
        muted: Set<Instrument> = [], required: Bool = false, compact: Bool? = nil, deferSelection: Bool = false,
        look: Look = .filter, keyboardIcon: Bool = false,
        labels: (previous: String, next: String) = ("Previous Instrument", "Next Instrument"),
        identifier: String, panel: ((Instrument) -> UIView)? = nil
    ) {
        selection = InstrumentSelection(
            instruments: instruments, hidden: hidden, disabled: disabled, muted: muted,
            required: required, deferSelection: deferSelection
        )
        self.selected = selected
        self.look = look
        self.keyboardIcon = keyboardIcon
        self.labels = labels
        self.identifier = identifier
        self.compactOverride = compact
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rowHolder.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [rowHolder])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            rowHolder.heightAnchor.constraint(equalToConstant: InstrumentSelectorMetrics.buttonSize),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if let panel {
            let accordion = UKAccordionView<Instrument>(selection.effectiveSelection(selected), content: panel)
            stack.addArrangedSubview(accordion)
            self.accordion = accordion
        }
        if compact != nil { rebuildRow() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var effective: Instrument? { selection.effectiveSelection(selected) }

    private var isCompact: Bool {
        guard !selection.available.isEmpty else { return false }
        return compactOverride ?? selection.needsCompact(
            width: Double(lastWidth), buttonWidth: Double(InstrumentSelectorMetrics.buttonSize),
            gap: Double(InstrumentSelectorMetrics.gap)
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = rowHolder.bounds.width.rounded()
        if width != lastWidth {
            lastWidth = width
            if rowIsCompact != isCompact || row == nil { rebuildRow() }
        }
    }

    // MARK: Rows

    private func rebuildRow() {
        row?.removeFromSuperview()
        buttons = []
        guard lastWidth > 0 || compactOverride != nil else { return }
        let compact = isCompact
        rowIsCompact = compact
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = InstrumentSelectorMetrics.gap
        stack.alignment = .center
        if compact {
            stack.addArrangedSubview(arrow(.previous))
            if let centre = selection.compactCentre(selected: selected, previewIndex: previewIndex) {
                let button = circle(centre) { [weak self] in
                    guard let self, let next = self.selection.pressingCentre(selected: self.selected, previewIndex: self.previewIndex) else { return }
                    self.choose(next)
                }
                button.accessibilityIdentifier = "\(identifier).centre"
                stack.addArrangedSubview(button)
            }
            stack.addArrangedSubview(arrow(.next))
        } else {
            for instrument in selection.available {
                let button = circle(instrument) { [weak self] in
                    guard let self, let next = self.selection.pressing(instrument, selected: self.selected) else { return }
                    self.choose(next)
                }
                button.accessibilityIdentifier = "\(identifier).\(instrument.rawValue)"
                stack.addArrangedSubview(button)
            }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        rowHolder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: rowHolder.centerXAnchor), stack.centerYAnchor.constraint(equalTo: rowHolder.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: rowHolder.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: rowHolder.trailingAnchor),
        ])
        row = stack
        updateStates(animated: false)
    }

    private func choose(_ next: Instrument?) {
        selected = next
        onSelect?(next)
    }

    private func circle(_ instrument: Instrument, action: @escaping () -> Void) -> UKInstrumentCircleButton {
        let keyboard = keyboardIcon && (instrument == .lead || instrument == .proLead)
        let button = UKInstrumentCircleButton(instrument: instrument, keyboard: keyboard)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        buttons.append(button)
        return button
    }

    private func arrow(_ direction: InstrumentSelection.Direction) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImageView(image: UIImage(systemName: direction == .previous ? "chevron.backward" : "chevron.forward"))
        image.tintColor = BrandUIColors.textPrimary
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.isUserInteractionEnabled = false
        control.addSubview(image)
        control.layer.cornerRadius = 22
        control.layer.borderWidth = 1
        control.layer.borderColor = BrandUIColors.glassBorder.cgColor
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: 44), control.heightAnchor.constraint(equalToConstant: 44),
            image.centerXAnchor.constraint(equalTo: control.centerXAnchor), image.centerYAnchor.constraint(equalTo: control.centerYAnchor),
        ])
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = direction == .previous ? labels.previous : labels.next
        control.accessibilityIdentifier = "\(identifier).\(direction == .previous ? "previous" : "next")"
        control.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            switch self.selection.cycle(direction, selected: self.selected, previewIndex: self.previewIndex) {
            case .none: break
            case let .select(instrument): self.choose(instrument)
            case let .preview(index):
                self.previewIndex = index
                self.rebuildRow()
            }
        }, for: .touchUpInside)
        return control
    }

    private func updateStates(animated: Bool) {
        if rowIsCompact == true, row != nil {
            // The centre follows the choice: rebuild the row for the new centre.
            rebuildCompactCentre()
        }
        let apply = { [self] in
            for button in buttons {
                button.apply(selection.state(of: button.instrument, selected: selected), look: look)
            }
        }
        if animated && !UKAccessibility.reduceMotion {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    private func rebuildCompactCentre() {
        guard let stack = row, stack.arrangedSubviews.count == 3 || buttons.count == 1 else { return }
        let centre = selection.compactCentre(selected: selected, previewIndex: previewIndex)
        if buttons.first?.instrument != centre {
            rowIsCompact = nil
            rebuildRowKeepingState()
        }
    }

    private func rebuildRowKeepingState() {
        let saved = row
        row = nil
        saved?.removeFromSuperview()
        buttons = []
        rowIsCompact = isCompact
        rebuildRow()
    }
}
#endif
