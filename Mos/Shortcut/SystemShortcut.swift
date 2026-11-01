//
//  SystemShortcut.swift
//  Mos
//  系统快捷键组合常量定义
//  Created by 陈标 on 2025/8/28.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

/// The gesture actions supported by Mac Companion. General keyboard remapping is absent.
struct SystemShortcut {
    struct Shortcut: Equatable {
        let identifier: String
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags
        init(_ identifier: String, _ code: UInt16, _ modifiers: NSEvent.ModifierFlags) {
            self.identifier = identifier; self.code = code; self.modifiers = modifiers
        }
    }
    static let missionControl = Shortcut("missionControl", 160, .function)
    static let appExpose = Shortcut("appExpose", 125, .control)
    static let showDesktop = Shortcut("showDesktop", 103, .function)
    static let navigateBack = Shortcut("navigateBack", 123, .command)
    static let navigateForward = Shortcut("navigateForward", 124, .command)
    static func getShortcut(named identifier: String) -> Shortcut? {
        [missionControl, appExpose, showDesktop, navigateBack, navigateForward].first { $0.identifier == identifier }
    }
}

// MARK: - System Configuration Resolver

/// 从symbolichotkeys动态解析系统快捷键配置
extension SystemShortcut {

    /// 系统快捷键ID映射表 (symbolichotkeys -> 快捷键名称)
    private static let symbolicHotkeyMapping: [Int: String] = [
        33: "appExpose",      // Application Windows (default: Control-Down)
        79: "moveSpaceLeft",   // Move left a space (default: Control-Left)
        80: "moveSpaceLeft",   // Move left a space with shift modifier
        81: "moveSpaceRight",  // Move right a space (default: Control-Right)
        82: "moveSpaceRight",  // Move right a space with shift modifier
    ]

    /// 缓存的已解析快捷键配置
    private static var resolvedCache: [String: (code: CGKeyCode, modifiers: UInt64)] = {
        loadSystemShortcuts()
    }()

    /// 获取解析后的系统快捷键配置
    /// - Parameter name: 快捷键名称 (如 "moveSpaceLeft")
    /// - Returns: (keyCode, modifiers) 或 nil
    static func resolveSystemShortcut(_ name: String) -> (code: CGKeyCode, modifiers: UInt64)? {
        return resolvedCache[name]
    }

    /// 重新加载系统快捷键配置
    static func reloadSystemShortcuts() {
        resolvedCache = loadSystemShortcuts()
        NSLog("SystemShortcut: Reloaded system config, \(resolvedCache.count) shortcuts resolved")
    }

    /// 从系统配置加载快捷键
    private static func loadSystemShortcuts() -> [String: (code: CGKeyCode, modifiers: UInt64)] {
        // 读取系统快捷键配置
        guard let symbolicHotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = symbolicHotkeys["AppleSymbolicHotKeys"] as? [String: Any] else {
            NSLog("SystemShortcut: Failed to read com.apple.symbolichotkeys")
            return [:]
        }
        return resolveSystemShortcuts(from: hotkeys)
    }

    /// Decode a supplied snapshot without sending keys or changing system settings.
    static func resolveSystemShortcuts(from hotkeys: [String: Any]) -> [String: (code: CGKeyCode, modifiers: UInt64)] {
        var resolved: [String: (code: CGKeyCode, modifiers: UInt64)] = [:]
        // 解析每个感兴趣的快捷键
        for (hotkeyID, shortcutName) in symbolicHotkeyMapping {
            guard let hotkeyConfig = hotkeys[String(hotkeyID)] as? [String: Any],
                  let enabled = hotkeyConfig["enabled"] as? Bool,
                  enabled,
                  let value = hotkeyConfig["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3 else {
                continue
            }

            // 提取参数
            // parameters[0]: Unicode character (65535 for non-printable)
            // parameters[1]: Virtual key code
            // parameters[2]: Modifier flags
            guard let keyCode = parameters[1] as? Int,
                  let modifiers = parameters[2] as? Int,
                  (0..<Int(UInt16.max)).contains(keyCode), modifiers >= 0 else {
                continue
            }

            // 只保存主快捷键(ID较小的),避免重复
            // Hotkey 79/81 是主快捷键, 80/82 是带额外修饰键的变体
            if hotkeyID == 33 || hotkeyID == 79 || hotkeyID == 81 {
                if resolved[shortcutName] == nil {
                    resolved[shortcutName] = (CGKeyCode(keyCode), UInt64(modifiers))
                    NSLog("SystemShortcut: Loaded \(shortcutName) = keyCode:\(keyCode), modifiers:0x\(String(modifiers, radix: 16))")
                }
            }
        }

        return resolved
    }
}
