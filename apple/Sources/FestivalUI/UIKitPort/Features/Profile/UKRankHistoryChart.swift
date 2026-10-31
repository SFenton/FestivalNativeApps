#if os(iOS)
import Accessibility
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Plot

/// The Rank History plot (``RankHistoryCharts`` without its chrome), drawn with Core Graphics:
/// value bars on a leading axis (each coloured by its rank's place in the field), the rank
/// line on a trailing reversed rank axis (bright blue with dots), and a date label under each
/// visible bar. Every point sits at its series index and the x domain is the visible window,
/// so paging slides the window instead of re-laying out.
///
/// It is an accessibility container: one adjustable chart element over the plot (the whole plot
/// is the hit target, HIG Charts) that reads every visible snapshot and carries the Audio Graph,
/// then one static-text element per axis.
final class UKRankHistoryPlotView: UIView {
    /// Plot height (``RankHistoryCharts/plotHeight``).
    static let height = RankHistoryCharts.plotHeight
    /// Width of each value-axis label column (two of them make ``RankHistoryCharts``' axis overhead).
    static let labelColumn: CGFloat = 48
    private static let bottomAxis: CGFloat = 22
    private static let topInset: CGFloat = 6

    private(set) var points: [RankHistoryCharts.Point] = []
    private(set) var valueKind: RankHistoryValueKind = .playerTotalScore
    private var range: Range<Int> = 0..<0
    private var scale = RankHistoryChartScale(values: [], ranks: [])
    private var chartTitle = ""
    private let chartElement: UKRankHistoryChartElement
    private let leadingAxis: UIAccessibilityElement
    private let trailingAxis: UIAccessibilityElement
    private let bottomAxis: UIAccessibilityElement

    /// Called to page by the chart element's adjustable action (`+1` newer, `-1` older).
    var onAdjust: ((Int) -> Void)? {
        didSet { chartElement.onAdjust = onAdjust }
    }

