import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: BatteryMonitor

    @AppStorage("lowAlertEnabled") private var lowEnabled = true
    @AppStorage("lowThreshold") private var lowThreshold = 20
    @AppStorage("limitAlertEnabled") private var limitEnabled = false
    @AppStorage("chargeLimit") private var chargeLimit = 80
    @AppStorage("chargingAlertEnabled") private var chargingAlertEnabled = true
    @AppStorage("disconnectAlertEnabled") private var disconnectAlertEnabled = true
    @AppStorage("glowEnabled") private var glowEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true

    @State private var detailsExpanded = false
    @State private var alertsExpanded = false
    @State private var historyDays = 1

    private var statusColor: Color {
        if monitor.isCharging { return .green }
        if monitor.percent <= 20 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            batteryHeader
            historyCard
            detailsCard
            alertsCard
            footer
        }
        .padding(16)
        .frame(width: 330)
        .background(.regularMaterial)
        .onAppear { monitor.refresh() }
    }

    private var batteryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.11))
                        .frame(width: 48, height: 48)
                    Image(systemName: monitor.symbolName)
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(monitor.percent)")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(5, geometry.size.width * CGFloat(min(max(monitor.percent, 0), 100)) / 100))
                }
            }
            .frame(height: 5)

            HStack(spacing: 6) {
                Image(systemName: monitor.onACPower ? "powerplug.fill" : "battery.100")
                    .font(.system(size: 10, weight: .medium))
                Text(monitor.onACPower ? (monitor.isCharging ? "Power adapter connected" : "Connected to power") : "Running on battery")
                Spacer(minLength: 0)
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("History range", selection: $historyDays) {
                    Text("24H").tag(1)
                    Text("7D").tag(7)
                    Text("30D").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }

            let samples = monitor.history(for: historyDays)
            BatterySparkline(values: samples.map { Double($0.percent) })
                .frame(height: 48)

            HStack {
                Text(historyRangeLabel)
                Spacer()
                Text(samples.last.map { "Now \($0.percent)%" } ?? "Gathering data")
                    .foregroundStyle(.primary.opacity(0.75))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if samples.count < 2 {
                Text("History builds while the app is running.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailsCard: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(spacing: 9) {
                detailRow("Battery health", value: percentText(monitor.healthPercent))
                detailRow("Cycle count", value: monitor.cycleCount.map(String.init))
                detailRow("Temperature", value: monitor.temperatureC.map { String(format: "%.1f °C", $0) })
                detailRow("Voltage", value: monitor.voltageV.map { String(format: "%.3f V", $0) })
                detailRow("Current", value: monitor.currentA.map { String(format: "%.3f A", $0) })
                detailRow("Power estimate", value: monitor.powerW.map { String(format: "%.2f W", $0) })
                detailRow("Time remaining", value: monitor.runtimeDescription)
                detailRow("Design capacity", value: capacityText(monitor.designCapacityMAh))
                detailRow("Maximum capacity", value: capacityText(monitor.maximumCapacityMAh))
                if let health = monitor.healthPercent, health < 80 {
                    Label("Capacity is significantly reduced.", systemImage: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Some readings depend on what the battery controller reports. Power is an estimate, not adapter input wattage.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)
        } label: {
            Label("Battery information", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
        }
        .disclosureGroupStyle(.automatic)
        .padding(.horizontal, 2)
    }

    private var alertsCard: some View {
        DisclosureGroup(isExpanded: $alertsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Low battery", isOn: $lowEnabled)
                if lowEnabled {
                    settingStepper("Notify at", value: $lowThreshold, range: 1...50, suffix: "%")
                }

                Toggle("Charge threshold reminder", isOn: $limitEnabled)
                if limitEnabled {
                    settingStepper("Notify at", value: $chargeLimit, range: 50...100, suffix: "%")
                    Text("Reminder only; macOS doesn't provide a general public API to enforce a charge cap.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.6)
                Toggle("Charger connected", isOn: $chargingAlertEnabled)
                Toggle("Charger disconnected", isOn: $disconnectAlertEnabled)
                Toggle("Screen-edge glow", isOn: $glowEnabled)
                Toggle("Alert sounds", isOn: $soundEnabled)
            }
            .font(.system(size: 11))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.top, 10)
        } label: {
            Label("Notifications", systemImage: "bell.badge")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 5, height: 5)
            Text(monitor.lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Waiting for battery data")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Refresh battery information")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Quit")
            .keyboardShortcut("q")
        }
        .padding(.top, 1)
    }

    private var statusText: String {
        if monitor.isCharging { return "Charging · \(monitor.runtimeDescription) to full" }
        if monitor.onACPower { return "Connected to power" }
        return "\(monitor.runtimeDescription) remaining"
    }

    private var historyRangeLabel: String {
        switch historyDays {
        case 7: return "Last 7 days"
        case 30: return "Last 30 days"
        default: return "Last 24 hours"
        }
    }

    private func detailRow(_ label: String, value: String?) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value ?? "Unavailable")
                .foregroundStyle(.primary.opacity(value == nil ? 0.45 : 0.9))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
    }

    private func settingStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Stepper("\(value.wrappedValue)\(suffix)", value: value, in: range)
                .fixedSize()
        }
        .padding(.leading, 4)
    }

    private func percentText(_ value: Double?) -> String? {
        value.map { String(format: "%.0f%%", $0) }
    }

    private func capacityText(_ value: Int?) -> String? {
        value.map { "\($0) mAh" }
    }
}

private struct BatterySparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.025))
                if values.count >= 2 {
                    Path { path in
                        let width = geometry.size.width - 12
                        let height = geometry.size.height - 12
                        let minValue = max(0, (values.min() ?? 0) - 3)
                        let maxValue = min(100, (values.max() ?? 100) + 3)
                        let span = max(1, maxValue - minValue)
                        for (index, value) in values.enumerated() {
                            let x = 6 + width * CGFloat(index) / CGFloat(values.count - 1)
                            let y = 6 + height * CGFloat(1 - (value - minValue) / span)
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                } else {
                    Text("Collecting history")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
