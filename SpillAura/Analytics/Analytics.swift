import Foundation
import TelemetryDeck

enum AnalyticsSignal {
    // Session Reliability
    case entertainmentSessionStarted(channelCount: Int, groupId: String)
    case entertainmentSessionEnded(durationSeconds: Int, reconnectCount: Int)
    case entertainmentSessionFailed(errorReason: String, phase: String)
    case entertainmentSessionReconnect(attemptNumber: Int, previousDurationSeconds: Int)
    case bridgeDiscoveryCompleted(method: String, durationMs: Int)
    case appResumedFromSleep(sessionRecovered: Bool)

    // Streaming Health
    case streamingModeActivated(mode: String, detail: String)
    case streamingModeSwitched(fromMode: String, toMode: String)
    case screenCaptureStarted(displayId: UInt32, zoneCount: Int, edgeBias: Double)
    case screenCaptureFailed(errorDescription: String)

    // Usage
    case auraSelected(auraName: String, isBuiltin: Bool)
    case brightnessChanged(value: Double)
    case settingsChanged(setting: String, newValue: String)

    var name: String {
        switch self {
        case .entertainmentSessionStarted: "entertainmentSessionStarted"
        case .entertainmentSessionEnded: "entertainmentSessionEnded"
        case .entertainmentSessionFailed: "entertainmentSessionFailed"
        case .entertainmentSessionReconnect: "entertainmentSessionReconnect"
        case .bridgeDiscoveryCompleted: "bridgeDiscoveryCompleted"
        case .appResumedFromSleep: "appResumedFromSleep"
        case .streamingModeActivated: "streamingModeActivated"
        case .streamingModeSwitched: "streamingModeSwitched"
        case .screenCaptureStarted: "screenCaptureStarted"
        case .screenCaptureFailed: "screenCaptureFailed"
        case .auraSelected: "auraSelected"
        case .brightnessChanged: "brightnessChanged"
        case .settingsChanged: "settingsChanged"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .entertainmentSessionStarted(let channelCount, let groupId):
            ["channelCount": "\(channelCount)", "groupId": groupId]
        case .entertainmentSessionEnded(let durationSeconds, let reconnectCount):
            ["durationSeconds": "\(durationSeconds)", "reconnectCount": "\(reconnectCount)"]
        case .entertainmentSessionFailed(let errorReason, let phase):
            ["errorReason": errorReason, "phase": phase]
        case .entertainmentSessionReconnect(let attemptNumber, let previousDurationSeconds):
            ["attemptNumber": "\(attemptNumber)", "previousDurationSeconds": "\(previousDurationSeconds)"]
        case .bridgeDiscoveryCompleted(let method, let durationMs):
            ["method": method, "durationMs": "\(durationMs)"]
        case .appResumedFromSleep(let sessionRecovered):
            ["sessionRecovered": "\(sessionRecovered)"]
        case .streamingModeActivated(let mode, let detail):
            ["mode": mode, "detail": detail]
        case .streamingModeSwitched(let fromMode, let toMode):
            ["fromMode": fromMode, "toMode": toMode]
        case .screenCaptureStarted(let displayId, let zoneCount, let edgeBias):
            ["displayId": "\(displayId)", "zoneCount": "\(zoneCount)", "edgeBias": String(format: "%.1f", edgeBias)]
        case .screenCaptureFailed(let errorDescription):
            ["errorDescription": errorDescription]
        case .auraSelected(let auraName, let isBuiltin):
            ["auraName": auraName, "isBuiltin": "\(isBuiltin)"]
        case .brightnessChanged(let value):
            ["value": String(format: "%.2f", value)]
        case .settingsChanged(let setting, let newValue):
            ["setting": setting, "newValue": newValue]
        }
    }
}

enum Analytics {
    static func send(_ signal: AnalyticsSignal) {
        guard UserDefaults.standard.bool(forKey: StorageKey.analyticsEnabled) else { return }
        TelemetryDeck.signal(signal.name, parameters: signal.parameters)
    }

    static func initialize() {
        UserDefaults.standard.register(defaults: [StorageKey.analyticsEnabled: true])
        guard UserDefaults.standard.bool(forKey: StorageKey.analyticsEnabled) else { return }
        let config = TelemetryDeck.Config(appID: "F9B0EB7A-F247-47C0-9F85-CBDFAF8FEDE3")
        TelemetryDeck.initialize(config: config)
    }
}
