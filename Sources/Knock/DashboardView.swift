import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine

    @State private var selectedPattern: KnockPattern?
    @State private var showingCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("nocnoc")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Dashboard — coming next")
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(32)
        }
        .background(
            LinearGradient(
                colors: [Theme.pageTop, Theme.pageBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(Theme.primaryText)
        .sheet(isPresented: $showingCalibration) {
            Text("Calibration Wizard — coming soon")
                .frame(width: 500, height: 400)
        }
        .onAppear {
            if !settingsStore.settings.hasCompletedCalibration {
                showingCalibration = true
            }
        }
    }
}
