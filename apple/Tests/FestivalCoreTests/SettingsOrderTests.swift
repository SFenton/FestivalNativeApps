import Testing
@testable import FestivalCore

// MARK: - SettingsOrder codec

@Test func settingsOrderRoundTripsAFullOrder() {
    let order: [PathColumnKey] = [.score, .note, .od, .beat, .time]
    let raw = SettingsOrder.encode(order)
    #expect(raw == "score,note,od,beat,time")
    #expect(SettingsOrder.decode(raw) == order)
}

@Test func settingsOrderAppendsCasesMissingFromStoredData() {
    // Simulates a value saved before a new case (`.od`) existed.
    let raw = "score,note,beat,time"
    let decoded: [PathColumnKey] = SettingsOrder.decode(raw)
    #expect(decoded == [.score, .note, .beat, .time, .od])
}

@Test func settingsOrderDropsUnknownAndDuplicateTokens() {
    let raw = "score,score,bogus,note"
    let decoded: [PathColumnKey] = SettingsOrder.decode(raw)
    #expect(decoded.filter { $0 == .score }.count == 1)
    #expect(Set(decoded) == Set(PathColumnKey.allCases))
    #expect(decoded.count == PathColumnKey.allCases.count)
}

@Test func settingsOrderDefaultsFromAnEmptyString() {
    let decoded: [PathColumnKey] = SettingsOrder.decode("")
    #expect(Set(decoded) == Set(PathColumnKey.allCases))
}

@Test func pathColumnKeyLabelsAreTitleCase() {
    for key in PathColumnKey.allCases {
        #expect(key.label.first?.isUppercase == true)
    }
}
