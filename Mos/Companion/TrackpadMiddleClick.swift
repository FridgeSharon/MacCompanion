import Cocoa

/// Original recognition state, independent of the device bridge and event posting.
struct TrackpadTapRecognizer {
    private var began: Double?
    private var anchor = CGPoint.zero
    private var contact: Int32 = 0
    private var rejected = false
    private var lifting = false

    mutating func physicalClick() { rejected = true }
    mutating func cancel() { self = Self() }
    mutating func update(count: Int, point: CGPoint, contact: Int32, touching: Bool, time: Double) -> Bool {
        guard time.isFinite, point.x.isFinite, point.y.isFinite else { cancel(); return false }
        if count == 0 {
            let fire = began.map { !rejected && time >= $0 && time - $0 <= 0.30 } ?? false
            cancel(); return fire
        }
        if count > 3 || count < 0 { rejected = true }
        if began != nil && count < 3 { lifting = true }
        guard count == 3, touching else { return false }
        if lifting { rejected = true }
        if began == nil && !rejected { began = time; anchor = point; self.contact = contact }
        if self.contact != contact || hypot(point.x - anchor.x, point.y - anchor.y) > 0.035 { rejected = true }
        return false
    }
}

struct TrackpadMiddleSession {
    private(set) var device: UInt64?
    mutating func begin(device: UInt64, threeFingers: Bool) -> Bool {
        guard self.device == nil, device != 0, threeFingers else { return false }
        self.device = device; return true
    }
    func matches(_ device: UInt64) -> Bool { device != 0 && self.device == device }
    mutating func end(device: UInt64) -> Bool {
        guard matches(device) else { return false }
        self.device = nil; return true
    }
    mutating func cancel() -> Bool { let held = device != nil; device = nil; return held }
}

final class TrackpadMiddleController {
    static let shared = TrackpadMiddleController()
    static let changed = Notification.Name("CompanionTrackpadMiddleChanged")
    private enum Key {
        static let enabled = "companionTrackpadMiddleEnabledV1"
        static let tap = "companionTrackpadMiddleTapV1"
        static let click = "companionTrackpadMiddleClickV1"
    }
    private struct Frame {
        var recognizer = TrackpadTapRecognizer()
        var count = 0
        var touching = false
        var received = 0.0
    }
    private let lock = NSLock()
    private var frames: [UInt64: Frame] = [:]
    private var running = false
    private var allowTap = false
    private var allowClick = false
    private var generation = 0
    private var lastPhysicalClick: [UInt64: Double] = [:]
    private var session = TrackpadMiddleSession()
    private var interceptor: Interceptor?
    private var watchdog: Timer?
    private(set) var status = NSLocalizedString("Trackpad middle-click is off", comment: "Middle-click status")
    var enabled: Bool { UserDefaults.standard.bool(forKey: Key.enabled) }
    var tapEnabled: Bool { UserDefaults.standard.object(forKey: Key.tap) as? Bool ?? true }
    var clickEnabled: Bool { UserDefaults.standard.object(forKey: Key.click) as? Bool ?? true }

    func configure(enabled: Bool? = nil, tap: Bool? = nil, click: Bool? = nil) {
        if let enabled { UserDefaults.standard.set(enabled, forKey: Key.enabled) }
        if let tap { UserDefaults.standard.set(tap, forKey: Key.tap) }
        if let click { UserDefaults.standard.set(click, forKey: Key.click) }
        stop(); start()
    }

    func start() {
        guard !running else { return }
        guard enabled else { publish(NSLocalizedString("Trackpad middle-click is off", comment: "Middle-click status")); return }
        guard AXIsProcessTrusted() else {
            publish(NSLocalizedString("Accessibility approval is required", comment: "Middle-click status")); return
        }
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
            .compactMap { UserDefaults.standard.persistentDomain(forName: $0) }
        let dragConflict = domains.contains { ($0["TrackpadThreeFingerDrag"] as? Bool) == true }
        let tapConflict = domains.contains { ($0["TrackpadThreeFingerTapGesture"] as? Int ?? 0) != 0 }
        lock.lock(); running = true; allowTap = tapEnabled && !tapConflict
        allowClick = clickEnabled && !dragConflict; lock.unlock()
        let count = MCStartTrackpadFrames { device, count, x, y, contact, touching, _ in
            TrackpadMiddleController.shared.receive(device: device, count: Int(count),
                point: CGPoint(x: x, y: y), contact: contact, touching: touching)
        }
        guard count > 0 else {
            stop(); publish(NSLocalizedString("No supported trackpad was found. Reconnect it and toggle this feature again.", comment: "Middle-click status")); return
        }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        do {
            interceptor = try Interceptor(event: mask, handleBy: Self.callback,
                listenOn: .cgSessionEventTap, placeAt: .headInsertEventTap, for: .defaultTap)
            interceptor?.onRestart = { TrackpadMiddleController.shared.cancelHeldClick() }
        } catch {
            stop(); publish(NSLocalizedString("Trackpad middle-click could not start", comment: "Middle-click status")); return
        }
        if tapConflict && tapEnabled {
            publish(NSLocalizedString("Tap is paused: macOS assigns three-finger tap to Look Up. Change that in Trackpad settings, then toggle this feature.", comment: "Middle-click conflict"))
        } else if dragConflict && clickEnabled {
            publish(NSLocalizedString("Physical click is paused while macOS three-finger drag is enabled.", comment: "Middle-click conflict"))
        } else { publish(NSLocalizedString("Trackpad middle-click is ready", comment: "Middle-click status")) }
    }