    /// Creates the plot.
    ///
    /// - Parameter identifier: The chart element's identifier (`<prefix>.chart`).
    init(identifier: String) {
        chartElement = UKRankHistoryChartElement(accessibilityContainer: UIView())
        leadingAxis = UIAccessibilityElement(accessibilityContainer: UIView())
        trailingAxis = UIAccessibilityElement(accessibilityContainer: UIView())
        bottomAxis = UIAccessibilityElement(accessibilityContainer: UIView())
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        contentMode = .redraw
        isOpaque = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        chartElement.accessibilityContainer = self
        chartElement.accessibilityIdentifier = identifier
        for axis in [leadingAxis, trailingAxis, bottomAxis] {
            axis.accessibilityContainer = self
            axis.accessibilityTraits = .staticText
        }
        accessibilityElements = [chartElement, leadingAxis, trailingAxis, bottomAxis]
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Data

    /// Shows a window of the series.
    ///
    /// - Parameters:
    ///   - points: Every snapshot, oldest first.
    ///   - valueKind: What the bars measure.
    ///   - title: The chart's accessibility title, e.g. "Lead rank history".
    ///   - range: The visible index window.
    func show(points: [RankHistoryCharts.Point], valueKind: RankHistoryValueKind, title: String, range: Range<Int>) {
        self.points = points
        self.valueKind = valueKind
        self.range = range
        chartTitle = title
        scale = RankHistoryChartScale(values: points.map(\.value), ranks: points.map(\.rank))
        updateAccessibility()
        setNeedsDisplay()
    }

    // MARK: Geometry

    private var plotRect: CGRect {
        CGRect(
            x: Self.labelColumn, y: Self.topInset,
            width: max(0, bounds.width - 2 * Self.labelColumn),
            height: max(0, bounds.height - Self.topInset - Self.bottomAxis)
        )
    }

    private func x(forIndex index: Int, in plot: CGRect) -> CGFloat {
        let lower = Double(range.lowerBound) - 0.5
        let upper = Double(max(range.lowerBound + 1, range.upperBound)) - 0.5
        return plot.minX + CGFloat((Double(index) - lower) / (upper - lower)) * plot.width
    }

    private func y(forValue value: Double, in plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(value / scale.valueTop) * plot.height
    }

    /// About `count` evenly spaced value ticks from 0 (Swift Charts' automatic marks).
    private func valueTicks(top: Double, count: Int = 4) -> [Double] {
        guard top > 0 else { return [0] }
        let raw = top / Double(count)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let step = (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10) * magnitude
        return Array(stride(from: 0, through: top, by: step))
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !points.isEmpty, !range.isEmpty else { return }
        let plot = plotRect
        guard plot.width > 0, plot.height > 0 else { return }
        drawGrid(in: context, plot: plot)
        context.saveGState()
        context.clip(to: plot)
        drawBars(in: context, plot: plot)
        drawRankLine(in: context, plot: plot)
        context.restoreGState()
        drawAxisLabels(plot: plot)
    }

    private func drawGrid(in context: CGContext, plot: CGRect) {
        context.setStrokeColor(BrandUIColors.glassBorder.cgColor)
        context.setLineWidth(1)
        for tick in valueTicks(top: scale.valueTop) {
            let y = y(forValue: tick, in: plot).rounded() + 0.5
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        context.strokePath()
    }

    private func drawBars(in context: CGContext, plot: CGRect) {
        let barWidth = max(8, (bounds.width - 2 * Self.labelColumn) / CGFloat(max(1, range.count)) * 0.85)
        for point in points where range.contains(point.index) {
            let rgb = RankHistoryChartFormat.rankColor(rank: point.rank, totalAccounts: point.rankedAccountCount)
            let color = UIColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 0.8)
            let centre = x(forIndex: point.index, in: plot)
            let top = y(forValue: point.value, in: plot)
            let bar = CGRect(x: centre - barWidth / 2, y: top, width: barWidth, height: max(0, plot.maxY - top))
            context.setFillColor(color.cgColor)
            context.addPath(UIBezierPath(roundedRect: bar, cornerRadius: min(4, bar.height / 2)).cgPath)
            context.fillPath()
        }
    }

    private func drawRankLine(in context: CGContext, plot: CGRect) {
        let visible = points.filter { $0.index >= range.lowerBound - 1 && $0.index <= range.upperBound }
        let xs = visible.map { x(forIndex: $0.index, in: plot) }
        let ys = visible.map { y(forValue: scale.y(forRank: $0.rank), in: plot) }
        guard !visible.isEmpty else { return }
        let line = BrandUIColors.rankHistoryLine
        context.setStrokeColor(line.cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if visible.count > 1 {
            context.addPath(Self.monotonePath(xs: xs, ys: ys).cgPath)
            context.strokePath()
        }
        context.setFillColor(line.cgColor)
        let radius = (30 / CGFloat.pi).squareRoot()
        for (px, py) in zip(xs, ys) {
            context.fillEllipse(in: CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// A monotone cubic through the points (Fritsch-Carlson), the `.monotone` interpolation.
    ///
    /// - Parameters:
    ///   - xs: Increasing x positions.
    ///   - ys: Y positions.
    /// - Returns: The curve.
    static func monotonePath(xs: [CGFloat], ys: [CGFloat]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let firstX = xs.first, let firstY = ys.first else { return path }
        path.move(to: CGPoint(x: firstX, y: firstY))
        let n = xs.count
        guard n > 1 else { return path }
        var secants: [CGFloat] = []
        for k in 0 ..< n - 1 { secants.append((ys[k + 1] - ys[k]) / max(0.0001, xs[k + 1] - xs[k])) }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        if n > 2 {
            for k in 1 ..< n - 1 {
                tangents[k] = secants[k - 1] * secants[k] <= 0 ? 0 : (secants[k - 1] + secants[k]) / 2
            }
        }
        for k in 0 ..< n - 1 {
            if secants[k] == 0 {
                tangents[k] = 0
                tangents[k + 1] = 0
                continue
            }
            let a = tangents[k] / secants[k], b = tangents[k + 1] / secants[k]
            let s = a * a + b * b
            if s > 9 {
                let t = 3 / s.squareRoot()
                tangents[k] = t * a * secants[k]
                tangents[k + 1] = t * b * secants[k]
            }
        }
        for k in 0 ..< n - 1 {
            let h = xs[k + 1] - xs[k]
            path.addCurve(
                to: CGPoint(x: xs[k + 1], y: ys[k + 1]),
                controlPoint1: CGPoint(x: xs[k] + h / 3, y: ys[k] + tangents[k] * h / 3),
                controlPoint2: CGPoint(x: xs[k + 1] - h / 3, y: ys[k + 1] - tangents[k + 1] * h / 3)
            )
        }
        return path
    }

    private func drawAxisLabels(plot: CGRect) {
        let font = UKFont.font(.caption2)
        let white = BrandUIColors.textPrimary
        let right = NSMutableParagraphStyle()
        right.alignment = .right
        let left = NSMutableParagraphStyle()
        left.alignment = .left
        let centre = NSMutableParagraphStyle()
        centre.alignment = .center
        let height = font.lineHeight
        for tick in valueTicks(top: scale.valueTop) {
            let text = valueKind.tick(tick)
            let rect = CGRect(x: 0, y: y(forValue: tick, in: plot) - height / 2, width: Self.labelColumn - 6, height: height)
            (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: white, .paragraphStyle: right])
        }
        for rank in scale.rankTicks {
            let yy = y(forValue: scale.y(forRank: rank), in: plot)
            let rect = CGRect(x: plot.maxX + 6, y: yy - height / 2, width: Self.labelColumn - 6, height: height)
            ("#\(rank.formatted())" as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: white, .paragraphStyle: left])
        }
        var lastMax = -CGFloat.infinity
        for point in points where range.contains(point.index) {
            let centreX = x(forIndex: point.index, in: plot)
            let width = (point.label as NSString).size(withAttributes: [.font: font]).width + 4
            guard centreX - width / 2 > lastMax else { continue }
            lastMax = centreX + width / 2
            let rect = CGRect(x: centreX - width / 2, y: plot.maxY + 4, width: width, height: height)
            (point.label as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: white, .paragraphStyle: centre])
        }
    }

    // MARK: Accessibility

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAccessibility()
        setNeedsDisplay()
    }

    private func updateAccessibility() {
        let plot = plotRect
        let visible = points.filter { range.contains($0.index) }
        chartElement.accessibilityLabel = "\(chartTitle) chart"
        chartElement.accessibilityValue = RankHistoryCharts.accessibilityValue(page: visible, kind: valueKind)
        chartElement.accessibilityTraits = .adjustable
        chartElement.accessibilityFrameInContainerSpace = plot
        chartElement.descriptor = points.isEmpty ? nil : RankHistoryDescriptor(points: points, valueKind: valueKind, title: chartTitle).makeChartDescriptor()
        leadingAxis.accessibilityLabel = "\(valueKind.title) scale, 0 to \(valueKind.tick(scale.valueTop))"
        leadingAxis.accessibilityFrameInContainerSpace = CGRect(x: 0, y: plot.minY, width: max(1, plot.minX), height: plot.height)
        trailingAxis.accessibilityLabel = "Rank scale, " + ChartAxisLabels.span(
            scale.rankTicks.first.map { "#\($0.formatted())" }, scale.rankTicks.last.map { "#\($0.formatted())" }
        )
        trailingAxis.accessibilityFrameInContainerSpace = CGRect(x: plot.maxX, y: plot.minY, width: max(1, bounds.width - plot.maxX), height: plot.height)
        bottomAxis.accessibilityLabel = "Dates, " + ChartAxisLabels.span(visible.first?.label, visible.last?.label)
        bottomAxis.accessibilityFrameInContainerSpace = CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: max(1, bounds.height - plot.maxY))
    }
}

