import SwiftUI

struct InningOutGridStoryView: View {
    let story: InningOutGridStory
    var close: (() -> Void)? = nil
    var onCompleted: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 36.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 22.0
    @ScaledMetric(relativeTo: .body) private var tileHeight = 46.0
    @State private var playback = TrajectoryPlayback()
    @State private var launched = false
    @State private var hold = StoryCompletionHold()
    @State private var delivered = false
    private let navy = Color(hubHex: "#0C2340")
    private let red = Color(hubHex: "#B61A32")
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var reduced: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.environment["HUB_STORY_REDUCE_MOTION"] == "1"
        #else
        reduceMotion
        #endif
    }
    private var previewTime: Double? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HUB_STORY_PREVIEW_TIME"], let value = Double(raw), value.isFinite, (0...story.durationSeconds).contains(value) { return value }
        #endif
        return nil
    }
    var body: some View {
        GeometryReader { window in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(story.heading).font(.system(size: headingSize, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("out-grid.heading")
                        Text(story.commentary).font(.system(size: bodySize * (window.size.width >= 650 ? 26.0 / 22.0 : 1)))
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                            .accessibilityIdentifier("out-grid.commentary")
                        TimelineView(.animation(paused: reduced || scenePhase != .active || previewTime != nil || playback.elapsed >= story.durationSeconds)) { _ in
                            let time = previewTime ?? playback.time(now: now, duration: story.durationSeconds)
                            let revealed = story.revealedOuts(at: time)
                            VStack(spacing: 16) {
                                if typeSize.isAccessibilitySize {
                                    ScrollView(.horizontal) { grid(revealed: revealed).frame(minWidth: 660) }
                                } else { grid(revealed: revealed) }
                                VStack(spacing: 2) {
                                    Text("\(story.strikeouts(at: time)) OF 27")
                                        .font(.system(.largeTitle, design: .rounded).weight(.black).monospacedDigit())
                                        .accessibilityIdentifier("out-grid.count")
                                    Text("STRIKEOUTS").font(.headline.weight(.bold)).tracking(2)
                                }.accessibilityElement(children: .combine)
                                    .accessibilityValue("\(revealed) of 27 outs revealed")
                                    .accessibilityIdentifier("out-grid.summary")
                                    .id("out-grid.payoff")
                            }
                        }
                        Button { replay() } label: {
                            Label("Replay", systemImage: "arrow.counterclockwise")
                                .font(.headline).frame(minHeight: 44).frame(maxWidth: .infinity)
                        }.accessibilityIdentifier("out-grid.replay")
                    }.padding(18).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                }
                .onChange(of: playback.elapsed >= story.durationSeconds) { _, complete in
                    if complete && onCompleted != nil && previewTime == nil {
                        if reduced { scroll.scrollTo("out-grid.payoff", anchor: .bottom) }
                        else { withAnimation(.easeOut(duration: 0.25)) { scroll.scrollTo("out-grid.payoff", anchor: .bottom) } }
                    }
                }
            }
        }
        .background(navy.ignoresSafeArea()).foregroundStyle(.white).tint(.white)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(navy, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if let close { ToolbarItem(placement: .topBarTrailing) {
                Button("Dismiss", action: close).frame(minHeight: 44).accessibilityIdentifier("private-launch.dismiss")
            } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !launched { playback.start(now: now, reducedMotion: reduced, duration: story.durationSeconds); launched = true }
            else { playback.resume(now: now, duration: story.durationSeconds) }
        }
        .background {
            PlaybackClock(active: launched && !delivered && scenePhase == .active && previewTime == nil) { clock in
                let complete = playback.time(now: clock, duration: story.durationSeconds) >= story.durationSeconds
                if complete { playback.pause(now: clock, duration: story.durationSeconds) }
                if let onCompleted, hold.tick(now: clock, complete: complete, duration: typeSize.isAccessibilitySize || voiceOver ? 15 : 6) {
                    delivered = true; onCompleted()
                }
            }
        }
        .onDisappear { playback.pause(now: now, duration: story.durationSeconds); hold.pause() }
        .onChange(of: scenePhase) { _, phase in
            hold.pause()
            if phase == .active { playback.resume(now: now, duration: story.durationSeconds) }
            else { playback.pause(now: now, duration: story.durationSeconds) }
        }
        .onChange(of: reduced) { _, value in
            if value { playback.start(now: now, reducedMotion: true, duration: story.durationSeconds); hold.reset() }
        }
    }
    private func grid(revealed: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
            ForEach(1...9, id: \.self) { inning in
                VStack(spacing: 9) {
                    Text("INNING \(inning)").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75)).accessibilityHidden(true)
                    HStack(spacing: 4) {
                        ForEach(story.outs.filter { $0.inning == inning }) { out in
                            let visible = out.number <= revealed
                            Text(visible ? (out.result == .strikeout ? "K" : "OUT") : "·")
                                .font(.system(size: visible && out.result == .strikeout ? 27 : 10, weight: .black))
                                .frame(maxWidth: .infinity).frame(height: tileHeight)
                                .background(visible ? (out.result == .strikeout ? red : Color(hubHex: "#626D7B")) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                                .accessibilityLabel("Inning \(inning), out \((out.number - 1) % 3 + 1): \(visible ? (out.result == .strikeout ? "strikeout" : "other out") : "not revealed")")
                                .accessibilityIdentifier("out-grid.out.\(out.number)")
                        }
                    }
                }.padding(8).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            }
        }.accessibilityIdentifier("out-grid.panels")
    }
    private func replay() {
        hold.reset(); delivered = false
        playback.start(now: now, reducedMotion: reduced, duration: story.durationSeconds)
    }
}
