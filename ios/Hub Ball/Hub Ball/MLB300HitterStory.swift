import SwiftUI
import AVFoundation

private enum HitterStyle {
    static let paper = AppColor.bone
    static let navy = AppColor.night
    static let coral = Color(hubHex: "#BC6259")
    static let gold = Color(hubHex: "#B47B20")
}

struct MLB300HitterStory: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var launched = false
    @State private var building = false
    @State private var startedAt: TimeInterval = 0
    @State private var playbackID = UUID()
    @State private var musicEnabled = false
    @State private var audio = StoryAudioController()
    @State private var audioUnavailable = false
    @State private var selectedIndex = MLB300HitterData.seasons.count - 1
    @State private var showMethodology = false

    private var finish: MLB300HitterData.Season { MLB300HitterData.finish }
    private var peak: MLB300HitterData.Season { MLB300HitterData.peak }

    var body: some View {
        GeometryReader { window in
            let compact = window.size.height < 720 && !typeSize.usesExpandedReadingLayout
            ZStack {
                HitterStyle.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 12 : 22) {
                        Text("The vanishing .300 hitter")
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("Six last year. Six so far in 2026.")
                            .font(compact ? .subheadline : .title3).foregroundStyle(HitterStyle.navy.opacity(0.72))
                        StoryStatCards(expanded: typeSize.usesExpandedReadingLayout, compact: compact)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("QUALIFIED HITTERS · .301 OR HIGHER")
                                .font(.caption.weight(.bold)).tracking(1)
                            Text(MLB300HitterData.coverageLabel)
                                .font(.caption).foregroundStyle(HitterStyle.navy.opacity(0.65))
                            Text(MLB300HitterData.snapshotLabel)
                                .font(.caption2).foregroundStyle(HitterStyle.navy.opacity(0.65))
                                .accessibilityIdentifier("hitter.snapshot")
                        }
                        TimelineView(.animation(paused: !building)) { _ in
                            let elapsed = building ? ProcessInfo.processInfo.systemUptime - startedAt : (launched ? MLB300HitterData.duration : 0)
                            Animated300LineChart(elapsed: elapsed, selectedIndex: $selectedIndex)
                        }
                        .frame(height: compact ? 220 : 280)
                        yearInspector
                        Text("In \(String(peak.year)), \(peak.count) qualified hitters finished above .300. Only six did in 2025. Six qualify so far in 2026—with the final day still to play.")
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                        Button("How we count · methodology") { showMethodology = true }
                            .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("hitter.methodology")
                    }
                    .padding(compact ? 16 : 22)
                    .frame(maxWidth: 740, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityHidden(!launched)
                if !launched {
                    StoryLaunchOverlay(musicEnabled: $musicEnabled, launch: launch, close: { dismiss() })
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if launched { masthead.padding(.horizontal, 22).background(HitterStyle.paper) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if launched {
                    controls
                        .frame(maxWidth: 696, alignment: .leading)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(HitterStyle.paper)
                        .overlay(alignment: .top) { Divider() }
                }
            }
            .foregroundStyle(HitterStyle.navy)
            .tint(HitterStyle.coral)
            .preferredColorScheme(launched ? .light : .dark)
            .task(id: playbackID) {
                guard building else { return }
                let remaining = max(0, MLB300HitterData.duration - (ProcessInfo.processInfo.systemUptime - startedAt))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                guard !Task.isCancelled else { return }
                building = false
            }
            .onDisappear { stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
                musicEnabled = false
                audio.stop()
            }
            .sheet(isPresented: $showMethodology) { methodology }
        }
    }

    private var masthead: some View {
        HStack {
            Text("HUB BALL / STORIES")
                .font(.caption.monospaced().weight(.bold)).tracking(1.5)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close story").accessibilityIdentifier("hitter.close")
        }
    }

    private var yearInspector: some View {
        let season = MLB300HitterData.seasons[selectedIndex]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(season.label).font(.title2.weight(.bold)).monospacedDigit()
                Text("\(season.count) players").font(.title3).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(season.label): \(season.count) qualified hitters")
            .accessibilityIdentifier("hitter.selection")
            Slider(value: Binding(get: { Double(selectedIndex) }, set: { selectedIndex = Int($0.rounded()) }), in: 0...Double(MLB300HitterData.seasons.count - 1), step: 1)
                .accessibilityLabel("Season")
                .accessibilityValue("\(season.label), \(season.count) players")
                .accessibilityIdentifier("hitter.year")
            Text("Tap the chart or slide through the seasons.")
                .font(.caption).foregroundStyle(HitterStyle.navy.opacity(0.65))
        }
        .padding(14)
        .background(HitterStyle.navy.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { replayButton; musicButton }
                VStack(alignment: .leading, spacing: 10) { replayButton; musicButton }
            }
            Text(building ? "Building · 10 seconds" : MLB300HitterData.endingQuestion)
                .font(.caption).foregroundStyle(HitterStyle.navy.opacity(0.65))
                .accessibilityIdentifier(building ? "hitter.building" : "hitter.complete")
            if audioUnavailable {
                Text("Sound is unavailable. The full story continues without it.").font(.caption).accessibilityIdentifier("hitter.audioUnavailable")
            }
        }
    }

    private var replayButton: some View {
        Button { launch() } label: {
            Label("Replay build", systemImage: "arrow.counterclockwise").frame(minHeight: 44)
        }
        .buttonStyle(.bordered).accessibilityIdentifier("hitter.replay")
    }

    private var musicButton: some View {
        Button {
            musicEnabled.toggle()
            updateAudio()
        } label: {
            Label(musicEnabled ? "Music on" : "Music off", systemImage: musicEnabled ? "speaker.wave.2" : "speaker.slash")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered).accessibilityIdentifier("hitter.music")
    }

    private func launch() {
        updateAudio() // This function is called only from a user's tap.
        selectedIndex = MLB300HitterData.seasons.count - 1
        startedAt = ProcessInfo.processInfo.systemUptime
        launched = true
        building = !reduceMotion
        playbackID = UUID()
    }

    private func updateAudio() {
        audioUnavailable = false
        if musicEnabled {
            if !audio.start() { musicEnabled = false; audioUnavailable = true }
        } else { audio.stop() }
    }

    private func stop() {
        building = false
        musicEnabled = false
        audio.stop()
    }

    private var methodology: some View {
        NavigationStack {
            List {
                Section("Above .300 means .301 or higher") {
                    Text("Only hitters whose official, three-decimal batting average is .301 or higher are counted. A player displayed at .300 is excluded, even if his unrounded average is slightly above .300. This is not a count of .300-or-better hitters.")
                }
                Section("Qualification") {
                    Text("The series uses the batting-title threshold of 3.1 plate appearances per team game, with season-length adjustments for shortened seasons, including 1981, 1994, 1995 and 2020.")
                    Text("Historical reconstruction: PA = AB + BB + HBP + SH + SF. AVG = H ÷ AB, rounded to three decimal places before applying the cutoff.")
                }
                Section("The series") {
                    Text("Source: Hub Ball’s supplied editorial handoff, covering completed seasons from 1976 through 2025. The historical counts are reproduced as supplied.")
                    Text("The decline is rounded to the nearest whole percent: (51 − 6) ÷ 51 = 88%. The chart shows player counts, not the share of qualified hitters; MLB’s number of teams has changed over this period.")
                    Text("2026 is a provisional snapshot from MLB’s qualified-hitter leaderboard, checked before the games on September 27, 2026. Six players are displayed at .301 or higher. This snapshot does not update automatically, and the final count may change.")
                    Link("MLB 2026 batting-average leaderboard", destination: URL(string: "https://www.mlb.com/stats/batting-average/2026")!)
                    Text("The final 2026 count will replace this YTD point only after the regular season ends and totals are verified with the same cutoff.")
                }
                Section("Every season") {
                    ForEach(MLB300HitterData.seasons) { season in
                        LabeledContent(season.label, value: "\(season.count) players")
                    }
                }
            }
            .navigationTitle("How we count")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMethodology = false } } }
        }
    }
}