    func stop() {
        lock.lock(); running = false; allowTap = false; allowClick = false; generation += 1
        frames.removeAll(); lastPhysicalClick.removeAll(); lock.unlock()
        cancelHeldClick(); interceptor?.stop(); interceptor = nil; MCStopTrackpadFrames()
    }

    private func receive(device: UInt64, count: Int, point: CGPoint, contact: Int32, touching: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard running else { lock.unlock(); return }
        var frame = frames[device] ?? Frame()
        let tap = frame.recognizer.update(count: count, point: point, contact: contact, touching: touching, time: now)
        frame.count = count; frame.touching = touching; frame.received = now; frames[device] = frame
        let shouldPost = tap && allowTap
        let epoch = generation
        lock.unlock()
        if shouldPost {
            // Let a queued physical click invalidate the tap before posting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let active = self.running && self.allowTap && self.generation == epoch &&
                    now - (self.lastPhysicalClick[device] ?? -.infinity) > 0.35
                self.lock.unlock()
                guard active, !CompanionSettings.shared.isExcluded(NSWorkspace.shared.frontmostApplication) else { return }
                self.postClick(down: true); self.postClick(down: false)
            }
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelHeldClick(); return Unmanaged.passUnretained(event)
        }
        let device = MCTrackpadDeviceForEvent(event)
        if type == .leftMouseDown {
            lock.lock()
            let frame = frames[device]
            let eligible = running && allowClick && frame?.count == 3 && frame?.touching == true &&
                ProcessInfo.processInfo.systemUptime - (frame?.received ?? 0) < 0.20
            for key in frames.keys where frames[key]?.count == 3 {
                frames[key]?.recognizer.physicalClick()
                lastPhysicalClick[key] = ProcessInfo.processInfo.systemUptime
            }
            lock.unlock()
            guard !CompanionSettings.shared.isExcluded(NSWorkspace.shared.frontmostApplication),
                  session.begin(device: device, threeFingers: eligible) else { return Unmanaged.passUnretained(event) }
            event.type = .otherMouseDown
            watchdog?.invalidate()
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                if !MCPhysicalMouseButtonDown(0) { self?.cancelHeldClick() }
            }
        } else if type == .leftMouseUp {
            guard session.end(device: device) else { return Unmanaged.passUnretained(event) }
            watchdog?.invalidate(); watchdog = nil
            event.type = .otherMouseUp
        } else if type == .leftMouseDragged {
            guard session.matches(device) else { return Unmanaged.passUnretained(event) }
            event.type = .otherMouseDragged
        } else { return Unmanaged.passUnretained(event) }
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return Unmanaged.passUnretained(event)
    }

    /// Allows the window-sizing interceptor to pass trackpad middle clicks through,
    /// including after that interceptor has been restarted or moved ahead of this one.
    func handlesPhysicalClick(_ event: CGEvent) -> Bool {
        lock.lock(); let active = running && allowClick; lock.unlock()
        guard active else { return false }
        let device = MCTrackpadDeviceForEvent(event)
        if session.matches(device) { return true }
        guard !CompanionSettings.shared.isExcluded(NSWorkspace.shared.frontmostApplication) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let frame = frames[device] else { return false }
        return device != 0 && frame.count == 3 && frame.touching &&
            ProcessInfo.processInfo.systemUptime - frame.received < 0.20
    }

    private func cancelHeldClick() {
        watchdog?.invalidate(); watchdog = nil
        lock.lock()
        for key in frames.keys { frames[key]?.recognizer.physicalClick() }
        lock.unlock()
        if session.cancel() { postClick(down: false) }
    }
    private func postClick(down: Bool) {
        guard let source = CGEventSource(stateID: .privateState), let cursor = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: source, mouseType: down ? .otherMouseDown : .otherMouseUp,
                                  mouseCursorPosition: cursor, mouseButton: .center) else { return }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.eventSourceUserData, value: 0x4D434D43)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }
    private func publish(_ value: String) {
        status = value; NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        TrackpadMiddleController.shared.handle(type: type, event: event)
    }
}
