import Foundation

public enum AudioControlRules {
    public static func normalizedVolume(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }

    public static func percentage(for value: Double) -> Int {
        Int((normalizedVolume(value) * 100).rounded())
    }

    public static func effectiveGain(for preference: ApplicationAudioPreference) -> Double {
        preference.isMuted ? 0 : normalizedVolume(preference.volume)
    }

    public static func requiresProcessing(_ preference: ApplicationAudioPreference) -> Bool {
        preference.isMuted
            || normalizedVolume(preference.volume) < 1
            || preference.outputDeviceUID != nil
    }

    public static func resolvedOutputUID(
        preferredUID: String?,
        availableUIDs: Set<String>,
        defaultUID: String?
    ) -> String? {
        if let preferredUID, availableUIDs.contains(preferredUID) {
            return preferredUID
        }
        return defaultUID
    }

    public static func hasExternalOutput(in devices: [AudioOutputDevice]) -> Bool {
        devices.contains(where: \.isExternal)
    }

    public static func shouldShow(isAudioActive: Bool, showOnlyActive: Bool) -> Bool {
        !showOnlyActive || isAudioActive
    }
}
