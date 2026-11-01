import Cocoa

/// Pure recognition state: one action per press, accumulated motion, dominant axis.
/// Returning nil on release means the original click must be replayed as a balanced pair.
struct DirectionalGestureRecognizer {
    private(set) var isHeld = false
    private(set) var fired: GestureDirection?
    private var delta = CGPoint.zero

    mutating func begin() { isHeld = true; fired = nil; delta = .zero }
    mutating func move(dx: Double, dy: Double, threshold: Double) -> GestureDirection? {
        guard isHeld, fired == nil, dx.isFinite, dy.isFinite else { return nil }
        delta.x += dx; delta.y += dy
        guard max(abs(delta.x), abs(delta.y)) >= threshold else { return nil }
        let direction: GestureDirection = abs(delta.x) > abs(delta.y)
            ? (delta.x < 0 ? .left : .right) : (delta.y < 0 ? .up : .down)
        fired = direction
        return direction
    }
    mutating func end() -> Bool {
        let replay = isHeld && fired == nil
        cancel()
        return replay
    }
    mutating func cancel() { isHeld = false; fired = nil; delta = .zero }
}

final class CompanionGestureController {
    static let shared = CompanionGestureController()
    private var recognizer = DirectionalGestureRecognizer()
    private var press: CGEvent?
    private var pressConfiguration: CompanionConfiguration?
    private var continuous = false
    private var tracedMotion = false
    private var cancelledReleaseButton: Int64?
    private var anchor = CGPoint.zero
    private var activeButton: Int64?
    private var watchdog: Timer?
    private var motionInterceptor: Interceptor?
    private(set) var lastEventDescription = NSLocalizedString("Waiting for a thumb button", comment: "Gesture status")
    var isHeld: Bool { recognizer.isHeld }

    /// Invoked on the existing main-run-loop event tap. No I/O or UI work on motion.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let motion = type == .mouseMoved || type == .otherMouseDragged
        if motion {
            guard recognizer.isHeld, let button = activeButton, let config = pressConfiguration else { return false }
            if !tracedMotion {
                tracedMotion = true
                CompanionGestureDiagnostics.record(["event": "first-motion", "type": type.rawValue,
                    "held": button, "reportedButton": event.getIntegerValueField(.mouseEventButtonNumber), "pressedMask": NSEvent.pressedMouseButtons, "physicalDown": MCPhysicalMouseButtonDown(Int32(button))])
            }
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            if continuous { ContinuousGestureEmitter.shared.move(dx: dx, dy: dy) }
            else if let direction = recognizer.move(dx: dx, dy: dy, threshold: config.gestureThreshold) {
                let action = config.action(for: direction)
                lastEventDescription = direction.title + ": " + action.title
                CompanionGestureDiagnostics.record(["event": "recognized", "direction": direction.rawValue, "action": action.rawValue, "backend": config.gestureBackend.rawValue])
                continuous = config.gestureBackend == .continuous && ContinuousGestureEmitter.shared.begin(
                    direction: direction, action: action, at: anchor, sensitivity: config.gestureSensitivity)
                if !continuous { DispatchQueue.main.async { action.perform() } }
            }
            event.location = anchor
            return false
        }
        guard type == .otherMouseDown || type == .otherMouseUp else { return false }
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        if type == .otherMouseUp, cancelledReleaseButton == number {
            cancelledReleaseButton = nil; return true
        }
        if type == .otherMouseDown {
            if cancelledReleaseButton == number { cancelledReleaseButton = nil }
            lastEventDescription = String(format: NSLocalizedString("Detected mouse button %d", comment: "Gesture status"), Int(number + 1))
        }
        if type == .otherMouseUp, activeButton == number {
            let replay = recognizer.end()
            let down = press
            if continuous { ContinuousGestureEmitter.shared.end() }
            activeButton = nil
            cancel()
            if replay, let down, let up = event.copy() {
                down.timestamp = up.timestamp > 0 ? up.timestamp - 1 : 0
                down.location = anchor; up.location = anchor
                down.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
                up.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
                down.post(tap: .cgSessionEventTap); up.post(tap: .cgSessionEventTap)
            }
            return true
        }
        let config = CompanionSettings.shared.configuration
        guard config.gesturesEnabled, number == Int64(config.gestureButton), type == .otherMouseDown,
              !CompanionSettings.shared.isExcluded(NSWorkspace.shared.frontmostApplication), press == nil,
              let copy = event.copy() else { return false }
        tracedMotion = false
        CompanionGestureDiagnostics.record(["event": "press", "button": number])
        anchor = event.location; press = copy; pressConfiguration = config; activeButton = number; recognizer.begin()
        do {
            let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue) | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
            motionInterceptor = try Interceptor(event: mask, handleBy: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    CompanionGestureController.shared.cancel()
                    return Unmanaged.passUnretained(event)
                }
                _ = CompanionGestureController.shared.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }, listenOn: .cgSessionEventTap, placeAt: .tailAppendEventTap, for: .defaultTap)
            motionInterceptor?.onRestart = { CompanionGestureController.shared.cancel() }
        } catch {
            cancel()
            lastEventDescription = NSLocalizedString("Gesture input could not start; check Accessibility permission", comment: "Gesture status")
            return false
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let button = self.activeButton else { return }
            // Recover from an intercepted/lost release, device disconnection or application switch.
            // The intercepted down can be absent from combined session state.
            // Consult physical HID state before treating it as a lost release.
            let released = (NSEvent.pressedMouseButtons & (1 << Int(button))) == 0 && !MCPhysicalMouseButtonDown(Int32(button))
            if released || CompanionSettings.shared.isExcluded(NSWorkspace.shared.frontmostApplication) {
                CompanionGestureDiagnostics.record(["event": "watchdog-cancel", "released": released])
                self.cancel()
            }
        }
        return true
    }

    func cancel() {
        if let activeButton { CompanionGestureDiagnostics.record(["event": "cancel-or-release", "button": activeButton]) }
        if let activeButton { cancelledReleaseButton = activeButton }
        if continuous { ContinuousGestureEmitter.shared.end(cancel: true) }; continuous = false
        pressConfiguration = nil
        watchdog?.invalidate(); watchdog = nil
        motionInterceptor?.stop(); motionInterceptor = nil
        recognizer.cancel(); press = nil; activeButton = nil
    }
}
