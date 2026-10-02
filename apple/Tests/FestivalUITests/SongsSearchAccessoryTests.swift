import Testing
@testable import FestivalUI

// MARK: - SongsSearchAccessory (issue #42)

/// The accessory button shows the query once one is entered, otherwise the prompt.
@Test(arguments: [
    ("", nil),
    ("   ", nil),
    ("muse", "muse"),
    (" muse ", " muse "),
] as [(String, String?)])
func accessoryShowsTheQueryOrThePrompt(query: String, expected: String?) {
    #expect(SongsSearchAccessory.displayedQuery(query) == expected)
}

/// Clear appears for any text, so whitespace can be cleared too.
@Test(arguments: [("", false), (" ", true), ("a", true)])
func clearShowsForAnyText(query: String, expected: Bool) {
    #expect(SongsSearchAccessory.showsClear(query) == expected)
}

/// The bar closes only when the field loses focus it had.
@Test(arguments: [
    (false, false, false),
    (false, true, false),
    (true, true, false),
    (true, false, true),
])
func barClosesOnlyWhenFocusIsLost(was: Bool, now: Bool, expected: Bool) {
    #expect(SongsSearchAccessory.closesOnFocusChange(wasFocused: was, isFocused: now) == expected)
}

/// Copy matches the web placeholder and keeps a short inline fallback.
@Test func promptsAndLabel() {
    #expect(SongsSearchAccessory.prompt == "Search songs or artists")
    #expect(SongsSearchAccessory.shortPrompt == "Search")
    #expect(SongsSearchAccessory.accessibilityLabel == "Search Songs")
}
