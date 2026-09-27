import SwiftUI

struct PlayoffBracketView: View {
    let payload: PostseasonPayload
    let onSelect: (PostseasonSeries) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var minimumCardWidth = 98.0
    @ScaledMetric(relativeTo: .caption) private var cardHeight = 68.0
    @ScaledMetric(relativeTo: .caption) private var nameSize = 12.0

    private func series(_ slot: PlayoffBracketSlot) -> PostseasonSeries? {
        payload.series.first { $0.id == slot.seriesID(season: payload.season) }
    }

    var body: some View {
        GeometryReader { bounds in
            let wide = bounds.size.width >= 900
            let columns = wide ? 7.0 : 3.0
            let width = max(bounds.size.width - 24, minimumCardWidth * columns + (columns - 1) * 12)
            let fittedHeight = wide ? cardHeight * 1.25
                : dynamicTypeSize.isAccessibilitySize ? cardHeight
                : min(cardHeight, max(56, (bounds.size.height - 24 - 152.6) / 5.2))
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 12) {
                    bracket(width: width, wide: wide, cardHeight: fittedHeight)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.tap")
                        Text("Tap a matchup for series details. Numbers are series wins.")
                    }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneDim)
                    if payload.phase == "field-setting" {
                        Text("FIELD TAKING SHAPE · Matchups follow MLB’s current schedule. Unsettled places stay open.")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.boneMuted)
                    }
                }
                .frame(width: width)
                .frame(minHeight: max(0, bounds.size.height - 24), alignment: .topLeading)
                .padding(12)
            }
            .defaultScrollAnchor(.topLeading)
            .accessibilityIdentifier("playoffs.bracket")
        }
    }

    private func center(_ slot: PlayoffBracketSlot, width: CGFloat, wide: Bool, cardHeight: CGFloat) -> CGPoint {
        let columns = wide ? 7.0 : 3.0
        let cell = (width - (columns - 1) * 12) / columns
        let step = wide ? max(170, cardHeight + 18) : cardHeight + 18
        if wide {
            let y = slot.round == "wild-card" || slot.round == "division-series"
                ? 90 + CGFloat(slot.row) * step : 90 + step / 2
            return CGPoint(x: cell / 2 + CGFloat(slot.column) * (cell + 12), y: y)
        }
        if slot.league == "MLB" { return CGPoint(x: width / 2, y: 68 + step * 2.35) }
        let leagueOffset = slot.league == "NL" ? step * 3.7 : 0
        let column = slot.league == "NL" ? slot.column - 4 : slot.column
        let y = slot.round == "league-championship" ? step / 2 : CGFloat(slot.row) * step
        return CGPoint(x: cell / 2 + CGFloat(column) * (cell + 12), y: 68 + leagueOffset + y)
    }

    private func bracket(width: CGFloat, wide: Bool, cardHeight: CGFloat) -> some View {
        let columns = wide ? 7.0 : 3.0
        let cell = (width - (columns - 1) * 12) / columns
        let step = wide ? max(170, cardHeight + 18) : cardHeight + 18
        let height = wide ? 100 + step + cardHeight / 2 : 68 + step * 4.7 + cardHeight / 2
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for slot in PlayoffBracketSlot.all {
                    guard let destination = PlayoffBracketSlot.all.first(where: { $0.id == slot.destinationID }) else { continue }
                    let start = center(slot, width: width, wide: wide, cardHeight: cardHeight)
                    let end = center(destination, width: width, wide: wide, cardHeight: cardHeight)
                    var path = Path()
                    if !wide && destination.league == "MLB" {
                        let direction: CGFloat = slot.league == "AL" ? 1 : -1
                        let a = CGPoint(x: start.x, y: start.y + direction * cardHeight / 2)
                        let b = CGPoint(x: end.x, y: end.y - direction * cardHeight / 2)
                        let elbow = (a.y + b.y) / 2
                        path.move(to: a)
                        path.addLine(to: CGPoint(x: a.x, y: elbow))
                        path.addLine(to: CGPoint(x: b.x, y: elbow))
                        path.addLine(to: b)
                    } else {
                        let direction: CGFloat = end.x > start.x ? 1 : -1
                        let a = CGPoint(x: start.x + direction * cell / 2, y: start.y)
                        let b = CGPoint(x: end.x - direction * cell / 2, y: end.y)
                        path.move(to: a)
                        path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: a.y))
                        path.addLine(to: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                        path.addLine(to: b)
                    }
                    let confirmed = series(slot)?.winnerTeamId != nil
                    context.stroke(path, with: .color(confirmed ? AppColor.amber : AppColor.boneMuted.opacity(0.55)), lineWidth: confirmed ? 2 : 1)
                }
            }
            .accessibilityHidden(true)

            if wide {
                leagueHeading("AMERICAN LEAGUE", color: AppColor.steel)
                    .position(x: cell * 1.5 + 12, y: 12)
                leagueHeading("NATIONAL LEAGUE", color: AppColor.amber)
                    .position(x: width - cell * 1.5 - 12, y: 12)
                ForEach(Array(["WILD CARD", "DIVISION", "ALCS", "WORLD SERIES", "NLCS", "DIVISION", "WILD CARD"].enumerated()), id: \.offset) { index, label in
                    roundHeading(label).frame(width: cell)
                        .position(x: cell / 2 + CGFloat(index) * (cell + 12), y: 40)
                }
            } else {
                leagueHeading("AMERICAN LEAGUE", color: AppColor.steel)
                    .position(x: width / 2, y: 8)
                leagueHeading("NATIONAL LEAGUE", color: AppColor.amber)
                    .position(x: width / 2, y: 8 + step * 3.7)
                ForEach(0..<3) { index in
                    roundHeading(["WILD CARD", "DIVISION", "ALCS"][index]).frame(width: cell)
                        .position(x: cell / 2 + CGFloat(index) * (cell + 12), y: 25)
                    roundHeading(["NLCS", "DIVISION", "WILD CARD"][index]).frame(width: cell)
                        .position(x: cell / 2 + CGFloat(index) * (cell + 12), y: 25 + step * 3.7)
                }
                Label("WORLD SERIES", systemImage: "trophy.fill")
                    .font(.system(size: nameSize, weight: .bold))
                    .foregroundStyle(AppColor.amber)
                    .padding(.horizontal, 5).background(AppColor.night)
                    .position(x: width / 2, y: 68 + step * 2.35 - cardHeight / 2 - 16)
            }

            ForEach(PlayoffBracketSlot.all) { slot in
                matchup(slot, width: cell)
                    .frame(width: cell, height: cardHeight)
                    .position(center(slot, width: width, wide: wide, cardHeight: cardHeight))
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Complete \(payload.season) MLB playoff bracket, American League, World Series, National League")
    }

    private func leagueHeading(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: nameSize, weight: .bold)).tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5).background(AppColor.night)
    }

    private func roundHeading(_ text: String) -> some View {
        Text(text).font(.system(size: nameSize - 3, weight: .semibold))
            .tracking(0.5).foregroundStyle(AppColor.boneMuted)
            .background(AppColor.night)
    }

    private func matchup(_ slot: PlayoffBracketSlot, width: CGFloat) -> some View {
        let labelSize = width > 120 ? nameSize * 1.15 : nameSize
        let item = series(slot)
        let rows = participants(item, slot: slot)
        return Button {
            if let item { onSelect(item) }
        } label: {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(row.teamId.flatMap(teamColor) ?? AppColor.boneMuted.opacity(0.5))
                            .frame(width: 3, height: 14)
                        Text(compactName(row, width: width))
                            .font(.system(size: labelSize, weight: .semibold))
                            .foregroundStyle(row.resolved ? AppColor.bone : AppColor.boneDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if item?.winnerTeamId == row.teamId, row.teamId != nil {
                            Image(systemName: "checkmark").font(.system(size: labelSize - 2, weight: .bold))
                                .foregroundStyle(AppColor.amber)
                        }
                        Text(row.teamId.flatMap { item?.wins(for: $0) }.map(String.init) ?? "–")
                            .font(.system(size: labelSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(item?.winnerTeamId == row.teamId && row.teamId != nil ? AppColor.amber : AppColor.bone)
                    }
                    .padding(.horizontal, 7)
                    .frame(maxHeight: .infinity)
                    if index == 0 { Rectangle().fill(AppColor.rule).frame(height: 0.5) }
                }
                Text(status(item))
                    .font(.system(size: labelSize - 3, weight: .medium))
                    .foregroundStyle(item?.state == "live" ? AppColor.amber : AppColor.boneMuted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(AppColor.night)
            }
            .background(AppColor.nightRaised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(slot.league == "MLB" ? AppColor.amber.opacity(0.8) : AppColor.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .accessibilityIdentifier("bracket.\(slot.id)")
        .accessibilityLabel("\(slot.league) \(slot.round.replacingOccurrences(of: "-", with: " ")), \(rows.map { $0.name ?? $0.slot ?? "TBD" }.joined(separator: " versus "))")
        .accessibilityValue(rows.map { row in
            "\(row.name ?? row.slot ?? "TBD"): \(row.teamId.flatMap { item?.wins(for: $0) }.map { "\($0) series wins" } ?? "unresolved")"
        }.joined(separator: ", ") + ". " + status(item))
        .accessibilityHint("Opens series details")
    }

    private func participants(_ item: PostseasonSeries?, slot: PlayoffBracketSlot) -> [PostseasonClub] {
        var result = item?.participants ?? []
        let fallback: [String]
        switch slot.round {
        case "world-series": fallback = ["AL champion", "NL champion"]
        case "league-championship": fallback = ["Division winner", "Division winner"]
        default: fallback = item?.unresolvedSlots ?? []
        }
        for label in fallback where result.count < 2 {
            result.append(PostseasonClub(teamId: nil, name: nil, abbreviation: nil, slot: label, resolved: false))
        }
        while result.count < 2 {
            result.append(PostseasonClub(teamId: nil, name: nil, abbreviation: nil, slot: "TBD", resolved: false))
        }
        return Array(result.prefix(2))
    }

    private func compactName(_ club: PostseasonClub, width: CGFloat) -> String {
        if let id = club.teamId, let team = HubTeam.allCases.first(where: { $0.mlbID == id }) {
            return width > 150 ? team.shortName : (club.abbreviation ?? team.abbreviation)
        }
        let label = club.slot ?? club.name ?? "TBD"
        if label.hasSuffix("champion") { return label }
        return label.replacingOccurrences(of: "AL ", with: "")
            .replacingOccurrences(of: "NL ", with: "")
            .replacingOccurrences(of: "Wild Card #", with: "WC ")
            .replacingOccurrences(of: " Winner", with: " winner")
    }

    private func status(_ item: PostseasonSeries?) -> String {
        guard let item else { return "MATCHUP TBD" }
        if item.state == "complete" { return "FINAL · \(item.completedGameCount) GAMES" }
        if item.state == "unknown" { return "UNDER REVIEW" }
        let games = payload.games.filter { $0.seriesId == item.id }
        if let live = games.first(where: { $0.abstractState == "Live" }) {
            return "LIVE" + (live.liveInning.map { " · INNING \($0)" } ?? "")
        }
        if let next = games.filter({ $0.abstractState == "Preview" || $0.abstractState == "Scheduled" })
            .min(by: { ($0.gameDate ?? "") < ($1.gameDate ?? "") }) {
            // A TBD provider timestamp is a date placeholder, never a local start time.
            if next.timeTBD { return "\(next.gameDate.map { String($0.prefix(10).suffix(5)).replacingOccurrences(of: "-", with: "/") } ?? "DATE TBD") · TIME TBD" }
            if let date = next.startDate { return date.formatted(.dateTime.month(.abbreviated).day()).uppercased() }
        }
        return item.requiredWins.map { "FIRST TO \($0)" } ?? "MATCHUP TBD"
    }

    private func teamColor(_ id: Int) -> Color? {
        HubTeam.allCases.first { $0.mlbID == id }.map { Color(hubHex: $0.colors.primary) }
    }
}
