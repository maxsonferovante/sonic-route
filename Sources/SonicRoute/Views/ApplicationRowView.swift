import AppKit
import SwiftUI
import SonicRouteCore

struct ApplicationRowView: View {
    let row: ApplicationAudioRowState
    let outputDevices: [AudioOutputDevice]
    let defaultOutputUID: String?
    let onVolumeChanged: (Double) -> Void
    let onMuteToggled: () -> Void
    let onOutputChanged: (String?) -> Void

    private static let defaultOutputTag = "__system_default__"

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                appIcon
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(row.application.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 4)

                outputPicker
            }

            HStack(spacing: 8) {
                Button(action: onMuteToggled) {
                    Image(systemName: muteSymbol)
                        .frame(width: 18, height: 20)
                        .foregroundStyle(row.preference.isMuted ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(row.preference.isMuted ? "Ativar áudio" : "Silenciar app")
                .accessibilityLabel(row.preference.isMuted ? "Ativar áudio de \(row.application.displayName)" : "Silenciar \(row.application.displayName)")

                Slider(value: volumeBinding, in: 0...1)
                    .accessibilityLabel("Volume de \(row.application.displayName)")

                Text("\(AudioControlRules.percentage(for: row.preference.volume))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .accessibilityLabel("\(AudioControlRules.percentage(for: row.preference.volume)) por cento")
            }

            if let controlError = row.controlError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controlError)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Abrir Ajustes de Privacidade") {
                            AudioCapturePrivacySettings.open()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.link)
                    }
                }
                .padding(.leading, 25)
            } else if !row.application.isAudioActive {
                Text("As preferências serão aplicadas quando este app começar a reproduzir áudio.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 25)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var appIcon: Image {
        if let icon = row.application.icon {
            return Image(nsImage: icon)
        }
        return Image(systemName: "app.fill")
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { row.preference.volume },
            set: onVolumeChanged
        )
    }

    private var muteSymbol: String {
        if row.preference.isMuted { return "speaker.slash.fill" }
        return row.preference.volume == 0 ? "speaker.fill" : "speaker.wave.1.fill"
    }

    private var selectedOutputTag: String {
        row.preference.outputDeviceUID ?? Self.defaultOutputTag
    }

    private var outputPicker: some View {
        Picker(
            "Saída de áudio",
            selection: Binding(
                get: { selectedOutputTag },
                set: { onOutputChanged($0 == Self.defaultOutputTag ? nil : $0) }
            )
        ) {
            Label("Padrão do Sistema", systemImage: "speaker.wave.2")
                .tag(Self.defaultOutputTag)
            ForEach(outputDevices) { device in
                Label(device.name, systemImage: device.symbolName)
                    .tag(device.uid)
            }
            if let preferredUID = row.preference.outputDeviceUID,
               !outputDevices.contains(where: { $0.uid == preferredUID }) {
                Label("Saída indisponível · usando padrão", systemImage: "exclamationmark.circle")
                    .tag(preferredUID)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 170, alignment: .trailing)
        .help("Saída: \(currentOutputLabel)")
    }

    private var currentOutputLabel: String {
        guard let uid = row.preference.outputDeviceUID else {
            return outputDevices.first(where: { $0.uid == defaultOutputUID })?.name ?? "Padrão do Sistema"
        }
        return outputDevices.first(where: { $0.uid == uid })?.name ?? "Saída indisponível; usando padrão"
    }

}
