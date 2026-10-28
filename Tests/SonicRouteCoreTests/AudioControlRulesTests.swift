import Testing
@testable import SonicRouteCore

@Suite
struct AudioControlRulesTests {
    @Test
    func muteSilencesOutputWithoutDiscardingSavedVolume() {
        let preference = ApplicationAudioPreference(
            volume: 0.42,
            isMuted: true,
            outputDeviceUID: nil
        )

        #expect(AudioControlRules.effectiveGain(for: preference) == 0)
        #expect(preference.volume == 0.42)
    }

    @Test
    func anyVolumeBelowFullScaleRequiresAudioProcessing() {
        #expect(AudioControlRules.requiresProcessing(
            ApplicationAudioPreference(volume: 0.999, isMuted: false, outputDeviceUID: nil)
        ))
        #expect(AudioControlRules.requiresProcessing(
            ApplicationAudioPreference(volume: 1, isMuted: false, outputDeviceUID: nil)
        ) == false)
    }

    @Test
    func sliderValuesStayWithinTheSupportedRange() {
        #expect(AudioControlRules.normalizedVolume(-0.2) == 0)
        #expect(AudioControlRules.normalizedVolume(1.4) == 1)
        #expect(AudioControlRules.percentage(for: 0.426) == 43)
    }

    @Test
    func missingPreferredOutputFallsBackToTheCurrentSystemOutput() {
        let resolved = AudioControlRules.resolvedOutputUID(
            preferredUID: "bluetooth-airpods",
            availableUIDs: ["internal-speakers", "usb-interface"],
            defaultUID: "internal-speakers"
        )

        #expect(resolved == "internal-speakers")
    }

    @Test
    func detectsWhetherAnExternalOutputIsAvailable() {
        let builtIn = AudioOutputDevice(uid: "internal", name: "Alto-falantes do Mac", kind: .builtIn)
        let bluetooth = AudioOutputDevice(uid: "airpods", name: "AirPods", kind: .bluetooth)

        #expect(AudioControlRules.hasExternalOutput(in: [builtIn]) == false)
        #expect(AudioControlRules.hasExternalOutput(in: [builtIn, bluetooth]))
        #expect(AudioControlRules.hasExternalOutput(in: []) == false)
    }

    @Test
    func selectedAppsFollowTheAudioActivityFilter() {
        #expect(AudioControlRules.shouldShow(
            bundleIdentifier: "com.example.player",
            ownBundleIdentifier: nil,
            isAudioActive: false,
            showOnlyActive: true
        ) == false)
        #expect(AudioControlRules.shouldShow(
            bundleIdentifier: "com.example.player",
            ownBundleIdentifier: nil,
            isAudioActive: false,
            showOnlyActive: false
        ))
        #expect(AudioControlRules.shouldShow(
            bundleIdentifier: "com.example.player",
            ownBundleIdentifier: nil,
            isAudioActive: true,
            showOnlyActive: true
        ))
    }

    @Test
    func neverShowsSonicRouteAsAControllableApplication() {
        #expect(AudioControlRules.shouldShow(
            bundleIdentifier: "com.sonicroute.SonicRoute",
            ownBundleIdentifier: "com.sonicroute.SonicRoute",
            isAudioActive: true,
            showOnlyActive: false
        ) == false)
    }
}
