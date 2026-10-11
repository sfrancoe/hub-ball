import Foundation

/// Capability 4: one nine-inning game, three ordered batter outs per inning.
/// A finite renderer with owned colors, no code, URLs to assets, or expressions.
nonisolated struct InningOutGridStory: Codable, Sendable {
    enum Result: String, Codable, Sendable { case strikeout, other }
    struct Out: Codable, Identifiable, Sendable {
        let number: Int
        let inning: Int
        let result: Result
        let pitcher: String
        let batter: String
        var id: Int { number }
    }
    let schemaVersion: Int
    let id: String
    let renderer: String
    let rendererVersion: Int
    let title: String
    let heading: String
    let commentary: String
    let durationSeconds: Double
    let outs: [Out]
    let methodology: [String]
    let sources: [RemoteStory.Source]
    func validate() throws {
        guard schemaVersion == 1 && renderer == "inning-out-grid" && rendererVersion == 1 else { throw StoryContentError.unsupported }
        try StoryContract.check(StoryContract.slug(id) && durationSeconds.isFinite && (2...20).contains(durationSeconds))
        try StoryContract.text(title, limit: 160); try StoryContract.text(heading, limit: 160)
        try StoryContract.text(commentary)
        try StoryContract.check(outs.count == 27)
        for (index, out) in outs.enumerated() {
            try StoryContract.check(out.number == index + 1 && out.inning == index / 3 + 1)
            try StoryContract.text(out.pitcher, limit: 120); try StoryContract.text(out.batter, limit: 120)
        }
        try StoryContract.check((1...12).contains(methodology.count) && (1...12).contains(sources.count) && Set(sources.map(\.id)).count == sources.count)
        for text in methodology { try StoryContract.text(text) }
        for source in sources {
            try StoryContract.check(StoryContract.slug(source.id) && StoryContract.sourceURL(source.url) != nil && StoryContract.timestamp(source.retrievedAt))
            try StoryContract.text(source.title, limit: 200)
        }
    }
    func revealedOuts(at elapsed: Double) -> Int {
        guard elapsed.isFinite else { return 0 }
        return min(27, max(0, Int((min(durationSeconds, max(0, elapsed)) / durationSeconds * 27).rounded(.down))))
    }
    func strikeouts(at elapsed: Double) -> Int {
        outs.prefix(revealedOuts(at: elapsed)).filter { $0.result == .strikeout }.count
    }
}

nonisolated struct OutGridPreview: Identifiable, Sendable {
    let entry: StoryEntry
    let story: InningOutGridStory
    var id: String { entry.id }
}

nonisolated enum ClevelandLaunchStory {
    static let item: OutGridPreview? = {
        guard let catalogURL = Bundle.main.url(forResource: "story-private-cleveland-catalog", withExtension: "json"),
              let catalogBytes = try? Data(contentsOf: catalogURL), let catalog = try? StoryContract.decodeCatalog(catalogBytes),
              catalog.revision == "private-cleveland-october11", catalog.stories.count == 1,
              let entry = catalog.stories.first, entry.id == "almost-every-out-a-k",
              let url = Bundle.main.url(forResource: "story-private-cleveland-k", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              case .outGrid(let story) = try? StoryContract.decodeDocument(data, entry: entry) else { return nil }
        return OutGridPreview(entry: entry, story: story)
    }()
}
