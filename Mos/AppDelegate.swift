//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

enum AppRuntime {
    static var isRunningXCTest: Bool {
        isRunningXCTest(environment: ProcessInfo.processInfo.environment) || isXCTestLoaded
    }

    static func isRunningXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestBundlePath"] != nil ||
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    static var shouldRunAppStartupSideEffects: Bool {
        return shouldRunAppStartupSideEffects(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: isXCTestLoaded
        )
    }

    static func shouldRunAppStartupSideEffects(
        environment: [String: String],
        isXCTestLoaded: Bool = false
    ) -> Bool {
        let isRunningTests = isRunningXCTest(environment: environment) || isXCTestLoaded
        guard isRunningTests else { return true }
        return environment["MOS_TEST_ENABLE_APP_STARTUP"] == "1"
    }

    private static var isXCTestLoaded: Bool {
        NSClassFromString("XCTestCase") != nil ||
        NSClassFromString("XCTest.XCTestCase") != nil
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var session = CompanionSessionState()
    // 防抖定时器: 显示器参数变化通知
    private var screenChangeTimer: Timer?
    // 权限恢复轮询定时器
    private var permissionRecoveryTimer: Timer?

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须最早调用: 从 Mos 自身 env 移除 DYLD_INSERT_LIBRARIES / __XPC_DYLD_* 等
        // Xcode 调试器注入的 vars. 这些 vars 会沿 XPC 链路传到 launchservicesd 再传到
        // 任何 Mos 启动的子 App, 导致依赖 AVKit 的 system app (Maps/FindMy/Podcasts)
        // 加载 libViewDebuggerSupport 时找不到符号 → dyld halt. Mos 自身进程已加载完
        // 依赖, unsetenv 不影响自身, 只让之后启动的子进程拿到干净 env.
        ShortcutExecutor.sanitizeOwnLaunchEnvironment()

        guard AppRuntime.shouldRunAppStartupSideEffects else {
            NSLog("Running under XCTest; skipping app startup side effects")
            return
        }

        // 禁止重复运行, 结束正在运行的实例
        Utils.preventMultiRunning(killExist: true)
        
        // DEBUG: 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // 读取用户设置
        CompanionSettings.importMosPreferences()
        Options.shared.readOptions()
        _ = CompanionSettings.shared
        
        // The private utility starts quietly, including when launched at login.
        // Preferences remain available from the menu bar or an explicit app reopen.

        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionChanged(_:)),
                                                              name: name, object: nil)
        }
        // 监听显示器参数变化 (热插拔/分辨率/显示器休眠唤醒), 延迟重建 CVDisplayLink
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenChangeTimer?.invalidate()
            self?.screenChangeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                ScrollPoster.shared.recreateDisplayLink()
            }
        }
        // 监听辅助功能权限在运行时被撤销
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessibilityPermissionLost),
            name: .mosAccessibilityPermissionLost,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        DirectWindowController.shared.recoverNativeSettings()
        ContinuousGestureEmitter.shared.start()
        AWDLController.shared.start()
        startWithAccessibilityPermissionsChecker(nil)
    }

    // 用户双击打开应用程序
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A visible window may be parked in another Stage Manager group. An
        // explicit reopen should bring the single settings window forward.
        if Utils.isHadAccessibilityPermissions() {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        }
        return false
    }
    
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        stopInputServices()
        AWDLController.shared.stop()
        // 写入尚未 flush 的脏配置组
        Options.shared.flushPendingSaves()
    }
    
    // 检查是否有访问 accessibility 权限, 如果有则启动滚动处理, 并结束计时器
    // 10.14(Mojave) 后, 若无该权限会直接在创建 eventTap 时报错 (https://developer.apple.com/videos/play/wwdc2018/702/)
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        guard session.isInteractive else { return }
        guard Utils.isHadAccessibilityPermissions() else {
            if timer == nil {
                showPermissionGuidance(retryInterval: 10)
            }
            return
        }
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = nil
        ScrollCore.shared.enable()
        ThumbButtonMonitor.shared.enable()
        DirectWindowController.shared.start()
        StageManagerGuardian.shared.start()
        TrackpadMiddleController.shared.start()
    }

    @objc private func sessionChanged(_ note: Notification) {
        guard session.receive(note.name) else { return }
        if session.isInteractive { startWithAccessibilityPermissionsChecker(nil) }
        else { stopInputServices() }
    }

    private func stopInputServices() {
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = nil
        DirectWindowController.shared.stop()
        StageManagerGuardian.shared.stop()
        ScrollCore.shared.disable()
        ThumbButtonMonitor.shared.disable()
        TrackpadMiddleController.shared.stop()
    }

    @objc func handleAccessibilityPermissionLost() {
        guard session.isInteractive, permissionRecoveryTimer == nil else { return }
        stopInputServices()
        showPermissionGuidance(retryInterval: 2)
    }

    private func showPermissionGuidance(retryInterval: TimeInterval) {
        guard permissionRecoveryTimer == nil else { return }
        permissionRecoveryTimer = Timer.scheduledTimer(timeInterval: retryInterval, target: self,
            selector: #selector(startWithAccessibilityPermissionsChecker(_:)), userInfo: nil, repeats: true)
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
    }
}
