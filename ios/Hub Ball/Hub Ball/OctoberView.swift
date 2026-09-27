import SwiftUI
import UIKit

private enum OctoberSection: String, CaseIterable {
    case race = "Bracket"
    case tonight = "Tonight"
    case calls = "My Calls"
}

private func bracketLabel(_ series: PostseasonSeries) -> String {
    switch series.round {
    case "wild-card": "\(series.league ?? "League") Wild Card slot \(series.bracketSlot)"
    case "division-series": "\(series.league ?? "League") Division Series slot \(series.bracketSlot)"
    case "league-championship": "\(series.league ?? "League") Championship Series"
    case "world-series": "World Series"
    default: "Bracket slot not established"
    }
}

struct OctoberView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = PostseasonStore(season: OctoberFeature.season)
    @State private var section: OctoberSection = .race
    @State private var selectedSeries: PostseasonSeries?
    @State private var selectedCall: PostseasonSeries?

    private var payload: PostseasonPayload? { store.snapshot }
    private var series: [PostseasonSeries] { payload?.series ?? [] }

    var body: some View {
        ZStack {
            AppColor.night.ignoresSafeArea()
            VStack(spacing: 0) {
                masthead
                Picker("Playoff view", selection: $section) {
                    ForEach(OctoberSection.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Group {
                    if let payload {
                        switch section {
                        case .race: raceView(payload)
                        case .tonight: tonightView(payload)
                        case .calls: callsView(payload)
                        }
                    } else if store.isLoading {
                        ProgressView("Opening the playoff bracket…").tint(AppColor.amber)
                            .foregroundStyle(AppColor.bone)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.refresh()
            while !Task.isCancelled, scenePhase == .active {
                guard store.snapshot?.isLive == true else { break }
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, scenePhase == .active else { break }
                await store.refresh()
            }
        }
        .sheet(item: $selectedSeries) { series in
            OctoberSeriesDetail(series: series, allSeries: self.series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCall) { series in
            OctoberCallEditor(series: series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(String(OctoberFeature.season)) PLAYOFFS")
                    .font(AppFont.displayLarge)
                    .tracking(1.5)
                    .foregroundStyle(AppColor.bone)
                Spacer()
                if let checked = payload?.checkedDate {
                    Text(store.isDelayed ? "DELAYED UPDATES" : "CHECKED \(checked.formatted(date: .omitted, time: .shortened))")
                        .font(AppFont.label)
                        .foregroundStyle(store.isDelayed || store.refreshFailed ? AppColor.amber : AppColor.boneMuted)
                }
            }
            Text("EVERY SERIES. THE WHOLE PICTURE.")
                .font(AppFont.label)
                .tracking(1.1)
                .foregroundStyle(AppColor.boneMuted)
            if store.refreshFailed {
                HStack {
                    Text("Saved data · Updates unavailable")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.amber)
                    Spacer()
                    Button("Retry") { Task { await store.refresh() } }
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.bone)
                        .frame(minHeight: 44)
                }
            } else if store.isDelayed {
                Text("Saved live snapshot · Updates may be delayed")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.amber)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.nightRaised)
    }

    private func raceView(_ payload: PostseasonPayload) -> some View {
        PlayoffBracketView(payload: payload) { selectedSeries = $0 }
            .refreshable { await store.refresh() }
    }

    private var rootingChoices: [PostseasonClub] {
        let all = series.flatMap(\.participants).filter(\.resolved)
        return Dictionary(grouping: all, by: \.teamId).compactMap { $0.value.first }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func tonightView(_ payload: PostseasonPayload) -> some View {
        let tonight = relevantTonightGames(payload.games)
        let ordered = tonight.sorted {
            let firstPriority = priority($0, payload: payload)
            let secondPriority = priority($1, payload: payload)
            if firstPriority != secondPriority { return firstPriority < secondPriority }
            return ($0.gameDate ?? "", $0.gamePk) < ($1.gameDate ?? "", $1.gamePk)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHAT MATTERS NEXT")
                        .font(AppFont.displayMedium)
                        .foregroundStyle(AppColor.bone)
                    Text("Editorial priority · not a win probability")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.boneMuted)
                }
                if ordered.isEmpty {
                    Text("No postseason game is on today. Here is the next scheduled game and the latest confirmed result.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                }
                ForEach(ordered) { game in tonightCard(game, payload: payload) }
            }
            .padding(14)
        }
        .refreshable { await store.refresh() }
    }

    private func tonightCard(_ game: PostseasonGame, payload: PostseasonPayload) -> some View {
        let localDate = game.startDate
        let associated = game.seriesId.flatMap { id in series.first(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(associated.map { roundTitle($0.round) } ?? "POSTSEASON")
                    .font(AppFont.label).foregroundStyle(AppColor.amber)
                Spacer()
                Text(game.timeTBD || localDate == nil ? "TIME TBD" : localDate!.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.label).foregroundStyle(AppColor.boneMuted)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(game.away.name ?? game.away.slot ?? "TBD")
                    .frame(maxWidth: .infinity, alignment: .leading)
                score(game.awayScore)
                Text("—").foregroundStyle(AppColor.boneMuted)
                score(game.homeScore)
                Text(game.home.name ?? game.home.slot ?? "TBD")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            .font(AppFont.bodySmall.weight(.semibold))
            if !game.broadcasts.isEmpty {
                Text("BROADCAST · \(game.broadcasts.joined(separator: ", "))")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(game.status.uppercased())
                    .font(AppFont.label).foregroundStyle(game.abstractState == "Live" ? AppColor.amber : AppColor.boneMuted)
                if let inning = game.liveInning, game.abstractState == "Live" {
                    Text("· INNING \(inning)").font(AppFont.label).foregroundStyle(AppColor.boneDim)
                }
                Spacer()
                if game.conditional { Text("IF NECESSARY").font(AppFont.label).foregroundStyle(AppColor.boneMuted) }
            }
            Text(stakes(for: game, series: associated))
                .font(AppFont.bodySmall)
                .foregroundStyle(AppColor.boneDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .leading) { Rectangle().fill(game.abstractState == "Live" ? AppColor.amber : AppColor.rule).frame(width: 3) }
    }

    private func score(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "·")
            .font(AppFont.numberLarge)
            .monospacedDigit()
            .foregroundStyle(AppColor.bone)
            .frame(minWidth: 22)
    }

    private func callsView(_ payload: PostseasonPayload) -> some View {
        let established = series.filter {
            $0.participants.count == 2 && $0.requiredWins != nil
                && ($0.state != "complete" || store.call(for: $0) != nil)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MY CALLS").font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                    Text("A call stays on this device. A fresh entry opens for every new series.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                }
                if established.isEmpty {
                    Text("Calls open when both teams in a series are established.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppColor.nightRaised)
                }
                ForEach(established) { item in
                    Button { selectedCall = item } label: { callRow(item) }
                        .buttonStyle(.plain)
                        .disabled(!store.mayEdit(item) && store.call(for: item) == nil)
                }
                championPicker
            }
            .padding(14)
        }
    }

    private func callRow(_ item: PostseasonSeries) -> some View {
        let existing = store.call(for: item)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(roundTitle(item.round)).font(AppFont.label).foregroundStyle(AppColor.boneMuted)
                Spacer()
                Text(existing?.outcome == "correct" ? "CALLED IT" : existing?.outcome == "missed" ? "OCTOBER HAD OTHER PLANS" : existing?.entryCategory.uppercased() ?? "MAKE A CALL")
                    .font(AppFont.label).foregroundStyle(AppColor.amber)
            }
            Text(item.participants.compactMap(\.name).joined(separator: "  ·  "))
                .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
            if let existing {
                Text("Pick: \(teamName(existing.winnerTeamID)) in \(existing.seriesLength) · \(existing.entryCategory == "pre-series" ? "Pre-series" : "From here")\(existing.exactLength == true ? " · Exact length" : "")")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            } else {
                Text("Pick the series winner and length")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var championPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHAMPION CALL · OPTIONAL").font(AppFont.label).foregroundStyle(AppColor.boneMuted)
            Menu {
                Button("No champion call") { store.saveChampion(nil) }
                ForEach(rootingChoices, id: \.teamId) { club in
                    Button(club.name ?? "Team") { if let id = club.teamId { store.saveChampion(id) } }
                }
            } label: {
                Label(store.calls.championTeamID.map(teamName) ?? "Choose a champion", systemImage: "trophy")
                    .font(AppFont.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColor.amber)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.nightRaised)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The field hasn’t opened yet.").font(AppFont.displayMedium)
            Text("We’ll keep the MLB-wide postseason path here. Your favorite team stays as it is.")
                .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            if store.refreshFailed { Text("Postseason data is temporarily unavailable.").font(AppFont.bodySmall).foregroundStyle(AppColor.amber) }
            Button("Try again") { Task { await store.refresh() } }
                .buttonStyle(HubProminentButtonStyle())
                .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .foregroundStyle(AppColor.bone)
    }

    private func priority(_ game: PostseasonGame, payload: PostseasonPayload) -> Int {
        let current = game.seriesId.flatMap { id in series.first(where: { $0.id == id }) }
        let aWins = game.away.teamId.flatMap { current?.wins(for: $0) } ?? 0
        let hWins = game.home.teamId.flatMap { current?.wins(for: $0) } ?? 0
        let needed = current?.requiredWins ?? 99
        if aWins == needed - 1 || hWins == needed - 1 { return 0 }
        if let rooting = store.selectedRootingTeamID,
           game.away.teamId == rooting || game.home.teamId == rooting { return 1 }
        if game.abstractState == "Live" { return 2 }
        return 3
    }

    private func stakes(for game: PostseasonGame, series: PostseasonSeries?) -> String {
        guard let series, let required = series.requiredWins, let wins = series.wins,
              let awayID = game.away.teamId, let homeID = game.home.teamId else {
            return "Series score is shown when it is confirmed; stakes are not yet established."
        }
        let awayWins = wins[String(awayID)] ?? 0
        let homeWins = wins[String(homeID)] ?? 0
        if awayWins == required - 1, homeWins == required - 1 {
            return "Winner advances. The other team is eliminated."
        }
        if awayWins == required - 1 {
            return "A win by \(game.away.name ?? "\(awayID)") advances. \(game.home.name ?? "Their opponent") must win to extend the series."
        }
        if homeWins == required - 1 {
            return "A win by \(game.home.name ?? "\(homeID)") advances. \(game.away.name ?? "Their opponent") must win to extend the series."
        }
        if series.winnerTeamId != nil { return "Series complete. The result is confirmed above." }
        return "The series continues; neither team can clinch with one win tonight."
    }

    private func relevantTonightGames(_ games: [PostseasonGame]) -> [PostseasonGame] {
        let playable = games.filter { ["Preview", "Live", "Final"].contains($0.abstractState) }
        let live = playable.filter { $0.abstractState == "Live" }
        if !live.isEmpty { return live }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: Date())
        let upcoming = playable.filter { $0.abstractState == "Preview" || $0.abstractState == "Scheduled" }
        let nextDate = upcoming.compactMap { $0.gameDate?.prefix(10).description }
            .filter { $0 >= todayKey }.min()
        let next = upcoming.filter { $0.gameDate?.prefix(10).description == nextDate }
        let latestFinal = playable.filter { $0.abstractState == "Final" }
            .max { ($0.gameDate ?? "") < ($1.gameDate ?? "") }
        if next.isEmpty { return latestFinal.map { [$0] } ?? [] }
        return next + (latestFinal.map { [$0] } ?? [])
    }

    private func teamName(_ teamID: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == teamID })?.fullName ?? "Team"
    }

    private func roundTitle(_ round: String) -> String {
        switch round {
        case "wild-card": "Wild Card"
        case "division-series": "Division Series"
        case "league-championship": "League Championship"
        case "world-series": "World Series"
        default: "Postseason"
        }
    }

}

