import SwiftUI

struct StoriesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var team: HubTeam? = nil
    var closeLibrary: (() -> Void)? = nil
    @State private var hitterPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                if team == nil || team?.hasPublishedStories == true {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("STORIES").font(.title2.weight(.black))
                                    Spacer()
                                    if let closeLibrary {
                                        Button("Done", action: closeLibrary)
                                            .frame(minHeight: 44)
                                            .accessibilityIdentifier("stories.close")
                                    }
                                }
                                Text(team == nil ? "Every team. The whole game. Baseball stories worth a closer look." : "The numbers that explain a season—and the roads they took to get there.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppColor.ink.opacity(0.72))
                            }
                            .foregroundStyle(AppColor.navy)

                            if team == nil {
                                Text("MLB · FEATURED").font(AppFont.label).foregroundStyle(AppColor.amber)
                                Button { hitterPresented = true } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("The vanishing .300 hitter")
                                            .font(.system(.title, design: .serif).weight(.bold))
                                        Text("Seven in 2025. Seven so far in 2026. Will it end at seven again?")
                                            .font(.subheadline)
                                        Label("WATCH THE STORY · 10 SECONDS", systemImage: "play.circle.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color(hubHex: "#BC6259"))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(22)
                                    .foregroundStyle(AppColor.night)
                                    .background(AppColor.bone, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("stories.hitter")
                            }

                            if team == nil || team == .boston {
                                if team == nil { teamHeading("BOSTON") }
                                storyLink(
                                    title: "NINE PITCHES",
                                    summary: "Payton Tolle opened against Kansas City with nine pitches, nine strikes and three strikeouts.",
                                    systemImage: "9.circle.fill"
                                ) {
                                    NinePitchesView()
                                }

                                storyLink(
                                    title: "FOUR ROADS, ONE RECORD",
                                    summary: "Four Boston seasons reached 57–51 after 108 games—then went four different ways.",
                                    systemImage: "chart.xyaxis.line"
                                ) {
                                    Game108GraphView()
                                }
                            }

                            if team == nil || team == .milwaukee {
                                if team == nil { teamHeading("MILWAUKEE") }
                                NavigationLink {
                                    BrewersShutoutView()
                                } label: {
                                    BrewersShutoutStoryCard()
                                }
                                .buttonStyle(.plain)
                            }

                            if team == nil || team == .newYork {
                                if team == nil { teamHeading("NEW YORK YANKEES") }
                                storyLink(
                                    title: "THE HOME RUN CHASE",
                                    summary: "By age, Aaron Judge trails the legends. Count at-bats instead, and the picture flips.",
                                    systemImage: "baseball.diamond.bases"
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
            .fullScreenCover(isPresented: $hitterPresented) { MLB300HitterStory() }
        }
    }

    private func teamHeading(_ name: String) -> some View {
        Text(name).font(AppFont.label).foregroundStyle(AppColor.amber).padding(.top, 12)
    }

    private func storyLink<Destination: View>(
        title: String,
        summary: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        let expanded = dynamicTypeSize.usesExpandedReadingLayout
        let layout = expanded
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return NavigationLink(destination: destination) {
            layout {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColor.ink)
                    .frame(width: 62, height: 62)
                    .background(AppColor.nightRaised)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(AppColor.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.ink.opacity(0.76))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !expanded {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppColor.hunterGreen)
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StoriesView(team: .boston)
}
