import Cocoa
import CoreVideo

struct DockSwipePacket: Equatable {
    let motion: Int32
    let progress: Double
    let phase: UInt32
    let velocity: Double
}

/// One axis and one destination per hold. Progress can reverse to zero; it never
/// crosses into the opposite action. The native Dock decides how an ended swipe settles.
struct ContinuousGestureState {
    let direction: GestureDirection
    let motion: Int32
    let nativeSign: Double
    let scale: Double
    let limit: Double
    private(set) var progress: Double = 0
    private var velocity: Double = 0
    private var previousTime: Double?
    private var lastDelta = 0.0
    private var begun = false
    private var dirty = false
    private var finished = false

    init?(direction: GestureDirection, action: CompanionAction, screen: CGSize, spaces: Int, sensitivity: Double) {
        self.direction = direction
        let horizontal = direction == .left || direction == .right
        switch (horizontal, action) {
        case (true, .moveSpaceRight): motion = 1; nativeSign = -1
        case (true, .moveSpaceLeft): motion = 1; nativeSign = 1
        case (false, .missionControl): motion = 2; nativeSign = 1
        case (false, .appExpose): motion = 2; nativeSign = -1
        default: return nil
        }
        guard screen.width > 0, screen.height > 0, sensitivity.isFinite, sensitivity > 0 else { return nil }
        limit = horizontal ? (spaces <= 1 ? 2 : 1 + 1 / Double(spaces - 1)) : 1
        scale = limit / Double(horizontal ? screen.width : screen.height) * sensitivity
    }
    mutating func move(dx: Double, dy: Double, time: Double) {
        guard !finished, dx.isFinite, dy.isFinite, time.isFinite else { return }
        let projected: Double
        switch direction { case .left: projected = -dx; case .right: projected = dx; case .up: projected = -dy; case .down: projected = dy }
        let next = min(limit, max(0, progress + projected * scale))
        if next != progress { lastDelta = next - progress }
        if let previousTime, time > previousTime {
            let sample = (next - progress) / max(0.001, time - previousTime)
            velocity = min(20, max(-20, velocity * 0.5 + sample * 0.5))
        }
        previousTime = time; dirty = dirty || next != progress; progress = next
    }
    mutating func frame() -> DockSwipePacket? {
        guard !finished else { return nil }
        if !begun {
            // Retain the initial signed motion in began. In particular, a vertical
            // stream must identify its opening direction in its first packet.
            guard progress > 0 else { return nil }
            begun = true; dirty = false
            return DockSwipePacket(motion: motion, progress: nativeSign * progress, phase: 1, velocity: 0)
        }
        guard dirty else { return nil }
        dirty = false
        return DockSwipePacket(motion: motion, progress: nativeSign * progress, phase: 2, velocity: 0)
    }
    mutating func end(cancel: Bool, time: Double) -> [DockSwipePacket] {
        guard !finished else { return [] }
        var output: [DockSwipePacket] = []
        if !begun, progress == 0 { finished = true; return [] }
        if !begun, let begin = frame() { output.append(begin) }
        if dirty, let changed = frame() { output.append(changed) }
        let cancelled = cancel || progress < 0.0001 || lastDelta < 0
        let recent = previousTime.map { time - $0 < 0.12 } ?? false
        output.append(DockSwipePacket(motion: motion, progress: nativeSign * progress,
            phase: cancelled ? 8 : 4, velocity: cancelled || !recent ? 0 : nativeSign * velocity))
        finished = true
        return output
    }
}

private final class ContinuousGestureSession {
    static let queue = DispatchQueue(label: "com.github.FridgeSharon.MacCompanion.native-gesture", qos: .userInteractive)
    private let lock = NSLock()
    private var state: ContinuousGestureState
    private var queued = false
    private var finished = false
    private var tracedChange = false
    init(state: ContinuousGestureState) { self.state = state }
    func move(dx: Double, dy: Double) {
        lock.lock(); defer { lock.unlock() }
        state.move(dx: dx, dy: dy, time: ProcessInfo.processInfo.systemUptime)
    }
    func enqueueFrame() {
        lock.lock()
        guard !finished, !queued else { lock.unlock(); return }
        queued = true; lock.unlock()
        Self.queue.async {
            self.lock.lock(); self.queued = false
            let packet = self.finished ? nil : self.state.frame()
            self.lock.unlock()
            if let packet { self.post(packet) }
        }
    }
    func finish(cancel: Bool) {
        Self.queue.async {
            self.lock.lock()
            let packets = self.finished ? [] : self.state.end(cancel: cancel, time: ProcessInfo.processInfo.systemUptime)
            self.finished = true; self.lock.unlock()
            for packet in packets { self.post(packet) }
        }
    }
    private func post(_ packet: DockSwipePacket) {
        let posted = MCPostDockSwipe(packet.motion, packet.progress, packet.phase, packet.velocity)
        if packet.phase != 2 || !tracedChange {
            if packet.phase == 2 { tracedChange = true }
            CompanionGestureDiagnostics.record(["event": "packet", "phase": packet.phase, "motion": packet.motion, "progress": packet.progress, "posted": posted])
        }
        if !posted {
            DispatchQueue.main.async { ContinuousGestureEmitter.shared.disableForSession() }
        }
    }
}

