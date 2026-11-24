#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Chart lessons

/// The inert Song Info accuracy chart and its optional cycling score detail. Both use the
/// guide's sample history rather than a player's selected account or a service read.
final class UKFirstRunSongChartPreview: UIView {
    private let plot: UKFirstRunAccuracyPlot
    private let detail = UIView()
    private let date = UKLabel(style: .subheadline, weight: .semibold, lines: 1)
    private let score = UKLabel(style: .subheadline, weight: .semibold, monospacedDigit: true, lines: 1)
    private let accuracy = UKLabel(style: .subheadline, lines: 1)
    private let gold = UKStarRatingView(stars: 1, gold: true, size: 16)
    private let values = UIStackView()
    private var index = 0
    private var active = false
    private var rotationTask: Task<Void, Never>?
    private var animator: UIViewPropertyAnimator?
    private var accessibilityObserver: UKAccessibilityObserver?
    private nonisolated(unsafe) var sceneObservers: [NSObjectProtocol] = []

    /// - Parameter slideID: The Song Info chart or selection lesson; other lessons return nil.
    init?(slideID: String) {
        let showsSelection: Bool
        switch slideID {
        case "songinfo-chart": showsSelection = false
        case "songinfo-bar-select": showsSelection = true
        default: return nil
        }
        plot = UKFirstRunAccuracyPlot(showsSelection: showsSelection)
        super.init(frame: .zero)
        clipsToBounds = true
        let card = UKCardView(cornerRadius: 16)
        let secondary = showsSelection ? makeDetail() : Self.makeLegend()
        let stack = UIStackView(arrangedSubviews: [plot, secondary])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 14 - plot.labelHeadroom),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -14),
        ])
        guard showsSelection else { return }
        updateSelection()
        accessibilityObserver = UKAccessibilityObserver { [weak self] in self?.refreshPlayback() }
        let center = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIScene else { return }
                let sceneID = ObjectIdentifier(scene)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.window?.windowScene,
                          ObjectIdentifier(scene) == sceneID else { return }
                    self.refreshPlayback(sceneActive: name == UIScene.didActivateNotification)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
        rotationTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshPlayback()
    }

    /// - Parameter active: Whether the chart is on the current slide.
    func setActive(_ active: Bool) {
        self.active = active
        refreshPlayback()
    }

    private static func makeLegend() -> UIView {
        let legend = UIStackView(arrangedSubviews: [
            legendItem("Accuracy", tone: BrandUIColors.accentBlue),
            legendItem("Full Combo", tone: BrandUIColors.gold),
        ])
        legend.spacing = 16
        let holder = UIView()
        legend.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(legend)
        NSLayoutConstraint.activate([
            legend.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            legend.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor),
            legend.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
            legend.topAnchor.constraint(equalTo: holder.topAnchor),
            legend.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    private static func legendItem(_ title: String, tone: UIColor) -> UIView {
        let swatch = UIView()
        swatch.backgroundColor = tone
        swatch.layer.cornerRadius = 2
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 10), swatch.heightAnchor.constraint(equalToConstant: 10),
        ])
        let row = UIStackView(arrangedSubviews: [
            swatch, UKLabel(title, style: .caption2, color: BrandUIColors.textMuted, lines: 1),
        ])
        row.alignment = .center
        row.spacing = 4
        return row
    }

    private func makeDetail() -> UIView {
        detail.backgroundColor = BrandUIColors.accentPurple.withAlphaComponent(0.18)
        detail.layer.cornerRadius = 10
        values.addArrangedSubview(score)
        values.addArrangedSubview(accuracy)
        values.alignment = .center
        values.spacing = 16
        let row = UIStackView(arrangedSubviews: [date, UIView(), values])
        row.alignment = .center
        row.spacing = 8
        date.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(row)
        NSLayoutConstraint.activate([
            detail.heightAnchor.constraint(equalToConstant: 44),
            row.centerYAnchor.constraint(equalTo: detail.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -14),
        ])
        return detail
    }

    // MARK: - Selection playback

    private func updateSelection() {
        let sample = FirstRunDemoPool.scoreHistory[index]
        plot.selectedIndex = index
        date.text = sample.label
        score.text = sample.score.formatted()
        accuracy.text = "\(Int(sample.accuracy))%"
        if sample.isFullCombo {
            if gold.superview == nil { values.addArrangedSubview(gold) }
        } else {
            gold.removeFromSuperview()
        }
    }

    private func refreshPlayback(sceneActive: Bool? = nil) {
        let foreground = sceneActive ?? (window?.windowScene?.activationState == .foregroundActive)
        let reduceMotion = UKAccessibility.reduceMotion
        let still = DebugAnimationOverride.stillBackground
        let runs = FirstRunDemoTickerPolicy.runs(
            active: active && foreground, enabled: plot.showsSelection, constrained: false,
            reduceMotion: reduceMotion, stillBackground: still
        )
        if runs, rotationTask == nil {
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: FirstRunDemoTiming.barSelectInterval) } catch { return }
                    guard let self else { return }
                    await self.advanceSelection()
                }
            }
        } else if !runs, plot.showsSelection {
            rotationTask?.cancel()
            rotationTask = nil
            if animator?.state == .active { animator?.stopAnimation(true) }
            animator = nil
            detail.alpha = 1
            if reduceMotion || still {
                index = 0
                updateSelection()
            }
        }
    }

    private func advanceSelection() async {
        fadeDetail(to: 0)
        do { try await Task.sleep(for: .seconds(FirstRunDemoTiming.barSelectFadeSeconds)) } catch { return }
        index = (index + 1) % FirstRunDemoPool.scoreHistory.count
        updateSelection()
        fadeDetail(to: 1)
    }

    private func fadeDetail(to opacity: CGFloat) {
        let curve = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.25, y: 0.1), controlPoint2: CGPoint(x: 0.25, y: 1)
        )
        let animation = UIViewPropertyAnimator(duration: FirstRunDemoTiming.barSelectFadeSeconds, timingParameters: curve)
        animation.addAnimations { [detail] in detail.alpha = opacity }
        animator = animation
        animation.startAnimation()
    }
}

