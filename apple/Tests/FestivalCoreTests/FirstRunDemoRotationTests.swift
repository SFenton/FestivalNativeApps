import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

private struct Item: Identifiable, Equatable {
    let id: String
}

private func items(_ count: Int) -> [Item] {
    (0..<count).map { Item(id: "s\($0)") }
}

// MARK: - Timing

@Suite("FirstRunDemoTiming")
struct FirstRunDemoTimingTests {
    @Test("Timing matches the web theme's demo constants")
    func matchesWeb() {
        #expect(FirstRunDemoTiming.swapInterval == .milliseconds(5_000))
        #expect(FirstRunDemoTiming.fadeSeconds == 0.4)
        #expect(FirstRunDemoTiming.fade == .milliseconds(400))
        #expect(FirstRunDemoTiming.staggerSeconds == 0.125)
        #expect(FirstRunDemoTiming.entranceRise == 12)
        #expect(FirstRunDemoTiming.barSelectInterval == .milliseconds(2_500))
        #expect(FirstRunDemoTiming.barSelectFadeSeconds == 0.3)
    }
}

// MARK: - Swap selection

@Suite("FirstRunDemoRotation")
struct FirstRunDemoRotationTests {
    @Test("One row swaps for up to 3 rows, two for up to 6, three beyond", arguments: [
        (0, 0), (1, 1), (3, 1), (4, 2), (6, 2), (7, 3), (20, 3),
    ])
    func swapCount(rows: Int, expected: Int) {
        #expect(FirstRunDemoRotation.swapCount(rowCount: rows) == expected)
    }

    @Test("Swapped indices are distinct, in range, ascending and repeatable")
    func indicesAreWellFormed() {
        for rows in 1...8 {
            for tick in 0..<40 {
                let picked = FirstRunDemoRotation.swapIndices(rowCount: rows, tick: tick)
                #expect(picked.count == FirstRunDemoRotation.swapCount(rowCount: rows))
                #expect(Set(picked).count == picked.count)
                #expect(picked == picked.sorted())
                #expect(picked.allSatisfy { (0..<rows).contains($0) })
                #expect(picked == FirstRunDemoRotation.swapIndices(rowCount: rows, tick: tick))
            }
        }
    }

    @Test("The same rows are not swapped twice in a row when another choice exists")
    func avoidsPreviousSet() {
        for rows in [2, 3, 4, 5] {
            var previous: Set<Int> = []
            for tick in 0..<60 {
                let picked = Set(FirstRunDemoRotation.swapIndices(rowCount: rows, tick: tick, avoiding: previous))
                #expect(picked != previous)
                previous = picked
            }
        }
    }

    @Test("Successive ticks spread swaps across every row")
    func coversEveryRow() {
        var seen = Set<Int>()
        var previous: Set<Int> = []
        for tick in 0..<20 {
            let picked = FirstRunDemoRotation.swapIndices(rowCount: 4, tick: tick, avoiding: previous)
            seen.formUnion(picked)
            previous = Set(picked)
        }
        #expect(seen == [0, 1, 2, 3])
    }

    @Test("A single row always swaps itself")
    func singleRow() {
        #expect(FirstRunDemoRotation.swapIndices(rowCount: 1, tick: 3, avoiding: [0]) == [0])
    }
}

// MARK: - Row rotation

@Suite("FirstRunRowRotation")
struct FirstRunRowRotationTests {
    @Test("The first pool items start visible")
    func initialRows() {
        let rotation = FirstRunRowRotation(pool: items(6), visible: 3)
        #expect(rotation.rows.map(\.id) == ["s0", "s1", "s2"])
        #expect(rotation.canRotate)
    }

    @Test("A pool no larger than the rows cannot rotate")
    func smallPoolDoesNotRotate() {
        var rotation = FirstRunRowRotation(pool: items(3), visible: 3)
        #expect(!rotation.canRotate)
        #expect(rotation.nextSwap().isEmpty)
        var duplicates = FirstRunRowRotation(pool: [Item(id: "a"), Item(id: "b"), Item(id: "a")], visible: 2)
        #expect(!duplicates.canRotate)
        #expect(duplicates.nextSwap().isEmpty)
        #expect(!FirstRunRowRotation(pool: [Item](), visible: 3).canRotate)
    }

