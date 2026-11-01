#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Privacy policy

/// The policy column: routes a tap to the link under the finger. The labels themselves take no
/// touches, so each paragraph stays plain static text.
@MainActor
final class UKPolicyColumn: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        func walk(_ view: UIView) {
            if let label = view as? UKLinkLabel, !label.links.isEmpty {
                let point = recognizer.location(in: label)
                if label.bounds.contains(point) { label.openLink(at: point) }
            }
            view.subviews.forEach(walk)
        }
        walk(self)
    }
}

/// The policy's effective date and sections (``PrivacyPolicyContent``), shared by the Privacy
/// Policy sheet and the list/detail Settings' inline pane. The caller scrolls and pads it.
@MainActor
enum UKPrivacyPolicyContent {
    /// Builds the content column.
    ///
    /// - Parameter policy: The policy to show.
    /// - Returns: A vertical stack of the date and sections.
    static func make(policy: PrivacyPolicy = .current) -> UIStackView {
        let column = UKPolicyColumn()
        column.axis = .vertical
        column.spacing = 24
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        let date = UKLabel(policy.effectiveDateText, style: .subheadline, weight: .semibold)
        date.accessibilityIdentifier = "fst.privacy-policy.effective-date"
        column.addArrangedSubview(date)
        for section in policy.sections {
            let block = UIStackView()
            block.axis = .vertical
            block.spacing = 10
            let heading = UKLabel(section.title, style: .headline).asHeader()
            heading.accessibilityIdentifier = "fst.privacy-policy.section.\(section.id)"
            block.addArrangedSubview(heading)
            for item in section.blocks {
                switch item {
                case let .paragraph(text):
                    block.addArrangedSubview(textView(PrivacyPolicy.styledText(text, boldLead: false)))
                case let .bullets(items):
                    let list = UIStackView()
                    list.axis = .vertical
                    list.spacing = 8
                    for bullet in items {
                        let row = UIStackView()
                        row.axis = .horizontal
                        row.alignment = .firstBaseline
                        row.spacing = 8
                        let dot = UKLabel("\u{2022}", style: .body)
                        dot.isAccessibilityElement = false
                        dot.setContentHuggingPriority(.required, for: .horizontal)
                        row.addArrangedSubview(dot)
                        row.addArrangedSubview(textView(PrivacyPolicy.styledText(bullet, boldLead: true)))
                        list.addArrangedSubview(row)
                    }
                    block.addArrangedSubview(list)
                }
            }
            column.addArrangedSubview(block)
        }
        return column
    }

    private static func textView(_ text: AttributedString) -> UILabel {
        let label = UKLinkLabel()
        let body = UKFont.font(.body)
        let bold = UKFont.font(.body, weight: .bold)
        let result = NSMutableAttributedString()
        var links: [(NSRange, URL)] = []
        for run in text.runs {
            let piece = NSMutableAttributedString(string: String(text[run.range].characters))
            let strong = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            let whole = NSRange(location: 0, length: piece.length)
            piece.addAttributes([.font: strong ? bold : body, .foregroundColor: BrandUIColors.textPrimary], range: whole)
            if let link = run.link {
                piece.addAttributes([.foregroundColor: BrandUIColors.accentBlue, .underlineStyle: NSUnderlineStyle.single.rawValue], range: whole)
                links.append((NSRange(location: result.length, length: piece.length), link))
            }
            result.append(piece)
        }
        label.attributedText = result
        label.links = links
        return label
    }
}

/// A wrapping label whose links open when tapped: static text to accessibility (the policy's
/// paragraphs read as text), with the link under the finger found by layout.
@MainActor
final class UKLinkLabel: UILabel {
    /// The tappable ranges. Kept apart from the text so the label stays plain static text.
    var links: [(NSRange, URL)] = []

    init() {
        super.init(frame: .zero)
        numberOfLines = 0
        adjustsFontForContentSizeCategory = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Opens the link at a point of the label, if there is one.
    ///
    /// - Parameter point: In the label's coordinates.
    func openLink(at point: CGPoint) {
        guard let attributed = attributedText, attributed.length > 0 else { return }
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: bounds.size)
        container.lineFragmentPadding = 0
        container.lineBreakMode = lineBreakMode
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let index = layout.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard let link = links.first(where: { NSLocationInRange(index, $0.0) })?.1 else { return }
        UIApplication.shared.open(link)
    }
}

/// The Privacy Policy sheet's page (``PrivacyPolicySheet``): the policy in a scroll view, a
/// 680 pt column with 20 pt side padding.
@MainActor
final class UKPrivacyPolicyViewController: UIViewController, UKModalScrollProviding {
    private let scrollView = UIScrollView()
    private let policy: PrivacyPolicy
    var ukModalScrollView: UIScrollView? { scrollView }