// MARK: - Accuracy plot

/// Accuracy-only chart from the three illustrative categorical dates, with an optional
/// score annotation above each bar or a purple stroke around the selected bar.
private final class UKFirstRunAccuracyPlot: UKHistoryChartViewport {
    /// Allows text and the selection stroke above the top gridline to remain in the canvas.
    let labelHeadroom: CGFloat = 18
    let showsSelection: Bool
    var selectedIndex = 0 { didSet { setNeedsDisplay() } }

    /// - Parameter showsSelection: True for the 28 pt selectable-bar illustration.
    init(showsSelection: Bool) {
        self.showsSelection = showsSelection
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: (showsSelection ? 120 : 150) + labelHeadroom).isActive = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKFirstRunAccuracyPlot, _) in
            self.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let ticks = [0, 25, 50, 75, 100]
        let points = FirstRunDemoPool.scoreHistory
        let tickColor = UIColor.secondaryLabel
        let tickAttributes: [NSAttributedString.Key: Any] = [.font: axisFont, .foregroundColor: tickColor]
        let scoreAttributes: [NSAttributedString.Key: Any] = [
            .font: UKFont.font(.caption2, weight: .semibold), .foregroundColor: BrandUIColors.textPrimary,
        ]
        let leading = ceil(("100" as NSString).size(withAttributes: tickAttributes).width) + Self.axisLabelGap
        let dateBand = ceil(axisFont.lineHeight) + Self.axisLabelGap + 1
        let plot = CGRect(x: leading, y: labelHeadroom, width: max(0, bounds.width - leading),
                          height: max(0, bounds.height - labelHeadroom - dateBand))
        guard !plot.isEmpty else { return }
        let slot = plot.width / CGFloat(points.count)
        let barWidth = min(slot, showsSelection ? 28 : slot * 0.7)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.14).cgColor)
        context.setLineWidth(1 / traitCollection.displayScale)
        for tick in ticks {
            let y = plot.maxY - CGFloat(tick) / 100 * plot.height
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()
            let text = String(tick) as NSString
            let size = text.size(withAttributes: tickAttributes)
            text.draw(at: CGPoint(x: plot.minX - Self.axisLabelGap - size.width, y: y - size.height / 2),
                      withAttributes: tickAttributes)
        }
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [2, 2])
        for boundary in 0...points.count {
            let x = plot.minX + CGFloat(boundary) * slot
            context.move(to: CGPoint(x: x, y: plot.minY))
            context.addLine(to: CGPoint(x: x, y: plot.maxY + ceil(axisFont.lineHeight) + Self.axisLabelGap))
        }
        context.strokePath()
        context.restoreGState()
        let centers = points.indices.map { plot.minX + (CGFloat($0) + 0.5) * slot }
        for (index, point) in points.enumerated() {
            let center = centers[index]
            let height = CGFloat(point.accuracy) / 100 * plot.height
            let bar = CGRect(x: center - barWidth / 2, y: plot.maxY - height, width: barWidth, height: height)
            firstRunAccuracyUIColor(point.accuracy, isFullCombo: point.isFullCombo).setFill()
            UIBezierPath(roundedRect: bar, byRoundingCorners: [.topLeft, .topRight],
                         cornerRadii: CGSize(width: 4, height: 4)).fill()
            if showsSelection {
                if index == selectedIndex {
                    BrandUIColors.accentPurple.setStroke()
                    let selection = UIBezierPath(roundedRect: bar.insetBy(dx: -2, dy: -2), cornerRadius: 5)
                    selection.lineWidth = 2
                    selection.stroke()
                }
            } else {
                let text = point.score.formatted() as NSString
                let size = text.size(withAttributes: scoreAttributes)
                text.draw(at: CGPoint(x: center - size.width / 2, y: bar.minY - size.height - Self.axisLabelGap),
                          withAttributes: scoreAttributes)
            }
        }
        drawDateLabels(zip(points, centers).map { ($0.label, $1) },
                       top: plot.maxY + Self.axisLabelGap, color: tickColor, gap: 4)
    }
}
#endif
