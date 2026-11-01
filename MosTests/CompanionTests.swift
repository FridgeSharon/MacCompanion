import XCTest
@testable import Mos_Debug

final class CompanionTests: XCTestCase {
    func testPreferencesKeepsEveryTabVisibleWithoutResizing() throws {
        let controller: PreferencesWindowController = Utils.instantiateControllerFromStoryboard(
            withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        let window = try XCTUnwrap(controller.window)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        controller.showWindow(nil)
        let tabs = try XCTUnwrap(window.contentViewController as? PreferencesTabViewController)
        XCTAssertEqual(tabs.tabViewItems.count, 7)
        let initialFrame = window.frame
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertEqual(window.frame, initialFrame, "Tab \(index) resized the settings window")
            let toolbar = try XCTUnwrap(window.toolbar)
            XCTAssertEqual(toolbar.visibleItems?.count, 7, "Tab \(index) hid a settings tab")
        }
    }
    func testNativeThumbBindingSurvivesWithoutVendorBackend() {
        let recorded = RecordedEvent(type: .mouse, code: 3, modifiers: 0, deviceFilter: nil)
        let native = recorded.normalizedForButtonBinding(diagnosis: LogiCenter.shared.buttonCaptureDiagnosis(forMosCode: 3))
        XCTAssertEqual(native.type, .mouse)
        XCTAssertEqual(native.code, 3)
        XCTAssertEqual(native.modifiers, 0)
        XCTAssertNil(native.deviceFilter)
        XCTAssertFalse(LogiCenter.shared.isBusy)
    }
    func testSettingsPaneLoadsAndLaysOut() {
        let controller = CompanionPreferencesViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.view.frame.width, 620)
        XCTAssertEqual(controller.view.frame.height, 650)
    }
    func testAWDLPolicyRestoresOutsideWiFiGamesAndHonorsManualModes() {
        for wifi in [false, true] {
            for game in [false, true] {
                XCTAssertEqual(AWDLMode.game.suppress(onWiFi: wifi, gameActive: game), wifi && game)
                XCTAssertFalse(AWDLMode.on.suppress(onWiFi: wifi, gameActive: game))
                XCTAssertTrue(AWDLMode.off.suppress(onWiFi: wifi, gameActive: game))
            }
        }
        XCTAssertTrue(AWDLMode.isGame(["LSApplicationCategoryType": "public.app-category.games"]))
        XCTAssertTrue(AWDLMode.isGame(["LSSupportsGameMode": true]))
        XCTAssertFalse(AWDLMode.isGame(["LSApplicationCategoryType": "public.app-category.productivity"]))
        XCTAssertFalse(AWDLMode.isGame([:]))
    }
    func testAWDLModeChangeNotifiesSettingsEvenWhenInterfacePolicyIsUnchanged() {
        let suite = "com.github.FridgeSharon.MacCompanion.AWDLTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: "companionAWDLModeV1")
        let controller = AWDLController(defaults: defaults)
        let updated = expectation(description: "Menu selection reaches settings")
        let observer = NotificationCenter.default.addObserver(forName: AWDLController.changed, object: nil, queue: .main) { notification in
            guard notification.object as? AWDLController === controller else { return }
            XCTAssertEqual(controller.mode, .on); updated.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        controller.setMode(.on)
        wait(for: [updated], timeout: 1)
    }
    func testAWDLSettingsAndPanePreserveMouseConfiguration() {
        let suite = "com.github.FridgeSharon.MacCompanion.AWDLTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "companionAWDLModeV1")
        let controller = AWDLController(defaults: defaults)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(controller.enabled)
        controller.setMode(.on)
        XCTAssertEqual(defaults.integer(forKey: "companionAWDLModeV1"), 1)
        XCTAssertNil(defaults.object(forKey: CompanionSettings.key))
        let pane = AWDLPreferencesViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentViewController = pane
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.view.frame.size, CGSize(width: 620, height: 460))
    }
    func testAppExposeDefaultsToCurrentApplicationWindows() {
        let shortcut = SystemShortcut.getShortcut(named: CompanionAction.appExpose.rawValue)
        XCTAssertEqual(shortcut?.code, 125) // Down Arrow, not the legacy app launcher key.
        XCTAssertEqual(shortcut?.modifiers, .control)
    }
    func testAppExposeUsesApplicationWindowsHotkeyIncludingUserRemapping() {
        let configuredFlags = Int(CGEventFlags.maskControl.rawValue | CGEventFlags.maskSecondaryFn.rawValue)
        let configured = SystemShortcut.resolveSystemShortcuts(from: [
            "33": ["enabled": true, "value": ["parameters": [65535, 125, configuredFlags]]],
            "35": ["enabled": true, "value": ["parameters": [65535, 125, configuredFlags | Int(CGEventFlags.maskShift.rawValue)]]]
        ])
        XCTAssertEqual(configured["appExpose"]?.code, 125)
        XCTAssertEqual(configured["appExpose"]?.modifiers, UInt64(configuredFlags))
        let remapped = SystemShortcut.resolveSystemShortcuts(from: [
            "33": ["enabled": true, "value": ["parameters": [46, 47, Int(CGEventFlags.maskCommand.rawValue)]]]
        ])
        XCTAssertEqual(remapped["appExpose"]?.code, 47)
        XCTAssertEqual(remapped["appExpose"]?.modifiers, CGEventFlags.maskCommand.rawValue)
    }
    func testDisabledOrInvalidApplicationWindowsHotkeyFallsBackSafely() {
        for parameters in [[65535, -1, 0], [65535, 65535, 0], [65535, 65536, 0], [65535, 125, -1], [65535]] {
            XCTAssertNil(SystemShortcut.resolveSystemShortcuts(from: ["33": ["enabled": true, "value": ["parameters": parameters]]])["appExpose"])
        }
        XCTAssertNil(SystemShortcut.resolveSystemShortcuts(from: [
            "33": ["enabled": false, "value": ["parameters": [65535, 125, 262144]]]
        ])["appExpose"])
    }
    func testSmallMovementReplaysOriginalClick() {
        var state = DirectionalGestureRecognizer(); state.begin()
        XCTAssertNil(state.move(dx: 5, dy: 4, threshold: 30))
        XCTAssertTrue(state.end()); XCTAssertFalse(state.isHeld)
    }
    func testAccumulatedMotionTriggersOncePerHold() {
        var state = DirectionalGestureRecognizer(); state.begin()
        XCTAssertNil(state.move(dx: 0, dy: -15, threshold: 30))
        XCTAssertEqual(state.move(dx: 0, dy: -15, threshold: 30), .up)
        XCTAssertNil(state.move(dx: 300, dy: 0, threshold: 30))
        XCTAssertFalse(state.end())
        state.begin()
        XCTAssertEqual(state.move(dx: 40, dy: 2, threshold: 30), .right)
    }
    func testAllDirectionsAndCancellation() {
        for (dx, dy, expected) in [(0.0, -40.0, GestureDirection.up), (0, 40, .down), (-40, 0, .left), (40, 0, .right)] {
            var state = DirectionalGestureRecognizer(); state.begin()
            XCTAssertEqual(state.move(dx: dx, dy: dy, threshold: 30), expected)
            state.cancel(); XCTAssertFalse(state.end())
            XCTAssertNil(state.move(dx: dx, dy: dy, threshold: 30))
        }
    }
    func testNonFiniteMotionIsIgnored() {
        var state = DirectionalGestureRecognizer(); state.begin()
        XCTAssertNil(state.move(dx: .nan, dy: .infinity, threshold: 30))
        XCTAssertEqual(state.move(dx: -31, dy: 0, threshold: 30), .left)
    }
    func testEveryNativeLayoutMapsToReservedAreaWithoutDrift() {
        for edge in [StageEdge.left, .right] {
            for visible in [CGRect(x: 0, y: 80, width: 3008, height: 1544), CGRect(x: -1920, y: -1080, width: 1920, height: 1055)] {
                let usable = StageLayout.reservedFrame(visible, width: 151, edge: edge)
                for fraction in StageLayout.fractions {
                    let native = StageLayout.rect(fraction, in: visible)
                    let expected = StageLayout.rect(fraction, in: usable).integral
                    guard let result = StageLayout.correction(for: native, visibleFrame: visible, width: 151, edge: edge) else {
                        XCTFail("Missing correction for \(fraction)"); continue
                    }
                    XCTAssertEqual(result, expected)
                    XCTAssertNil(StageLayout.correction(for: result, visibleFrame: visible, width: 151, edge: edge))
                }
            }
        }
    }
    func testFloatingWindowsAndUnsafeWidthsAreNotChanged() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        XCTAssertNil(StageLayout.correction(for: CGRect(x: 210, y: 130, width: 600, height: 450), visibleFrame: screen, width: 151, edge: .left))
        XCTAssertNil(StageLayout.correction(for: screen, visibleFrame: screen, width: 700, edge: .left))
        XCTAssertNil(StageLayout.correction(for: screen, visibleFrame: screen, width: .nan, edge: .left))
    }
    func testNativeMarginsArePreserved() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let native = StageLayout.rect(StageLayout.fractions[1], in: screen, margin: 8)
        let expected = StageLayout.rect(StageLayout.fractions[1], in: StageLayout.reservedFrame(screen, width: 150, edge: .left), margin: 8)
        XCTAssertEqual(StageLayout.correction(for: native, visibleFrame: screen, width: 150, edge: .left), expected)
    }
    func testNativeFeedbackIsBounded() {
        var history = StageCorrectionHistory()
        let source = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let target = CGRect(x: 151, y: 0, width: 1449, height: 900)
        XCTAssertTrue(history.permits(source: source, target: target, now: 10))
        XCTAssertTrue(history.permits(source: source, target: target, now: 10.5))
        XCTAssertFalse(history.permits(source: source, target: target, now: 11))
        XCTAssertTrue(history.permits(source: source.offsetBy(dx: 20, dy: 0), target: target, now: 12))
    }
    func testClosedWindowHistoryDoesNotAccumulateInLongLivedApps() {
        var records = StageWindowRecords()
        for hash in 1...10_000 {
            let key = StageWindowRecords.key(pid: 42, hash: CFHashCode(hash))
            records.history[key] = StageCorrectionHistory()
            records.suppressed.insert(key)
            records.retainWindows(pid: 42, hashes: [CFHashCode(hash)])
            XCTAssertEqual(records.history.count, 1)
            XCTAssertEqual(records.suppressed, [key])
        }
        records.retainWindows(pid: 42, hashes: [])
        XCTAssertTrue(records.history.isEmpty)
        XCTAssertTrue(records.suppressed.isEmpty)
    }
    func testClosingOneAppsWindowsPreservesOtherAppsRetryGuards() {
        var records = StageWindowRecords()
        let first = StageWindowRecords.key(pid: 4, hash: 1)
        let other = StageWindowRecords.key(pid: 42, hash: 1)
        var history = StageCorrectionHistory()
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(history.permits(source: frame, target: frame, now: 1))
        records.history = [first: history, other: history]
        records.suppressed = [first, other]
        records.retainWindows(pid: 4, hashes: [])
        XCTAssertNil(records.history[first])
        XCTAssertEqual(records.history[other]?.attempts, 1)
        XCTAssertEqual(records.suppressed, [other])
        // Reusing a closed window's identifier must not inherit suppression.
        records.retainWindows(pid: 4, hashes: [1])
        XCTAssertFalse(records.suppressed.contains(first))
    }
    func testInvalidSettingsAreClampedAndExceptionsMatchOnlyTheirApp() {
        var config = CompanionConfiguration(); config.gestureButton = 0; config.stageWidth = .infinity; config.gestureThreshold = -10
        config.excludedPaths = ["relative", "/Applications/Game.app", "/Applications/Game.app"]
        config.validate()
        XCTAssertEqual(config.gestureButton, 3); XCTAssertEqual(config.stageWidth, 151.2975); XCTAssertEqual(config.gestureThreshold, 10)
        XCTAssertEqual(config.excludedPaths.count, 1)
        XCTAssertTrue(CompanionSettings.matches(paths: config.excludedPaths, bundlePath: "/Applications/Game.app", executablePath: nil))
        XCTAssertTrue(CompanionSettings.matches(paths: config.excludedPaths, bundlePath: nil, executablePath: "/Applications/Game.app/Contents/MacOS/Game"))
        XCTAssertFalse(CompanionSettings.matches(paths: config.excludedPaths, bundlePath: "/Applications/Game.app2", executablePath: nil))
    }
}

