import SwiftUI

enum HomeDestination {
    case october
    case games
    case schedule
    case standings
}

struct HomeView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.hubTeamPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("october.homeInvitationDismissed") private var octoberInvitationDismissed = false
    @State private var store: HomeStore
    let team: HubTeam
    let onSelect: (HomeDestination) -> Void

    init(team: HubTeam = .boston, onSelect: @escaping (HomeDestination) -> Void) {
        self.team = team
        self.onSelect = onSelect
        _store = State(initialValue: HomeStore(team: team))
    }

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()
            VStack(spacing: 0) {
                homeMasthead
                if OctoberFeature.homeInvitationEnabled && !octoberInvitationDismissed {
                    octoberInvitation
                }
                Group {
                    if store.recentGame != nil, store.schedule != nil {
                        briefing
                    } else if store.isLoading {
                        ProgressView("Loading today's briefing…")
                            .tint(AppColor.ink)
                            .foregroundStyle(AppColor.ink)
                    } else {
                        errorView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task { await store.load() }
    }

    private var octoberInvitation: some View {
        HStack(spacing: 10) {
            Button { onSelect(.october) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppColor.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The 2026 playoff bracket is here.")
                            .font(AppFont.bodySmall.weight(.semibold))
                            .foregroundStyle(AppColor.bone)
                        Text("Follow the whole MLB field.")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.boneMuted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(AppColor.bone)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the complete MLB playoff bracket. Your favorite team does not change.")

            Button { octoberInvitationDismissed = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.boneMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss playoff invitation")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .background(AppColor.nightRaised)
        .overlay(alignment: .leading) { Rectangle().fill(AppColor.amber).frame(width: 3) }
    }

    private var homeMasthead: some View {
        Group {
            if usesExpandedReadingLayout {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(palette.line)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.fullName)
                            .font(AppFont.displayLarge)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(todayHeading)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.ink.opacity(0.88))
                    }
                    .layoutPriority(1)
                }
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "baseball.fill")
                        .font(.system(size: contentWidth >= 650 ? 42 : 36, weight: .regular))
                        .foregroundStyle(palette.line)

                    Text(team.fullName)
                        .font(AppFont.displayLarge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .layoutPriority(1)

                    Spacer()

                    Text(todayHeading)
                        .font(AppFont.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .foregroundStyle(AppColor.ink)
        .padding(.horizontal, 12)
        .padding(.top, usesExpandedReadingLayout ? 14 : 10)
        .padding(.bottom, usesExpandedReadingLayout ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.fullName), \(todayHeading)")
    }

    private var usesExpandedReadingLayout: Bool {
        dynamicTypeSize.usesExpandedReadingLayout
    }

    private var briefing: some View {
        ScrollView {
            VStack(spacing: 0) {
                lastGameCard
                Color.clear.frame(height: usesExpandedReadingLayout ? 20 : 32)
                standingsCard
                Color.clear.frame(height: usesExpandedReadingLayout ? 20 : 32)
                upcomingBoard
            }
            .padding(.horizontal, contentWidth >= 650 ? 18 : 12)
            .padding(.top, usesExpandedReadingLayout ? 4 : 0)
            .padding(.bottom, 12)
        }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var standingsCard: some View {
        if let division = store.standings?.divisions.first(where: { division in
            division.teams.contains(where: \.isFavorite)
        }) {
            Button { onSelect(.standings) } label: {
                if usesExpandedReadingLayout {
                    expandedStandingsContent(division)
                } else {
                    compactStandingsContent(division)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the standings")
        }
    }

    private func compactStandingsContent(_ division: StandingsDivision) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Team")
                    .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                    .frame(width: contentWidth >= 650 ? 200 : 135, alignment: .leading)
                Text("W").frame(maxWidth: .infinity)
                Text("L").frame(maxWidth: .infinity)
                Text("GB").frame(maxWidth: .infinity)
                Text("L10").frame(maxWidth: .infinity)
                Text("STRK").frame(maxWidth: .infinity)
            }
            .font(AppFont.label)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .modifier(HomeTableHeaderStyle())

            ForEach(Array(division.teams.enumerated()), id: \.element.id) { index, team in
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(team.rank)
                            .font(AppFont.number)
                            .foregroundStyle(AppColor.boneMuted)
                            .frame(width: 12, alignment: .trailing)
                        Text(team.cityName)
                            .font(.system(size: 15, weight: team.isFavorite ? .black : .bold))
                            .foregroundStyle(team.isFavorite ? AppColor.amber : AppColor.bone)
                            .lineLimit(1)
                    }
                    .frame(width: contentWidth >= 650 ? 200 : 135, alignment: .leading)

                    standingNumber(team.wins, emphasized: team.isFavorite)
                    standingNumber(team.losses, emphasized: team.isFavorite)
                    Text(team.gamesBack).font(AppFont.number).frame(maxWidth: .infinity)
                    Text(team.lastTen).font(AppFont.number).frame(maxWidth: .infinity)
                    Text(team.streak).font(AppFont.number).foregroundStyle(AppColor.streakColor(team.streak)).frame(maxWidth: .infinity)
                }
                .foregroundStyle(AppColor.navy)
                .padding(.horizontal, 13)
                .frame(height: 35)
                .background(team.isFavorite ? palette.tint : AppColor.paper)
                .overlay(alignment: .leading) {
                    if team.isFavorite { Rectangle().fill(palette.line).frame(width: 3) }
                }
                if index < division.teams.count - 1 {
                    Divider().overlay(AppColor.separator).padding(.leading, 13)
                }
            }

            if let standings = store.standings, standings.isDelayed {
                Label("Standings delayed · Updated \(standings.updatedText)", systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(AppColor.paper)
            }
        }
        .modifier(HomeCardStyle())
    }

    private func expandedStandingsContent(_ division: StandingsDivision) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Standings")
                .font(.headline.weight(.black))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(HomeTableHeaderStyle())

            ForEach(Array(division.teams.enumerated()), id: \.element.id) { index, team in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(team.rank).font(AppFont.number).foregroundStyle(AppColor.boneMuted)
                        Text(team.cityName)
                            .font(.headline.weight(team.isFavorite ? .black : .bold))
                            .foregroundStyle(team.isFavorite ? AppColor.amber : AppColor.bone)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if team.isFavorite { Image(systemName: "star.fill").foregroundStyle(AppColor.amber).accessibilityHidden(true) }
                    }
                    VStack(spacing: 5) {
                        homeMetric("Wins", "\(team.wins)")
                        homeMetric("Losses", "\(team.losses)")
                        homeMetric("Games back", team.gamesBack)
                        homeMetric("Last 10", team.lastTen)
                        homeMetric("Streak", team.streak, valueColor: AppColor.streakColor(team.streak))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(team.isFavorite ? palette.tint : AppColor.paper)
                .overlay(alignment: .leading) {
                    if team.isFavorite { Rectangle().fill(palette.line).frame(width: 3) }
                }
                if index < division.teams.count - 1 { Divider().overlay(AppColor.separator).padding(.leading, 16) }
            }

            if let standings = store.standings, standings.isDelayed {
                Label("Standings delayed · Updated \(standings.updatedText)", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.inkMuted)
                    .padding(16)
            }
        }
        .modifier(HomeCardStyle())
    }

    private func homeMetric(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.boneMuted)
            Spacer(minLength: 8)
            Text(value).font(.body.weight(.bold).monospacedDigit()).foregroundStyle(valueColor ?? AppColor.bone)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var lastGameCard: some View {
        if let game = store.recentGame {
            let favorite = favoriteTeam(in: game)
            let opponent = opponent(in: game)
            Button { onSelect(.games) } label: {
                if usesExpandedReadingLayout {
                    expandedLastGameContent(game, favorite: favorite, opponent: opponent)
                        .modifier(HomeCardStyle())
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            HStack(spacing: 7) {
                                Text(compactNumericDate(game.gameDate))
                                if game.isLive {
                                    LiveGameIndicator()
                                } else {
                                    Text(game.result.lowercased() == "win" ? "W" : "L")
                                        .foregroundStyle(
                                            game.result.lowercased() == "win"
                                                ? AppColor.resultWinText
                                                : AppColor.resultLossText
                                        )
                                }
                            }
                            .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("R").frame(width: 38, alignment: .trailing)
                            Text("H").frame(width: 38, alignment: .trailing)
                            Text("E").frame(width: 38, alignment: .trailing)
                            Text("LOB").frame(width: 44, alignment: .trailing)
                            Text("SB").frame(width: 36, alignment: .trailing)
                        }
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.8)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .modifier(HomeTableHeaderStyle())

                        gameResultRow(favorite, isWinner: favorite.runs > opponent.runs)
                        Divider().overlay(AppColor.separator).padding(.leading, 13)
                        gameResultRow(opponent, isWinner: opponent.runs > favorite.runs)

                        HStack(spacing: 8) {
                            Text("Home runs")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(AppColor.boneMuted)
                            Text(homeRunSummary(for: favorite))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColor.navy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 27)
                        .background(AppColor.nightRaised)

                        HStack(spacing: 8) {
                            Text(game.isLive ? "Live" : "Pitching")
                                .foregroundStyle(AppColor.boneMuted)
                            Text(game.isLive ? game.liveStatus ?? "In progress" : pitchingSummary(for: game))
                                .foregroundStyle(AppColor.navy)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            if game.isLive, let scheduledGame = scheduledGame(for: game) {
                                Text("·").foregroundStyle(AppColor.boneMuted)
                                Text(scheduledGame.watchSummary)
                                    .foregroundStyle(AppColor.navy)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 27)
                        .background(AppColor.nightRaised)
                    }
                    .modifier(HomeCardStyle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Game Center")
        }
    }

    private func expandedLastGameContent(
        _ game: RecentGame,
        favorite: TeamBoxScore,
        opponent: TeamBoxScore
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(compactDate(game.gameDate)).font(.headline.weight(.black))
                    Spacer(minLength: 8)
                    Text(game.isLive ? "LIVE" : game.result.uppercased()).font(.subheadline.weight(.black)).foregroundStyle(game.isLive ? AppColor.amber : AppColor.steel)
                }
                Text("Last game · tap for Game Recaps").font(.caption).foregroundStyle(AppColor.boneMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HomeTableHeaderStyle())

            expandedGameResultRow(favorite, isWinner: favorite.runs > opponent.runs)
            Divider().overlay(AppColor.separator).padding(.leading, 16)
            expandedGameResultRow(opponent, isWinner: opponent.runs > favorite.runs)

            VStack(alignment: .leading, spacing: 8) {
                expandedSummaryRow("Home runs", homeRunSummary(for: favorite))
                expandedSummaryRow(game.isLive ? "Live" : "Pitching", game.isLive ? game.liveStatus ?? "In progress" : pitchingSummary(for: game))
                if game.isLive, let scheduledGame = scheduledGame(for: game) {
                    expandedSummaryRow("Watch", scheduledGame.watchSummary)
                }
            }
            .padding(16)
        }
    }

    private func expandedGameResultRow(_ team: TeamBoxScore, isWinner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(team.cityName).font(.headline.weight(isWinner ? .black : .bold)).foregroundStyle(isWinner ? AppColor.amber : AppColor.bone)
                Spacer(minLength: 8)
                Text(isWinner ? "WINNER" : "").font(.caption.weight(.black)).foregroundStyle(AppColor.amber)
            }
            homeMetric("Runs", "\(team.runs)", valueColor: isWinner ? AppColor.amber : AppColor.bone)
            homeMetric("Hits", "\(team.hits)")
            homeMetric("Errors", "\(team.errors)")
            homeMetric("Left on base", "\(team.leftOnBase)")
            homeMetric("Stolen bases", "\(team.batting.reduce(0) { $0 + ($1.stolenBases ?? 0) })")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.nightRaised)
    }

    private func expandedSummaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(AppColor.boneMuted)
            Text(value).font(.body.weight(.semibold)).foregroundStyle(AppColor.bone).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var upcomingBoard: some View {
        if let schedule = store.schedule {
            let upcomingGames = schedule.games
                .filter { $0.gamePk != store.recentGame?.gamePk }
                .prefix(3)
            VStack(spacing: 0) {
                tableHeader
                ForEach(Array(upcomingGames).indices, id: \.self) { index in
                    let game = Array(upcomingGames)[index]
                    upcomingRow(game)
                    if index < upcomingGames.count - 1 {
                        Divider().overlay(AppColor.separator).padding(.leading, 13)
                    }
                }

                if upcomingGames.isEmpty {
                    Text("No upcoming games are scheduled.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
            }
            .modifier(HomeCardStyle())
        }
    }

    private var tableHeader: some View {
        Group {
            if usesExpandedReadingLayout {
                Text("Next 3 games")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Text(contentWidth < 400 ? "Next 3" : "Next 3 games")
                        .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Time").frame(width: 52, alignment: .center)
                    Text("Starter").frame(width: 128, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .black))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, usesExpandedReadingLayout ? 12 : 0)
        .frame(minHeight: usesExpandedReadingLayout ? 52 : 36, alignment: .center)
        .modifier(HomeTableHeaderStyle())
    }

    private func upcomingRow(_ game: ScheduledGame) -> some View {
        Group {
            if usesExpandedReadingLayout {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(shortGameDate(game.gameDate)) · \(game.locationWord) \(game.opponent)")
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    homeMetric("Start time", game.formattedTime)
                    homeMetric("Starter", projectedStarter(for: game))
                    expandedSummaryRow("Watch", game.watchSummary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(shortGameDate(game.gameDate)) \(game.locationWord) \(game.opponent)")
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(game.watchSummary)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(AppColor.navy.opacity(0.68))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(game.formattedTime)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 52, alignment: .center)
                    Text(projectedStarter(for: game))
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 128, alignment: .trailing)
                }
                .padding(.horizontal, 13)
                .frame(height: 48)
            }
        }
        .foregroundStyle(AppColor.navy)
        .accessibilityElement(children: .combine)
    }

    private func scheduledGame(for game: RecentGame) -> ScheduledGame? {
        store.schedule?.games.first { $0.gamePk == game.gamePk }
    }

    private func gameResultRow(_ team: TeamBoxScore, isWinner: Bool) -> some View {
        HStack(spacing: 0) {
            Text(team.cityName)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            gameResultNumber(team.runs, width: 38, isRunTotal: true, isWinner: isWinner)
            gameResultNumber(team.hits, width: 38)
            gameResultNumber(team.errors, width: 38)
            gameResultNumber(team.leftOnBase, width: 44)
            gameResultNumber(team.batting.reduce(0) { $0 + ($1.stolenBases ?? 0) }, width: 36)
        }
        .foregroundStyle(AppColor.navy)
        .padding(.horizontal, 13)
        .frame(height: 35)
        .background(AppColor.nightRaised)
    }

    private func gameResultNumber(
        _ value: Int,
        width: CGFloat,
        isRunTotal: Bool = false,
        isWinner: Bool = false
    ) -> some View {
        Text("\(value)")
            .font(AppFont.number)
            .foregroundStyle(isRunTotal && isWinner ? AppColor.amber : AppColor.bone)
            .frame(width: width, alignment: .trailing)
    }

    private func homeRunSummary(for team: TeamBoxScore) -> String {
        let hitters = team.batting.filter { $0.homeRuns > 0 }
        guard !hitters.isEmpty else { return "None" }
        return hitters.map { batter in
            let total = batter.seasonHomeRuns.map(String.init) ?? "—"
            return "\(surname(batter.name)) (\(total))"
        }.joined(separator: ", ")
    }

    private func pitchingSummary(for game: RecentGame) -> String {
        var decisions = [
            pitchingDecision("W", pitcher: game.decisions.winner, game: game),
            pitchingDecision("L", pitcher: game.decisions.loser, game: game)
        ]
        if !game.decisions.save.isEmpty {
            decisions.append(pitchingDecision("SV", pitcher: game.decisions.save, game: game))
        }
        return decisions.joined(separator: " · ")
    }

    private func pitchingDecision(_ label: String, pitcher: String, game: RecentGame) -> String {
        let record = decisionValue(for: pitcher, in: game.away)
            ?? decisionValue(for: pitcher, in: game.home)
        let name = surname(pitcher)
        return record.map { "\(label) \(name) (\($0))" } ?? "\(label) \(name)"
    }

    private func decisionValue(for pitcher: String, in team: TeamBoxScore) -> String? {
        guard let note = team.pitching.first(where: { $0.name == pitcher })?.note,
              let comma = note.lastIndex(of: ",") else { return nil }
        return note[note.index(after: comma)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " )"))
    }

    private var todayHeading: String {
        let now = Date.now
        let calendar = BaseballTime.calendar
        let weekday = BaseballTime.format(now, .dateTime.weekday(.abbreviated))
        if contentWidth < 650 {
            return "\(weekday) \(calendar.component(.month, from: now))/\(calendar.component(.day, from: now))"
        }
        let month = BaseballTime.format(now, .dateTime.month(.abbreviated))
        let day = calendar.component(.day, from: now)
        return "\(weekday), \(month) \(ordinal(day))"
    }

    private func ordinal(_ day: Int) -> String {
        let suffix: String
        if (11...13).contains(day % 100) { suffix = "th" }
        else {
            switch day % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" }
        }
        return "\(day)\(suffix)"
    }

    private func projectedStarter(for game: ScheduledGame) -> String {
        guard game.showProbables, !game.favoriteTeamPitcher.isEmpty else { return "TBD" }
        return game.favoriteTeamPitcher
    }

    private func surname(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard let last = parts.last else { return name }

        let suffix = last
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        let generationalSuffixes = Set(["jr", "sr", "ii", "iii", "iv", "v"])
        if generationalSuffixes.contains(suffix), parts.count > 1 {
            return String(parts[parts.count - 2])
        }
        return String(last)
    }

    private func standingNumber(_ value: Int, emphasized: Bool) -> some View {
        Text("\(value)")
            .font(.system(size: 14, weight: emphasized ? .black : .medium, design: .monospaced))
            .frame(maxWidth: .infinity)
    }

    private func scoreTeam(_ team: TeamBoxScore, isWinner: Bool) -> some View {
        HStack(alignment: .center, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.abbreviation)
                    .font(AppFont.displayMedium)
                    .foregroundStyle(AppColor.bone)
                Text(team.record)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColor.navy.opacity(0.46))
            }
            Spacer(minLength: 2)
            Text("\(team.runs)")
                .font(AppFont.numberExtraLarge)
                .foregroundStyle(isWinner ? AppColor.amber : AppColor.bone)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultPill(_ result: String) -> some View {
        Text(result.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(0.7)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(AppColor.nightRaised)
            .foregroundStyle(AppColor.ink)
            .clipShape(Rectangle())
    }

    private func oddsCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(value == "—" ? AppColor.navy.opacity(0.36) : AppColor.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: width, alignment: .trailing)
    }

    private func favoriteTeam(in game: RecentGame) -> TeamBoxScore {
        game.away.id == team.mlbID ? game.away : game.home
    }

    private func opponent(in game: RecentGame) -> TeamBoxScore {
        game.away.id == team.mlbID ? game.home : game.away
    }

    private func ordinal(_ rank: String) -> String {
        switch rank { case "1": "1st"; case "2": "2nd"; case "3": "3rd"; default: "\(rank)th" }
    }

    private func compactDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return BaseballTime.format(date, .dateTime.month(.abbreviated).day().year())
    }

    private func compactNumericDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return BaseballTime.format(date, .dateTime.month(.defaultDigits).day().year(.twoDigits))
    }

    private func shortGameDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return BaseballTime.format(date, .dateTime.weekday(.abbreviated))
            + " "
            + BaseballTime.format(date, .dateTime.month(.defaultDigits).day())
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
    private func american(_ value: Int?) -> String { value.map(signed) ?? "—" }

    private func runLine(_ odds: HomeGameOdds?) -> String {
        guard let line = odds?.runLine else { return "—" }
        let lineText = line > 0 ? "+\(line.formatted())" : line.formatted()
        return odds?.runLinePrice.map { "\(lineText) \(signed($0))" } ?? lineText
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
            Text(store.errorMessage ?? "Today's briefing is unavailable.")
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await store.load() } }
                .buttonStyle(HubProminentButtonStyle())
                .tint(AppColor.navy)
        }
        .foregroundStyle(AppColor.ink)
        .padding(24)
    }
}

private struct HomeTableHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(AppColor.ink.opacity(0.82))
            .background(AppColor.nightRaised)
            .overlay(alignment: .top) {
                Rectangle().fill(AppColor.ink.opacity(0.78)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppColor.ink.opacity(0.78)).frame(height: 1)
            }
    }
}

private struct HomeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColor.nightRaised)
            .clipShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }
}
