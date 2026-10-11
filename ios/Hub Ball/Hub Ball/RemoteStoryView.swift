import SwiftUI

private enum EditorialStyle {
    static let paper = Color(hubHex: "#F4F0E6")
    static let ink = Color(hubHex: "#142D3F")
    static let accent = Color(hubHex: "#B64436")
    static let gold = Color(hubHex: "#95600A")
    static let muted = Color(hubHex: "#536777")
}

struct RemoteStoryView: View {
    let entry: StoryEntry
    @Environment(AppModel.self) private var model
    private var store: StoryCatalogStore { model.stories }

    var body: some View {
        Group {
            if !entry.isSupported {
                ContentUnavailableView {
                    Label("A newer story experience", systemImage: "arrow.down.app")
                } description: {
                    Text(entry.fallback + "\n\nUpdate Hub Ball to open the interactive version.")
                }
            } else if let story = store.stories[entry.id] {
                Group {
                    switch story {
                    case .guess(let value):
                        GuessRevealStoryView(story: value, note: store.notes[entry.id]) { await store.load(entry, force: true) }
                    case .outGrid(let value):
                        InningOutGridStoryView(story: value)
                    case .trajectory(let value):
                        TrajectoryStoryView(story: value, note: store.notes[entry.id]) { await store.load(entry, force: true) }
                    }
                }
                .id(store.contentRevision(for: entry.id))
            } else if store.loading.contains(entry.id) {
                ProgressView("Downloading story…")
            } else {
                ContentUnavailableView {
                    Label("Story ready to download", systemImage: "arrow.down.circle")
                } description: { Text(store.notes[entry.id] ?? entry.fallback) }
                actions: { Button("Try again") { Task { await store.load(entry, force: true) } }.accessibilityIdentifier("remote.retry") }
            }
        }
        .background(EditorialStyle.paper.ignoresSafeArea())
        .foregroundStyle(EditorialStyle.ink)
        .navigationTitle("Hub Ball / Stories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(EditorialStyle.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.light)
        .task(id: entry.cacheKey) { await store.load(entry) }
    }
}

/// Reusable interaction primitives. Every label, value, comparison and grid item is data.
struct GuessRevealStoryView: View {
    let story: RemoteStory
    var note: String?
    let refresh: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: String?
    @State private var revealed = false
    @State private var showPassport = false
    @State private var selectedItem: RemoteStory.Passport.Item?
    @State private var showSources = false
    @AccessibilityFocusState private var answerFocused: Bool
    private var reducesMotion: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.environment["HUB_STORY_REDUCE_MOTION"] == "1"
        #else
        reduceMotion
        #endif
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let note {
                        Label(note, systemImage: "arrow.down.circle")
                            .font(.footnote).foregroundStyle(EditorialStyle.muted)
                            .accessibilityIdentifier("remote.cache-note")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(story.kicker.uppercased()).font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(EditorialStyle.accent)
                        Text(story.title).font(.system(.title, design: .serif).weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("remote.title")
                        Text(story.intro).font(.body).lineSpacing(4).foregroundStyle(EditorialStyle.muted)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text(story.question).font(.title3.weight(.semibold)).id("question")
                        choiceLayout {
                            ForEach(Array(story.choices.enumerated()), id: \.element.id) { index, choice in
                                Button { reveal(choice.id) } label: {
                                    choiceCard(choice, index: index)
                                }
                                .buttonStyle(.plain)
                                .disabled(revealed)
                                .accessibilityLabel("\(choice.label), \(choice.value) \(choice.unit), \(choice.detail)")
                                .accessibilityHint("Choose this answer and reveal the result")
                                .accessibilityIdentifier("remote.choice.\(choice.id)")
                            }
                        }
                        if !revealed {
                            Button("Skip the guess · show me") { reveal(nil) }
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                                .accessibilityIdentifier("remote.reveal")
                        }
                    }
                    if revealed {
                        VStack(alignment: .leading, spacing: 14) {
                            if let selection {
                                Text(selection == story.correctChoiceID ? "YOU CALLED IT" : "THAT’S THE TWIST")
                                    .font(.caption.weight(.bold)).tracking(1).foregroundStyle(EditorialStyle.accent)
                            }
                            Text(story.answerTitle).font(.system(.title, design: .serif).weight(.bold))
                                .accessibilityFocused($answerFocused).accessibilityIdentifier("remote.answer")
                            Text(story.answer).font(.body).lineSpacing(4)
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                        .transition(.opacity)
                        if !story.stats.isEmpty { statCards }
                        if !story.bars.isEmpty { comparisonChart }
                        if let passport = story.passport { passportSection(passport) }
                        Text(story.conclusion).font(.system(.title3, design: .serif)).lineSpacing(4)
                        Button {
                            revealed = false; selection = nil; showPassport = false
                            scroll.scrollTo("question", anchor: .top)
                        } label: { Label("Try the reveal again", systemImage: "arrow.counterclockwise") }
                            .frame(minHeight: 44).accessibilityIdentifier("remote.replay")
                    }
                    Button { showSources = true } label: { Label("Sources & how we count", systemImage: "info.circle") }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .accessibilityIdentifier("remote.sources")
                }
                .padding(22).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity)
            }
            .refreshable { await refresh() }
        }
        .background(EditorialStyle.paper.ignoresSafeArea())
        .foregroundStyle(EditorialStyle.ink).tint(EditorialStyle.accent)
        .sheet(isPresented: $showSources) { sources }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ParkStamp(result: item.result).frame(height: 130)
                        Text(item.name).font(.system(.title, design: .serif).bold())
                        Text(item.resultLabel).font(.headline).foregroundStyle(EditorialStyle.accent)
                        Text(item.detail).font(.body).lineSpacing(4)
                        Text("An illustrated stamp, not a measured stadium diagram.").font(.footnote).foregroundStyle(EditorialStyle.muted)
                    }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
                .background(EditorialStyle.paper.ignoresSafeArea())
                .navigationTitle(item.label).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedItem = nil }.accessibilityIdentifier("remote.detail.close") } }
            }.tint(EditorialStyle.accent).preferredColorScheme(.light)
        }
    }

    private var choiceLayout: AnyLayout {
        typeSize >= .xxxLarge || story.choices.count > 2 ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    private func choiceCard(_ choice: RemoteStory.Choice, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(choice.label.uppercased()).font(.caption.weight(.bold)).tracking(1)
                Spacer(minLength: 4)
                Image(systemName: revealed && choice.id == story.correctChoiceID ? "checkmark.circle.fill" : "circle")
            }
            Text(choice.value).font(.system(.largeTitle, design: .serif).weight(.black))
            Text(choice.unit.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(EditorialStyle.muted)
            // An original two-direction motif; no trajectory or stadium dimensions are implied.
            ChoiceArc(mirrored: index.isMultiple(of: 2)).stroke(EditorialStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 5]))
                .frame(height: 34).accessibilityHidden(true)
            Text(choice.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(revealed && choice.id == story.correctChoiceID ? EditorialStyle.accent : EditorialStyle.ink.opacity(0.12), lineWidth: 2) }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    private func reveal(_ choice: String?) {
        selection = choice
        withAnimation(reducesMotion ? nil : .easeOut(duration: 0.35)) { revealed = true }
        answerFocused = true
    }

    private var statCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize >= .xxxLarge ? 250 : 140))], alignment: .leading, spacing: 12) {
            ForEach(Array(story.stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.label).font(.caption.weight(.bold)).foregroundStyle(EditorialStyle.muted)
                    Text(stat.value).font(.system(.title, design: .serif).bold()).foregroundStyle(EditorialStyle.accent)
                    Text(stat.note).font(.footnote)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
            }
        }
    }
    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("COMPARE THE NUMBERS").font(.caption.weight(.bold)).tracking(1).foregroundStyle(EditorialStyle.muted)
            ForEach(Array(story.bars.enumerated()), id: \.offset) { _, bar in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(bar.label) · \(bar.value.formatted()) \(bar.unit)").font(.headline)
                    GeometryReader { geometry in
                        Capsule().fill(EditorialStyle.ink.opacity(0.09))
                        Capsule().fill(EditorialStyle.accent).frame(width: max(bar.value > 0 ? 4 : 0, geometry.size.width * bar.value / max(1, story.barMaximum ?? story.bars.map(\.value).max() ?? 1)))
                    }.frame(height: 12).accessibilityHidden(true)
                    Text(bar.detail).font(.subheadline).foregroundStyle(EditorialStyle.muted)
                }.accessibilityElement(children: .combine)
            }
        }.accessibilityIdentifier("remote.chart")
    }

    private func passportSection(_ passport: RemoteStory.Passport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(passport.title).font(.system(.title2, design: .serif).bold())
            Text(passport.intro).font(.subheadline).lineSpacing(3).foregroundStyle(EditorialStyle.muted)
            Button {
                withAnimation(reducesMotion ? nil : .easeOut(duration: 0.25)) { showPassport.toggle() }
            } label: {
                HStack {
                    Label(showPassport ? "Close the passport" : "Open the park passport", systemImage: "book.closed")
                    Spacer()
                    Image(systemName: showPassport ? "chevron.up" : "chevron.down")
                }.font(.headline).padding(16).frame(minHeight: 44)
                    .background(EditorialStyle.ink, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
            }.buttonStyle(.plain).accessibilityIdentifier("remote.passport")
                .accessibilityValue(showPassport ? "Expanded" : "Collapsed")
            if showPassport {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize >= .xxxLarge ? 150 : 90))], spacing: 12) {
                    ForEach(passport.items) { item in
                        Button { selectedItem = item } label: {
                            VStack(spacing: 8) {
                                ParkStamp(result: item.result).frame(height: 45)
                                Text(item.label).font(.caption.weight(.black))
                                Image(systemName: item.result == "yes" ? "star.fill" : item.result == "no" ? "minus" : "questionmark")
                                    .font(.caption).foregroundStyle(item.result == "yes" ? EditorialStyle.accent : EditorialStyle.muted)
                            }.padding(12).frame(maxWidth: .infinity)
                                .background(item.result == "yes" ? Color.white : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(item.result == "yes" ? EditorialStyle.accent : EditorialStyle.ink.opacity(0.12), lineWidth: item.result == "yes" ? 2 : 1) }
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(item.name), \(item.resultLabel)")
                            .accessibilityHint("Opens the park detail")
                            .accessibilityIdentifier("remote.park.\(item.id)")
                    }
                }.accessibilityIdentifier("remote.grid")
            }
        }
    }
    private var sources: some View {
        NavigationStack {
            List {
                Section("How we count") {
                    ForEach(Array(story.methodology.enumerated()), id: \.offset) { _, paragraph in Text(paragraph) }
                }
                Section("Original sources") {
                    ForEach(story.sources) { source in
                        if let url = StoryContract.sourceURL(source.url) {
                            VStack(alignment: .leading, spacing: 6) {
                                Link(source.title, destination: url)
                                Text("Checked \(source.retrievedAt.prefix(10))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle("Sources & methodology")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false }.accessibilityIdentifier("remote.sources.close") } }
        }.tint(EditorialStyle.accent).preferredColorScheme(.light)
    }
}

private struct ChoiceArc: Shape {
    var mirrored: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: mirrored ? rect.maxX : rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: mirrored ? rect.minX : rect.maxX, y: rect.maxY * 0.4), control: CGPoint(x: rect.midX, y: -rect.height * 0.65))
        }
    }
}

private struct ParkStamp: View {
    let result: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(2)
            Image(systemName: "baseball.diamond.bases").resizable().scaledToFit().padding(8)
        }.foregroundStyle(result == "yes" ? EditorialStyle.accent : EditorialStyle.muted.opacity(0.65))
            .accessibilityHidden(true)
    }
}
