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

struct Entry: Codable, Identifiable { var id = UUID(); var t: Date; var oz: Double }

func fmt(_ oz: Double) -> String {
    oz.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(oz))" : String(format: "%.1f", oz)
}

enum Prefs {
    private static let d = UserDefaults.standard
    static var weight: Double { d.object(forKey: "weight") as? Double ?? 150 }
    static var vessel: Int { d.object(forKey: "vessel") as? Int ?? 2 }
    static var customOz: Double { d.object(forKey: "customOz") as? Double ?? 16 }
    static var interval: Double { d.object(forKey: "interval") as? Double ?? 30 }
    static var wake: Int { d.object(forKey: "wake") as? Int ?? 7 }
    static var bedtime: Int { d.object(forKey: "bedtime") as? Int ?? 22 }
    static var on: Bool { d.bool(forKey: "on") }

    static var awakeHours: Double { Double(max(1, bedtime - wake)) }
    static var goal: Double { weight / 2 }                       // half your weight (lb) in oz
    static var vesselOz: Double { vessel == 4 ? customOz : vessels[vessel].oz }
    static var vesselName: String { vessels[vessel].name.lowercased() }
    static var perReminder: Double { goal / max(1, awakeHours * 60 / interval) }

    // Quiet hours
    static var isAwake: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= wake && h < bedtime
    }
    /// How far through the awake window we are (0...1) — used for Bilbo's mood.
    static var expectedProgress: Double {
        let c = Calendar.current
        let now = Double(c.component(.hour, from: Date())) + Double(c.component(.minute, from: Date())) / 60
        return min(max((now - Double(wake)) / awakeHours, 0), 1)
    }

    // Days (local time)
    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func day(_ offset: Int = 0) -> String {
        dayString(Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date())
    }
    static func liveStreak(_ streak: Int, _ lastGoalDay: String) -> Int {
        (lastGoalDay == day(0) || lastGoalDay == day(-1)) ? streak : 0
    }
    static func rollDay() {
        if d.string(forKey: "day") != day(0) {
            d.set(day(0), forKey: "day")
            d.set(0.0, forKey: "drunk")
            d.removeObject(forKey: "log")
        }
    }

    // Today's individual drinks (for undo / editing)
    static var log: [Entry] {
        guard let data = d.data(forKey: "log") else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
    static func saveLog(_ l: [Entry]) { d.set(try? JSONEncoder().encode(l), forKey: "log") }

    // History (last 30 days) for the Map of the Journey
    static var history: [String: Double] { d.dictionary(forKey: "history") as? [String: Double] ?? [:] }

    /// Logs water, updates history and streak. Used by the button AND the notification action.
    @discardableResult
    static func logDrink(oz: Double) -> (goalHit: Bool, streak: Int) {
        rollDay()
        let total = d.double(forKey: "drunk") + oz
        d.set(total, forKey: "drunk")
        var l = log; l.append(Entry(t: Date(), oz: oz)); saveLog(l)
        let keep = Set((-29...0).map { day($0) })
        var h = history.filter { keep.contains($0.key) }
        h[day()] = total
        d.set(h, forKey: "history")

        let last = d.string(forKey: "lastGoalDay") ?? ""
        guard total >= goal, last != day() else { return (false, d.integer(forKey: "streak")) }
        let s = (last == day(-1)) ? d.integer(forKey: "streak") + 1 : 1
        d.set(s, forKey: "streak")
        d.set(day(), forKey: "lastGoalDay")
        d.set(max(s, d.integer(forKey: "bestStreak")), forKey: "bestStreak")
        return (true, s)
    }

    /// If today's streak credit was earned and we've dropped below goal, take it back.
    private static func revokeStreakIfNeeded(total: Double) {
        guard total < goal, d.string(forKey: "lastGoalDay") == day() else { return }
        let n = max(0, d.integer(forKey: "streak") - 1)
        d.set(n, forKey: "streak")
        d.set(n > 0 ? day(-1) : "", forKey: "lastGoalDay")
    }

    private static func setToday(_ total: Double) {
        d.set(total, forKey: "drunk")
        var h = history
        h[day()] = total
        d.set(h, forKey: "history")
        revokeStreakIfNeeded(total: total)
    }

    static func removeEntry(_ id: UUID) {
        var l = log
        guard let i = l.firstIndex(where: { $0.id == id }) else { return }
        let e = l.remove(at: i)
        saveLog(l)
        setToday(max(0, d.double(forKey: "drunk") - e.oz))
    }

    static func resetToday() {
        d.removeObject(forKey: "log")
        setToday(0)
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
        let drink = UNNotificationAction(identifier: "DRINK", title: "🍺 Drank my sip", options: [])
        c.setNotificationCategories([
            UNNotificationCategory(identifier: "SIP", actions: [drink], intentIdentifiers: [], options: [])
        ])
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Prefs.rollDay()
        if Prefs.on { start() }
    }

    func start() {
        stop()
        // Random-ish: 70%–130% of the chosen interval
        let delay = Prefs.interval * 60 * Double.random(in: 0.7...1.3)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.remind()
            self?.start()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func remind() {
        guard Prefs.isAwake else { return }          // quiet hours: stay silent
        Prefs.rollDay()
        let oz = Prefs.perReminder
        let pct = oz / max(1, Prefs.vesselOz) * 100
        let content = UNMutableNotificationContent()
        content.title = "🌿 Time for a Sip"
        content.body = "\(lines.randomElement()!)\nDrink about \(Int(oz.rounded())) oz (\(String(format: "%.0f", pct))% of your \(Prefs.vesselName))."
        content.sound = .default
        content.categoryIdentifier = "SIP"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }

    // "🍺 Drank my sip" button on the notification
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler h: @escaping () -> Void) {
        if r.actionIdentifier == "DRINK" {
            Prefs.logDrink(oz: Prefs.perReminder)
            Sound.play("splash", fallback: "Bottle")
        }
        h()
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
    @AppStorage("barStyle") private var barStyle = 0

    var body: some Scene {
        MenuBarExtra {
            ContentView(shire: shire)
        } label: {
            let live = Prefs.liveStreak(streak, lastGoalDay)
            let p = min(drunk / max(weight / 2, 1), 1)
            let amount = "\(Int(drunk))/\(Int(weight / 2))" + (live > 0 ? " · \(live)d" : "")
            switch barStyle {
            case 1: Image(nsImage: menuBarImage(progress: p, text: nil, bar: false))
            case 2: Image(nsImage: menuBarImage(progress: p, text: amount, bar: false))
            case 3: Image(nsImage: menuBarImage(progress: p, text: nil, bar: true))
            default: Text("🍺 \(Int(drunk))/\(Int(weight / 2)) oz" + (live > 0 ? " · 🔥\(live)" : ""))
            }
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

// MARK: - Sound

enum Sound {
    private static var playing: [NSSound] = []
    /// Plays a bundled .wav (splash / fanfare); falls back to a macOS system sound if it isn't in the project.
    static func play(_ name: String, fallback: String) {
        guard UserDefaults.standard.object(forKey: "sound") as? Bool ?? true else { return }
        var snd: NSSound?
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            snd = NSSound(contentsOf: url, byReference: true)
        } else {
            snd = NSSound(named: NSSound.Name(fallback))
        }
        guard let snd else { return }
        snd.volume = 0.6
        playing = Array((playing + [snd]).suffix(4))
        snd.play()
    }
}

// MARK: - Menu bar icon (template image: macOS tints it for light/dark)

func menuBarImage(progress: Double, text: String?, bar: Bool) -> NSImage {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                .foregroundColor: NSColor.black]
    let textSize = text.map { ($0 as NSString).size(withAttributes: attrs) } ?? .zero
    let iconW: CGFloat = bar ? 34 : 16
    let gap: CGFloat = text == nil ? 0 : 5
    let img = NSImage(size: NSSize(width: iconW + gap + textSize.width, height: 18), flipped: false) { rect in
        if bar {
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 6.5, width: iconW, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 6.5, width: max(5, iconW * progress), height: 5), xRadius: 2.5, yRadius: 2.5).fill()
        } else {
            let c = NSPoint(x: 8, y: 9)
            let track = NSBezierPath()
            track.appendArc(withCenter: c, radius: 6, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            if progress > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: 6, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
        }
        if let t = text {
            (t as NSString).draw(at: NSPoint(x: iconW + gap, y: (rect.height - textSize.height) / 2), withAttributes: attrs)
        }
        return true
    }
    img.isTemplate = true
    return img
}

// MARK: - Main panel

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

enum Mood { case calm, happy, worried }
struct Celebration { let start: Date; let doom: Bool }

struct ContentView: View {
    let shire: Shire
    @AppStorage("weight") var weight = 150.0
    @AppStorage("vessel") var vessel = 2
    @AppStorage("customOz") var customOz = 16.0
    @AppStorage("interval") var interval = 30.0
    @AppStorage("wake") var wake = 7
    @AppStorage("bedtime") var bedtime = 22
    @AppStorage("drunk") var drunk = 0.0
    @AppStorage("on") var on = false
    @AppStorage("streak") var streak = 0
    @AppStorage("bestStreak") var best = 0
    @AppStorage("lastGoalDay") var lastGoalDay = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hopStart: Date?
    @State private var cheer: String?
    @State private var celebration: Celebration?
    @AppStorage("barStyle") var barStyle = 0
    @AppStorage("sound") var sound = true
    @State private var showSettings = false
    @State private var showLog = false
    @State private var customText = ""
    @State private var contentHeight: CGFloat = 640

    /// Never taller than the visible screen area (below the menu bar)
    var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) - 30 }

    private let cheers = ["Splendid!", "Hooray! A proper hobbit.", "Ahh, lovely. Back to my armchair!",
                          "Excellent sip, my friend.", "Fit for a second breakfast!"]
    private let milestones = [3, 7, 14, 30, 50, 100, 365]

    var goal: Double { weight / 2 }
    var vesselOz: Double { vessel == 4 ? customOz : vessels[vessel].oz }
    var perReminder: Double { goal / max(1, Double(max(1, bedtime - wake)) * 60 / interval) }
    var progress: Double { min(drunk / max(goal, 1), 1) }
    var liveStreak: Int { Prefs.liveStreak(streak, lastGoalDay) }

    var mood: Mood {
        let expected = Prefs.expectedProgress
        if progress >= 1 { return .happy }
        if Prefs.isAwake && expected - progress > 0.2 { return .worried }
        if progress > 0.05 && progress >= expected { return .happy }
        return .calm
    }

    var rank: String {
        switch progress {
        case ..<0.25: return "Still snug in Bag End"
        case ..<0.5: return "Off to the Green Dragon"
        case ..<0.75: return "Crossing the Brandywine"
        case ..<1: return "Nearly at Rivendell!"
        default: return "Quest complete — the Ring is in the fire! 🔥"
        }
    }

    var bilboSays: String {
        if let cheer { return cheer }
        if mood == .worried { return "Oh dear, we're behind schedule. A sip, quick!" }
        switch progress {
        case ..<0.25: return "Is it elevenses yet? Water first, then!"
        case ..<0.5: return "Not a bad start. I've had worse mornings in Bag End."
        case ..<0.75: return "Past the Brandywine! Keep sipping."
        case ..<1: return "Rivendell is in sight. One more tankard!"
        default: return "Goal reached! I could sing about it."
        }
    }

    func logDrink(_ oz: Double) {
        let r = Prefs.logDrink(oz: oz)
        cheer = cheers.randomElement()
        hopStart = Date()
        Sound.play(r.goalHit ? "fanfare" : "splash", fallback: r.goalHit ? "Hero" : "Bottle")
        if r.goalHit {
            let doom = milestones.contains(r.streak)
            celebration = Celebration(start: Date(), doom: doom)
            cheer = doom ? "Mount Doom! \(r.streak) days in a row!" : "Goal reached! The Shire rejoices!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { cheer = nil }
    }

    var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🌿 The Hobbit's Hydration").font(Theme.font(20, bold: true))
                Text("Second breakfast is nothing without water").font(Theme.font(12)).italic().opacity(0.7)
            }

            BilboScene(progress: progress, message: bilboSays, mood: mood, streak: liveStreak,
                       hopStart: hopStart, celebration: celebration)

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

            HStack(spacing: 8) {
                Button { logDrink(vesselOz) } label: {
                    Text("🍺  I drank a \(vessels[vessel].name.lowercased()) (\(fmt(vesselOz)) oz)")
                        .font(Theme.font(14, bold: true)).frame(maxWidth: .infinity).padding(8)
                        .background(Theme.caramel).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain)
                Button { if let e = Prefs.log.last { Prefs.removeEntry(e.id) } } label: {
                    Text("↩︎").font(Theme.font(16, bold: true)).frame(width: 34).padding(.vertical, 8)
                        .background(Color.white.opacity(0.12)).cornerRadius(8)
                }
                .buttonStyle(.plain).disabled(Prefs.log.isEmpty).opacity(Prefs.log.isEmpty ? 0.35 : 1)
                .help("Undo last drink")
            }

            JourneyMap(goal: goal, today: drunk)

            Divider()

            Toggle("Remind me, as a good hobbit would", isOn: $on)
                .toggleStyle(.switch).font(Theme.font(13, bold: true))

            Foldout(title: "📜 Today's log", open: $showLog)
            if showLog { logSection }

            Foldout(title: "⚙️ Settings", open: $showSettings)
            if showSettings { settings }

            HStack {
                Button("Reset today") { Prefs.resetToday() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.font(Theme.font(11)).buttonStyle(.link)
        }
        .padding(16)
        .frame(width: 340)
        .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
        }
        .frame(width: 340, height: min(max(contentHeight, 200), maxHeight))
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
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

    var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("oz", text: $customText).textFieldStyle(.roundedBorder).frame(width: 60)
                Button("Add custom amount") {
                    if let oz = Double(customText), oz > 0, oz <= 128 { logDrink(oz); customText = "" }
                }
            }
            let entries = Array(Prefs.log.reversed())
            if entries.isEmpty {
                Text("Nothing logged with the new log yet today.").font(Theme.font(11)).italic().opacity(0.6)
            }
            ForEach(entries) { e in
                HStack {
                    Text(e.t, style: .time).font(Theme.font(12))
                    Text("\(fmt(e.oz)) oz").font(Theme.font(12, bold: true))
                    Spacer()
                    Button { Prefs.removeEntry(e.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help("Remove this drink")
                }
            }
        }
    }

    var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                        .background(vessel == i ? Theme.gold.opacity(0.35) : Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(vessel == i ? Theme.gold : .clear, lineWidth: 1.5))
                        .cornerRadius(8)
                    }.buttonStyle(.plain)
                }
            }
            if vessel == 4 {
                Stepper("Custom size: \(Int(customOz)) oz", value: $customOz, in: 2...64, step: 1).font(Theme.font(12))
            }
            Stepper("Your weight: \(Int(weight)) lb → goal \(Int(goal)) oz", value: $weight, in: 60...400, step: 5)
                .font(Theme.font(12))

            Text("Quiet hours").font(Theme.font(13, bold: true))
            Stepper("Wake up: \(String(format: "%02d", wake)):00", value: $wake, in: 0...12).font(Theme.font(12))
            Stepper("Bedtime: \(String(format: "%02d", bedtime)):00", value: $bedtime, in: 13...23).font(Theme.font(12))
            Text("No reminders between bedtime and wake-up.").font(Theme.font(10)).italic().opacity(0.6)

            Text("Remind me every ~\(Int(interval)) min").font(Theme.font(13, bold: true))
            Slider(value: $interval, in: 5...120, step: 5).tint(Theme.gold)
            Text("Sip about \(Int(perReminder.rounded())) oz each time, roughly \(String(format: "%.1f", goal / max(vesselOz, 1))) \(vessels[vessel].name.lowercased())s a day.")
                .font(Theme.font(11)).italic().opacity(0.75)

            Text("Menu bar style").font(Theme.font(13, bold: true))
            Picker("", selection: $barStyle) {
                Text("🍺 Text").tag(0)
                Text("Ring").tag(1)
                Text("Ring + oz").tag(2)
                Text("Bar").tag(3)
            }.pickerStyle(.segmented).labelsHidden()

            Toggle("Sound effects", isOn: $sound).toggleStyle(.switch).font(Theme.font(12))
            Toggle("Open at login", isOn: $launchAtLogin).toggleStyle(.switch).font(Theme.font(12))
        }
    }
}

