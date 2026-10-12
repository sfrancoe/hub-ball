import SwiftUI

struct HeadlinesView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store: HeadlinesStore
    @State private var secondarySource: NewsSource
    let team: HubTeam

    init(team: HubTeam = .boston) {
        self.team = team
        _store = State(initialValue: HeadlinesStore(team: team))
        _secondarySource = State(initialValue: team.newsSources.dropFirst().first ?? team.newsSources[0])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if !store.feeds.isEmpty {
                        GeometryReader { space in
                            if contentWidth >= 720 && space.size.height > space.size.width {
                                let rows = team.newsSources.chunked(into: 2)
                                VStack(spacing: 12) {
                                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                        HStack(spacing: 12) {
                                            ForEach(row) { source in
                                                newspaperQuadrant(source)
                                            }
                                            if row.count == 1 {
                                                Color.clear.frame(maxWidth: .infinity)
                                            }
                                        }
                                        .frame(height: max(1, (space.size.height - 12 * CGFloat(rows.count + 1)) / CGFloat(rows.count)))
                                    }
                                }
                                .padding(12)
                            } else {
                                HStack(spacing: 0) {
                                    newspaperColumn(selection: $store.selectedSource)
                                    if contentWidth >= 720 {
                                        Divider().overlay(AppColor.teamAccent.opacity(0.3))
                                        newspaperColumn(selection: $secondarySource)
                                    }
                                }
                            }
                        }
                    } else if store.isLoading {
                        ProgressView("Loading headlines…")
                            .tint(.black)
                            .foregroundStyle(.black)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await store.load()
        }
    }

    private func newspaperQuadrant(_ source: NewsSource) -> some View {
        VStack(spacing: 0) {
            newspaperName(
                store.feeds[source]?.source ?? source.shortName,
                source: source,
                font: .system(size: 20, weight: .black)
            )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColor.accentSoft)
                .accessibilityAddTraits(.isHeader)

            Divider().overlay(AppColor.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let feed = store.feeds[source] {
                        ForEach(Array(feed.articles.enumerated()), id: \.element.id) { index, article in
                            newspaperStory(article)
                            if index < feed.articles.count - 1 {
                                Divider().overlay(AppColor.border)
                            }
                        }
                    } else {
                        errorView
                    }
                }
                .padding(.horizontal, 14)
            }
            .refreshable { await store.load() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.paper)
        .clipped()
    }

    private func newspaperStory(_ article: NewsArticle) -> some View {
        Group {
            if let url = URL(string: article.url) {
                Link(destination: url) {
                    newspaperStoryText(article)
                }
                .buttonStyle(.plain)
            } else {
                newspaperStoryText(article)
            }
        }
    }

    private func newspaperStoryText(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            articleHeadline(article, fontSize: 17)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.ink.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(article.publishedText)
                .font(.system(size: 10))
                .foregroundStyle(AppColor.hunterGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func newspaperColumn(selection: Binding<NewsSource>) -> some View {
        VStack(spacing: 0) {
            sourcePicker(selection: selection)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if let feed = store.feeds[selection.wrappedValue] {
                        feedHeader(feed, source: selection.wrappedValue)

                        ForEach(feed.articles) { article in
                            articleCard(article)
                        }
                    } else {
                        errorView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .foregroundStyle(AppColor.ink)
            }
            .id(selection.wrappedValue)
            .refreshable {
                await store.load()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourcePicker(selection: Binding<NewsSource>) -> some View {
        HStack(spacing: 0) {
            ForEach(team.newsSources) { source in
                Button {
                    selection.wrappedValue = source
                } label: {
                    newspaperName(
                        source.shortName,
                        source: source,
                        font: .system(
                            size: selection.wrappedValue == source ? 16 : 13,
                            weight: selection.wrappedValue == source ? .black : .semibold
                        )
                    )
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == source ? .isSelected : [])
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(AppColor.paper)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(AppColor.border, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func feedHeader(_ feed: NewsFeed, source: NewsSource) -> some View {
        HStack(alignment: .firstTextBaseline) {
            newspaperName(feed.source, source: source, font: .system(size: 14, weight: .black))

            Spacer()

            Text("Updated \(feed.refreshedText)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.78))
                .multilineTextAlignment(.trailing)
        }
    }

    private func newspaperName(_ name: String, source: NewsSource, font: Font) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let hasNewStory = store.feeds[source]?.articles.contains {
                $0.isNew(asOf: timeline.date)
            } ?? false
            let badge = Text(hasNewStory ? " ⚡" : "")
                .foregroundColor(AppColor.red)

            Text("\(Text(name))\(badge)")
                .font(font)
                .foregroundStyle(.black)
                .accessibilityLabel(hasNewStory ? "\(name), new stories available" : name)
        }
    }

    private func articleCard(_ article: NewsArticle) -> some View {
        Group {
            if let url = URL(string: article.url) {
                Link(destination: url) {
                    articleContent(article)
                }
                .buttonStyle(.plain)
            } else {
                articleContent(article)
            }
        }
        .frame(minHeight: 142, alignment: .topLeading)
        .cardStyle(padding: 14)
    }

    private func articleContent(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(article.category.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(AppColor.red)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(Color.black)

                Text(article.publishedText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.red)
            }

            articleHeadline(article, fontSize: contentWidth >= 650 ? 21 : 16,
                            lineLimit: contentWidth >= 650 ? 5 : 3)

            if !article.description.isEmpty {
                Text(article.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black)
                    .lineSpacing(2)
                    .lineLimit(4)
            }
        }
    }

    private func articleHeadline(_ article: NewsArticle, fontSize: CGFloat, lineLimit: Int? = nil) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let isNew = article.isNew(asOf: timeline.date)
            let badge = Text(isNew ? "  ⚡ NEW" : "")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(AppColor.red)
            Text("\(Text(article.title))\(badge)")
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(AppColor.ink)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(isNew ? "New in the last six hours. \(article.title)" : article.title)
        }
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Headlines Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The headlines could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(HubProminentButtonStyle())
            .tint(AppColor.red)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    HeadlinesView()
}