    @Test("Swaps never show the same item twice and walk the whole pool")
    func rotatesWithoutDuplicates() {
        var rotation = FirstRunRowRotation(pool: items(8), visible: 3)
        var shown = Set(rotation.rows.map(\.id))
        for _ in 0..<12 {
            let swap = rotation.nextSwap()
            #expect(swap.count == 1)
            let before = rotation.rows
            rotation.replace(swap)
            #expect(Set(rotation.rows.map(\.id)).count == 3)
            for index in swap { #expect(rotation.rows[index] != before[index]) }
            for index in 0..<3 where !swap.contains(index) { #expect(rotation.rows[index] == before[index]) }
            shown.formUnion(rotation.rows.map(\.id))
        }
        #expect(shown.count == 8)
    }

    @Test("Four rows swap two at a time")
    func fourRows() {
        var rotation = FirstRunRowRotation(pool: items(12), visible: 4)
        let swap = rotation.nextSwap()
        #expect(swap.count == 2)
        rotation.replace(swap)
        #expect(Set(rotation.rows.map(\.id)).count == 4)
    }

    @Test("Out-of-range indices are ignored")
    func ignoresBadIndices() {
        var rotation = FirstRunRowRotation(pool: items(5), visible: 2)
        rotation.replace([7, -1])
        #expect(rotation.rows.map(\.id) == ["s0", "s1"])
    }
}

// MARK: - Window rotation

@Suite("FirstRunWindowRotation")
struct FirstRunWindowRotationTests {
    @Test("A window steps through its pool and wraps")
    func wraps() {
        var window = FirstRunWindowRotation(pool: Array(0..<6), count: 2)
        #expect(window.rows == [0, 1])
        window.advance()
        #expect(window.rows == [2, 3])
        window.advance()
        #expect(window.rows == [4, 5])
        window.advance()
        #expect(window.rows == [0, 1])
    }

    @Test("A window wraps across the end of an uneven pool")
    func unevenPool() {
        var window = FirstRunWindowRotation(pool: Array(0..<5), count: 2)
        window.advance()
        window.advance()
        #expect(window.rows == [4, 0])
    }

    @Test("Window size is clamped to the pool, and an empty pool shows nothing")
    func clamps() {
        var empty = FirstRunWindowRotation(pool: [Int](), count: 3)
        empty.advance()
        #expect(empty.rows.isEmpty)
        #expect(FirstRunWindowRotation(pool: [1, 2], count: 5).rows == [1, 2])
    }
}

// MARK: - Score pattern

@Suite("FirstRunDemoScorePattern")
struct FirstRunDemoScorePatternTests {
    @Test("The hash matches the web's JavaScript string hash", arguments: [
        ("", Int32(0)), ("Abc", 65_602), ("Through the Fire and Flames", -483_769_719),
        ("Bohemian Rhapsody", 1_202_173_955), ("é🎸", 1_997_221),
    ])
    func hashMatchesJavaScript(title: String, expected: Int32) {
        #expect(FirstRunDemoScorePattern.hash(title) == expected)
    }

    @Test("States come from bit pairs of the absolute hash, as on the web")
    func states() {
        // |hash("Bohemian Rhapsody")| = 0b…0000_0011: lead FC, then three unscored.
        #expect(FirstRunDemoScorePattern.states(title: "Bohemian Rhapsody", count: 4)
            == [.fullCombo, .noScore, .noScore, .noScore])
        #expect(FirstRunDemoScorePattern.states(title: "Through the Fire and Flames", count: 4)
            == [.fullCombo, .scored, .fullCombo, .scored])
        #expect(FirstRunDemoScorePattern.states(title: "", count: 2) == [.noScore, .noScore])
        #expect(FirstRunDemoScorePattern.states(title: "Abc", count: 0).isEmpty)
    }
}
