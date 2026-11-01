import Cocoa

enum NativeWindowPreferenceValue: Codable, Equatable {
    case boolean(Bool), string(String)
    var object: CFPropertyList {
        switch self { case .boolean(let value): return value ? kCFBooleanTrue : kCFBooleanFalse; case .string(let value): return value as CFString }
    }
}
struct NativeWindowPreference: Codable, Equatable {
    let domain: String
    let key: String
    let owned: NativeWindowPreferenceValue
    static let controls: [Self] = [
        Self(domain: "global", key: "AppleActionOnDoubleClick", owned: .string("None")),
        Self(domain: "com.apple.WindowManager", key: "EnableTilingByEdgeDrag", owned: .boolean(false)),
        Self(domain: "com.apple.WindowManager", key: "EnableTopTilingByEdgeDrag", owned: .boolean(false)),
        Self(domain: "com.apple.WindowManager", key: "EnableTilingOptionAccelerator", owned: .boolean(false))
    ]
}
protocol NativeWindowPreferenceStore {
    func read(_ preference: NativeWindowPreference) -> NativeWindowPreferenceValue?
    @discardableResult func write(_ value: NativeWindowPreferenceValue?, to preference: NativeWindowPreference) -> Bool
}
final class SystemWindowPreferenceStore: NativeWindowPreferenceStore {
    private func domain(_ preference: NativeWindowPreference) -> CFString {
        preference.domain == "global" ? kCFPreferencesAnyApplication : preference.domain as CFString
    }
    func read(_ preference: NativeWindowPreference) -> NativeWindowPreferenceValue? {
        let app = domain(preference)
        CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let value = CFPreferencesCopyValue(preference.key as CFString, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        if preference.domain == "global", let string = value as? String { return .string(string) }
        if let bool = value as? Bool { return .boolean(bool) }
        return nil
    }
    func write(_ value: NativeWindowPreferenceValue?, to preference: NativeWindowPreference) -> Bool {
        let app = domain(preference)
        CFPreferencesSetValue(preference.key as CFString, value?.object, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) && read(preference) == value
    }
}

/// Write-ahead journal. Restoration is compare-and-set, so changes made in System
/// Settings while we were running are never overwritten by a stale snapshot.
final class NativeWindowSettingsLease {
    struct Entry: Codable { let preference: NativeWindowPreference; let previous: NativeWindowPreferenceValue? }
    static let journalKey = "companionNativeWindowLeaseV1"
    private let store: NativeWindowPreferenceStore
    private let defaults: UserDefaults
    init(store: NativeWindowPreferenceStore = SystemWindowPreferenceStore(), defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
    }
    var hasJournal: Bool { defaults.data(forKey: Self.journalKey) != nil }
    var owned: Bool {
        guard let data = defaults.data(forKey: Self.journalKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data),
              entries.map(\.preference) == NativeWindowPreference.controls else { return false }
        return entries.allSatisfy { store.read($0.preference) == $0.preference.owned }
    }
    @discardableResult func acquire() -> Bool {
        guard !hasJournal else { return owned }
        let entries = NativeWindowPreference.controls.map { Entry(preference: $0, previous: store.read($0)) }
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        defaults.set(data, forKey: Self.journalKey)
        guard defaults.synchronize() else { defaults.removeObject(forKey: Self.journalKey); return false }
        for entry in entries {
            guard store.write(entry.preference.owned, to: entry.preference) else { _ = restore(); return false }
        }
        return owned
    }
    @discardableResult func restore() -> Bool {
        guard let data = defaults.data(forKey: Self.journalKey) else { return true }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return false }
        var success = true
        for entry in entries where store.read(entry.preference) == entry.preference.owned {
            if !store.write(entry.previous, to: entry.preference) { success = false }
        }
        if success { defaults.removeObject(forKey: Self.journalKey); defaults.synchronize() }
        return success
    }
}