final class CompanionUpgradeTests: XCTestCase {
    func testLegacySettingsKeepEveryExistingChoice() throws {
        let old = #"{"gesturesEnabled":false,"gestureButton":4,"gestureThreshold":67,"up":"missionControl","down":"appExpose","left":"moveSpaceLeft","right":"moveSpaceRight","stageEnabled":false,"stageWidth":173,"excludedPaths":["/Applications/Game.app"]}"#
        let config = try JSONDecoder().decode(CompanionConfiguration.self, from: Data(old.utf8))
        XCTAssertFalse(config.gesturesEnabled); XCTAssertEqual(config.gestureButton, 4)
        XCTAssertEqual(config.gestureThreshold, 67); XCTAssertFalse(config.stageEnabled)
        XCTAssertEqual(config.stageWidth, 173); XCTAssertEqual(config.excludedPaths, ["/Applications/Game.app"])
        XCTAssertEqual(config.gestureBackend, .actions); XCTAssertEqual(config.windowSizingMode, .nativeCorrection)
        XCTAssertEqual(config.gestureSensitivity, 1); XCTAssertFalse(config.trackpadPresetApplied)
        XCTAssertEqual(try JSONDecoder().decode(CompanionConfiguration.self, from: JSONEncoder().encode(config)).down, .appExpose)
    }
    func testTrackpadPresetChangesLegacyDirectionsOnceAndKeepsCustomActions() {
        var config = CompanionConfiguration(); config.selectBackend(.continuous)
        XCTAssertEqual(config.left, .moveSpaceRight); XCTAssertEqual(config.right, .moveSpaceLeft)
        config.left = .moveSpaceLeft; config.selectBackend(.actions); config.selectBackend(.continuous)
        XCTAssertEqual(config.left, .moveSpaceLeft)
        config = CompanionConfiguration(); config.left = .missionControl; config.selectBackend(.continuous)
        XCTAssertEqual(config.left, .missionControl)
    }
    func testContinuousPhasesFollowMovementAndReverseToCancel() throws {
        var swipe = try XCTUnwrap(ContinuousGestureState(direction: .left, action: .moveSpaceRight,
            screen: CGSize(width: 1000, height: 800), spaces: 3, sensitivity: 1))
        XCTAssertNil(swipe.frame())
        swipe.move(dx: -400, dy: 2000, time: 1)
        let progress = try XCTUnwrap(swipe.frame())
        XCTAssertEqual(progress.phase, 1); XCTAssertEqual(progress.progress, -0.6, accuracy: 0.0001)
        XCTAssertNil(swipe.frame())
        swipe.move(dx: 200, dy: 0, time: 1.1)
        XCTAssertEqual(swipe.frame()?.progress ?? -1, -0.3, accuracy: 0.0001)
        XCTAssertEqual(swipe.end(cancel: false, time: 1.2).map(\.phase), [8])
        XCTAssertTrue(swipe.end(cancel: false, time: 1.3).isEmpty)
    }
    func testContinuousClampBalancedFastReleaseAndFallback() throws {
        for (direction, action, sign) in [(GestureDirection.right, CompanionAction.moveSpaceLeft, 1.0), (.up, .missionControl, 1), (.down, .appExpose, -1)] {
            var swipe = try XCTUnwrap(ContinuousGestureState(direction: direction, action: action,
                screen: CGSize(width: 1600, height: 900), spaces: 2, sensitivity: 1))
            let dx = direction == .right ? 100000.0 : 0
            let dy = direction == .up ? -100000.0 : (direction == .down ? 100000.0 : 0)
            swipe.move(dx: dx, dy: dy, time: 10)
            swipe.move(dx: .nan, dy: .infinity, time: 11)
            let packets = swipe.end(cancel: false, time: 12)
            XCTAssertEqual(packets.map(\.phase), [1, 4])
            XCTAssertEqual(packets[0].progress, sign * swipe.limit)
            XCTAssertEqual(packets.last?.velocity, 0)
        }
        XCTAssertNil(ContinuousGestureState(direction: .left, action: .missionControl, screen: CGSize(width: 1000, height: 800), spaces: 2, sensitivity: 1))
        XCTAssertNil(ContinuousGestureState(direction: .up, action: .appExpose, screen: .zero, spaces: 2, sensitivity: 1))
        var untouched = try XCTUnwrap(ContinuousGestureState(direction: .up, action: .missionControl, screen: CGSize(width: 1000, height: 800), spaces: 2, sensitivity: 1))
        XCTAssertTrue(untouched.end(cancel: true, time: 1).isEmpty)
    }
    func testVerticalBeginCarriesTheOpeningDirectionBeforeAnyChangedPacket() throws {
        for (direction, action, dy, sign) in [(GestureDirection.up, CompanionAction.missionControl, -50.0, 1.0), (.down, .appExpose, 50, -1)] {
            var state = try XCTUnwrap(ContinuousGestureState(direction: direction, action: action,
                screen: CGSize(width: 1600, height: 1000), spaces: 3, sensitivity: 1))
            XCTAssertNil(state.frame())
            state.move(dx: 0, dy: dy, time: 1)
            let began = try XCTUnwrap(state.frame())
            XCTAssertEqual(began.motion, 2); XCTAssertEqual(began.phase, 1)
            XCTAssertEqual(began.progress, sign * 0.05, accuracy: 0.0001)
            state.move(dx: 0, dy: dy, time: 1.1)
            XCTAssertEqual(state.frame()?.phase, 2)
            XCTAssertEqual(state.end(cancel: true, time: 1.2).map(\.phase), [8])
        }
    }
    func testNativeBridgeRoundTripWithoutPosting() throws {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { throw XCTSkip("Private bridge is restricted to macOS 27") }
        XCTAssertTrue(MCNativeGestureBridgeAvailable()); XCTAssertTrue(MCNativeGestureBridgeRoundTrip())
    }
    func testDirectLayoutsMeetWithoutGapsAtOddWidthsAndBothStageEdges() throws {
        let screen = CompanionScreen(id: "display", frame: CGRect(x: -2000, y: -900, width: 1600, height: 900),
            visible: CGRect(x: -2000, y: -900, width: 1600, height: 875))
        var config = CompanionConfiguration(); config.stageWidth = 151
        for edge in [StageEdge.left, .right] {
            let area = screen.workingArea(config: config, stageOn: true, edge: edge)
            XCTAssertEqual(area.width, 1449)
            let left = try XCTUnwrap(CompanionWindowLayout.leftHalf.frame(in: area))
            let right = try XCTUnwrap(CompanionWindowLayout.rightHalf.frame(in: area))
            XCTAssertEqual(left.maxX, right.minX); XCTAssertEqual(left.width + right.width, area.width)
            let top = try XCTUnwrap(CompanionWindowLayout.topLeft.frame(in: area))
            let bottom = try XCTUnwrap(CompanionWindowLayout.bottomLeft.frame(in: area))
            XCTAssertEqual(top.minY, bottom.maxY); XCTAssertEqual(top.height + bottom.height, area.height)
        }
        XCTAssertEqual(screen.workingArea(config: config, stageOn: false, edge: .left), screen.visible)
    }
    func testSemanticLayoutRecalculatesOnRescaleRotationAndDisconnect() throws {
        let old = CompanionScreen(id: "one", frame: CGRect(x: 0, y: 0, width: 3008, height: 1692), visible: CGRect(x: 0, y: 52, width: 3008, height: 1610))
        let rotated = CompanionScreen(id: "one", frame: CGRect(x: -1200, y: 0, width: 1200, height: 1920), visible: CGRect(x: -1200, y: 0, width: 1200, height: 1890))
        let laptop = CompanionScreen(id: "two", frame: CGRect(x: 0, y: -1100, width: 1728, height: 1117), visible: CGRect(x: 0, y: -1100, width: 1728, height: 1084))
        let layout = CompanionWindowLayout.rightHalf
        let before = try XCTUnwrap(layout.frame(in: old.visible))
        let sameDisplay = try XCTUnwrap(WindowLayoutGeometry.screen(for: before, preferredID: "one", screens: [laptop, rotated]))
        XCTAssertEqual(sameDisplay.id, "one")
        let resized = try XCTUnwrap(layout.frame(in: sameDisplay.visible))
        XCTAssertEqual(resized.width, 600); XCTAssertEqual(resized.height, 1890)
        let remaining = try XCTUnwrap(WindowLayoutGeometry.screen(for: resized, preferredID: "one", screens: [laptop]))
        XCTAssertEqual(remaining.id, "two")
        XCTAssertTrue(laptop.visible.contains(WindowLayoutGeometry.fit(before, in: laptop.visible)))
    }
    func testSnapTargetsAndDragRestoreKeepTheGrabPoint() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
        XCTAssertEqual(WindowLayoutGeometry.snap(at: CGPoint(x: 800, y: 899), screen: screen), .fill)
        XCTAssertEqual(WindowLayoutGeometry.snap(at: CGPoint(x: 1, y: 400), screen: screen), .leftHalf)
        XCTAssertEqual(WindowLayoutGeometry.snap(at: CGPoint(x: 1599, y: 899), screen: screen), .topRight)
        XCTAssertNil(WindowLayoutGeometry.snap(at: CGPoint(x: 800, y: 1), screen: screen))
        let restored = WindowLayoutGeometry.dragRestore(current: screen, floating: CGRect(x: 200, y: 100, width: 800, height: 600),
            downPoint: CGPoint(x: 800, y: 880), cursor: CGPoint(x: 1000, y: 700), bounds: screen)
        XCTAssertEqual(restored, CGRect(x: 600, y: 120, width: 800, height: 600))
    }
    func testTwoCloseControlClicksCannotBecomeTitlebarFill() {
        var clicks = TitlebarDoubleClick(); let point = CGPoint(x: 500, y: 20)
        clicks.down(window: 4, point: point, time: 10, count: 1, titlebar: false)
        clicks.down(window: 4, point: point, time: 10.1, count: 2, titlebar: true)
        XCTAssertFalse(clicks.shouldFill(window: 4, point: point, time: 10.12, count: 2, titlebar: true, interval: 0.5))
        clicks.down(window: 4, point: point, time: 11, count: 1, titlebar: true)
        XCTAssertTrue(clicks.shouldFill(window: 4, point: point, time: 11.2, count: 2, titlebar: true, interval: 0.5))
    }

}

