#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Plot

/// The drawn part of the Score History chart: accuracy bars on the trailing 0 to 100 % axis
/// (gold for a 100 % full combo), the score line and its points on the leading axis, date
/// labels below, in Core Graphics from the same data the SwiftUI chart plots.
final class UKScoreHistoryPlotView: UIView {
    /// One plotted score.
    struct Point {
        let id: Int
        let label: String
        let score: Double
        let accuracy: Double
        let gold: Bool
    }

    /// The plot's total height (Swift Charts' `.frame(height: 220)`).
    static let height: CGFloat = 220
    private static let bottomAxis: CGFloat = 24
    private static let topInset: CGFloat = 6
    /// Web `accentBlueBright` (#4C7DFF), the score line and its dots.
    static let lineColor = UIColor(red: 76 / 255, green: 125 / 255, blue: 1, alpha: 1)

    var points: [Point] = [] { didSet { setNeedsDisplay() } }
    var range: Range<Int> = 0..<0 { didSet { setNeedsDisplay() } }
    var top: Double = 1 { didSet { setNeedsDisplay() } }
    var selectedIndex: Int? { didSet { setNeedsDisplay() } }
    /// The card's measured width, which sizes the bars.
    var chartWidth: CGFloat = 0
    /// Called with the nearest bar's index when the plot is tapped.
    var onSelect: ((Int) -> Void)?
    /// Called with +1 (newer page) or -1 (older page) on a horizontal swipe.
    var onPage: ((Int) -> Void)?

    private let font = UKFont.font(.caption2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKScoreHistoryPlotView, _) in self.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Geometry

    private var leadingTicks: [Double] { SongScoreHistoryChartMath.scoreTicks(top: top) }
    private var percentTicks: [Double] { [0, 25, 50, 75, 100] }

    private var axisFont: [NSAttributedString.Key: Any] {
        [.font: UKFont.font(.caption2), .foregroundColor: BrandUIColors.textPrimary]
    }

