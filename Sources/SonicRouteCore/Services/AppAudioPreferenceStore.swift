import Foundation

public final class AppAudioPreferenceStore: AppAudioPreferenceStoring {
    private let defaults: UserDefaults
    private let preferencesKey = "appAudioPreferences.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preference(for bundleIdentifier: String) -> ApplicationAudioPreference {
        guard
            let data = defaults.data(forKey: preferencesKey),
            let preferences = try? JSONDecoder().decode(
                [String: ApplicationAudioPreference].self,
                from: data
            )
        else {
            return .default
        }

        return preferences[bundleIdentifier] ?? .default
    }

    public func setPreference(_ preference: ApplicationAudioPreference, for bundleIdentifier: String) {
        var preferences = decodedPreferences()
        var normalized = preference
        normalized.volume = AudioControlRules.normalizedVolume(normalized.volume)
        preferences[bundleIdentifier] = normalized

        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: preferencesKey)
    }

    public func removeAllPreferences() {
        defaults.removeObject(forKey: preferencesKey)
    }

    private func decodedPreferences() -> [String: ApplicationAudioPreference] {
        guard
            let data = defaults.data(forKey: preferencesKey),
            let preferences = try? JSONDecoder().decode(
                [String: ApplicationAudioPreference].self,
                from: data
            )
        else {
            return [:]
        }
        return preferences
    }
}
