import SwiftUI
import AppKit
import LocalAuthentication
import IOKit.ps

@main
struct AsciiCoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No normal window; AppDelegate creates the full-screen ones when it's time to cover
        Settings { EmptyView() }
    }
}

extension Notification.Name {
    // A macOS permission prompt (e.g. the camera) is about to show (object: true) or has closed (false)
    static let permissionPrompt = Notification.Name("permissionPrompt")
}

// Borderless windows can't receive key presses unless we allow it
final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    private(set) var isCovering = false
    private var screenFrames: [CGRect] = []
    private var unlocking = false
    private var idle: IdleController?
    private var lastPatternChange = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `xd-loop --diagnose` prints what idle mode can see from inside the app sandbox, then exits
        if CommandLine.arguments.contains("--diagnose") {
            print(IdleController.diagnostics())
            exit(0)
        }

        // Start dormant: just the menu bar icon, watching for the Mac to sit idle (IdleMode.swift)
        idle = IdleController(app: self)

        // A monitor was plugged in, unplugged, or rearranged: cover the new layout
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)

        // Step the cover back while a permission prompt is showing, so you can see it
        NotificationCenter.default.addObserver(self, selector: #selector(permissionPrompt(_:)),
                                               name: .permissionPrompt, object: nil)

        // Check every few seconds whether we're on battery, to slow the animations down
        checkPower()
        Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(checkPower),
                             userInfo: nil, repeats: true)

        // Auto-cycle checks once a second whether it's time for a new pattern
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(autoCycle),
                             userInfo: nil, repeats: true)

        // While covering, every key press comes here first and is swallowed so nothing else reacts.
        // While dormant, keys pass straight through
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isCovering else { return event }
            self.handleKey(event)
            return nil
        }
    }

    // Opening xd-loop again while it's already running (Spotlight, Finder, Launchpad) covers right away
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        startCover()
        return false
    }

    func startCover() {
        guard !isCovering else { return }
        isCovering = true
        lastPatternChange = Date()
        NSApp.unhide(nil)   // endCover() hid the app; hidden apps can't show windows
        buildWindows(fadeIn: true)
        NSCursor.hide()
        // We're a background app asking to come to the front. ignoringOtherApps is deprecated,
        // but it's still the only way to take the keyboard without a click, and the unlock keys need it
        NSApp.activate(ignoringOtherApps: true)
        idle?.refreshIcon()
        if AppState.shared.audioStrength > 0 { AudioMeter.shared.start() }
    }

    // Back to dormant: windows gone, keyboard handed back to whatever you were using
    func endCover() {
        guard isCovering else { return }
        isCovering = false
        AppState.shared.wheelOpen = false
        closeWindows()
        AudioMeter.shared.stop()
        NSCursor.unhide()
        NSApp.hide(nil)
        idle?.didUncover()
    }

    // Taking the content out first matters: it tells each AsciiView it has left its window,
    // which stops its display link. Otherwise the link keeps the view alive, drawing in the background
    private func closeWindows() {
        for w in windows {
            w.contentView = nil
            w.close()
        }
        windows = []
    }

    // One borderless window per display, above everything else, on every Space
    private func buildWindows(fadeIn: Bool) {
        closeWindows()
        windows = NSScreen.screens.map { screen in
            let w = CoverWindow(contentRect: screen.frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false   // we keep our own reference, so close() mustn't free it too
            w.level = unlocking ? .normal : .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.backgroundColor = .black
            w.contentView = NSHostingView(rootView: ContentView(screenFrame: screen.frame))
            if fadeIn { w.alphaValue = 0 }
            w.makeKeyAndOrderFront(nil)
            return w
        }
        windows.first?.makeKeyAndOrderFront(nil)
        screenFrames = NSScreen.screens.map(\.frame)

        if fadeIn {
            let fading = windows
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1
                for w in fading { w.animator().alphaValue = 1 }
            }
        }
    }

    @objc private func permissionPrompt(_ note: Notification) {
        let showing = note.object as? Bool ?? false
        for w in windows { w.level = showing ? .normal : .screenSaver }
        if !showing && isCovering {
            windows.first?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func screensChanged() {
        // This also fires for small things, so only rebuild when the screens really changed
        guard isCovering, NSScreen.screens.map(\.frame) != screenFrames else { return }
        buildWindows(fadeIn: false)
    }

    // A random new pattern every few seconds while covering, if auto-cycle is on.
    // Pressing ` yourself restarts the countdown
    @objc private func autoCycle() {
        let state = AppState.shared
        guard isCovering, state.autoCycle > 0, !state.wheelOpen,
              Date().timeIntervalSince(lastPatternChange) >= state.autoCycle else { return }
        lastPatternChange = Date()
        state.randomPattern()
    }

    @objc private func checkPower() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        let saving = source == kIOPSBatteryPowerValue || ProcessInfo.processInfo.isLowPowerModeEnabled
        if AppState.shared.onBattery != saving { AppState.shared.onBattery = saving }
    }

    // ` next pattern, Shift + ` previous, Tab flips ASCII/shaders, = colour wheel (shaders only),
    // Esc asks for Touch ID, Control + Shift + right Option + Return uncovers. Every other key does nothing
    private func handleKey(_ event: NSEvent) {
        if Self.isSecretQuit(keyCode: event.keyCode, flags: event.modifierFlags) {
            endCover()
            return
        }
        let state = AppState.shared
        switch event.keyCode {
        case 50:   // the ` key, just below Esc; with Shift it goes backwards
            let step = event.modifierFlags.contains(.shift) ? -1 : 1
            if state.shaderMode { state.stepShader(step) } else { state.stepAscii(step) }
            lastPatternChange = Date()
        case 48:   // Tab
            state.toggleMode()
        case 24:   // =
            if state.shaderMode { state.wheelOpen.toggle() }
        case 53:   // Esc
            unlockWithTouchID()
        default:
            break
        }
    }

    // Control + Shift + right Option + Return (or the Enter key on a number pad).
    // Shift is there because Rectangle uses Control + Option + Return for Maximize and grabs it first.
    // macOS marks which Option key is held with an extra bit: 0x20 for left, 0x40 for right
    static func isSecretQuit(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let rightOption: UInt = 0x40
        let isReturn = keyCode == 36 || keyCode == 76
        return isReturn && flags.contains([.control, .shift]) && flags.rawValue & rightOption != 0
    }

    // Shows the Touch ID prompt; a matching fingerprint uncovers, cancelling puts the cover back
    private func unlockWithTouchID() {
        guard !unlocking else { return }
        let context = LAContext()
        context.localizedFallbackTitle = ""   // no "Use Password" button: fingerprint only
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        unlocking = true

        // Drop below the system's Touch ID prompt while it's showing
        for w in windows { w.level = .normal }
        Task {
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                        localizedReason: "unlock the screen")) ?? false
            unlocking = false
            if ok {
                endCover()
            } else {
                for w in windows { w.level = .screenSaver }
                windows.first?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