private struct StoryLaunchOverlay: View {
    @Binding var musicEnabled: Bool
    let launch: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HitterStyle.navy.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("HUB BALL / A BASEBALL STORY").font(.caption.monospaced().weight(.bold)).tracking(2)
                        .foregroundStyle(AppColor.amber)
                    Text("The vanishing .300 hitter")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("Six last year.\nSix so far this year.\nWill it end at six again?")
                        .font(.title2).foregroundStyle(AppColor.bone.opacity(0.75)).lineSpacing(6)
                    Button(action: launch) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "play.circle.fill").font(.system(size: 56))
                            Text("Tap to watch the .300 hitter disappear.").font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .background(AppColor.bone.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .accessibilityIdentifier("hitter.launch")
                    Toggle("Music · optional", isOn: $musicEnabled)
                        .tint(AppColor.amber).accessibilityIdentifier("hitter.launchMusic")
                    Text("10 seconds · 1976–2026 YTD\n2026 snapshot: Sept. 27, before today’s games.\nQualified hitters with a displayed average of .301 or higher.")
                        .font(.caption).foregroundStyle(AppColor.bone.opacity(0.65))
                }
                .padding(28).padding(.top, 60)
                .frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .padding(12).accessibilityLabel("Close story").accessibilityIdentifier("hitter.close")
        }
        .foregroundStyle(AppColor.bone)
    }
}

