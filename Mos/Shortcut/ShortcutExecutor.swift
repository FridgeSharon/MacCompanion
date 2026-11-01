//
//  ShortcutExecutor.swift
//  Mos
//  系统快捷键执行器 - 发送快捷键事件
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// Posts only configured gesture shortcuts; no general remapping or script execution.
final class ShortcutExecutor {
    static let shared = ShortcutExecutor()
    func execute(code: CGKeyCode, flags: UInt64) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = CGEventFlags(rawValue: flags); down.post(tap: .cghidEventTap)
        }
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
    func execute(named identifier: String) {
        if let configured = SystemShortcut.resolveSystemShortcut(identifier) {
            execute(code: configured.code, flags: configured.modifiers)
        } else if let shortcut = SystemShortcut.getShortcut(named: identifier) {
            execute(code: shortcut.code, flags: UInt64(shortcut.modifiers.rawValue))
        }
    }

    static func sanitizeOwnLaunchEnvironment() {
        for key in ProcessInfo.processInfo.environment.keys where shouldStripEnvKey(key) {
            unsetenv(key)
        }
    }

    /// 已 unsetenv 后再读, 返回当前 env 的副本 (供 Process.environment 显式赋值用).
    /// 双重保险: sanitizeOwnLaunchEnvironment 已经清干净源头, 这里再过滤一遍兜底.
    static func sanitizedSubprocessEnvironment() -> [String: String] {
        return filterEnvironment(ProcessInfo.processInfo.environment)
    }

    /// 纯函数: 输入一个 env dict, 输出剥离了污染 keys 的副本. 暴露出来供单测用控制输入验证.
    static func filterEnvironment(_ env: [String: String]) -> [String: String] {
        var out = env
        for key in env.keys where shouldStripEnvKey(key) {
            out.removeValue(forKey: key)
        }
        return out
    }

    private static func shouldStripEnvKey(_ key: String) -> Bool {
        // dyld 注入 / fallback 路径 / 框架路径
        if key.hasPrefix("DYLD_") { return true }
        // Xcode 通过 launchd XPC 传递的 dyld 注入 (会跨 XPC 边界变成子进程的 DYLD_*)
        if key.hasPrefix("__XPC_DYLD_") { return true }
        // Xcode 调试器附加 (LLVM profile / SwiftUI 视图调试 等)
        if key.hasPrefix("__XPC_LLVM_") { return true }
        if key == "SWIFTUI_VIEW_DEBUG" { return true }
        if key.hasPrefix("OS_ACTIVITY_DT_") { return true }
        // 内存分析器
        if key.hasPrefix("MallocStack") { return true }
        if key == "NSZombieEnabled" { return true }
        if key == "NSDeallocateZombies" { return true }
        // Sanitizer ABI shim
        if key.hasPrefix("LSAN_") || key.hasPrefix("ASAN_") || key.hasPrefix("TSAN_") || key.hasPrefix("UBSAN_") { return true }
        return false
    }

}
