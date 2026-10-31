#if os(iOS) && DEBUG
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Gallery

/// Debug gallery of every UIKit design primitive in its states, reached with
/// `FST_UIKIT_GALLERY=design` (``UKApp/makeRootViewController(userActivity:)``), or
/// `design:<id>,<id>` to show only those sections (smaller hierarchies keep UI tests fast). Each
/// primitive carries a `fst.uikit.gallery.<name>` identifier so
/// `UKDesignGalleryJourneyTests` can check labels, traits, targets and text scaling; the
/// SwiftUI app has no gallery, so the journey skips there.
final class UKDesignGalleryViewController: UIViewController, UKModalScrollProviding {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var fade: UKModalTopEdgeFade?
    private var accordion: UKAccordionView<Bool>?
    private let only: Set<String>?

    /// Creates the gallery.
    ///
    /// - Parameter only: Section identifiers to show; nil shows all.
    init(only: Set<String>? = nil) {
        self.only = only
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var ukModalScrollView: UIScrollView? { scroll }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = BrandUIColors.appBackground
        view.accessibilityIdentifier = "fst.uikit.gallery.design"
        title = "Design Gallery"
        navigationItem.largeTitleDisplayMode = .never
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.accessibilityIdentifier = "fst.uikit.gallery.design.scroll"
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        buildSections()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fade?.layout()
    }

    // MARK: Sections

    private func buildSections() {
        add("Section header", UKSectionHeaderView("Find a Profile", subtitle: "Search by username."), id: "section-header")
        addTexts()
        addSurfaces()
        addGroup()
        addGlyphs()
        addSelectors()
        addMarquees()
        addAccordions()
        addStates()
        addTitles()
        addCarouselAndFades()
        addSheetButton()
    }

    private func add(_ name: String, _ view: UIView, id: String) {
        if let only, !only.contains(id) { return }
        let header = UKLabel(name, style: .caption1, weight: .semibold, color: BrandUIColors.textMuted).asHeader()
        header.accessibilityIdentifier = "fst.uikit.gallery.\(id).title"
        view.accessibilityIdentifier = view.accessibilityIdentifier ?? "fst.uikit.gallery.\(id)"
        let group = UIStackView(arrangedSubviews: [header, view])
        group.axis = .vertical
        group.spacing = 6
        stack.addArrangedSubview(group)
    }

    private func addTexts() {
        let text = UIStackView(arrangedSubviews: [
            UKLabel("Large title", style: .largeTitle, weight: .bold), UKLabel("Headline", style: .headline),
            UKLabel("Body text wraps at every Dynamic Type size up to AX5 and stays white.", style: .body),
            UKLabel("1234567890 monospaced digits", style: .body, monospacedDigit: true),
            UKLabel("Accent text", style: .body, color: UKAccentText.blue), UKFootnoteLabel("Footnote under a card."),
        ])
        text.axis = .vertical
        text.spacing = 4
        add("Fonts and text", text, id: "text")
    }

