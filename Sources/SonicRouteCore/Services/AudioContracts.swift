import Foundation

@MainActor
public protocol AudioDeviceServicing: AnyObject {
    func outputDevices() throws -> [AudioOutputDevice]
    func defaultOutputDeviceUID() throws -> String?
}

@MainActor
public protocol AudioSessionServicing: AnyObject {
    func discoverApplications(showOnlyActive: Bool) throws -> [RunningAudioApplication]
    func apply(
        _ preference: ApplicationAudioPreference,
        to application: RunningAudioApplication,
        defaultOutputUID: String?,
        availableDevices: [AudioOutputDevice]
    ) throws -> AudioControlStatus
    func stopControlling(bundleIdentifier: String)
    func stopAll()
}

public protocol AppAudioPreferenceStoring: AnyObject {
    func preference(for bundleIdentifier: String) -> ApplicationAudioPreference
    func setPreference(_ preference: ApplicationAudioPreference, for bundleIdentifier: String)
    func removeAllPreferences()
}
