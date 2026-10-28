import CoreAudio
import Foundation

@MainActor
public final class CoreAudioDeviceService: AudioDeviceServicing {
    public init() {}

    public func outputDevices() throws -> [AudioOutputDevice] {
        let devices = try AudioHardwareSystem.shared.devices
        return devices.compactMap { device in
            do {
                guard try device.canBeDefaultOutputDevice else { return nil }
                let kind = (try? device.transportType).map(Self.deviceKind(for:)) ?? .other
                return AudioOutputDevice(uid: try device.uid, name: try device.name, kind: kind)
            } catch {
                return nil
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func defaultOutputDeviceUID() throws -> String? {
        try AudioHardwareSystem.shared.defaultOutputDevice?.uid
    }

    private static func deviceKind(for transportType: UInt32) -> AudioOutputDeviceKind {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            .hdmi
        case kAudioDeviceTransportTypeUSB:
            .usb
        case kAudioDeviceTransportTypeAirPlay:
            .airPlay
        default:
            .other
        }
    }
}
