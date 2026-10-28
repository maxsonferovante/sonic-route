import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public private(set) var applications: [ApplicationAudioRowState] = []
    @Published public private(set) var outputDevices: [AudioOutputDevice] = []
    @Published public private(set) var defaultOutputUID: String?
    @Published public private(set) var isLoading = true
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var settingsMessage: String?
    @Published public private(set) var refreshDate: Date?

    @Published public private(set) var showOnlyActiveApps: Bool
    @Published public private(set) var restorePreferencesOnLaunch: Bool
    @Published public private(set) var launchAtLogin: Bool
    @Published public private(set) var globalShortcutEnabled: Bool

    public var hasExternalOutputDevices: Bool {
        AudioControlRules.hasExternalOutput(in: outputDevices)
    }

    private let deviceService: AudioDeviceServicing
    private let sessionService: AudioSessionServicing
    private let preferenceStore: AppAudioPreferenceStoring
    private let loginItemService: LoginItemServicing
    private let globalShortcutService: GlobalShortcutServicing
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var controlledBundleIdentifiers = Set<String>()
    private var sessionPreferences: [String: ApplicationAudioPreference] = [:]

    private enum SettingKey {
        static let showOnlyActiveApps = "showOnlyActiveApps"
        static let restorePreferencesOnLaunch = "restorePreferencesOnLaunch"
        static let globalShortcutEnabled = "globalShortcutEnabled"
    }

    public init(
        deviceService: AudioDeviceServicing? = nil,
        sessionService: AudioSessionServicing? = nil,
        preferenceStore: AppAudioPreferenceStoring? = nil,
        loginItemService: LoginItemServicing? = nil,
        globalShortcutService: GlobalShortcutServicing? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.deviceService = deviceService ?? CoreAudioDeviceService()
        self.sessionService = sessionService ?? CoreAudioSessionService()
        self.preferenceStore = preferenceStore ?? AppAudioPreferenceStore()
        self.loginItemService = loginItemService ?? LoginItemService()
        self.globalShortcutService = globalShortcutService ?? CarbonGlobalShortcutService()
        self.defaults = defaults

        showOnlyActiveApps = defaults.object(forKey: SettingKey.showOnlyActiveApps) as? Bool ?? true
        restorePreferencesOnLaunch = defaults.object(forKey: SettingKey.restorePreferencesOnLaunch) as? Bool ?? true
        globalShortcutEnabled = defaults.object(forKey: SettingKey.globalShortcutEnabled) as? Bool ?? false
        launchAtLogin = self.loginItemService.isEnabled

        if globalShortcutEnabled {
            try? self.globalShortcutService.setEnabled(true)
        }
    }

    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        sessionService.stopAll()
        controlledBundleIdentifiers.removeAll()
    }

    public func refresh() async {
        do {
            let devices = try deviceService.outputDevices()
            let defaultUID = try deviceService.defaultOutputDeviceUID()
            let discovered = try sessionService.discoverApplications(showOnlyActive: showOnlyActiveApps)
            let activeBundleIdentifiers = Set(
                discovered.filter(\.isAudioActive).map(\.bundleIdentifier)
            )

            for staleBundleIdentifier in controlledBundleIdentifiers.subtracting(activeBundleIdentifiers) {
                sessionService.stopControlling(bundleIdentifier: staleBundleIdentifier)
                controlledBundleIdentifiers.remove(staleBundleIdentifier)
            }

            var nextRows: [ApplicationAudioRowState] = []
            for application in discovered {
                let preference = effectivePreference(for: application.bundleIdentifier)
                var status: AudioControlStatus = .passThrough
                if application.isAudioActive {
                    do {
                        status = try sessionService.apply(
                            preference,
                            to: application,
                            defaultOutputUID: defaultUID,
                            availableDevices: devices
                        )
                    } catch {
                        status = .failed(error.localizedDescription)
                    }
                }

                switch status {
                case .controlled:
                    controlledBundleIdentifiers.insert(application.bundleIdentifier)
                case .passThrough, .failed:
                    controlledBundleIdentifiers.remove(application.bundleIdentifier)
                }

                let controlError: String?
                if case .failed(let message) = status {
                    controlError = message
                } else {
                    controlError = nil
                }

                nextRows.append(
                    ApplicationAudioRowState(
                        application: application,
                        preference: preference,
                        isBeingControlled: status == .controlled,
                        controlError: controlError
                    )
                )
            }

            outputDevices = devices
            defaultOutputUID = defaultUID
            applications = nextRows
            errorMessage = nil
            refreshDate = Date()
        } catch {
            errorMessage = "Não foi possível consultar os dispositivos ou apps de áudio. \(error.localizedDescription)"
        }

        isLoading = false
    }

    public func setVolume(_ value: Double, for bundleIdentifier: String) {
        updatePreference(for: bundleIdentifier) {
            $0.volume = AudioControlRules.normalizedVolume(value)
        }
    }

    public func toggleMute(for bundleIdentifier: String) {
        updatePreference(for: bundleIdentifier) { $0.isMuted.toggle() }
    }

    public func setMuted(_ isMuted: Bool, for bundleIdentifier: String) {
        updatePreference(for: bundleIdentifier) { $0.isMuted = isMuted }
    }

    public func setOutputDevice(_ uid: String?, for bundleIdentifier: String) {
        updatePreference(for: bundleIdentifier) { $0.outputDeviceUID = uid }
    }

    public func setShowOnlyActiveApps(_ isEnabled: Bool) {
        guard showOnlyActiveApps != isEnabled else { return }
        showOnlyActiveApps = isEnabled
        defaults.set(isEnabled, forKey: SettingKey.showOnlyActiveApps)
        Task { await refresh() }
    }

    public func setRestorePreferencesOnLaunch(_ isEnabled: Bool) {
        guard restorePreferencesOnLaunch != isEnabled else { return }
        restorePreferencesOnLaunch = isEnabled
        defaults.set(isEnabled, forKey: SettingKey.restorePreferencesOnLaunch)
        sessionPreferences.removeAll()
        Task { await refresh() }
    }

    public func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItemService.setEnabled(isEnabled)
            launchAtLogin = loginItemService.isEnabled
            settingsMessage = launchAtLogin == isEnabled ? nil : "O macOS ainda precisa aprovar o item de início de sessão."
        } catch {
            launchAtLogin = loginItemService.isEnabled
            settingsMessage = error.localizedDescription
        }
    }

    public func setGlobalShortcutEnabled(_ isEnabled: Bool) {
        do {
            try globalShortcutService.setEnabled(isEnabled)
            globalShortcutEnabled = isEnabled
            defaults.set(isEnabled, forKey: SettingKey.globalShortcutEnabled)
            settingsMessage = nil
        } catch {
            globalShortcutEnabled = false
            defaults.set(false, forKey: SettingKey.globalShortcutEnabled)
            settingsMessage = error.localizedDescription
        }
    }

    public func clearSettingsMessage() {
        settingsMessage = nil
    }

    private func updatePreference(
        for bundleIdentifier: String,
        mutation: (inout ApplicationAudioPreference) -> Void
    ) {
        guard let index = applications.firstIndex(where: { $0.id == bundleIdentifier }) else { return }
        var preference = applications[index].preference
        mutation(&preference)
        preference.volume = AudioControlRules.normalizedVolume(preference.volume)
        sessionPreferences[bundleIdentifier] = preference
        preferenceStore.setPreference(preference, for: bundleIdentifier)
        applications[index].preference = preference

        let application = applications[index].application
        guard application.isAudioActive else { return }

        do {
            let status = try sessionService.apply(
                preference,
                to: application,
                defaultOutputUID: defaultOutputUID,
                availableDevices: outputDevices
            )
            applications[index].isBeingControlled = status == .controlled
            applications[index].controlError = nil
            if status == .controlled {
                controlledBundleIdentifiers.insert(bundleIdentifier)
            } else {
                controlledBundleIdentifiers.remove(bundleIdentifier)
            }
        } catch {
            applications[index].isBeingControlled = false
            applications[index].controlError = error.localizedDescription
            controlledBundleIdentifiers.remove(bundleIdentifier)
        }
    }

    private func effectivePreference(for bundleIdentifier: String) -> ApplicationAudioPreference {
        if let sessionPreference = sessionPreferences[bundleIdentifier] {
            return sessionPreference
        }
        return restorePreferencesOnLaunch
            ? preferenceStore.preference(for: bundleIdentifier)
            : .default
    }
}
