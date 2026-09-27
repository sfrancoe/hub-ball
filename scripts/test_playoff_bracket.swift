import Foundation

@main
struct PlayoffBracketTest {
    static func main() throws {
        let slots = PlayoffBracketSlot.all
        precondition(slots.count == 11)
        precondition(Set(slots.map(\.id)).count == 11)
        for path in CommandLine.arguments.dropFirst() {
            let payload = try JSONDecoder().decode(PostseasonPayload.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            precondition(payload.series.count == 11, "Fixture must cover the entire tournament")
            for series in payload.series {
                guard let slot = slots.first(where: { $0.seriesID(season: payload.season) == series.id }) else {
                    fatalError("Real provider series missing from bracket: \(series.id)")
                }
                let expected = slot.destinationID.map { "\(payload.season)-\($0)" }
                precondition(series.nextSlots?.first == expected, "Advancement line must match provider normalization: \(series.id)")
                var current = slot
                var visited = Set<String>()
                while let next = current.destinationID {
                    precondition(visited.insert(current.id).inserted, "No cycles")
                    current = slots.first { $0.id == next }!
                }
                precondition(current.round == "world-series", "Every path must reach World Series")
            }
        }
        print("All 11 bracket slots and advancement paths agree with recorded postseasons")
    }
}