private struct StoryStatCards: View {
    let expanded: Bool
    var compact = false
    var body: some View {
        let layout = expanded ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            stat("\(MLB300HitterData.peak.count)", "Peak, \(String(MLB300HitterData.peak.year))", color: HitterStyle.coral)
            stat("\(MLB300HitterData.finish.count)", MLB300HitterData.finish.label, color: HitterStyle.gold)
            stat("−\(MLB300HitterData.decline)%", "From the peak", color: HitterStyle.navy)
        }
    }
    private func stat(_ number: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number).font(.system(.title, design: .serif).weight(.bold)).foregroundStyle(color)
            Text(label).font(compact ? .caption2 : .caption).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct Animated300LineChart: View {
    let elapsed: TimeInterval
    @Binding var selectedIndex: Int
    private let seasons = MLB300HitterData.seasons

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(x: 27, y: 42, width: max(1, geometry.size.width - 43), height: geometry.size.height - 76)
            let points = seasons.enumerated().map { index, season in
                CGPoint(x: rect.minX + CGFloat(index) / CGFloat(seasons.count - 1) * rect.width,
                        y: rect.maxY - CGFloat(season.count) / 60 * rect.height)
            }
            let progress = MLB300HitterData.progress(elapsed: elapsed)
            ZStack(alignment: .topLeading) {
                ForEach([0, 20, 40, 60], id: \.self) { count in
                    let y = rect.maxY - CGFloat(count) / 60 * rect.height
                    Path { p in p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)) }
                        .stroke(HitterStyle.navy.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Text("\(count)").font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(HitterStyle.navy.opacity(0.5)).position(x: 10, y: y)
                }
                Path { path in path.addLines(points) }
                    .trim(from: 0, to: progress)
                    .stroke(HitterStyle.coral, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(seasons.enumerated()), id: \.element.id) { index, season in
                    Circle()
                        .fill(index == seasons.count - 1 ? HitterStyle.gold : HitterStyle.coral)
                        .frame(width: index == selectedIndex ? 10 : 5, height: index == selectedIndex ? 10 : 5)
                        .position(points[index])
                        .opacity(MLB300HitterData.pointOpacity(index: index, elapsed: elapsed))
                }
                if elapsed >= 5 {
                    callout("\(String(MLB300HitterData.peak.year)) · \(MLB300HitterData.peak.count) players", color: HitterStyle.coral)
                        .position(x: points[MLB300HitterData.peakIndex].x, y: points[MLB300HitterData.peakIndex].y - 23)
                }
                if progress >= 1 {
                    Path { path in
                        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 47))
                        path.addLine(to: points.last!)
                    }
                    .stroke(HitterStyle.gold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    callout("\(MLB300HitterData.finish.label) · \(MLB300HitterData.finish.count) players", color: HitterStyle.gold)
                        .position(x: rect.maxX - 65, y: rect.minY + 32)
                }
                if selectedIndex != MLB300HitterData.peakIndex && selectedIndex != seasons.count - 1 {
                    let selected = seasons[selectedIndex]
                    callout("\(selected.label) · \(selected.count) players", color: HitterStyle.navy)
                        .position(x: min(rect.maxX - 53, max(rect.minX + 53, points[selectedIndex].x)),
                                  y: min(rect.maxY - 12, points[selectedIndex].y + 25))
                }
                ForEach([0, 14, 24, 34, seasons.count - 1], id: \.self) { index in
                    Text(seasons[index].label).font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(HitterStyle.navy.opacity(0.6)).position(x: points[index].x, y: rect.maxY + 20)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in select(value.location.x, rect: rect) })
            .onContinuousHover { phase in
                if case let .active(location) = phase { select(location.x, rect: rect) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Qualified hitters above .300, 1976 through \(MLB300HitterData.finish.label). Peak 51 in 1999; six final in 2025 and six so far in 2026. Snapshot before September 27 games. Use the Season slider below to explore every year.")
            .accessibilityIdentifier("hitter.chart")
        }
    }

    private func select(_ x: CGFloat, rect: CGRect) {
        selectedIndex = min(seasons.count - 1, max(0, Int(((x - rect.minX) / rect.width * CGFloat(seasons.count - 1)).rounded())))
    }

    private func callout(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            .padding(5).background(HitterStyle.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
    }
}
