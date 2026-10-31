#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Navigation inside a sheet

/// What a page pushed inside a sheet asks of its host (``UKNavigating``): pushes stay in
/// the sheet's own navigation stack, as the SwiftUI Find Rival sheet pushes inside its own
/// `NavigationStack`. Section and shell commands do nothing in a sheet.
@MainActor
final class UKSheetPathNavigator: UKNavigating {
    private weak var navigation: UINavigationController?
    private let context: UKContext

    /// Creates the navigator.
    ///
    /// - Parameters:
    ///   - navigation: The sheet's stack.
    ///   - context: The sheet's context; pages pushed get a copy that names this navigator.
    init(navigation: UINavigationController, context: UKContext) {
        self.navigation = navigation
        self.context = context
    }

    private func page(for route: AppRoute) -> UIViewController {
        UKRouteDestination.make(route, context: context.with { $0.navigator = self; $0.surface = .sheet })
    }

    func push(_ route: AppRoute) { navigation?.pushViewController(page(for: route), animated: true) }
    func pop() { navigation?.popViewController(animated: true) }

    func replaceTop(with route: AppRoute) {
        guard let navigation else { return }
        var stack = navigation.viewControllers
        guard !stack.isEmpty else { return }
        stack[stack.count - 1] = page(for: route)
        navigation.setViewControllers(stack, animated: false)
    }

    func select(_ section: FestivalSection) {}
    func openDrawer() {}
    func presentProfile() {}
}

// MARK: - Find Rival

/// "Find Rival" search sheet (``FindRivalSheet``): a player search over the public account
/// search (`GET /api/account/search`), debounced 250 ms, whose chosen result pushes that
/// player's Rival Detail inside the sheet with no scope (Settings derive it).
final class UKFindRivalViewController: UIViewController, UITextFieldDelegate, UKModalScrollProviding {
    private enum Phase {
        case enterQuery
        case loading
        case results([PlayerSearchResult])
        case failed(String)
    }

    private let context: UKContext
    private let scrollView = UIScrollView()
    private let resultsCard = UIView()
    private let field = UITextField()
    private let clearButton = UIButton(type: .system)
    private var phase = Phase.enterQuery
    private var searchTask: Task<Void, Never>?
    private var retry = 0
    private var navigator: UKSheetPathNavigator?

    var ukModalScrollView: UIScrollView? { scrollView }

    /// Creates the sheet's page.
    ///
    /// - Parameter context: The sheet's context.
    init(context: UKContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { searchTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrandUIColors.appBackground
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.ukPin(to: view)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        stack.addArrangedSubview(UKSectionHeaderView("Find a Rival"))
        stack.addArrangedSubview(makeSearchCard())
        resultsCard.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        resultsCard.layer.cornerRadius = 10
        resultsCard.layer.cornerCurve = .continuous
        resultsCard.clipsToBounds = true
        stack.addArrangedSubview(resultsCard)
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if navigator == nil, let navigation = navigationController {
            navigator = UKSheetPathNavigator(navigation: navigation, context: context)
        }
        if case .enterQuery = phase, field.text?.isEmpty ?? true { field.becomeFirstResponder() }
    }

    // MARK: Search field

    private func makeSearchCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        let capsule = UIView()
        capsule.backgroundColor = BrandUIColors.appBackground
        capsule.layer.cornerCurve = .continuous
        capsule.translatesAutoresizingMaskIntoConstraints = false
        let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        magnifier.tintColor = BrandUIColors.textPrimary
        magnifier.isAccessibilityElement = false
        field.attributedPlaceholder = NSAttributedString(
            string: "Find Rival", attributes: [.foregroundColor: BrandUIColors.textPrimary.withAlphaComponent(0.8)]
        )
        field.textColor = BrandUIColors.textPrimary
        field.font = UKFont.font(.body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = self
        field.accessibilityLabel = "Find Rival"
        field.accessibilityIdentifier = "fst.rivals.findRival.search"
        field.addAction(UIAction { [weak self] _ in self?.queryChanged() }, for: .editingChanged)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = BrandUIColors.textPrimary
        clearButton.accessibilityLabel = "Clear Search"
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in
            self?.field.text = ""
            self?.queryChanged()
        }, for: .primaryActionTriggered)
        let row = UIStackView(arrangedSubviews: [magnifier, field, clearButton])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(row)
        card.addSubview(capsule)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -6),
            capsule.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            capsule.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            capsule.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            capsule.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            capsule.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        capsule.layer.cornerRadius = 22
        return card
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func queryChanged() {
        clearButton.isHidden = (field.text ?? "").isEmpty
        phase = .enterQuery
        render()
        scheduleSearch()
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        phase = .loading
        render()
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let response = try await self.context.session.client().searchPlayers(query: term)
                try Task.checkCancellation()
                self.phase = .results(response.results)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
            self.render()
        }
    }

    // MARK: Results

    private func render() {
        resultsCard.subviews.forEach { $0.removeFromSuperview() }
        let content: UIView
        switch phase {
        case .enterQuery:
            let label = UKLabel("Enter at least two characters to search for a rival.", alignment: .center)
            content = Self.centred(label, minHeight: max(view.bounds.height * 0.55, 180))
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Searching Players")
            content = Self.centred(loading, minHeight: 0, vertical: 32)
        case let .results(results):
            if results.isEmpty {
                let label = UKLabel("No player results were returned. Try another search or Retry.", alignment: .center)
                content = Self.stacked([label, retryButton()])
            } else {
                content = resultRows(results)
            }
        case let .failed(message):
            let symbol = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
            symbol.tintColor = BrandUIColors.gold
            symbol.setContentHuggingPriority(.required, for: .horizontal)
            let text = UKLabel("Player search unavailable: \(message)", color: BrandUIColors.gold)
            let line = UIStackView(arrangedSubviews: [symbol, text])
            line.spacing = 8
            line.alignment = .top
            content = Self.stacked([line, retryButton()], padding: 16)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        resultsCard.addSubview(content)
        content.ukPin(to: resultsCard)
    }

    private func retryButton() -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = BrandUIColors.textPrimary
        configuration.title = "Retry Search"
        let button = UIButton(configuration: configuration)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.retry += 1
            self?.scheduleSearch()
        }, for: .primaryActionTriggered)
        return button
    }

    private func resultRows(_ results: [PlayerSearchResult]) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        for (index, player) in results.enumerated() {
            if index > 0 { stack.addArrangedSubview(UKHairlineView()) }
            var configuration = UIButton.Configuration.plain()
            configuration.title = player.displayName
            configuration.image = UIImage(systemName: "person.crop.circle")
            configuration.imagePadding = 8
            configuration.baseForegroundColor = BrandUIColors.textPrimary
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.accessibilityLabel = "View rivalry with \(player.displayName)"
            button.accessibilityIdentifier = "fst.rivals.findRival.result.\(player.accountId)"
            button.addAction(UIAction { [weak self] _ in
                self?.navigator?.push(.rivalDetail(rivalId: player.accountId, name: player.displayName, scope: nil))
            }, for: .primaryActionTriggered)
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private static func centred(_ view: UIView, minHeight: CGFloat, vertical: CGFloat = 16) -> UIView {
        let holder = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(view)
        var constraints = [
            view.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -16),
            view.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            holder.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor, constant: vertical * 2),
        ]
        if minHeight > 0 { constraints.append(holder.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)) }
        NSLayoutConstraint.activate(constraints)
        return holder
    }

    private static func stacked(_ views: [UIView], padding: CGFloat = 16) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        return stack
    }
}
#endif
