import Foundation

/// Generated MLB qualified-hitter counts using displayed AVG >= .300, including .300.
/// Refresh with scripts/fetch_hitter_story.py; player totals live in data/mlb300-hitters.json.
/// 2026 remains a dated provisional snapshot until final totals have been confirmed.
enum MLB300HitterData {
    struct Season: Identifiable, Equatable {
        let year: Int
        let count: Int
        var isProvisional = false
        var label: String { "\(year)\(isProvisional ? " YTD" : "")" }
        var id: Int { year }
    }

    static let seasons: [Season] = [
        .init(year: 1976, count: 24),
        .init(year: 1977, count: 33),
        .init(year: 1978, count: 16),
        .init(year: 1979, count: 29),
        .init(year: 1980, count: 33),
        .init(year: 1981, count: 31),
        .init(year: 1982, count: 23),
        .init(year: 1983, count: 26),
        .init(year: 1984, count: 25),
        .init(year: 1985, count: 18),
        .init(year: 1986, count: 23),
        .init(year: 1987, count: 27),
        .init(year: 1988, count: 22),
        .init(year: 1989, count: 18),
        .init(year: 1990, count: 22),
        .init(year: 1991, count: 25),
        .init(year: 1992, count: 23),
        .init(year: 1993, count: 36),
        .init(year: 1994, count: 47),
        .init(year: 1995, count: 44),
        .init(year: 1996, count: 47),
        .init(year: 1997, count: 35),
        .init(year: 1998, count: 49),
        .init(year: 1999, count: 55),
        .init(year: 2000, count: 53),
        .init(year: 2001, count: 46),
        .init(year: 2002, count: 35),
        .init(year: 2003, count: 40),
        .init(year: 2004, count: 36),
        .init(year: 2005, count: 33),
        .init(year: 2006, count: 38),
        .init(year: 2007, count: 40),
        .init(year: 2008, count: 34),
        .init(year: 2009, count: 42),
        .init(year: 2010, count: 23),
        .init(year: 2011, count: 26),
        .init(year: 2012, count: 26),
        .init(year: 2013, count: 24),
        .init(year: 2014, count: 17),
        .init(year: 2015, count: 20),
        .init(year: 2016, count: 25),
        .init(year: 2017, count: 25),
        .init(year: 2018, count: 16),
        .init(year: 2019, count: 19),
        .init(year: 2020, count: 23),
        .init(year: 2021, count: 14),
        .init(year: 2022, count: 11),
        .init(year: 2023, count: 9),
        .init(year: 2024, count: 7),
        .init(year: 2025, count: 7),
        .init(year: 2026, count: 7, isProvisional: true)
    ]
    static let peak = seasons.max { $0.count < $1.count }!
    static let peakIndex = seasons.firstIndex(of: peak)!
    static let finish = seasons.last!
    static let snapshotLabel = "Sept. 27, 2026 · before today’s games"
    static let coverageLabel = "1976–2025 final · 2026 YTD"
    static let endingQuestion = "Seven so far. Will it end at seven again?"
    static let decline = Int((100 * (1 - Double(finish.count) / Double(peak.count))).rounded())
    static let duration: TimeInterval = 10

    /// Monotonic elapsed time makes timing independent of frame rate.
    static func progress(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed / duration))
    }
}