private final class WindowPreferenceTestStore: NativeWindowPreferenceStore {
    var values: [String: NativeWindowPreferenceValue] = [:]
    var failOnce: String?
    var beforeWrite: (() -> Void)?
    func read(_ preference: NativeWindowPreference) -> NativeWindowPreferenceValue? { values[preference.key] }
    func write(_ value: NativeWindowPreferenceValue?, to preference: NativeWindowPreference) -> Bool {
        beforeWrite?()
        if failOnce == preference.key { failOnce = nil; return false }
        values[preference.key] = value; return true
    }
}
final class NativeWindowLeaseTests: XCTestCase {
    private func withLease(_ test: (NativeWindowSettingsLease, WindowPreferenceTestStore, UserDefaults) throws -> Void) rethrows {
        let suite = "com.github.FridgeSharon.MacCompanion.leaseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WindowPreferenceTestStore()
        store.values = ["AppleActionOnDoubleClick": .string("Fill"), "EnableTilingByEdgeDrag": .boolean(true)]
        try test(NativeWindowSettingsLease(store: store, defaults: defaults), store, defaults)
    }
    func testLeaseJournalsBeforeMutationAndRestoresMissingPreferences() {
        withLease { lease, store, defaults in
            let previous = store.values
            store.beforeWrite = { XCTAssertNotNil(defaults.data(forKey: NativeWindowSettingsLease.journalKey)) }
            XCTAssertTrue(lease.acquire()); XCTAssertTrue(lease.owned)
            XCTAssertTrue(lease.restore()); XCTAssertEqual(store.values, previous); XCTAssertFalse(lease.hasJournal)
        }
    }
    func testCrashRecoveryAndExternalSettingsArePreserved() {
        withLease { lease, store, defaults in
            XCTAssertTrue(lease.acquire())
            store.values["AppleActionOnDoubleClick"] = .string("Minimize")
            XCTAssertFalse(lease.owned)
            let recovered = NativeWindowSettingsLease(store: store, defaults: defaults)
            XCTAssertTrue(recovered.restore())
            XCTAssertEqual(store.values["AppleActionOnDoubleClick"], .string("Minimize"))
            XCTAssertEqual(store.values["EnableTilingByEdgeDrag"], .boolean(true))
            XCTAssertNil(store.values["EnableTopTilingByEdgeDrag"])
        }
    }
    func testPartialAcquisitionFailureRollsBackAndFailedRestoreCanRetry() {
        withLease { lease, store, defaults in
            let original = store.values
            store.failOnce = "EnableTopTilingByEdgeDrag"
            XCTAssertFalse(lease.acquire()); XCTAssertEqual(store.values, original); XCTAssertFalse(lease.hasJournal)
            XCTAssertTrue(lease.acquire())
            store.failOnce = "EnableTilingByEdgeDrag"
            XCTAssertFalse(lease.restore()); XCTAssertTrue(lease.hasJournal)
            XCTAssertTrue(lease.restore()); XCTAssertEqual(store.values, original)
        }
    }
    func testCorruptJournalCannotAuthorizeAnotherAcquisition() {
        withLease { lease, store, defaults in
            defaults.set(Data("broken".utf8), forKey: NativeWindowSettingsLease.journalKey)
            XCTAssertFalse(lease.owned); XCTAssertFalse(lease.acquire()); XCTAssertFalse(lease.restore())
        }
    }
}

