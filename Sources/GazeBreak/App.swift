import AppKit
import SwiftUI

@main
struct GazeBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = GazeBreakModel()
    private var reminderWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var mouseTrackingMonitors: [Any] = []
    private var isStatusItemHovered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if CommandLine.arguments.contains("--self-test") {
            runSelfTest()
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = logoImage()
        statusItem.button?.toolTip = "GazeBreak"
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        installStatusItemHoverTracking()

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 475)
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model))

        model.onTick = { [weak self] in self?.updateStatusItem() }
        model.onReminder = { [weak self] in self?.showReminder() }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.pauseForSystem() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.resumeFromSystem() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.pauseForSystem() }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.resumeFromSystem() }
            }
        ]
        model.start()
        updateStatusItem()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Keep the menu-bar UI from lingering after the user clicks into another app.
        popover?.performClose(nil)
    }

    private func runSelfTest() {
        let defaults = UserDefaults.standard
        let savedInterval = defaults.object(forKey: "intervalMinutes")
        let savedBreak = defaults.object(forKey: "breakSeconds")
        let savedEnabled = defaults.object(forKey: "remindersEnabled")
        var passed = false
        defer {
            restoreDefault(savedInterval, key: "intervalMinutes")
            restoreDefault(savedBreak, key: "breakSeconds")
            restoreDefault(savedEnabled, key: "remindersEnabled")
            if passed { print("GazeBreak self-test passed") }
            NSApp.terminate(nil)
        }

        model.remindersEnabled = true
        model.updateInterval(1)
        model.setCountdownForTesting(2)
        var reminderFired = false
        model.onReminder = { reminderFired = true }

        model.advanceOneSecondForTesting()
        precondition(model.secondsRemaining == 1, "countdown did not advance")
        model.advanceOneSecondForTesting()
        precondition(model.secondsRemaining == 0, "countdown did not reach zero")
        precondition(model.isPaused, "model did not pause at the reminder")
        precondition(reminderFired, "reminder callback did not fire")

        model.finishCurrentBreak()
        precondition(model.secondsRemaining == 60, "break completion did not reset interval")
        precondition(!model.isPaused, "break completion left model paused")
        passed = true
    }

    private func restoreDefault(_ value: Any?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func logoImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "GazeBreakLogo", withExtension: "png")
            ?? Bundle.module.url(forResource: "GazeBreakLogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        mouseTrackingMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(sender) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = isStatusItemHovered ? "  \(model.displayTime)" : ""
        button.imagePosition = isStatusItemHovered ? .imageLeading : .imageOnly
        button.toolTip = "Next break in \(model.displayTime)"
        button.contentTintColor = model.isPaused ? .secondaryLabelColor : .labelColor
    }

    private func installStatusItemHoverTracking() {
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateStatusItemHover()
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateStatusItemHover()
        }
        if let localMonitor { mouseTrackingMonitors.append(localMonitor) }
        if let globalMonitor { mouseTrackingMonitors.append(globalMonitor) }
    }

    private func updateStatusItemHover() {
        guard let button = statusItem?.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let hovered = buttonFrame.contains(NSEvent.mouseLocation)
        guard hovered != isStatusItemHovered else { return }
        isStatusItemHovered = hovered
        updateStatusItem()
    }

    private func showReminder() {
        guard reminderWindow == nil else { return }
        let controller = NSHostingController(rootView: ReminderView(model: model) { [weak self] in
            self?.dismissReminder()
        })
        let window = NSPanel(contentViewController: controller)
        window.styleMask = [.borderless, .nonactivatingPanel]
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 390, height: 285))
        window.center()
        window.makeKeyAndOrderFront(nil)
        reminderWindow = window
    }

    private func dismissReminder() {
        reminderWindow?.orderOut(nil)
        reminderWindow = nil
    }
}

@MainActor
final class GazeBreakModel: ObservableObject {
    @Published var intervalMinutes: Int {
        didSet { UserDefaults.standard.set(intervalMinutes, forKey: Defaults.intervalMinutes) }
    }
    @Published var breakSeconds: Int {
        didSet { UserDefaults.standard.set(breakSeconds, forKey: Defaults.breakSeconds) }
    }
    @Published private(set) var secondsRemaining: Int
    @Published private(set) var isPaused = false
    @Published private(set) var isLongBreak = false
    @Published var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: Defaults.remindersEnabled) }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Defaults.soundEnabled) }
    }
    @Published var breakSoundName: String {
        didSet { UserDefaults.standard.set(breakSoundName, forKey: Defaults.breakSoundName) }
    }
    var onTick: (() -> Void)?
    var onReminder: (() -> Void)?
    private var timer: Timer?
    private var focusSeconds = 0
    private var systemPaused = false
    private let longBreakAfterSeconds = 2 * 60 * 60
    let longBreakSeconds = 15 * 60

    private enum Defaults {
        static let intervalMinutes = "intervalMinutes"
        static let breakSeconds = "breakSeconds"
        static let remindersEnabled = "remindersEnabled"
        static let soundEnabled = "soundEnabled"
        static let breakSoundName = "breakSoundName"
    }

    init() {
        let savedInterval = UserDefaults.standard.object(forKey: Defaults.intervalMinutes) as? Int ?? 20
        intervalMinutes = savedInterval
        breakSeconds = UserDefaults.standard.object(forKey: Defaults.breakSeconds) as? Int ?? 30
        remindersEnabled = UserDefaults.standard.object(forKey: Defaults.remindersEnabled) as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: Defaults.soundEnabled) as? Bool ?? true
        breakSoundName = UserDefaults.standard.string(forKey: Defaults.breakSoundName) ?? BreakSound.pop.rawValue
        secondsRemaining = savedInterval * 60
    }

    deinit { timer?.invalidate() }

    var formattedTime: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var displayTime: String { remindersEnabled ? formattedTime : "Off" }
    var currentBreakSeconds: Int { isLongBreak ? longBreakSeconds : breakSeconds }

    func start() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func togglePaused() { isPaused.toggle(); onTick?() }

    func reset() {
        focusSeconds = 0
        finishCurrentBreak()
    }

    func finishCurrentBreak() {
        isLongBreak = false
        secondsRemaining = intervalMinutes * 60
        isPaused = false
        onTick?()
    }

    // Kept internal so the timer state machine can be tested without waiting 20 minutes.
    func advanceOneSecondForTesting() { tick() }

    func setCountdownForTesting(_ seconds: Int) { secondsRemaining = max(0, seconds) }

    func pauseForSystem() {
        guard !isPaused else { return }
        systemPaused = true
        isPaused = true
        onTick?()
    }

    func resumeFromSystem() {
        guard systemPaused else { return }
        systemPaused = false
        isPaused = false
        onTick?()
    }

    func updateInterval(_ value: Int) {
        intervalMinutes = value
        reset()
    }

    private func tick() {
        guard !isPaused, remindersEnabled else { return }
        focusSeconds += 1
        if secondsRemaining > 1 {
            secondsRemaining -= 1
        } else {
            secondsRemaining = 0
            isLongBreak = focusSeconds >= longBreakAfterSeconds
            isPaused = true
            onReminder?()
        }
        onTick?()
    }
}

