import UIKit

/// Apple associates this HTTPS route with TestFlight. Restrict opening to an
/// installed associated app; the web/App Store fallback is never an app handoff.
@MainActor enum TestFlightHandoff {
    static let url = URL(string: "https://testflight.apple.com/a")!
    typealias Opener = @MainActor (URL, [UIApplication.OpenExternalURLOptionsKey: Any]) async -> Bool

    static func open(using opener: Opener = liveOpen) async -> Bool {
        await opener(url, [.universalLinksOnly: true])
    }

    private static func liveOpen(_ url: URL, _ options: [UIApplication.OpenExternalURLOptionsKey: Any]) async -> Bool {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["HUB_TESTFLIGHT_HANDOFF"] {
        case "success": return true
        case "failure": return false
        default: break
        }
        #endif
        return await UIApplication.shared.open(url, options: options)
    }
}