private struct OctoberSeriesDetail: View {
    @Environment(\.dismiss) private var dismiss
    let series: PostseasonSeries
    let allSeries: [PostseasonSeries]
    let store: PostseasonStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(series.participants.compactMap(\.name).joined(separator: "  ·  "))
                    .font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                ForEach(series.participants) { team in
                    HStack {
                        Text(team.name ?? team.slot ?? "Team to be determined")
                        Spacer()
                        Text(team.teamId.flatMap { series.wins(for: $0) }.map(String.init) ?? "—")
                            .font(AppFont.numberLarge).monospacedDigit().foregroundStyle(AppColor.amber)
                    }
                    .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
                }
                Text(seriesConsequence)
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                Text("Next: \(nextDescription)")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.night.ignoresSafeArea())
            .navigationTitle(series.round.replacingOccurrences(of: "-", with: " ").capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("series.close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func teamName(_ id: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == id })?.fullName ?? "Team"
    }

    private var seriesConsequence: String {
        guard let winner = series.winnerTeamId else {
            guard let required = series.requiredWins, let wins = series.wins,
                  let first = series.participants.first?.teamId,
                  let second = series.participants.dropFirst().first?.teamId else {
                return "Win/loss consequences are not established from the available series data."
            }
            let firstWins = wins[String(first)] ?? 0
            let secondWins = wins[String(second)] ?? 0
            if firstWins == required - 1, secondWins == required - 1 {
                return "Next game decides the series. The winner advances; the other team is eliminated."
            }
            if firstWins == required - 1 {
                return "A win by \(teamName(first)) advances. \(teamName(second)) must win to extend the series."
            }
            if secondWins == required - 1 {
                return "A win by \(teamName(second)) advances. \(teamName(first)) must win to extend the series."
            }
            return "A win adds one confirmed series win. Advancement is not yet determined."
        }
        return "Series winner: \(teamName(winner))."
    }

    private var nextDescription: String {
        guard let nextID = series.nextSlots?.first,
              let next = allSeries.first(where: { $0.id == nextID }) else {
            return "bracket slot not established"
        }
        return bracketLabel(next)
    }
}