final class CompanionControlStateTests: XCTestCase {
    func testContinuousSensitivityIsOnlyEditableForContinuousStyle() throws {
        let original = CompanionSettings.shared.configuration
        defer { CompanionSettings.shared.update { $0 = original } }
        CompanionSettings.shared.update { $0.gestureBackend = .actions }
        let controller = CompanionPreferencesViewController()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let controls = descendants(controller.view)
        let slider = try XCTUnwrap(controls.compactMap { $0 as? NSSlider }.first { $0.accessibilityLabel() == "Continuous gesture sensitivity" })
        let backend = try XCTUnwrap(controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Gesture style" })
        XCTAssertFalse(slider.isEnabled)
        backend.selectItem(at: 1); NSApp.sendAction(try XCTUnwrap(backend.action), to: backend.target, from: backend)
        XCTAssertTrue(slider.isEnabled)
        backend.selectItem(at: 0); NSApp.sendAction(try XCTUnwrap(backend.action), to: backend.target, from: backend)
        XCTAssertFalse(slider.isEnabled)
    }
}

final class AccessibilityFrameTransactionTests: XCTestCase {
    func testAnimatedAccessibilityIsRestoredAfterPlacementAndReadback() {
        var events: [String] = []
        let result = AccessibilityFrameTransaction.perform(readEnhanced: { true }, writeEnhanced: {
            events.append($0 ? "restore" : "disable"); return true
        }, adjustment: { events.append("size-position-readback"); return 42 })
        XCTAssertEqual(result, 42)
        XCTAssertEqual(events, ["disable", "size-position-readback", "restore"])
    }
    func testFailedPlacementAlsoRestoresOriginalAccessibility() {
        var values: [Bool] = []
        let result: CGRect? = AccessibilityFrameTransaction.perform(readEnhanced: { true }, writeEnhanced: {
            values.append($0); return true
        }, adjustment: { nil })
        XCTAssertNil(result); XCTAssertEqual(values, [false, true])
    }
    func testInactiveOrUnsupportedEnhancedModeIsNeverChanged() {
        for value: Bool? in [false, nil] {
            var writes = 0
            _ = AccessibilityFrameTransaction.perform(readEnhanced: { value }, writeEnhanced: { _ in writes += 1; return true }, adjustment: { true })
            XCTAssertEqual(writes, 0)
        }
    }
    func testFailedDisableStillAttemptsToRestoreTheKnownOriginalState() {
        var values: [Bool] = []
        _ = AccessibilityFrameTransaction.perform(readEnhanced: { true }, writeEnhanced: { values.append($0); return false }, adjustment: { true })
        XCTAssertEqual(values, [false, true])
    }
}

final class TitlebarClickCaptureTests: XCTestCase {
    private let point = CGPoint(x: 500, y: 30)
    private func prepared(titlebar: Bool = true, release: Bool = true) -> TitlebarClickCapture {
        var gate = TitlebarClickCapture()
        guard case .inspect(let ticket) = gate.down(count: 1, window: 20, frontPID: 10, point: point, time: 1, interval: 0.5) else {
            XCTFail("First click should pass and request off-thread verification"); return gate
        }
        gate.confirm(ticket: ticket, window: 20, pid: 10, titlebar: titlebar)
        if release { XCTAssertEqual(gate.up(at: point), .pass) }
        return gate
    }
    func testOnlyVerifiedSecondTitlebarClickIsConsumedAndCommittedOnce() {
        var gate = prepared()
        XCTAssertEqual(gate.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5), .capture)
        XCTAssertTrue(gate.isCapturing)
        XCTAssertEqual(gate.up(at: point), .commit)
        XCTAssertFalse(gate.isCapturing)
        XCTAssertEqual(gate.up(at: point), .pass)
    }
    func testControlsAndUnverifiedHitsKeepOrdinaryDoubleClicks() {
        var control = prepared(titlebar: false)
        XCTAssertEqual(control.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5), .pass)
        var unverified = TitlebarClickCapture()
        _ = unverified.down(count: 1, window: 20, frontPID: 10, point: point, time: 1, interval: 0.5)
        _ = unverified.up(at: point)
        XCTAssertEqual(unverified.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5), .pass)
    }
    func testDifferentWindowMovedClickExpiredClickAndUnreleasedFirstClickPassThrough() {
        for (window, targetPoint, time, release) in [(UInt32(21), point, 1.2, true),
            (20, CGPoint(x: 520, y: 30), 1.2, true), (20, point, 2.0, true), (20, point, 1.2, false)] {
            var gate = prepared(release: release)
            XCTAssertEqual(gate.down(count: 2, window: window, frontPID: 10, point: targetPoint, time: time, interval: 0.5), .pass)
        }
    }
    func testWindowlessEventRequiresMatchingForegroundProcess() {
        var matching = prepared()
        XCTAssertEqual(matching.down(count: 2, window: 0, frontPID: 10, point: point, time: 1.2, interval: 0.5), .capture)
        var otherApp = prepared()
        XCTAssertEqual(otherApp.down(count: 2, window: 0, frontPID: 99, point: point, time: 1.2, interval: 0.5), .pass)
    }
    func testCancellationAndDraggingConsumeOnlyTheReleaseAlreadyOwned() {
        var cancelled = prepared()
        _ = cancelled.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5)
        cancelled.cancel()
        XCTAssertEqual(cancelled.up(at: point), .consume)
        XCTAssertEqual(cancelled.up(at: point), .pass)
        var dragged = prepared()
        _ = dragged.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5)
        XCTAssertEqual(dragged.up(at: CGPoint(x: 600, y: 30)), .consume)
    }
    func testStaleAXReplyCannotAuthorizeAnotherPress() {
        var gate = TitlebarClickCapture()
        guard case .inspect(let old) = gate.down(count: 1, window: 20, frontPID: 10, point: point, time: 1, interval: 0.5) else { return XCTFail() }
        guard case .inspect(let fresh) = gate.down(count: 1, window: 21, frontPID: 10, point: point, time: 2, interval: 0.5) else { return XCTFail() }
        XCTAssertNotEqual(old, fresh)
        XCTAssertFalse(gate.confirm(ticket: old, window: 20, pid: 10, titlebar: true))
        _ = gate.up(at: point)
        XCTAssertEqual(gate.down(count: 2, window: 21, frontPID: 10, point: point, time: 2.2, interval: 0.5), .pass)
    }
    func testFreshPressRecoversFromALostCapturedRelease() {
        var gate = prepared()
        _ = gate.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5)
        XCTAssertTrue(gate.isCapturing)
        guard case .inspect = gate.down(count: 1, window: 21, frontPID: 11, point: point, time: 5, interval: 0.5) else { return XCTFail() }
        XCTAssertFalse(gate.isCapturing)
        XCTAssertEqual(gate.up(at: point), .pass)
    }
    func testRapidRepeatedPairsEachProduceOneAction() {
        var gate = prepared()
        _ = gate.down(count: 2, window: 20, frontPID: 10, point: point, time: 1.2, interval: 0.5)
        XCTAssertEqual(gate.up(at: point), .commit)
        guard case .inspect(let ticket) = gate.down(count: 3, window: 20, frontPID: 10, point: point, time: 1.3, interval: 0.5) else { return XCTFail() }
        gate.confirm(ticket: ticket, window: 20, pid: 10, titlebar: true)
        _ = gate.up(at: point)
        XCTAssertEqual(gate.down(count: 4, window: 20, frontPID: 10, point: point, time: 1.4, interval: 0.5), .capture)
        XCTAssertEqual(gate.up(at: point), .commit)
    }
}

