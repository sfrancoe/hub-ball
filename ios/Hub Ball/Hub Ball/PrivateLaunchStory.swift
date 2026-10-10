import Foundation
import SwiftUI

/// Scott-only release seed: independent of public catalogs, refresh and disk-cache eviction.
nonisolated enum PrivateLaunchStory {
    static let item: PrivateStoryPreview? = {
        guard let catalogURL = Bundle.main.url(forResource: "story-private-separated-catalog", withExtension: "json"),
              let catalogBytes = try? Data(contentsOf: catalogURL), let catalog = try? StoryContract.decodeCatalog(catalogBytes),
              catalog.revision == "private-separated-october10", catalog.stories.count == 1,
              let entry = catalog.stories.first, entry.id == "separated-by-one",
              let url = Bundle.main.url(forResource: "story-private-separated-by-one", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              case .trajectory(let story) = try? StoryContract.decodeDocument(data, entry: entry) else { return nil }
        return PrivateStoryPreview(entry: entry, story: story)
    }()
}

struct PrivateLaunchStoryView: View {
    let item: PrivateStoryPreview
    var close: (() -> Void)? = nil
    var body: some View {
        TrajectoryStoryView(story: item.story, note: "Private preview · October 10, 2026", refresh: {}, endpointLabels: ["CWS", "CLE"])
            .navigationTitle("Hub Ball / Stories").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(AppColor.bone, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if let close {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Dismiss", action: close).frame(minHeight: 44)
                            .accessibilityIdentifier("private-launch.dismiss")
                    }
                }
            }
    }
}
