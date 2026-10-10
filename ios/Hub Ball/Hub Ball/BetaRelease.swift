import Foundation

nonisolated struct ReleaseVersion: Comparable, Sendable {
    let parts: [Int]
    init?(_ text: String) {
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = fields.map { Int($0)! } + Array(repeating: 0, count: 3 - fields.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

nonisolated struct InstalledBeta: Sendable {
    let version: String
    let build: Int
    let os: String
    let deviceFamily: String
}

nonisolated struct BetaRelease: Codable, Sendable, Equatable {
    let version: String
    let build: Int
    let audience: String
    let available: Bool
    let confirmedAt: String
    let expiresAt: String
    let minimumOS: String
    let deviceFamilies: [String]
    let verifiedGroupIDs: [String]
    var identity: String { "\(version)/\(build)" }
    static let supportedGroups = Set(["a7c07355-b794-49b9-b36d-75c129c8d6bb", "58b84a1e-c8ab-4b73-9948-3362b4569fd1"])
    func eligible(installed: InstalledBeta, now: Date) -> Bool {
        let dates = ISO8601DateFormatter()
        guard available, audience == "all-supported-testers", build > 0, build < 1_000_000_000,
              Set(verifiedGroupIDs) == Self.supportedGroups, verifiedGroupIDs.count == Self.supportedGroups.count,
              Set(deviceFamilies) == Set(["iphone", "ipad"]), deviceFamilies.count == 2,
              deviceFamilies.contains(installed.deviceFamily),
              let targetVersion = ReleaseVersion(version), let currentVersion = ReleaseVersion(installed.version),
              let minimum = ReleaseVersion(minimumOS), let os = ReleaseVersion(installed.os), minimum <= os,
              targetVersion >= currentVersion, build > installed.build, installed.build > 0,
              let confirmed = dates.date(from: confirmedAt), let expiry = dates.date(from: expiresAt),
              confirmed <= now, now.timeIntervalSince(confirmed) < 24 * 3600,
              expiry > now, expiry > confirmed, expiry.timeIntervalSince(confirmed) <= 90 * 86400 else { return false }
        return true
    }
}

nonisolated struct BetaReleaseManifest: Codable, Sendable {
    let schemaVersion: Int
    let bundleID: String
    let enabled: Bool
    let target: BetaRelease?
    static func target(from data: Data, installed: InstalledBeta, now: Date) throws -> BetaRelease? {
        guard data.count <= 16 * 1024 else { return nil }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.schemaVersion == 1, manifest.bundleID == "com.sfrancoe.HubBall", manifest.enabled,
              let target = manifest.target, target.eligible(installed: installed, now: now) else { return nil }
        return target
    }
}
