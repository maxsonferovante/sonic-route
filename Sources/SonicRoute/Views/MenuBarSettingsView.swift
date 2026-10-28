import AppKit
import SwiftUI
import SonicRouteCore

struct MenuBarSettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Toggle(
                "Iniciar junto ao macOS",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: viewModel.setLaunchAtLogin
                )
            )

            Toggle(
                "Mostrar apenas apps com áudio ativo",
                isOn: Binding(
                    get: { viewModel.showOnlyActiveApps },
                    set: viewModel.setShowOnlyActiveApps
                )
            )

            Toggle(
                "Restaurar preferências ao iniciar apps",
                isOn: Binding(
                    get: { viewModel.restorePreferencesOnLaunch },
                    set: viewModel.setRestorePreferencesOnLaunch
                )
            )

            Toggle(
                "Atalho global ⌃⌥⌘S",
                isOn: Binding(
                    get: { viewModel.globalShortcutEnabled },
                    set: viewModel.setGlobalShortcutEnabled
                )
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Permissão de áudio", systemImage: "waveform.badge.mic")
                    .font(.system(size: 12, weight: .semibold))
                Text("O macOS solicita permissão de gravação de áudio do sistema na primeira vez que você controla um app. O áudio é processado localmente e não é salvo.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abrir Ajustes de Privacidade") {
                    AudioCapturePrivacySettings.open()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.link)
            }

            if let settingsMessage = viewModel.settingsMessage {
                Text(settingsMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Atalho abre o painel com Control + Option + Command + S.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

}

enum AudioCapturePrivacySettings {
    static func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
