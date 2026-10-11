import SwiftUI
import AppKit

/// Minimal battery body. The percentage is shown beside the icon, not inside it.
struct BatteryIconView: View {
    let percent: Int
    let fill: Color

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill.opacity(0.28))
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill)
                        .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(fill.opacity(0.55))
                .frame(width: 2, height: 5)
        }
        .padding(.vertical, 1)
    }
}

enum BatteryIcon {
    @MainActor
    static func image(percent: Int, charging: Bool) -> NSImage {
        let color: Color?
        if charging { color = .green }
        else if percent <= 10 { color = .red }
        else if percent <= 20 { color = .orange }
        else { color = nil }
        let renderer = ImageRenderer(content: BatteryIconView(percent: percent, fill: color ?? .black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = color == nil
        return image
    }
}

struct BatteryMenuBarLabel: View {
    @ObservedObject var monitor: BatteryMonitor
    var body: some View {
        Image(nsImage: BatteryIcon.image(percent: monitor.percent, charging: monitor.isCharging))
    }
}
