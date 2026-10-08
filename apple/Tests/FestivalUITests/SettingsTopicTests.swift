import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Settings topics (issue #371)

/// The owner's list of chevron rows, plus the two reviewed additions (Song Row Visual
/// Order and CHOpt Paths), in the single page's order.
@Test func settingsTopicsCoverTheOwnersList() {
    #expect(SettingsTopic.allCases == [
        .songRowOrder, .paths, .accessibility, .itemShop, .instruments, .metadata,
        .version, .serviceInfo, .firstRun, .privacyPolicy,
    ])
    #expect(SettingsTopic.allCases.filter(\.isAppSettingsRow) == [.songRowOrder, .paths])
}

/// Row titles match the single page's section titles; page titles stay short enough for
/// a half pane's large title.
@Test func settingsTopicTitles() {
    #expect(SettingsTopic.instruments.rowTitle == "Show Instruments")
    #expect(SettingsTopic.metadata.rowTitle == "Show Instrument Metadata")
    #expect(SettingsTopic.version.rowTitle == "Festival Score Tracker Version")
    #expect(SettingsTopic.serviceInfo.rowTitle == ServiceInfoText.title)
    #expect(SettingsTopic.version.pageTitle == "Version")
    for topic in SettingsTopic.allCases {
        #expect(topic.pageTitle.count <= 21, "\(topic)")
        #expect(!topic.subtitle.isEmpty, "\(topic)")
    }
}

/// Identifiers are unique and Privacy Policy keeps its single-page row's identifier.
@Test func settingsTopicIdentifiers() {
    let ids = SettingsTopic.allCases.map(\.accessibilityIdentifier)
    #expect(Set(ids).count == ids.count)
    #expect(SettingsTopic.privacyPolicy.accessibilityIdentifier == "fst.settings.privacy-policy")
    #expect(SettingsTopic.instruments.accessibilityIdentifier == "fst.settings.topic.instruments")
}

/// Song Row Visual Order is listed only while Independent Visual Order is on; an open
/// topic whose row leaves the list closes to the placeholder (`split-panes` R6, #372).
@Test func settingsSongRowOrderTopicFollowsItsSwitch() {
    #expect(SettingsTopic.songRowOrder.isListed(independentVisualOrder: true))
    #expect(!SettingsTopic.songRowOrder.isListed(independentVisualOrder: false))
    for topic in SettingsTopic.allCases where topic != .songRowOrder {
        #expect(topic.isListed(independentVisualOrder: false), "\(topic)")
    }
}
