import Cocoa

private func companionAXValue(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}

final class StageManagerGuardian {
    static let shared = StageManagerGuardian()
    private let worker = WindowAccessibility.queue
    private let statusLock = NSLock()
    private let generationLock = NSLock()
    private var generationValue: UInt64 = 0
    private var generation: UInt64 {
        generationLock.lock(); defer { generationLock.unlock() }; return generationValue
    }
    private func advanceGeneration() {
        generationLock.lock(); generationValue &+= 1; generationLock.unlock()
    }
    private let diagnostics = ProcessInfo.processInfo.arguments.contains("--companion-diagnostics")
    private var diagnosticFrames: [[String: Any]] = []
    private var diagnosticHistory: [[String: Any]] = []
    private var lastDiagnosticSnapshot = ""
    private var reconcileBusy = false // main-thread owned; never accumulate AX scans
    private var refreshBusy = false // main-thread owned, bounds AX work when an app is hung
    private struct ScreenSnapshot { let frame: CGRect; let visibleFrame: CGRect }
    private var observers: [pid_t: AXObserver] = [:]
    private var windows: [pid_t: [AXUIElement]] = [:]
    private var work: DispatchWorkItem?
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var records = StageWindowRecords()
    private var lastSettingsSignature = ""
    private(set) var corrections = 0
    private var statusStorage = NSLocalizedString("Waiting for Accessibility permission", comment: "Stage helper status")
    var status: String {
        get { statusLock.lock(); defer { statusLock.unlock() }; return statusStorage }
        set { statusLock.lock(); statusStorage = newValue; statusLock.unlock() }
    }