private struct OctoberCallEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var winnerID: Int?
    @State private var length = 4
    @State private var shareItems: [Any] = []
    @State private var sharing = false
    let series: PostseasonSeries
    let store: PostseasonStore

    private var requiredWins: Int { series.requiredWins ?? 2 }
    private var possibleLengths: [Int] { (requiredWins...(requiredWins * 2 - 1)).map { $0 } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("PICK A SIDE")
                    .font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                ForEach(series.participants) { participant in
                    Button {
                        winnerID = participant.teamId
                        if length < requiredWins { length = requiredWins }
                    } label: {
                        HStack {
                            Text(participant.name ?? participant.slot ?? "Team")
                            Spacer()
                            if winnerID == participant.teamId { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.amber) }
                        }
                        .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
                        .padding(14).background(AppColor.nightRaised)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .disabled(!store.mayEdit(series) && store.call(for: series) != nil)
                }
                Picker("Series length", selection: $length) {
                    ForEach(possibleLengths, id: \.self) { games in Text("In \(games)").tag(games) }
                }
                .pickerStyle(.segmented)
                .tint(AppColor.amber)
                .disabled(!store.mayEdit(series) && store.call(for: series) != nil)
                if let winnerID {
                    Text("A call is a prediction. It does not change who you are rooting for.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                    Button(store.mayEdit(series) ? "Save and share my call" : "Share my call") {
                        if store.mayEdit(series) {
                            store.saveCall(series: series, winner: winnerID, length: length)
                        }
                        prepareShare(winnerID: winnerID)
                    }
                    .buttonStyle(HubProminentButtonStyle())
                    .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppColor.night.ignoresSafeArea())
            .navigationTitle("My Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(AppColor.bone) } }
            .sheet(isPresented: $sharing) { OctoberActivitySheet(items: shareItems) }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let existing = store.call(for: series) {
                winnerID = existing.winnerTeamID
                length = existing.seriesLength
            } else {
                winnerID = series.participants.first?.teamId
                length = requiredWins
            }
        }
    }

    @MainActor
    private func prepareShare(winnerID: Int) {
        let winner = teamName(winnerID)
        let round = series.round.replacingOccurrences(of: "-", with: " ").capitalized
        let webURL = URL(string: "https://red-sox.netlify.app/october/")!
        let savedCall = store.call(for: series)
        let outcome = savedCall?.outcome == "correct" ? "CALLED IT" : savedCall?.outcome == "missed" ? "OCTOBER HAD OTHER PLANS" : nil
        let color = HubTeam.allCases.first(where: { $0.mlbID == winnerID })?.definition.colors.teamTint ?? "#E8A33D"
        let ticket = OctoberTicketCard(
            winner: winner,
            round: round,
            length: length,
            outcome: outcome,
            exactLength: savedCall?.exactLength == true,
            teamColor: Color(hubHex: color)
        )
        let renderer = ImageRenderer(content: ticket.frame(width: 1080, height: 1350))
        renderer.scale = 1
        guard let image = renderer.uiImage else { return }
        let message = outcome.map { "\($0): I picked \(winner) in \(length) in the \(round). Your turn." }
            ?? "I called \(winner) in \(length) in the \(round). I called it. Your turn."
        shareItems = [image, message, webURL]
        sharing = true
    }

    private func teamName(_ id: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == id })?.fullName ?? "Team"
    }
}

