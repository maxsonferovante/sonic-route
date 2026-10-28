import AppKit
import CoreAudio
import Foundation

public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let uid: String
    public let name: String
    public let kind: AudioOutputDeviceKind

    public var id: String { uid }
    public var isExternal: Bool { kind != .builtIn }
    public var symbolName: String { kind.symbolName }

    public init(uid: String, name: String, kind: AudioOutputDeviceKind = .other) {
        self.uid = uid
        self.name = name
        self.kind = kind
    }
}

public enum AudioOutputDeviceKind: Equatable, Sendable {
    case builtIn
    case bluetooth
    case hdmi
    case usb
    case airPlay
    case other

    public var symbolName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .hdmi: "display"
        case .usb: "hifispeaker.fill"
        case .airPlay: "airplayaudio"
        case .other: "hifispeaker"
        }
    }
}

public struct RunningAudioApplication: Identifiable {
    public let bundleIdentifier: String
    public let displayName: String
    public let processObjectIDs: [AudioObjectID]
    public let isAudioActive: Bool
    public let icon: NSImage?

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        displayName: String,
        processObjectIDs: [AudioObjectID] = [],
        isAudioActive: Bool,
        icon: NSImage? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.processObjectIDs = processObjectIDs
        self.isAudioActive = isAudioActive
        self.icon = icon
    }
}

public struct ApplicationAudioPreference: Codable, Equatable, Sendable {
    public var volume: Double
    public var isMuted: Bool
    public var outputDeviceUID: String?

    public static let `default` = ApplicationAudioPreference(
        volume: 1,
        isMuted: false,
        outputDeviceUID: nil
    )

    public init(volume: Double, isMuted: Bool, outputDeviceUID: String?) {
        self.volume = volume
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
    }
}

public struct ApplicationAudioRowState: Identifiable {
    public let application: RunningAudioApplication
    public var preference: ApplicationAudioPreference
    public var isBeingControlled: Bool
    public var controlError: String?

    public var id: String { application.bundleIdentifier }

    public init(
        application: RunningAudioApplication,
        preference: ApplicationAudioPreference,
        isBeingControlled: Bool,
        controlError: String?
    ) {
        self.application = application
        self.preference = preference
        self.isBeingControlled = isBeingControlled
        self.controlError = controlError
    }
}

public enum AudioControlStatus: Equatable {
    case passThrough
    case controlled
    case failed(String)
}

public enum AudioServiceError: LocalizedError {
    case noOutputDevice
    case deviceUnavailable(String)
    case tapCreationFailed(String)
    case aggregateDeviceCreationFailed
    case engineUnavailable
    case engineStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "Nenhuma saída de áudio está disponível."
        case .deviceUnavailable(let name):
            return "A saída “\(name)” não está disponível. O áudio seguirá pela saída padrão do macOS."
        case .tapCreationFailed(let detail):
            return "O macOS não permitiu capturar este app. Verifique a permissão de gravação de áudio do sistema. (\(detail))"
        case .aggregateDeviceCreationFailed:
            return "Não foi possível preparar a entrada de áudio capturada."
        case .engineUnavailable:
            return "Não foi possível preparar o mecanismo de áudio."
        case .engineStartFailed(let detail):
            return "Não foi possível iniciar o encaminhamento de áudio. (\(detail))"
        }
    }
}