/// The adjustable chart element: swiping up or down pages, as the pager buttons do.
final class UKRankHistoryChartElement: UIAccessibilityElement, @preconcurrency AXChart {
    /// Called with `+1` (newer page) or `-1` (older page).
    var onAdjust: ((Int) -> Void)?
    /// The Audio Graph descriptor.
    var descriptor: AXChartDescriptor?

    var accessibilityChartDescriptor: AXChartDescriptor? {
        get { descriptor }
        set { descriptor = newValue }
    }

    override func accessibilityIncrement() { onAdjust?(+1) }
    override func accessibilityDecrement() { onAdjust?(-1) }
}

private extension BrandUIColors {
    /// Web `Colors.accentBlueBright` (#4C7DFF), the rank line and its dots.
    static let rankHistoryLine = UIColor(red: 76 / 255, green: 125 / 255, blue: 1, alpha: 1)
}

// MARK: - Round glyph button

/// A 44 pt pager button with a 36 pt frosted circle and a footnote glyph (the Rank History
/// pager's `pagerButton`).
final class UKRoundGlyphButton: UIControl {
    private let circle = UIView()
    private let glyph: UIImageView

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - symbol: SF Symbol name.
    ///   - label: Spoken action.
    ///   - identifier: Accessibility identifier.
    ///   - action: Tap handler.
    init(symbol: String, label: String, identifier: String, action: @escaping () -> Void) {
        glyph = UIImageView(image: UIImage(systemName: symbol))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        circle.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        circle.layer.cornerRadius = 18
        circle.layer.borderWidth = 1
        circle.layer.borderColor = BrandUIColors.glassBorder.cgColor
        circle.isUserInteractionEnabled = false
        circle.translatesAutoresizingMaskIntoConstraints = false
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        glyph.contentMode = .center
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)
        addSubview(glyph)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 36), circle.heightAnchor.constraint(equalToConstant: 36),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor), circle.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor), glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44), heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityIdentifier = identifier
        accessibilityTraits = .button
        addAction(UIAction { _ in action() }, for: .touchUpInside)
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { applyState() }
    }

    private func applyState() {
        glyph.tintColor = isEnabled ? BrandUIColors.textPrimary : BrandUIColors.textDisabled
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}

