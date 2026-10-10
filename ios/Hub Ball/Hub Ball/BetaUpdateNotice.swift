import SwiftUI

struct BetaUpdateNotice: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let update: () -> Void
    let later: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                ScrollView { copy }.frame(height: 150)
            } else { copy }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cream).foregroundStyle(AppColor.ink)
    }
    @ViewBuilder private var actions: some View {
        Button(action: later) { Text("Dismiss").frame(minHeight: 44) }.buttonStyle(.bordered)
            .accessibilityHint("Hides this update reminder for seven days")
            .accessibilityIdentifier("beta-update.later")
        Button(action: update) { Text("Open TestFlight to update").fixedSize(horizontal: false, vertical: true).frame(minHeight: 44) }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens TestFlight so you can select Hub Ball and update")
            .accessibilityIdentifier("beta-update.update")
    }
    private var copy: some View {
        Text("New version of Hub Ball").font(.headline).accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BetaUpdateInstructions: View {
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("TestFlight didn’t open").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Open TestFlight manually, select Hub Ball, then tap Update. You can also turn on Automatic Updates on Hub Ball’s TestFlight page.")
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
