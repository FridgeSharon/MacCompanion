import Cocoa

/// Permit one queued or executing lookup at a time. An unresponsive AX server
/// must not make high-frequency input retain an unbounded backlog of work.
final class BoundedWindowWork {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending = false

    init(queue: DispatchQueue) { self.queue = queue }

    @discardableResult func submit(_ work: @escaping () -> Void) -> Bool {
        lock.lock()
        guard !pending else { lock.unlock(); return false }
        pending = true
        lock.unlock()
        queue.async {
            defer { self.lock.lock(); self.pending = false; self.lock.unlock() }
            work()
        }
        return true
    }
}

/// Some Catalyst accessibility servers return the nearest control rather than
/// the element under a blank point. Resolve from actual rectangles, retaining
/// real controls and giving up when an unpositioned control makes the hit unsafe.
enum BoundedAccessibilityHit {
    static func resolve<Node>(_ initial: Node, at point: CGPoint, frame: (Node) -> CGRect?,
        parent: (Node) -> Node?, children: (Node) -> [Node], isControl: (Node) -> Bool) -> Node? {
        func contains(_ rect: CGRect) -> Bool { !rect.isEmpty && rect.insetBy(dx: -0.5, dy: -0.5).contains(point) }
        var candidate: Node? = initial
        for _ in 0..<20 {
            guard let node = candidate else { return nil }
            if let rect = frame(node), contains(rect) {
                var current = node
                for _ in 0..<12 {
                    if isControl(current) { return current }
                    let descendants = Array(children(current).prefix(80))
                    let positioned = descendants.compactMap { child -> (Node, CGRect)? in
                        guard let rect = frame(child), contains(rect) else { return nil }
                        return (child, rect)
                    }
                    if let smallest = positioned.min(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) {
                        current = smallest.0
                    } else {
                        if descendants.contains(where: { isControl($0) && frame($0) == nil }) { return nil }
                        return current
                    }
                }
                return nil
            }
            candidate = parent(node)
        }
        return nil
    }
}
