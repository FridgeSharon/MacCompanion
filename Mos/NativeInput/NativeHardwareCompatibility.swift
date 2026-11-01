// Copyright (c) 2026 Guy Sharon. Licensed under CC BY-NC 4.0.
// Native-input compatibility for the Mos UI (Caldis, CC BY-NC 4.0).
// This file contains no vendor protocol implementation or device-ID catalogue.
import Cocoa

public enum ScrollRole: Hashable, CaseIterable { case dash, toggle, block }

public enum ConflictStatus: Equatable {
    case clear, foreignDivert, remapped, mosOwned, unknown
    public var isConflict: Bool { self == .foreignDivert || self == .remapped }
}

struct LogiButtonCaptureDiagnosis {
    let ownership: ConflictStatus = .clear
    let usesNativeEvents = true
    let canUseStandardMouseAlias = false
    let isContention = false
    let isBLEHIDPPOnlyControl = false
}

struct SessionActivityStatus {
    enum Phase { case discovery, reportingQuery }
    let phase: Phase
    let deviceName: String
    let progress: (current: Int, total: Int)?
}

/// Ordinary mouse buttons use Quartz. No vendor hardware discovery is performed.
final class LogiCenter {
    static let shared = LogiCenter()
    enum CycleDirection { case up, down }
    static let sessionChanged = Notification.Name("NativeInput.SessionChanged")
    static let reportingDidComplete = Notification.Name("NativeInput.ReportingComplete")
    static let activityChanged = Notification.Name("NativeInput.ActivityChanged")
    static let conflictChanged = Notification.Name("NativeInput.ConflictChanged")
    static let buttonEventRelay = Notification.Name("NativeInput.ButtonRelay")
    var isBusy: Bool { false }
    var isRecording: Bool { false }
    var currentActivitySummary: [SessionActivityStatus] { [] }
    func start() {}
    func stop() {}
    func refreshReportingStates() {}
    func beginKeyRecording() {}
    func endKeyRecording() {}
    func isLogiCode(_ code: UInt16) -> Bool { false }
    func name(forMosCode code: UInt16) -> String? { nil }
    func nativeMouseButton(forMosCode code: UInt16) -> UInt16? { nil }
    func buttonCaptureDiagnosis(forMosCode code: UInt16) -> LogiButtonCaptureDiagnosis { .init() }
    func conflictStatus(forMosCode code: UInt16) -> ConflictStatus { .clear }
    func isDeliveryContended(forMosCode code: UInt16) -> Bool { false }
    func showBLEHIDPPUnstableToast(forMosCode code: UInt16) {}
    func executeSmartShiftToggle() {}
    func executeDPICycle(direction: CycleDirection) {}
    func logButtonCaptureDiagnostic(_ message: String) {}
    func showDebugPanel() {}
}

enum LogiStandardMouseButtonAlias {
    static func nativeButtonCode(forMosCode code: UInt16) -> UInt16? { nil }
    static func convertedRecordedEvent(from event: RecordedEvent) -> RecordedEvent? { nil }
    static func convertedBinding(from binding: ButtonBinding) -> ButtonBinding? { nil }
}
