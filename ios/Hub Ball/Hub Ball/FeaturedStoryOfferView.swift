import SwiftUI

/// Owned by the app model, so rebuilding a tab or returning from background cannot reoffer it.
struct FeaturedStoryLaunch {
    private(set) var consumed = false
    private(set) var offeredID: String?
    private let defaults: UserDefaults
    static let acknowledgementKey = "hubFeaturedAcknowledgedStoryIDs.v1"
    init(defaults: UserDefaults? = nil) {
        #if DEBUG
        let name = ProcessInfo.processInfo.environment["HUB_FEATURED_ACK_DEFAULTS"]
        self.defaults = defaults ?? name.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        #else
        self.defaults = defaults ?? .standard
        #endif
    }
    func acknowledged(_ id: String) -> Bool {
        (defaults.stringArray(forKey: Self.acknowledgementKey) ?? []).contains(id)
    }
    mutating func acknowledge(_ id: String) {
        guard StoryContract.slug(id) else { return }
        var values = defaults.stringArray(forKey: Self.acknowledgementKey) ?? []
        if !values.contains(id) && values.count < 1_024 { values.append(id); defaults.set(values, forKey: Self.acknowledgementKey) }
    }
    mutating func offer(completedOnboarding: Bool, busy: Bool, entry: StoryEntry?) -> StoryEntry? {
        guard completedOnboarding && !busy && !consumed else { return nil }
        consumed = true
        guard let entry, entry.isSupported, !acknowledged(entry.id), (defaults.stringArray(forKey: Self.acknowledgementKey) ?? []).count < 1_024 else { return nil }
        offeredID = entry.id
        return entry
    }
}

struct FeaturedStoryOfferView: View {
    let entry: StoryEntry
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var watching = false
    @State private var detent = PresentationDetent.height(400)
    var body: some View {
        NavigationStack {
            ScrollView {
                StoryPreviewCard(title: entry.title, summary: entry.summary, action: entry.actionLabel,
                                 watch: { detent = .large; watching = true }, dismiss: close)
                    .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(AppColor.paleRed.ignoresSafeArea())
                .navigationTitle("Featured story").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $watching) {
                    RemoteStoryView(entry: entry)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button("Done", action: close).accessibilityIdentifier("featured.close")
                        } }
                }
        }.preferredColorScheme(.light)
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(400), .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .onAppear { if typeSize.isAccessibilitySize { detent = .large } }
            .onChange(of: typeSize) { _, value in if value.isAccessibilitySize { detent = .large } }
    }
}


/// Playback receives the pinned verified revision only after the user's Play action.
struct FeaturedStoryCardView: View {
    let item: FeaturedStoryItem
    let acknowledge: () -> Void
    let close: () -> Void
    @State private var playing = false
    var body: some View {
        Group { content }.task {
            guard let expiry = item.offerExpiresAt else { return }
            let delay = expiry.timeIntervalSinceNow
            if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
            guard !Task.isCancelled else { return }; close()
        }
    }
    @ViewBuilder private var content: some View {
        if playing {
            FeaturedStoryDocumentView(item: item, close: close)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(item.hookTitle).font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("featured.hook")
                        Text(item.hookSummary).font(.title3).foregroundStyle(Color(hubHex: "#F6C873"))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("featured.hook-summary")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) { actions }
                            VStack(alignment: .leading, spacing: 18) { actions }
                        }
                    }.padding(28).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
                }.background(Color(hubHex: "#0B1628").ignoresSafeArea())
            }.preferredColorScheme(.dark)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    @ViewBuilder private var actions: some View {
        Button("Dismiss") { acknowledge(); close() }.buttonStyle(.bordered).tint(.white)
            .frame(minHeight: 48).accessibilityIdentifier("featured.dismiss")
        Button { acknowledge(); playing = true } label: { Label("Play", systemImage: "play.fill") }
            .buttonStyle(.borderedProminent).tint(Color(hubHex: "#F6C873")).foregroundStyle(Color(hubHex: "#0B1628"))
            .frame(minHeight: 48).accessibilityIdentifier("featured.play")
    }
}
