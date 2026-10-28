import AppKit
import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation

@MainActor
public final class CoreAudioSessionService: AudioSessionServicing {
    private var sessions: [String: RoutedProcessAudioSession] = [:]

    public init() {}

    public func discoverApplications(showOnlyActive: Bool) throws -> [RunningAudioApplication] {
        let processes = try AudioHardwareSystem.shared.processes
        var activeProcesses: [String: [pid_t]] = [:]

        for process in processes {
            do {
                guard try process.isRunningOutput else { continue }
                guard let bundleIdentifier = try process.bundleID, !bundleIdentifier.isEmpty else { continue }
                let pid = try process.pid
                activeProcesses[bundleIdentifier, default: []].append(pid)
            } catch {
                continue
            }
        }

        var bundleIdentifiers = Set(activeProcesses.keys)
        if !showOnlyActive {
            for runningApplication in NSWorkspace.shared.runningApplications
            where runningApplication.activationPolicy == .regular {
                guard let bundleIdentifier = runningApplication.bundleIdentifier else { continue }
                guard bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
                bundleIdentifiers.insert(bundleIdentifier)
            }
        }

        return bundleIdentifiers.compactMap { bundleIdentifier in
            let runningApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).filter { !$0.isTerminated }
            let representative = runningApplications.first
            let processIDs = Array(Set(activeProcesses[bundleIdentifier] ?? [])).sorted()
            let isAudioActive = !processIDs.isEmpty

            guard AudioControlRules.shouldShow(
                bundleIdentifier: bundleIdentifier,
                ownBundleIdentifier: Bundle.main.bundleIdentifier,
                isAudioActive: isAudioActive,
                showOnlyActive: showOnlyActive
            ) else {
                return nil
            }

            return RunningAudioApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: representative?.localizedName ?? bundleIdentifier,
                processIDs: processIDs,
                isAudioActive: isAudioActive,
                icon: representative?.icon
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func apply(
        _ preference: ApplicationAudioPreference,
        to application: RunningAudioApplication,
        defaultOutputUID: String?,
        availableDevices: [AudioOutputDevice]
    ) throws -> AudioControlStatus {
        guard application.isAudioActive else {
            stopControlling(bundleIdentifier: application.bundleIdentifier)
            return .passThrough
        }

        guard AudioControlRules.requiresProcessing(preference) else {
            stopControlling(bundleIdentifier: application.bundleIdentifier)
            return .passThrough
        }

        let availableUIDs = Set(availableDevices.map(\.uid))
        guard let outputUID = AudioControlRules.resolvedOutputUID(
            preferredUID: preference.outputDeviceUID,
            availableUIDs: availableUIDs,
            defaultUID: defaultOutputUID
        ) else {
            stopControlling(bundleIdentifier: application.bundleIdentifier)
            throw AudioServiceError.noOutputDevice
        }

        guard let outputDevice = try AudioHardwareSystem.shared.device(forUID: outputUID) else {
            stopControlling(bundleIdentifier: application.bundleIdentifier)
            throw AudioServiceError.deviceUnavailable(outputUID)
        }

        if let session = sessions[application.bundleIdentifier], session.outputDeviceUID == outputUID {
            session.setVolume(AudioControlRules.effectiveGain(for: preference))
            return .controlled
        }

        stopControlling(bundleIdentifier: application.bundleIdentifier)
        let session = try RoutedProcessAudioSession.create(
            bundleIdentifier: application.bundleIdentifier,
            outputDevice: outputDevice,
            volume: AudioControlRules.effectiveGain(for: preference)
        )
        sessions[application.bundleIdentifier] = session
        return .controlled
    }

    public func stopControlling(bundleIdentifier: String) {
        sessions.removeValue(forKey: bundleIdentifier)?.stop()
    }

    public func stopAll() {
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
    }
}

@MainActor
private final class RoutedProcessAudioSession {
    let outputDeviceUID: String

