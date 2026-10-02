import Foundation
import Testing
@testable import FestivalCore

private struct Key: Equatable, Sendable {
    var instrument: String
    var accountId: String?
    var publicationRevision: Int
}

@Test func reappearanceLoadGateLoadsUntilAKeySucceeds() {
    var gate = ReappearanceLoadGate<Key>()
    let lead = Key(instrument: "Solo_Guitar", accountId: "a", publicationRevision: 0)
    #expect(gate.loadedKey == nil)
    #expect(gate.needsLoad(for: lead))

    // A failed or cancelled read never marks the gate, so Back retries it.
    #expect(gate.needsLoad(for: lead))

    gate.markLoaded(lead)
    #expect(gate.loadedKey == lead)
    // Back from View Full Leaderboard reappears with the same key: keep the rows.
    #expect(!gate.needsLoad(for: lead))
}

@Test func reappearanceLoadGateReloadsForAnyChangedKeyPart() {
    var gate = ReappearanceLoadGate<Key>()
    let loaded = Key(instrument: "Solo_Guitar", accountId: "a", publicationRevision: 0)
    gate.markLoaded(loaded)

    var otherInstrument = loaded
    otherInstrument.instrument = "Solo_Bass"
    var otherAccount = loaded
    otherAccount.accountId = "b"
    var deselected = loaded
    deselected.accountId = nil
    var newPublication = loaded
    newPublication.publicationRevision = 1

    for key in [otherInstrument, otherAccount, deselected, newPublication] {
        #expect(gate.needsLoad(for: key))
    }
    gate.markLoaded(newPublication)
    #expect(!gate.needsLoad(for: newPublication))
    #expect(gate.needsLoad(for: loaded))
}

@Test func reappearanceLoadGateResetForcesTheNextLoad() {
    var gate = ReappearanceLoadGate<String>()
    gate.markLoaded("Solo_Guitar")
    #expect(!gate.needsLoad(for: "Solo_Guitar"))
    gate.reset()
    #expect(gate.loadedKey == nil)
    #expect(gate.needsLoad(for: "Solo_Guitar"))
    #expect(gate == ReappearanceLoadGate<String>())
}
