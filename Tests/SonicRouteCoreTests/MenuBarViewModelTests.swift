import Foundation
import Testing
@testable import SonicRouteCore

@Suite
@MainActor
struct MenuBarViewModelTests {
    @Test
    func appControlsPersistAndApplyWhenAudioBecomesActive() async {
        let suiteName = "SonicRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let application = RunningAudioApplication(
            bundleIdentifier: "com.example.player",
            displayName: "Example Player",
            processObjectIDs: [],
            isAudioActive: false
        )
        let sessions = FakeAudioSessionService(applications: [application])
        let store = AppAudioPreferenceStore(defaults: defaults)
        let viewModel = MenuBarViewModel(
            deviceService: FakeAudioDeviceService(
                devices: [
                    AudioOutputDevice(uid: "internal", name: "Alto-falantes do Mac"),
                    AudioOutputDevice(uid: "usb", name: "Interface USB")
                ],
                defaultUID: "internal"
            ),
            sessionService: sessions,
            preferenceStore: store,
            loginItemService: FakeLoginItemService(),
            globalShortcutService: FakeGlobalShortcutService(),
            defaults: defaults
        )

        await viewModel.refresh()
        viewModel.setShowOnlyActiveApps(false)
        await viewModel.refresh()
        viewModel.setVolume(0.4, for: application.bundleIdentifier)
        viewModel.setMuted(true, for: application.bundleIdentifier)
        viewModel.setOutputDevice("usb", for: application.bundleIdentifier)

        #expect(sessions.lastAppliedPreference == nil)

        sessions.applications = [
            RunningAudioApplication(
                bundleIdentifier: application.bundleIdentifier,
                displayName: application.displayName,
                processObjectIDs: [42],
                isAudioActive: true
            )
        ]
        await viewModel.refresh()

        let row = viewModel.applications.first
        #expect(row?.preference.volume == 0.4)
        #expect(row?.preference.isMuted == true)
        #expect(row?.preference.outputDeviceUID == "usb")
        #expect(row?.isBeingControlled == true)
        #expect(sessions.lastAppliedPreference?.volume == 0.4)
        #expect(sessions.lastAppliedPreference?.isMuted == true)
        #expect(store.preference(for: application.bundleIdentifier).outputDeviceUID == "usb")
    }
}

@MainActor
private final class FakeAudioDeviceService: AudioDeviceServicing {
    let devices: [AudioOutputDevice]
    let defaultUID: String?

    init(devices: [AudioOutputDevice], defaultUID: String?) {
        self.devices = devices
        self.defaultUID = defaultUID
    }

    func outputDevices() throws -> [AudioOutputDevice] { devices }
    func defaultOutputDeviceUID() throws -> String? { defaultUID }
}

@MainActor
private final class FakeAudioSessionService: AudioSessionServicing {
    var applications: [RunningAudioApplication]
    private(set) var lastAppliedPreference: ApplicationAudioPreference?

    init(applications: [RunningAudioApplication]) {
        self.applications = applications
    }

    func discoverApplications(showOnlyActive: Bool) throws -> [RunningAudioApplication] {
        applications.filter {
            AudioControlRules.shouldShow(
                bundleIdentifier: $0.bundleIdentifier,
                ownBundleIdentifier: nil,
                isAudioActive: $0.isAudioActive,
                showOnlyActive: showOnlyActive
            )
        }
    }

    func apply(
        _ preference: ApplicationAudioPreference,
        to application: RunningAudioApplication,
        defaultOutputUID: String?,
        availableDevices: [AudioOutputDevice]
    ) throws -> AudioControlStatus {
        lastAppliedPreference = preference
        return .controlled
    }

    func stopControlling(bundleIdentifier: String) {}
    func stopAll() {}
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

@MainActor
private final class FakeGlobalShortcutService: GlobalShortcutServicing {
    func setEnabled(_ enabled: Bool) throws {}
}
