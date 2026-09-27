import Foundation

struct PostseasonPayload: Codable, Sendable {
    let schemaVersion: Int
    let season: Int
    let phase: String
    let checkedAt: String
    let providerUpdatedAt: String?
    let source: String
    let sourceURL: String
    let teamsAndSlots: [PostseasonSlot]
    let series: [PostseasonSeries]
    let games: [PostseasonGame]

    var checkedDate: Date? { Self.parseDate(checkedAt) }
    var isLive: Bool { games.contains { $0.abstractState == "Live" } }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct PostseasonSlot: Codable, Identifiable, Sendable {
    let id: String
    let teamId: Int?
    let name: String?
    let unresolved: Bool
    let qualification: String
}

struct PostseasonClub: Codable, Identifiable, Sendable {
    let teamId: Int?
    let name: String?
    let abbreviation: String?
    let slot: String?
    let resolved: Bool

    var id: String { teamId.map(String.init) ?? "slot-\(slot ?? "unknown")" }
}

struct PostseasonSeries: Codable, Identifiable, Sendable {
    let id: String
    let round: String
    let league: String?
    let bracketSlot: String
    let participants: [PostseasonClub]
    let unresolvedSlots: [String]
    let requiredWins: Int?
    let gameIds: [Int]
    let completedGameCount: Int
    let wins: [String: Int]?
    let winnerTeamId: Int?
    let state: String
    let nextSlots: [String]?

    func wins(for teamID: Int) -> Int? { wins?[String(teamID)] }
}

struct PostseasonGame: Codable, Identifiable, Sendable {
    let gamePk: Int
    let seriesId: String?
    let gameNumber: Int?
    let gameType: String?
    let gameDate: String?
    let timeTBD: Bool
    let status: String
    let abstractState: String
    let broadcasts: [String]
    let conditional: Bool
    let away: PostseasonClub
    let home: PostseasonClub
    let awayScore: Int?
    let homeScore: Int?
    let winnerTeamId: Int?
    let liveInning: Int?

    var id: Int { gamePk }
    var startDate: Date? {
        guard !timeTBD, let gameDate else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: gameDate) ?? ISO8601DateFormatter().date(from: gameDate)
    }
}

struct OctoberCall: Codable, Identifiable, Sendable {
    let seriesID: String
    let winnerTeamID: Int
    let seriesLength: Int
    let entryCategory: String
    let createdAt: Date
    let revisedAt: Date
    var cutoffAt: Date?
    var cutoffEvidence: String
    var outcome: String?
    var exactLength: Bool?

    var id: String { seriesID }
}

struct OctoberCallBook: Codable, Sendable {
    var championTeamID: Int?
    var calls: [String: OctoberCall] = [:]
}

/// Fixed tournament slots retain their identity as TBD opponents become real teams.
struct PlayoffBracketSlot: Identifiable {
    let league: String
    let round: String
    let slot: String
    let column: Int
    let row: Int

    var id: String { "\(league.lowercased())-\(round)-\(slot.lowercased())" }
    func seriesID(season: Int) -> String { "\(season)-\(id)" }

    static let all: [Self] = [
        .init(league: "AL", round: "wild-card", slot: "B", column: 0, row: 0),
        .init(league: "AL", round: "wild-card", slot: "A", column: 0, row: 1),
        .init(league: "AL", round: "division-series", slot: "A", column: 1, row: 0),
        .init(league: "AL", round: "division-series", slot: "B", column: 1, row: 1),
        .init(league: "AL", round: "league-championship", slot: "main", column: 2, row: 0),
        .init(league: "MLB", round: "world-series", slot: "main", column: 3, row: 0),
        .init(league: "NL", round: "league-championship", slot: "main", column: 4, row: 0),
        .init(league: "NL", round: "division-series", slot: "A", column: 5, row: 0),
        .init(league: "NL", round: "division-series", slot: "B", column: 5, row: 1),
        .init(league: "NL", round: "wild-card", slot: "B", column: 6, row: 0),
        .init(league: "NL", round: "wild-card", slot: "A", column: 6, row: 1),
    ]

    var destinationID: String? {
        switch round {
        case "wild-card": "\(league.lowercased())-division-series-\(slot == "B" ? "a" : "b")"
        case "division-series": "\(league.lowercased())-league-championship-main"
        case "league-championship": "mlb-world-series-main"
        default: nil
        }
    }
}