final class ContinuousGestureEmitter {
    static let shared = ContinuousGestureEmitter()
    private let bridgeAvailable = MCNativeGestureBridgeAvailable() && MCNativeGestureBridgeRoundTrip()
    private var disabled = false
    private var active: ContinuousGestureSession?
    private var link: CVDisplayLink?
    private struct Display { let frame: CGRect; let id: CGDirectDisplayID; let spaces: Int }
    private var displays: [Display] = []
    private var primaryTop: CGFloat = 0
    private var tokens: [NSObjectProtocol] = []
    func start() {
        guard tokens.isEmpty else { return }
        refreshDisplays()
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            CompanionGestureController.shared.cancel(); self?.refreshDisplays()
        })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() })
    }
    private func refreshDisplays() {
        primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let display = number.uint32Value
            let spaces = CGDisplayCreateUUIDFromDisplayID(display).map {
                Int(MCSpaceCountForDisplay(CFUUIDCreateString(nil, $0.takeRetainedValue()) as String))
            } ?? 1
            return Display(frame: screen.frame, id: display, spaces: spaces)
        }
    }
    var available: Bool { bridgeAvailable && !disabled }
    var status: String {
        NSLocalizedString(available ? "Continuous gestures available · experimental" : "Continuous gestures unavailable · using actions", comment: "Gesture backend status")
    }
    func begin(direction: GestureDirection, action: CompanionAction, at point: CGPoint, sensitivity: Double) -> Bool {
        guard available, active == nil else { return false }
        let appKitPoint = CGPoint(x: point.x, y: primaryTop - point.y)
        guard let display = displays.first(where: { $0.frame.contains(appKitPoint) }) else { return false }
        guard let state = ContinuousGestureState(direction: direction, action: action, screen: display.frame.size,
            spaces: display.spaces, sensitivity: sensitivity) else { return false }
        let session = ContinuousGestureSession(state: state)
        var newLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithCGDisplay(display.id, &newLink) == kCVReturnSuccess, let newLink else { return false }
        CVDisplayLinkSetOutputCallback(newLink, { _, _, _, _, _, context in
            if let context { Unmanaged<ContinuousGestureSession>.fromOpaque(context).takeUnretainedValue().enqueueFrame() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(session).toOpaque())
        active = session; link = newLink
        guard CVDisplayLinkStart(newLink) == kCVReturnSuccess else { active = nil; link = nil; return false }
        return true
    }
    func move(dx: Double, dy: Double) { active?.move(dx: dx, dy: dy) }
    func end(cancel: Bool = false) {
        if let link { CVDisplayLinkStop(link) }; link = nil
        let ending = active; active = nil
        ending?.finish(cancel: cancel)
    }
    func disableForSession() { disabled = true; end(cancel: true) }
}

/// Opt-in sparse diagnostics, always written off the input callback.
enum CompanionGestureDiagnostics {
    private static let enabled = ProcessInfo.processInfo.arguments.contains("--companion-diagnostics")
    private static let queue = DispatchQueue(label: "com.github.FridgeSharon.MacCompanion.gesture-diagnostics", qos: .utility)
    private static var events: [[String: Any]] = []
    static func observeNative(_ event: CGEvent) {
        guard enabled, event.getIntegerValueField(.eventSourceUserData) != 0x4D434753, let copy = event.copy() else { return }
        queue.async {
            if let summary = MCCopyDockSwipeSummary(copy) as? [String: Any] { record(summary) }
        }
    }
    static func record(_ event: [String: Any]) {
        guard enabled else { return }
        queue.async {
            events.append(event); events = Array(events.suffix(100))
            if let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: "/private/tmp/mac-companion-gestures.json"), options: .atomic)
            }
        }
    }
}
