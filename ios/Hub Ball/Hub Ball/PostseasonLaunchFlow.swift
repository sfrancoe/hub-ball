import Foundation
import Observation

/// Process-owned ordering. The timeout does not await an uncooperative request.
@MainActor @Observable final class PostseasonLaunchFlow {
    enum Phase { case idle, checking, notice, opening, awaitingReturn, instructions, ready, story, finished }
    private(set) var phase: Phase = .idle
    private(set) var target: BetaRelease?
    private var active = true
    private var leftForUpdate = false
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    private var updatesResolved = false
    private var featuredPrepared = true
    @ObservationIgnored private var featuredTask: Task<Void, Never>?
    static let checkTimeout: Duration = .seconds(2)

    func begin(updates: BetaUpdateStore, featured: FeaturedStoryStore? = nil, timeout: Duration = checkTimeout) {
        guard phase == .idle else { return }
        phase = .checking
        if let featured {
            featuredPrepared = false
            featuredTask = Task { [weak self] in
                await featured.prepare(timeout: timeout)
                guard let self, !Task.isCancelled else { return }
                self.featuredPrepared = true
                if self.phase == .checking && self.updatesResolved { self.phase = featuredPrepared ? .ready : .checking }
            }
        }
        checkTask = Task { [weak self] in
            await updates.check()
            guard !Task.isCancelled else { return }
            self?.resolve(updates.offer(completedOnboarding: true, storyConsumed: true, busy: false))
        }
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.resolve(nil)
        }
    }
    private func resolve(_ target: BetaRelease?) {
        guard phase == .checking && !updatesResolved else { return }
        checkTask?.cancel(); checkTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        self.target = target
        updatesResolved = true
        phase = target == nil ? (featuredPrepared ? .ready : .checking) : .notice
    }
    func dismissNotice(updates: BetaUpdateStore) {
        guard phase == .notice else { return }
        if let target { updates.later(target) }
        target = nil; phase = featuredPrepared ? .ready : .checking
    }
    func noticeUnavailable() {
        guard phase == .notice else { return }
        target = nil; phase = featuredPrepared ? .ready : .checking
    }
    func beginHandoff(updates: BetaUpdateStore) {
        guard phase == .notice else { return }
        if let target { updates.later(target) }
        target = nil; leftForUpdate = false; phase = .opening
    }
    func handoffFinished(opened: Bool) {
        guard phase == .opening else { return }
        phase = opened ? (active && leftForUpdate ? (featuredPrepared ? .ready : .checking) : .awaitingReturn) : .instructions
    }
    func setActive(_ value: Bool) {
        active = value
        if !value && (phase == .opening || phase == .awaitingReturn) { leftForUpdate = true }
        if value && leftForUpdate && phase == .awaitingReturn { phase = featuredPrepared ? .ready : .checking }
    }
    func instructionsDismissed() {
        guard phase == .instructions else { return }
        phase = featuredPrepared ? .ready : .checking
    }
    func didPresentStory() { if phase == .ready { phase = .story } }
    func storyDismissed() { if phase == .story || phase == .ready { phase = .finished } }
    func skip() {
        checkTask?.cancel(); deadlineTask?.cancel(); featuredTask?.cancel(); target = nil; phase = .finished
    }
}

/// Only foreground reading time counts. Replay clears the prior completion hold.
nonisolated struct StoryCompletionHold: Sendable {
    private(set) var elapsed: TimeInterval = 0
    private var anchor: TimeInterval?
    mutating func tick(now: TimeInterval, complete: Bool, duration: TimeInterval) -> Bool {
        guard complete else { reset(); return false }
        if let anchor { elapsed += max(0, now - anchor) }
        anchor = now
        return elapsed >= duration
    }
    mutating func pause() { anchor = nil }
    mutating func reset() { elapsed = 0; anchor = nil }
}
