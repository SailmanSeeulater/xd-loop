import AppKit
import IOKit.pwr_mgt
import ServiceManagement

// Dormant mode: the menu bar icon, plus a timer that covers the screen once the Mac has sat idle
final class IdleController: NSObject, NSMenuDelegate {
    private weak var app: AppDelegate?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let saved = UserDefaults.standard

    // Settings, remembered between launches
    private var idleMinutes: Int {
        get { saved.object(forKey: "idleMinutes") as? Int ?? 5 }
        set { saved.set(newValue, forKey: "idleMinutes") }
    }
    private var pausedUntil: Date? {
        get { saved.object(forKey: "pausedUntil") as? Date }
        set { saved.set(newValue, forKey: "pausedUntil") }
    }
    private var skipVideo: Bool {
        get { saved.object(forKey: "skipVideo") as? Bool ?? true }
        set { saved.set(newValue, forKey: "skipVideo") }
    }
    private var skipFullScreen: Bool {
        get { saved.object(forKey: "skipFullScreen") as? Bool ?? true }
        set { saved.set(newValue, forKey: "skipFullScreen") }
    }

    // What macOS has told us
    private var screenLocked = false
    private var screenSaverRunning = false
    private var sessionActive = true
    private var lastUncovered = Date()
    private var displaySleptFirst = false   // the display turned off before we got to cover it

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        // Lock screen and screen saver come in as system-wide notifications
        let system = DistributedNotificationCenter.default()
        system.addObserver(self, selector: #selector(macLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        system.addObserver(self, selector: #selector(macUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        system.addObserver(self, selector: #selector(screenSaverStarted), name: .init("com.apple.screensaver.didstart"), object: nil)
        system.addObserver(self, selector: #selector(screenSaverStopped), name: .init("com.apple.screensaver.didstop"), object: nil)

        // Display sleep, Mac sleep (lid closed) and switching to another user
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displaySlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaySlept), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayWoke), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionLeft), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionReturned), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        // Check every 5 seconds; it's a handful of cheap questions to macOS
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(check), userInfo: nil, repeats: true)
    }

    // MARK: Deciding when to cover

    @objc private func check() {
        refreshIcon()
        guard let app, !app.isCovering else { return }
        if let until = pausedUntil {
            if until > Date() { return }
            pausedUntil = nil
        }
        guard blockReason() == nil, effectiveIdle() >= Double(idleMinutes * 60) else { return }
        displaySleptFirst = false
        app.startCover()
    }

    // Why we're holding off right now, or nil if nothing is in the way
    private func blockReason(ignoringDisplay: Bool = false) -> String? {
        if screenLocked { return "Mac is locked" }
        if screenSaverRunning { return "screen saver is on" }
        if !sessionActive { return "another user is logged in" }
        if !ignoringDisplay && AppState.shared.displayAsleep { return "display is asleep" }
        if skipVideo && Self.somethingKeepsDisplayAwake() == true { return "a video or call is playing" }
        if skipFullScreen && Self.frontAppIsFullScreen() { return "a full-screen app is open" }
        return nil
    }

    // Seconds since your last input, counting an unlock (or launching xd-loop) as activity
    private func effectiveIdle() -> Double {
        min(Self.secondsIdle(), Date().timeIntervalSince(lastUncovered))
    }

    func didUncover() {
        lastUncovered = Date()
        refreshIcon()
    }

    // MARK: What macOS tells us

    @objc private func macLocked() { screenLocked = true }

    // You've already typed your Mac password or used Touch ID, so don't make you unlock twice
    @objc private func macUnlocked() {
        screenLocked = false
        app?.endCover()
    }

    @objc private func screenSaverStarted() { screenSaverRunning = true }
    @objc private func screenSaverStopped() { screenSaverRunning = false }

    @objc private func displaySlept() {
        // If the display turned itself off while you were idle but before we covered it,
        // macOS's "turn display off" time is shorter than our idle time
        if let app, !app.isCovering, pausedUntil == nil, blockReason(ignoringDisplay: true) == nil {
            let idle = effectiveIdle()
            if idle >= 55 && idle < Double(idleMinutes * 60) { displaySleptFirst = true }
        }
        AppState.shared.displayAsleep = true
    }

    @objc private func displayWoke() { AppState.shared.displayAsleep = false }
    @objc private func sessionLeft() { sessionActive = false }
    @objc private func sessionReturned() { sessionActive = true }

    // MARK: Asking macOS

    // Seconds since the last key press, click, scroll or mouse move anywhere on the Mac
    static func secondsIdle() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    // True when some app has asked macOS to keep the display on (video players, calls, slideshows).
    // nil if macOS wouldn't say
    static func somethingKeepsDisplayAwake() -> Bool? {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let counts = status?.takeRetainedValue() as? [String: Int] else { return nil }
        return (counts["PreventUserIdleDisplaySleep"] ?? 0) > 0 || (counts["NoDisplaySleepAssertion"] ?? 0) > 0
    }

    // True when the frontmost app has a window exactly the size of a screen (full-screen apps,
    // slideshows, games). Normal maximised windows leave room for the menu bar, so they don't count
    static func frontAppIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        for window in windowList() {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            if screenSizes.contains(rect.size) { return true }
        }
        return false
    }

    private static func windowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    // What `xd-loop --diagnose` prints
    static func diagnostics() -> String {
        let awake = somethingKeepsDisplayAwake().map { $0 ? "yes" : "no" } ?? "UNAVAILABLE"
        return """
        seconds idle: \(Int(secondsIdle()))
        video/call keeping display awake: \(awake)
        frontmost app full-screen: \(frontAppIsFullScreen())
        on-screen windows visible: \(windowList().count)
        start at login status: \(SMAppService.mainApp.status.rawValue)
        """
    }

    // MARK: Menu bar

    func refreshIcon() {
        let paused = pausedUntil.map { $0 > Date() } ?? false
        let image = NSImage(systemSymbolName: paused ? "pause.circle" : "apple.terminal", accessibilityDescription: "xd-loop")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // Rebuilt every time the menu opens, so it always shows the current state
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info(statusText()))
        if displaySleptFirst {
            menu.addItem(info("⚠︎ Your display turned off before xd-loop could cover it."))
            menu.addItem(info("    Lower the idle time, or raise “Turn display off” in System Settings."))
        }
        menu.addItem(.separator())
        menu.addItem(action("Cover now", #selector(coverNow)))
        menu.addItem(.separator())

        let idleMenu = NSMenu()
        for minutes in [1, 2, 5, 10, 15, 30] {
            let item = action("\(minutes) min", #selector(setIdleTime(_:)), tag: minutes)
            item.state = minutes == idleMinutes ? .on : .off
            idleMenu.addItem(item)
        }
        menu.addItem(submenu("Idle time", idleMenu))

        let pauseMenu = NSMenu()
        pauseMenu.addItem(action("30 minutes", #selector(pause(_:)), tag: 30))
        pauseMenu.addItem(action("1 hour", #selector(pause(_:)), tag: 60))
        pauseMenu.addItem(action("Until tomorrow", #selector(pause(_:)), tag: -1))
        if pausedUntil != nil {
            pauseMenu.addItem(.separator())
            pauseMenu.addItem(action("Resume", #selector(resume)))
        }
        menu.addItem(submenu("Pause", pauseMenu))
        menu.addItem(.separator())

        menu.addItem(toggle("Skip during video and calls", skipVideo, #selector(toggleSkipVideo)))
        menu.addItem(toggle("Skip during full-screen apps", skipFullScreen, #selector(toggleSkipFullScreen)))
        menu.addItem(.separator())
        menu.addItem(toggle("Start at login", SMAppService.mainApp.status == .enabled, #selector(toggleStartAtLogin)))
        menu.addItem(.separator())
        menu.addItem(action("Quit xd-loop", #selector(quit), key: "q"))
    }

    private func statusText() -> String {
        if app?.isCovering == true { return "● Covering the screen" }
        if let until = pausedUntil, until > Date() {
            let tomorrow = !Calendar.current.isDateInToday(until)
            return "Paused until " + (tomorrow ? "tomorrow" : until.formatted(date: .omitted, time: .shortened))
        }
        if let reason = blockReason() { return "Waiting: \(reason)" }
        return "Covers after \(idleMinutes) min idle"
    }

    @objc private func coverNow() { app?.startCover() }

    @objc private func setIdleTime(_ sender: NSMenuItem) {
        idleMinutes = sender.tag
        displaySleptFirst = false
    }

    @objc private func pause(_ sender: NSMenuItem) {
        if sender.tag < 0 {
            pausedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        } else {
            pausedUntil = Date().addingTimeInterval(Double(sender.tag) * 60)
        }
        refreshIcon()
    }

    @objc private func resume() {
        pausedUntil = nil
        lastUncovered = Date()   // start the idle count fresh
        refreshIcon()
    }

    @objc private func toggleSkipVideo() { skipVideo.toggle() }
    @objc private func toggleSkipFullScreen() { skipFullScreen.toggle() }

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                // macOS may want you to switch it on in Login Items first
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Start at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // Small builders for menu items
    private func info(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func action(_ title: String, _ selector: Selector, tag: Int = 0, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ selector: Selector) -> NSMenuItem {
        let item = action(title, selector)
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
