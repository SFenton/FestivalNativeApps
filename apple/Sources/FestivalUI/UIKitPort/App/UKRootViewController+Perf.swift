#if os(iOS) && DEBUG
import UIKit

// MARK: - Performance probes

extension UKRootViewController {
    private var perfTopController: UIViewController? {
        guard let stack = stacks[selected] else { return nil }
        return stack.trailing?.visibleViewController ?? stack.leading.visibleViewController
    }

    func perfPresentSongsFilter() {
        select(.songs)
        (perfTopController as? UKSongsViewController)?.presentFilter()
    }

    func perfPresentSongPaths() {
        (perfTopController as? UKSongDetailViewController)?.perfPresentPaths()
    }

    func perfPresentSuggestionsFilter() {
        select(.suggestions)
        (perfTopController as? UKSuggestionsViewController)?.perfPresentFilter()
    }

    func perfPresentFeedback() {
        select(.settings)
        (perfTopController as? UKSettingsViewController)?.perfPresentFeedback()
    }

    func perfPresentPrivacyPolicy() {
        select(.settings)
        (perfTopController as? UKSettingsViewController)?.perfPresentPrivacyPolicy()
    }

    var perfAccordionIsOpen: Bool {
        (perfTopController as? UKSettingsViewController)?.perfAccordionIsOpen ?? false
    }

    func perfToggleAccordion() {
        select(.settings)
        (perfTopController as? UKSettingsViewController)?.perfToggleAccordion()
    }

    func perfRestoreAccordion() {
        (perfTopController as? UKSettingsViewController)?.perfRestoreAccordion()
    }
}
#endif
