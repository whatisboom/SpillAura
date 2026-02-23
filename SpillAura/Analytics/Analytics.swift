import Foundation
import TelemetryDeck

enum AnalyticsSignal {
    // Session Reliability
    case entertainmentSessionStarted(channelCount: Int, groupId: String)
    case entertainmentSessionEnded(durationSeconds: Int, reconnectCount: Int)
    case entertainmentSessionFailed(errorReason: String, phase: String)
    case entertainmentSessionReconnect(attemptNumber: Int, previousDurationSeconds: Int)
    case bridgeDiscoveryCompleted(method: String, durationMs: Int)
    case appResumedFromSleep

    // Streaming Health
    case streamingModeActivated(mode: String, detail: String)
    case streamingModeSwitched(fromMode: String, toMode: String)
    case screenCaptureStarted(displayId: UInt32, zoneCount: Int, edgeBias: Double)
    case screenCaptureFailed(errorDescription: String)

    // Onboarding + Pairing
    case bridgeDiscoveryStarted
    case pairingStarted
    case pairingFailed(reason: String)
    case entertainmentGroupSelected(groupName: String, channelCount: Int)

    // Usage
    case auraSelected(auraName: String, isBuiltin: Bool)
    case auraCreated(name: String, colorCount: Int, pattern: String)
    case auraDeleted(name: String)
    case brightnessChanged(value: Double)
    case settingsChanged(setting: String, newValue: String)
    case settingsWindowOpened
    case analyticsOptedOut

    // Zones
    case zonePresetApplied(preset: String, channelCount: Int)
    case zoneRegionAssigned(channelId: UInt8, region: String)
    case displaySelected(monitorCount: Int)
    case edgeBiasChanged(value: Double)
    case channelIdentificationStarted(identifyAll: Bool)

    // Reliability
    case dtlsHandshakeTimeout

    // Product Refinement
    case speedMultiplierChanged(value: Double)
    case auraEditorClosed(action: String, isNew: Bool, colorCount: Int)
    case appTerminated(sessionDurationSeconds: Int)

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
        case .bridgeDiscoveryStarted: "bridgeDiscoveryStarted"
        case .pairingStarted: "pairingStarted"
        case .pairingFailed: "pairingFailed"
        case .entertainmentGroupSelected: "entertainmentGroupSelected"
        case .auraSelected: "auraSelected"
        case .auraCreated: "auraCreated"
        case .auraDeleted: "auraDeleted"
        case .brightnessChanged: "brightnessChanged"
        case .settingsChanged: "settingsChanged"
        case .settingsWindowOpened: "settingsWindowOpened"
        case .analyticsOptedOut: "analyticsOptedOut"
        case .zonePresetApplied: "zonePresetApplied"
        case .zoneRegionAssigned: "zoneRegionAssigned"
        case .displaySelected: "displaySelected"
        case .edgeBiasChanged: "edgeBiasChanged"
        case .channelIdentificationStarted: "channelIdentificationStarted"
        case .dtlsHandshakeTimeout: "dtlsHandshakeTimeout"
        case .speedMultiplierChanged: "speedMultiplierChanged"
        case .auraEditorClosed: "auraEditorClosed"
        case .appTerminated: "appTerminated"
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
        case .appResumedFromSleep:
            [:]
        case .streamingModeActivated(let mode, let detail):
            ["mode": mode, "detail": detail]
        case .streamingModeSwitched(let fromMode, let toMode):
            ["fromMode": fromMode, "toMode": toMode]
        case .screenCaptureStarted(let displayId, let zoneCount, let edgeBias):
            ["displayId": "\(displayId)", "zoneCount": "\(zoneCount)", "edgeBias": String(format: "%.1f", edgeBias)]
        case .screenCaptureFailed(let errorDescription):
            ["errorDescription": errorDescription]
        case .bridgeDiscoveryStarted:
            [:]
        case .pairingStarted:
            [:]
        case .pairingFailed(let reason):
            ["reason": reason]
        case .entertainmentGroupSelected(let groupName, let channelCount):
            ["groupName": groupName, "channelCount": "\(channelCount)"]
        case .auraSelected(let auraName, let isBuiltin):
            ["auraName": auraName, "isBuiltin": "\(isBuiltin)"]
        case .auraCreated(let name, let colorCount, let pattern):
            ["name": name, "colorCount": "\(colorCount)", "pattern": pattern]
        case .auraDeleted(let name):
            ["name": name]
        case .brightnessChanged(let value):
            ["value": String(format: "%.2f", value)]
        case .settingsChanged(let setting, let newValue):
            ["setting": setting, "newValue": newValue]
        case .settingsWindowOpened:
            [:]
        case .analyticsOptedOut:
            [:]
        case .zonePresetApplied(let preset, let channelCount):
            ["preset": preset, "channelCount": "\(channelCount)"]
        case .zoneRegionAssigned(let channelId, let region):
            ["channelId": "\(channelId)", "region": region]
        case .displaySelected(let monitorCount):
            ["monitorCount": "\(monitorCount)"]
        case .edgeBiasChanged(let value):
            ["value": String(format: "%.1f", value)]
        case .channelIdentificationStarted(let identifyAll):
            ["identifyAll": "\(identifyAll)"]
        case .dtlsHandshakeTimeout:
            [:]
        case .speedMultiplierChanged(let value):
            ["value": String(format: "%.2f", value)]
        case .auraEditorClosed(let action, let isNew, let colorCount):
            ["action": action, "isNew": "\(isNew)", "colorCount": "\(colorCount)"]
        case .appTerminated(let sessionDurationSeconds):
            ["sessionDurationSeconds": "\(sessionDurationSeconds)"]
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
