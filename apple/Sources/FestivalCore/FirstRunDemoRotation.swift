import Foundation

// MARK: - Timing

/// First-run demo animation timing, ported from the web theme
/// (`packages/theme/src/animation.ts`) so native demos rotate on the same clock.
public enum FirstRunDemoTiming {
    /// Time between two data swaps (web `DEMO_SWAP_INTERVAL_MS`).
    public static let swapInterval: Duration = .milliseconds(5_000)
    /// Fade-out, and then fade-in, time of one swap in seconds (web `FADE_DURATION`).
    public static let fadeSeconds: Double = 0.4
    /// Delay between cascading rows on entrance in seconds (web `STAGGER_INTERVAL`).
    public static let staggerSeconds: Double = 0.125
    /// Rise distance of a row's entrance in points (web `fadeInUp`: `translateY(12px)`).
    public static let entranceRise: Double = 12
    /// Selection cycle of the Song Info bar-select demo (web `BarSelectDemo` `CYCLE_MS`).
    public static let barSelectInterval: Duration = .milliseconds(2_500)
    /// Detail-card fade of the bar-select demo in seconds (web `BarSelectDemo`'s 300 ms).
    public static let barSelectFadeSeconds: Double = 0.3

    /// Fade duration as a `Duration`, for sleeping between fade-out and swap.
    public static var fade: Duration { .milliseconds(Int(fadeSeconds * 1_000)) }
}

// MARK: - Swap selection

/// Which rows a demo swaps on each tick, ported from the web's `useDemoSongs` swap cycle.
///
/// The web picks rows with `Math.random`; natives use a seeded shuffle of the tick number so
/// captures and tests repeat, while keeping the web's rules: how many rows swap, and never the
/// exact same rows twice in a row.
public enum FirstRunDemoRotation {
    /// Rows swapped per tick: one for up to 3 rows, two for up to 6, otherwise three
    /// (web `SMALL_POOL`/`MEDIUM_POOL`).
    ///
    /// - Parameter rowCount: Visible rows.
    /// - Returns: 0 for no rows, else 1, 2 or 3.
    public static func swapCount(rowCount: Int) -> Int {
        switch rowCount {
        case ..<1: 0
        case 1...3: 1
        case 4...6: 2
        default: 3
        }
    }

    /// The row indices to swap on `tick`.
    ///
    /// - Parameters:
    ///   - rowCount: Visible rows.
    ///   - tick: Zero-based swap number; seeds the deterministic shuffle.
    ///   - previous: Rows swapped on the previous tick; avoided when another choice exists
    ///     (web `MAX_DEDUP_ATTEMPTS` = 10).
    /// - Returns: ``swapCount(rowCount:)`` distinct indices in ascending order.
    public static func swapIndices(rowCount: Int, tick: Int, avoiding previous: Set<Int> = []) -> [Int] {
        let count = swapCount(rowCount: rowCount)
        guard count > 0 else { return [] }
        var picked: [Int] = []
        for attempt in 0..<10 {
            var generator = SplitMix64(seed: UInt64(truncatingIfNeeded: tick) &* 0x9E37_79B9 &+ UInt64(attempt))
            picked = Array(Array(0..<rowCount).shuffled(using: &generator).prefix(count)).sorted()
            if Set(picked) != previous || count == rowCount { break }
        }
        return picked
    }
}

/// A small deterministic generator (SplitMix64) for repeatable demo shuffles.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Row rotation

/// Visible demo rows that rotate through a larger pool, ported from the web's `useDemoSongs`:
/// each tick swaps ``FirstRunDemoRotation/swapCount(rowCount:)`` rows for pool items that are
/// not already visible.
///
/// Replacements walk the pool in order (the web picks at random) so every pool item appears
/// before any repeats, and runs are reproducible.
public struct FirstRunRowRotation<Element: Identifiable> {
    /// The rows currently shown, in stable positions.
    public private(set) var rows: [Element]
    /// Everything the rows may show.
    public let pool: [Element]
    private var cursor: Int
    private var tick = 0
    private var lastSwapped: Set<Int> = []

