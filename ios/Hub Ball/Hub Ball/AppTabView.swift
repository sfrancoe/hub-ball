import SwiftUI

enum MainTab: String, CaseIterable {
    case home
    case recent
    case standings
    case schedule
    case headlines
    case xPosts
    case players
    case pitching
    case leaders
    case stories

    var title: String {
        switch self {
        case .home: "Home"
        case .recent: "Game Recaps"
        case .schedule: "Schedule"
        case .headlines: "Newspapers"
        case .xPosts: "X Posts"
        case .standings: "Standings"
        case .players: "Players"
        case .pitching: "Pitching"
        case .leaders: "Leaders"
        case .stories: "Stories"
        }
    }

    static var defaultOrderStorageValue: String {
        allCases.map(\.rawValue).joined(separator: ",")
    }

    static func ordered(from storedValue: String) -> [MainTab] {
        var seen = Set<MainTab>()
        let savedTabs = storedValue
            .split(separator: ",")
            .compactMap { MainTab(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        let completeOrder = savedTabs + allCases.filter { !seen.contains($0) }
        return [.home] + completeOrder.filter { $0 != .home }
    }
}

struct AppTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(HubPreferences.selectedTeamKey) private var selectedTeamID = HubTeam.boston.id
    @AppStorage(HubPreferences.completedTeamOnboardingKey) private var completedTeamOnboarding = false
    @AppStorage(HubPreferences.pageOrderKey) private var storedPageOrder = MainTab.defaultOrderStorageValue
    @State private var session: TeamSession?
    @State private var selectedTab: MainTab = .home
    @State private var settingsPresented = false
    @State private var playoffsPresented = false
    @State private var showFeaturedAfterOnboarding = false
    @State private var storiesPresented = false
    @State private var hitterPresented = false
    @State private var featuredStory: StoryEntry?
    @State private var remoteFeaturedStory: FeaturedStoryItem?
    @State private var launchStoryPresented = false
    @State private var updateInstructionsPresented = false
    @State private var postseasonLanding = true
    @State private var hasAppeared = false
    @State private var selectedPlayerID: Int?

    private var team: HubTeam {
        HubTeam(rawValue: selectedTeamID) ?? .boston
    }

    private var palette: HubTeamPalette {
        HubTeamPalette(team: team)
    }

    private var availableTabs: [MainTab] {
        MainTab.ordered(from: storedPageOrder).filter { tab in
            switch tab {
            case .home: team.supportsHome
            case .players: team.supportsPlayers
            default: true
            }
        }
    }

    var body: some View {
        GeometryReader { window in
            VStack(spacing: 0) {
                if dynamicTypeSize.usesExpandedReadingLayout {
                    expandedNavigation
                } else {
                    topNavigation
                }
                if let update = updateOffer {
                    BetaUpdateNotice(update: { openUpdate(update) }, later: {
                        if model.launchFlow.phase == .notice { model.launchFlow.dismissNotice(updates: model.updates) }
                        else { model.updates.later(update) }
                    })
                }
                if let session, session.team == team {
                    selectedContent
                        .id(team.id)
                        .environment(session)
                        .environment(\.hubContentWidth, window.size.width)
                }
            }
            // iPad window controls float over the upper-left corner in narrow
            // windows. Keep the custom page heading below their touch area.
            .padding(.top, compactPadWindowInset(width: window.size.width))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColor.cream)
        .foregroundStyle(AppColor.ink)
        .font(AppFont.body)
        .environment(\.hubTeamPalette, palette)
        .task { if completedTeamOnboarding { model.launchFlow.begin(updates: model.updates, featured: model.featured) } }
        .onAppear {
            if session == nil { session = TeamSession(team: team) }
            guard !hasAppeared else { return }
            model.launchFlow.setActive(scenePhase == .active)
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains(where: { $0.hasPrefix("-show-") }) {
                postseasonLanding = false
                model.launchFlow.skip()
            }
            if arguments.contains("-show-hitter-story") {
                completedTeamOnboarding = true
                hitterPresented = true
            } else if arguments.contains("-show-story-library") {
                completedTeamOnboarding = true
                storiesPresented = true
            } else if arguments.contains("-show-october") {
                completedTeamOnboarding = true
                playoffsPresented = true
            } else if arguments.contains("-show-stories"), team.hasPublishedStories {
                selectedTab = .stories
            } else if arguments.contains("-show-recent") {
                selectedTab = .recent
            } else if team.supportsPlayers,
               let playerArgument = arguments.first(where: { $0.hasPrefix("-show-player=") }),
               let playerID = Int(playerArgument.replacingOccurrences(of: "-show-player=", with: "")) {
                selectedPlayerID = playerID
                selectedTab = .players
            } else if team.supportsPlayers, arguments.contains("-show-players") {
                selectedTab = .players
            } else {
                selectedTab = team.supportsHome ? .home : .recent
                model.launchFlow.begin(updates: model.updates, featured: model.featured)
            }
            #else
            selectedTab = team.supportsHome ? .home : .recent
            model.launchFlow.begin(updates: model.updates, featured: model.featured)
            #endif
            hasAppeared = true
        }
        .onChange(of: selectedTeamID) { _, _ in
            session?.scheduler.stop()
            session = TeamSession(team: team)
            selectedPlayerID = nil
            if !availableTabs.contains(selectedTab) {
                selectedTab = team.supportsHome ? .home : .recent
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.launchFlow.setActive(newPhase == .active)
            if newPhase == .background { session?.scheduler.setBackground(true) }
            if newPhase == .active {
                session?.scheduler.setBackground(false)
                if model.launchFlow.phase == .finished { Task { await model.updates.check() } }
                driveLaunchFlow()
            }

        }
        .onChange(of: model.launchFlow.phase) { _, _ in driveLaunchFlow() }
        .onChange(of: model.updates.candidate) { _, _ in
            if model.launchFlow.phase == .notice && model.updates.offer(completedOnboarding: true, storyConsumed: true, busy: false) == nil {
                model.launchFlow.noticeUnavailable()
            }
        }
        .fullScreenCover(isPresented: onboardingPresented, onDismiss: {
            if showFeaturedAfterOnboarding {
                showFeaturedAfterOnboarding = false
                postseasonLanding = true
                model.launchFlow.begin(updates: model.updates, featured: model.featured)
            }
        }) {
            TeamOnboardingView(selectedTeamID: $selectedTeamID) {
                showFeaturedAfterOnboarding = true
                completedTeamOnboarding = true
                selectedTab = team.supportsHome ? .home : .recent
            }
        }
        .fullScreenCover(isPresented: $playoffsPresented, onDismiss: driveLaunchFlow) {
            NavigationStack {
                OctoberView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("MLB · ALL TEAMS")
                                .font(AppFont.label)
                                .foregroundStyle(AppColor.boneMuted)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { playoffsPresented = false }
                                .tint(AppColor.amber)
                                .accessibilityIdentifier("playoffs.close")
                        }
                    }
                    .toolbarBackground(AppColor.night, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $storiesPresented, onDismiss: driveLaunchFlow) {
            StoriesView(closeLibrary: { storiesPresented = false })
        }
        .fullScreenCover(isPresented: $hitterPresented, onDismiss: driveLaunchFlow) { MLB300HitterStory() }
        .sheet(item: $remoteFeaturedStory, onDismiss: {
            launchStoryPresented = false
            postseasonLanding = true
            model.launchFlow.storyDismissed()
        }) { item in
            FeaturedStoryDocumentView(item: item) { remoteFeaturedStory = nil }
        }
        .sheet(item: $featuredStory, onDismiss: {
            launchStoryPresented = false
            postseasonLanding = true
            model.launchFlow.storyDismissed()
        }) { entry in
            if let item = ClevelandLaunchStory.item, item.id == entry.id {
                NavigationStack { InningOutGridStoryView(story: item.story, close: { featuredStory = nil }, onCompleted: { featuredStory = nil }) }
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            } else if let item = PrivateLaunchStory.item, item.id == entry.id {
                NavigationStack { PrivateLaunchStoryView(item: item, close: { featuredStory = nil }, completed: { featuredStory = nil }) }
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
            } else {
                FeaturedStoryOfferView(entry: entry) { featuredStory = nil }
            }
        }
        .sheet(isPresented: $updateInstructionsPresented, onDismiss: {
            model.launchFlow.instructionsDismissed()
            driveLaunchFlow()
        }) {
            BetaUpdateInstructions { updateInstructionsPresented = false }
        }
        .sheet(isPresented: $settingsPresented, onDismiss: driveLaunchFlow) {
            TeamSettingsView(selectedTeamID: $selectedTeamID) { selectedTeam in
                selectedPlayerID = nil
                selectedTab = selectedTeam.supportsHome ? .home : .recent
                postseasonLanding = false
                settingsPresented = false
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var launchBusy: Bool {
        launchStoryPresented || featuredStory != nil || remoteFeaturedStory != nil || playoffsPresented || storiesPresented || hitterPresented || settingsPresented || updateInstructionsPresented || scenePhase != .active
    }

    private func driveLaunchFlow() {
        guard completedTeamOnboarding, !launchBusy else { return }
        if model.launchFlow.phase == .instructions { updateInstructionsPresented = true }
        if model.launchFlow.phase == .ready { presentLaunchStory() }
    }

    private func openUpdate(_ update: BetaRelease) {
        let launching = model.launchFlow.phase == .notice
        if launching { model.launchFlow.beginHandoff(updates: model.updates) }
        else { model.updates.later(update) }
        Task {
            let opened = await TestFlightHandoff.open()
            if launching { model.launchFlow.handoffFinished(opened: opened); driveLaunchFlow() }
            else if !opened && scenePhase == .active { updateInstructionsPresented = true }
        }
    }

    private func presentLaunchStory() {
        guard model.launchFlow.phase == .ready, !model.featuredStoryLaunch.consumed else { return }
        #if DEBUG
        // Preserve existing explicit renderer/legacy fixtures; shipped launch is always remote.
        let env = ProcessInfo.processInfo.environment
        if env["HUB_STORY_SEPARATED_LAUNCH"] == "1" || env["HUB_STORY_CLEVELAND_LAUNCH"] == "1" || env["HUB_STORY_LEGACY_LAUNCH"] == "1" {
            let entry = env["HUB_STORY_SEPARATED_LAUNCH"] == "1" ? PrivateLaunchStory.item?.entry :
                env["HUB_STORY_CLEVELAND_LAUNCH"] == "1" ? ClevelandLaunchStory.item?.entry : StorySeed.catalog.stories.first { $0.id == "whole-season-by-june" }
            featuredStory = model.featuredStoryLaunch.offer(completedOnboarding: completedTeamOnboarding, busy: launchBusy, entry: entry)
            launchStoryPresented = featuredStory != nil
            if featuredStory != nil { model.launchFlow.didPresentStory() } else { model.launchFlow.storyDismissed() }
            return
        }
        #endif
        let selected = model.featured.selected()
        let offered = model.featuredStoryLaunch.offer(completedOnboarding: completedTeamOnboarding, busy: launchBusy, entry: selected?.entry)
        remoteFeaturedStory = offered == nil ? nil : selected
        launchStoryPresented = remoteFeaturedStory != nil
        if remoteFeaturedStory != nil { model.launchFlow.didPresentStory() }
        else { model.launchFlow.storyDismissed() }
    }

    private var updateOffer: BetaRelease? {
        guard completedTeamOnboarding, !launchBusy else { return nil }
        if model.launchFlow.phase == .notice { return model.launchFlow.target }
        guard model.launchFlow.phase == .finished else { return nil }
        return model.updates.offer(completedOnboarding: completedTeamOnboarding,
                                   storyConsumed: model.featuredStoryLaunch.consumed, busy: false)
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !completedTeamOnboarding },
            set: { isPresented in
                if !isPresented { completedTeamOnboarding = true }
            }
        )
    }

    private func compactPadWindowInset(width: CGFloat) -> CGFloat {
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad, width < 650 {
            return 32
        }
        return 0
    }

    @ViewBuilder
    private var selectedContent: some View {
        if postseasonLanding {
            NavigationStack {
                OctoberView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .principal) {
                        Text("MLB · ALL TEAMS").font(AppFont.label).foregroundStyle(AppColor.boneMuted)
                            .accessibilityIdentifier("postseason.landing.title")
                    } }
                    .toolbarBackground(AppColor.night, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }.preferredColorScheme(.dark)
        } else {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-show-home-run-chase") {
            NavigationStack { HomeRunChaseView() }
        } else {
            selectedTabContent
        }
        #else
        selectedTabContent
        #endif
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
                HomeView(team: team) { destination in
                    switch destination {
                    case .october: playoffsPresented = true
                    case .games: selectedTab = .recent
                    case .schedule: selectedTab = .schedule
                    case .standings: selectedTab = .standings
                    }
                }
                .mainTabSwipe(selection: $selectedTab, current: .home, availableTabs: availableTabs)
        case .recent:
                RecentGameView(team: team, onSelectPlayer: showPlayer)
                    .mainTabSwipe(selection: $selectedTab, current: .recent, availableTabs: availableTabs)
        case .schedule:
                ScheduleView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .schedule, availableTabs: availableTabs)
        case .headlines:
                HeadlinesView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .headlines, availableTabs: availableTabs)
        case .xPosts:
                XPostsView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .xPosts, availableTabs: availableTabs)
        case .standings:
                StandingsView()
                    .mainTabSwipe(selection: $selectedTab, current: .standings, availableTabs: availableTabs)
        case .players:
                PlayersView(team: team, requestedPlayerID: selectedPlayerID) {
                    selectedPlayerID = nil
                }
                // Player history contains a horizontally scrollable stats table.
                // Keep its gestures inside the player screen instead of switching tabs.
        case .pitching:
                PitchingView(team: team, onSelectPlayer: showPlayer)
                    .mainTabSwipe(selection: $selectedTab, current: .pitching, availableTabs: availableTabs)
        case .leaders:
                SeasonLeadersView(team: team)
                    .mainTabSwipe(selection: $selectedTab, current: .leaders, availableTabs: availableTabs)
        case .stories:
                // Stories can contain their own horizontal paging and sliders. An outer
                // page swipe would interpret those interactions as a trip to another tab.
                StoriesView(team: team)
        }
    }

    private func showPlayer(_ playerID: Int) {
        guard team.supportsPlayers else { return }
        selectedPlayerID = playerID
        selectedTab = .players
    }

    private var teamPickerButton: some View {
        Button { settingsPresented = true } label: {
            HStack(spacing: 6) {
                Text(team.shortName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch team")
        .accessibilityValue(team.pickerTitle)
        .accessibilityHint("Opens teams and settings")
    }

    private var playoffsButton: some View {
        Button { postseasonLanding = true } label: {
            HStack(spacing: 4) {
                smallTrophy
                Text("Postseason")
                    .fixedSize()
                    .foregroundStyle(AppColor.bone)
                smallTrophy
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppColor.amber)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Postseason")
        .accessibilityIdentifier("playoffs.open")
        .accessibilityHint("Opens the complete MLB playoff bracket for both leagues")
    }

    private var smallTrophy: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: 11, weight: .semibold))
            .accessibilityHidden(true)
    }

    private var storiesButton: some View {
        Button { storiesPresented = true } label: {
            Text("Stories")
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stories.open")
        .accessibilityHint("Opens baseball stories from across MLB")
    }

    private var teamAndPlayoffsNavigation: some View {
        HStack(spacing: 0) {
            teamPickerButton
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if OctoberFeature.enabled {
                    playoffsButton
                } else {
                    Color.clear.frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            storiesButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var expandedNavigation: some View {
        VStack(spacing: 0) {
            teamAndPlayoffsNavigation
            if !postseasonLanding {
            Menu {
                Picker("Page", selection: $selectedTab) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
            } label: {
                HStack {
                    Text(selectedTab.title).font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
            }
            .accessibilityLabel("Page")
            .accessibilityValue("\(selectedTab.title), \(team.shortName)")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.bone)
        .background(HubMastheadBackground(palette: palette))
    }

    private var topNavigation: some View {
        VStack(spacing: 0) {
            teamAndPlayoffsNavigation
            if !postseasonLanding { pageStrip }
        }
        .foregroundStyle(AppColor.bone)
        .background(HubMastheadBackground(palette: palette))
    }

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: dynamicTypeSize.usesExpandedReadingLayout ? 16 : 22) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(selectedTab == tab
                                    ? .headline.weight(.bold)
                                    : .subheadline.weight(.medium))
                                .foregroundStyle(
                                    selectedTab == tab ? AppColor.bone : AppColor.boneMuted
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) {
                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(AppColor.amber)
                                            .frame(height: 2)
                                            .offset(y: -3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(selectedTab, anchor: .center)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
            .onChange(of: availableTabs) { _, tabs in
                guard tabs.contains(selectedTab) else { return }
                proxy.scrollTo(selectedTab, anchor: .center)
            }
        }
    }

}

private struct MainTabSwipeModifier: ViewModifier {
    @Binding var selection: MainTab
    let current: MainTab
    let availableTabs: [MainTab]
    let edgeOnly: Bool

    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let minimumDistance: CGFloat = 64
    private let edgeWidth: CGFloat = 44

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded(handleSwipe)
        )
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height

        guard abs(horizontalDistance) >= minimumDistance,
              abs(horizontalDistance) > abs(verticalDistance) * 1.35 else {
            return
        }

        if edgeOnly || dynamicTypeSize.usesExpandedReadingLayout {
            let screenWidth = contentWidth
            let beganAtRequiredEdge = horizontalDistance < 0
                ? value.startLocation.x >= screenWidth - edgeWidth
                : value.startLocation.x <= edgeWidth
            guard beganAtRequiredEdge else { return }
        }

        let direction = horizontalDistance < 0 ? 1 : -1
        let swipeTabs = availableTabs
        guard !swipeTabs.isEmpty,
              let currentIndex = swipeTabs.firstIndex(of: current) else { return }
        let destinationIndex = (currentIndex + direction + swipeTabs.count) % swipeTabs.count
        let destination = swipeTabs[destinationIndex]

        withAnimation(.easeOut(duration: 0.2)) {
            selection = destination
        }
    }
}

private extension View {
    func mainTabSwipe(
        selection: Binding<MainTab>,
        current: MainTab,
        availableTabs: [MainTab],
        edgeOnly: Bool = false
    ) -> some View {
        modifier(
            MainTabSwipeModifier(
                selection: selection,
                current: current,
                availableTabs: availableTabs,
                edgeOnly: edgeOnly
            )
        )
    }
}

#Preview {
    AppTabView()

    .environment(TeamSession(team: .boston))
    .environment(AppModel())
}
