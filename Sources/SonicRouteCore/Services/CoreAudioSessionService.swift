import AppKit
import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation
import Synchronization

@MainActor
public final class CoreAudioSessionService: AudioSessionServicing {
    private var sessions: [String: RoutedProcessAudioSession] = [:]

    public init() {}

    public func discoverApplications(showOnlyActive: Bool) throws -> [RunningAudioApplication] {
        let processes = try AudioHardwareSystem.shared.processes
        var activeProcesses: [String: [AudioObjectID]] = [:]
        var representatives: [String: NSRunningApplication] = [:]
        var fallbackRepresentatives: [String: NSRunningApplication] = [:]
        let runningApplications = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var regularApplications: [String: NSRunningApplication] = [:]
        for application in runningApplications where application.activationPolicy == .regular {
            guard let bundleIdentifier = application.bundleIdentifier else { continue }
            regularApplications[bundleIdentifier] = application
        }
        let applicationIdentityCandidates = regularApplications.compactMap { entry -> AudioApplicationIdentityCandidate? in
            guard let bundleURL = entry.value.bundleURL else { return nil }
            return AudioApplicationIdentityCandidate(
                bundleIdentifier: entry.key,
                bundlePath: bundleURL.path
            )
        }

        for process in processes {
            do {
                guard try process.isRunningOutput else { continue }
                guard let bundleIdentifier = try process.bundleID, !bundleIdentifier.isEmpty else { continue }
                let processApplication = NSRunningApplication(processIdentifier: try process.pid)
                let hostApplication = AudioApplicationIdentityRules.hostApplication(
                    processBundleIdentifier: bundleIdentifier,
                    processBundleURL: processApplication?.bundleURL,
                    candidates: applicationIdentityCandidates
                )
                let applicationBundleIdentifier = hostApplication?.bundleIdentifier ?? bundleIdentifier
                activeProcesses[applicationBundleIdentifier, default: []].append(process.id)

                if let processApplication {
                    fallbackRepresentatives[bundleIdentifier] = processApplication
                }
                if let representative = regularApplications[applicationBundleIdentifier] {
                    representatives[applicationBundleIdentifier] = representative
                }
            } catch {
                continue
            }
        }

        var bundleIdentifiers = Set(activeProcesses.keys)
        if !showOnlyActive {
            for runningApplication in runningApplications where runningApplication.activationPolicy == .regular {
                guard let bundleIdentifier = runningApplication.bundleIdentifier else { continue }
                let hostApplication = AudioApplicationIdentityRules.hostApplication(
                    processBundleIdentifier: bundleIdentifier,
                    processBundleURL: runningApplication.bundleURL,
                    candidates: applicationIdentityCandidates
                )
                let applicationBundleIdentifier = hostApplication?.bundleIdentifier ?? bundleIdentifier
                guard applicationBundleIdentifier != Bundle.main.bundleIdentifier else { continue }
                bundleIdentifiers.insert(applicationBundleIdentifier)
            }
        }

        return bundleIdentifiers.compactMap { bundleIdentifier in
            let representative = representatives[bundleIdentifier]
                ?? regularApplications[bundleIdentifier]
                ?? fallbackRepresentatives[bundleIdentifier]
            let processObjectIDs = Array(Set(activeProcesses[bundleIdentifier] ?? [])).sorted()
            let isAudioActive = !processObjectIDs.isEmpty

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
                processObjectIDs: processObjectIDs,
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

        if let session = sessions[application.bundleIdentifier],
           session.outputDeviceUID == outputUID,
           session.processObjectIDs == application.processObjectIDs {
            session.setVolume(AudioControlRules.effectiveGain(for: preference))
            return .controlled
        }

        stopControlling(bundleIdentifier: application.bundleIdentifier)
        let session = try RoutedProcessAudioSession.create(
            bundleIdentifier: application.bundleIdentifier,
            processObjectIDs: application.processObjectIDs,
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
    let processObjectIDs: [AudioObjectID]

    private let tap: AudioHardwareTap
    private let aggregateDevice: AudioHardwareAggregateDevice
    private let engine: AVAudioEngine
    private let mixer: AVAudioMixerNode
    private let inputIOProcID: AudioDeviceIOProcID
    private var isStopped = false

    private init(
        outputDeviceUID: String,
        processObjectIDs: [AudioObjectID],
        tap: AudioHardwareTap,
        aggregateDevice: AudioHardwareAggregateDevice,
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode,
        inputIOProcID: AudioDeviceIOProcID
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.processObjectIDs = processObjectIDs
        self.tap = tap
        self.aggregateDevice = aggregateDevice
        self.engine = engine
        self.mixer = mixer
        self.inputIOProcID = inputIOProcID
    }

    static func create(
        bundleIdentifier: String,
        processObjectIDs: [AudioObjectID],
        outputDevice: AudioHardwareDevice,
        volume: Double
    ) throws -> RoutedProcessAudioSession {
        let system = AudioHardwareSystem.shared
        let outputUID = try outputDevice.uid
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.name = "Sonic Route — \(bundleIdentifier)"
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

        let tapFormat: AudioStreamBasicDescription
        do {
            tapFormat = try tap.format
        } catch {
            try? system.destroyAggregateDevice(aggregateDevice)
            try? system.destroyProcessTap(tap)
            throw AudioServiceError.engineStartFailed(error.localizedDescription)
        }
        guard
            tapFormat.mFormatID == kAudioFormatLinearPCM,
            tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            tapFormat.mBitsPerChannel == 32,
            tapFormat.mChannelsPerFrame > 0
        else {
            try? system.destroyAggregateDevice(aggregateDevice)
            try? system.destroyProcessTap(tap)
            throw AudioServiceError.engineStartFailed("O Core Audio retornou um formato de captura não suportado.")
        }

        let channelCount = AVAudioChannelCount(tapFormat.mChannelsPerFrame)
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: tapFormat.mSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            try? system.destroyAggregateDevice(aggregateDevice)
            try? system.destroyProcessTap(tap)
            throw AudioServiceError.engineStartFailed("Não foi possível preparar o formato de áudio capturado.")
        }

        let ringBuffer = ProcessTapRingBuffer(channelCount: Int(channelCount), capacityFrames: 16_384)
        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        let sourceNode = AVAudioSourceNode(format: sourceFormat) { _, _, frameCount, outputData in
            ringBuffer.render(into: outputData, frameCount: Int(frameCount))
        }
        var inputIOProcID: AudioDeviceIOProcID?
        var isInputStarted = false
        do {
            guard let outputAudioUnit = engine.outputNode.audioUnit else {
                throw AudioServiceError.engineUnavailable
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
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: mixer, format: sourceFormat)
            engine.prepare()

            let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
                &inputIOProcID,
                aggregateDevice.id,
                nil
            ) { _, inputData, _, _, _ in
                ringBuffer.append(from: inputData)
            }
            guard ioProcStatus == noErr, let createdIOProcID = inputIOProcID else {
                throw AudioServiceError.engineStartFailed("Erro ao preparar a captura (\(ioProcStatus)).")
            }

            let inputStatus = AudioDeviceStart(aggregateDevice.id, createdIOProcID)
            guard inputStatus == noErr else {
                throw AudioServiceError.engineStartFailed("Erro ao iniciar a captura (\(inputStatus)).")
            }
            isInputStarted = true

            try engine.start()
        } catch {
            engine.stop()
            if let inputIOProcID {
                if isInputStarted {
                    _ = AudioDeviceStop(aggregateDevice.id, inputIOProcID)
                }
                _ = AudioDeviceDestroyIOProcID(aggregateDevice.id, inputIOProcID)
            }
            try? system.destroyAggregateDevice(aggregateDevice)
            try? system.destroyProcessTap(tap)
            if let audioError = error as? AudioServiceError {
                throw audioError
            }
            throw AudioServiceError.engineStartFailed(error.localizedDescription)
        }

        return RoutedProcessAudioSession(
            outputDeviceUID: outputUID,
            processObjectIDs: processObjectIDs,
            tap: tap,
            aggregateDevice: aggregateDevice,
            engine: engine,
            mixer: mixer,
            inputIOProcID: inputIOProcID!
        )
    }

    func setVolume(_ volume: Double) {
        mixer.outputVolume = Float(AudioControlRules.normalizedVolume(volume))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        engine.stop()
        _ = AudioDeviceStop(aggregateDevice.id, inputIOProcID)
        _ = AudioDeviceDestroyIOProcID(aggregateDevice.id, inputIOProcID)
        try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
        try? AudioHardwareSystem.shared.destroyProcessTap(tap)
    }

}

private final class ProcessTapRingBuffer: @unchecked Sendable {
    private let channelCount: Int
    private let capacityFrames: Int
    private let samples: UnsafeMutablePointer<Float>
    private let readFrame = Atomic<Int>(0)
    private let writeFrame = Atomic<Int>(0)

