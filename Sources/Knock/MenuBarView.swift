import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("nocnoc")
                .font(.title2.weight(.bold))

            updateStatusView

            Text(engine.lastActionSummary)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            WaveformView(values: motionMonitor.waveform, threshold: motionMonitor.snapshot.threshold * settingsStore.settings.waveformGain)
                .frame(height: 80)
                .padding(10)
                .background(Theme.darkPanel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Label(engine.isMonitoring ? "Monitoring" : "Paused", systemImage: engine.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                Spacer()
                Text("T \(motionMonitor.snapshot.threshold.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(.body, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

            Divider()

            Button(engine.isMonitoring ? "Pause Monitoring" : "Resume Monitoring") {
                engine.toggleMonitoring()
            }
            .buttonStyle(.plainHandCursor)

            Button("Open nocnoc") {
                if appModel.mainWindow == nil {
                    openWindow(id: "main")
                    DispatchQueue.main.async {
                        appModel.activateMainWindow()
                    }
                } else {
                    appModel.activateMainWindow()
                }
            }
            .buttonStyle(.plainHandCursor)

            Divider()

            Button("Quit") {
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plainHandCursor)
        }
        .padding(16)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.status {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking for updates...", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.accent)
        case .failed:
            Label("Update check failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        case .available(let version, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Update available: v\(version)", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.info)
            }
            .buttonStyle(.plainHandCursor)
        }
    }
}
