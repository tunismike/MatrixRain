import Cocoa
import WebKit
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import Darwin

// ============================================================================
// Matrix Rain — Native Multi-Display Screensaver & Idle Daemon
//
// Modes:
//   --daemon       Background LaunchAgent daemon (in-process IOKit idle,
//                  sleep/lock/lid awareness, live config reload, child mgmt)
//   --screensaver  Fullscreen WKWebView on every display, smooth fade,
//                  full local + remote (HIDIdleTime) dismissal
//   --wallpaper    Desktop-level live wallpaper mode
//   --status       Print current config and system idle/display diagnostics
// ============================================================================

// MARK: - Logging

private let logDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
}()

func logLine(_ message: String) {
    let ts = logDateFormatter.string(from: Date())
    print("[\(ts)] \(message)")
    fflush(stdout)
}

// MARK: - System State Queries (In-Process, Zero Subprocesses)

enum SystemState {
    /// Returns macOS HID idle time in seconds directly from IOHIDSystem.
    /// Synthetic/remote input (e.g. RustDesk) resets this kernel counter.
    static func hidIdleSeconds() -> Double {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )
        guard service != 0 else { return 0.0 }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return 0.0
        }

        if let num = prop as? NSNumber {
            return num.doubleValue / 1_000_000_000.0
        }
        if let data = prop as? Data, data.count >= MemoryLayout<UInt64>.size {
            let nanos = data.withUnsafeBytes { $0.load(as: UInt64.self) }
            return Double(nanos) / 1_000_000_000.0
        }
        return 0.0
    }

    /// True if the built-in MacBook clamshell lid is currently closed.
    static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return false
        }

        return (prop as? Bool) ?? false
    }

    /// Returns online display IDs.
    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return Array(displays.prefix(Int(count)))
    }

    /// True if there are no awake, viewable displays (all asleep, none online,
    /// or lid closed with only the built-in panel online).
    static func areAllDisplaysDarkOrAsleep() -> Bool {
        let displays = onlineDisplays()
        if displays.isEmpty { return true }

        let lidClosed = isLidClosed()
        var anyAwakeVisible = false
        for id in displays {
            if CGDisplayIsAsleep(id) != 0 { continue }
            if lidClosed && CGDisplayIsBuiltin(id) != 0 { continue }
            anyAwakeVisible = true
            break
        }
        return !anyAwakeVisible
    }

    /// True if the macOS GUI session is locked or switched off console.
    static func isSessionLockedOrInactive() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked {
            return true
        }
        if let onConsole = dict["kCGSSessionOnConsoleKey"] as? Bool, !onConsole {
            return true
        }
        return false
    }

    /// True when running on battery power.
    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        guard let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
            return false
        }
        return sourceType == kIOPSBatteryPowerValue
    }

    /// Returns names of other processes currently holding display-sleep assertions.
    static func activeDisplaySleepAssertionProcesses(excludingPID: pid_t = getpid()) -> [String] {
        var unmanagedDict: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&unmanagedDict)
        guard status == kIOReturnSuccess,
              let byProcess = unmanagedDict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return []
        }

        let displayTypes: Set<String> = [
            "PreventUserIdleDisplaySleep",
            "NoDisplaySleepAssertion"
        ]

        var names: [String] = []
        for (pidNum, assertions) in byProcess {
            let pid = pid_t(pidNum.int32Value)
            if pid == excludingPID { continue }

            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String,
                      displayTypes.contains(type) else {
                    continue
                }
                let procName = (assertion["Process Name"] as? String) ?? "pid:\(pid)"
                names.append(procName)
                break
            }
        }
        return names
    }

    static func hasBlockingDisplaySleepAssertion(
        ignoring: Set<String>,
        excludingPIDs: Set<pid_t>
    ) -> (blocked: Bool, blockers: [String]) {
        var unmanagedDict: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&unmanagedDict)
        guard status == kIOReturnSuccess,
              let byProcess = unmanagedDict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            return (false, [])
        }

        let displayTypes: Set<String> = [
            "PreventUserIdleDisplaySleep",
            "NoDisplaySleepAssertion"
        ]

        var blockers: [String] = []
        for (pidNum, assertions) in byProcess {
            let pid = pid_t(pidNum.int32Value)
            if excludingPIDs.contains(pid) { continue }

            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String,
                      displayTypes.contains(type) else {
                    continue
                }
                let procName = (assertion["Process Name"] as? String) ?? "pid:\(pid)"
                let normalized = procName.lowercased()
                if normalized == "matrixscreensaver" || ignoring.contains(normalized) {
                    continue
                }
                blockers.append(procName)
                break
            }
        }
        return (!blockers.isEmpty, blockers)
    }
}

