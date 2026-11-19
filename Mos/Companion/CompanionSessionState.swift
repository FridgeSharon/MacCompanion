import Cocoa

/// Waking a display does not necessarily reactivate this user's session.
struct CompanionSessionState {
    private var awake = true
    private var active = true
    var isInteractive: Bool { awake && active }

    /// Returns true only when services should actually suspend or resume.
    @discardableResult
    mutating func receive(_ name: Notification.Name) -> Bool {
        let previous = isInteractive
        switch name {
        case NSWorkspace.willSleepNotification: awake = false
        case NSWorkspace.didWakeNotification: awake = true
        case NSWorkspace.sessionDidResignActiveNotification: active = false
        case NSWorkspace.sessionDidBecomeActiveNotification: active = true
        default: break
        }
        return previous != isInteractive
    }
}