    private let tap: AudioHardwareTap
    private let aggregateDevice: AudioHardwareAggregateDevice
    private let engine: AVAudioEngine
    private let mixer: AVAudioMixerNode
    private var isStopped = false

    private init(
        outputDeviceUID: String,
        tap: AudioHardwareTap,
        aggregateDevice: AudioHardwareAggregateDevice,
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.tap = tap
        self.aggregateDevice = aggregateDevice
        self.engine = engine
        self.mixer = mixer
    }

    static func create(
        bundleIdentifier: String,
        outputDevice: AudioHardwareDevice,
        volume: Double
    ) throws -> RoutedProcessAudioSession {
        let system = AudioHardwareSystem.shared
        let outputUID = try outputDevice.uid
        let tapDescription = CATapDescription()
        tapDescription.name = "Sonic Route — \(bundleIdentifier)"
        tapDescription.bundleIDs = [bundleIdentifier]
        tapDescription.isProcessRestoreEnabled = true
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        let tap: AudioHardwareTap
        do {
            guard let createdTap = try system.makeProcessTap(description: tapDescription) else {
                throw AudioServiceError.tapCreationFailed("Core Audio não retornou um tap.")
            }
            tap = createdTap
        } catch {
            throw AudioServiceError.tapCreationFailed(error.localizedDescription)
        }

        let aggregateDescription: [String: Any]
        do {
            aggregateDescription = [
                kAudioAggregateDeviceNameKey: "Sonic Route Capture",
                kAudioAggregateDeviceUIDKey: "com.sonicroute.capture.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: try tap.uid]],
                kAudioAggregateDeviceTapAutoStartKey: 1
            ]
        } catch {
            try? system.destroyProcessTap(tap)
            throw AudioServiceError.aggregateDeviceCreationFailed
        }

        let aggregateDevice: AudioHardwareAggregateDevice
        do {
            guard let createdDevice = try system.makeAggregateDevice(description: aggregateDescription) else {
                try? system.destroyProcessTap(tap)
                throw AudioServiceError.aggregateDeviceCreationFailed
            }
            aggregateDevice = createdDevice
        } catch {
            try? system.destroyProcessTap(tap)
            throw AudioServiceError.aggregateDeviceCreationFailed
        }

        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        do {
            guard
                let inputAudioUnit = engine.inputNode.audioUnit,
                let outputAudioUnit = engine.outputNode.audioUnit
            else {
                throw AudioServiceError.engineUnavailable
            }

            var inputDeviceID = aggregateDevice.id
            let inputStatus = AudioUnitSetProperty(
                inputAudioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &inputDeviceID,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
            guard inputStatus == noErr else {
                throw AudioServiceError.engineStartFailed("Erro ao conectar a captura (\(inputStatus)).")
            }

            var outputDeviceID = outputDevice.id
            let outputStatus = AudioUnitSetProperty(
                outputAudioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &outputDeviceID,
                UInt32(MemoryLayout<AudioObjectID>.size)
            )
            guard outputStatus == noErr else {
                throw AudioServiceError.deviceUnavailable(try outputDevice.name)
            }

            mixer.outputVolume = Float(AudioControlRules.normalizedVolume(volume))
            engine.connect(engine.inputNode, to: mixer, format: nil)
            engine.prepare()
            try engine.start()
        } catch {
            engine.stop()
            try? system.destroyAggregateDevice(aggregateDevice)
            try? system.destroyProcessTap(tap)
            if let audioError = error as? AudioServiceError {
                throw audioError
            }
            throw AudioServiceError.engineStartFailed(error.localizedDescription)
        }

        return RoutedProcessAudioSession(
            outputDeviceUID: outputUID,
            tap: tap,
            aggregateDevice: aggregateDevice,
            engine: engine,
            mixer: mixer
        )
    }

    func setVolume(_ volume: Double) {
        mixer.outputVolume = Float(AudioControlRules.normalizedVolume(volume))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        engine.stop()
        try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
        try? AudioHardwareSystem.shared.destroyProcessTap(tap)
    }

}
