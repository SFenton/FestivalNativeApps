#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Carousel

/// A horizontal paging carousel of cards (``HorizontalCarousel``): one to three cards
/// across (``CarouselPaging/columns(width:minimumCardWidth:spacing:margin:)``), 12 pt
/// apart with 16 pt margins, snapping a card at a time, each card in its own vertical
/// scroller. Below it a dot row (up to ten pages) or a "3 / 12" counter; the indicator is
/// one adjustable element ("Page 3 of 12") that pages with swipe up and down.
///
/// Identifiers: `fst.carousel.<title words joined by ->` for the scroller and
/// `fst.carousel.indicator` for the indicator.
final class UKHorizontalCarouselView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let title: String
    private let minimumCardWidth: CGFloat
    private let makeCard: (Int) -> UIView
    private let collection: UICollectionView
    private let flow = UICollectionViewFlowLayout()
    private let indicator = UKCarouselIndicatorView()
    private let dots = UIStackView()
    private let counter = UKLabel(style: .caption1, monospacedDigit: true, color: BrandUIColors.textSecondary, lines: 1, alignment: .center)
    private var heightConstraint: NSLayoutConstraint!
    private var measuredHeight: CGFloat = 0
    private var columns = 1

    /// Number of cards.
    var count: Int { didSet { collection.reloadData(); updateIndicator() } }
    /// Whether more cards can load (shows "+" and the counter style).
    var hasMore: Bool { didSet { updateIndicator() } }
    /// Called when a card within two of the end appears and more can load.
    var onNearEnd: (() -> Void)?
    /// The first visible card.
    private(set) var index = 0

    /// Creates a carousel.
    ///
    /// - Parameters:
    ///   - title: Accessibility label of the indicator and source of the identifier.
    ///   - count: Number of cards.
    ///   - minimumCardWidth: Narrowest a card may be before the column count drops.
    ///   - hasMore: Whether more cards can load.
    ///   - makeCard: Builds the card for an index; called when it becomes visible.
    init(title: String, count: Int, minimumCardWidth: CGFloat = 300, hasMore: Bool = false, makeCard: @escaping (Int) -> UIView) {
        self.title = title
        self.count = count
        self.hasMore = hasMore
        self.minimumCardWidth = minimumCardWidth
        self.makeCard = makeCard
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = CarouselPaging.spacing
        flow.sectionInset = UIEdgeInsets(top: 0, left: CarouselPaging.margin, bottom: 0, right: CarouselPaging.margin)
        collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.decelerationRate = .fast
        collection.dataSource = self
        collection.delegate = self
        collection.clipsToBounds = true
        collection.register(UKCarouselCell.self, forCellWithReuseIdentifier: "card")
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.accessibilityIdentifier = "fst.carousel." + title.lowercased().split(separator: " ").joined(separator: "-")
        dots.axis = .horizontal
        dots.spacing = 6
        dots.alignment = .center
        indicator.translatesAutoresizingMaskIntoConstraints = false
        for view in [dots, counter] {
            view.translatesAutoresizingMaskIntoConstraints = false
            indicator.addSubview(view)
        }
        indicator.isAccessibilityElement = true
        indicator.onAdjust = { [weak self] forward in self?.page(forward: forward) }
        indicator.accessibilityLabel = title
        indicator.accessibilityTraits = .adjustable.union(.updatesFrequently)
        indicator.accessibilityIdentifier = "fst.carousel.indicator"
        addSubview(collection)
        addSubview(indicator)
        heightConstraint = collection.heightAnchor.constraint(equalToConstant: 100)
        NSLayoutConstraint.activate([
            collection.leadingAnchor.constraint(equalTo: leadingAnchor), collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.topAnchor.constraint(equalTo: topAnchor), heightConstraint,
            indicator.topAnchor.constraint(equalTo: collection.bottomAnchor, constant: 6),
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor), indicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            indicator.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
            dots.centerXAnchor.constraint(equalTo: indicator.centerXAnchor), dots.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
            counter.centerXAnchor.constraint(equalTo: indicator.centerXAnchor), counter.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
        ])
        updateIndicator()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let newColumns = CarouselPaging.columns(
            width: bounds.width, minimumCardWidth: minimumCardWidth, spacing: CarouselPaging.spacing, margin: CarouselPaging.margin
        )
        if newColumns != columns {
            columns = newColumns
            flow.invalidateLayout()
            updateIndicator()
        }
        indicator.isHidden = !(count > columns || hasMore)
    }

    private var cardWidth: CGFloat {
        let usable = bounds.width - CarouselPaging.margin * 2 - CarouselPaging.spacing * CGFloat(columns - 1)
        return max(floor(usable / CGFloat(columns)), 1)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: cardWidth, height: max(measuredHeight, 1))
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "card", for: indexPath) as! UKCarouselCell
        let card = makeCard(indexPath.item)
        cell.show(card)
        let height = UKSelfSizing.fittingHeight(of: card, width: cardWidth)
        if height > measuredHeight {
            measuredHeight = height
            heightConstraint.constant = height
            flow.invalidateLayout()
            invalidateIntrinsicContentSize()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if CarouselPaging.shouldLoadMore(appearing: indexPath.item, count: count, hasMore: hasMore) { onNearEnd?() }
    }

    // MARK: Paging

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let step = cardWidth + CarouselPaging.spacing
        guard step > 0 else { return }
        let projected = targetContentOffset.pointee.x / step
        let current = scrollView.contentOffset.x / step
        var page = velocity.x > 0.2 ? ceil(current + 0.001) : (velocity.x < -0.2 ? floor(current - 0.001) : projected.rounded())
        page = min(max(page, 0), CGFloat(max(count - 1, 0)))
        targetContentOffset.pointee.x = page * step
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let step = cardWidth + CarouselPaging.spacing
        guard step > 0, count > 0 else { return }
        let next = min(max(Int((scrollView.contentOffset.x / step).rounded()), 0), count - 1)
        if next != index {
            index = next
            updateIndicator()
        }
    }

    /// Pages one card (swipe up or down on the indicator for VoiceOver).
    ///
    /// - Parameter forward: Whether to page toward the end.
    func page(forward: Bool) {
        let target = CarouselPaging.step(from: index, count: count, forward: forward)
        guard target < count else { return }
        let step = cardWidth + CarouselPaging.spacing
        collection.setContentOffset(CGPoint(x: CGFloat(target) * step, y: 0), animated: !UKAccessibility.reduceMotion)
        index = target
        updateIndicator()
    }

    private func updateIndicator() {
        let usesDots = CarouselPaging.usesDots(count: count, hasMore: hasMore)
        dots.isHidden = !usesDots
        counter.isHidden = usesDots
        if usesDots {
            if dots.arrangedSubviews.count != count {
                dots.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for _ in 0..<count {
                    let dot = UIView()
                    dot.translatesAutoresizingMaskIntoConstraints = false
                    dot.layer.cornerRadius = 3
                    NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 6), dot.heightAnchor.constraint(equalToConstant: 6)])
                    dots.addArrangedSubview(dot)
                }
            }
            for (offset, dot) in dots.arrangedSubviews.enumerated() {
                dot.backgroundColor = offset == index ? BrandUIColors.textPrimary : BrandUIColors.textPrimary.withAlphaComponent(0.3)
            }
        } else {
            counter.text = CarouselPaging.counter(index: index, count: count, hasMore: hasMore)
        }
        indicator.accessibilityValue = CarouselPaging.accessibilityValue(index: index, count: count, hasMore: hasMore)
        indicator.isHidden = !(count > columns || hasMore)
    }

}

/// The carousel's page indicator: one adjustable accessibility element.
final class UKCarouselIndicatorView: UIView {
    /// Called with true to page forward (swipe up), false to page back.
    var onAdjust: ((Bool) -> Void)?
    override func accessibilityIncrement() { onAdjust?(true) }
    override func accessibilityDecrement() { onAdjust?(false) }
}

/// One carousel card: the card in its own vertical scroller that bounces only on overflow.
final class UKCarouselCell: UICollectionViewCell {
    private let scroll = UIScrollView()
    private var card: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor), scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ view: UIView) {
        card?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        card = view
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card?.removeFromSuperview()
        card = nil
    }
}
#endif
