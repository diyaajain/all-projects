import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Vessels & preferences

struct Vessel { let name: String; let icon: String; let oz: Double }

let vessels = [
    Vessel(name: "Teacup", icon: "🍵", oz: 8),
    Vessel(name: "Mug", icon: "☕️", oz: 12),
    Vessel(name: "Tankard", icon: "🍺", oz: 20),
    Vessel(name: "Flagon", icon: "🏺", oz: 32),
    Vessel(name: "Custom", icon: "🪣", oz: 0),
]

enum Prefs {
    private static let d = UserDefaults.standard
    static var weight: Double { d.object(forKey: "weight") as? Double ?? 150 }
    static var vessel: Int { d.object(forKey: "vessel") as? Int ?? 2 }
    static var customOz: Double { d.object(forKey: "customOz") as? Double ?? 16 }
    static var interval: Double { d.object(forKey: "interval") as? Double ?? 30 }
    static var awake: Double { d.object(forKey: "awake") as? Double ?? 14 }
    static var on: Bool { d.bool(forKey: "on") }

    static var goal: Double { weight / 2 }                       // classic rule: half your weight (lb) in oz
    static var vesselOz: Double { vessel == 4 ? customOz : vessels[vessel].oz }
    static var vesselName: String { vessels[vessel].name.lowercased() }
    static var perReminder: Double { goal / max(1, awake * 60 / interval) }

    /// Local-time day string, e.g. "2026-10-09". offset -1 = yesterday.
    static func day(_ offset: Int = 0) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// A streak only counts if the goal was last hit today or yesterday.
    static func liveStreak(_ streak: Int, _ lastGoalDay: String) -> Int {
        (lastGoalDay == day(0) || lastGoalDay == day(-1)) ? streak : 0
    }

    static func rollDay() {
        if d.string(forKey: "day") != day(0) {
            d.set(day(0), forKey: "day")
            d.set(0.0, forKey: "drunk")
        }
    }
}

// MARK: - Reminder engine

final class Shire: NSObject, UNUserNotificationCenterDelegate {
    private var timer: Timer?
    private let lines = [
        "Second breakfast calls — and so does water!",
        "Even Frodo stopped at the stream. Have a sip.",
        "A hobbit well-watered is a hobbit well-pleased.",
        "Put the kettle down and pick the tankard up.",
        "The road is long. Hydrate, Master Baggins.",
        "Elevenses? Water first, then cake.",
        "The Shire doesn't drink itself dry. Sip now!",
    ]

    override init() {
        super.init()
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Prefs.rollDay()
        if Prefs.on { start() }
    }

    func start() {
        stop()
        // Random-ish: anywhere from 70% to 130% of the chosen interval
        let delay = Prefs.interval * 60 * Double.random(in: 0.7...1.3)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.remind()
            self?.start()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func remind() {
        Prefs.rollDay()
        let oz = Prefs.perReminder
        let fraction = oz / max(1, Prefs.vesselOz)
        let content = UNMutableNotificationContent()
        content.title = "🌿 Time for a Sip"
        content.body = "\(lines.randomElement()!)\nDrink about \(Int(oz.rounded())) oz (\(String(format: "%.0f", fraction * 100))% of your \(Prefs.vesselName))."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }
}

// MARK: - App

@main
struct HobbitHydrationApp: App {
    @State private var shire = Shire()
    @AppStorage("drunk") private var drunk = 0.0
    @AppStorage("weight") private var weight = 150.0
    @AppStorage("streak") private var streak = 0
    @AppStorage("lastGoalDay") private var lastGoalDay = ""

    var body: some Scene {
        MenuBarExtra {
            ContentView(shire: shire)
        } label: {
            let live = Prefs.liveStreak(streak, lastGoalDay)
            Text("🍺 \(Int(drunk))/\(Int(weight / 2)) oz" + (live > 0 ? " · 🔥\(live)" : ""))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Theme

enum Theme {
    static let bg = Color(red: 0.23, green: 0.15, blue: 0.09)       // deep chocolate
    static let cream = Color(red: 0.96, green: 0.90, blue: 0.77)
    static let caramel = Color(red: 0.62, green: 0.40, blue: 0.19)
    static let gold = Color(red: 0.85, green: 0.64, blue: 0.25)
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .bold : .regular, design: .serif)
    }
}

// MARK: - UI

struct ContentView: View {
    let shire: Shire
    @AppStorage("weight") var weight = 150.0
    @AppStorage("vessel") var vessel = 2
    @AppStorage("customOz") var customOz = 16.0
    @AppStorage("interval") var interval = 30.0
    @AppStorage("awake") var awake = 14.0
    @AppStorage("drunk") var drunk = 0.0
    @AppStorage("on") var on = false
    @AppStorage("streak") var streak = 0
    @AppStorage("bestStreak") var best = 0
    @AppStorage("lastGoalDay") var lastGoalDay = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var liveStreak: Int { Prefs.liveStreak(streak, lastGoalDay) }

