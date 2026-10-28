import Carbon
import Foundation

@MainActor
public protocol GlobalShortcutServicing: AnyObject {
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public final class CarbonGlobalShortcutService: GlobalShortcutServicing {
    public var onShortcutPressed: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try register()
        } else {
            unregister()
        }
    }

    private func register() throws {
        guard hotKey == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<CarbonGlobalShortcutService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    service.onShortcutPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            throw GlobalShortcutError.registrationFailed(handlerStatus)
        }

        let identifier = EventHotKeyID(signature: OSType(0x53524F55), id: 1)
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw GlobalShortcutError.registrationFailed(hotKeyStatus)
        }
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

public enum GlobalShortcutError: LocalizedError {
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Não foi possível registrar o atalho global (\(status))."
        }
    }
}
