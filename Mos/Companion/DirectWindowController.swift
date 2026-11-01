import Cocoa

private final class WindowPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill(); path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke(); path.lineWidth = 2; path.stroke()
    }
}
private struct WindowContext {
    let config: CompanionConfiguration
    let screens: [CompanionScreen]
    let top: CGFloat
    let stageOn: Bool
    let edge: StageEdge
}
private final class WindowEpoch {
    private let lock = NSLock(); private var value: UInt64 = 0
    func capture() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value &+= 1; lock.unlock() }
}

final class DirectWindowController {
    static let shared = DirectWindowController()
    private let worker = WindowAccessibility.queue
    private let titlebarWork = BoundedWindowWork(queue: WindowAccessibility.inputInspectionQueue)
    private let dragWork = BoundedWindowWork(queue: WindowAccessibility.queue)
    private let epoch = WindowEpoch()
    private let lease = NativeWindowSettingsLease()
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var primaryInterceptor: Interceptor?
    private var primaryCapture = TitlebarClickCapture() // main-run-loop owned
    private var verifiedClick: CompanionWindow?
    private var capturedClick: CompanionWindow?
    private var capturedToken: UInt64 = 0
    private var frontPID: pid_t = 0
    private var doubleClickInterval = NSEvent.doubleClickInterval
    private var preview: NSPanel?
    private var active = false // main-thread owned
    private var conflict = false
    private var inputFailure = false
    private var reflowWork: DispatchWorkItem?
    private var inspectionWork: DispatchWorkItem?
    private var signature = ""
    private var cachedContext: WindowContext?
    private var lastDrag = 0.0
    private var lastExternalPID: pid_t?
    private(set) var isInteracting = false
    private let statusLock = NSLock()
    private var statusStorage = NSLocalizedString("Native sizing with gap correction", comment: "")
    var status: String {
        get { statusLock.lock(); defer { statusLock.unlock() }; return statusStorage }
        set { statusLock.lock(); statusStorage = newValue; statusLock.unlock() }
    }
    // Owned solely by the shared AX worker.
    private var records: [CompanionWindowKey: (window: AXUIElement, placement: ManagedWindowPlacement)] = [:]
    private var click = TitlebarDoubleClick()
    private struct Drag {
        let window: CompanionWindow
        var initialRaw: CGRect
        let downPoint: CGPoint
        var moving = false
        var resizing = false
        var restored = false
    }
    private var drag: Drag?
    private let diagnostics = ProcessInfo.processInfo.arguments.contains("--companion-diagnostics")
    private var diagnosticEvents: [[String: Any]] = []
    private func trace(_ event: [String: Any]) {
        guard diagnostics else { return }
        var event = event; event["time"] = Date().timeIntervalSince1970
        diagnosticEvents.append(event); diagnosticEvents = Array(diagnosticEvents.suffix(60))
        if let data = try? JSONSerialization.data(withJSONObject: diagnosticEvents, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/mac-companion-direct.json"), options: .atomic)
        }
    }