    func logDrink() {
        drunk += vesselOz
        let today = Prefs.day(0)
        if drunk >= goal && lastGoalDay != today {
            streak = (lastGoalDay == Prefs.day(-1)) ? streak + 1 : 1
            lastGoalDay = today
            best = max(best, streak)
        }
    }

    var goal: Double { weight / 2 }
    var vesselOz: Double { vessel == 4 ? customOz : vessels[vessel].oz }
    var perReminder: Double { goal / max(1, awake * 60 / interval) }
    var progress: Double { min(drunk / max(goal, 1), 1) }

    var rank: String {
        switch progress {
        case ..<0.25: return "Still snug in Bag End"
        case ..<0.5: return "Off to the Green Dragon"
        case ..<0.75: return "Crossing the Brandywine"
        case ..<1: return "Nearly at Rivendell!"
        default: return "Quest complete — the Ring is in the fire! 🔥"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🌿 The Hobbit's Hydration").font(Theme.font(20, bold: true))
                Text("Second breakfast is nothing without water").font(Theme.font(12)).italic().opacity(0.7)
            }

            // Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Int(drunk)) of \(Int(goal)) oz today").font(Theme.font(14, bold: true))
                    Spacer()
                    Text("\(Int(progress * 100))%").font(Theme.font(14))
                }
                ProgressView(value: progress).tint(Theme.gold)
                Text(rank).font(Theme.font(12)).italic()
                HStack {
                    Text("🔥 \(liveStreak)-day streak").font(Theme.font(13, bold: true))
                    Spacer()
                    Text("best: \(best)").font(Theme.font(11)).opacity(0.7)
                }
                if liveStreak > 0 && lastGoalDay != Prefs.day(0) {
                    Text("Reach your goal today to keep it alive!").font(Theme.font(10)).italic().opacity(0.7)
                }
            }

            Button {
                logDrink()
            } label: {
                Text("🍺  I drank a \(vessels[vessel].name.lowercased()) (\(Int(vesselOz)) oz)")
                    .font(Theme.font(14, bold: true)).frame(maxWidth: .infinity).padding(8)
                    .background(Theme.caramel).foregroundColor(.white).cornerRadius(8)
            }.buttonStyle(.plain)

            Divider()

            // Vessel
            Text("Your vessel").font(Theme.font(13, bold: true))
            HStack(spacing: 6) {
                ForEach(vessels.indices, id: \.self) { i in
                    Button { vessel = i } label: {
                        VStack(spacing: 2) {
                            Text(vessels[i].icon).font(.system(size: 20))
                            Text(vessels[i].name).font(Theme.font(10))
                            Text(i == 4 ? "\(Int(customOz))oz" : "\(Int(vessels[i].oz))oz").font(Theme.font(9)).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(vessel == i ? Theme.gold.opacity(0.45) : Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(vessel == i ? Theme.gold : .clear, lineWidth: 1.5))
                        .cornerRadius(8)
                    }.buttonStyle(.plain)
                }
            }
            if vessel == 4 {
                Stepper("Custom size: \(Int(customOz)) oz", value: $customOz, in: 2...64, step: 1).font(Theme.font(12))
            }

            // Body & goal
            Stepper("Your weight: \(Int(weight)) lb → goal \(Int(goal)) oz", value: $weight, in: 60...400, step: 5)
                .font(Theme.font(12))
            Stepper("Hours awake: \(Int(awake))", value: $awake, in: 4...20).font(Theme.font(12))

            // Interval
            VStack(alignment: .leading, spacing: 4) {
                Text("Remind me every ~\(Int(interval)) min").font(Theme.font(13, bold: true))
                Slider(value: $interval, in: 5...120, step: 5).tint(Theme.gold)
                Text("Sip about \(Int(perReminder.rounded())) oz each time — roughly \(String(format: "%.1f", goal / max(vesselOz, 1))) \(vessels[vessel].name.lowercased())s a day.")
                    .font(Theme.font(11)).italic().opacity(0.75)
                Text("Reminders pop up a little randomly, like a surprise visit from Gandalf.")
                    .font(Theme.font(10)).opacity(0.55)
            }

            Toggle("Remind me, as a good hobbit would", isOn: $on)
                .toggleStyle(.switch).font(Theme.font(13, bold: true))

            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.switch).font(Theme.font(12))

            HStack {
                Button("Reset today") { drunk = 0 }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.font(Theme.font(11)).buttonStyle(.link)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundColor(Theme.cream)
        .tint(Theme.gold)
        .background(Theme.bg)
        .environment(\.colorScheme, .dark)
        .onChange(of: on) { _ in on ? shire.start() : shire.stop() }
        .onChange(of: interval) { _ in if on { shire.start() } }
        .onChange(of: launchAtLogin) { enable in
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
        .onAppear { Prefs.rollDay() }
    }
}
