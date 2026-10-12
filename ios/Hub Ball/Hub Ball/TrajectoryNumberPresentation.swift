import Foundation

/// Compiled presentation only. Geometry/data keep their original fractional precision.
nonisolated enum TrajectoryNumberPresentation: Sendable {
    case standard
    case wholeRunCounts
    case innings

    func counter(_ value: Double) -> String {
        self == .wholeRunCounts ? integer(value) : value.formatted(.number.precision(.fractionLength(0...1)))
    }
    func axis(_ value: Double, grouping: Bool = true) -> String {
        if self == .wholeRunCounts { return integer(value) }
        if self == .innings {
            let outs = Int((value * 3).rounded()), whole = outs / 3, remainder = outs % 3
            return (whole == 0 && remainder != 0 ? "" : String(whole)) + (remainder == 1 ? "⅓" : remainder == 2 ? "⅔" : "")
        }
        return grouping ? value.formatted() : value.formatted(.number.grouping(.never))
    }
    private func integer(_ value: Double) -> String {
        value.rounded(.down).formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }
}