struct Foldout: View {
    let title: String
    @Binding var open: Bool
    var body: some View {
        Button { open.toggle() } label: {
            HStack {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold)).frame(width: 12)
                Text(title).font(Theme.font(13, bold: true))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Map of the Journey (last 7 days)

struct JourneyMap: View {
    let goal: Double
    let today: Double

    var body: some View {
        let hist = Prefs.history
        let cal = Calendar.current
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        VStack(alignment: .leading, spacing: 6) {
            Text("🗺️ Map of the Journey").font(Theme.font(13, bold: true))
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(-6...0, id: \.self) { off in
                    let date = cal.date(byAdding: .day, value: off, to: Date()) ?? Date()
                    let oz = off == 0 ? today : (hist[Prefs.dayString(date)] ?? 0)
                    let h = min(60, 50 * oz / max(goal, 1))
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 60)
                            RoundedRectangle(cornerRadius: 4).fill(oz >= goal ? Theme.gold : Theme.caramel)
                                .frame(height: max(2, h))
                            Rectangle().fill(Theme.gold.opacity(0.5)).frame(height: 1).padding(.bottom, 50)
                        }
                        Text(letters[cal.component(.weekday, from: date) - 1])
                            .font(Theme.font(10, bold: off == 0)).opacity(off == 0 ? 1 : 0.6)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Gold bars: goal reached. The thin line is your goal.").font(Theme.font(9)).italic().opacity(0.6)
        }
    }
}

// MARK: - Bilbo scene (everything is driven by the clock, so nothing leaks into the layout)

struct Wave: Shape {
    var level: Double
    var phase: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.height * (1 - level)
        p.move(to: CGPoint(x: 0, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: top))
        for x in stride(from: 0.0, through: r.width, by: 4) {
            p.addLine(to: CGPoint(x: x, y: top + sin(x / r.width * .pi * 4 + phase) * 4))
        }
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.closeSubpath()
        return p
    }
}