// MARK: - Chart with chrome

/// The combined Rank History chart with its latest summary, rotated axis titles, legend and
/// pager (``RankHistoryCharts``): a swipeable window of history (a page at a time) with the
/// web's four pagination buttons. One chart for every rank history (pattern `chart-date-axis`):
/// the Player profile plots an instrument's Total Score, Band Detail its Rank By metric.
final class UKRankHistoryChartView: UIView, UKWidthDependent {
    private let points: [RankHistoryCharts.Point]
    private let valueKind: RankHistoryValueKind
    private let title: String
    private let identifierPrefix: String
    private let plot: UKRankHistoryPlotView
    private let summary = UIStackView()
    private let legend = UIView()
    private let pager = UIStackView()
    private let rangeLabel = UKLabel(style: .footnote, monospacedDigit: true, lines: 1, alignment: .center)
    private var buttons: [UKRoundGlyphButton] = []
    private var chartWidth: CGFloat
    private var start: Int?
    private let gestureDelegate = UKRankHistoryPagingGesture()

    /// Creates a chart of any rank history.
    ///
    /// - Parameters:
    ///   - points: Ranked snapshots, oldest first, indexed from 0.
    ///   - valueKind: What the bars measure.
    ///   - title: Accessibility title, e.g. "Band rank history".
    ///   - identifierPrefix: Identifier prefix for the chart and its pager buttons.
    ///   - initialChartWidth: Expected plot width so the first frame already pages correctly.
    init(
        points: [RankHistoryCharts.Point], valueKind: RankHistoryValueKind, title: String, identifierPrefix: String,
        initialChartWidth: CGFloat = 0
    ) {
        self.points = points
        self.valueKind = valueKind
        self.title = title
        self.identifierPrefix = identifierPrefix
        self.chartWidth = initialChartWidth
        plot = UKRankHistoryPlotView(identifier: "\(identifierPrefix).chart")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        reload(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Build

    private func build() {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 12
        column.alignment = .fill
        if let latest = points.last { column.addArrangedSubview(makeSummary(latest)) }
        let plotRow = UIStackView(arrangedSubviews: [axisTitle(valueKind.title, degrees: -90), plot, axisTitle("Rank", degrees: 90)])
        plotRow.axis = .horizontal
        plotRow.spacing = 2
        plotRow.alignment = .fill
        column.addArrangedSubview(plotRow)
        column.addArrangedSubview(makeLegend())
        column.addArrangedSubview(makePager())
        ukPin(column)
        plot.onAdjust = { [weak self] direction in
            guard let self else { return }
            let paging = self.paging
            let start = self.currentStart
            self.move(to: direction > 0 ? paging.forwardPage(from: start) : paging.backPage(from: start))
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        gestureDelegate.pagesAvailable = { [weak self] in self?.paging.needsPagination ?? false }
        pan.delegate = gestureDelegate
        plot.addGestureRecognizer(pan)
    }

    private func makeSummary(_ latest: RankHistoryCharts.Point) -> UIView {
        let field = latest.rankedAccountCount.map { " of \($0.formatted())" } ?? ""
        let headline = UKLabel("#\(latest.rank.formatted())\(field)", style: .title3, weight: .bold, monospacedDigit: true)
        summary.axis = .vertical
        summary.spacing = 2
        summary.addArrangedSubview(headline)
        if latest.hasValue {
            summary.addArrangedSubview(UKLabel("\(valueKind.title) \(valueKind.text(latest.value))", style: .footnote))
        }
        summary.isAccessibilityElement = true
        summary.accessibilityLabel = "Latest \(valueKind.rankName) \(latest.rank.formatted())\(field)"
            + (latest.hasValue ? ", \(valueKind.inlineName) \(valueKind.text(latest.value))" : "")
        return summary
    }

    private func axisTitle(_ text: String, degrees: CGFloat) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let label = UKLabel(text, style: .caption1, lines: 1)
        label.transform = CGAffineTransform(rotationAngle: degrees * .pi / 180)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityLabel = "\(text) axis"
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalToConstant: 16),
            label.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        return holder
    }

    private func makeLegend() -> UIView {
        let swatch = UIView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor(red: 220 / 255, green: 40 / 255, blue: 40 / 255, alpha: 1).cgColor,
                           UIColor(red: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = 2
        gradient.frame = CGRect(x: 0, y: 0, width: 16, height: 12)
        swatch.layer.addSublayer(gradient)
        NSLayoutConstraint.activate([swatch.widthAnchor.constraint(equalToConstant: 16), swatch.heightAnchor.constraint(equalToConstant: 12)])
        let value = UIStackView(arrangedSubviews: [swatch, UKLabel(valueKind.title, style: .subheadline)])
        value.spacing = 6
        value.alignment = .center
        let lineMark = UIView()
        lineMark.translatesAutoresizingMaskIntoConstraints = false
        let stroke = UIView(frame: CGRect(x: 0, y: 5, width: 18, height: 2))
        stroke.backgroundColor = BrandUIColors.rankHistoryLine
        let dot = UIView(frame: CGRect(x: 15, y: 3, width: 6, height: 6))
        dot.backgroundColor = BrandUIColors.rankHistoryLine
        dot.layer.cornerRadius = 3
        lineMark.addSubview(stroke)
        lineMark.addSubview(dot)
        NSLayoutConstraint.activate([lineMark.widthAnchor.constraint(equalToConstant: 24), lineMark.heightAnchor.constraint(equalToConstant: 12)])
        let rank = UIStackView(arrangedSubviews: [lineMark, UKLabel("Rank", style: .subheadline)])
        rank.spacing = 6
        rank.alignment = .center
        let row = UIStackView(arrangedSubviews: [UIView(), value, rank, UIView()])
        row.spacing = 20
        row.alignment = .center
        row.distribution = .equalCentering
        legend.translatesAutoresizingMaskIntoConstraints = false
        legend.ukPin(row)
        legend.isAccessibilityElement = true
        legend.accessibilityLabel = "Legend: bars show \(valueKind.title), the line shows Rank"
        legend.accessibilityTraits = .staticText
        return legend
    }

    private func makePager() -> UIView {
        let specs: [(String, String, String)] = [
            ("chevron.backward.2", "Back one page", "back-page"), ("chevron.backward", "Back one entry", "back-entry"),
            ("chevron.forward", "Forward one entry", "forward-entry"), ("chevron.forward.2", "Forward one page", "forward-page"),
        ]
        buttons = specs.map { symbol, label, id in
            UKRoundGlyphButton(symbol: symbol, label: label, identifier: "\(identifierPrefix).\(id)") { [weak self] in
                self?.pagerTapped(id)
            }
        }
        rangeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pager.axis = .horizontal
        pager.spacing = 12
        pager.alignment = .center
        pager.addArrangedSubview(buttons[0])
        pager.addArrangedSubview(buttons[1])
        pager.addArrangedSubview(rangeLabel)
        pager.addArrangedSubview(buttons[2])
        pager.addArrangedSubview(buttons[3])
        return pager
    }

    // MARK: Paging

    private static let axisOverhead: CGFloat = 96

    private var paging: RankHistoryPaging {
        let plotWidth = Double(max(0, chartWidth - Self.axisOverhead))
        let size = chartWidth > 0 ? RankHistoryPaging.pageSize(forPlotWidth: plotWidth) : points.count
        return RankHistoryPaging(count: points.count, pageSize: size)
    }

    private var currentStart: Int { paging.clamp(start ?? paging.latestStart) }

    private func pagerTapped(_ id: String) {
        let paging = paging
        let start = currentStart
        switch id {
        case "back-page": move(to: paging.backPage(from: start))
        case "back-entry": move(to: paging.backEntry(from: start))
        case "forward-entry": move(to: paging.forwardEntry(from: start))
        default: move(to: paging.forwardPage(from: start))
        }
    }

    private func move(to index: Int) {
        guard points.indices.contains(index) else { return }
        start = index == paging.latestStart ? nil : index
        reload(animated: true)
    }

    @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, paging.needsPagination else { return }
        let drag = gesture.translation(in: plot)
        guard abs(drag.x) > 50, abs(drag.x) > abs(drag.y) else { return }
        let paging = paging
        move(to: drag.x < 0 ? paging.forwardPage(from: currentStart) : paging.backPage(from: currentStart))
    }

    /// Redraws the window and the pager.
    ///
    /// - Parameter animated: Cross-fade the plot (not under Reduce Motion).
    private func reload(animated: Bool) {
        let paging = paging
        let first = currentStart
        let range = paging.visibleRange(from: first)
        let update = {
            self.plot.show(points: self.points, valueKind: self.valueKind, title: self.title, range: range)
        }
        if animated, !UKAccessibility.reduceMotion {
            UIView.transition(with: plot, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
        } else {
            update()
        }
        pager.isHidden = !paging.needsPagination
        buttons[0].isEnabled = paging.canGoBack(from: first)
        buttons[1].isEnabled = paging.canGoBack(from: first)
        buttons[2].isEnabled = paging.canGoForward(from: first)
        buttons[3].isEnabled = paging.canGoForward(from: first)
        rangeLabel.text = rangeText(range)
        rangeLabel.accessibilityLabel = "Showing \(rangeText(range))"
    }

    private func rangeText(_ range: Range<Int>) -> String {
        guard let first = range.first, let last = range.last, last < points.count else { return "" }
        return first == last ? points[first].label : "\(points[first].label) – \(points[last].label)"
    }

    func prepare(width: CGFloat) {
        // 16 pt axis title + 2 pt spacing on each side of the plot.
        let measured = max(0, width - 36)
        guard abs(measured - chartWidth) > 0.5 else { return }
        let before = paging
        chartWidth = measured
        if paging != before { start = nil }
        reload(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let measured = plot.bounds.width.rounded()
        if measured > 0, abs(measured - chartWidth) > 0.5 {
            let before = paging
            chartWidth = measured
            if paging != before { start = nil }
            reload(animated: false)
        }
    }
}

/// Lets the chart's horizontal swipe pages while the page still scrolls vertically over it.
@MainActor
private final class UKRankHistoryPagingGesture: NSObject, UIGestureRecognizerDelegate {
    var pagesAvailable: () -> Bool = { false }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pagesAvailable() else { return false }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}

// MARK: - Card

/// One instrument's 30-day Total Score rank history card (``PlayerRankHistoryCard``): a
/// placeholder while the read is in flight, an inline retry card on failure, nothing for an
/// empty history, else the chart. Reads only the pure rank-history GET, never player-stats.
final class UKPlayerRankHistoryCardView: UIView, UKWidthDependent {
    private let session: FestivalSession
    private let accountId: String
    private let instrument: Instrument
    private var phase: PlayerRankHistoryCard.Phase
    private var cardWidth: CGFloat = 0
    private var loadTask: Task<Void, Never>?
    private let host = UIView()
    /// Called when the card's visibility or size may have changed (the page re-collects Quick Links).
    var onChange: (() -> Void)?

    private var title: String { "\(instrument.label) Rank History" }

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instrument: Played, Settings-visible chart.
    ///   - preloaded: The page's finished history read, or nil to read here.
    init(session: FestivalSession, accountId: String, instrument: Instrument, preloaded: PlayerRankHistoryCard.Phase?) {
        self.session = session
        self.accountId = accountId
        self.instrument = instrument
        phase = preloaded ?? .loading
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        ukPin(host)
        render()
        if case .loading = phase { load() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { loadTask?.cancel() }

    /// Whether the card shows a chart (it takes a Quick Links entry then).
    var showsChart: Bool {
        if case let .loaded(points) = phase { return !points.isEmpty }
        return false
    }

    func prepare(width: CGFloat) {
        guard abs(width - cardWidth) > 0.5 else { return }
        cardWidth = width
        render()
    }

    private func render() {
        host.subviews.forEach { $0.removeFromSuperview() }
        host.accessibilityIdentifier = nil
        host.accessibilityContainerType = .none
        isHidden = false
        switch phase {
        case .loading:
            let section = UKGroupSectionView("Rank History", subtitle: "Ranking progression over the past 30 days.")
            let loading = UKLoadingView(accessibilityLabel: "Loading \(title)")
            loading.heightAnchor.constraint(equalToConstant: RankHistoryCharts.plotHeight).isActive = true
            section.setRows([loading])
            host.ukPin(section)
            section.ukContain(identifier: "fst.player.rank-history.\(instrument.rawValue).loading")
        case let .failed(issue):
            let section = UKGroupSectionView(title)
            let status = UKServiceStatusInlineView(issue, scope: "player.rank-history.\(instrument.rawValue)") { [weak self] in
                self?.retry()
            }
            section.setRows([status])
            host.ukPin(section)
            section.ukContain(identifier: "fst.player.rank-history.\(instrument.rawValue).error")
        case let .loaded(snapshots) where snapshots.isEmpty:
            isHidden = true
        case let .loaded(snapshots):
            let section = UKGroupSectionView("Rank History", subtitle: "Ranking progression over the past 30 days.")
            let chart = UKRankHistoryChartView(
                points: RankHistoryCharts.points(snapshots), valueKind: .playerTotalScore,
                title: "\(instrument.label) rank history", identifierPrefix: "fst.player.rank-history.\(instrument.rawValue)",
                initialChartWidth: RankHistoryCharts.chartWidth(forCardWidth: cardWidth)
            )
            section.setRows([chart])
            chart.prepare(width: max(0, cardWidth - 32))
            host.ukPin(section)
            section.ukContain(identifier: "fst.player.rank-history.\(instrument.rawValue)")
        }
        onChange?()
    }

    private func retry() {
        phase = .loading
        render()
        load()
    }

    /// Read the pure rank-history GET, never player-stats.
    private func load() {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let history = try await self.session.playerRankHistory(instrument: self.instrument, accountId: self.accountId)
                try Task.checkCancellation()
                self.phase = .loaded(history.rankedChronological)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(ServiceIssue(error))
            }
            self.render()
            if self.showsChart { UKFadeIn.fadeIn(self.host) }
        }
    }
}
#endif