private struct OctoberTicketCard: View {
    let winner: String
    let round: String
    let length: Int
    let outcome: String?
    let exactLength: Bool
    let teamColor: Color

    var body: some View {
        ZStack {
            AppColor.night
            VStack(alignment: .leading, spacing: 34) {
                HStack {
                    Text("HUB BALL").font(.custom("BarlowCondensed-SemiBold", size: 42)).tracking(4)
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.custom("Inter-Regular", size: 24).monospacedDigit())
                }
                Rectangle().fill(teamColor).frame(height: 4)
                VStack(alignment: .leading, spacing: 14) {
                    Text(outcome ?? "MY PLAYOFF CALL")
                        .font(.custom("Inter-Medium", size: 25)).tracking(3)
                        .foregroundStyle(AppColor.boneMuted)
                    Text(winner.uppercased())
                        .font(.custom("BarlowCondensed-SemiBold", size: 100))
                        .minimumScaleFactor(0.62).lineLimit(2)
                        .foregroundStyle(AppColor.bone)
                    Text("TO WIN THE \(round.uppercased())")
                        .font(.custom("Inter-Regular", size: 29)).tracking(1.5)
                    Text("IN \(length) GAMES")
                        .font(.custom("Inter-Medium", size: 34).monospacedDigit())
                        .foregroundStyle(teamColor)
                    if exactLength {
                        Text("EXACT LENGTH · BONUS BADGE")
                            .font(.custom("Inter-Medium", size: 22))
                            .tracking(1.4)
                            .foregroundStyle(AppColor.amber)
                    }
                }
                Spacer()
                    Text("I CALLED IT. YOUR TURN.")
                    .font(.custom("BarlowCondensed-SemiBold", size: 36)).tracking(1.2)
                Text("HUB BALL · BASEBALL AFTER DARK")
                    .font(.custom("Inter-Regular", size: 20)).tracking(2)
                    .foregroundStyle(AppColor.boneMuted)
            }
            .foregroundStyle(AppColor.bone)
            .padding(62)
        }
    }
}

private struct OctoberActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
