import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Songs, Detail and solo scores share one scene-owned navigation path.
///
/// On an iPhone Duo inner display the path is shown as the Songs list beside a Song
/// Detail column (`ListDetailStack`); everywhere else it is one stack.
struct SongNavigationRoot: View {
    let session: FestivalSession
    @Binding var path: [AppRoute]
    @Binding var searchText: String
    @Binding var settledSearch: String
    @Binding var selectedInstrument: Instrument?
    @Binding var navigationNotice: String?
    let visibleInstruments: Set<Instrument>
    let highContrast: Bool
    let isVisible: Bool

    /// Retain a shared route and visibility policy across platform navigation.
    ///
    /// - Parameters:
    ///   - session: Shared process-lifetime service and artwork cache.
    ///   - path: Current Songs navigation stack.
    ///   - searchText: Live search entry.
    ///   - settledSearch: Debounced search query.
    ///   - selectedInstrument: Scene-owned chart filter surviving section switches.
    ///   - navigationNotice: Explanation for safe route or filter invalidation.
    ///   - visibleInstruments: Persisted chart visibility.
    ///   - highContrast: Effective system or in-app contrast override.
    ///   - isVisible: False when another tab or a nested route covers Songs.
    init(
        session: FestivalSession, path: Binding<[AppRoute]>,
        searchText: Binding<String>, settledSearch: Binding<String>,
        selectedInstrument: Binding<Instrument?> = .constant(nil),
        navigationNotice: Binding<String?> = .constant(nil),
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        highContrast: Bool = false, isVisible: Bool = true
    ) {
        self.session = session
        _path = path
        _searchText = searchText
        _settledSearch = settledSearch
        _selectedInstrument = selectedInstrument
        _navigationNotice = navigationNotice
        self.visibleInstruments = visibleInstruments
        self.highContrast = highContrast
        self.isVisible = isVisible
    }

    var body: some View {
        ListDetailStack(
            section: .songs, session: session, visibleInstruments: visibleInstruments,
            path: $path, isVisible: isVisible
        ) { rootIsTop in
            SongsScreen(
                session: session, searchText: $searchText, settledSearch: $settledSearch,
                selectedInstrument: $selectedInstrument, navigationNotice: $navigationNotice,
                visibleInstruments: visibleInstruments, highContrast: highContrast,
                isVisible: isVisible && rootIsTop,
                openShop: { path.append(.shop) }
            )
        }
    }
}
