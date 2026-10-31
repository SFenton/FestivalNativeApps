#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Accordion

/// Content that opens and closes in the accordion choreography (``FestivalAccordionContent``
/// and ``FestivalAccordionState``): opening resizes first, then fades the content in;
/// closing fades the content out, then resizes. Reduce Motion (system or in-app) drops the
/// resize animation and settles in 20 ms; the fades always run.
///
/// ``follow(_:)`` moves to a value or nil (closed); the view calls ``onLayoutChange``
/// whenever its height changes so a self-sizing cell can re-measure.
@MainActor
final class UKAccordionView<Value: Equatable>: UIView {
    private let makeContent: (Value) -> UIView
    private let holder = UIView()
    private var content: UIView?
    private var heightConstraint: NSLayoutConstraint!
    private var sequence: Task<Void, Never>?
    private(set) var state: FestivalAccordionState<Value>

    /// Called after a step changed the view's height.
    var onLayoutChange: (() -> Void)?

    /// Creates an accordion.
    ///
    /// - Parameters:
    ///   - value: The value shown at first, nil for closed.
    ///   - content: Builds the content for a value.
    init(_ value: Value? = nil, content: @escaping (Value) -> UIView) {
        makeContent = content
        state = FestivalAccordionState(value)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        holder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(holder)
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            holder.leadingAnchor.constraint(equalTo: leadingAnchor), holder.trailingAnchor.constraint(equalTo: trailingAnchor),
            holder.topAnchor.constraint(equalTo: topAnchor),
            holder.bottomAnchor.constraint(equalTo: bottomAnchor).withPriority(.defaultHigh),
        ])
        render(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { sequence?.cancel() }

    /// Moves to a value (or closes with nil), running the choreography.
    ///
    /// - Parameter value: The value to show, nil to close.
    func follow(_ value: Value?) {
        sequence?.cancel()
        state.request(value)
        let reduceMotion = UKAccessibility.reduceMotion
        let steps = AccordionChoreography.plan(expanded: value != nil, from: state.phase, reduceMotion: reduceMotion)
        var remaining = steps[...]
        while let step = remaining.first, step.delay == 0 {
            run(step.change, reduceMotion: reduceMotion)
            remaining = remaining.dropFirst()
        }
        guard !remaining.isEmpty else { return }
        let delayed = Array(remaining)
        sequence = Task { @MainActor [weak self] in
            for step in delayed {
                try? await Task.sleep(for: .seconds(step.delay))
                guard !Task.isCancelled, let self else { return }
                self.run(step.change, reduceMotion: reduceMotion)
            }
        }
    }

    private func run(_ change: AccordionChoreography.Change, reduceMotion: Bool) {
        let before = state.shown
        state.apply(change)
        let resizes = change == .open || change == .close
        let duration: TimeInterval = resizes
            ? (reduceMotion ? 0 : AccordionChoreography.resizeDuration) : AccordionChoreography.fadeDuration
        if state.shown != before || content == nil { rebuildContent() }
        let apply = { [self] in
            content?.alpha = state.showsContent ? 1 : 0
            heightConstraint.isActive = state.shown == nil
            invalidateIntrinsicContentSize()
            (window ?? self).layoutIfNeeded()
        }
        if duration > 0 && window != nil {
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
        content?.isUserInteractionEnabled = state.showsContent
        content?.accessibilityElementsHidden = !state.showsContent
        onLayoutChange?()
    }

    private func render(animated: Bool) {
        rebuildContent()
        content?.alpha = state.showsContent ? 1 : 0
        content?.accessibilityElementsHidden = !state.showsContent
        heightConstraint.isActive = state.shown == nil
    }

    private func rebuildContent() {
        content?.removeFromSuperview()
        content = nil
        guard let shown = state.shown else { return }
        let view = makeContent(shown)
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: holder.leadingAnchor), view.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            view.topAnchor.constraint(equalTo: holder.topAnchor), view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        content = view
    }
}

extension NSLayoutConstraint {
    /// This constraint with a priority, for chaining.
    ///
    /// - Parameter priority: The priority.
    /// - Returns: The same constraint.
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Disclosure group

/// A header row that expands a body in the accordion choreography
/// (``FestivalDisclosureGroup``): a chevron button, "Expanded" / "Collapsed" as its
/// accessibility value, the body opened and closed by ``UKAccordionView``.
final class UKDisclosureGroupView: UIView {
    private let header = UIControl()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let accordion: UKAccordionView<Bool>
    private let announcesState: Bool

    /// Whether the body is open (or opening).
    private(set) var isExpanded: Bool

    /// Called when the user toggles the group.
    var onToggle: ((Bool) -> Void)?

    /// Creates a disclosure group.
    ///
    /// - Parameters:
    ///   - label: The always-visible header content.
    ///   - body: The expanding content.
    ///   - initiallyExpanded: Whether the body starts open.
    ///   - announcesState: Speak "Expanded" / "Collapsed" as the header's value.
    ///   - identifier: Accessibility identifier of the header.
    init(label: UIView, body: UIView, initiallyExpanded: Bool = false, announcesState: Bool = true, identifier: String? = nil) {
        isExpanded = initiallyExpanded
        self.announcesState = announcesState
        accordion = UKAccordionView<Bool>(initiallyExpanded ? true : nil) { _ in body }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        chevron.tintColor = BrandUIColors.textMuted
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        header.addSubview(chevron)
        header.isAccessibilityElement = true
        header.accessibilityTraits = .button
        header.accessibilityIdentifier = identifier
        header.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [header, accordion])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            label.topAnchor.constraint(equalTo: header.topAnchor), label.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        header.accessibilityLabel = (label as? UILabel)?.text ?? label.accessibilityLabel
        updateAccessibility()
        chevron.transform = initiallyExpanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Toggles the group as a tap does.
    func toggle() {
        setExpanded(!isExpanded)
        onToggle?(isExpanded)
    }

    /// Opens or closes the body in the accordion choreography.
    ///
    /// - Parameter expanded: The target state.
    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        accordion.follow(expanded ? true : nil)
        let transform = expanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        if UKAccessibility.reduceMotion {
            chevron.transform = transform
        } else {
            UIView.animate(withDuration: AccordionChoreography.resizeDuration, delay: 0, options: .curveEaseInOut) {
                self.chevron.transform = transform
            }
        }
        updateAccessibility()
    }

    private func updateAccessibility() {
        header.accessibilityValue = announcesState ? FestivalAccordionAccessibility.value(isExpanded: isExpanded) : nil
    }
}
#endif