private enum BreakSound: String, CaseIterable, Identifiable {
    case pop = "Pop"
    case tink = "Tink"
    case ping = "Ping"
    case glass = "Glass"
    case bottle = "Bottle"

    var id: String { rawValue }
}

struct MenuView: View {
    @ObservedObject var model: GazeBreakModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GazeBreak").font(.system(size: 17, weight: .semibold))
                    Text("A tiny reset for your eyes").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "eye.circle.fill").font(.system(size: 26)).foregroundStyle(.blue)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(!model.remindersEnabled ? "REMINDERS OFF" : (model.isPaused ? "PAUSED" : "NEXT BREAK IN"))
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(model.displayTime)
                    .font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit()
                Text(model.isLongBreak ? "Take a longer 15-minute reset." : "Look at something roughly 6 m / 20 ft away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePaused() }
                    .buttonStyle(.borderedProminent).tint(.blue)
                Button("Reset") { model.reset() }.buttonStyle(.bordered)
                Spacer()
            }.padding(.vertical, 18)

            Divider().padding(.bottom, 14)
            HStack {
                Text("Remind me every"); Spacer()
                Picker("Interval", selection: Binding(get: { model.intervalMinutes }, set: { model.updateInterval($0) })) {
                    Text("20 min").tag(20); Text("30 min").tag(30); Text("45 min").tag(45); Text("60 min").tag(60)
                }.labelsHidden().frame(width: 95)
            }.font(.callout)
            HStack {
                Text("Break length"); Spacer()
                Picker("Break", selection: $model.breakSeconds) {
                    Text("20 sec").tag(20); Text("30 sec").tag(30); Text("45 sec").tag(45); Text("60 sec").tag(60)
                }.labelsHidden().frame(width: 95)
            }.font(.callout).padding(.top, 10)
            Toggle("Enable reminders", isOn: $model.remindersEnabled).toggleStyle(.switch).font(.callout).padding(.top, 18)
            HStack {
                Toggle("Sound at break end", isOn: $model.soundEnabled).toggleStyle(.switch).font(.callout)
                Spacer()
                Button("Test") {
                    playBreakCompletionSound(named: model.breakSoundName, enabled: model.soundEnabled)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Sound").font(.callout)
                Spacer()
                Picker("Sound", selection: $model.breakSoundName) {
                    ForEach(BreakSound.allCases) { sound in
                        Text(sound.rawValue).tag(sound.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 95)
            }
            .padding(.top, 10)
            HStack {
                Spacer()
                Button("Quit GazeBreak") { NSApp.terminate(nil) }
                    .buttonStyle(.link).font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 18)
        }
        .padding(20).frame(width: 320)
    }
}

struct ReminderView: View {
    @ObservedObject var model: GazeBreakModel
    let dismiss: () -> Void
    @State private var remaining: Int = 30

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.fill").font(.system(size: 30)).foregroundStyle(.blue)
            Text(model.isLongBreak ? "Take a longer reset" : "Look away for a moment").font(.title2.bold())
            Text(model.isLongBreak ? "Step away from the screen for a few minutes, then come back refreshed." : "Find something in the distance, let your focus soften, and blink normally.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%02d", remaining)).font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.blue)
            HStack(spacing: 10) {
                Button("Skip") { dismiss(); model.finishCurrentBreak() }.buttonStyle(.bordered)
                Button("I’m back") { dismiss(); model.finishCurrentBreak() }.buttonStyle(.borderedProminent).tint(.blue)
            }
        }
        .padding(28).frame(width: 390, height: 285)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .onAppear { remaining = model.currentBreakSeconds }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if remaining > 0 {
                remaining -= 1
            } else {
                playBreakCompletionSound(named: model.breakSoundName, enabled: model.soundEnabled)
                dismiss()
                model.reset()
            }
        }
    }
}

private func playBreakCompletionSound(named name: String, enabled: Bool) {
    guard enabled else { return }
    if let sound = NSSound(named: NSSound.Name(name)) {
        sound.volume = 0.35
        sound.play()
    } else {
        NSSound.beep()
    }
}
