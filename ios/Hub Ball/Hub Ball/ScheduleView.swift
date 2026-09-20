import SwiftUI

struct ScheduleView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.hubTeamPalette) private var palette
    @State private var store: ScheduleStore
    @State private var selectedGameID: Int?
    let team: HubTeam

    init(team: HubTeam = .boston) {
        self.team = team
        _store = State(initialValue: ScheduleStore(team: team))
    }

    private let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let schedule = store.schedule {
                        scheduleContent(schedule)
                    } else if store.isLoading {
                        ProgressView("Loading the schedule…")
                            .tint(AppColor.ink)
                            .foregroundStyle(AppColor.ink)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await loadSchedule()
        }
    }

    private func scheduleContent(_ schedule: Schedule) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if contentWidth >= 850 {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 16) {
                                ForEach(calendarMonths(for: schedule)) { month in
                                    monthCard(month, schedule: schedule)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            if let game = selectedGame(in: schedule) {
                                gameDetailCard(game)
                                    .frame(width: 340)
                            }
                        }
                        nextThreeGamesCard(schedule)
                    }
                } else {
                    ForEach(calendarMonths(for: schedule)) { month in
                        monthCard(month, schedule: schedule)
                    }
                    nextThreeGamesCard(schedule)
                    if let game = selectedGame(in: schedule) {
                        gameDetailCard(game)
                    }
                }

                Text("\(remainingGames(in: schedule).count) games remaining · Through \(formattedSeasonEnd(schedule.regularSeasonEnd))")
                    .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .semibold))
                    .foregroundStyle(AppColor.ink.opacity(0.82))
                    .padding(.vertical, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await loadSchedule()
        }
    }

    private func monthCard(_ month: CalendarMonth, schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.title)
                .font(.system(size: contentWidth >= 650 ? 19 : 17, weight: .black))
                .foregroundStyle(AppColor.navy)

            LazyVGrid(columns: calendarColumns, spacing: 3) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: contentWidth >= 650 ? 12 : 8, weight: .black))
                        .tracking(0.25)
                        .foregroundStyle(AppColor.hunterGreen)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(month.days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date, games: games(on: date, in: schedule))
                    } else {
                        Color.clear
                            .frame(height: contentWidth >= 650 ? 92 : 67)
                    }
                }
            }
        }
        .cardStyle(padding: 12)
    }

    private func dayCell(_ date: Date, games: [ScheduledGame]) -> some View {
        let game = games.first
        let selected = games.contains { $0.id == selectedGameID }
        let isHome = game?.location == "home"

        return VStack(spacing: 3) {
            Text(BaseballTime.format(date, .dateTime.day()))
                .font(.system(size: 15, weight: game == nil ? .regular : .medium))
                .foregroundStyle(game == nil ? AppColor.boneMuted : selected ? AppColor.amber : AppColor.bone)

            if let game {
                Text("\(game.locationWord) \(opponentCode(game.opponent))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected || isHome ? AppColor.bone : AppColor.boneMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(game.formattedTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? AppColor.bone : isHome ? AppColor.boneDim : AppColor.boneMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if games.count > 1 || game.doubleheader {
                    Text("DH")
                        .font(.system(size: contentWidth >= 650 ? 12 : 7, weight: .black))
                        .foregroundStyle(AppColor.ink)
                }
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.emptyDay)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentWidth >= 650 ? 92 : 72)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(isHome ? palette.tint : AppColor.night)
        }
        .overlay {
            if game != nil && !isHome && !selected {
                RoundedRectangle(cornerRadius: 4).stroke(AppColor.calendarOutline, lineWidth: 1)
            }
            if selected {
                VStack { Spacer(); Rectangle().fill(AppColor.amber).frame(height: 3) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let game {
                withAnimation(.easeOut(duration: 0.18)) {
                    selectedGameID = game.id
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(game == nil ? [] : .isButton)
    }

    private func gameDetailCard(_ game: ScheduledGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.fullFormattedDay)
                        .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: .black))
                        .foregroundStyle(AppColor.red)

                    Text("\(game.locationWord) \(game.opponent)")
                        .font(.system(size: contentWidth >= 650 ? 26 : 24, weight: .black))
                        .foregroundStyle(AppColor.navy)
                }

                Spacer()

                Text(game.formattedTime)
                    .font(.system(size: contentWidth >= 650 ? 22 : 20, weight: .black))
                    .foregroundStyle(AppColor.hunterGreen)
            }

            Divider()

            if game.showProbables {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Projected starters")
                        .font(.system(size: contentWidth >= 650 ? 15 : 13, weight: .black))
                        .foregroundStyle(AppColor.red)

                    HStack(alignment: .top) {
                        starterDetail(
                            team.cityName,
                            pitcherName(game.favoriteTeamPitcher),
                            game.favoriteTeamPitcherRecord
                        )
                        Spacer()
                        Text("vs.")
                            .font(.system(size: contentWidth >= 650 ? 14 : 12, weight: .black))
                            .foregroundStyle(AppColor.border)
                            .padding(.top, 13)
                        Spacer()
                        starterDetail(
                            game.opponent,
                            pitcherName(game.opponentPitcher),
                            game.opponentPitcherRecord,
                            alignment: .trailing
                        )
                    }
                }
                .padding(14)
                .background(AppColor.nightRaised)
                .clipShape(Rectangle())
            }

            HStack {
                detailItem("Venue", game.venue)
                Spacer()
                detailItem("Opponent", game.opponentRecord, alignment: .trailing)
            }

            if game.doubleheader {
                Text("Doubleheader · Game \(game.gameNumber)")
                    .font(.system(size: contentWidth >= 650 ? 12 : 9, weight: .black))
                    .foregroundStyle(AppColor.red)
            }
        }
        .cardStyle(padding: 16)
    }

    @ViewBuilder
    private func nextThreeGamesCard(_ schedule: Schedule) -> some View {
        let games = Array(remainingGames(in: schedule).prefix(3))
        if !games.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Next 3 games")
                        .font(.system(size: contentWidth >= 650 ? 18 : 16, weight: .black))
                    Spacer()
                    Text("UPCOMING")
                        .font(.system(size: contentWidth >= 650 ? 11 : 9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(AppColor.hunterGreen)
                }
                .foregroundStyle(AppColor.navy)
                .padding(.horizontal, 14)
                .frame(height: contentWidth >= 650 ? 42 : 38)
                .background(AppColor.nightRaised)

                ForEach(games.indices, id: \.self) { index in
                    let game = games[index]
                    compactMatchupRow(game)
                    if index < games.count - 1 {
                        Divider()
                            .overlay(AppColor.separator)
                            .padding(.leading, contentWidth >= 650 ? 66 : 58)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColor.border, lineWidth: 1)
            }
        }
    }

    private func compactMatchupRow(_ game: ScheduledGame) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 1) {
                Text(compactWeekday(game))
                    .font(.system(size: contentWidth >= 650 ? 11 : 9, weight: .black))
                    .tracking(0.35)
                    .foregroundStyle(AppColor.hunterGreen)
                Text(compactDay(game))
                    .font(.system(size: contentWidth >= 650 ? 22 : 19, weight: .black))
                    .foregroundStyle(AppColor.red)
            }
            .frame(width: contentWidth >= 650 ? 42 : 36)

            Rectangle()
                .fill(AppColor.separator)
                .frame(width: 1, height: contentWidth >= 650 ? 44 : 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(game.locationWord) \(game.opponent)")
                    .font(.system(size: contentWidth >= 650 ? 17 : 15, weight: .black))
                    .foregroundStyle(AppColor.navy)
                    .lineLimit(1)
                Text("\(game.formattedTime) · \(compactPitchingMatchup(game))")
                    .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .bold))
                    .foregroundStyle(AppColor.ink.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Text(game.location == "home" ? "HOME" : "AWAY")
                .font(.system(size: contentWidth >= 650 ? 10 : 8, weight: .black))
                .tracking(0.45)
                .foregroundStyle(game.location == "home" ? palette.tint : AppColor.hunterGreen)
        }
        .padding(.horizontal, 14)
        .frame(height: contentWidth >= 650 ? 64 : 57)
        .accessibilityElement(children: .combine)
    }

    private func detailItem(
        _ label: String,
        _ value: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .black))
                .foregroundStyle(AppColor.hunterGreen)
            Text(value.isEmpty ? "To be announced" : value)
                .font(.system(size: contentWidth >= 650 ? 19 : 17, weight: .bold))
                .foregroundStyle(AppColor.ink)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
    }

    private func starterDetail(
        _ label: String,
        _ name: String,
        _ record: String?,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .black))
                .foregroundStyle(AppColor.hunterGreen)
            Text(name)
                .font(.system(size: contentWidth >= 650 ? 20 : 18, weight: .black))
                .foregroundStyle(AppColor.navy)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            if !name.isEmpty, name != "To be announced" {
                Text(recordLabel(record))
                    .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: .bold))
                    .foregroundStyle(AppColor.hunterGreen)
            }
        }
    }

    private func recordLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "—" else {
            return "Record unavailable"
        }
        return value.replacingOccurrences(of: "-", with: "–")
    }

    private func compactWeekday(_ game: ScheduledGame) -> String {
        guard let date = game.date else { return "" }
        return BaseballTime.format(date, .dateTime.weekday(.abbreviated)).uppercased()
    }

    private func compactDay(_ game: ScheduledGame) -> String {
        guard let date = game.date else { return "" }
        return BaseballTime.format(date, .dateTime.day())
    }

    private func compactPitchingMatchup(_ game: ScheduledGame) -> String {
        guard game.showProbables,
              !game.favoriteTeamPitcher.isEmpty,
              !game.opponentPitcher.isEmpty else {
            return "Starters TBD"
        }
        return "\(surname(game.favoriteTeamPitcher)) vs. \(surname(game.opponentPitcher))"
    }

    private func surname(_ value: String) -> String {
        value.split(separator: " ").last.map(String.init) ?? value
    }

    private func loadSchedule() async {
        await store.load()
        guard let schedule = store.schedule else { return }
        let games = remainingGames(in: schedule)
        if selectedGameID == nil || !games.contains(where: { $0.id == selectedGameID }) {
            selectedGameID = games.first?.id
        }
    }

    private func selectedGame(in schedule: Schedule) -> ScheduledGame? {
        let games = remainingGames(in: schedule)
        return games.first { $0.id == selectedGameID } ?? games.first
    }

    private func games(on date: Date, in schedule: Schedule) -> [ScheduledGame] {
        schedule.games.filter { game in
            guard let gameDate = game.date else { return false }
            return easternCalendar.isDate(gameDate, inSameDayAs: date)
        }
    }

    private func calendarMonths(for schedule: Schedule) -> [CalendarMonth] {
        let cutoff = easternCalendar.startOfDay(for: Date())
        guard let seasonEnd = seasonEndDate(schedule.regularSeasonEnd), cutoff <= seasonEnd else {
            return []
        }

        var cursor = firstDayOfMonth(cutoff)
        let finalMonth = firstDayOfMonth(seasonEnd)
        var months: [CalendarMonth] = []

        while cursor <= finalMonth {
            let dayRange = easternCalendar.range(of: .day, in: .month, for: cursor) ?? 1..<2
            let leadingBlanks = easternCalendar.component(.weekday, from: cursor) - 1
            var days = Array<Date?>(repeating: nil, count: leadingBlanks)
            days.append(contentsOf: dayRange.compactMap { day in
                easternCalendar.date(byAdding: .day, value: day - 1, to: cursor)
            }.map { date in
                date >= cutoff ? Optional.some(date) : nil
            })
            while days.count % 7 != 0 {
                days.append(nil)
            }
            while days.count >= 7 && days.prefix(7).allSatisfy({ $0 == nil }) {
                days.removeFirst(7)
            }

            months.append(
                CalendarMonth(
                    id: monthID(cursor),
                    title: BaseballTime.format(cursor, .dateTime.month(.wide).year()),
                    days: days
                )
            )
            guard let next = easternCalendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return months
    }

    private func remainingGames(in schedule: Schedule) -> [ScheduledGame] {
        let cutoff = easternCalendar.startOfDay(for: Date())
        return schedule.games.filter { game in
            guard let date = game.date else { return false }
            return date >= cutoff
        }
    }

    private var easternCalendar: Calendar {
        BaseballTime.calendar
    }

    private func firstDayOfMonth(_ date: Date) -> Date {
        let components = easternCalendar.dateComponents([.year, .month], from: date)
        return easternCalendar.date(from: components) ?? date
    }

    private func seasonEndDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return easternCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func monthID(_ date: Date) -> String {
        let parts = easternCalendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    private func isToday(_ date: Date) -> Bool {
        easternCalendar.isDateInToday(date)
    }

    private func pitcherName(_ value: String) -> String {
        value.isEmpty ? "To be announced" : value
    }

    private func opponentCode(_ opponent: String) -> String {
        [
            "Angels": "LAA", "Astros": "HOU", "Athletics": "ATH",
            "Blue Jays": "TOR", "Braves": "ATL", "Brewers": "MIL",
            "Cardinals": "STL", "Cubs": "CHC", "Diamondbacks": "ARI",
            "Dodgers": "LAD", "Giants": "SF", "Guardians": "CLE",
            "Mariners": "SEA", "Marlins": "MIA", "Mets": "NYM",
            "Nationals": "WSH", "Orioles": "BAL", "Padres": "SD",
            "Phillies": "PHI", "Pirates": "PIT", "Rangers": "TEX",
            "Rays": "TB", "Reds": "CIN", "Rockies": "COL",
            "Royals": "KC", "Tigers": "DET", "Twins": "MIN",
            "White Sox": "CWS", "Yankees": "NYY"
        ][opponent] ?? String(opponent.prefix(3)).uppercased()
    }

    private func formattedSeasonEnd(_ value: String) -> String {
        guard let date = seasonEndDate(value) else { return value }
        return BaseballTime.format(date, .dateTime.month(.wide).day().year())
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Schedule Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The schedule could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await loadSchedule() }
            }
            .buttonStyle(HubProminentButtonStyle())
            .tint(AppColor.red)
        }
    }
}

private struct CalendarMonth: Identifiable {
    let id: String
    let title: String
    let days: [Date?]
}

#Preview {
    ScheduleView()
}
