import Foundation

nonisolated enum StoryDocument: Sendable {
    case guess(RemoteStory)
    case trajectory(TrajectoryStory)
    case outGrid(InningOutGridStory)
    var title: String { switch self { case .guess(let s): s.title; case .trajectory(let s): s.title; case .outGrid(let s): s.title } }
}

/// A finite, declarative chart contract. No code, formulas or arbitrary assets.
nonisolated struct TrajectoryStory: Codable, Sendable {
    struct Chart: Codable, Sendable {
        struct Axis: Codable, Sendable {
            let label: String
            let minimum: Double
            let maximum: Double
            let ticks: [Double]
        }
        struct Point: Codable, Sendable { let x: Double; let y: Double }
        struct Series: Codable, Identifiable, Sendable {
            let id: String
            let label: String
            let color: String
            let points: [Point]
        }
        struct Emphasis: Codable, Identifiable, Sendable {
            struct Comparison: Codable, Sendable {
                let sourceSeriesID: String
                let targetSeriesID: String
            }
            let id: String
            let x: Double
            let y: Double
            let holdSeconds: Double
            let title: String
            let detail: String
            let comparison: Comparison?
        }
        struct Sequence: Codable, Sendable { let secondsPerSeries: Double }
        let kind: String
        let xAxis: Axis
        let yAxis: Axis
        let durationSeconds: Double
        let series: [Series]
        let emphasis: [Emphasis]
        let sequence: Sequence?
        var minimumCapability: Int { sequence != nil || emphasis.contains { $0.comparison != nil } ? 3 : 2 }
        var sweepSeconds: Double { durationSeconds - emphasis.reduce(0) { $0 + $1.holdSeconds } }
        func x(at elapsed: Double) -> Double {
            var remaining = max(0, elapsed)
            var previous = xAxis.minimum
            for beat in emphasis {
                let segment = (beat.x - previous) / (xAxis.maximum - xAxis.minimum) * sweepSeconds
                if remaining < segment { return previous + remaining / sweepSeconds * (xAxis.maximum - xAxis.minimum) }
                remaining -= segment
                if remaining < beat.holdSeconds { return beat.x }
                remaining -= beat.holdSeconds; previous = beat.x
            }
            return min(xAxis.maximum, previous + remaining / sweepSeconds * (xAxis.maximum - xAxis.minimum))
        }
        func value(in series: Series, at x: Double) -> Double {
            let points = series.points
            guard let first = points.first, let last = points.last else { return 0 }
            if x <= first.x { return first.y }
            if x >= last.x { return last.y }
            let upper = points.firstIndex { $0.x > x }!
            let a = points[upper - 1], b = points[upper]
            return kind == "line" ? a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x) : a.y
        }
        func displayedProgress(_ progress: Double) -> Double {
            if kind == "step" || kind == "bar" { return series[0].points.last { $0.x <= progress }?.x ?? xAxis.minimum }
            return progress.rounded(.down)
        }
        func validate() throws {
            try StoryContract.check(["line", "step", "bar"].contains(kind) && durationSeconds.isFinite && (2...20).contains(durationSeconds))
            for axis in [xAxis, yAxis] {
                try StoryContract.text(axis.label, limit: 80)
                try StoryContract.check(axis.minimum.isFinite && axis.maximum.isFinite && axis.minimum < axis.maximum && abs(axis.minimum) <= 1_000_000 && abs(axis.maximum) <= 1_000_000)
                try StoryContract.check((2...8).contains(axis.ticks.count) && Set(axis.ticks).count == axis.ticks.count && axis.ticks == axis.ticks.sorted() && axis.ticks.allSatisfy { $0.isFinite && $0 >= axis.minimum && $0 <= axis.maximum })
            }
            try StoryContract.check((1...6).contains(series.count) && Set(series.map(\.id)).count == series.count && series.reduce(0) { $0 + $1.points.count } <= 2_000)
            for row in series {
                try StoryContract.check(StoryContract.slug(row.id) && ["coral", "navy", "gold", "teal", "purple", "gray"].contains(row.color))
                try StoryContract.text(row.label, limit: 80)
                try StoryContract.check((2...600).contains(row.points.count) && row.points.first?.x == xAxis.minimum && row.points.last?.x == xAxis.maximum)
                if kind == "bar" { try StoryContract.check(row.points.count <= 60 && yAxis.minimum <= 0 && yAxis.maximum >= 0) }
                for (index, point) in row.points.enumerated() {
                    try StoryContract.check(point.x.isFinite && point.y.isFinite && point.x >= xAxis.minimum && point.x <= xAxis.maximum && point.y >= yAxis.minimum && point.y <= yAxis.maximum && (index == 0 || point.x > row.points[index - 1].x))
                }
            }
            try StoryContract.check(emphasis.count <= 8 && Set(emphasis.map(\.id)).count == emphasis.count && emphasis.map(\.x) == emphasis.map(\.x).sorted() && Set(emphasis.map(\.x)).count == emphasis.count && sweepSeconds >= 1)
            for beat in emphasis {
                try StoryContract.check(StoryContract.slug(beat.id) && beat.x.isFinite && beat.y.isFinite && beat.holdSeconds.isFinite && (0...2).contains(beat.holdSeconds) && beat.x >= xAxis.minimum && beat.x <= xAxis.maximum && beat.y >= yAxis.minimum && beat.y <= yAxis.maximum)
                try StoryContract.text(beat.title, limit: 160); try StoryContract.text(beat.detail, limit: 500)
                if let comparison = beat.comparison {
                    guard let source = series.firstIndex(where: { $0.id == comparison.sourceSeriesID }),
                          let target = series.firstIndex(where: { $0.id == comparison.targetSeriesID }) else { throw StoryContentError.invalid }
                    try StoryContract.check(sequence != nil && target < source && value(in: series[source], at: beat.x) == beat.y && series[target].points.last?.y == beat.y && beat.holdSeconds >= 1.9)
                }
            }
            if let sequence {
                try StoryContract.check(sequence.secondsPerSeries.isFinite && (1...4).contains(sequence.secondsPerSeries))
                try StoryContract.check(abs(sequence.secondsPerSeries * Double(series.count) + emphasis.reduce(0) { $0 + $1.holdSeconds } - durationSeconds) < 0.001)
            }
        }
    }
    let schemaVersion: Int
    let id: String
    let renderer: String
    let rendererVersion: Int
    let title: String
    let kicker: String
    let intro: String
    let chart: Chart
    let conclusion: String
    let presentation: Presentation?
    var minimumCapability: Int { presentation == nil ? chart.minimumCapability : 5 }
    struct Presentation: Codable, Sendable {
        struct Interval: Codable, Sendable { let start: Double; let end: Double; let label: String }
        let style: String
        let headline: String
        let subheadline: String
        let hookExpiresAt: String
        let numberFormat: String
        let openingSeconds: Double
        let sweepSeconds: Double
        func barGrowth(elapsed: Double, index: Int, count: Int) -> Double {
            let progress = min(1, max(0, (elapsed - openingSeconds) / sweepSeconds))
            return min(1, max(0, progress * Double(count) - Double(index)))
        }
        let intervals: [Interval]
        func hookIsCurrent(now: Date = Date()) -> Bool {
            now < (ISO8601DateFormatter().date(from: hookExpiresAt) ?? .distantPast)
        }
        func validate(chart: Chart) throws {
            try StoryContract.check(style == "screening-room" && ["standard", "innings"].contains(numberFormat))
            try StoryContract.check(openingSeconds.isFinite && sweepSeconds.isFinite && openingSeconds >= 0 && openingSeconds <= 3 && sweepSeconds >= 1 && openingSeconds + sweepSeconds <= chart.durationSeconds)
            try StoryContract.text(headline, limit: 160); try StoryContract.text(subheadline, limit: 400)
            try StoryContract.check(StoryContract.timestamp(hookExpiresAt) && intervals.count <= 6)
            for interval in intervals {
                try StoryContract.check(interval.start.isFinite && interval.end.isFinite && interval.start < interval.end && interval.start >= chart.xAxis.minimum - 0.5 && interval.end <= chart.xAxis.maximum + 0.5)
                try StoryContract.text(interval.label, limit: 80)
            }
            if numberFormat == "innings" {
                try StoryContract.check(chart.kind == "bar" && chart.yAxis.minimum == 0 && chart.series.allSatisfy { $0.points.allSatisfy { $0.y >= 0 && abs($0.y * 3 - ($0.y * 3).rounded()) < 0.000001 } })
            }
        }
    }
    let methodology: [String]
    let sources: [RemoteStory.Source]
    func validate() throws {
        guard schemaVersion == 1 && renderer == "chart-trajectory" && rendererVersion == 1 else { throw StoryContentError.unsupported }
        try StoryContract.check(StoryContract.slug(id))
        try StoryContract.text(title, limit: 160); try StoryContract.text(kicker, limit: 160)
        try StoryContract.text(intro); try StoryContract.text(conclusion)
        try chart.validate()
        try presentation?.validate(chart: chart)
        try StoryContract.check((1...12).contains(methodology.count) && (1...12).contains(sources.count) && Set(sources.map(\.id)).count == sources.count)
        for text in methodology { try StoryContract.text(text) }
        for source in sources {
            try StoryContract.check(StoryContract.slug(source.id) && StoryContract.sourceURL(source.url) != nil && StoryContract.timestamp(source.retrievedAt))
            try StoryContract.text(source.title, limit: 200)
        }
    }
}

/// Elapsed time is frozen outside the foreground; returning resumes without jumping or restarting.
struct TrajectoryPlayback {
    private(set) var elapsed = 0.0
    private var anchor: TimeInterval?
    mutating func start(now: TimeInterval, reducedMotion: Bool, duration: Double) {
        elapsed = reducedMotion ? duration : 0; anchor = reducedMotion ? nil : now
    }
    func time(now: TimeInterval, duration: Double) -> Double { min(duration, elapsed + max(0, now - (anchor ?? now))) }
    mutating func pause(now: TimeInterval, duration: Double) { elapsed = time(now: now, duration: duration); anchor = nil }
    mutating func resume(now: TimeInterval, duration: Double) { if elapsed < duration { anchor = now } }
}
