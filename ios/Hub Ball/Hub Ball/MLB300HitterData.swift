import Foundation

/// Supplied Hub Ball editorial handoff, 1976–2025. Counts use displayed AVG >= .301,
/// not .300-or-better. Keep this series separate from the story presentation.
/// 2026 is a dated MLB Stats API snapshot, explicitly provisional. Never label it final
/// until final regular-season totals have been confirmed.
enum MLB300HitterData {
    struct Season: Identifiable, Equatable {
        let year: Int
        let count: Int
        var isProvisional = false
        var label: String { "\(year)\(isProvisional ? " YTD" : "")" }
        var id: Int { year }
    }

    static let seasons: [Season] = [
        .init(year: 1976, count: 23), .init(year: 1977, count: 30), .init(year: 1978, count: 16), .init(year: 1979, count: 26), .init(year: 1980, count: 29),
        .init(year: 1981, count: 30), .init(year: 1982, count: 21), .init(year: 1983, count: 25), .init(year: 1984, count: 24), .init(year: 1985, count: 15),
        .init(year: 1986, count: 22), .init(year: 1987, count: 24), .init(year: 1988, count: 21), .init(year: 1989, count: 17), .init(year: 1990, count: 20),
        .init(year: 1991, count: 23), .init(year: 1992, count: 21), .init(year: 1993, count: 32), .init(year: 1994, count: 46), .init(year: 1995, count: 38),
        .init(year: 1996, count: 44), .init(year: 1997, count: 31), .init(year: 1998, count: 46), .init(year: 1999, count: 51), .init(year: 2000, count: 49),
        .init(year: 2001, count: 44), .init(year: 2002, count: 30), .init(year: 2003, count: 36), .init(year: 2004, count: 36), .init(year: 2005, count: 30),
        .init(year: 2006, count: 33), .init(year: 2007, count: 36), .init(year: 2008, count: 31), .init(year: 2009, count: 35), .init(year: 2010, count: 19),
        .init(year: 2011, count: 23), .init(year: 2012, count: 22), .init(year: 2013, count: 23), .init(year: 2014, count: 15), .init(year: 2015, count: 19),
        .init(year: 2016, count: 24), .init(year: 2017, count: 23), .init(year: 2018, count: 14), .init(year: 2019, count: 19), .init(year: 2020, count: 20),
        .init(year: 2021, count: 12), .init(year: 2022, count: 10), .init(year: 2023, count: 9), .init(year: 2024, count: 7), .init(year: 2025, count: 6),
        .init(year: 2026, count: 6, isProvisional: true)
    ]
    static let peak = seasons.max { $0.count < $1.count }!
    static let peakIndex = seasons.firstIndex(of: peak)!
    static let finish = seasons.last!
    static let snapshotLabel = "Sept. 27, 2026 · before today’s games"
    static let coverageLabel = "1976–2025 final · 2026 YTD"
    static let endingQuestion = "Six so far. Will it end at six again?"
    static let decline = Int((100 * (1 - Double(finish.count) / Double(peak.count))).rounded())
    static let duration: TimeInterval = 10

    /// Monotonic elapsed time makes timing independent of frame rate.
    static func progress(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed / duration))
    }

    static func pointOpacity(index: Int, elapsed: TimeInterval) -> Double {
        let start = Double(index) / Double(seasons.count - 1) * 8.5
        return min(1, max(0, (elapsed - start) / 0.5))
    }
}
