import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor
struct SeparatedStoryTests {
    @Test func officialArraysAndHeldEnding() throws {
        let item = try #require(PrivateLaunchStory.item), chart = item.story.chart
        #expect(item.id == "separated-by-one" && item.entry.title == "Separated by One")
        #expect(chart.series[0].points.map(\.y) == [0,6,8,11,16,19,22,29,31,37,42,49,55,58])
        #expect(chart.series[1].points.map(\.y) == [0,5,6,10,16,20,21,27,35,38,41,44,51,57])
        #expect(chart.kind == "line" && chart.sequence == nil && chart.durationSeconds == 10)
        #expect(chart.xAxis.minimum == 0 && chart.xAxis.maximum == 13 && chart.yAxis.minimum == 0 && chart.yAxis.maximum == 70)
        #expect(chart.frame(at: 10).progresses == [13,13] && chart.frame(at: 100).progresses == [13,13])
        #expect(chart.frame(at: 9).beat == nil && chart.frame(at: 10).beat?.title == "Tonight: one game to advance.")
        #expect(chart.frame(at: 10).beat?.detail.contains("CWS 7 · CLE 6") == true && chart.frame(at: 10).beat?.detail.contains("CLE 85 · CWS 84") == true)
        #expect(item.entry.minimumRendererVersion == 2)
    }
    @Test func isolatedFromPublicRefreshAndAvailableOffline() async throws {
        let item = try #require(PrivateLaunchStory.item)
        #expect(!StorySeed.catalog.stories.contains { $0.id == item.id })
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StoryCatalogStore(cache: StoryContentCache(directory: directory), fetch: { _,_ in throw URLError(.notConnectedToInternet) })
        await store.refresh(force: true)
        #expect(store.refreshFailed && PrivateLaunchStory.item?.id == item.id)
        #expect(PrivateStoryPreviews.items.count == 3)
    }
    @Test func oncePerFreshLaunchAfterOnboarding() throws {
        let entry = try #require(PrivateLaunchStory.item).entry
        var launch = FeaturedStoryLaunch()
        #expect(launch.offer(completedOnboarding: false,busy: false,entry: entry) == nil && !launch.consumed)
        #expect(launch.offer(completedOnboarding: true,busy: true,entry: entry) == nil && !launch.consumed)
        #expect(launch.offer(completedOnboarding: true,busy: false,entry: entry)?.id == "separated-by-one")
        #expect(launch.offer(completedOnboarding: true,busy: false,entry: entry) == nil)
        var cold = FeaturedStoryLaunch()
        #expect(cold.offer(completedOnboarding: true,busy: false,entry: entry)?.id == "separated-by-one")
    }
    @Test func integerCountsAtEveryFrameWithUnchangedSmoothGeometry() throws {
        let chart = try #require(PrivateLaunchStory.item).story.chart
        var previous = [0, 0]
        var sawFractionalGeometry = false
        for tick in 0...1000 {
            let frame = chart.frame(at: Double(tick) / 100)
            for (index, series) in chart.series.enumerated() {
                let progress = try #require(frame.progresses[index])
                let value = chart.value(in: series, at: progress)
                sawFractionalGeometry = sawFractionalGeometry || value != floor(value)
                let count = try #require(Int(TrajectoryNumberPresentation.wholeRunCounts.counter(value)))
                #expect(count == Int(floor(value)) && count >= previous[index])
                #expect(TrajectoryNumberPresentation.wholeRunCounts.axis(value) == String(count))
                previous[index] = count
            }
        }
        #expect(sawFractionalGeometry && previous == [58,57])
        #expect(chart.frame(at: 0).progresses == [0,0])
        #expect(TrajectoryNumberPresentation.wholeRunCounts.counter(58) == "58")
        #expect(TrajectoryNumberPresentation.wholeRunCounts.counter(57) == "57")
    }
    @Test func unrelatedRatesKeepFractionalPrecision() {
        #expect(TrajectoryNumberPresentation.standard.counter(12.34) == 12.34.formatted(.number.precision(.fractionLength(0...1))))
        #expect(TrajectoryNumberPresentation.standard.axis(0.300) == 0.300.formatted())
        #expect(TrajectoryNumberPresentation.standard.axis(57.25, grouping: false) == 57.25.formatted(.number.grouping(.never)))
    }

}
