#if os(iOS) && DEBUG
import FestivalCore
import UIKit

/// UIKit-only projection of the native page-command tree for iPad UI tests.
///
/// Every button creates the same `UICommand` payload used by `UKMenuBar`; it does not
/// duplicate page actions or maintain an independent menu state.
@MainActor
final class UKDebugMenuBarMirror: UIView {
    static let identifier = "fst.menu-bar-mirror"

    private weak var root: UKRootViewController?
    private let stack = UIStackView()

    init(root: UKRootViewController) {
        self.root = root
        super.init(frame: .zero)
        accessibilityIdentifier = Self.identifier
        isAccessibilityElement = false
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        layer.cornerRadius = 12
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(commands: [UKPageMenuCommand], blocked: Bool, trace: String?, dispatch: String?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let lookup = flatten(commands)
        addButton("Sort…", id: "sort", source: lookup["sort"], blocked: blocked)
        addButton("Filter…", id: "filter", source: lookup["filter"], blocked: blocked)
        addSubmenu("Rank By", id: "rankBy", source: lookup["rankBy"], blocked: blocked)
        addSubmenu("Instrument", id: "instrument", source: lookup["instrument"], blocked: blocked)
        addSubmenu("Band Size", id: "bandSize", source: lookup["bandSize"], blocked: blocked)
        addButton("as List", id: "asList", source: lookup["asList"], blocked: blocked)
        addButton("as Grid", id: "asGrid", source: lookup["asGrid"], blocked: blocked)
        let identityTitle = lookup["profile.identity"]?.title ?? "Select This Profile"
        addButton(identityTitle, id: "profile.identity", source: lookup["profile.identity"], blocked: blocked)
        addButton("View Rival's Profile", id: "profile.rival", source: lookup["profile.rival"], blocked: blocked)
        addButton("Find Rival…", id: "findRival", source: lookup["findRival"], blocked: blocked)
        if let trace {
            let evidence = UILabel()
            evidence.text = "Native menu trace"
            evidence.accessibilityLabel = "Native menu trace"
            evidence.accessibilityIdentifier = "fst.menu-bar-trace"
            evidence.accessibilityValue = dispatch.map {
                "{\"dispatch\":\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\",\"page\":\(trace)}"
            } ?? trace
            evidence.numberOfLines = 0
            evidence.isAccessibilityElement = true
            stack.addArrangedSubview(evidence)
        }
    }

    private func addSubmenu(
        _ title: String, id: String, source: UKPageMenuCommand?, blocked: Bool
    ) {
        addButton(title, id: id, source: source, blocked: blocked, parent: true)
        let children = source?.children ?? (id == "bandSize" ? BandType.allCases.map {
            UKPageMenuCommand(identifier: "bandSize.\($0.rawValue)", title: $0.label)
        } : [])
        for child in children {
            addButton(child.title, id: child.identifier, source: child, blocked: blocked)
        }
    }

    private func addButton(
        _ title: String, id: String, source: UKPageMenuCommand?, blocked: Bool, parent: Bool = false
    ) {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.setTitle(source?.title ?? title, for: .normal)
        button.accessibilityLabel = source?.title ?? title
        button.accessibilityIdentifier = "fst.menu-bar.\(id)"
        button.accessibilityValue = source?.state == .on ? "1" : "0"
        button.isEnabled = parent || (!blocked && source?.isEnabled == true)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }
            let command = UICommand(
                title: button.accessibilityLabel ?? title,
                action: #selector(UKShellCommands.ukPageMenuCommand(_:)),
                propertyList: id
            )
            self.root?.ukPageMenuCommand(command)
        }, for: .primaryActionTriggered)
        stack.addArrangedSubview(button)
    }

    private func flatten(_ commands: [UKPageMenuCommand]) -> [String: UKPageMenuCommand] {
        var result: [String: UKPageMenuCommand] = [:]
        for command in commands {
            result[command.identifier] = command
            for child in flatten(command.children) { result[child.key] = child.value }
        }
        return result
    }
}
#endif
