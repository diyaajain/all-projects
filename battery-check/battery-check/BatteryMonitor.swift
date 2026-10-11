import Foundation
import Combine
import IOKit
import IOKit.ps
import UserNotifications
import SwiftUI

struct BatterySnapshot: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let percent: Int
    let onACPower: Bool
    let isCharging: Bool
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var percent = 0
    @Published var isCharging = false
    @Published var onACPower = false
    @Published var minutesRemaining: Int?
    @Published var cycleCount: Int?
    @Published var healthPercent: Double?
    @Published var temperatureC: Double?
    @Published var voltageV: Double?
    @Published var currentA: Double?
    @Published var powerW: Double?
    @Published var designCapacityMAh: Int?
    @Published var maximumCapacityMAh: Int?
    @Published var history: [BatterySnapshot] = []
    @Published var lastUpdated: Date?

    private var timer: Timer?
    private var previousOnACPower: Bool?
    private var previousCharging: Bool?
    private var previousPercent: Int?
    private var previousLowState = false
    private var previousLimitState = false
    private var lastSnapshotDate: Date?

    private let historyKey = "batteryHistory.v1"

    init() {
        UserDefaults.standard.register(defaults: [
            "lowAlertEnabled": true,
            "lowThreshold": 20,
            "limitAlertEnabled": false,
            "chargeLimit": 80,
            "chargingAlertEnabled": true,
            "disconnectAlertEnabled": true,
            "glowEnabled": true,
            "soundEnabled": true
        ])
        loadHistory()
        requestNotificationPermission()
        refresh()
        startPowerSourceNotifications()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    deinit { timer?.invalidate() }

    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var runtimeDescription: String {
        guard let minutesRemaining, minutesRemaining >= 0 else { return "Unavailable" }
        return "About \(minutesRemaining / 60)h \(minutesRemaining % 60)m"
    }

    func refresh() {
        let oldAC = previousOnACPower
        let oldCharging = previousCharging
        let oldPercent = previousPercent

        readPowerSource()
        readSmartBattery()
        lastUpdated = Date()
        checkAlerts(oldAC: oldAC, oldCharging: oldCharging, oldPercent: oldPercent)
        recordSnapshotIfDue()
        previousOnACPower = onACPower
        previousCharging = isCharging
        previousPercent = percent
    }

    func history(for days: Int) -> [BatterySnapshot] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return history.filter { $0.date >= cutoff }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func startPowerSourceNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }

            let monitor = Unmanaged<BatteryMonitor>
                .fromOpaque(context)
                .takeUnretainedValue()

            Task { @MainActor in
                monitor.refresh()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func readPowerSource() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            percent = description[kIOPSCurrentCapacityKey] as? Int ?? percent
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            onACPower = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let timeKey = onACPower ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[timeKey] as? Int,
               minutes >= 0,
               minutes != Int(kIOPSTimeRemainingUnlimited) {

                minutesRemaining = minutes
            } else {
                minutesRemaining = nil
            }
            return
        }
    }

    private func readSmartBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return }

        func int(_ key: String) -> Int? { (dictionary[key] as? NSNumber)?.intValue }
        cycleCount = int("CycleCount")
        let design = int("DesignCapacity")
        let maximum = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity") ?? int("MaxCapacity")
        designCapacityMAh = design
        maximumCapacityMAh = maximum
        if let design, design > 0, let maximum {
            healthPercent = min(100, max(0, Double(maximum) / Double(design) * 100))
        }
        if let temperature = int("Temperature") { temperatureC = Double(temperature) / 100 }
        if let voltage = int("Voltage") { voltageV = Double(voltage) / 1000 }
        if let amperage = int("InstantAmperage") ?? int("Amperage") {
            currentA = Double(amperage) / 1000
            if let voltage = int("Voltage") {
                powerW = abs(Double(amperage) * Double(voltage)) / 1_000_000
            }
        }
    }

    private func checkAlerts(oldAC: Bool?, oldCharging: Bool?, oldPercent: Int?) {
        let defaults = UserDefaults.standard
        let glow = defaults.bool(forKey: "glowEnabled")
        let soundEnabled = defaults.bool(forKey: "soundEnabled")

        if let oldAC, !oldAC, onACPower, defaults.bool(forKey: "chargingAlertEnabled") {
            showAlert(title: "Power adapter connected",
                      message: isCharging ? "Charging started at \(percent)%." : "Your Mac is connected to power.",
                      symbol: "bolt.fill", color: .green, sound: "Ping", glow: glow, soundEnabled: soundEnabled)
        } else if let oldAC, oldAC, !onACPower, defaults.bool(forKey: "disconnectAlertEnabled") {
            let runtime = minutesRemaining.map { "About \($0 / 60)h \($0 % 60)m remaining" } ?? "Runtime estimate unavailable"
            showAlert(title: "Power adapter disconnected",
                      message: "\(percent)% battery · \(runtime)",
                      symbol: "battery.75percent", color: .orange, sound: "Ping", glow: glow, soundEnabled: soundEnabled)
        } else if let oldCharging, !oldCharging, isCharging, oldAC == true,
                  defaults.bool(forKey: "chargingAlertEnabled") {
            showAlert(title: "Charging started", message: "Battery at \(percent)%.",
                      symbol: "battery.100percent.bolt", color: .green, sound: "Ping", glow: glow, soundEnabled: soundEnabled)
        }

        let lowThreshold = defaults.integer(forKey: "lowThreshold")
        let isLow = defaults.bool(forKey: "lowAlertEnabled") && !onACPower && percent <= lowThreshold
        if isLow && !previousLowState {
            showAlert(title: "Battery low", message: "\(percent)% remaining. Time to plug in.",
                      symbol: "battery.25percent", color: .red, sound: "Basso", glow: glow, soundEnabled: soundEnabled)
        }
        previousLowState = isLow

        let limit = defaults.integer(forKey: "chargeLimit")
        let crossedLimit = onACPower && (oldPercent ?? percent) < limit && percent >= limit
        let isAtLimit = defaults.bool(forKey: "limitAlertEnabled") && crossedLimit
        if isAtLimit && !previousLimitState {
            showAlert(title: "Charge limit reached", message: "Battery is at \(percent)%. You can unplug now.",
                      symbol: "battery.100percent", color: .orange, sound: "Glass", glow: glow, soundEnabled: soundEnabled)
        }
        previousLimitState = defaults.bool(forKey: "limitAlertEnabled") && onACPower && percent >= limit
        if percent < limit || !onACPower { previousLimitState = false }
    }

    private func showAlert(title: String, message: String, symbol: String, color: Color,
                           sound: String, glow: Bool, soundEnabled: Bool) {
        AlertPresenter.shared.show(title: title, message: message, symbol: symbol, color: color,
                                   sound: soundEnabled ? sound : nil, glow: glow)
    }

    private func recordSnapshotIfDue() {
        let now = Date()
        if let lastSnapshotDate, now.timeIntervalSince(lastSnapshotDate) < 300 { return }
        history.append(BatterySnapshot(date: now, percent: percent, onACPower: onACPower, isCharging: isCharging))
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        history = Array(history.filter { $0.date >= cutoff }.suffix(9_000))
        lastSnapshotDate = now
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([BatterySnapshot].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        history = saved.filter { $0.date >= cutoff }
        lastSnapshotDate = history.last?.date
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
