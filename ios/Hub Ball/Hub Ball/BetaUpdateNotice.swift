import SwiftUI

struct BetaUpdateNotice: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let target: BetaRelease
    let update: () -> Void
    let later: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                ScrollView { copy }.frame(height: 150)
            } else { copy }
            HStack(spacing: 16) {
                Button(action: update) { Text("Update").frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                    .accessibilityHint("Shows how to update Hub Ball in TestFlight")
                    .accessibilityIdentifier("beta-update.update")
                Button(action: later) { Text("Later").frame(minHeight: 44) }.buttonStyle(.bordered)
                    .accessibilityHint("Hides this update reminder for seven days")
                    .accessibilityIdentifier("beta-update.later")
            }.frame(minHeight: 44).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cream).foregroundStyle(AppColor.ink)
    }
    private var copy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hub Ball update available").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Version \(target.version) (\(target.build)) is ready in TestFlight.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BetaUpdateInstructions: View {
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Update Hub Ball in TestFlight").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Open the TestFlight app, select Hub Ball, then tap Update. You can also turn on Automatic Updates on Hub Ball’s TestFlight page.")
                        .accessibilityIdentifier("beta-update.instructions")
                    Text("If Update isn’t shown, keep using Hub Ball and check TestFlight again later.")
                    Link("TestFlight help from Apple", destination: BetaUpdateStore.helpURL)
                        .frame(minHeight: 44).accessibilityIdentifier("beta-update.help")
                }.padding(20).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(AppColor.cream)
            .navigationTitle("Update in TestFlight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: close).frame(minHeight: 44).accessibilityIdentifier("beta-update.done")
            } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
