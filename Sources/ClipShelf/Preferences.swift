import AppKit
import Carbon
import Observation
import ServiceManagement
import ClipShelfCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32 = UInt32(kVK_ANSI_V)
    var modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var label = "⇧⌘V"
}

@Observable final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults
    private let interface: InterfacePreferences
    @ObservationIgnored var interfaceChanged: (() -> Void)?
    var language: AppLanguage {
        get { interface.language }
        set { interface.language = newValue; interfaceChanged?() }
    }
    var theme: AppTheme {
        get { interface.theme }
        set { interface.theme = newValue; interfaceChanged?() }
    }
    var paused: Bool { didSet { defaults.set(paused, forKey: "paused") } }
    var completedOnboarding: Bool { didSet { defaults.set(completedOnboarding, forKey: "onboarded") } }
    var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "limit") } }
    var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "days") } }
    var exclusions: [String] { didSet { defaults.set(exclusions, forKey: "exclusions") } }
    var shortcut: Shortcut { didSet { if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: "shortcut") } } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        interface = InterfacePreferences(defaults: defaults)
        paused = defaults.bool(forKey: "paused")
        completedOnboarding = defaults.bool(forKey: "onboarded")
        historyLimit = max(100, defaults.object(forKey: "limit") as? Int ?? 1000)
        retentionDays = max(1, defaults.object(forKey: "days") as? Int ?? 30)
        exclusions = defaults.stringArray(forKey: "exclusions") ?? []
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? Shortcut()
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

nonisolated private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                            nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else {
        return OSStatus(eventNotHandledErr)
    }
    // Carbon dispatches these hotkey events on the main event loop.
    let address = UInt(bitPattern: context)
    return MainActor.assumeIsolated {
        let service = Unmanaged<HotKeyService>.fromOpaque(UnsafeMutableRawPointer(bitPattern: address)!).takeUnretainedValue()
        return service.handlePress(id)
    }
}

final class HotKeyService {
    var onPress: (() -> Void)?
    private static let signature: OSType = 0x434C4950
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var shortcutID: UInt32 = 0

    func register(_ shortcut: Shortcut) throws {
        let dispatcher = GetEventDispatcherTarget()
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(dispatcher, hotKeyHandler, 1, &type,
                                             Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw ShortcutError.unavailable }
        }
        // Register the replacement before releasing the old shortcut.
        let nextID = shortcutID &+ 1
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: nextID), dispatcher, 0, &replacement)
        guard result == noErr, let replacement else { throw ShortcutError.unavailable }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
        shortcutID = nextID
    }

    fileprivate func handlePress(_ id: EventHotKeyID) -> OSStatus {
        guard reference != nil, id.signature == Self.signature, id.id == shortcutID else {
            return OSStatus(eventNotHandledErr)
        }
        onPress?()
        return noErr
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
enum ShortcutError: LocalizedError {
    case unavailable
    var errorDescription: String? { Localizer()("This shortcut is already in use. Choose another one in Settings.") }
}
