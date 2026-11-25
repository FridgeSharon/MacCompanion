//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

class ScrollPoster {

    // 单例
    static let shared = ScrollPoster(dispatchContext: .shared, usesDisplayLink: true)

    private init(dispatchContext: ScrollDispatchContext, usesDisplayLink: Bool) {
        self.dispatchContext = dispatchContext
        self.usesDisplayLink = usesDisplayLink
        NSLog("Module initialized: ScrollPoster")
    }

#if DEBUG
    convenience init() {
        self.init(dispatchContext: ScrollDispatchContext(testDelivery: { _ in }), usesDisplayLink: true)
    }

    convenience init(testDispatchContext: ScrollDispatchContext) {
        self.init(dispatchContext: testDispatchContext, usesDisplayLink: false)
    }

    func processFrameForTests() {
        processing(now: lastManualEventTime)
    }
#endif

    // 插值器
    private let filter = ScrollFilter()
    // 发送器
    // The main run loop owns the link and its timers. Its output callback only
    // accesses stream state protected by stateLock.
    private var poster: CVDisplayLink?
    // 滚动数据
    private var current = (y: 0.0, x: 0.0)  // 当前滚动距离
    private var delta = (y: 0.0, x: 0.0)  // 滚动方向记录
    private var buffer = (y: 0.0, x: 0.0)  // 滚动缓冲距离
    // 滚动配置
    private var shifting = false
    private var duration = 0.0
    // 输入节奏追踪
    private var lastManualEventTime: CFTimeInterval = 0.0
    private var manualInputEnded = true
    private var momentumActive = false
    private var momentumEndScheduledTime: CFTimeInterval? = nil
    private var trackingEndScheduledTime: CFTimeInterval? = nil
    // 阈值: 鼠标滚轮事件间隔低于 continuationThreshold 视为持续跟随
    //      介于 continuationThreshold 与 separationThreshold 之间模拟惯性衔接
    private let manualContinuationThreshold: CFTimeInterval = 0.18
    private let manualSeparationThreshold: CFTimeInterval = 0.45
    private let trackingEndAdvance: CFTimeInterval = 0.04
    private let momentumEndDelay: CFTimeInterval = 0.13
    // 状态锁和投递上下文
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext: ScrollDispatchContext
    private let usesDisplayLink: Bool
    private let scrollPhase = ScrollPhase()
    private var targetPID: pid_t = 0
    private var targetIsChrome = false
    private var inputSequence: UInt64 = 0
    private var finishPending = false
    // 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        var simTrackpadEnabled: Bool
        var deadZone: Double
    }
    private var config = ConfigSnapshot(simTrackpadEnabled: false, deadZone: 1.0)
    // CVDisplayLink 恢复机制
    private var keeper: Timer?
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0
    // CVDisplayLink 刷新率自纠 (issue #958):
    // 显示器唤醒/重连时会先短暂报告过渡刷新率 (如先 60Hz 再升 144Hz), 若重建正好落在这个窗口,
    // 就会把 link 绑到偏低的刷新率, 使平滑滚动只按低帧率绘制 (卡顿), 而现有恢复机制识别不了.
    // 对策: 每次建立 link 后延迟复查若干次, 发现 link 标称率明显低于显示器实际率就重建追平.
    private var rateVerifyTimer: Timer?
    private var rateVerifyAttemptsLeft = 0
    private var isVerifying = false
    private let rateVerifyDelays: [TimeInterval] = [2.0, 4.0, 8.0]
    private let rateVerifyRatio = 0.7
    // 主线程访问, 无需锁
    var isAvailable: Bool { return poster != nil }
    var isRunning: Bool { poster.map { CVDisplayLinkIsRunning($0) } ?? false }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func handleInput(
        event: CGEvent, targetIsChrome: Bool, duration: Double, y: Double, x: Double,
        speed: Double, amplification: Double = 1, simTrackpadEnabled: Bool, deadZone: Double
    ) -> Bool {
        guard let pid = pid_t(exactly: event.getIntegerValueField(.eventTargetUnixProcessID)),
              pid > 1 else { return false }
        guard let template = event.copy() else {
#if DEBUG
            dispatchContext.recordUpdateSnapshotFailure()
#endif
            return false
        }
        guard !usesDisplayLink || tryStart() else { return false }

        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        if targetPID != 0 && targetPID != pid {
            // Close the old scroll sequence with its own target and settings.
            finishUnlocked(.MomentumEnd, discardQueuedFrames: true)
        }
        targetPID = pid
        self.targetIsChrome = targetIsChrome
        dispatchContext.capture(template: template, targetPID: pid)
        inputSequence &+= 1
        finishPending = false
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
        config = ConfigSnapshot(simTrackpadEnabled: simTrackpadEnabled, deadZone: deadZone)
        // 更新滚动配置
        self.duration = duration
        // 更新滚动数据
        if y*delta.y > 0 {
            buffer.y += y * speed * amplification
        } else {
            buffer.y = y * speed * amplification
            current.y = 0.0
        }
        if x*delta.x > 0 {
            buffer.x += x * speed * amplification
        } else {
            buffer.x = x * speed * amplification
            current.x = 0.0
        }
        delta = (y: y, x: x)
        let now = CFAbsoluteTimeGetCurrent()
        let interval = lastManualEventTime > 0.0 ? now - lastManualEventTime : nil
        let separatedByTime = interval == nil ? true : interval! >= manualSeparationThreshold
        let phase = scrollPhase.phase
        let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
        let plan = scrollPhase.onManualInputDetected(isSeparated: separated)
        perform(plan, emitTargetImmediately: false)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        return true
    }
    func updateShifting(enable: Bool) {
        os_unfair_lock_lock(&stateLock)
        shifting = enable
        os_unfair_lock_unlock(&stateLock)
    }
    func shift(with nextValue: ( y: Double, x: Double )) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if shifting {
            // 判断哪个轴有值, 有值则赋给 X
            // 某些鼠标 (MXMaster/MXAnywhere), 按下 Shift 后会显式转换方向为横向, 此处针对这类转换进行归一化处理
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: nextValue.x, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        } else {
            return (y: nextValue.y, x: nextValue.x)
        }
    }