    private func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: axisFont).width)
    }

    /// The plot area, between the two label columns.
    var plotRect: CGRect {
        let leading = (leadingTicks.map { width(of: SongScoreHistoryChartMath.scoreAxisLabel($0)) }.max() ?? 0) + 8
        let trailing = width(of: "100%") + 8
        return CGRect(
            x: leading, y: Self.topInset, width: max(1, bounds.width - leading - trailing),
            height: Self.height - Self.bottomAxis - Self.topInset
        )
    }

    private func x(_ index: Int, plot: CGRect) -> CGFloat {
        let lower = Double(range.lowerBound) - 0.5
        let upper = Double(max(range.lowerBound + 1, range.upperBound)) - 0.5
        return plot.minX + CGFloat((Double(index) - lower) / (upper - lower)) * plot.width
    }

    private func y(_ value: Double, plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(min(max(value / top, 0), 1)) * plot.height
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !range.isEmpty, range.upperBound <= points.count else { return }
        let plot = plotRect
        // Gridlines and the leading (score) labels.
        context.setStrokeColor(BrandUIColors.glassBorder.cgColor)
        context.setLineWidth(1)
        for tick in leadingTicks {
            let yy = y(tick, plot: plot)
            context.move(to: CGPoint(x: plot.minX, y: yy))
            context.addLine(to: CGPoint(x: plot.maxX, y: yy))
            context.strokePath()
            let text = SongScoreHistoryChartMath.scoreAxisLabel(tick) as NSString
            let size = text.size(withAttributes: axisFont)
            text.draw(at: CGPoint(x: plot.minX - 6 - size.width, y: yy - size.height / 2), withAttributes: axisFont)
        }
        for tick in percentTicks {
            let text = "\(Int(tick))%" as NSString
            let size = text.size(withAttributes: axisFont)
            text.draw(at: CGPoint(x: plot.maxX + 6, y: y(tick / 100 * top, plot: plot) - size.height / 2), withAttributes: axisFont)
        }
        // Bars, line and points are clipped to the plot.
        context.saveGState()
        context.clip(to: plot.insetBy(dx: 0, dy: -2))
        let barWidth = max(8, (chartWidth - 96) / CGFloat(max(1, range.count)) * 0.85)
        let visible = Array(points[range])
        for point in visible {
            let center = x(point.id, plot: plot)
            let barTop = y(point.accuracy / 100 * top, plot: plot)
            let bar = CGRect(x: center - barWidth / 2, y: barTop, width: barWidth, height: plot.maxY - barTop)
            let alpha: CGFloat = selectedIndex == nil || selectedIndex == point.id ? 1 : 0.55
            let color = point.gold ? BrandUIColors.gold : Self.accuracyColor(point.accuracy)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.addPath(UIBezierPath(roundedRect: bar, cornerRadius: min(4, bar.height / 2)).cgPath)
            context.fillPath()
        }
        let positions = visible.map { CGPoint(x: x($0.id, plot: plot), y: y($0.score, plot: plot)) }
        if let line = Self.monotonePath(positions) {
            context.setStrokeColor(Self.lineColor.cgColor)
            context.setLineWidth(2)
            context.setLineJoin(.round)
            context.addPath(line)
            context.strokePath()
        }
        context.setFillColor(Self.lineColor.cgColor)
        for position in positions {
            context.fillEllipse(in: CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6))
        }
        context.restoreGState()
        // Date labels, dropping any that would touch the previous one.
        var lastMax = -CGFloat.infinity
        for point in visible {
            let text = point.label as NSString
            let size = text.size(withAttributes: axisFont)
            let left = x(point.id, plot: plot) - size.width / 2
            guard left >= lastMax + 6, left >= 0, left + size.width <= bounds.width else { continue }
            text.draw(at: CGPoint(x: left, y: plot.maxY + 6), withAttributes: axisFont)
            lastMax = left + size.width
        }
    }

    /// Web `accuracyColor`: red to green over 0 to 100 %.
    static func accuracyColor(_ percent: Double) -> UIColor {
        let rgb = SongScoreHistoryChartMath.accuracyRGB(percent)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// A monotone cubic path through the points (Swift Charts' `.monotone` interpolation).
    ///
    /// - Parameter points: Left-to-right positions.
    /// - Returns: The curve, or nil for no points.
    static func monotonePath(_ points: [CGPoint]) -> CGPath? {
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        guard points.count > 1 else { return path }
        let n = points.count
        var slopes = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            slopes[i] = dx == 0 ? 0 : (points[i + 1].y - points[i].y) / dx
        }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }
        for i in 0..<(n - 1) {
            if slopes[i] == 0 { tangents[i] = 0; tangents[i + 1] = 0; continue }
            let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
            let h = (a * a + b * b).squareRoot()
            if h > 3 {
                tangents[i] = 3 * a / h * slopes[i]
                tangents[i + 1] = 3 * b / h * slopes[i]
            }
        }
        for i in 0..<(n - 1) {
            let dx = (points[i + 1].x - points[i].x) / 3
            path.addCurve(
                to: points[i + 1],
                control1: CGPoint(x: points[i].x + dx, y: points[i].y + tangents[i] * dx),
                control2: CGPoint(x: points[i + 1].x - dx, y: points[i + 1].y - tangents[i + 1] * dx)
            )
        }
        return path
    }

    // MARK: Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let plot = plotRect
        let location = gesture.location(in: self)
        guard plot.insetBy(dx: -8, dy: 0).contains(CGPoint(x: location.x, y: plot.midY)), !range.isEmpty else { return }
        let nearest = range.min { abs(x($0, plot: plot) - location.x) < abs(x($1, plot: plot) - location.x) }
        if let nearest { onSelect?(nearest) }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        onPage?(gesture.direction == .left ? 1 : -1)
    }
}

// MARK: - Chart

