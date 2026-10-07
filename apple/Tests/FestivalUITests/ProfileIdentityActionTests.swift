import SwiftUI
import Testing
import FestivalDesign
@testable import FestivalUI

// MARK: - ProfileIdentityAction styling

/// The player page's identity action draws one fill in every placement (issue #351):
/// the header button and the iPhone Duo rail item read the same `prominentFill`.
struct ProfileIdentityActionTests {
    @Test func selectAndSwitchShareTheAccentBlueFill() {
        #expect(ProfileIdentityAction.select.prominentFill == AccentText.prominentFill)
        #expect(ProfileIdentityAction.switchTo.prominentFill == AccentText.prominentFill)
        #expect(ProfileIdentityAction.select.prominentFill == ProfileIdentityAction.switchTo.prominentFill)
    }

    @Test func deselectStaysRed() {
        #expect(ProfileIdentityAction.deselect.prominentFill == BrandTokens.statusRed)
        #expect(ProfileIdentityAction.deselect.isDestructive)
    }

    @Test func onlySelectAndSwitchAreProminentPrimaryActions() {
        #expect(ProfileIdentityAction.select.isProminent)
        #expect(ProfileIdentityAction.switchTo.isProminent)
        #expect(!ProfileIdentityAction.deselect.isProminent)
    }
}
