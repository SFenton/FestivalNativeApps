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

    func perfPresentFirstRunCarousel() {
        let slides = FirstRunSettingsSection.replaySlides(.songs)
        let center = session.firstRunCenter
        center.store.resetPage(slides.map(\.id))
        let presentation = UKFirstRunPresentation(
            page: .songs, slides: slides, presenter: perfTopController ?? self, session: session
        ) { [weak self] viewed in
            center.store.markSeen(viewed)
            self?.perfFirstRunPresentation = nil
        }
        guard presentation.admission != .rejected else { return }
        perfFirstRunPresentation = presentation
        presentation.advanceForPerformance()
    }

    func perfStopFirstRunCarousel() {
        perfFirstRunPresentation?.dismissForPerformance()
    }

    var perfFirstRunCarouselReady: Bool {
        guard let presentation = perfFirstRunPresentation else { return false }
        return presentation.isPresented
            && presentation.performanceIsVisible
            && presentation.performancePageIndex > 0
    }

    var perfFirstRunCarouselRestored: Bool {
        perfFirstRunPresentation == nil
    }
}
#endif
