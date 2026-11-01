import Cocoa

enum StageEdge { case left, right }

enum StageLayout {
    static let fractions: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1, height: 1),
        CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        CGRect(x: 0, y: 0, width: 1, height: 0.5), CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
        CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    ]
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
    static func reservedFrame(_ frame: CGRect, width: CGFloat, edge: StageEdge) -> CGRect {
        guard width.isFinite, width > 0, width < frame.width / 2 else { return frame }
        return CGRect(x: frame.minX + (edge == .left ? width : 0), y: frame.minY,
                      width: frame.width - width, height: frame.height)
    }
    static func rect(_ fraction: CGRect, in frame: CGRect, margin: CGFloat = 0) -> CGRect {
        CGRect(x: frame.minX + frame.width * fraction.minX, y: frame.minY + frame.height * fraction.minY,
               width: frame.width * fraction.width, height: frame.height * fraction.height).insetBy(dx: margin, dy: margin)
    }
    /// Recognize only standard native layouts. Already-correct frames and arbitrary floating
    /// windows produce no correction, so repeated AX notifications cannot keep shrinking them.
    static func correction(for window: CGRect, visibleFrame: CGRect, width: CGFloat, edge: StageEdge) -> CGRect? {
        let usable = reservedFrame(visibleFrame, width: width, edge: edge)
        guard usable != visibleFrame, window.width > 0, window.height > 0 else { return nil }
        for margin: CGFloat in [0, 8] {
            if fractions.contains(where: { near(window, rect($0, in: usable, margin: margin)) }) { return nil }
        }
        for margin: CGFloat in [0, 8] {
            if let fraction = fractions.first(where: { near(window, rect($0, in: visibleFrame, margin: margin), tolerance: 5) }) {
                return rect(fraction, in: usable, margin: margin).integral
            }
        }
        return nil
    }
}

/// Bounded, per-window write guard. Native tiling may reassert its geometry; after two
/// attempts at the same source frame we yield instead of fighting WindowManager.
struct StageCorrectionHistory {
    private(set) var source: CGRect?
    private(set) var target: CGRect?
    private(set) var attempts = 0
    private(set) var lastAttempt: TimeInterval = 0
    mutating func permits(source: CGRect, target: CGRect, now: TimeInterval) -> Bool {
        if let oldSource = self.source, StageLayout.near(oldSource, source),
           let oldTarget = self.target, StageLayout.near(oldTarget, target), now - lastAttempt < 3 {
            guard attempts < 2 else { return false }
            attempts += 1
        } else { attempts = 1 }
        self.source = source; self.target = target; lastAttempt = now
        return true
    }
}

/// Keep retry guards only as long as their windows exist. A long-lived app can
/// create/close arbitrarily many windows without accumulating correction state.
struct StageWindowRecords {
    var history: [String: StageCorrectionHistory] = [:]
    var suppressed: Set<String> = []

    static func key(pid: pid_t, hash: CFHashCode) -> String { "\(pid):\(hash)" }
    mutating func removeAll() { history.removeAll(); suppressed.removeAll() }
    mutating func retainWindows(pid: pid_t, hashes: Set<CFHashCode>) {
        guard !history.isEmpty || !suppressed.isEmpty else { return }
        let prefix = "\(pid):"
        let live = Set(hashes.map { Self.key(pid: pid, hash: $0) })
        history = history.filter { !$0.key.hasPrefix(prefix) || live.contains($0.key) }
        suppressed = suppressed.filter { !$0.hasPrefix(prefix) || live.contains($0) }
    }
}
