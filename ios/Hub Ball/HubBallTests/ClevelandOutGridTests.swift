import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor
struct ClevelandOutGridTests {
    @Test func exactOfficialSequenceCopyAndCapability() throws {
        let item = try #require(ClevelandLaunchStory.item), story = item.story
        #expect(story.heading == "Wow!")
        #expect(story.commentary == "Cleveland set a major league record (regular OR postseason) for the number of strikeouts in a 9-inning game going back to 1900. They did this in the deciding Game 5 of the ALDS. Guardians move on after winning 2-0.")
        #expect(story.outs.count == 27 && story.outs.filter { $0.result == .strikeout }.count == 21)
        #expect(story.outs.filter { $0.result == .other }.map(\.number) == [1,3,9,14,17,24])
        #expect(story.durationSeconds == 9.6 && item.entry.minimumRendererVersion == 4)
        #expect(!item.entry.isSupported(by: 3) && item.entry.isSupported(by: 4))
        #expect(PrivateLaunchStory.item?.id == "separated-by-one")
        for inning in 1...9 { #expect(story.outs.filter { $0.inning == inning }.count == 3) }
        let names = ["Gavin Williams", "Erik Sabrowski", "Hunter Gaddis", "Cade Smith"]
        #expect(names.map { name in story.outs.filter { $0.pitcher == name }.count } == [17,1,4,5])
        #expect(names.map { name in story.outs.filter { $0.pitcher == name && $0.result == .strikeout }.count } == [12,1,4,4])
    }
    @Test func cachedGridAndMinimumCapabilityRemainValidated() async throws {
        let item = try #require(ClevelandLaunchStory.item)
        let url = try #require(Bundle.main.url(forResource: "story-private-cleveland-k", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory)
        await cache.saveStory(CachedStory(entry: item.entry, data: data))
        let cached = try #require(await cache.story(id: item.id))
        guard case .outGrid(let restored) = try cached.decoded() else { Issue.record("Wrong cached document"); return }
        #expect(restored.strikeouts(at: 9.6) == 21)
        let old = StoryEntry(id: item.id, revision: item.entry.revision, title: item.entry.title, summary: item.entry.summary, fallback: item.entry.fallback, publishedAt: item.entry.publishedAt, teamIDs: [114], renderer: "inning-out-grid", rendererVersion: 1, minimumRendererVersion: 3)
        #expect(throws: (any Error).self) { _ = try StoryContract.decodeDocument(data, entry: old) }
    }
    @Test func integerRevealAndFinalClamp() throws {
        let story = try #require(ClevelandLaunchStory.item).story
        var previous = 0
        for frame in 0...960 {
            let t = Double(frame) / 100, n = story.revealedOuts(at: t)
            #expect(n >= previous && n <= 27 && story.strikeouts(at: t) <= n)
            #expect(story.strikeouts(at: t) == story.outs.prefix(n).filter { $0.result == .strikeout }.count)
            previous = n
        }
        #expect(story.revealedOuts(at: -1) == 0 && story.revealedOuts(at: .nan) == 0)
        #expect(story.revealedOuts(at: 9.6) == 27 && story.strikeouts(at: 99) == 21)
    }
    @Test func rejectsForgedOrderingResultDurationAndHash() throws {
        let item = try #require(ClevelandLaunchStory.item)
        let bytes = try JSONEncoder().encode(item.story)
        var original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["order", "inning", "result", "duration", "size"] {
            var value = original
            var rows = try #require(value["outs"] as? [[String: Any]])
            switch key {
            case "order": rows[0]["number"] = 2
            case "inning": rows[0]["inning"] = 2
            case "result": rows[0]["result"] = "script"
            case "size": rows.removeLast()
            default: value["durationSeconds"] = 0
            }
            value["outs"] = rows
            let changed = try JSONSerialization.data(withJSONObject: value)
            #expect(throws: (any Error).self) { let s = try JSONDecoder().decode(InningOutGridStory.self, from: changed); try s.validate() }
        }
        original["heading"] = "Changed"
        #expect(throws: (any Error).self) { _ = try StoryContract.decodeDocument(JSONSerialization.data(withJSONObject: original), entry: item.entry) }
    }
}