    /// - Parameters:
    ///   - pool: Items to rotate through; duplicates by `id` are tolerated but never shown twice.
    ///   - visible: Rows to show; the first `visible` pool items start visible.
    public init(pool: [Element], visible: Int) {
        self.pool = pool
        rows = Array(pool.prefix(max(0, visible)))
        cursor = rows.count
    }

    /// Whether a swap can show anything new: the pool must hold more items than the rows.
    public var canRotate: Bool {
        !rows.isEmpty && Set(pool.map(\.id)).count > Set(rows.map(\.id)).count
    }

    /// Choose the rows to swap next and advance the tick; empty when ``canRotate`` is false.
    ///
    /// - Returns: Ascending row indices to fade out and replace with ``replace(_:)``.
    public mutating func nextSwap() -> [Int] {
        guard canRotate else { return [] }
        let indices = FirstRunDemoRotation.swapIndices(rowCount: rows.count, tick: tick, avoiding: lastSwapped)
        tick += 1
        lastSwapped = Set(indices)
        return indices
    }

    /// Replace each row in `indices` with the next pool item that is not visible.
    ///
    /// - Parameter indices: Rows from ``nextSwap()``; out-of-range indices are ignored.
    public mutating func replace(_ indices: [Int]) {
        guard !pool.isEmpty else { return }
        for index in indices where rows.indices.contains(index) {
            let visible = Set(rows.map(\.id))
            for _ in 0..<pool.count {
                let candidate = pool[cursor % pool.count]
                cursor = (cursor + 1) % pool.count
                if !visible.contains(candidate.id) {
                    rows[index] = candidate
                    break
                }
            }
        }
    }
}

// MARK: - Window rotation

/// A fixed-size window that steps through a pool, wrapping (web Rivals/Compete demos'
/// `poolIdxRef`): each step shows the next `count` items.
public struct FirstRunWindowRotation<Element> {
    /// Items to page through.
    public let pool: [Element]
    /// Items shown at once.
    public let count: Int
    private var start = 0

    /// - Parameters:
    ///   - pool: Items to page through.
    ///   - count: Items shown at once, clamped to the pool size.
    public init(pool: [Element], count: Int) {
        self.pool = pool
        self.count = min(max(0, count), pool.count)
    }

    /// The items currently shown.
    public var rows: [Element] {
        guard !pool.isEmpty else { return [] }
        return (0..<count).map { pool[(start + $0) % pool.count] }
    }

    /// Move to the next window.
    public mutating func advance() {
        guard !pool.isEmpty else { return }
        start = (start + count) % pool.count
    }
}

// MARK: - Song icon pattern

/// The per-instrument score pattern the Songs **icons** demo draws for a song, ported from
/// the web `SongIconsDemo` `buildScores` so each rotated-in song shows a different mix.
public enum FirstRunDemoScorePattern {
    /// One instrument's demo state.
    public enum State: Equatable, Sendable {
        case noScore, scored, fullCombo
    }

    /// The web's 32-bit string hash: `h = ((h << 5) - h + charCode) | 0` over UTF-16 units.
    ///
    /// - Parameter title: Song title.
    /// - Returns: The signed 32-bit hash.
    public static func hash(_ title: String) -> Int32 {
        var h: Int32 = 0
        for unit in title.utf16 {
            h = (h &<< 5) &- h &+ Int32(unit)
        }
        return h
    }

    /// Demo state for each of `count` instruments, in order.
    ///
    /// Bit `2i` of `|hash|` decides "scored", bit `2i+1` decides full combo, as on the web.
    ///
    /// - Parameters:
    ///   - title: Song title seeding the pattern.
    ///   - count: Number of instruments.
    /// - Returns: `count` states.
    public static func states(title: String, count: Int) -> [State] {
        let h = hash(title)
        // JS `Math.abs` of Int32.min is 2^31; keep it in 64 bits.
        let bits = Int64(h).magnitude
        return (0..<max(0, count)).map { i in
            let scored = (bits >> UInt64(i * 2)) & 1 == 1
            let fullCombo = scored && (bits >> UInt64(i * 2 + 1)) & 1 == 1
            return fullCombo ? .fullCombo : scored ? .scored : .noScore
        }
    }
}
