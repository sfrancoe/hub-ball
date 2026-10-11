import SwiftUI

struct StoriesView: View {
    var team: HubTeam? = nil
    var closeLibrary: (() -> Void)? = nil
    @State private var hitterPresented = false
    @Environment(AppModel.self) private var model
    private var remoteEntries: [StoryEntry] {
        model.stories.catalog.stories.filter { team == nil || $0.teamIDs.contains(team!.mlbID) }
    }

    private var privateLaunchPreview: PrivateStoryPreview? {
        guard team == nil || [145, 114].contains(team!.mlbID) else { return nil }
        return PrivateLaunchStory.item
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                if team == nil || team?.hasPublishedStories == true || !remoteEntries.isEmpty || privateLaunchPreview != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("STORIES").font(.title2.weight(.black))
                                    Spacer()
                                    Button { Task { await model.stories.refresh(force: true) } } label: {
                                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                                    }.accessibilityLabel("Refresh stories").accessibilityIdentifier("stories.refresh")
                                    if let closeLibrary {
                                        Button("Done", action: closeLibrary)
                                            .frame(minHeight: 44)
                                            .accessibilityIdentifier("stories.close")
                                    }
                                }
                                if team != nil {
                                    Text("The numbers that explain a season—and the roads they took to get there.")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColor.ink.opacity(0.72))
                                } else {
                                    Text("MLB · FEATURED")
                                        .font(AppFont.label)
                                        .foregroundStyle(AppColor.amber)
                                }
                            }
                            .foregroundStyle(AppColor.navy)

                            if model.stories.refreshFailed {
                                Text("Showing saved stories. New stories will appear when connected.")
                                    .font(.footnote).foregroundStyle(AppColor.navy)
                                    .accessibilityIdentifier("stories.offline")
                            }
                            if (team == nil || team?.mlbID == 114), let item = ClevelandLaunchStory.item {
                                teamHeading("PRIVATE PREVIEW · OCTOBER 11")
                                NavigationLink { InningOutGridStoryView(story: item.story) } label: {
                                    StoryPreviewCard(title: item.entry.title, summary: item.entry.summary, action: "WATCH THE CHART · 10 SECONDS")
                                }.buttonStyle(.plain).accessibilityIdentifier("stories.private.almost-every-out-a-k")
                            }
                            if let item = privateLaunchPreview {
                                teamHeading("PRIVATE PREVIEW · OCTOBER 10")
                                NavigationLink { PrivateLaunchStoryView(item: item) } label: {
                                    StoryPreviewCard(title: item.entry.title, summary: item.entry.summary, action: "WATCH THE CHART · 10 SECONDS")
                                }.buttonStyle(.plain).accessibilityIdentifier("stories.private.separated-by-one")
                            }
                            if team == nil && !PrivateStoryPreviews.items.isEmpty {
                                teamHeading("PRIVATE PREVIEW")
                                NavigationLink {
                                    PrivateStoryComparisonView(closeLibrary: closeLibrary)
                                } label: {
                                    StoryPreviewCard(title: "Three October 9 stories", summary: "Cleveland’s sixth. Milwaukee’s margins. Baker’s breakout. Watch all three and choose your favorite.", action: "COMPARE ALL THREE")
                                }.buttonStyle(.plain).accessibilityIdentifier("stories.private-previews")
                            }
                            if !remoteEntries.isEmpty {
                                teamHeading("NEW IN HUB BALL")
                                ForEach(remoteEntries) { entry in
                                    NavigationLink {
                                        RemoteStoryView(entry: entry)
                                    } label: {
                                        StoryPreviewCard(title: entry.title, summary: entry.summary,
                                                         action: entry.actionLabel)
                                    }.buttonStyle(.plain).accessibilityIdentifier("stories.remote.\(entry.id)")
                                }
                            }

                            if team == nil {
                                Button { hitterPresented = true } label: {
                                    StoryPreviewCard(
                                        title: "The vanishing .300 hitter",
                                        summary: "Seven qualified hitters finished at .300 or higher in 2026, matching 2025.",
                                        action: "WATCH THE STORY · 5 SECONDS"
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("stories.hitter")
                            }

                            if team == nil || team == .boston {
                                if team == nil { teamHeading("BOSTON") }
                                storyLink(
                                    title: "Nine pitches",
                                    summary: "Payton Tolle opened against Kansas City with nine pitches, nine strikes and three strikeouts."
                                ) {
                                    NinePitchesView()
                                }

                                storyLink(
                                    title: "Four roads, one record",
                                    summary: "Four Boston seasons reached 57–51 after 108 games—then went four different ways."
                                ) {
                                    Game108GraphView()
                                }
                            }

                            if team == nil || team == .milwaukee {
                                if team == nil { teamHeading("MILWAUKEE") }
                                storyLink(
                                    title: "Who built the 42?",
                                    summary: "Two games. Forty-two runs. None allowed. Follow the hitters and pitchers behind Milwaukee’s 22–0 and 20–0 shutouts."
                                ) {
                                    BrewersShutoutView()
                                }
                            }

                            if team == nil || team == .newYork {
                                if team == nil { teamHeading("NEW YORK YANKEES") }
                                storyLink(
                                    title: "The home run chase",
                                    summary: "By age, Aaron Judge trails the legends. Count at-bats instead, and the picture flips."
                                ) {
                                    HomeRunChaseView()
                                }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView(
                        "\((team?.shortName ?? "Team")) stories coming soon",
                        systemImage: "book.pages",
                        description: Text("This section will appear when the first \((team?.shortName ?? "Team")) visual story is ready.")
                    )
                    .foregroundStyle(AppColor.ink)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.stories.restore(); model.setStoriesVisible(true) }
            .onDisappear { model.setStoriesVisible(false) }
            .refreshable { await model.stories.refresh(force: true) }
            .fullScreenCover(isPresented: $hitterPresented) { MLB300HitterStory() }
        }
    }

    private func teamHeading(_ name: String) -> some View {
        Text(name).font(AppFont.label).foregroundStyle(AppColor.amber).padding(.top, 12)
    }

    private func storyLink<Destination: View>(
        title: String,
        summary: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        return NavigationLink(destination: destination) {
            StoryPreviewCard(title: title, summary: summary, action: "WATCH THE STORY")
        }
        .buttonStyle(.plain)
    }
}

struct StoryPreviewCard: View {
    let title: String
    let summary: String
    let action: String
    var watch: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title2, design: .serif).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(summary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if let watch {
                    Button(action: watch) { Label(action, systemImage: "play.circle.fill").fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 48).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Watch the chart").accessibilityIdentifier("featured.watch")
                } else {
                    Label(action, systemImage: "play.circle.fill")
                }
                if let dismiss {
                    Button(action: dismiss) { Text("Dismiss").frame(minWidth: 70, minHeight: 48).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss featured story").accessibilityIdentifier("featured.dismiss")
                }
            }.font(.caption.weight(.bold)).foregroundStyle(Color(hubHex: watch == nil ? "#BC6259" : "#A84138"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .foregroundStyle(AppColor.night)
        .background(AppColor.bone, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    StoriesView(team: .boston)

    .environment(TeamSession(team: .boston))
    .environment(AppModel())
}