    /// Creates the page.
    ///
    /// - Parameter policy: The policy to show.
    init(policy: PrivacyPolicy = .current) {
        self.policy = policy
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "fst.privacy-policy.content"
        view.addSubview(scrollView)
        let content = UKPrivacyPolicyContent.make(policy: policy)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        UKSettingsScrollPage.install(content, in: scrollView, side: 20, top: 8, bottom: 32)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if UKSettingsScrollPage.remeasureLabels(in: scrollView) { scrollView.setNeedsLayout() }
    }

    /// Presents the policy as a large sheet.
    ///
    /// - Parameter presenter: The controller to present from.
    static func present(from presenter: UIViewController) {
        UKSheet.present(
            UKPrivacyPolicyViewController(), from: presenter, title: PrivacyPolicy.current.title,
            closeIdentifier: "fst.privacy-policy.close", size: .large
        )
    }
}

// MARK: - Licenses

/// `/settings/licenses` (``LicensesScreen``): one card listing this app's actual third-party
/// software, each row opening its full license text in a sheet.
@MainActor
final class UKLicensesViewController: UKSettingsScrollPage {
    private let entries: [SoftwareLicense]
    private lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The page's context.
    ///   - entries: Rows to list; the app's real manifest by default.
    init(context: UKContext, entries: [SoftwareLicense] = LicenseManifest.thirdPartySoftware) {
        self.entries = entries
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        ukSetPageTitle("Licenses")
        let section = UKGroupSectionView("Third-Party Software", subtitle: "Open source packages bundled in this build.")
        if entries.isEmpty {
            let note = UKFootnoteLabel(
                "This build has no external Swift package dependencies — every module (FestivalCore, "
                    + "FestivalDesign, FestivalUI) is first-party. This list updates the day one is added."
            )
            note.accessibilityIdentifier = "fst.licenses.empty"
            section.setRows([note])
        } else {
            section.setRows(entries.map(licenseRow))
        }
        setCards([section])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        background.viewWillAppear()
        ukInstallAccountItems()
        if let section = column.arrangedSubviews.first, section.alpha == 1 {
            UKFadeIn.fadeIn(section, staggerIndex: 0)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
    }

    private func licenseRow(_ entry: SoftwareLicense) -> UIView {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        let name = UKLabel(entry.name, style: .body, weight: .semibold)
        let role = UKLabel(entry.versionOrRole, style: .footnote)
        let texts = UIStackView(arrangedSubviews: [name, role])
        texts.axis = .vertical
        texts.spacing = 2
        let type = UKLabel(entry.licenseType, style: .caption1, weight: .semibold, lines: 1)
        let pill = UIView()
        pill.backgroundColor = BrandUIColors.surfaceFrosted
        pill.layer.cornerRadius = 12
        type.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(type)
        NSLayoutConstraint.activate([
            type.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8), type.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            type.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4), type.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
        ])
        pill.setContentHuggingPriority(.required, for: .horizontal)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [texts, pill, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor), row.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            row.topAnchor.constraint(equalTo: control.topAnchor), row.bottomAnchor.constraint(equalTo: control.bottomAnchor),
        ])
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = "\(entry.name), \(entry.versionOrRole), \(entry.licenseType)"
        control.accessibilityHint = "Shows the full license text"
        control.accessibilityIdentifier = "fst.licenses.\(entry.id)"
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let self else { return }
            UKSheet.present(
                UKLicenseDetailViewController(entry: entry), from: self, title: "\(entry.name) · \(entry.licenseType)",
                closeIdentifier: "fst.licenses.close", size: .large
            )
            control?.accessibilityViewIsModal = false
        }, for: .touchUpInside)
        return control
    }
}

/// Full license text for one entry (``LicenseDetailSheet``).
@MainActor
final class UKLicenseDetailViewController: UIViewController, UKModalScrollProviding {
    private let entry: SoftwareLicense
    private let text = UITextView()
    var ukModalScrollView: UIScrollView? { text }

    /// Creates the page.
    ///
    /// - Parameter entry: The license to show.
    init(entry: SoftwareLicense) {
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        text.isEditable = false
        text.backgroundColor = .clear
        text.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        text.adjustsFontForContentSizeCategory = true
        text.translatesAutoresizingMaskIntoConstraints = false
        let mono = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
        )
        let result = NSMutableAttributedString()
        if let url = entry.url {
            result.append(NSAttributedString(string: url.absoluteString + "\n\n", attributes: [
                .font: UKFont.font(.footnote), .link: url,
            ]))
        }
        result.append(NSAttributedString(string: entry.licenseText, attributes: [
            .font: mono, .foregroundColor: BrandUIColors.textPrimary,
        ]))
        text.attributedText = result
        text.linkTextAttributes = [.foregroundColor: BrandUIColors.accentBlue]
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor), text.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            text.topAnchor.constraint(equalTo: view.topAnchor), text.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
#endif