    func start() {
        guard timer == nil, AXIsProcessTrusted() else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if name == NSWorkspace.activeSpaceDidChangeNotification { self?.invalidateHistory() }
                self?.refresh(); self?.schedule()
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.invalidateHistory(); self?.schedule() })
        tokens.append(NotificationCenter.default.addObserver(forName: CompanionSettings.changed,
            object: nil, queue: .main) { [weak self] _ in self?.invalidateHistory(); self?.refresh(); self?.schedule() })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh(); self?.schedule() }
        timer?.tolerance = 0.2
        refresh(); schedule()
    }

    func stop() {
        advanceGeneration()
        work?.cancel(); work = nil; timer?.invalidate(); timer = nil
        worker.async { self.clearObservers(); self.records.removeAll() }
        for token in tokens { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens.removeAll()
    }

    var isStageOn: Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool ?? false
    }
    var stripEdge: StageEdge {
        let dock = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(dock)
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String
        if orientation == "left" { return .right }
        if orientation == "right" { return .left }
        return NSLocale.characterDirection(forLanguage: Locale.current.languageCode ?? "en") == .rightToLeft ? .right : .left
    }
    private func invalidateHistory() {
        advanceGeneration()
        worker.async { self.records.removeAll() }
    }
    private func clearObservers() {
        for observer in observers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observers.removeAll(); windows.removeAll()
    }
    private func checkSettings(_ config: CompanionConfiguration) {
        let signature = "\(config.stageEnabled)-\(isStageOn)-\(stripEdge)-\(config.stageWidth)"
        if signature != lastSettingsSignature {
            lastSettingsSignature = signature; records.removeAll(); schedule()
        }
    }
    private func refresh() {
        guard timer != nil, !refreshBusy else { return }
        let config = CompanionSettings.shared.configuration
        let apps = NSWorkspace.shared.runningApplications
        refreshBusy = true
        let epoch = generation
        worker.async {
            defer { DispatchQueue.main.async { self.refreshBusy = false } }
            guard epoch == self.generation else { return }
            self.checkSettings(config)
            if config.windowSizingMode == .direct || (config.stageEnabled && self.isStageOn) {
                // NSRunningApplication's dynamic getters synchronously query
                // LaunchServices. Never enumerate them on the input run loop.
                let eligible = apps.filter {
                    $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() &&
                    !CompanionSettings.matches(paths: config.excludedPaths, bundlePath: $0.bundleURL?.path, executablePath: $0.executableURL?.path)
                }
                guard epoch == self.generation else { return }
                self.refreshOnWorker(apps: eligible)
            } else { self.clearObservers(); self.records.removeAll() }
        }
    }
    private func refreshOnWorker(apps: [NSRunningApplication]) {
        guard AXIsProcessTrusted() else { status = NSLocalizedString("Waiting for Accessibility permission", comment: ""); return }
        let live = Set(apps.map(\.processIdentifier))
        for pid in Array(observers.keys) where !live.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
            windows.removeValue(forKey: pid)
            records.retainWindows(pid: pid, hashes: [])
        }
        for app in apps {
            let pid = app.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.15)
            if observers[pid] == nil {
                var observer: AXObserver?
                let callback: AXObserverCallback = { _, _, _, _ in
                    StageManagerGuardian.shared.schedule()
                    DirectWindowController.shared.windowDidChange()
                }
                if AXObserverCreate(pid, callback, &observer) == .success, let observer {
                    observers[pid] = observer
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                    for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                        AXObserverAddNotification(observer, element, notification as CFString, nil)
                    }
                }
            }
            guard let observer = observers[pid], let list = companionAXValue(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            records.retainWindows(pid: pid, hashes: Set(list.map { CFHash($0) }))
            let old = windows[pid] ?? []
            for window in old where !list.contains(where: { CFEqual($0, window) }) {
                for notification in [kAXMovedNotification, kAXResizedNotification] { AXObserverRemoveNotification(observer, window, notification as CFString) }
            }
            for window in list where !old.contains(where: { CFEqual($0, window) }) {
                AXUIElementSetMessagingTimeout(window, 0.15)
                for notification in [kAXMovedNotification, kAXResizedNotification] { AXObserverAddNotification(observer, window, notification as CFString, nil) }
            }
            windows[pid] = list
        }
    }

    func schedule() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.schedule() }; return }
        guard timer != nil else { return }
        work?.cancel()
        let next = DispatchWorkItem { [weak self] in self?.reconcile() }
        work = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: next)
    }

    func reconcile() {
        guard timer != nil else { return }
        let config = CompanionSettings.shared.configuration
        guard config.stageEnabled else { status = NSLocalizedString("Stage Manager helper is off", comment: ""); return }
        guard isStageOn else { status = NSLocalizedString("Stage Manager is off — space reclaimed", comment: ""); return }
        guard AXIsProcessTrusted() else { return }
        // Do not reposition a window while a native drag, resize or gesture is underway.
        guard NSEvent.pressedMouseButtons == 0, !CompanionGestureController.shared.isHeld, !DirectWindowController.shared.isInteracting else { schedule(); return }
        let screens = NSScreen.screens.map { ScreenSnapshot(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let primaryTop = screens.first?.frame.maxY else { return }
        guard !reconcileBusy else { return }
        reconcileBusy = true
        let epoch = generation
        worker.async {
            self.reconcileOnWorker(config: config, screens: screens, primaryTop: primaryTop, epoch: epoch)
            DispatchQueue.main.async { self.reconcileBusy = false }
        }
    }

    private func reconcileOnWorker(config: CompanionConfiguration, screens: [ScreenSnapshot], primaryTop: CGFloat, epoch: UInt64) {
        guard epoch == generation, AXIsProcessTrusted(), config.stageEnabled, isStageOn else { return }
        let edge = stripEdge
        diagnosticFrames = []
        defer {
            if diagnostics {
                let snapshot: [String: Any] = ["frames": diagnosticFrames, "screens": screens.map {
                    ["frame": NSStringFromRect($0.frame), "visible": NSStringFromRect($0.visibleFrame)]
                }]
                if let encoded = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
                   let digest = String(data: encoded, encoding: .utf8), digest != lastDiagnosticSnapshot {
                    lastDiagnosticSnapshot = digest
                    diagnosticHistory.append(["time": Date().timeIntervalSince1970, "snapshot": snapshot])
                    diagnosticHistory = Array(diagnosticHistory.suffix(60))
                    if let data = try? JSONSerialization.data(withJSONObject: diagnosticHistory, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: URL(fileURLWithPath: "/private/tmp/mac-companion-stage.json"), options: .atomic)
                    }
                }
            }
        }
        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let visiblePIDs = Set(onScreen.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        var blocked = 0
        for (pid, list) in windows where visiblePIDs.contains(pid) {
            if diagnostics {
                for window in list {
                    diagnosticFrames.append(["rawPID": pid, "rawFrame": Self.frame(window).map(NSStringFromRect) ?? "nil",
                        "role": companionAXValue(window, kAXSubroleAttribute) as? String ?? "nil",
                        "onScreen": Self.frame(window).map { Self.isOnScreen($0, pid: pid, windowInfo: onScreen) } ?? false,
                        "cgFrames": onScreen.filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid }.map { $0[kCGWindowBounds as String] ?? "nil" }])
                }
            }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  !CompanionSettings.matches(paths: config.excludedPaths, bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path) else { continue }
            for window in list {
                guard companionAXValue(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      companionAXValue(window, kAXMinimizedAttribute) as? Bool != true,
                      companionAXValue(window, "AXFullScreen") as? Bool != true,
                      let original = Self.frame(window),
                      Self.isOnScreen(original, pid: pid, windowInfo: onScreen) else { continue }
                let appKitFrame = CGRect(x: original.minX, y: primaryTop - original.maxY, width: original.width, height: original.height)
                guard let screen = screens.max(by: { Self.area($0.frame.intersection(appKitFrame)) < Self.area($1.frame.intersection(appKitFrame)) }),
                      Self.area(screen.frame.intersection(appKitFrame)) >= Self.area(appKitFrame) * 0.9 else { continue }
                if diagnostics {
                    diagnosticFrames.append(["pid": pid, "app": app.bundleIdentifier ?? "unknown", "window": NSStringFromRect(appKitFrame),
                        "visible": NSStringFromRect(screen.visibleFrame), "screen": NSStringFromRect(screen.frame)])
                }
                if config.windowSizingMode == .direct, DirectWindowController.shared.isManaged(window) { continue }
                let key = StageWindowRecords.key(pid: pid, hash: CFHash(window))
                guard let targetAppKit = StageLayout.correction(for: appKitFrame, visibleFrame: screen.visibleFrame,
                    width: CGFloat(config.stageWidth), edge: edge) else {
                    // Moving to a different floating layout is an explicit user action: allow a later native tile again.
                    if let previous = records.history[key], let target = previous.target, !StageLayout.near(original, target),
                       let source = previous.source, !StageLayout.near(original, source) {
                        records.history.removeValue(forKey: key); records.suppressed.remove(key)
                    }
                    continue
                }
                let target = CGRect(x: targetAppKit.minX, y: primaryTop - targetAppKit.maxY, width: targetAppKit.width, height: targetAppKit.height)
                guard !records.suppressed.contains(key) else { blocked += 1; continue }
                var record = records.history[key] ?? StageCorrectionHistory()
                guard record.permits(source: original, target: target, now: ProcessInfo.processInfo.systemUptime) else {
                    records.suppressed.insert(key); blocked += 1; continue
                }
                records.history[key] = record
                guard epoch == generation else { return }
                guard !CGEventSource.buttonState(.combinedSessionState, button: .left) else { continue }
                if Self.setFrame(target, on: window) {
                    corrections += 1
                    worker.asyncAfter(deadline: .now() + 0.2) {
                        guard epoch == self.generation, let actual = Self.frame(window), !StageLayout.near(actual, target, tolerance: 4) else { return }
                        self.records.suppressed.insert(key)
                        self.status = NSLocalizedString("Some windows resist resizing; automatic retries paused", comment: "Stage status")
                    }
                } else { records.suppressed.insert(key); blocked += 1 }
            }
        }
        status = blocked > 0
            ? NSLocalizedString("Some windows resist resizing; automatic retries paused", comment: "Stage status")
            : String(format: NSLocalizedString("Active · %d layout adjustments", comment: "Stage status"), corrections)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
    private static func isOnScreen(_ frame: CGRect, pid: pid_t, windowInfo: [[String: Any]]) -> Bool {
        windowInfo.contains { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return StageLayout.near(frame, rect, tolerance: 5)
        }
    }
    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let position = companionAXValue(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = companionAXValue(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
    private static func setFrame(_ frame: CGRect, on window: AXUIElement) -> Bool {
        WindowAccessibility.placeRaw(frame, on: window, bounds: frame) != nil
    }
}
