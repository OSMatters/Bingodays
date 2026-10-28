import Foundation

enum NativeICloudAnalyticsOperation: String {
    case enable, manualSync = "manual_sync", backgroundPush = "background_push"
}

enum NativeICloudAnalyticsResult: String {
    case success, waiting, noData = "no_data", failed
}

/// Desktop diagnostics stay local; mobile Firebase is not linked into the Mac app.
enum AnalyticsService {
    static func logBingoCompleted(boardSize: Int, completedLineCount: Int, filledTaskCount: Int) {
        DiagnosticLogStore.record("bingo_completed", category: "mac", details: ["board_size": String(boardSize)])
    }
    static func logICloudSyncToggled(isEnabled: Bool) {
        DiagnosticLogStore.record("icloud_sync_toggled", category: "mac", details: ["enabled": String(isEnabled)])
    }
    static func logICloudSyncResult(operation: NativeICloudAnalyticsOperation, result: NativeICloudAnalyticsResult, failureStage: String? = nil) {
        DiagnosticLogStore.record("icloud_sync_result", category: "mac", details: ["operation": operation.rawValue, "result": result.rawValue])
    }
}