    init(channelCount: Int, capacityFrames: Int) {
        self.channelCount = channelCount
        self.capacityFrames = capacityFrames
        samples = .allocate(capacity: channelCount * capacityFrames)
        samples.initialize(repeating: 0, count: channelCount * capacityFrames)
    }

    deinit {
        samples.deallocate()
    }

    func append(from inputData: UnsafePointer<AudioBufferList>) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard !inputBuffers.isEmpty else { return }

        let framesInBuffer: Int
        if inputBuffers.count == channelCount {
            framesInBuffer = Int(inputBuffers[0].mDataByteSize) / MemoryLayout<Float>.stride
        } else if inputBuffers.count == 1 {
            framesInBuffer = Int(inputBuffers[0].mDataByteSize) / (MemoryLayout<Float>.stride * channelCount)
        } else {
            return
        }

        let currentWriteFrame = writeFrame.load(ordering: .relaxed)
        let currentReadFrame = readFrame.load(ordering: .acquiring)
        let freeFrames = max(0, capacityFrames - (currentWriteFrame - currentReadFrame))
        let framesToWrite = min(framesInBuffer, freeFrames)
        guard framesToWrite > 0 else { return }

        if inputBuffers.count == channelCount {
            for channel in 0 ..< channelCount {
                guard let input = inputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else {
                    return
                }
                for frame in 0 ..< framesToWrite {
                    let ringFrame = (currentWriteFrame + frame) % capacityFrames
                    samples[ringFrame * channelCount + channel] = input[frame]
                }
            }
        } else {
            guard let input = inputBuffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            for frame in 0 ..< framesToWrite {
                let ringFrame = (currentWriteFrame + frame) % capacityFrames
                let inputOffset = frame * channelCount
                let outputOffset = ringFrame * channelCount
                for channel in 0 ..< channelCount {
                    samples[outputOffset + channel] = input[inputOffset + channel]
                }
            }
        }

        writeFrame.store(currentWriteFrame + framesToWrite, ordering: .releasing)
    }

    func render(into outputData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) -> OSStatus {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard outputBuffers.count == channelCount else { return kAudio_ParamError }

        let currentReadFrame = readFrame.load(ordering: .relaxed)
        let currentWriteFrame = writeFrame.load(ordering: .acquiring)
        let framesAvailable = max(0, currentWriteFrame - currentReadFrame)
        let framesToRead = min(frameCount, framesAvailable)

        for channel in 0 ..< channelCount {
            guard let output = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            for frame in 0 ..< frameCount {
                if frame < framesToRead {
                    let ringFrame = (currentReadFrame + frame) % capacityFrames
                    output[frame] = samples[ringFrame * channelCount + channel]
                } else {
                    output[frame] = 0
                }
            }
        }

        readFrame.store(currentReadFrame + framesToRead, ordering: .releasing)
        return noErr
    }
}