final class WindowFrameOrderingTests: XCTestCase {
    func testFillMovesBeforeGrowingAndRightTileShrinksBeforeMoving() {
        let bounds = CGRect(x: 151, y: 0, width: 2857, height: 1662)
        let floating = CGRect(x: 500, y: 200, width: 1500, height: 1000)
        XCTAssertFalse(WindowLayoutGeometry.resizeBeforeMove(current: floating, target: bounds, bounds: bounds))
        let large = CGRect(x: 151, y: 0, width: 2400, height: 1662)
        let right = CGRect(x: 1580, y: 0, width: 1428, height: 1662)
        XCTAssertTrue(WindowLayoutGeometry.resizeBeforeMove(current: large, target: right, bounds: bounds))
        let offscreen = floating.offsetBy(dx: -3008, dy: 0)
        XCTAssertTrue(WindowLayoutGeometry.resizeBeforeMove(current: offscreen, target: bounds, bounds: bounds))
    }
}

final class TitlebarHitRegionTests: XCTestCase {
    private let window = CGRect(x: -700, y: 1700, width: 1500, height: 1000)
    func testNestedUnifiedToolbarExtendsTheTitlebarPast44Points() {
        let path = [TitlebarHitRegion.Node(role: kAXGroupRole, frame: nil),
            .init(role: kAXToolbarRole, frame: CGRect(x: -700, y: 1730, width: 1500, height: 58)),
            .init(role: kAXGroupRole, frame: nil), .init(role: kAXWindowRole, frame: nil)]
        XCTAssertTrue(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1770), window: window, path: path))
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1900), window: window, path: path))
    }
    func testToolbarButtonsAndTextFieldsRemainOrdinaryClicks() {
        for role in [kAXButtonRole, kAXTextFieldRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXSliderRole, kAXSplitterRole, "AXTab"] {
            let path = [TitlebarHitRegion.Node(role: role, frame: nil),
                .init(role: kAXToolbarRole, frame: CGRect(x: -700, y: 1730, width: 1500, height: 58))]
            XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1770), window: window, path: path))
        }
    }
    func testContentToolbarCannotBecomeWindowTitlebar() {
        let path = [TitlebarHitRegion.Node(role: kAXGroupRole, frame: nil),
            .init(role: kAXToolbarRole, frame: CGRect(x: -700, y: 2000, width: 1500, height: 50))]
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: 500, y: 2020), window: window, path: path))
        XCTAssertTrue(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1730), window: window, path: path))
    }
}

