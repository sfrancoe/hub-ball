import Foundation
import CryptoKit

nonisolated enum StoryContentError: Error { case invalid, unsupported, oversized, integrity }

/// Content can select these bundled capabilities; it cannot supply code or formulas.
nonisolated enum StoryContract {
    static let rendererVersion = 5
    static let catalogLimit = 128 * 1_024
    static let payloadLimit = 512 * 1_024

    static func check(_ condition: Bool) throws { if !condition { throw StoryContentError.invalid } }
    static func text(_ value: String, limit: Int = 2_000) throws {
        try check(!value.isEmpty && value.count <= limit && !value.unicodeScalars.contains { $0.value < 32 && $0 != "\n" && $0 != "\t" })
    }
    static func slug(_ value: String) -> Bool {
        guard value.count <= 80, let match = value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) else { return false }
        return match == value.startIndex..<value.endIndex
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func timestamp(_ value: String) -> Bool {
        value.count == 20 && value.hasSuffix("Z") && ISO8601DateFormatter().date(from: value) != nil
    }
    static func sourceURL(_ value: String) -> URL? {
        guard value.count <= 2_000, let url = URL(string: value), url.scheme == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func decodeCatalog(_ data: Data) throws -> StoryCatalog {
        guard data.count <= catalogLimit else { throw StoryContentError.oversized }
        let catalog = try JSONDecoder().decode(StoryCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }
    static func decodeStory(_ data: Data, entry: StoryEntry) throws -> RemoteStory {
        guard data.count <= payloadLimit else { throw StoryContentError.oversized }
        guard entry.isSupported else { throw StoryContentError.unsupported }
        guard hash(data) == entry.revision else { throw StoryContentError.integrity }
        let story = try JSONDecoder().decode(RemoteStory.self, from: data)
        try story.validate()
        try check(story.id == entry.id && story.title == entry.title && story.renderer == entry.renderer && story.rendererVersion == entry.rendererVersion)
        return story
    }
    static func decodeDocument(_ data: Data, entry: StoryEntry) throws -> StoryDocument {
        guard data.count <= payloadLimit else { throw StoryContentError.oversized }
        guard entry.isSupported else { throw StoryContentError.unsupported }
        guard hash(data) == entry.revision else { throw StoryContentError.integrity }
        if entry.renderer == "guess-reveal" { return .guess(try decodeStory(data, entry: entry)) }
        if entry.renderer == "inning-out-grid" {
            try check(entry.minimumRendererVersion >= 4)
            let story = try JSONDecoder().decode(InningOutGridStory.self, from: data)
            try story.validate()
            try check(story.id == entry.id && story.title == entry.title && story.renderer == entry.renderer && story.rendererVersion == entry.rendererVersion)
            return .outGrid(story)
        }
        try check(entry.minimumRendererVersion >= 2)
        let story = try JSONDecoder().decode(TrajectoryStory.self, from: data)
        try story.validate()
        try check(entry.minimumRendererVersion >= story.minimumCapability)
        try check(story.id == entry.id && story.title == entry.title && story.renderer == entry.renderer && story.rendererVersion == entry.rendererVersion)
        return .trajectory(story)
    }
}

nonisolated struct StoryCatalog: Codable, Sendable {
    let schemaVersion: Int
    let revision: String
    let publishedAt: String
    let stories: [StoryEntry]
    func validate() throws {
        guard schemaVersion == 1 else { throw StoryContentError.unsupported }
        try StoryContract.check(StoryContract.slug(revision) && StoryContract.timestamp(publishedAt) && stories.count <= 120)
        try StoryContract.check(Set(stories.map(\.id)).count == stories.count)
        for entry in stories { try entry.validate() }
    }
    static let empty = StoryCatalog(schemaVersion: 1, revision: "empty", publishedAt: "2026-10-08T00:00:00Z", stories: [])
}

nonisolated struct StoryEntry: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let revision: String
    let title: String
    let summary: String
    let fallback: String
    let publishedAt: String
    let teamIDs: [Int]
    let renderer: String
    let rendererVersion: Int
    let minimumRendererVersion: Int
    var payloadPath: String { "stories/\(id)/\(revision).json" }
    var cacheKey: String { "\(id)-\(revision)" }
    func isSupported(by capability: Int) -> Bool {
        minimumRendererVersion <= capability && rendererVersion == 1 &&
        (renderer == "guess-reveal" || (renderer == "chart-trajectory" && capability >= 2) || (renderer == "inning-out-grid" && capability >= 4))
    }
    var isSupported: Bool { isSupported(by: StoryContract.rendererVersion) }
    var actionLabel: String { !isSupported ? "READ THE SUMMARY" : ["chart-trajectory", "inning-out-grid"].contains(renderer) ? "WATCH THE CHART" : "GUESS · REVEAL · EXPLORE" }
    func validate() throws {
        try StoryContract.check(StoryContract.slug(id) && StoryContract.slug(renderer))
        try StoryContract.check(revision.count == 64 && revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil)
        try StoryContract.text(title, limit: 160); try StoryContract.text(summary, limit: 400); try StoryContract.text(fallback)
        try StoryContract.check(StoryContract.timestamp(publishedAt) && (1...100).contains(rendererVersion) && (1...100).contains(minimumRendererVersion))
        try StoryContract.check(teamIDs.count <= 30 && Set(teamIDs).count == teamIDs.count && teamIDs.allSatisfy { (1...1_000).contains($0) })
    }
}

nonisolated struct RemoteStory: Codable, Identifiable, Sendable {
    struct Choice: Codable, Identifiable, Sendable {
        let id: String
        let label: String
        let value: String
        let unit: String
        let detail: String
    }
    struct Stat: Codable, Sendable { let label: String; let value: String; let note: String }
    struct Bar: Codable, Sendable { let label: String; let value: Double; let unit: String; let detail: String }
    struct Passport: Codable, Sendable {
        struct Item: Codable, Identifiable, Sendable {
            let id: String
            let label: String
            let name: String
            let result: String
            let detail: String
            var resultLabel: String { result == "yes" ? "Modeled homer" : result == "no" ? "Not a modeled homer" : "Unknown" }
        }
        let title: String
        let intro: String
        let items: [Item]
    }
    struct Source: Codable, Identifiable, Sendable { let id: String; let title: String; let url: String; let retrievedAt: String }
    let schemaVersion: Int
    let id: String
    let renderer: String
    let rendererVersion: Int
    let title: String
    let kicker: String
    let intro: String
    let question: String
    let choices: [Choice]
    let correctChoiceID: String
    let answerTitle: String
    let answer: String
    let stats: [Stat]
    let bars: [Bar]
    let barMaximum: Double?
    let passport: Passport?
    let methodology: [String]
    let sources: [Source]
    let conclusion: String

    func validate() throws {
        guard schemaVersion == 1 && renderer == "guess-reveal" && rendererVersion == 1 else { throw StoryContentError.unsupported }
        try StoryContract.check(StoryContract.slug(id))
        for value in [intro, answer, conclusion] { try StoryContract.text(value) }
        try StoryContract.text(title, limit: 160); try StoryContract.text(kicker, limit: 160)
        try StoryContract.text(question, limit: 300); try StoryContract.text(answerTitle, limit: 200)
        try StoryContract.check((2...4).contains(choices.count) && Set(choices.map(\.id)).count == choices.count && choices.contains { $0.id == correctChoiceID })
        for choice in choices {
            try StoryContract.check(StoryContract.slug(choice.id))
            for value in [choice.label, choice.value, choice.unit, choice.detail] { try StoryContract.text(value, limit: 300) }
        }
        try StoryContract.check(stats.count <= 6 && bars.count <= 8)
        if let barMaximum {
            try StoryContract.check(barMaximum.isFinite && (1...100_000).contains(barMaximum) && bars.allSatisfy { $0.value <= barMaximum })
        }
        for stat in stats { for value in [stat.label, stat.value, stat.note] { try StoryContract.text(value, limit: 300) } }
        for bar in bars {
            try StoryContract.check(bar.value.isFinite && (0...100_000).contains(bar.value))
            try StoryContract.text(bar.label, limit: 160); try StoryContract.text(bar.unit, limit: 80); try StoryContract.text(bar.detail, limit: 500)
        }
        if let passport {
            try StoryContract.text(passport.title, limit: 160); try StoryContract.text(passport.intro)
            try StoryContract.check((1...60).contains(passport.items.count) && Set(passport.items.map(\.id)).count == passport.items.count)
            for item in passport.items {
                try StoryContract.check(StoryContract.slug(item.id) && ["yes", "no", "unknown"].contains(item.result))
                for value in [item.label, item.name, item.detail] { try StoryContract.text(value, limit: 1_000) }
            }
        }
        try StoryContract.check((1...12).contains(methodology.count) && (1...12).contains(sources.count) && Set(sources.map(\.id)).count == sources.count)
        for paragraph in methodology { try StoryContract.text(paragraph) }
        for source in sources {
            try StoryContract.check(StoryContract.slug(source.id) && StoryContract.sourceURL(source.url) != nil && StoryContract.timestamp(source.retrievedAt))
            try StoryContract.text(source.title, limit: 200)
        }
    }
}