    private func addSurfaces() {
        let card = UKCardView(cornerRadius: 16)
        card.embed(UKLabel("Material card", style: .body), insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        let capsule = UKCardView(capsule: true)
        capsule.embed(UKLabel("Capsule card", style: .body, lines: 1), insets: UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20))
        let glass = UIStackView()
        glass.axis = .vertical
        glass.spacing = 8
        for (name, role) in [("Glass card", FestivalGlassRole.card), ("Glass control", .control), ("Glass overlay", .overlay)] {
            let surface = UKGlassView(role, cornerRadius: 16)
            surface.accessibilityIdentifier = "fst.uikit.gallery.glass.\(name.split(separator: " ")[1].lowercased())"
            let label = UKLabel(name, style: .body)
            label.translatesAutoresizingMaskIntoConstraints = false
            surface.contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -16),
                label.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 14),
                label.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -14),
            ])
            glass.addArrangedSubview(surface)
        }
        let all = UIStackView(arrangedSubviews: [card, capsule, glass])
        all.axis = .vertical
        all.spacing = 8
        all.alignment = .fill
        add("Surfaces", all, id: "surfaces")
    }

    private func addGroup() {
        let section = UKGroupSectionView("Item Shop", subtitle: "Control how Item Shop availability is displayed.")
        section.setRows((1...3).map { UKLabel("Padded row \($0)", style: .body) })
        let viewAll = UKViewAllButton(identifier: "fst.uikit.gallery.view-all", listName: "Item Shop")
        section.setAction(viewAll)
        let flush = UKGroupSectionView("Flush rows", rows: .flush(separatorInset: 12))
        flush.setRows((1...2).map { _ in
            let row = UKLabel("Flush row fills the card edge to edge", style: .body)
            let holder = UIView()
            holder.addSubview(row)
            row.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12).isActive = true
            row.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -12).isActive = true
            row.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12).isActive = true
            row.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12).isActive = true
            return holder
        })
        let both = UIStackView(arrangedSubviews: [section, flush])
        both.axis = .vertical
        both.spacing = 16
        add("Group section", both, id: "group")
    }

    private func addGlyphs() {
        let icons = UIStackView(arrangedSubviews: Instrument.allCases.map { UKInstrumentIconView($0, size: 32) })
        icons.spacing = 8
        let scrollIcons = UIScrollView()
        scrollIcons.addSubview(icons)
        icons.translatesAutoresizingMaskIntoConstraints = false
        scrollIcons.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icons.leadingAnchor.constraint(equalTo: scrollIcons.contentLayoutGuide.leadingAnchor),
            icons.trailingAnchor.constraint(equalTo: scrollIcons.contentLayoutGuide.trailingAnchor),
            icons.topAnchor.constraint(equalTo: scrollIcons.contentLayoutGuide.topAnchor),
            icons.bottomAnchor.constraint(equalTo: scrollIcons.contentLayoutGuide.bottomAnchor),
            icons.heightAnchor.constraint(equalTo: scrollIcons.frameLayoutGuide.heightAnchor),
            scrollIcons.heightAnchor.constraint(equalToConstant: 32),
        ])
        add("Instrument icons", scrollIcons, id: "icons")
        let stars = UIStackView(arrangedSubviews: [
            UKStarRatingView(stars: 3), UKStarRatingView(stars: 5, gold: true), UKStarRatingView(stars: 4, style: .mini),
            UKStarRatingView(stars: 6, gold: true, style: .mini),
        ])
        stars.axis = .vertical
        stars.alignment = .leading
        stars.spacing = 6
        add("Star rating", stars, id: "stars")
        let meters = UIStackView(arrangedSubviews: [
            UKDifficultyMeterView(level: 4), UKDifficultyMeterView(level: 2, raw: true), UKDifficultyMeterView(level: .nan),
        ])
        meters.axis = .vertical
        meters.alignment = .leading
        meters.spacing = 6
        add("Difficulty meter", meters, id: "difficulty")
    }

    private func addSelectors() {
        let full = UKInstrumentSelectorView(
            instruments: [.lead, .bass, .drums, .vocals], selected: .lead, compact: false, identifier: "fst.uikit.gallery.selector.full"
        )
        let compact = UKInstrumentSelectorView(
            instruments: [.lead, .bass, .drums, .vocals, .proLead], selected: .bass, compact: true,
            identifier: "fst.uikit.gallery.selector.compact"
        )
        let states = UKInstrumentSelectorView(
            instruments: [.lead, .bass, .drums, .vocals], selected: .drums, disabled: [.vocals], muted: [.bass], compact: false,
            look: .graph, identifier: "fst.uikit.gallery.selector.states"
        )
        let label = UKLabel("Selected: Lead Guitar", style: .footnote)
        label.accessibilityIdentifier = "fst.uikit.gallery.selector.value"
        full.onSelect = { label.text = "Selected: \($0?.label ?? "None")" }
        let all = UIStackView(arrangedSubviews: [full, compact, states, label])
        all.axis = .vertical
        all.spacing = 12
        add("Instrument selector", all, id: "selector")
    }

    private func addMarquees() {
        let group = UKMarqueeSyncGroup()
        let short = UKMarqueeLabel("Short title")
        let long = UKMarqueeLabel("A very long song title that does not fit on one line at all, so it scrolls")
        let long2 = UKMarqueeLabel("An equally long artist name that also overflows the available width of the row")
        long.accessibilityIdentifier = "fst.uikit.gallery.marquee.long"
        for marquee in [short, long, long2] { marquee.syncGroup = group }
        let song = UKSongHeaderTextView(
            title: "Song Title That Is Long Enough To Scroll Across The Row", artist: "Artist Name That Is Also Quite Long Indeed",
            titleFont: UKFont.font(.title3, weight: .bold), spacing: 4, details: [UKSongBoardLine(instrument: .lead, text: "Lead Guitar, Rank 1,234")]
        )
        let all = UIStackView(arrangedSubviews: [short, long, long2, song])
        all.axis = .vertical
        all.spacing = 6
        add("Marquee", all, id: "marquee")
    }

    private func addAccordions() {
        let accordion = UKAccordionView<Bool>(nil) { _ in
            let label = UKLabel("Accordion content opens, then fades in.", style: .body)
            label.accessibilityIdentifier = "fst.uikit.gallery.accordion.content"
            return label
        }
        self.accordion = accordion
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Toggle accordion"
        configuration.baseBackgroundColor = UKAccentText.prominentFill
        let toggle = UIButton(configuration: configuration)
        toggle.accessibilityIdentifier = "fst.uikit.gallery.accordion.toggle"
        toggle.addAction(UIAction { [weak accordion] _ in
            guard let accordion else { return }
            accordion.follow(accordion.state.target == nil ? true : nil)
        }, for: .primaryActionTriggered)
        let disclosure = UKDisclosureGroupView(
            label: UKLabel("Disclosure group", style: .body), body: UKLabel("Disclosed body text.", style: .body),
            identifier: "fst.uikit.gallery.disclosure"
        )
        let all = UIStackView(arrangedSubviews: [toggle, accordion, disclosure])
        all.axis = .vertical
        all.spacing = 8
        all.alignment = .fill
        add("Accordion", all, id: "accordion")
    }

    private func addStates() {
        let empty = UKEmptyStateView(
            "No Songs", systemImage: "music.note", subtitle: "Try a different filter.", placement: .inline,
            identifier: "fst.uikit.gallery.empty"
        )
        let combined = UKEmptyStateView(
            "No Results", subtitle: "Search for a song, artist or player.", placement: .inline, reading: .combined,
            identifier: "fst.uikit.gallery.empty.combined"
        )
        let loadingStack = UIStackView(arrangedSubviews: [
            UKLoadingView(), UKLoadingView(placement: .inline, status: "Loading songs"),
        ])
        loadingStack.axis = .horizontal
        loadingStack.spacing = 24
        loadingStack.alignment = .center
        let inline = UKServiceStatusInlineView(.offline, scope: "gallery", fallbackTitle: "Offline") {}
        let full = UKServiceStatusView(.scrapeInProgress(retryAfter: 90), title: "Songs", scope: "gallery") {}
        full.heightAnchor.constraint(equalToConstant: 320).isActive = true
        let fresh = UKFreshnessDisclosureView(message: "Showing scores from the last publication.", symbol: "clock")
        let banner = UKRefreshErrorBanner(message: "The network connection was lost.")
        let all = UIStackView(arrangedSubviews: [empty, combined, loadingStack, inline, full, fresh, banner])
        all.axis = .vertical
        all.spacing = 12
        add("Common states", all, id: "states")
    }

    private func addTitles() {
        let header = UKInstrumentPageTitleView(
            instrument: .lead, title: "Lead Guitar", subtitle: "Rank 12", subtitleInstrument: .lead, style: .header,
            identifier: "fst.uikit.gallery.title.header"
        )
        let pinned = UKInstrumentPageTitleView(
            instrument: .bass, title: "Bass Leaderboard", subtitle: "Top 100", subtitleInstrument: nil, style: .pinned,
            identifier: "fst.uikit.gallery.title.pinned"
        )
        let multi = UKInstrumentPageTitleView(
            instruments: [.lead, .bass, .drums], title: "All Instruments", style: .header, identifier: "fst.uikit.gallery.title.multi"
        )
        let slot = UKLeaderboardColumnSlot(template: "88,888", content: UKLabel("12", style: .body, weight: .bold, monospacedDigit: true))
        let all = UIStackView(arrangedSubviews: [header, pinned, multi, slot])
        all.axis = .vertical
        all.spacing = 12
        all.alignment = .leading
        add("Page titles and column slot", all, id: "titles")
    }

    private func addCarouselAndFades() {
        let carousel = UKHorizontalCarouselView(title: "Gallery Cards", count: 5, minimumCardWidth: 220) { index in
            let card = UKCardView(cornerRadius: 16)
            card.embed(UKLabel("Card \(index + 1)", style: .headline), insets: UIEdgeInsets(top: 24, left: 16, bottom: 24, right: 16))
            return card
        }
        add("Horizontal carousel", carousel, id: "carousel")
        let list = UIScrollView()
        list.translatesAutoresizingMaskIntoConstraints = false
        let rows = UIStackView(arrangedSubviews: (1...12).map { UKLabel("Faded row \($0)", style: .body) })
        rows.axis = .vertical
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false
        list.addSubview(rows)
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: host.leadingAnchor), list.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            list.topAnchor.constraint(equalTo: host.topAnchor), list.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: list.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: list.contentLayoutGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: list.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: list.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: list.frameLayoutGuide.widthAnchor),
            host.heightAnchor.constraint(equalToConstant: 160),
        ])
        add("Bottom chrome fade", host, id: "fade")
        bottomFade = UKBottomChromeFade(maskedView: host, scrollView: list)
        bottomFadeHost = host
    }

    private var bottomFade: UKBottomChromeFade?
    private weak var bottomFadeHost: UIView?

    private func addSheetButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Open sheet"
        configuration.baseBackgroundColor = UKAccentText.prominentFill
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "fst.uikit.gallery.sheet.open"
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let content = UKGallerySheetContent()
            UKSheet.present(
                content, from: self, title: "Sheet", closeIdentifier: "fst.uikit.gallery.sheet.close", size: .compact
            )
        }, for: .primaryActionTriggered)
        add("Sheet", button, id: "sheet")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let host = bottomFadeHost { bottomFade?.chromeTop = host.bounds.height - 1 }
    }
}

/// Sheet content for the gallery: a list that scrolls under the transparent header.
private final class UKGallerySheetContent: UIViewController, UKModalScrollProviding {
    private let scroll = UIScrollView()
    var ukModalScrollView: UIScrollView? { scroll }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView(arrangedSubviews: (1...30).map { UKLabel("Sheet row \($0)", style: .body) })
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        view.accessibilityIdentifier = "fst.uikit.gallery.sheet.content"
    }
}
#endif