final class BoundedAccessibilityHitTests: XCTestCase {
    private final class Node {
        let name: String; let rect: CGRect?; let control: Bool
        weak var parent: Node?
        var children: [Node] = []
        init(_ name: String, _ rect: CGRect?, control: Bool = false) { self.name = name; self.rect = rect; self.control = control }
        func add(_ child: Node) { children.append(child); child.parent = self }
    }
    private func resolve(_ node: Node, _ point: CGPoint) -> Node? {
        BoundedAccessibilityHit.resolve(node, at: point, frame: { $0.rect }, parent: { $0.parent }, children: { $0.children }, isControl: { $0.control })
    }
    func testCatalystNearestButtonOutsideThePointResolvesToBlankHeader() {
        let header = Node("header", CGRect(x: -117, y: 1735, width: 971, height: 46))
        let call = Node("call", CGRect(x: 728, y: 1739, width: 28, height: 28), control: true)
        header.add(call)
        XCTAssertTrue(resolve(call, CGPoint(x: 65.5, y: 1750)) === header)
        XCTAssertTrue(resolve(call, CGPoint(x: 740, y: 1750)) === call)
    }
    func testWindowFallbackFindsTheRealSmallControlWithoutStealingIt() {
        let window = Node("window", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let group = Node("group", window.rect); window.add(group)
        let close = Node("close", CGRect(x: 10, y: 10, width: 16, height: 16), control: true); window.add(close)
        XCTAssertTrue(resolve(window, CGPoint(x: 18, y: 18)) === close)
        XCTAssertTrue(resolve(window, CGPoint(x: 500, y: 20)) === group)
    }
    func testUnknownControlBoundsFailOpenAndNothingResolvesOutsideTheWindow() {
        let window = Node("window", CGRect(x: 0, y: 0, width: 1000, height: 800))
        window.add(Node("unpositioned control", nil, control: true))
        XCTAssertNil(resolve(window, CGPoint(x: 500, y: 20)))
        XCTAssertNil(resolve(window, CGPoint(x: 1200, y: 20)))
    }
    func testCaptionHeightUsesNativeTrafficLightGeometry() {
        let window = CGRect(x: -723, y: 1725, width: 1577, height: 1032)
        let height = TitlebarHitRegion.nativeHeight(window: window, closeButton: CGRect(x: -710, y: 1745, width: 16, height: 16))
        XCTAssertEqual(height, 56)
        XCTAssertTrue(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1775), window: window, path: [], nativeHeight: height))
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: 500, y: 1800), window: window, path: [], nativeHeight: height))
        XCTAssertEqual(TitlebarHitRegion.nativeHeight(window: window, closeButton: nil), 44)
    }
}

