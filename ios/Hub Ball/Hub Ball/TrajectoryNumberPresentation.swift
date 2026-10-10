import Foundation

/// Compiled presentation only. Geometry/data keep their original fractional precision.
nonisolated enum TrajectoryNumberPresentation: Sendable {
    case standard
    case wholeRunCounts

    func counter(_ value: Double) -> String {
        self == .wholeRunCounts ? integer(value) : value.formatted(.number.precision(.fractionLength(0...1)))
    }
    func axis(_ value: Double, grouping: Bool = true) -> String {
        if self == .wholeRunCounts { return integer(value) }
        return grouping ? value.formatted() : value.formatted(.number.grouping(.never))
    }
    private func integer(_ value: Double) -> String {
        value.rounded(.down).formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }
}