// MARK: - Config (INI)

struct ScreensaverConfig {
    var enabled: Bool = true
    var idleTimeSeconds: Double = 180.0
    var htmlURL: URL
    var maxDurationSeconds: Double = 0.0
    var allowDisplaySleepOnBattery: Bool = true
    var respectDisplaySleepAssertions: Bool = false
    var ignoreAssertionProcesses: Set<String> = ["antigravity", "rustdesk"]
    var fadeInSeconds: Double = 0.35
    var fadeOutSeconds: Double = 0.15

    static func load(baseDir: URL, configPath: URL? = nil, htmlOverride: URL? = nil) -> ScreensaverConfig {
        let cfgURL = configPath ?? baseDir.appendingPathComponent("config.ini")
        let cfgDir = cfgURL.deletingLastPathComponent()
        let defaultHTML = cfgDir.appendingPathComponent("index.html")
        var cfg = ScreensaverConfig(htmlURL: htmlOverride ?? defaultHTML)

        guard let content = try? String(contentsOf: cfgURL, encoding: .utf8) else {
            return cfg
        }

        var currentSection = ""
        var rawHtmlPath = ""

        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                continue
            }
            guard currentSection == "screensaver",
                  let eqIdx = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = trimmed[..<eqIdx]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            var value = trimmed[trimmed.index(after: eqIdx)...]
                .trimmingCharacters(in: .whitespaces)

            // Strip inline comments preceded by whitespace
            if let hashRange = value.range(of: " #") {
                value = String(value[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            switch key {
            case "enabled":
                cfg.enabled = parseBool(value, default: cfg.enabled)
            case "idletimeseconds":
                if let v = Double(value), v > 0 { cfg.idleTimeSeconds = v }
            case "htmlpath":
                rawHtmlPath = value
            case "maxdurationseconds":
                if let v = Double(value), v >= 0 { cfg.maxDurationSeconds = v }
            case "allowdisplaysleeponbattery":
                cfg.allowDisplaySleepOnBattery = parseBool(value, default: cfg.allowDisplaySleepOnBattery)
            case "respectdisplaysleepassertions":
                cfg.respectDisplaySleepAssertions = parseBool(value, default: cfg.respectDisplaySleepAssertions)
            case "ignoreassertionprocesses":
                let items = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                cfg.ignoreAssertionProcesses = Set(items)
            case "fadeinseconds":
                if let v = Double(value), v >= 0 { cfg.fadeInSeconds = v }
            case "fadeoutseconds":
                if let v = Double(value), v >= 0 { cfg.fadeOutSeconds = v }
            default:
                break
            }
        }

        if let override = htmlOverride {
            cfg.htmlURL = override
        } else if !rawHtmlPath.isEmpty {
            let candidate: URL
            if rawHtmlPath.hasPrefix("/") {
                candidate = URL(fileURLWithPath: rawHtmlPath)
            } else {
                candidate = cfgDir.appendingPathComponent(rawHtmlPath)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                cfg.htmlURL = candidate
            } else {
                logLine("HtmlPath not found, falling back to index.html: \(candidate.path)")
                cfg.htmlURL = defaultHTML
            }
        }

        return cfg
    }

    private static func parseBool(_ s: String, default fallback: Bool) -> Bool {
        switch s.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return fallback
        }
    }
}

// MARK: - Signal Handling

private var sigtermSource: DispatchSourceSignal?
private var sigintSource: DispatchSourceSignal?

func installSignalHandlers(_ handler: @escaping () -> Void) {
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)

    let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    term.setEventHandler(handler: handler)
    term.resume()
    sigtermSource = term

    let intr = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    intr.setEventHandler(handler: handler)
    intr.resume()
    sigintSource = intr
}

