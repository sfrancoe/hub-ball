import Foundation
import Observation

/// One owner per selected club. Tab view lifetime never owns network state.
@MainActor @Observable
final class TeamSession {
    let scheduler = RefreshScheduler()
    let team: HubTeam
    let home: HomeStore
    let recent: RecentGameStore
    let schedule: ScheduleStore
    let standings: StandingsStore
    let headlines: HeadlinesStore
    let xPosts: XPostsStore
    let players: PlayersStore
    let pitching: PitchingStore
    let leaders: SeasonLeadersStore

    init(team: HubTeam, api: APIClient = .shared) {
        self.team = team
        let schedule = ScheduleStore(team: team, api: api)
        let recent = RecentGameStore(team: team, api: api, scheduleStore: schedule)
        let standings = StandingsStore(team: team, api: api)
        self.schedule = schedule
        self.recent = recent
        self.standings = standings
        home = HomeStore(team: team, recent: recent, schedule: schedule, standings: standings)
        headlines = HeadlinesStore(team: team, api: api)
        xPosts = XPostsStore(team: team, api: api)
        players = PlayersStore(team: team, api: api)
        pitching = PitchingStore(team: team, api: api)
        leaders = SeasonLeadersStore(team: team, api: api)
        scheduler.register("recent", isLive: { recent.hasLiveGame }) {
            await recent.load()
            return recent.errorMessage == nil && !recent.games.isEmpty
                && recent.games.allSatisfy { !recent.hasRefreshWarning(for: $0) }
        }
        scheduler.register("standings") {
            await standings.load()
            return standings.errorMessage == nil
        }
        scheduler.register("schedule") { await schedule.load(minimumRefreshInterval: 60); return schedule.errorMessage == nil }
        let headlines = self.headlines, xPosts = self.xPosts, players = self.players
        let pitching = self.pitching, leaders = self.leaders
        scheduler.register("headlines") { await headlines.load(); return headlines.errorMessage == nil }
        scheduler.register("xPosts") { await xPosts.load(); return xPosts.errorMessage == nil }
        scheduler.register("players") { await players.load(); return players.errorMessage == nil }
        scheduler.register("pitching") { await pitching.load(); return pitching.errorMessage == nil }
        scheduler.register("leaders") { await leaders.load(); return leaders.errorMessage == nil }
    }
    func setVisible(_ screen: String, _ visible: Bool) {
        let jobs = screen == "home" ? ["recent", "standings"] : [screen]
        scheduler.setVisible(visible, observer: screen, jobs: jobs)
    }

}

/// League-wide state survives opening and closing covers, and team changes.
@MainActor @Observable
final class AppModel {
    let scheduler = RefreshScheduler()
    let postseason = PostseasonStore(season: OctoberFeature.season)
    let history = PostseasonHistoryStore(season: OctoberFeature.season)
    let news = PostseasonNewsStore(season: OctoberFeature.season)
    let stories = StoryCatalogStore()
    let featured = FeaturedStoryStore()
    let updates = BetaUpdateStore.live()
    var featuredStoryLaunch = FeaturedStoryLaunch()
    let launchFlow = PostseasonLaunchFlow()
    let game108 = Game108GraphStore()
    let homeRunChase = HomeRunChaseStore()
    // Lazy construction avoids AVAudioEngine allocation during SwiftUI redraws.
    @ObservationIgnored lazy var graphMusic = GraphMusicPlayer()
    private var playerStores: [HubTeam: PlayersStore] = [:]
    private var scorecards: [Int: PostseasonScorecardStore] = [:]

    init() {
        let postseason = self.postseason, history = self.history, news = self.news
        scheduler.register("postseason", isLive: { postseason.snapshot?.isLive == true }) {
            await postseason.refresh(); return !postseason.refreshFailed
        }
        scheduler.register("history") { await history.refresh(); return !history.refreshFailed }
        scheduler.register("news") { await news.refresh(); return !news.refreshFailed }
    }

    func setStoriesVisible(_ visible: Bool) {
        let stories = self.stories
        scheduler.register("stories") { await stories.refresh(); return !stories.refreshFailed }
        scheduler.setVisible(visible, observer: "stories", jobs: ["stories"])
    }

    func setOctoberVisible(_ visible: Bool) {
        scheduler.setVisible(visible, observer: "october", jobs: ["postseason", "history", "news"])
    }

    func setScorecardVisible(_ game: PostseasonGame, _ visible: Bool) {
        let store = scorecard(for: game)
        let key = "scorecard-\(game.gamePk)"
        scheduler.register(key, isLive: { store.snapshot?.isLive ?? (game.abstractState == "Live") }) {
            await store.refresh(); return !store.refreshFailed
        }
        scheduler.setVisible(visible, observer: key, jobs: [key])
    }

    func players(for team: HubTeam) -> PlayersStore {
        if let store = playerStores[team] { return store }
        let store = PlayersStore(team: team)
        playerStores[team] = store
        return store
    }

    func scorecard(for game: PostseasonGame) -> PostseasonScorecardStore {
        if let store = scorecards[game.gamePk] { return store }
        let store = PostseasonScorecardStore(game: game)
        scorecards[game.gamePk] = store
        return store
    }
}
