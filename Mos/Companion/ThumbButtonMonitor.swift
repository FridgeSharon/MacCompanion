import Cocoa

/// Intercepts only auxiliary mouse buttons for the configured hold-and-move gesture.
/// All other input retains its native behavior; general input remapping is absent.
final class ThumbButtonMonitor {
    static let shared = ThumbButtonMonitor()
    private var interceptor: Interceptor?
    private(set) var isActive = false

    func enable() {
        guard !isActive else { return }
        var mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        if ProcessInfo.processInfo.arguments.contains("--companion-diagnostics") { mask |= CGEventMask(1 << 30) }
        do {
            interceptor = try Interceptor(event: mask, handleBy: Self.callback,
                listenOn: .cgSessionEventTap, placeAt: .tailAppendEventTap, for: .defaultTap)
            interceptor?.onRestart = { CompanionGestureController.shared.cancel() }
            isActive = true
        } catch {
            interceptor?.stop(); interceptor = nil
            NSLog("Thumb gesture monitor could not start: %@", String(describing: error))
        }
    }

    func disable() {
        CompanionGestureController.shared.cancel()
        interceptor?.stop(); interceptor = nil; isActive = false
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            CompanionGestureController.shared.cancel()
            return Unmanaged.passUnretained(event)
        }
        if type.rawValue == 30 {
            CompanionGestureDiagnostics.observeNative(event)
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }
        return CompanionGestureController.shared.handle(type: type, event: event)
            ? nil : Unmanaged.passUnretained(event)
    }
}