// MARK: - Daemon Mode

class DaemonDelegate: NSObject, NSApplicationDelegate {
    let executablePath: String
    let baseDir: URL
    let configPath: URL?

    var pollTimer: Timer?
    var childProcess: Process?
    var isLockedByNotification = false
    var screensAsleepByNotification = false
    var wasDarkOrLocked = false
    var lastWakeOrUnlockTime = Date.distantPast
    var suppressedUntilActivity = false
    var lastLogState = ""

    init(executablePath: String, baseDir: URL, configPath: URL?) {
        self.executablePath = executablePath
        self.baseDir = baseDir
        self.configPath = configPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)

        // Seed initial lock/sleep state
        isLockedByNotification = SystemState.isSessionLockedOrInactive()
        screensAsleepByNotification = SystemState.areAllDisplaysDarkOrAsleep()

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleSessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleSessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        installSignalHandlers { [weak self] in
            self?.shutdown()
        }

        let cfg = ScreensaverConfig.load(baseDir: baseDir, configPath: configPath)
        logLine("MatrixScreensaver daemon started (idle=\(Int(cfg.idleTimeSeconds))s, html=\(cfg.htmlURL.path), enabled=\(cfg.enabled))")

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        pollTimer?.tolerance = 0.25
        tick()
    }

    @objc func handleScreensDidSleep() {
        screensAsleepByNotification = true
        stopChild(reason: "displays went to sleep", suppressUntilActivity: true)
    }

    @objc func handleScreensDidWake() {
        screensAsleepByNotification = false
        lastWakeOrUnlockTime = Date()
        suppressedUntilActivity = false
    }

    @objc func handleSystemWillSleep() {
        screensAsleepByNotification = true
        stopChild(reason: "system going to sleep", suppressUntilActivity: true)
    }

    @objc func handleSessionResigned() {
        isLockedByNotification = true
        stopChild(reason: "session resigned active", suppressUntilActivity: true)
    }

    @objc func handleSessionBecameActive() {
        isLockedByNotification = false
        lastWakeOrUnlockTime = Date()
        suppressedUntilActivity = false
    }

    @objc func handleScreenLocked() {
        isLockedByNotification = true
        stopChild(reason: "screen locked", suppressUntilActivity: true)
    }

    @objc func handleScreenUnlocked() {
        isLockedByNotification = false
        lastWakeOrUnlockTime = Date()
        suppressedUntilActivity = false
    }

    func tick() {
        let cfg = ScreensaverConfig.load(baseDir: baseDir, configPath: configPath)
        let running = isChildRunning()
        let rawIdle = SystemState.hidIdleSeconds()

        if !cfg.enabled {
            if running {
                stopChild(reason: "disabled in config.ini", suppressUntilActivity: false)
            }
            return
        }

        let locked = isLockedByNotification || SystemState.isSessionLockedOrInactive()
        let dark = screensAsleepByNotification || SystemState.areAllDisplaysDarkOrAsleep()

        if locked || dark {
            wasDarkOrLocked = true
            if running {
                stopChild(
                    reason: locked ? "screen locked" : "displays dark/asleep",
                    suppressUntilActivity: true
                )
            }
            return
        }

        if wasDarkOrLocked {
            wasDarkOrLocked = false
            lastWakeOrUnlockTime = Date()
            suppressedUntilActivity = false
        }

        // Clear post-sleep suppression once user activity resets idle below threshold
        if suppressedUntilActivity {
            if rawIdle < cfg.idleTimeSeconds {
                suppressedUntilActivity = false
            } else {
                return
            }
        }

        // Effective idle resets after a wake or unlock so opening the lid never
        // immediately pops up the screensaver before IdleTimeSeconds elapses.
        let sinceWake = Date().timeIntervalSince(lastWakeOrUnlockTime)
        let effectiveIdle = min(rawIdle, sinceWake)

        if effectiveIdle >= cfg.idleTimeSeconds {
            if !running {
                if cfg.respectDisplaySleepAssertions {
                    let result = SystemState.hasBlockingDisplaySleepAssertion(
                        ignoring: cfg.ignoreAssertionProcesses,
                        excludingPIDs: [getpid()]
                    )
                    if result.blocked {
                        let key = "blocked:\(result.blockers.sorted().joined(separator: ","))"
                        if lastLogState != key {
                            logLine("Idle (\(String(format: "%.1f", effectiveIdle))s) but display-sleep assertion held by: \(result.blockers.joined(separator: ", "))")
                            lastLogState = key
                        }
                        return
                    }
                }
                lastLogState = ""
                launchChild(cfg: cfg, idle: effectiveIdle)
            }
        } else if running {
            // Activity resumed (covers remote/synthetic input as backup to child's own 250ms poll)
            stopChild(reason: String(format: "activity detected (%.1fs idle)", rawIdle), suppressUntilActivity: false)
        }
    }

    func isChildRunning() -> Bool {
        guard let proc = childProcess else { return false }
        if proc.isRunning { return true }
        childProcess = nil
        return false
    }

    func launchChild(cfg: ScreensaverConfig, idle: Double) {
        guard FileManager.default.fileExists(atPath: cfg.htmlURL.path) else {
            logLine("Cannot launch screensaver: HTML not found at \(cfg.htmlURL.path)")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        var args = ["--screensaver", "--html", cfg.htmlURL.path]
        if let cfgPath = configPath {
            args.append(contentsOf: ["--config", cfgPath.path])
        }
        proc.arguments = args
        proc.currentDirectoryURL = baseDir
        proc.standardOutput = FileHandle.standardOutput
        proc.standardError = FileHandle.standardError

        proc.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.childProcess === finished {
                    self.childProcess = nil
                }
            }
        }

        do {
            logLine("System idle (\(String(format: "%.1f", idle))s >= \(Int(cfg.idleTimeSeconds))s). Launching MatrixScreensaver...")
            try proc.run()
            childProcess = proc
        } catch {
            logLine("Failed to launch MatrixScreensaver child: \(error)")
        }
    }

    func stopChild(reason: String, suppressUntilActivity: Bool) {
        if suppressUntilActivity {
            suppressedUntilActivity = true
        }
        guard let proc = childProcess, proc.isRunning else {
            childProcess = nil
            return
        }
        logLine("Dismissing screensaver (\(reason))...")
        proc.terminate()
    }

    func shutdown() {
        logLine("Daemon shutting down.")
        pollTimer?.invalidate()
        pollTimer = nil
        if let proc = childProcess, proc.isRunning {
            proc.terminate()
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Screensaver / Wallpaper Mode

class MatrixWindow: NSWindow {
    var onUserInput: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        onUserInput?()
    }

    override func flagsChanged(with event: NSEvent) {
        if !event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onUserInput?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onUserInput?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onUserInput?()
    }

    override func otherMouseDown(with event: NSEvent) {
        onUserInput?()
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > 1 || abs(event.scrollingDeltaY) > 1 {
            onUserInput?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if abs(event.deltaX) > 5 || abs(event.deltaY) > 5 {
            onUserInput?()
        }
    }

    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class ScreensaverAppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var windows: [MatrixWindow] = []
    var webViews: [WKWebView] = []

    // Track display layout to rebuild cleanly on plug/unplug without shrinking glyphs
    var screenSignature: String = ""
    var rebuildWork: DispatchWorkItem?

    // Power assertions
    var displaySleepAssertionID: IOPMAssertionID = IOPMAssertionID(0)
    var hasDisplayAssertion = false
    var processActivity: NSObjectProtocol?
    var maxDurationTimer: Timer?
    var batteryCheckTimer: Timer?

    // Input monitors & remote-input (HIDIdleTime) watcher
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    var remoteIdleTimer: Timer?
    var initialMouseLocation: NSPoint = .zero
    var maxObservedIdle: Double = 0.0
    var isExiting = false

    let isScreensaverMode: Bool
    let isWallpaperMode: Bool
    let config: ScreensaverConfig

    init(isScreensaver: Bool, isWallpaper: Bool, config: ScreensaverConfig) {
        self.isScreensaverMode = isScreensaver
        self.isWallpaperMode = isWallpaper
        self.config = config
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSScreen.screens.isEmpty {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(isScreensaverMode ? .accessory : .prohibited)

        initialMouseLocation = NSEvent.mouseLocation
        maxObservedIdle = SystemState.hidIdleSeconds()

        buildWindows(animated: isScreensaverMode && config.fadeInSeconds > 0)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if isScreensaverMode {
            installInputMonitors()
            installRemoteIdleWatcher()
            acquirePowerAssertionsIfAllowed()
            configurePowerLimits()
        } else if isWallpaperMode {
            // Wallpaper mode does not hold display-sleep assertions
        }

        installSignalHandlers { [weak self] in
            self?.exitAll(animated: true)
        }
    }

    func currentScreenSignature() -> String {
        return NSScreen.screens.map { s in
            let f = s.frame
            return "\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))@\(s.backingScaleFactor)"
        }.joined(separator: "|")
    }

    func buildWindows(animated: Bool) {
        let initialAlpha: CGFloat = animated ? 0.0 : 1.0
        for (index, screen) in NSScreen.screens.enumerated() {
            createWindow(on: screen, displayIndex: index, initialAlpha: initialAlpha)
        }
        screenSignature = currentScreenSignature()

        if isScreensaverMode {
            NSCursor.hide()
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = config.fadeInSeconds
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    for window in windows {
                        window.animator().alphaValue = 1.0
                    }
                }
            }
        }
    }

    func tearDownWindows() {
        for webView in webViews {
            webView.stopLoading()
            webView.removeFromSuperview()
        }
        webViews.removeAll()
        for window in windows {
            window.onUserInput = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    // macOS fires this several times through a single plug or unplug, AND also
    // for non-layout events (XDR brightness/headroom shifts, True Tone, color
    // profiles, menu bar/space changes). Only blank the WebViews when the actual
    // display geometry/scale signature has changed, so spurious notifications
    // never cause a 0.6s black flash.
    @objc func screenParametersChanged() {
        guard !isExiting else { return }

        let nowSig = currentScreenSignature()
        if nowSig == screenSignature {
            // Layout didn't change — don't hide webViews. If a previous rebuild
            // timer was pending (e.g., transient display bounce), cancel it and
            // restore visibility.
            if rebuildWork != nil {
                rebuildWork?.cancel()
                rebuildWork = nil
                for webView in webViews { webView.isHidden = false }
            }
            return
        }

        logLine("screenParametersChanged detected layout change; settling before rebuild...")
        for webView in webViews { webView.isHidden = true }

        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isExiting else { return }
            self.rebuildWork = nil
            guard !NSScreen.screens.isEmpty else {
                self.exitAll(animated: false)
                return
            }
            guard self.currentScreenSignature() != self.screenSignature else {
                for webView in self.webViews { webView.isHidden = false }
                return
            }
            self.tearDownWindows()
            self.buildWindows(animated: false)
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logLine("Warning: WKWebView content process terminated; reloading \(config.htmlURL.lastPathComponent)")
        webView.loadFileURL(
            config.htmlURL,
            allowingReadAccessTo: config.htmlURL.deletingLastPathComponent()
        )
    }

    func createWindow(on screen: NSScreen, displayIndex: Int, initialAlpha: CGFloat) {
        let frame = screen.frame

        let window = MatrixWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.alphaValue = initialAlpha
        window.acceptsMouseMovedEvents = isScreensaverMode

        if isScreensaverMode {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        } else if isWallpaperMode {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.ignoresMouseEvents = true
        }

        let wkConfig = WKWebViewConfiguration()
        wkConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: window.contentView!.bounds, configuration: wkConfig)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")

        window.contentView?.addSubview(webView)
        webView.loadFileURL(
            config.htmlURL,
            allowingReadAccessTo: config.htmlURL.deletingLastPathComponent()
        )

        if isScreensaverMode {
            window.onUserInput = { [weak self] in
                self?.exitAll(animated: true)
            }
        }

        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        windows.append(window)
        webViews.append(webView)
    }

    // MARK: Input Dismissal

    func installInputMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .mouseMoved
        ]

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return event }
            if self.shouldDismiss(for: event) {
                self.exitAll(animated: true)
                return nil // Swallow event so it doesn't beep or click through
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return }
            if self.shouldDismiss(for: event) {
                self.exitAll(animated: true)
            }
        }
    }

    func shouldDismiss(for event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        case .flagsChanged:
            return !event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        case .scrollWheel:
            return abs(event.scrollingDeltaX) > 1 || abs(event.scrollingDeltaY) > 1
        case .mouseMoved:
            if abs(event.deltaX) > 5 || abs(event.deltaY) > 5 {
                return true
            }
            let loc = NSEvent.mouseLocation
            let dist = hypot(loc.x - initialMouseLocation.x, loc.y - initialMouseLocation.y)
            return dist > 8.0
        default:
            return false
        }
    }

    /// Checks IOKit HIDIdleTime every 250ms so remote/synthetic input (e.g. RustDesk)
    /// dismisses the screensaver almost immediately without waiting on the daemon.
    func installRemoteIdleWatcher() {
        remoteIdleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, !self.isExiting else { return }
            let idle = SystemState.hidIdleSeconds()
            if idle > self.maxObservedIdle {
                self.maxObservedIdle = idle
            } else if idle < self.maxObservedIdle - 0.5 {
                self.exitAll(animated: true)
            }
        }
        remoteIdleTimer?.tolerance = 0.05
    }

    // MARK: Power Assertions

    func acquirePowerAssertionsIfAllowed() {
        if config.allowDisplaySleepOnBattery && SystemState.isOnBattery() {
            logLine("On battery with AllowDisplaySleepOnBattery=True; skipping display-sleep assertion.")
            return
        }

        let reason = "Matrix Rain screensaver is active" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displaySleepAssertionID
        )
        if result == kIOReturnSuccess {
            hasDisplayAssertion = true
            logLine("Display sleep assertion acquired (ID: \(displaySleepAssertionID))")
        } else {
            logLine("Warning: Failed to acquire display sleep assertion (error: \(result))")
        }

        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "Matrix screensaver is active"
        )
    }

    func configurePowerLimits() {
        if config.maxDurationSeconds > 0 {
            maxDurationTimer = Timer.scheduledTimer(
                withTimeInterval: config.maxDurationSeconds,
                repeats: false
            ) { [weak self] _ in
                guard let self = self, !self.isExiting else { return }
                logLine("MaxDurationSeconds (\(Int(self.config.maxDurationSeconds))s) reached; releasing display-sleep assertion.")
                self.releaseDisplaySleepAssertion()
            }
        }

        if config.allowDisplaySleepOnBattery {
            batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                guard let self = self, !self.isExiting else { return }
                if self.hasDisplayAssertion && SystemState.isOnBattery() {
                    logLine("Switched to battery; releasing display-sleep assertion.")
                    self.releaseDisplaySleepAssertion()
                }
            }
            batteryCheckTimer?.tolerance = 2.0
        }
    }

    func releaseDisplaySleepAssertion() {
        if hasDisplayAssertion {
            IOPMAssertionRelease(displaySleepAssertionID)
            hasDisplayAssertion = false
            logLine("Display sleep assertion released.")
        }
        if let activity = processActivity {
            ProcessInfo.processInfo.endActivity(activity)
            processActivity = nil
        }
    }

    func exitAll(animated: Bool) {
        guard !isExiting else { return }
        isExiting = true

        rebuildWork?.cancel()
        remoteIdleTimer?.invalidate()
        remoteIdleTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil

        if let m = localEventMonitor {
            NSEvent.removeMonitor(m)
            localEventMonitor = nil
        }
        if let m = globalEventMonitor {
            NSEvent.removeMonitor(m)
            globalEventMonitor = nil
        }

        releaseDisplaySleepAssertion()
        if isScreensaverMode {
            NSCursor.unhide()
        }

        let fade = (animated && isScreensaverMode) ? config.fadeOutSeconds : 0.0
        if fade > 0 && !windows.isEmpty {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = fade
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                for window in windows {
                    window.animator().alphaValue = 0.0
                }
            }, completionHandler: {
                NSApp.terminate(nil)
            })
            // Safety net in case completion handler doesn't fire during shutdown
            DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.15) {
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Main Entrypoint

let args = CommandLine.arguments
let executablePath = URL(fileURLWithPath: args[0]).standardizedFileURL.path
let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

func argValue(_ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

let isDaemon = args.contains("--daemon")
let isScreensaver = args.contains("--screensaver")
let isWallpaper = args.contains("--wallpaper")
let isStatus = args.contains("--status")

let configOverride = argValue("--config").map { URL(fileURLWithPath: $0) }
let htmlOverride = argValue("--html").map { URL(fileURLWithPath: $0) }

if isStatus {
    let cfg = ScreensaverConfig.load(baseDir: executableDir, configPath: configOverride, htmlOverride: htmlOverride)
    let displays = SystemState.onlineDisplays()
    let assertions = SystemState.activeDisplaySleepAssertionProcesses()
    let blockCheck = SystemState.hasBlockingDisplaySleepAssertion(
        ignoring: cfg.ignoreAssertionProcesses,
        excludingPIDs: [getpid()]
    )

    print("MatrixScreensaver Status")
    print("  Base Dir:        \(executableDir.path)")
    print("  Config File:     \((configOverride ?? executableDir.appendingPathComponent("config.ini")).path)")
    print("  Enabled:         \(cfg.enabled)")
    print("  Idle Threshold:  \(Int(cfg.idleTimeSeconds))s")
    print("  HTML Path:       \(cfg.htmlURL.path) (exists=\(FileManager.default.fileExists(atPath: cfg.htmlURL.path)))")
    print("  Fade In / Out:   \(cfg.fadeInSeconds)s / \(cfg.fadeOutSeconds)s")
    print("  Max Duration:    \(cfg.maxDurationSeconds == 0 ? "unlimited" : "\(Int(cfg.maxDurationSeconds))s")")
    print("  Sleep on Batt:   \(cfg.allowDisplaySleepOnBattery)")
    print("  Respect Asserts: \(cfg.respectDisplaySleepAssertions) (ignore=\(cfg.ignoreAssertionProcesses.sorted().joined(separator: ",")))")
    print("System State")
    print("  HID Idle Time:   \(String(format: "%.2f", SystemState.hidIdleSeconds()))s")
    print("  Online Displays: \(displays.count) (asleep/dark=\(SystemState.areAllDisplaysDarkOrAsleep()))")
    for id in displays {
        let builtin = CGDisplayIsBuiltin(id) != 0 ? "built-in" : "external"
        let asleep = CGDisplayIsAsleep(id) != 0 ? "asleep" : "awake"
        print("    - Display \(id): \(builtin), \(asleep), \(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))")
    }
    print("  Lid Closed:      \(SystemState.isLidClosed())")
    print("  Session Locked:  \(SystemState.isSessionLockedOrInactive())")
    print("  On Battery:      \(SystemState.isOnBattery())")
    print("  Display Asserts: \(assertions.isEmpty ? "none" : assertions.joined(separator: ", "))")
    if cfg.respectDisplaySleepAssertions {
        print("  Would Block:     \(blockCheck.blocked) (\(blockCheck.blockers.joined(separator: ", ")))")
    }
    exit(0)
}

if isDaemon {
    let app = NSApplication.shared
    let delegate = DaemonDelegate(
        executablePath: executablePath,
        baseDir: executableDir,
        configPath: configOverride
    )
    app.delegate = delegate
    app.run()
} else if isScreensaver || isWallpaper {
    let cfg = ScreensaverConfig.load(
        baseDir: executableDir,
        configPath: configOverride,
        htmlOverride: htmlOverride
    )
    guard FileManager.default.fileExists(atPath: cfg.htmlURL.path) else {
        logLine("Error: Cannot find \(cfg.htmlURL.path)")
        logLine("Place index.html next to this executable, or use --html /path/to/index.html")
        exit(1)
    }

    let app = NSApplication.shared
    let delegate = ScreensaverAppDelegate(
        isScreensaver: isScreensaver,
        isWallpaper: isWallpaper,
        config: cfg
    )
    app.delegate = delegate
    app.run()
} else {
    print("Usage: MatrixScreensaver [--daemon | --screensaver | --wallpaper | --status] [--html PATH] [--config PATH]")
    exit(1)
}