/// Accuracy bars and the score line for one instrument, one page at a time (the SwiftUI
/// `ScoreHistoryChart`): the plot, a legend, the pager when the series is wider than one
/// page, and the tapped bar's detail row. Spoken as one chart element with its three axes.
final class UKScoreHistoryChartView: UIView {
    private let rows: [ScoreHistoryEntry]
    private let instrument: Instrument
    private let reservesPager: Bool
    private let currentSeason: Int?
    private let plot = UKScoreHistoryPlotView()
    private let stack = UIStackView()
    private let detailHolder = UIView()
    private var pagerView: UIView?
    private var pagerButtons: [UIButton] = []
    private var paging: RankHistoryPaging
    private var start: Int?
    private var selectedIndex: Int?
    private let points: [UKScoreHistoryPlotView.Point]
    private let top: Double
    private var axisElements: [UIAccessibilityElement] = []

    /// Creates the chart.
    ///
    /// - Parameters:
    ///   - rows: The instrument's history, oldest first.
    ///   - instrument: The chart's instrument.
    ///   - chartWidth: The card's measured width (the page size).
    ///   - reservesPager: Keep the pager row's space even when one page holds everything.
    ///   - currentSeason: The catalogue's current season, for the detail row.
    init(rows: [ScoreHistoryEntry], instrument: Instrument, chartWidth: CGFloat, reservesPager: Bool, currentSeason: Int?) {
        self.rows = rows
        self.instrument = instrument
        self.reservesPager = reservesPager
        self.currentSeason = currentSeason
        points = rows.enumerated().map { index, entry in
            .init(
                id: index, label: SongScoreHistoryChartMath.dateLabel(entry), score: Double(entry.newScore),
                accuracy: SongScoreHistoryModel.accuracyPercent(entry), gold: SongScoreHistoryModel.isGold(entry)
            )
        }
        top = max(1, (points.map(\.score).max() ?? 0) * 1.1)
        paging = SongScoreHistoryModel.paging(count: rows.count, chartWidth: Double(chartWidth))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        plot.chartWidth = chartWidth
        plot.points = points
        plot.top = top
        plot.onSelect = { [weak self] in self?.select($0) }
        plot.onPage = { [weak self] direction in
            guard let self, self.paging.needsPagination else { return }
            let first = self.first
            self.move(to: direction > 0 ? self.paging.forwardPage(from: first) : self.paging.backPage(from: first))
        }
        plot.isAccessibilityElement = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(plot)
        stack.addArrangedSubview(legend())
        if paging.needsPagination {
            let pager = makePager()
            pagerView = pager
            stack.addArrangedSubview(pager)
        } else if reservesPager {
            let pager = makePager()
            pager.isHidden = false
            pager.alpha = 0
            pager.accessibilityElementsHidden = true
            pager.isUserInteractionEnabled = false
            stack.addArrangedSubview(pager)
        }
        stack.addArrangedSubview(detailHolder)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var first: Int { paging.clamp(start ?? paging.latestStart) }

    private func applyWindow() {
        let range = paging.visibleRange(from: first)
        plot.range = range
        plot.selectedIndex = selectedIndex
        updatePager()
        accessibilityElements = nil
    }

    private func select(_ index: Int) {
        guard points.indices.contains(index) else { return }
        selectedIndex = index
        plot.selectedIndex = index
        detailHolder.subviews.forEach { $0.removeFromSuperview() }
        let row = UKScoreHistoryRowView(
            entry: rows[index], isBest: false, seasonColumn: ScoreRowSeasonPolicy.showsColumn(.historyDetail, width: 0),
            currentSeason: currentSeason, grouped: false, scoreTemplate: nil
        )
        row.accessibilityIdentifier = "fst.song-detail.history.detail"
        row.translatesAutoresizingMaskIntoConstraints = false
        detailHolder.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: detailHolder.leadingAnchor), row.trailingAnchor.constraint(equalTo: detailHolder.trailingAnchor),
            row.topAnchor.constraint(equalTo: detailHolder.topAnchor), row.bottomAnchor.constraint(equalTo: detailHolder.bottomAnchor),
        ])
        if !UKAccessibility.reduceMotion {
            row.alpha = 0
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) { row.alpha = 1 }
        }
    }

    private func move(to index: Int) {
        let apply = {
            self.start = index == self.paging.latestStart ? nil : index
            self.selectedIndex = nil
            self.detailHolder.subviews.forEach { $0.removeFromSuperview() }
            self.applyWindow()
        }
        if UKAccessibility.reduceMotion {
            apply()
        } else {
            UIView.transition(with: plot, duration: 0.35, options: [.transitionCrossDissolve, .curveEaseOut], animations: apply)
        }
    }

    // MARK: Legend

    private func swatch(color: UIColor?, gradient: [UIColor]?, title: String) -> UIView {
        let box = UIView()
        box.layer.cornerRadius = 2
        box.clipsToBounds = true
        if let gradient {
            let layer = CAGradientLayer()
            layer.colors = gradient.map(\.cgColor)
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 0.5)
            layer.frame = CGRect(x: 0, y: 0, width: 16, height: 12)
            box.layer.addSublayer(layer)
        } else {
            box.backgroundColor = color
        }
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([box.widthAnchor.constraint(equalToConstant: 16), box.heightAnchor.constraint(equalToConstant: 12)])
        let label = UKLabel(title, style: .subheadline, lines: 1)
        let row = UIStackView(arrangedSubviews: [box, label])
        row.spacing = 6
        row.alignment = .center
        return row
    }

    private func legend() -> UIView {
        let hasGraded = points.contains { !$0.gold }
        let hasGold = points.contains(where: \.gold)
        var items: [UIView] = []
        if hasGraded {
            items.append(swatch(color: nil, gradient: [UKScoreHistoryPlotView.accuracyColor(0), UKScoreHistoryPlotView.accuracyColor(100)], title: "Accuracy"))
        }
        if hasGold { items.append(swatch(color: BrandUIColors.gold, gradient: nil, title: "Accuracy (FC)")) }
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIView()
        bar.backgroundColor = UKScoreHistoryPlotView.lineColor
        let dot = UIView()
        dot.backgroundColor = UKScoreHistoryPlotView.lineColor
        dot.layer.cornerRadius = 3
        for view in [bar, dot] { view.translatesAutoresizingMaskIntoConstraints = false; line.addSubview(view) }
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 24), line.heightAnchor.constraint(equalToConstant: 12),
            bar.leadingAnchor.constraint(equalTo: line.leadingAnchor), bar.widthAnchor.constraint(equalToConstant: 18),
            bar.heightAnchor.constraint(equalToConstant: 2), bar.centerYAnchor.constraint(equalTo: line.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6), dot.heightAnchor.constraint(equalToConstant: 6),
            dot.centerYAnchor.constraint(equalTo: line.centerYAnchor), dot.leadingAnchor.constraint(equalTo: line.leadingAnchor, constant: 18),
        ])
        let score = UIStackView(arrangedSubviews: [line, UKLabel("Score", style: .subheadline, lines: 1)])
        score.spacing = 6
        score.alignment = .center
        items.append(score)
        let row = UIStackView(arrangedSubviews: items)
        row.spacing = 16
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        let holder = UIView()
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: holder.centerXAnchor), row.topAnchor.constraint(equalTo: holder.topAnchor),
            row.bottomAnchor.constraint(equalTo: holder.bottomAnchor), row.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor),
        ])
        // Static text, not a control (the audit judged it an 18 pt interactive element otherwise).
        holder.isAccessibilityElement = true
        holder.accessibilityLabel = "Legend: bars show accuracy, the line shows score"
        holder.accessibilityTraits = .staticText
        return holder
    }

    // MARK: Pager

    private func makePager() -> UIStackView {
        func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: symbol)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
            configuration.baseForegroundColor = BrandUIColors.textPrimary
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = label
            button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
            button.translatesAutoresizingMaskIntoConstraints = false
            let circle = UIView()
            circle.isUserInteractionEnabled = false
            circle.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            circle.layer.cornerRadius = 18
            circle.layer.borderWidth = 1
            circle.layer.borderColor = BrandUIColors.glassBorder.cgColor
            circle.translatesAutoresizingMaskIntoConstraints = false
            button.insertSubview(circle, at: 0)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44),
                circle.widthAnchor.constraint(equalToConstant: 36), circle.heightAnchor.constraint(equalToConstant: 36),
                circle.centerXAnchor.constraint(equalTo: button.centerXAnchor), circle.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            return button
        }
        let buttons = [
            button("chevron.backward.2", "Back one page") { [weak self] in guard let self else { return }; self.move(to: self.paging.backPage(from: self.first)) },
            button("chevron.backward", "Back one entry") { [weak self] in guard let self else { return }; self.move(to: self.paging.backEntry(from: self.first)) },
            button("chevron.forward", "Forward one entry") { [weak self] in guard let self else { return }; self.move(to: self.paging.forwardEntry(from: self.first)) },
            button("chevron.forward.2", "Forward one page") { [weak self] in guard let self else { return }; self.move(to: self.paging.forwardPage(from: self.first)) },
        ]
        pagerButtons = buttons
        let row = UIStackView(arrangedSubviews: [buttons[0], buttons[1], UIView(), buttons[2], buttons[3]])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func updatePager() {
        guard pagerButtons.count == 4 else { return }
        let first = first
        let back = paging.canGoBack(from: first)
        let forward = paging.canGoForward(from: first)
        for (index, button) in pagerButtons.enumerated() {
            let enabled = index < 2 ? back : forward
            button.isEnabled = enabled
            button.configuration?.baseForegroundColor = enabled ? BrandUIColors.textPrimary : BrandUIColors.textDisabled
        }
    }

    // MARK: Accessibility

    override var accessibilityElements: [Any]? {
        get {
            if let cached = super.accessibilityElements { return cached }
            let area = plot.plotRect
            let visible = Array(points[plot.range])
            let chart = UIAccessibilityElement(accessibilityContainer: self)
            chart.accessibilityLabel = "\(instrument.label) score history chart"
            chart.accessibilityValue = SongScoreHistoryChartMath.spokenValue(rows)
            chart.accessibilityIdentifier = "fst.song-detail.history.chart"
            chart.accessibilityTraits = .image
            chart.accessibilityFrameInContainerSpace = plot.convert(plot.bounds, to: self)
            func axis(_ label: String, _ rect: CGRect) -> UIAccessibilityElement {
                let element = UIAccessibilityElement(accessibilityContainer: self)
                element.accessibilityLabel = label
                element.accessibilityTraits = .staticText
                element.accessibilityFrameInContainerSpace = plot.convert(rect, to: self)
                return element
            }
            let leading = axis(
                "Score scale, 0 to \(SongScoreHistoryChartMath.scoreAxisLabel(top))",
                CGRect(x: 0, y: area.minY, width: max(1, area.minX), height: area.height)
            )
            let trailing = axis(
                "Accuracy scale, 0% to 100%",
                CGRect(x: area.maxX, y: area.minY, width: max(1, plot.bounds.width - area.maxX), height: area.height)
            )
            let bottom = axis(
                "Dates, " + ChartAxisLabels.span(visible.first?.label, visible.last?.label),
                CGRect(x: area.minX, y: area.maxY, width: area.width, height: max(1, plot.bounds.height - area.maxY))
            )
            let rest: [Any] = Array(stack.arrangedSubviews.dropFirst())
            let elements: [Any] = [chart, leading, trailing, bottom] + rest
            super.accessibilityElements = elements
            return elements
        }
        set { super.accessibilityElements = newValue }
    }
}
#endif