    func recoverNativeSettings() {
        guard !AppRuntime.isRunningXCTest else { return }
        if !lease.restore() { status = NSLocalizedString("Could not restore native window settings; use Restore macOS Window Controls", comment: "") }
    }
    func start() {
        guard timer == nil, !AppRuntime.isRunningXCTest, AXIsProcessTrusted() else { return }
        inputFailure = false
        signature = "" // Recompute managed geometry after sleep/permission recovery.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier != getpid(), name == NSWorkspace.didActivateApplicationNotification { self?.lastExternalPID = app.processIdentifier }
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    let pid = app.processIdentifier
                    self?.worker.async { [weak self] in
                        guard let self else { return }
                        self.records = self.records.filter { $0.key.pid != pid }
                    }
                }
                self?.refresh()
                if name == NSWorkspace.didActivateApplicationNotification { self?.scheduleReflow() }
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: CompanionSettings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.conflict = false; self?.inputFailure = false; self?.cancelInteraction(); self?.signature = ""; self?.refresh()
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelInteraction(); self?.signature = ""; self?.refresh()
        })
        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelInteraction() })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        probeTitlebarIfRequested()
    }
    private func probeTitlebarIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard diagnostics, let index = args.firstIndex(of: "--companion-probe-titlebar"), args.indices.contains(index + 1),
              let number = UInt32(args[index + 1]), let context = context() else { return }
        worker.async {
            guard let frame = WindowAccessibility.serverFrame(number) else { return }
            var samples: [[String: Any]] = []
            for (fraction, offset) in [(0.25, 25.0), (0.5, 25), (0.75, 25), (0.9, 25), (0.75, 50), (0.75, 70)] {
                let point = CGPoint(x: frame.minX + frame.width * fraction, y: frame.minY + offset)
                let hit = WindowAccessibility.hit(at: point, number: number, config: context.config)
                samples.append(["point": NSStringFromPoint(point), "titlebar": hit?.titlebar ?? false, "hitPath": hit?.hitPath ?? []])
            }
            self.trace(["event": "header-probe", "window": number, "frame": NSStringFromRect(frame), "samples": samples])
        }
    }
    func stop() {
        epoch.advance(); timer?.invalidate(); timer = nil; cancelInteraction(); stopMonitoring()
        reflowWork?.cancel(); inspectionWork?.cancel()
        for token in tokens { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }; tokens.removeAll()
        active = false
        if !lease.restore() { status = NSLocalizedString("Could not restore native window settings; use Restore macOS Window Controls", comment: "") }
    }
    func restoreNativeControls() {
        CompanionSettings.shared.update { $0.windowSizingMode = .nativeCorrection }
        cancelInteraction(); stopMonitoring(); active = false
        status = lease.restore() ? NSLocalizedString("Native window controls restored", comment: "") : NSLocalizedString("Native settings could not be restored; retry Restore macOS Window Controls", comment: "")
    }
    private func context() -> WindowContext? {
        let screens = CompanionScreen.capture()
        guard let top = screens.first?.frame.maxY else { return nil }
        return WindowContext(config: CompanionSettings.shared.configuration, screens: screens, top: top,
            stageOn: StageManagerGuardian.shared.isStageOn, edge: StageManagerGuardian.shared.stripEdge)
    }
    private func refresh() {
        guard let context = context() else { return }
        if context.config.windowSizingMode == .nativeCorrection, cachedContext?.config.windowSizingMode == .direct {
            worker.async { self.records.removeAll() }
        }
        cachedContext = context
        doubleClickInterval = NSEvent.doubleClickInterval
        let config = context.config
        let external = NSWorkspace.shared.frontmostApplication
        frontPID = external?.processIdentifier ?? 0
        if let external, external.processIdentifier != getpid() { lastExternalPID = external.processIdentifier }
        let excluded = external?.processIdentifier != getpid() && CompanionSettings.shared.isExcluded(external)
        let wanted = config.windowSizingMode == .direct && !excluded
        if active, lease.hasJournal, !lease.owned {
            conflict = true; active = false; cancelInteraction(); stopMonitoring(); _ = lease.restore()
        }
        if !wanted || conflict || inputFailure {
            if active { cancelInteraction(); stopMonitoring(); active = false }
            if lease.hasJournal { _ = lease.restore() }
            status = NSLocalizedString(inputFailure ? "Direct double-click input could not start; using native correction" : (conflict ? "Native settings changed; reselect Direct sizing to resume" :
                (excluded && config.windowSizingMode == .direct ? "Direct sizing paused in this app" : "Native sizing with gap correction")), comment: "")
        } else if !active {
            if lease.acquire() {
                active = true
                if startMonitoring() { status = NSLocalizedString("Direct sizing active", comment: "") }
                else {
                    active = false; inputFailure = true; _ = lease.restore()
                    worker.async { self.records.removeAll() }
                    status = NSLocalizedString("Direct double-click input could not start; using native correction", comment: "")
                }
            }
            else { status = NSLocalizedString("Could not take control of native sizing; using native correction", comment: "") }
        }
        let next = "\(config.windowSizingMode)-\(config.stageEnabled)-\(config.stageWidth)-\(context.stageOn)-\(context.edge)-\(context.screens)"
        if next != signature { signature = next; scheduleReflow() }
    }
    private func startMonitoring() -> Bool {
        guard globalMonitor == nil else { return primaryInterceptor != nil }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event); return event }
        do {
            let primary = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            primaryInterceptor = try Interceptor(event: primary, handleBy: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { DirectWindowController.shared.cancelInteraction() }
                    DirectWindowController.shared.primaryCapture.reset()
                    DirectWindowController.shared.verifiedClick = nil
                    DirectWindowController.shared.capturedClick = nil
                    return Unmanaged.passUnretained(event)
                }
                if TrackpadMiddleController.shared.handlesPhysicalClick(event) { return Unmanaged.passUnretained(event) }
                return DirectWindowController.shared.capturePrimary(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }, listenOn: .cgSessionEventTap, placeAt: .headInsertEventTap, for: .defaultTap)
            primaryInterceptor?.onRestart = { [weak self] in
                self?.cancelInteraction(); self?.primaryCapture.reset(); self?.verifiedClick = nil; self?.capturedClick = nil
            }
            primaryInterceptor?.shouldRestart = { [weak self] in self?.active == true }
            worker.async { self.trace(["event": "capture-install", "enabled": true]) }
            return true
        } catch {
            worker.async { self.trace(["event": "capture-install", "enabled": false]) }
            stopMonitoring()
            return false
        }
    }
    private func stopMonitoring() {
        primaryInterceptor?.stop(); primaryInterceptor = nil
        primaryCapture.reset(); verifiedClick = nil; capturedClick = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
    }
    private func cancelInteraction() {
        primaryCapture.cancel(); verifiedClick = nil; capturedClick = nil
        epoch.advance(); isInteracting = false; preview?.orderOut(nil)
        worker.async { self.drag = nil; self.click.cancel() }
    }
    /// No AX, preference reads, or UI messaging in this input callback. The first
    /// click passes through; a separate read lane verifies its original hit.
    private func capturePrimary(type: CGEventType, event: CGEvent) -> Bool {
        let point = event.location
        if type == .leftMouseUp {
            let result = primaryCapture.up(at: point)
            guard result != .pass else { return false }
            let window = capturedClick; capturedClick = nil; verifiedClick = nil
            let token = capturedToken
            if result == .commit, active, let window, frontPID == window.key.pid, let context = cachedContext {
                let appPoint = CGPoint(x: point.x, y: context.top - point.y)
                worker.async {
                    if token == self.epoch.capture(), let screen = context.screens.first(where: { $0.frame.contains(appPoint) }) {
                        self.trace(["event": "captured-double-click", "window": window.key.number])
                        self.apply(.fill, to: window, screen: screen, context: context, token: token)
                    }
                    DispatchQueue.main.async { if token == self.epoch.capture() { self.isInteracting = false } }
                }
            } else { isInteracting = false }
            return true
        }
        guard type == .leftMouseDown, active, !CompanionGestureController.shared.isHeld,
              event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]).isEmpty,
              let context = cachedContext else { primaryCapture.cancel(); verifiedClick = nil; return false }
        let raw = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        let number = CGWindowID(exactly: raw > 0 ? raw : event.getIntegerValueField(.mouseEventWindowUnderMousePointer)) ?? 0
        let count = Int(event.getIntegerValueField(.mouseEventClickState))
        switch primaryCapture.down(count: count, window: number, frontPID: frontPID, point: point,
            time: ProcessInfo.processInfo.systemUptime, interval: doubleClickInterval) {
        case .pass:
            verifiedClick = nil; return false
        case .inspect(let ticket):
            verifiedClick = nil
            titlebarWork.submit {
                let hit = WindowAccessibility.hit(at: point, number: number, config: context.config)
                self.worker.async { self.trace(["event": "capture-hit", "window": hit?.key.number ?? 0, "titlebar": hit?.titlebar ?? false, "hitPath": hit?.hitPath ?? []]) }
                DispatchQueue.main.async {
                    if let hit, self.primaryCapture.confirm(ticket: ticket, window: hit.key.number, pid: hit.key.pid, titlebar: hit.titlebar) {
                        self.verifiedClick = hit
                    }
                }
            }
            return false
        case .capture:
            guard let window = verifiedClick else { primaryCapture.cancel(); return true }
            epoch.advance(); capturedToken = epoch.capture(); capturedClick = window
            isInteracting = true
            DispatchQueue.main.async { self.preview?.orderOut(nil) }
            worker.async { self.drag = nil; self.click.cancel() }
            return true
        }
    }
    private func handle(_ event: NSEvent) {
        guard active else { return }
        if event.type == .keyDown { if event.keyCode == 53 { cancelInteraction() }; return }
        guard !CompanionGestureController.shared.isHeld else { cancelInteraction(); return }
        if event.type == .leftMouseDragged {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastDrag >= 1.0 / 60 else { return }; lastDrag = now
        }
        guard let context = cachedContext else { return }
        let cg = event.cgEvent
        let rawNumber = cg?.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) ?? 0
        let number = CGWindowID(exactly: rawNumber > 0 ? rawNumber : (cg?.getIntegerValueField(.mouseEventWindowUnderMousePointer) ?? 0)) ?? 0
        let point = cg?.location ?? CGPoint(x: NSEvent.mouseLocation.x, y: context.top - NSEvent.mouseLocation.y)
        let count = event.clickCount, time = event.timestamp
        if event.type == .leftMouseDown { epoch.advance(); preview?.orderOut(nil) }
        let token = epoch.capture()
        switch event.type {
        case .leftMouseDown:
            isInteracting = true
            worker.async {
                guard token == self.epoch.capture() else { return }
                let window = WindowAccessibility.hit(at: point, number: number, config: context.config)
                self.trace(["event": "down", "number": number, "resolved": window?.key.number ?? 0, "point": NSStringFromPoint(point), "titlebar": window?.titlebar ?? false, "count": count, "hitPath": window?.hitPath ?? []])
                self.click.down(window: window?.key.number ?? number, point: point, time: time, count: count, titlebar: window?.titlebar == true)
                self.drag = window.map { Drag(window: $0, initialRaw: $0.rawFrame,
                    downPoint: CGPoint(x: point.x, y: context.top - point.y)) }
            }
        case .leftMouseDragged:
            dragWork.submit { self.trackDrag(at: point, context: context, token: token) }
        case .leftMouseUp:
            preview?.orderOut(nil)
            worker.async {
                guard token == self.epoch.capture() else { return }
                self.trackDrag(at: point, context: context, token: token, showPreview: false)
                if let drag = self.drag {
                    let appPoint = CGPoint(x: point.x, y: context.top - point.y)
                    if drag.moving, !drag.resizing,
                       let screen = context.screens.first(where: { $0.frame.contains(appPoint) }),
                       let layout = WindowLayoutGeometry.snap(at: appPoint, screen: screen.frame) {
                        self.apply(layout, to: drag.window, screen: screen, context: context, token: token, toggleFill: false)
                    } else if self.click.shouldFill(window: drag.window.key.number, point: point, time: time, count: count,
                        titlebar: drag.window.titlebar && !drag.moving && !drag.resizing, interval: NSEvent.doubleClickInterval),
                        let screen = context.screens.first(where: { $0.frame.contains(appPoint) }) {
                        self.apply(.fill, to: drag.window, screen: screen, context: context, token: token)
                    } else { self.discardIfChanged(drag.window.key, top: context.top) }
                }
                self.drag = nil
                DispatchQueue.main.async { if token == self.epoch.capture() { self.isInteracting = false; self.preview?.orderOut(nil) } }
            }
        default: break
        }
    }
    private func trackDrag(at rawPoint: CGPoint, context: WindowContext, token: UInt64, showPreview: Bool = true) {
        guard token == epoch.capture(), var drag,
              let current = WindowAccessibility.serverFrame(drag.window.key.number) else { return }
        if abs(current.width - drag.initialRaw.width) > 2 || abs(current.height - drag.initialRaw.height) > 2 { drag.resizing = true }
        if !drag.resizing, abs(current.minX - drag.initialRaw.minX) > 2 || abs(current.minY - drag.initialRaw.minY) > 2 { drag.moving = true }
        let point = CGPoint(x: rawPoint.x, y: context.top - rawPoint.y)
        let screen = context.screens.first { $0.frame.contains(point) }
        if drag.moving, !drag.resizing, !drag.restored, let screen,
           let record = records[drag.window.key], record.placement.layout != nil {
            let previous = record.placement
            let initial = WindowAccessibility.flipped(drag.initialRaw, primaryTop: context.top)
            let restored = WindowLayoutGeometry.dragRestore(current: initial, floating: previous.floating,
                downPoint: drag.downPoint, cursor: point, bounds: screen.visible)
            if let actual = WindowAccessibility.placeRaw(WindowAccessibility.flipped(restored, primaryTop: context.top), on: drag.window.element,
                bounds: WindowAccessibility.flipped(screen.visible, primaryTop: context.top)) { drag.initialRaw = actual }
            records.removeValue(forKey: drag.window.key); drag.restored = true
        }
        self.drag = drag
        let rect: CGRect?
        if drag.moving, !drag.resizing, let screen, let layout = WindowLayoutGeometry.snap(at: point, screen: screen.frame) {
            rect = layout.frame(in: screen.workingArea(config: context.config, stageOn: context.stageOn, edge: context.edge))
        } else { rect = nil }
        if showPreview { DispatchQueue.main.async { if token == self.epoch.capture(), self.isInteracting { self.showPreview(rect) } } }
    }
    private func showPreview(_ rect: CGRect?) {
        guard let rect else { preview?.orderOut(nil); return }
        if preview == nil {
            let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true; panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = WindowPreviewView(); preview = panel
        }
        preview?.setFrame(rect, display: true); preview?.orderFrontRegardless()
    }
    func perform(_ layout: CompanionWindowLayout) {
        guard let context = context(), context.config.windowSizingMode == .direct, active else { return }
        let pid = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == getpid() ? nil : $0.processIdentifier } ?? lastExternalPID
        guard let pid else { return }
        let token = epoch.capture()
        worker.async {
            guard token == self.epoch.capture(), let window = WindowAccessibility.focused(pid: pid, config: context.config) else {
                self.status = NSLocalizedString("No resizable window is available", comment: ""); return
            }
            let frame = WindowAccessibility.flipped(window.rawFrame, primaryTop: context.top)
            guard let screen = WindowLayoutGeometry.screen(for: frame, preferredID: nil, screens: context.screens) else { return }
            self.apply(layout, to: window, screen: screen, context: context, token: token)
        }
    }
    private func apply(_ requested: CompanionWindowLayout, to window: CompanionWindow, screen: CompanionScreen,
                       context: WindowContext, token: UInt64, toggleFill: Bool = true) {
        guard token == epoch.capture(), WindowAccessibility.eligible(window.element),
              let raw = WindowAccessibility.frame(window.element) else { return }
        let current = WindowAccessibility.flipped(raw, primaryTop: context.top)
        discardIfChanged(window.key, top: context.top)
        let priorLayout = records[window.key]?.placement.layout?.rawValue ?? "floating"
        let hadRecord = records[window.key] != nil
        var record = records[window.key]?.placement ?? ManagedWindowPlacement(layout: nil, screenID: screen.id,
            applied: current, floating: current, beforeFill: nil, beforeFillLayout: nil)
        let working = screen.workingArea(config: context.config, stageOn: context.stageOn, edge: context.edge)
        let target: CGRect
        var layout: CompanionWindowLayout? = requested
        if requested == .restore {
            target = WindowLayoutGeometry.fit(record.floating, in: screen.visible); layout = nil
        } else if requested == .fill, toggleFill, record.layout == .fill, let previous = record.beforeFill {
            layout = record.beforeFillLayout
            target = layout?.frame(in: working) ?? WindowLayoutGeometry.fit(previous, in: screen.visible)
            record.beforeFill = nil; record.beforeFillLayout = nil
        } else {
            guard let frame = requested.frame(in: working) else { return }
            target = frame
            if requested == .fill { record.beforeFill = current; record.beforeFillLayout = record.layout }
        }
        guard token == epoch.capture() else { return }
        let bounds = layout == nil ? screen.visible : working
        guard let actualRaw = WindowAccessibility.placeRaw(WindowAccessibility.flipped(target, primaryTop: context.top), on: window.element,
            bounds: WindowAccessibility.flipped(bounds, primaryTop: context.top)) else {
            status = NSLocalizedString("This window does not allow resizing", comment: ""); return
        }
        let actual = WindowAccessibility.flipped(actualRaw, primaryTop: context.top)
        trace(["event": "place", "layout": requested.rawValue, "pid": window.key.pid, "window": window.key.number,
            "priorLayout": priorLayout, "hadRecord": hadRecord, "source": NSStringFromRect(current),
            "floating": NSStringFromRect(record.floating), "target": NSStringFromRect(target), "actual": NSStringFromRect(actual)])
        record.layout = StageLayout.near(actual, target, tolerance: 4) ? layout : nil
        record.applied = actual; record.screenID = screen.id
        records[window.key] = (window.element, record)
        status = StageLayout.near(actual, target, tolerance: 4) ? NSLocalizedString("Direct sizing active", comment: "") : NSLocalizedString("Window minimum size limits this layout", comment: "")
        // Some apps apply AX size changes asynchronously. Verify once after the
        // setter settles; a new interaction invalidates this bounded retry.
        worker.asyncAfter(deadline: .now() + 0.15) {
            guard token == self.epoch.capture(), var entry = self.records[window.key],
                  StageLayout.near(entry.placement.applied, actual),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !MCPhysicalMouseButtonDown(3), !MCPhysicalMouseButtonDown(4),
                  let settledRaw = WindowAccessibility.frame(window.element) else { return }
            var settled = WindowAccessibility.flipped(settledRaw, primaryTop: context.top)
            if !StageLayout.near(settled, target, tolerance: 4), StageLayout.near(settled, actual, tolerance: 4),
               settled.width <= target.width + 4, settled.height <= target.height + 4,
               let retried = WindowAccessibility.placeRaw(WindowAccessibility.flipped(target, primaryTop: context.top), on: window.element,
                   bounds: WindowAccessibility.flipped(bounds, primaryTop: context.top)) {
                settled = WindowAccessibility.flipped(retried, primaryTop: context.top)
            }
            let matched = StageLayout.near(settled, target, tolerance: 4)
            self.trace(["event": "settled", "window": window.key.number, "target": NSStringFromRect(target), "actual": NSStringFromRect(settled), "matched": matched])
            entry.placement.layout = matched ? layout : nil
            entry.placement.applied = settled; self.records[window.key] = entry
            self.status = matched ? NSLocalizedString("Direct sizing active", comment: "") : NSLocalizedString("Window minimum size limits this layout", comment: "")
        }
    }
    private func discardIfChanged(_ key: CompanionWindowKey, top: CGFloat) {
        guard let record = records[key] else { return }
        guard WindowAccessibility.eligible(record.window), let raw = WindowAccessibility.frame(record.window),
              NSRunningApplication(processIdentifier: key.pid) != nil else { records.removeValue(forKey: key); return }
        let current = WindowAccessibility.flipped(raw, primaryTop: top)
        if !StageLayout.near(current, record.placement.applied, tolerance: 4) {
            trace(["event": "history-discard", "window": key.number, "expected": NSStringFromRect(record.placement.applied), "actual": NSStringFromRect(current)])
            records.removeValue(forKey: key)
        }
    }
    // Called by the existing AX observer on the main run loop.
    func windowDidChange() {
        guard CompanionSettings.shared.configuration.windowSizingMode == .direct else { return }
        inspectionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isInteracting, NSEvent.pressedMouseButtons == 0, self.reflowWork == nil,
                  let context = self.context() else { return }
            self.worker.async { for key in Array(self.records.keys) { self.discardIfChanged(key, top: context.top) } }
        }
        inspectionWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    // Called only on the shared AX worker; managed geometry belongs to this service.
    func isManaged(_ element: AXUIElement) -> Bool {
        records.values.contains { $0.placement.layout != nil && CFEqual($0.window, element) }
    }
    private func scheduleReflow() {
        reflowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reflowWork = nil
            guard !self.isInteracting, !CompanionGestureController.shared.isHeld, NSEvent.pressedMouseButtons == 0 else { self.scheduleReflow(); return }
            guard let context = self.context(), context.config.windowSizingMode == .direct else { return }
            let token = self.epoch.capture()
            self.worker.async { self.reflow(context: context, token: token) }
        }
        reflowWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func reflow(context: WindowContext, token: UInt64) {
        for key in Array(records.keys) {
            guard token == epoch.capture() else { return }
            guard var entry = records[key], let layout = entry.placement.layout,
                  WindowAccessibility.eligible(entry.window), let raw = WindowAccessibility.frame(entry.window),
                  let app = NSRunningApplication(processIdentifier: key.pid),
                  !CompanionSettings.matches(paths: context.config.excludedPaths, bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path) else { records.removeValue(forKey: key); continue }
            // Offstage/full-screen windows are never moved by display reflow.
            guard let server = WindowAccessibility.serverFrame(key.number), StageLayout.near(raw, server, tolerance: 5),
                  WindowAccessibility.serverInfo(key.number)?[kCGWindowIsOnscreen as String] as? Bool == true else { continue }
            let current = WindowAccessibility.flipped(raw, primaryTop: context.top)
            guard let screen = WindowLayoutGeometry.screen(for: current, preferredID: entry.placement.screenID, screens: context.screens),
                  let target = layout.frame(in: screen.workingArea(config: context.config, stageOn: context.stageOn, edge: context.edge)) else { continue }
            let bounds = screen.workingArea(config: context.config, stageOn: context.stageOn, edge: context.edge)
            if !StageLayout.near(current, target), let result = WindowAccessibility.placeRaw(WindowAccessibility.flipped(target, primaryTop: context.top),
                on: entry.window, bounds: WindowAccessibility.flipped(bounds, primaryTop: context.top)) {
                entry.placement.applied = WindowAccessibility.flipped(result, primaryTop: context.top)
                if !StageLayout.near(entry.placement.applied, target, tolerance: 4) { entry.placement.layout = nil }
            } else { entry.placement.applied = current }
            entry.placement.screenID = screen.id; records[key] = entry
        }
    }
}