#if DEBUG
    func recordSkippedSyntheticEvent() {
        dispatchContext.recordSkippedSyntheticEvent()
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        dispatchContext.diagnosticsSnapshot()
    }
#endif

    private func resetUnlocked() {
        // 重置数值
        dispatchContext.clearContext()
        targetPID = 0
        targetIsChrome = false
        finishPending = false
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
        // 重置插值器
        filter.reset()
        scrollPhase.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    // 初始化 CVDisplayLink
    func create() {
        // 清理旧的 CVDisplayLink
        if let old = poster {
            if CVDisplayLinkIsRunning(old) {
                CVDisplayLinkStop(old)
            }
            poster = nil
        }
        // Display sleep can leave online displays with zero active displays.
        // CoreVideo rejects that state; the keeper/display-change notification
        // will retry after wake without flooding the log or allocating failed links.
        var activeDisplayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &activeDisplayCount) == .success,
              activeDisplayCount > 0 else { return }
        // 创建新的 CVDisplayLink, 检查返回值
        var newPoster: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&newPoster)
        if result == kCVReturnSuccess, let validPoster = newPoster {
            let handlerResult = CVDisplayLinkSetOutputHandler(validPoster) { [weak self] _, _, _, _, _ in
                self?.processing()
                return kCVReturnSuccess
            }
            guard handlerResult == kCVReturnSuccess else {
                NSLog("ScrollPoster: CVDisplayLink callback registration failed (%d)", handlerResult)
                return
            }
            poster = validPoster
            // 建立成功后安排刷新率复查; 复查内部触发的重建 (isVerifying) 不重置复查序列
            if !isVerifying { scheduleRateVerify() }
        } else {
            poster = nil
            NSLog("ScrollPoster: CVDisplayLink creation failed (%d)", result)
        }
    }
    private func startDisplayLink(_ link: CVDisplayLink) -> Bool {
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else { return false }
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&stateLock)
        return true
    }

    private func tryStart() -> Bool {
        if let link = poster, CVDisplayLinkIsRunning(link) || startDisplayLink(link) {
            return true
        }
        return recreateDisplayLink(startForInput: true)
    }

    func stop() {
        stop(.MomentumEnd, discardQueuedFrames: true)
    }

    private func stop(_ requestedPhase: Phase, discardQueuedFrames: Bool) {
        // Never call CVDisplayLinkStop from its output callback. CoreVideo can
        // wait for that callback to return, including when a display changes.
        if let link = poster, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        os_unfair_lock_lock(&stateLock)
        finishUnlocked(requestedPhase, discardQueuedFrames: discardQueuedFrames)
        os_unfair_lock_unlock(&stateLock)
    }

    private func finishUnlocked(_ requestedPhase: Phase, discardQueuedFrames: Bool) {
        if discardQueuedFrames {
            dispatchContext.advanceGeneration()
        }

        // 判断是否启用触控板模拟 (读 update 时主线程捕获的快照, 避免跨线程读)
        let enableSimTrackpad = config.simTrackpadEnabled
        let plan: ScrollPhase.TransitionPlan
        if requestedPhase == Phase.MomentumEnd {
            plan = scrollPhase.onMomentumFinish()
        } else {
            plan = scrollPhase.onManualInputEnded()
        }

        // 发送结束事件
        if enableSimTrackpad {
            perform(plan, emitTargetImmediately: true)
        } else {
            if targetIsChrome,
               let snapshot = dispatchContext.preparePostingSnapshot(),
               let phaseValues = phaseValues(for: .TrackingEnd) {
                _ = post(
                    snapshot,
                    (y: 0.0, x: 0.0),
                    phaseOverride: phaseValues,
                    fallbackToCurrentPhase: false
                )
            }
        }
        resetUnlocked()
    }

    // 重建 CVDisplayLink (带冷却期)
    @discardableResult
    func recreateDisplayLink(startForInput: Bool = false) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        let wasRunning = isRunning
        create()
        guard let validPoster = poster else {
            if wasRunning { stop() }
            return false
        }
        // Recovery after display wake must not create a permanent idle frame
        // loop. Start only for pending input or to resume an existing stream.
        guard wasRunning || startForInput else { return true }
        guard startDisplayLink(validPoster) else {
            if wasRunning { stop() }
            NSLog("ScrollPoster: CVDisplayLink start failed after recreate")
            return false
        }
        return true
    }
    // 守护定时器 (与 Interceptor 的 keeper 模式一致)
    func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }
    func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
        rateVerifyTimer?.invalidate()
        rateVerifyTimer = nil
        rateVerifyAttemptsLeft = 0
    }
    private func healthCheck() {
        guard let validPoster = poster else {
            recreateDisplayLink()
            return
        }
        if CVDisplayLinkIsRunning(validPoster) {
            os_unfair_lock_lock(&stateLock)
            let lastTime = lastCallbackTime
            os_unfair_lock_unlock(&stateLock)
            // lastTime > 0 避免首次回调前误判
            if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
                NSLog("ScrollPoster: zombie CVDisplayLink detected, recreating")
                recreateDisplayLink()
            }
        }
    }

    // MARK: 刷新率自纠 (见属性处说明)
    // 建立 link 后调用: 重置复查序列并安排第一次复查
    private func scheduleRateVerify() {
        rateVerifyAttemptsLeft = rateVerifyDelays.count
        armNextRateVerify()
    }
    private func armNextRateVerify() {
        rateVerifyTimer?.invalidate()
        guard rateVerifyAttemptsLeft > 0 else { rateVerifyTimer = nil; return }
        let delay = rateVerifyDelays[rateVerifyDelays.count - rateVerifyAttemptsLeft]
        rateVerifyTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.verifyRateAndFixIfNeeded()
        }
    }
    // 复查: link 标称率明显低于显示器实际率 -> 重建追平 (幂等, 不受 recreateCooldown 限制)
    private func verifyRateAndFixIfNeeded() {
        rateVerifyAttemptsLeft -= 1
        guard let current = poster else { rateVerifyTimer = nil; return }
        let nominal = linkNominalHz(current)
        let maxHz = maxActiveDisplayHz()
        guard nominal > 1, maxHz > 1, nominal < maxHz * rateVerifyRatio else {
            // 已追平显示器刷新率, 结束复查
            rateVerifyTimer = nil
            rateVerifyAttemptsLeft = 0
            return
        }
        NSLog("ScrollPoster: display link rate %.0fHz below display %.0fHz, recreating", nominal, maxHz)
        // 保持原运行状态: 若正在滚动 (running) 则重建后重新启动
        let wasRunning = CVDisplayLinkIsRunning(current)
        isVerifying = true
        create()
        isVerifying = false
        if wasRunning && poster.map(startDisplayLink) != true {
            stop()
        }
        // 自纠说明显示器仍在过渡: 清除冷却, 让后续 screenChange 能及时用最终配置重建
        lastRecreateAttempt = 0
        // 这次重建可能仍落在过渡态, 继续后续复查直到追平或用尽次数
        armNextRateVerify()
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool, delta: (y: Double, x: Double) = (0.0, 0.0)) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            emitPhase(item, delta: delta)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target, delta: delta)
            } else {
                scrollPhase.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    func emitPhase(_ item: (Phase, Phase?), delta: (y: Double, x: Double)) {
        scrollPhase.apply(phase: item.0, autoAdvance: item.1)
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            scrollPhase.didDeliverFrame()
            return
        }
        let phaseOverride = resolveSimTrackpadEnabled() ? phaseValues(for: item.0) : nil
        _ = post(snapshot, delta, phaseOverride: phaseOverride, fallbackToCurrentPhase: false)
    }

    // 处理滚动事件
    func processing(now: CFTimeInterval = CFAbsoluteTimeGetCurrent()) {
        var pendingStopPhase: Phase?
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = now
        guard targetPID != 0, !finishPending else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        // 计算插值
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: duration),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: duration)
        )
        // 更新滚动位置
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )
        // 平滑滚动结果
        let filledValue = filter.fill(with: frame)
        // 变换滚动结果，将滤波后的插值映射到当前姿态（考虑灵敏度、方向等因素）
        let shiftedValue = shift(with: filledValue)
        // 检测是否已经超过手动输入的持续时间阈值，准备结束手动阶段
        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > manualContinuationThreshold {
            let endPlan = scrollPhase.onManualInputEnded()
            if !(endPlan.queue.isEmpty && endPlan.target == nil) {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }
        // 计算缓冲值与当前位置的剩余距离，用于判断滚动是否已收敛
        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(residualY.magnitude, residualX.magnitude)
        let deadZone = config.deadZone
        if manualInputEnded && residualMagnitude > deadZone {
            if !momentumActive {
                perform(scrollPhase.onMomentumStart(), emitTargetImmediately: false)
                momentumActive = true
            } else {
                perform(scrollPhase.onMomentumOngoing(), emitTargetImmediately: false)
            }
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
        } else if momentumActive && residualMagnitude <= deadZone {
            if momentumEndScheduledTime == nil {
                momentumEndScheduledTime = now + momentumEndDelay
            }
        } else {
            momentumEndScheduledTime = nil
            if momentumActive {
                momentumActive = false
            }
        }
        // 发送滚动结果 - 只有当输出值超过死区阈值时才发送
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        if outputMagnitude > deadZone {
            _ = post(shiftedValue)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                pendingStopPhase = .MomentumEnd
            }
        }
        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= deadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                pendingStopPhase = .TrackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }
        guard let phase = pendingStopPhase else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        finishPending = true
        let sequence = inputSequence
        os_unfair_lock_unlock(&stateLock)
        DispatchQueue.main.async { [weak self] in
            self?.completeScroll(phase, inputSequence: sequence)
        }
    }

    func completeScroll(_ phase: Phase, inputSequence: UInt64) {
        os_unfair_lock_lock(&stateLock)
        let shouldFinish = finishPending && self.inputSequence == inputSequence
        os_unfair_lock_unlock(&stateLock)
        if shouldFinish {
            stop(phase, discardQueuedFrames: false)
        }
    }

    func resolveSimTrackpadEnabled() -> Bool {
        return config.simTrackpadEnabled
    }

    func phaseValues(for phase: Phase) -> (scroll: Double, momentum: Double)? {
        guard let scrollValue = PhaseValueMapping[phase]?[.Scroll],
              let momentumValue = PhaseValueMapping[phase]?[.Momentum] else {
            return nil
        }
        return (scroll: scrollValue, momentum: momentumValue)
    }

    @discardableResult
    func post(_ snapshot: ScrollDispatchContext.PostingSnapshot, _ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true) -> Bool {
        if let override = phaseOverride {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: override.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: override.momentum)
        } else if fallbackToCurrentPhase,
                  resolveSimTrackpadEnabled(),
                  let currentPhaseValues = phaseValues(for: scrollPhase.phase) {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: currentPhaseValues.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: currentPhaseValues.momentum)
        }
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
        // 是否连续滚动: 始终为 1.0
        snapshot.event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        ScrollUtils.shared.markSyntheticSmoothEvent(snapshot.event)
        // 通过 CGEventPostToPid 直投目标进程:
        // 不依赖 proxy (消除崩溃), 不经过 tap 链重新路由 (动量不跟随光标)
        // ref: @shichangone MR: https://github.com/Caldis/Mos/pull/523, issue #868
        dispatchContext.enqueue(snapshot)
        scrollPhase.didDeliverFrame()
        return true
    }

    @discardableResult
    func post(_ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true) -> Bool {
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            return false
        }
        return post(
            snapshot,
            v,
            phaseOverride: phaseOverride,
            fallbackToCurrentPhase: fallbackToCurrentPhase
        )
    }
}

// MARK: - 显示器刷新率查询 (刷新率自纠使用)
private extension ScrollPoster {
    /// CVDisplayLink 当前绑定显示器的标称刷新率 (Hz); 无效返回 -1
    func linkNominalHz(_ link: CVDisplayLink) -> Double {
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        // 无效/indefinite 周期时 timeValue 或 timeScale 为 0
        guard period.timeValue != 0, period.timeScale != 0 else { return -1 }
        let seconds = Double(period.timeValue) / Double(period.timeScale)
        return seconds > 0 ? 1.0 / seconds : -1
    }
    /// 当前活跃显示器里最高刷新率 (Hz); 取不到返回 -1
    func maxActiveDisplayHz() -> Double {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return -1 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return -1 }
        var mx = -1.0
        for id in ids.prefix(Int(count)) {
            if let hz = CGDisplayCopyDisplayMode(id)?.refreshRate, hz > mx { mx = hz }
        }
        return mx
    }
}
