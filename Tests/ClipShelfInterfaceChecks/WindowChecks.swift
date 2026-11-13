import AppKit
import Carbon
import ClipShelfCore

@main struct WindowChecks {
    @MainActor static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let suite = "ClipShelfWindowChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            for window in application.windows { window.orderOut(nil) }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let prefs = Preferences(defaults: defaults)
        let controller = try AppController(directory: directory, preferences: prefs)
        checkSecureInputPresentation(controller, application: application)
        try checkHotKeyDispatch()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Before recording", forType: .string)
        let monitor = ClipboardMonitor(repository: controller.repository, preferences: prefs, board: board)
        prefs.completedOnboarding = true
        monitor.capturePending()
        guard controller.repository.entries.isEmpty else { print("FAIL imported existing clipboard"); exit(1) }
        board.clearContents()
        board.setString("macOS clipboard check", forType: .string)
        monitor.capturePending()
        guard controller.repository.entries.count == 1,
              controller.repository.entries.first?.text == "macOS clipboard check",
              monitor.status == "Recording history" else {
            print("FAIL clipboard capture or recording status: \(monitor.status)"); exit(1)
        }
        prefs.paused = true
        board.clearContents()
        board.setString("Paused clipboard", forType: .string)
        monitor.capturePending()
        prefs.paused = false
        monitor.capturePending()
        guard controller.repository.entries.count == 1 else { print("FAIL imported paused clipboard"); exit(1) }
        print("PASS clipboard recording, status, existing and paused content exclusion")
        let image = ClipEntry(payload: ClipPayload(png: Data([1])), imageName: nil, sourceName: "", sourceID: "", at: Date())
        controller.expand(image)
        controller.expand(image)
        let previews = application.windows.filter { $0.title == "Image" }
        guard previews.count == 2 else { print("FAIL: expected two open preview windows, got \(previews.count)"); exit(1) }
        prefs.language = .russian
        guard previews.allSatisfy({ $0.title == "Изображение" }) else {
            print("FAIL: earlier preview title not translated: \(previews.map(\.title))"); exit(1)
        }
        prefs.theme = .light
        guard application.appearance?.name == .aqua else { print("FAIL light appearance"); exit(1) }
        prefs.theme = .dark
        guard application.appearance?.name == .darkAqua else { print("FAIL dark appearance"); exit(1) }
        prefs.theme = .system
        guard application.appearance == nil else { print("FAIL system appearance override remains"); exit(1) }
        guard application.mainMenu?.items.last?.title == "Правка" else { print("FAIL translated native menu"); exit(1) }
        print("PASS multiple preview titles, live appearance mappings, native menus")
    }

    private static func checkSecureInputPresentation(_ controller: AppController, application: NSApplication) {
        controller.isVerificationMode = true
        defer { controller.hide() }
        guard EnableSecureEventInput() == noErr else {
            print("FAIL could not enable Secure Input for the window check"); exit(1)
        }
        controller.show()
        let protectedPanel = application.windows.first { $0 is ShelfPanel && $0.isVisible }
        let stillProtected = IsSecureEventInputEnabled()
        DisableSecureEventInput()
        guard stillProtected, protectedPanel?.styleMask.contains(.nonactivatingPanel) == true else {
            print("FAIL history did not open as a nonactivating panel during Secure Input"); exit(1)
        }
        controller.hide()
        guard !IsSecureEventInputEnabled() else { return }
        controller.show()
        guard let regularPanel = application.windows.first(where: { $0 is ShelfPanel && $0.isVisible }),
              !regularPanel.styleMask.contains(.nonactivatingPanel) else {
            print("FAIL history did not return to its regular panel after Secure Input"); exit(1)
        }
        print("PASS secure and regular history window presentation")
    }

    private static func checkHotKeyDispatch() throws {
        let hotKey = HotKeyService()
        defer { hotKey.stop() }
        var received = 0
        hotKey.onPress = { received += 1 }
        try hotKey.register(Shortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | shiftKey | controlKey), label: "⌃⇧⌘F19"))

        func dispatch(signature: OSType, shortcutID: UInt32) {
            var event: EventRef?
            guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event) == noErr,
                  let event else { print("FAIL could not create hotkey event"); exit(1) }
            defer { ReleaseEvent(event) }
            var id = EventHotKeyID(signature: signature, id: shortcutID)
            guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr else {
                print("FAIL could not set hotkey event ID"); exit(1)
            }
            _ = SendEventToEventTarget(event, GetEventDispatcherTarget())
        }

        dispatch(signature: 0x54455354, shortcutID: 1)
        guard received == 0 else { print("FAIL an unrelated shortcut opened history"); exit(1) }
        dispatch(signature: 0x434C4950, shortcutID: 1)
        guard received == 1 else { print("FAIL the event dispatcher did not invoke the registered shortcut"); exit(1) }
        try hotKey.register(Shortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(cmdKey | shiftKey | controlKey), label: "⌃⇧⌘F18"))
        dispatch(signature: 0x434C4950, shortcutID: 1)
        guard received == 1 else { print("FAIL a replaced shortcut opened history"); exit(1) }
        dispatch(signature: 0x434C4950, shortcutID: 2)
        guard received == 2 else { print("FAIL the replacement shortcut did not open history"); exit(1) }
        print("PASS registered shortcut dispatch and unrelated event rejection")
    }
}
