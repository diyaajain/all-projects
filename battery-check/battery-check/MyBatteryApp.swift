import SwiftUI

@main
struct MyBatteryApp: App {
    @StateObject private var monitor = BatteryMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                BatteryMenuBarLabel(monitor: monitor)
                Text("\(monitor.percent)%")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
