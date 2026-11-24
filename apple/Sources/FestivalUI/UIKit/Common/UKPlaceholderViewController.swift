#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Placeholder

/// A screen not ported to UIKit yet: the page title over the shared background and a
/// short note, so the shell and navigation can be exercised before every lane lands.
final class UKPlaceholderViewController: UIViewController {
    private let context: UKContext

    /// Creates a placeholder.
    ///
    /// - Parameters:
    ///   - title: The page title.
    ///   - context: The screen's context.
    init(title: String, context: UKContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        navigationItem.largeTitleDisplayMode = .always
        let label = UILabel()
        label.text = "Not ported to UIKit yet"
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = BrandUIColors.textPrimary
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "fst.uikit.placeholder"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
        ])
    }
}
#endif