final class CatalystCaptionTests: XCTestCase {
    func testWDSCaptionIncludesItsFirstRowButNeverTheSidebarSearchRow() {
        let window = CGRect(x: -723, y: 1725, width: 1577, height: 1032)
        let sidebar = TitlebarHitRegion.Node(role: kAXGroupRole, frame: CGRect(x: -723, y: 1735, width: 605, height: 100), identifier: "WDSNavigationBar")
        XCTAssertTrue(TitlebarHitRegion.contains(CGPoint(x: -400, y: 1775), window: window, path: [sidebar], nativeHeight: 32))
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: -400, y: 1800), window: window, path: [sidebar], nativeHeight: 32))
        let search = TitlebarHitRegion.Node(role: kAXStaticTextRole, frame: nil, identifier: "TokenizedSearchBar_TextView")
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: -400, y: 1775), window: window, path: [search, sidebar], nativeHeight: 32))
    }
    func testActualNavigationButtonsStayExcludedInsideTheCaptionBand() {
        let window = CGRect(x: -723, y: 1725, width: 1577, height: 1032)
        let navbar = TitlebarHitRegion.Node(role: kAXGroupRole, frame: CGRect(x: -117, y: 1735, width: 971, height: 46), identifier: "WDSNavigationBar")
        XCTAssertTrue(TitlebarHitRegion.contains(CGPoint(x: 450, y: 1775), window: window, path: [navbar], nativeHeight: 32))
        let button = TitlebarHitRegion.Node(role: kAXButtonRole, frame: nil, identifier: "NavigationBar_VideoCallButton")
        XCTAssertFalse(TitlebarHitRegion.contains(CGPoint(x: 740, y: 1750), window: window, path: [button, navbar], nativeHeight: 32))
    }
}