struct BilboScene: View {
    let progress: Double
    let message: String
    let mood: Mood
    let streak: Int
    let hopStart: Date?
    let celebration: Celebration?

    /// "Outfit" unlocked by streak
    var accessory: String? {
        streak >= 30 ? "💍" : streak >= 14 ? "👑" : streak >= 7 ? "🍺" : streak >= 3 ? "🍃" : nil
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let now = tl.date
            let t = now.timeIntervalSinceReferenceDate
            let sway = sin(t * 1.4)
            let hopY: Double = {
                guard let h = hopStart else { return 0 }
                let dt = now.timeIntervalSince(h)
                return (0..<0.5).contains(dt) ? -18 * sin(dt / 0.5 * .pi) : 0
            }()
            ZStack {
                LinearGradient(colors: [Color(red: 0.34, green: 0.22, blue: 0.12), Color(red: 0.17, green: 0.11, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                Wave(level: 0.1 + 0.8 * progress, phase: t * 2)
                    .fill(Color(red: 0.36, green: 0.62, blue: 0.72).opacity(0.4))
                if let c = celebration, c.doom, now.timeIntervalSince(c.start) < 5 {
                    LinearGradient(colors: [.clear, Color.red.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                }
                bilbo(sway: sway, hopY: hopY)
                Text(message)
                    .font(Theme.font(12, bold: true)).foregroundColor(Theme.bg)
                    .padding(9).background(Theme.cream).cornerRadius(12)
                    .frame(maxWidth: 165, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                particles(now: now)
            }
            .frame(height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
        }
        .frame(height: 165)
    }

    func bilbo(sway: Double, hopY: Double) -> some View {
        Group {
            if NSImage(named: "bilbo") != nil {
                Image("bilbo").resizable().scaledToFit().frame(height: 150)
                    .saturation(mood == .worried ? 0.5 : 1)
                    .overlay(alignment: .top) {
                        Text(accessory ?? "").font(.system(size: 20)).offset(y: -10)
                    }
                    .overlay(alignment: .topLeading) {
                        Text(mood == .worried ? "💧" : (mood == .happy ? "✨" : ""))
                            .font(.system(size: 18)).offset(x: 6, y: 18)
                    }
            } else {
                Text("🍄").font(.system(size: 80))
            }
        }
        .scaleEffect(1 + 0.015 * sway, anchor: .bottom)
        .rotationEffect(.degrees(1.5 * sway), anchor: .bottom)
        .offset(y: hopY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 14)
    }

    /// Falling leaves for a goal, rising embers for a Mount Doom milestone.
    @ViewBuilder
    func particles(now: Date) -> some View {
        if let c = celebration, now.timeIntervalSince(c.start) < 5 {
            let dt = now.timeIntervalSince(c.start)
            let icons = c.doom ? ["🔥", "✨", "🌋"] : ["🍃", "🍂", "🍀"]
            GeometryReader { g in
                ForEach(0..<16, id: \.self) { i in
                    let x: Double = Double((i * 37) % 100) / 100 * g.size.width + sin(dt * 2 + Double(i)) * 12
                    let speed: Double = 35 + Double((i * 17) % 40)
                    let y: Double = c.doom ? g.size.height + 10 - dt * speed : -12 + dt * speed
                    Text(icons[i % 3]).font(.system(size: 16))
                        .position(x: x, y: y)
                        .opacity(max(0, 1 - dt / 5))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
