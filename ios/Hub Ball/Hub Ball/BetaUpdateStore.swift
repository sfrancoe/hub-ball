import Foundation
import Observation
import StoreKit
import UIKit

private nonisolated final class BetaRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// This is a broad-release hint, never a claim about the signed-in tester's group.
@MainActor @Observable final class BetaUpdateStore {
    typealias Fetch = @Sendable () async throws -> Data
    typealias Eligibility = @Sendable () async -> Bool
    private(set) var candidate: BetaRelease?
    private(set) var checking = false
    private let installed: InstalledBeta
    private let fetch: Fetch
    private let betaEligibility: Eligibility
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    private var lastCheck: Date?
    private var dismissed = Set<String>()
    static let snooze: TimeInterval = 7 * 86400
    static let helpURL = URL(string: "https://testflight.apple.com/")!

    init(installed: InstalledBeta, defaults: UserDefaults = .standard,
         clock: @escaping @Sendable () -> Date = Date.init,
         eligibility: @escaping Eligibility, fetch: @escaping Fetch) {
        self.installed = installed; self.defaults = defaults; self.clock = clock
        self.betaEligibility = eligibility; self.fetch = fetch
    }

    static func live() -> BetaUpdateStore {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        var defaults = UserDefaults.standard
        var url = AppBackend.sharedDataURL("releases/testflight-v1.json")
        var eligibility: Eligibility = {
            do {
                guard case .verified(let transaction) = try await AppTransaction.shared else { return false }
                return transaction.bundleID == "com.sfrancoe.HubBall" && transaction.appID == 6809478747 && transaction.environment == .sandbox
            } catch { return false }
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["HUB_UPDATE_ROOT"], let root = URL(string: value), StoryContentOrigin.approved(root, debug: true) {
            url = root.appending(path: "releases/testflight-v1.json")
        }
        if env["HUB_UPDATE_TEST_BETA"] == "1" { eligibility = { true } }
        if let value = env["HUB_UPDATE_TEST_BUILD"], let number = Int(value) { build = number }
        if let suite = env["HUB_UPDATE_TEST_DEFAULTS"] { defaults = UserDefaults(suiteName: suite) ?? .standard }
        #endif
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        let api = APIClient(session: URLSession(configuration: configuration, delegate: BetaRedirectPolicy(), delegateQueue: nil))
        let endpoint = url
        let installed = InstalledBeta(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                      build: build, os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                      deviceFamily: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
        return BetaUpdateStore(installed: installed, defaults: defaults, eligibility: eligibility, fetch: {
            guard StoryContentOrigin.approved(endpoint, debug: _isDebugAssertConfiguration()) else { throw URLError(.badURL) }
            return try await api.data(.url(endpoint), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        })
    }

    func check(force: Bool = false) async {
        guard !checking else { return }
        let now = clock()
        if let candidate, !candidate.eligible(installed: installed, now: now) { self.candidate = nil }
        if !force, let lastCheck, now.timeIntervalSince(lastCheck) < 1800 { return }
        expirationTask?.cancel()
        checking = true; candidate = nil; lastCheck = now
        defer { checking = false }
        do {
            let bytes = try await fetch()
            try Task.checkCancellation()
            guard let target = try BetaReleaseManifest.target(from: bytes, installed: installed, now: clock()),
                  await betaEligibility(), !Task.isCancelled else { return }
            candidate = target
            let dates = ISO8601DateFormatter()
            if let confirmed = dates.date(from: target.confirmedAt), let expiry = dates.date(from: target.expiresAt) {
                let delay = max(0, min(confirmed.addingTimeInterval(86400), expiry).timeIntervalSince(clock()))
                expirationTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    self?.candidate = nil
                }
            }
        } catch { /* Optional notice fails quietly, with no saved/offline target. */ }
    }

    func offer(completedOnboarding: Bool, storyConsumed: Bool, busy: Bool) -> BetaRelease? {
        guard completedOnboarding, storyConsumed, !busy, let candidate,
              candidate.eligible(installed: installed, now: clock()), !dismissed.contains(candidate.identity) else { return nil }
        let until = defaults.double(forKey: "hubBetaUpdateSnooze/\(candidate.identity)")
        guard until <= clock().timeIntervalSince1970 else { return nil }
        return candidate
    }

    func later(_ target: BetaRelease) {
        dismissed.insert(target.identity)
        defaults.set(clock().addingTimeInterval(Self.snooze).timeIntervalSince1970, forKey: "hubBetaUpdateSnooze/\(target.identity)")
    }
}
