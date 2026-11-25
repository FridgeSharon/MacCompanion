//
//  ScrollPosterStateTests.swift
//  MosTests
//
//  ScrollPoster.shift 方法测试 (Task 10)
//

import XCTest
import CoreGraphics
@testable import Mos_Debug

final class ScrollPosterStateTests: XCTestCase {

    var sut: ScrollPoster!

    override func setUp() {
        super.setUp()
        sut = ScrollPoster()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testRecreatingIdleDisplayLinkDoesNotStartAFrameLoop() throws {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            throw XCTSkip("Requires an awake display for the CoreVideo recovery check")
        }
        defer { sut.stop(); sut.stopKeeper() }
        XCTAssertTrue(sut.recreateDisplayLink())
        XCTAssertTrue(sut.isAvailable)
        XCTAssertFalse(sut.isRunning, "Display recovery must stay idle until there is scroll input")
    }

    func testUnroutableInputRemainsAvailableForNativeScrolling() throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
            wheel1: 3, wheel2: 4, wheel3: 0
        ))
        for invalidPID in [Int64(0), 1, Int64.max] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: invalidPID)
            let scroll = ScrollEvent(with: event)
            ScrollEvent.normalizeY(scroll, 100)
            XCTAssertEqual(scroll.Y.usableValue, 100)
            XCTAssertFalse(sut.handleInput(
                event: event, targetIsChrome: false, duration: 0.1, y: scroll.Y.usableValue, x: 0,
                speed: 1, simTrackpadEnabled: true, deadZone: 0.1
            ))
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 4)
            XCTAssertFalse(sut.isAvailable)
            XCTAssertFalse(sut.isRunning)
        }
    }

    func testChangingTargetEndsOldSequenceAndStartsWithoutItsResidual() throws {
        let oldPID: pid_t = 100
        let newPID: pid_t = 200
        var delivered: [ScrollDispatchContext.PostingSnapshot] = []
        let context = ScrollDispatchContext(testDelivery: { delivered.append($0) })
        let poster = ScrollPoster(testDispatchContext: context)

        func submit(pid: pid_t, delta: Double) throws {
            let event = try XCTUnwrap(CGEvent(
                scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                wheel1: 1, wheel2: 0, wheel3: 0
            ))
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            XCTAssertTrue(poster.handleInput(
                event: event, targetIsChrome: false, duration: 0.5, y: delta, x: 0,
                speed: 1, simTrackpadEnabled: true, deadZone: 0.1
            ))
        }

        try submit(pid: oldPID, delta: 100)
        poster.processFrameForTests()
        poster.processFrameForTests()
        context.flushForTests()
        XCTAssertGreaterThan(delivered.last?.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) ?? 0, 10)
        delivered.removeAll()

        try submit(pid: newPID, delta: 20)
        poster.processFrameForTests()
        poster.processFrameForTests()
        context.flushForTests()

        XCTAssertEqual(delivered.map(\.targetPID), [oldPID, newPID, newPID])
        XCTAssertEqual(delivered.map { $0.event.getDoubleValueField(.scrollWheelEventScrollPhase) }, [4, 1, 2])
        XCTAssertEqual(delivered.map { $0.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }, [0, 0, 2])
    }

    // MARK: - shift: shifting = false (默认)

    func testShift_whenNotShifting_passThrough() {
        // 默认 shifting = false
        let input = (y: 5.0, x: 3.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 5.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 3.0, accuracy: 1e-10)
    }

    func testShift_whenNotShifting_zeroValues() {
        let input = (y: 0.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    func testShift_whenNotShifting_negativeValues() {
        let input = (y: -10.0, x: -7.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, -10.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, -7.0, accuracy: 1e-10)
    }

    // MARK: - shift: shifting = true, Y有值X无值 -> 交换到X

    func testShift_whenShifting_yHasValue_xIsZero_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: 10.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10, "Y should become X's original value (0)")
        XCTAssertEqual(result.x, 10.0, accuracy: 1e-10, "X should receive Y's original value")
    }

    func testShift_whenShifting_negativeY_xIsZero_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: -8.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, -8.0, accuracy: 1e-10)
    }

    // MARK: - shift: shifting = true, X已有值 (如 MX Master 横向) -> 直接传递

    func testShift_whenShifting_bothAxesHaveValues_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 5.0, x: 3.0)
        let result = sut.shift(with: input)
        // 当 y != 0 且 x != 0 时, 不交换 (某些鼠标已经显式转换方向)
        XCTAssertEqual(result.y, 5.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 3.0, accuracy: 1e-10)
    }

    func testShift_whenShifting_onlyXHasValue_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 0.0, x: 7.0)
        let result = sut.shift(with: input)
        // y == 0, 不符合 y != 0 && x == 0 条件, 直接传递
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 7.0, accuracy: 1e-10)
    }

    func testShift_whenShifting_bothZero_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 0.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - updateShifting: 切换

    func testUpdateShifting_togglesShiftBehavior() {
        // 初始: 不 shift
        let input = (y: 10.0, x: 0.0)
        var result = sut.shift(with: input)
        XCTAssertEqual(result.y, 10.0, accuracy: 1e-10)

        // 启用 shift
        sut.updateShifting(enable: true)
        result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 10.0, accuracy: 1e-10)

        // 禁用 shift
        sut.updateShifting(enable: false)
        result = sut.shift(with: input)
        XCTAssertEqual(result.y, 10.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - 边界值

    func testShift_whenShifting_verySmallY_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: 0.001, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.001, accuracy: 1e-10)
    }

    func testShift_whenShifting_largeValues() {
        sut.updateShifting(enable: true)
        let input = (y: 10000.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 10000.0, accuracy: 1e-10)
    }
}
