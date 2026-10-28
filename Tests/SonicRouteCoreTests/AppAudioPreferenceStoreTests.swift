import Foundation
import Testing
@testable import SonicRouteCore

@Suite
struct AppAudioPreferenceStoreTests {
    @Test
    func savedControlsAreRestoredForTheMatchingBundleIdentifier() {
        let suiteName = "SonicRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppAudioPreferenceStore(defaults: defaults)
        let spotify = ApplicationAudioPreference(
            volume: 0.35,
            isMuted: true,
            outputDeviceUID: "usb-speakers"
        )
        store.setPreference(spotify, for: "com.spotify.client")

        #expect(store.preference(for: "com.spotify.client") == spotify)
        #expect(store.preference(for: "com.apple.FaceTime") == .default)
    }

    @Test
    func persistedVolumeIsKeptInsideTheSliderRange() {
        let suiteName = "SonicRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppAudioPreferenceStore(defaults: defaults)
        store.setPreference(
            ApplicationAudioPreference(volume: 1.5, isMuted: false, outputDeviceUID: nil),
            for: "com.example.player"
        )

        #expect(store.preference(for: "com.example.player").volume == 1)
    }
}
