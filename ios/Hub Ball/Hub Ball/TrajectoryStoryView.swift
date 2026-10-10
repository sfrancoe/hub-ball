import SwiftUI

private enum TrajectoryStyle {
    static let paper = AppColor.bone
    static let ink = AppColor.night
    static func color(_ name: String) -> Color {
        switch name {
        case "coral": Color(hubHex: "#A84138")
        case "gold": Color(hubHex: "#876010")
        case "teal": Color(hubHex: "#23726D")
        case "purple": Color(hubHex: "#78568D")
        case "gray": Color(hubHex: "#5E6974")
        default: Color(hubHex: "#183A56")
        }
    }
}

struct TrajectoryStoryView: View {
    let story: TrajectoryStory
    var note: String?
    let refresh: () async -> Void
    var endpointLabels: [String]? = nil
    var numbers: TrajectoryNumberPresentation = .standard
    var onCompleted: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var playback = TrajectoryPlayback()
    @State private var launched = false
    @State private var paused = false
    @State private var showSources = false
    @State private var showData = false
    @State private var completionHold = StoryCompletionHold()
    @State private var completionDelivered = false
    private var reduced: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.environment["HUB_STORY_REDUCE_MOTION"] == "1"
        #else
        reduceMotion
        #endif
    }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var previewTime: Double? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HUB_STORY_PREVIEW_TIME"], let value = Double(raw), value.isFinite, (0...story.chart.durationSeconds).contains(value) { return value }
        #endif
        return nil
    }
    private var finalSummary: String {
        story.chart.series.map { "\($0.label): \(numbers.axis($0.points.last?.y ?? 0)) \(story.chart.yAxis.label)" }.joined(separator: ". ")
    }
    var body: some View {
        GeometryReader { window in
            let compact = window.size.height < 750 && !typeSize.isAccessibilitySize
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                    if let note { Text(note).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("remote.cache-note") }
                    VStack(alignment: .leading, spacing: 9) {
                        Text(story.kicker.uppercased()).font(.caption.weight(.bold)).tracking(1).foregroundStyle(TrajectoryStyle.color("coral"))
                        Text(story.title).font(.system(compact ? .title2 : .title, design: .serif).weight(.bold))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("remote.title")
                        Text(story.intro).font(.body).foregroundStyle(TrajectoryStyle.ink.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
                    }
                    TimelineView(.animation(paused: paused || reduced || previewTime != nil || scenePhase != .active)) { _ in
                        let time = previewTime ?? playback.time(now: now, duration: story.chart.durationSeconds)
                        let frame = story.chart.frame(at: time)
                        let progress = frame.progress
                        VStack(alignment: .leading, spacing: 12) {
                            seriesLegend(frame: frame)
                            chartMetadataLayout {
                                Text(story.chart.yAxis.label.uppercased()).font(.caption.weight(.bold)).tracking(0.7)
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Text("\(story.chart.sequence == nil ? "" : story.chart.series[frame.activeSeries].label + " · ")\(story.chart.xAxis.label): \(numbers.axis(story.chart.displayedProgress(progress), grouping: false))")
                                    .font(.caption.monospacedDigit()).accessibilityIdentifier("trajectory.progress")
                            }
                            ZStack(alignment: .bottomTrailing) {
                                TrajectoryCanvas(chart: story.chart, frame: frame, endpointLabels: endpointLabels, numbers: numbers)
                                    .frame(height: typeSize.isAccessibilitySize ? 250 : compact ? 220 : window.size.width >= 650 ? 340 : 260)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(story.chart.kind) chart. \(story.chart.xAxis.label), \(numbers.axis(story.chart.xAxis.minimum, grouping: false)) to \(numbers.axis(story.chart.xAxis.maximum, grouping: false)); \(story.chart.yAxis.label), \(numbers.axis(story.chart.yAxis.minimum)) to \(numbers.axis(story.chart.yAxis.maximum)).")
                                    .accessibilityValue(numbers == .wholeRunCounts ? currentSummary(frame: frame) : frame.beat?.comparison == nil ? finalSummary : finalSummary + ". " + (frame.beat?.detail ?? ""))
                                    .accessibilityHint("Use Explore the data for each plotted value")
                                    .accessibilityIdentifier("trajectory.chart")
                                Button { replay() } label: {
                                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(TrajectoryStyle.color("coral"))
                                        .frame(width: 44, height: 44)
                                        .background(TrajectoryStyle.paper.opacity(0.95), in: Circle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Replay chart from the beginning")
                                    .accessibilityIdentifier("trajectory.replay")
                                    .padding(.trailing, 22).padding(.bottom, 32)
                            }
                            Text(story.chart.xAxis.label).font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                            emphasis(beat: frame.beat).id("trajectory.payoff")
                            HStack(spacing: 20) {
                                if !reduced && time < story.chart.durationSeconds {
                                    Button {
                                        if paused { playback.resume(now: now, duration: story.chart.durationSeconds) }
                                        else { playback.pause(now: now, duration: story.chart.durationSeconds); completionHold.pause() }
                                        paused.toggle()
                                    } label: { Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") }
                                    .accessibilityIdentifier("trajectory.pause")
                                }
                                Spacer(minLength: 0)
                            }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            Text(time >= story.chart.durationSeconds ? "Chart complete" : paused ? "Chart paused" : "Chart building")
                                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("trajectory.status")
                        }
                    }
                    Text(story.conclusion).font(.system(.body, design: .serif)).lineSpacing(4).accessibilityIdentifier("trajectory.conclusion")
                    HStack {
                        Button("Explore the data") { showData = true }.accessibilityIdentifier("trajectory.data")
                        Spacer(minLength: 12)
                        Button("Sources & methodology") { showSources = true }.accessibilityIdentifier("trajectory.sources")
                    }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
                }
                .padding(compact ? 16 : 22).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
            }
            .refreshable { await refresh() }
            .onChange(of: playback.elapsed >= story.chart.durationSeconds) { _, complete in
                if complete && onCompleted != nil && previewTime == nil {
                    withAnimation(.easeOut(duration: 0.25)) { scroll.scrollTo("trajectory.payoff", anchor: .bottom) }
                }
            }
            }
        }
        .background(TrajectoryStyle.paper.ignoresSafeArea()).foregroundStyle(TrajectoryStyle.ink).tint(TrajectoryStyle.color("coral"))
        .onAppear {
            if !launched { playback.start(now: now, reducedMotion: reduced, duration: story.chart.durationSeconds); launched = true; paused = reduced }
            else if !paused { playback.resume(now: now, duration: story.chart.durationSeconds) }
        }
        .background {
            PlaybackClock(active: launched && (!paused || (onCompleted != nil && playback.elapsed >= story.chart.durationSeconds)) && previewTime == nil && scenePhase == .active && !showSources && !showData && !completionDelivered) { clock in
                let complete = playback.time(now: clock, duration: story.chart.durationSeconds) >= story.chart.durationSeconds
                if complete && !paused {
                    playback.pause(now: clock, duration: story.chart.durationSeconds); paused = true
                }
                if let onCompleted, completionHold.tick(now: clock, complete: complete, duration: typeSize.isAccessibilitySize || voiceOverEnabled ? 15 : 6) {
                    completionDelivered = true
                    onCompleted()
                }
            }
        }
        .onDisappear { playback.pause(now: now, duration: story.chart.durationSeconds); completionHold.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !paused { playback.resume(now: now, duration: story.chart.durationSeconds) }
            else { playback.pause(now: now, duration: story.chart.durationSeconds); completionHold.pause() }
        }
        .onChange(of: reduced) { _, value in
            if value { playback.start(now: now, reducedMotion: true, duration: story.chart.durationSeconds); paused = true }
        }
        .onChange(of: showSources) { _, _ in completionHold.pause() }
        .onChange(of: showData) { _, _ in completionHold.pause() }
        .sheet(isPresented: $showSources) {
            NavigationStack {
                List {
                    Section("How we count") { ForEach(Array(story.methodology.enumerated()), id: \.offset) { _, text in Text(text) } }
                    Section("Original sources") {
                        ForEach(story.sources) { source in
                            VStack(alignment: .leading, spacing: 5) {
                                if let url = StoryContract.sourceURL(source.url) { Link(source.title, destination: url) }
                                Text("Checked \(source.retrievedAt.prefix(10))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.navigationTitle("Sources & methodology")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false }.accessibilityIdentifier("trajectory.sources.close") } }
            }.preferredColorScheme(.light)
        }
        .sheet(isPresented: $showData) {
            NavigationStack {
                List {
                    ForEach(story.chart.series) { series in
                        Section(series.label) {
                            ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                                Text("\(story.chart.xAxis.label): \(numbers.axis(point.x, grouping: false)) · \(story.chart.yAxis.label): \(numbers.axis(point.y))")
                                    .accessibilityLabel("\(series.label). \(story.chart.xAxis.label), \(numbers.axis(point.x, grouping: false)). \(story.chart.yAxis.label), \(numbers.axis(point.y)).")
                            }
                        }
                    }
                }.navigationTitle("Explore the data")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showData = false }.accessibilityIdentifier("trajectory.data.close") } }
            }.preferredColorScheme(.light)
        }
    }
    private func replay() {
        completionHold.reset(); completionDelivered = false
        playback.start(now: now, reducedMotion: reduced, duration: story.chart.durationSeconds); paused = reduced
    }
    private var chartMetadataLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
    }
    private func currentSummary(frame: TrajectoryStory.Chart.Frame) -> String {
        story.chart.series.enumerated().map { index, series in
            let value = frame.progresses[index].map { numbers.counter(story.chart.value(in: series, at: $0)) } ?? "0"
            return "\(series.label): \(value) \(story.chart.yAxis.label)"
        }.joined(separator: ". ")
    }
    private func seriesLegend(frame: TrajectoryStory.Chart.Frame) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 85), alignment: .leading), count: min(story.chart.series.count, typeSize.isAccessibilitySize ? 1 : 3)), alignment: .leading, spacing: 10) {
            ForEach(Array(story.chart.series.enumerated()), id: \.element.id) { index, series in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Rectangle().fill(TrajectoryStyle.color(series.color)).frame(width: 18, height: index == story.chart.series.count - 1 ? 4 : 2)
                        Text(series.label).font(.caption.weight(.bold))
                    }
                    Text(frame.progresses[index].map { numbers.counter(story.chart.value(in: series, at: $0)) } ?? "—")
                        .font(.system(.title2, design: .serif).weight(.bold)).monospacedDigit()
                    Text(story.chart.yAxis.label).font(.caption)
                }.foregroundStyle(TrajectoryStyle.color(series.color))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("trajectory.series.\(series.id)")
            }
        }
    }
    @ViewBuilder private func emphasis(beat: TrajectoryStory.Chart.Emphasis?) -> some View {
        if let beat {
            VStack(alignment: .leading, spacing: 5) {
                Text(beat.title).font(.system(.headline, design: .serif)).accessibilityIdentifier("trajectory.emphasis")
                Text(beat.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text("The chart builds automatically. Every series uses the same scale.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
        }
    }
}

private struct TrajectoryCanvas: View {
    let chart: TrajectoryStory.Chart
    let frame: TrajectoryStory.Chart.Frame
    var endpointLabels: [String]? = nil
    var numbers: TrajectoryNumberPresentation = .standard
    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 30, y: 8, width: max(1, size.width - (endpointLabels != nil ? 128 : chart.kind == "bar" ? 110 : 72)), height: max(1, size.height - 38))
            let barInset = chart.kind == "bar" ? plot.width / CGFloat(chart.series[0].points.count) / 2 : 0
            func px(_ x: Double) -> CGFloat { plot.minX + barInset + (x - chart.xAxis.minimum) / (chart.xAxis.maximum - chart.xAxis.minimum) * (plot.width - 2 * barInset) }
            func py(_ y: Double) -> CGFloat { plot.maxY - (y - chart.yAxis.minimum) / (chart.yAxis.maximum - chart.yAxis.minimum) * plot.height }
            for y in chart.yAxis.ticks {
                var path = Path(); path.move(to: CGPoint(x: plot.minX, y: py(y))); path.addLine(to: CGPoint(x: plot.maxX, y: py(y)))
                context.stroke(path, with: .color(TrajectoryStyle.ink.opacity(0.13)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                context.draw(Text(numbers.axis(y)).font(.system(size: 11, weight: .medium)).foregroundStyle(TrajectoryStyle.ink), at: CGPoint(x: plot.minX - 7, y: py(y)), anchor: .trailing)
            }
            if chart.yAxis.minimum < 0 && chart.yAxis.maximum > 0 {
                var baseline = Path(); baseline.move(to: CGPoint(x: plot.minX, y: py(0))); baseline.addLine(to: CGPoint(x: plot.maxX, y: py(0)))
                context.stroke(baseline, with: .color(TrajectoryStyle.ink.opacity(0.55)), lineWidth: 1.5)
            }
            for x in chart.xAxis.ticks {
                context.draw(Text(numbers.axis(x, grouping: false)).font(.system(size: 11, weight: .medium)).foregroundStyle(TrajectoryStyle.ink), at: CGPoint(x: px(x), y: plot.maxY + 16))
            }
            if let beat = frame.beat, beat.comparison == nil, endpointLabels == nil {
                var reference = Path(); reference.move(to: CGPoint(x: plot.minX, y: py(beat.y))); reference.addLine(to: CGPoint(x: plot.maxX, y: py(beat.y)))
                context.stroke(reference, with: .color(TrajectoryStyle.color("coral").opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                context.draw(Text(numbers.axis(beat.y)).font(.system(size: 11, weight: .bold)).foregroundStyle(TrajectoryStyle.color("coral")), at: CGPoint(x: plot.maxX + 5, y: py(beat.y)), anchor: .leading)
            }
            for (index, series) in chart.series.enumerated() {
                guard let progress = frame.progresses[index] else { continue }
                let color = TrajectoryStyle.color(series.color)
                if chart.kind == "bar" {
                    let slot = plot.width / CGFloat(series.points.count) / CGFloat(chart.series.count)
                    for point in series.points where point.x <= progress {
                        let rect = CGRect(x: px(point.x) - slot * CGFloat(chart.series.count) / 2 + slot * CGFloat(index), y: min(py(0), py(point.y)), width: max(1, slot * 0.8), height: abs(py(0) - py(point.y)))
                        context.fill(Path(rect), with: .color(color))
                        if series.points.count <= 8 {
                            context.draw(Text(numbers.axis(point.y)).font(.system(size: 11, weight: .bold)).foregroundStyle(color), at: CGPoint(x: rect.midX, y: rect.minY - 9))
                        }
                    }
                } else {
                    var path = Path(); let first = series.points[0]
                    path.move(to: CGPoint(x: px(first.x), y: py(first.y)))
                    var previous = first
                    for point in series.points.dropFirst() where point.x <= progress {
                        if chart.kind == "step" { path.addLine(to: CGPoint(x: px(point.x), y: py(previous.y))) }
                        path.addLine(to: CGPoint(x: px(point.x), y: py(point.y))); previous = point
                    }
                    path.addLine(to: CGPoint(x: px(progress), y: py(chart.value(in: series, at: progress))))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: index == chart.series.count - 1 ? 3 : 2, lineCap: .round, lineJoin: .round, dash: index == 0 ? [5, 3] : []))
                    context.fill(Path(ellipseIn: CGRect(x: px(progress) - 3, y: py(chart.value(in: series, at: progress)) - 3, width: 6, height: 6)), with: .color(color))
                }
            }
            if let labels = endpointLabels, labels.count == chart.series.count,
               frame.progresses.allSatisfy({ $0 == chart.xAxis.maximum }) {
                let ordered = chart.series.indices.sorted { chart.series[$0].points.last!.y > chart.series[$1].points.last!.y }
                var previousY: CGFloat = -100
                for index in ordered {
                    let point = chart.series[index].points.last!
                    let labelY = min(plot.maxY - 12, max(py(point.y), previousY + 20))
                    previousY = labelY
                    let color = TrajectoryStyle.color(chart.series[index].color)
                    var connector = Path(); connector.move(to: CGPoint(x: px(point.x), y: py(point.y)))
                    connector.addLine(to: CGPoint(x: plot.maxX + 8, y: labelY))
                    context.stroke(connector, with: .color(color), lineWidth: 1)
                    context.draw(Text("\(labels[index]) \(numbers.axis(point.y))").font(.system(size: 12, weight: .bold)).foregroundStyle(color), at: CGPoint(x: plot.maxX + 11, y: labelY), anchor: .leading)
                }
            }
            if let beat = frame.beat, endpointLabels == nil {
                context.stroke(Path(ellipseIn: CGRect(x: px(beat.x) - 5, y: py(beat.y) - 5, width: 10, height: 10)), with: .color(TrajectoryStyle.ink), lineWidth: 1.5)
                if let comparison = beat.comparison, let target = chart.series.first(where: { $0.id == comparison.targetSeriesID }), let endpoint = target.points.last {
                    let start = CGPoint(x: px(beat.x) + 7, y: py(beat.y))
                    let end = CGPoint(x: px(endpoint.x) - 5, y: py(endpoint.y))
                    let color = TrajectoryStyle.color("coral").opacity(frame.comparisonStrength)
                    var arrow = Path(); arrow.move(to: start); arrow.addLine(to: end)
                    context.stroke(arrow.trimmedPath(from: 0, to: frame.comparisonDraw), with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    if frame.comparisonDraw >= 1 {
                        var head = Path(); head.move(to: CGPoint(x: end.x - 7, y: end.y - 5)); head.addLine(to: end); head.addLine(to: CGPoint(x: end.x - 7, y: end.y + 5))
                        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    let radius = 5 + 3 * frame.comparisonStrength
                    context.stroke(Path(ellipseIn: CGRect(x: px(endpoint.x) - radius, y: py(endpoint.y) - radius, width: radius * 2, height: radius * 2)), with: .color(color), lineWidth: 2)
                    context.draw(Text(numbers.axis(endpoint.y)).font(.system(size: 13, weight: .bold)).foregroundStyle(color), at: CGPoint(x: px(endpoint.x) + 12, y: py(endpoint.y)), anchor: .leading)
                }
            }
        }
    }
}
