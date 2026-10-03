import Testing
@testable import FestivalUI

// MARK: - Identity notice (issue #97)

// The avatar/name card that used to hold these notices is gone; the notices card now
// shows only while a pause reason (or an action error) applies.

@Suite("Player profile identity notice")
struct PlayerProfileIdentityNoticeTests {
    @Test("A selected player never shows a pause notice")
    func selectedShowsNothing() {
        #expect(PlayerProfileIdentityNotice.notice(
            isSelected: true, payloadPublicationId: nil, sessionPublicationId: 7
        ) == nil)
        #expect(PlayerProfileIdentityNotice.notice(
            isSelected: true, payloadPublicationId: 6, sessionPublicationId: 7
        ) == nil)
    }

    @Test("A read without a verified publication pauses selection")
    func unverified() {
        let notice = PlayerProfileIdentityNotice.notice(
            isSelected: false, payloadPublicationId: nil, sessionPublicationId: 7
        )
        #expect(notice == .unverified)
        #expect(notice?.accessibilityIdentifier == "fst.player.unverified")
        #expect(notice?.message == "These scores have no verified publication. Selection is paused.")
    }

    @Test("A read from another publication pauses selection")
    func publicationChanged() {
        let notice = PlayerProfileIdentityNotice.notice(
            isSelected: false, payloadPublicationId: 6, sessionPublicationId: 7
        )
        #expect(notice == .publicationChanged)
        #expect(notice?.accessibilityIdentifier == "fst.player.preview-changed")
        #expect(notice?.message == "Published scores changed. Reload this page before selecting.")
        #expect(PlayerProfileIdentityNotice.notice(
            isSelected: false, payloadPublicationId: 6, sessionPublicationId: nil
        ) == .publicationChanged)
    }

    @Test("A matching publication shows no notice, so the page starts with its content")
    func matchingShowsNothing() {
        #expect(PlayerProfileIdentityNotice.notice(
            isSelected: false, payloadPublicationId: 7, sessionPublicationId: 7
        ) == nil)
    }
}
