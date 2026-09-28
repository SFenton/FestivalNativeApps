import Foundation

// Runs the unmodified Apple SuggestionGenerator over the shared parity fixture and prints the
// categories each scenario produces, as JSON, for the Windows parity test.

struct Scenario: Decodable {
    let name: String
    let seed: UInt32
    let disableSkipping: Bool?
    let fixedDisplayCount: Int?
    let currentSeason: Int
    let rivals: String
    let pages: [Int]
    let resetPages: [Int]?
    let resetCycles: Int?
}

struct Fixture: Decodable {
    let songs: [Song]
    let scores: [PlayerScore]
    let rivalsAll: RivalsAllResponse
    let rngSeeds: [UInt32]
    let scenarios: [Scenario]
}

func itemJSON(_ item: SuggestionSongItem) -> [String: Any] {
    var out: [String: Any] = ["id": item.id]
    if let v = item.stars { out["stars"] = v }
    if let v = item.percent { out["percent"] = v }
    if let v = item.fullCombo { out["fullCombo"] = v }
    if let v = item.percentileDisplay { out["percentileDisplay"] = v }
    if let v = item.rivalName { out["rivalName"] = v }
    if let v = item.rivalAccountId { out["rivalAccountId"] = v }
    if let v = item.rivalRankDelta { out["rivalRankDelta"] = v }
    return out
}

func categoryJSON(_ c: SuggestionCategory) -> [String: Any] {
    var out: [String: Any] = [
        "key": c.key, "title": c.title, "description": c.description, "type": c.type.rawValue,
        "songs": c.songs.map(itemJSON),
    ]
    if let i = c.instrument { out["instrument"] = i.rawValue }
    return out
}

let path = CommandLine.arguments[1]
let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
var index: [String: [Instrument: PlayerScore]] = [:]
for row in fixture.scores { index[row.songId, default: [:]][row.instrument] = row }
let rivalIndex = RivalDataIndex.build(from: fixture.rivalsAll)

var rngOut: [[String: Any]] = []
for seed in fixture.rngSeeds {
    var rng = SeededSuggestionRng(seed: seed)
    rngOut.append(["seed": seed, "doubles": (0..<8).map { _ in rng.nextDouble() }, "ints": (0..<8).map { _ in rng.nextInt(97) }])
}

var scenariosOut: [[String: Any]] = []
for s in fixture.scenarios {
    let gen = SuggestionGenerator(options: .init(
        seed: s.seed, disableSkipping: s.disableSkipping ?? false, fixedDisplayCount: s.fixedDisplayCount,
        currentSeason: s.currentSeason))
    gen.setSource(songs: fixture.songs, scoresIndex: index)
    if s.rivals == "early" { gen.setRivalData(rivalIndex) }
    var pages: [[[String: Any]]] = []
    for (n, count) in s.pages.enumerated() {
        pages.append(gen.getNext(count).map(categoryJSON))
        if n == 0 && s.rivals == "late" { gen.setRivalData(rivalIndex) }
    }
    var resetPages: [[[String: Any]]] = []
    if let rp = s.resetPages {
        for _ in 0..<(s.resetCycles ?? 1) {
            gen.resetForEndless()
            for count in rp { resetPages.append(gen.getNext(count).map(categoryJSON)) }
        }
    }
    scenariosOut.append(["name": s.name, "pages": pages, "resetPages": resetPages])
}

let rivalOut: [String: Any] = [
    "songRivals": rivalIndex.songRivals.map { ["accountId": $0.accountId, "displayName": $0.displayName, "direction": $0.direction] },
    "byRivalCounts": Dictionary(uniqueKeysWithValues: rivalIndex.byRival.map { ($0.key, $0.value.count) }),
    "closestCount": rivalIndex.closestRivalBySong.count,
]
let output: [String: Any] = ["rng": rngOut, "rivalIndex": rivalOut, "scenarios": scenariosOut]
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted])
FileHandle.standardOutput.write(data)
