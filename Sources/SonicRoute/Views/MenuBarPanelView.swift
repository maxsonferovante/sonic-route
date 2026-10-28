import SwiftUI
import SonicRouteCore

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.vertical, 10)

            if showingSettings {
                MenuBarSettingsView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                applicationContent
                    .transition(.opacity)
            }

            Divider().padding(.vertical, 10)
            footer
        }
        .padding(15)
        .frame(width: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.16), value: showingSettings)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 25, height: 25)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Sonic Route")
                    .font(.system(size: 14, weight: .semibold))
                Text(showingSettings ? "Ajustes" : "Controle de áudio por app")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { showingSettings.toggle() }
                viewModel.clearSettingsMessage()
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Voltar aos apps" : "Ajustes")
            .accessibilityLabel(showingSettings ? "Voltar aos apps" : "Abrir ajustes")
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
        if viewModel.isLoading && viewModel.applications.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Procurando apps com áudio…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text("Não foi possível acessar o áudio")
                    .font(.system(size: 13, weight: .semibold))
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Tentar novamente") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        } else if viewModel.applications.isEmpty {
            emptyState
        } else {
            VStack(spacing: 7) {
                if viewModel.defaultOutputUID != nil && !viewModel.hasExternalOutputDevices {
                    Label("Nenhuma saída externa conectada", systemImage: "headphones")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(viewModel.applications) { row in
                            ApplicationRowView(
                                row: row,
                                outputDevices: viewModel.outputDevices,
                                defaultOutputUID: viewModel.defaultOutputUID,
                                onVolumeChanged: { viewModel.setVolume($0, for: row.id) },
                                onMuteToggled: { viewModel.toggleMute(for: row.id) },
                                onOutputChanged: { viewModel.setOutputDevice($0, for: row.id) }
                            )
                            if row.id != viewModel.applications.last?.id {
                                Divider().padding(.leading, 39)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 500)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.secondary)
            Text(viewModel.showOnlyActiveApps ? "Nenhum app com áudio ativo" : "Nenhum app aberto")
                .font(.system(size: 13, weight: .semibold))
            Text(viewModel.showOnlyActiveApps
                 ? "A lista será atualizada quando um app começar a reproduzir áudio."
                 : "Abra um app que possa emitir áudio para controlá-lo aqui.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.defaultOutputUID != nil && !viewModel.hasExternalOutputDevices {
                Label("Nenhuma saída externa conectada", systemImage: "headphones")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.outputDevices.isEmpty ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(viewModel.outputDevices.first(where: { $0.uid == viewModel.defaultOutputUID })?.name ?? "Saída padrão indisponível")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !showingSettings {
                Button("Atualizar") {
                    Task { await viewModel.refresh() }
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}
