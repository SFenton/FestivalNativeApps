#if os(iOS) && DEBUG
import FestivalCore
import UIKit

// MARK: - Simulated Duo window readout

/// The UIKit counterpart of `DebugDuoWindowRemote.Readout`: a tiny label UI tests read
/// (`fst.shell.debug.duo-window`) to confirm the simulated iPhone Duo window and the
/// layout the shell resolved for it. Present only when `FST_DEBUG_DUO_WINDOW_REMOTE=1`.
final class UKDebugDuoWindowReadout: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 6)
        textColor = .systemYellow
        isUserInteractionEnabled = false
        accessibilityIdentifier = "fst.shell.debug.duo-window"
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Show the applied window and resolved layout, in the SwiftUI readout's format.
    ///
    /// - Parameters:
    ///   - window: The simulated window, or nil to hide the readout.
    ///   - layout: The layout resolved for it.
    func show(_ window: DebugDuoWindow?, layout: DeviceLayout) {
        guard let window else {
            isHidden = true
            return
        }
        let fold = layout.splitHinge.map { " fold=\(Int($0.midX.rounded()))" } ?? ""
        text = "\(window.rawValue) width=\(layout.widthClass) chrome=\(String(describing: layout.sectionChrome)) "
            + "regularSet=\(layout.usesRegularSectionSet)\(fold)"
        accessibilityLabel = text
        isHidden = false
    }
}

extension UKRootViewController {
    /// Start the simulated-window switch, apply its size classes to this root (the window
    /// may not hold it yet), follow each switch, and pin the readout bottom-leading.
    func installDebugDuoWindow() {
        guard DebugDuoWindowRemote.isEnabled else { return }
        DebugDuoWindowRemote.shared.start()
        let readout = UKDebugDuoWindowReadout()
        view.addSubview(readout)
        NSLayoutConstraint.activate([
            readout.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            readout.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
        ])
        duoReadout = readout
        observations.observe { [weak self] in
            // Track only the window; the layout pass runs untracked on the next turn.
            let window = DebugDuoWindowRemote.shared.window
            DispatchQueue.main.async { self?.applyDebugDuoWindow(window) }
        }
    }

    private func applyDebugDuoWindow(_ window: DebugDuoWindow?) {
        if let window {
            traitOverrides.horizontalSizeClass = window.widthClass == .regular ? .regular : .compact
            traitOverrides.verticalSizeClass = .regular
        }
        refreshLayout(initial: false)
        refreshDebugDuoWindowReadout()
    }

    /// Rewrite the readout from the current layout; a no-op without the switch.
    func refreshDebugDuoWindowReadout() {
        guard let readout = duoReadout as? UKDebugDuoWindowReadout else { return }
        readout.show(DebugDuoWindowRemote.shared.window, layout: layout)
        view.bringSubviewToFront(readout)
    }
}
#endif
