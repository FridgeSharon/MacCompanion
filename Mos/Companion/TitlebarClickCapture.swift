import Cocoa

/// A verified first click authorizes interception of only its matching second
/// title-bar press/release. Unverified controls and ordinary clicks fail open.
struct TitlebarClickCapture {
    enum Down: Equatable { case pass, inspect(UInt64), capture }
    enum Up: Equatable { case pass, consume, commit }
    private struct First {
        let ticket: UInt64
        let point: CGPoint
        let time: Double
        var window: UInt32 = 0
        var pid: Int32 = 0
        var verified = false
        var released = false
    }
    private struct Pending { let point: CGPoint; var cancelled = false }
    private var serial: UInt64 = 0
    private var first: First?
    private var pending: Pending?
    var isCapturing: Bool { pending != nil }

    mutating func down(count: Int, window: UInt32, frontPID: Int32, point: CGPoint, time: Double, interval: Double) -> Down {
        // A fresh down proves a previously owned release was lost. Never let
        // that stale pair swallow the new click's up and leave the app dragging.
        if pending != nil { pending = nil; first = nil }
        if count > 0 && count % 2 == 1 {
            serial &+= 1
            first = First(ticket: serial, point: point, time: time)
            return .inspect(serial)
        }
        guard count > 0, count % 2 == 0, let first, first.verified, first.released,
              time >= first.time, time - first.time <= interval, near(first.point, point),
              (window == first.window || (window == 0 && frontPID == first.pid)) else {
            first = nil; return .pass
        }
        self.first = nil; pending = Pending(point: point)
        return .capture
    }
    @discardableResult mutating func confirm(ticket: UInt64, window: UInt32, pid: Int32, titlebar: Bool) -> Bool {
        guard var first, first.ticket == ticket else { return false }
        first.window = window; first.pid = pid; first.verified = titlebar && window != 0 && pid > 0
        self.first = first
        return first.verified
    }
    mutating func up(at point: CGPoint) -> Up {
        if let pending {
            self.pending = nil
            return !pending.cancelled && near(pending.point, point) ? .commit : .consume
        }
        if var first { first.released = near(first.point, point); self.first = first }
        return .pass
    }
    /// Keep the swallowed release balanced even when a gesture is cancelled.
    mutating func cancel() { first = nil; pending?.cancelled = true }
    mutating func reset() { first = nil; pending = nil }
    private func near(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool { abs(lhs.x - rhs.x) <= 5 && abs(lhs.y - rhs.y) <= 5 }
}