final class WindowHitSelectionTests: XCTestCase {
    private let point = CGPoint(x: 500, y: 1750)
    private func info(_ number: Int, alpha: Double = 1, frame: CGRect = CGRect(x: -700, y: 1700, width: 1500, height: 1000)) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true,
         kCGWindowAlpha as String: alpha, kCGWindowBounds as String: frame.dictionaryRepresentation]
    }
    func testNativeEventWindowWinsOverAnotherStackingListWindow() {
        let target = info(20), decoy = info(99)
        let chosen = WindowHitSelection.select(at: point, requested: target, windows: [decoy, target])
        XCTAssertEqual(chosen?[kCGWindowNumber as String] as? Int, 20)
    }
    func testTransparentHelperIsIgnoredWhenEventHasNoWindowNumber() {
        let chosen = WindowHitSelection.select(at: point, requested: nil, windows: [info(99, alpha: 0), info(20)])
        XCTAssertEqual(chosen?[kCGWindowNumber as String] as? Int, 20)
    }
    func testStaleEventRectangleCannotRedirectTheClick() {
        let stale = info(99, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let chosen = WindowHitSelection.select(at: point, requested: stale, windows: [info(20)])
        XCTAssertEqual(chosen?[kCGWindowNumber as String] as? Int, 20)
    }
}


final class TrackpadMiddleClickTests: XCTestCase {
    private func frame(_ count: Int, _ time: Double, _ x: Double = 0.5, contact: Int32 = 1, touching: Bool = true, state: inout TrackpadTapRecognizer) -> Bool {
        state.update(count: count, point: CGPoint(x: x, y: 0.5), contact: contact, touching: touching, time: time)
    }
    func testThreeFingerTapFiresOnceAfterAllFingersLift() {
        var state = TrackpadTapRecognizer()
        XCTAssertFalse(frame(3, 1, state: &state)); XCTAssertFalse(frame(2, 1.05, state: &state))
        XCTAssertFalse(frame(1, 1.07, state: &state)); XCTAssertTrue(frame(0, 1.1, state: &state))
        XCTAssertFalse(frame(0, 1.2, state: &state))
    }
    func testTwoAndFourFingersKeepTheirNativeGestures() {
        for count in [2, 4] {
            var state = TrackpadTapRecognizer()
            XCTAssertFalse(frame(count, 1, state: &state)); XCTAssertFalse(frame(0, 1.1, state: &state))
        }
        var state = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &state); _ = frame(4, 1.02, state: &state)
        XCTAssertFalse(frame(0, 1.1, state: &state))
    }
    func testHoverAndRestingContactsDoNotClick() {
        var hover = TrackpadTapRecognizer()
        _ = frame(3, 1, touching: false, state: &hover)
        XCTAssertFalse(frame(0, 1.1, state: &hover))
        var resting = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &resting)
        XCTAssertFalse(frame(0, 1.5, state: &resting))
    }
    func testSwipeAndChangedContactAreRejected() {
        var swipe = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &swipe); _ = frame(3, 1.05, 0.6, state: &swipe)
        XCTAssertFalse(frame(0, 1.1, state: &swipe))
        var changed = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &changed); _ = frame(3, 1.05, contact: 2, state: &changed)
        XCTAssertFalse(frame(0, 1.1, state: &changed))
    }
    func testPhysicalClickSuppressesTapAndCancelCannotFire() {
        var state = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &state); state.physicalClick()
        XCTAssertFalse(frame(0, 1.1, state: &state))
        _ = frame(3, 2, state: &state); state.cancel()
        XCTAssertFalse(frame(0, 2.1, state: &state))
    }
    func testRelandingDuringReleaseDoesNotBecomeAnotherTap() {
        var state = TrackpadTapRecognizer()
        _ = frame(3, 1, state: &state); _ = frame(2, 1.02, state: &state)
        _ = frame(3, 1.04, state: &state)
        XCTAssertFalse(frame(0, 1.1, state: &state))
    }
    func testMiddleHoldRequiresKnownTrackpadAndMatchingRelease() {
        var session = TrackpadMiddleSession()
        XCTAssertFalse(session.begin(device: 0, threeFingers: true))
        XCTAssertFalse(session.begin(device: 10, threeFingers: false))
        XCTAssertTrue(session.begin(device: 10, threeFingers: true))
        XCTAssertFalse(session.matches(20)); XCTAssertFalse(session.end(device: 20))
        XCTAssertTrue(session.matches(10)); XCTAssertTrue(session.end(device: 10))
        XCTAssertFalse(session.end(device: 10))
    }
    func testCancelledMiddleHoldReleasesExactlyOnce() {
        var session = TrackpadMiddleSession()
        XCTAssertTrue(session.begin(device: 10, threeFingers: true))
        XCTAssertTrue(session.cancel()); XCTAssertFalse(session.cancel())
    }
}
