//
//  ScrollDispatchContext.swift
//  Mos
//
//  Created by Codex on 2026/3/5.
//

import Cocoa
import os

final class ScrollDispatchContext {

    static let shared = ScrollDispatchContext(deliver: { snapshot in
        // Deliver to the captured process so momentum stays with its original
        // target when the pointer moves, without relying on a tap proxy.
        snapshot.event.postToPid(snapshot.targetPID)
    })

    struct PostingSnapshot {
        let event: CGEvent
        let targetPID: pid_t
        let generation: UInt64
        let capturedAt: CFTimeInterval
    }

    private struct SnapshotState {
        var eventTemplate: CGEvent?
        var targetPID: pid_t = 0
        var generation: UInt64 = 0
        var updatedAt: CFTimeInterval = 0.0
    }

    private let deliver: (PostingSnapshot) -> Void
    private var state = SnapshotState()
    private var lock = os_unfair_lock_s()
    private let postQueue = DispatchQueue(label: "me.caldis.mos.scrollposter.post", qos: .userInteractive)
    // TTL 仅作为 enqueue 投递时的兜底安全网, 不用于快照创建门控
    // 需覆盖最长惯性减速阶段 (通常 1-3s, 极端 ~5s)
#if DEBUG
    var eventTTL: CFTimeInterval = 5.0
#else
    private let eventTTL: CFTimeInterval = 5.0
#endif

#if DEBUG
    private var postedFrames: UInt64 = 0
    private var droppedFramesByGeneration: UInt64 = 0
    private var droppedFramesByTTL: UInt64 = 0
    private var skippedSyntheticEvents: UInt64 = 0
    private var updateSnapshotFailures: UInt64 = 0
#endif

    private init(deliver: @escaping (PostingSnapshot) -> Void) {
        self.deliver = deliver
    }

#if DEBUG
    convenience init(testDelivery: @escaping (PostingSnapshot) -> Void) {
        self.init(deliver: testDelivery)
    }

    func flushForTests() {
        postQueue.sync {}
    }
#endif

    // The caller supplies a private copy so partial native passthrough cannot
    // mutate the template after it is published to the display-link thread.
    func capture(template: CGEvent, targetPID: pid_t) {
        os_unfair_lock_lock(&lock)
        state.eventTemplate = template
        state.targetPID = targetPID
        state.updatedAt = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&lock)
    }

    func advanceGeneration() {
        os_unfair_lock_lock(&lock)
        state.generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func clearContext() {
        os_unfair_lock_lock(&lock)
        state.eventTemplate = nil
        state.targetPID = 0
        state.updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        guard state.targetPID != 0,
              let eventClone = state.eventTemplate?.copy() else {
            os_unfair_lock_unlock(&lock)
            return nil
        }
        let snapshot = PostingSnapshot(event: eventClone, targetPID: state.targetPID, generation: state.generation, capturedAt: state.updatedAt)
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func enqueue(_ snapshot: PostingSnapshot) {
        postQueue.async { [self] in
            os_unfair_lock_lock(&self.lock)
            let now = CFAbsoluteTimeGetCurrent()
            let validGeneration = snapshot.generation == self.state.generation
            let validTTL = now - snapshot.capturedAt <= self.eventTTL
            if !validGeneration {
#if DEBUG
                self.droppedFramesByGeneration &+= 1
#endif
            } else if !validTTL {
#if DEBUG
                self.droppedFramesByTTL &+= 1
#endif
            }
            os_unfair_lock_unlock(&self.lock)
            guard validGeneration && validTTL else { return }
            self.deliver(snapshot)
#if DEBUG
            os_unfair_lock_lock(&self.lock)
            self.postedFrames &+= 1
            os_unfair_lock_unlock(&self.lock)
#endif
        }
    }

#if DEBUG
    func recordUpdateSnapshotFailure() {
        os_unfair_lock_lock(&lock)
        updateSnapshotFailures &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func recordSkippedSyntheticEvent() {
        os_unfair_lock_lock(&lock)
        skippedSyntheticEvents &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        os_unfair_lock_lock(&lock)
        let snapshot = (
            postedFrames: postedFrames,
            droppedFramesByGeneration: droppedFramesByGeneration,
            droppedFramesByTTL: droppedFramesByTTL,
            skippedSyntheticEvents: skippedSyntheticEvents,
            updateSnapshotFailures: updateSnapshotFailures
        )
        os_unfair_lock_unlock(&lock)
        return snapshot
    }

    func resetDiagnostics() {
        os_unfair_lock_lock(&lock)
        postedFrames = 0
        droppedFramesByGeneration = 0
        droppedFramesByTTL = 0
        skippedSyntheticEvents = 0
        updateSnapshotFailures = 0
        os_unfair_lock_unlock(&lock)
    }
#endif
}
