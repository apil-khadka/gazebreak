import AppKit
import SwiftUI
import Combine

@main
@MainActor
struct GazeBreakMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            GazeBreakSelfTest.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = GazeBreakModel()
    private var reminderWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var statusHoverObserver: StatusHoverObserver?
    private var isStatusItemHovered = false
    private lazy var dismissalMonitor = PopoverDismissalMonitor(
        target: { [weak self] event in self?.popoverEventTarget(event) ?? .outside },
        close: { [weak self] in self?.popover.performClose(nil) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.imagePosition = .imageOnly
        let icon = NSImage(systemSymbolName: "eye", accessibilityDescription: "GazeBreak")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "GazeBreak"
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        installStatusItemHoverTracking()

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        // Create the SwiftUI tree only while the menu is open.

        model.onTick = { [weak self] in self?.updateStatusItem() }
        model.onReminder = { [weak self] in self?.showReminder() }
        model.onBreakDismissed = { [weak self] in self?.dismissReminder() }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.pauseForSystem(.session) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.resumeFromSystem(.session) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.pauseForSystem(.display) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.resumeFromSystem(.display) }
            }
        ]
        model.start()
        updateStatusItem()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Keep the menu-bar UI from lingering after the user clicks into another app.
        popover?.performClose(nil)
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // An accessory app may still be inactive after a status-item click.
            // Activate it so the popover gets keyboard focus and resign events.
            if #available(macOS 14.0, *) { NSApp.activate() }
            else { NSApp.activate(ignoringOtherApps: true) }
            model.setCountdownVisible(true)
            let controller = NSHostingController(rootView: MenuView(model: model))
            popover.contentViewController = controller
            popover.contentSize = controller.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        dismissalMonitor.start()
    }

    func popoverDidClose(_ notification: Notification) {
        dismissalMonitor.stop()
        // Release controls, subscriptions and layout work when hidden.
        popover.contentViewController = nil
        model.setCountdownVisible(isStatusItemHovered)
    }

    private func popoverEventTarget(_ event: NSEvent) -> PopoverDismissalMonitor.Target {
        if event.window == statusItem.button?.window { return .statusItem }
        if event.window?.level == .popUpMenu { return .nativeMenu }
        guard let popoverWindow = popover.contentViewController?.view.window else { return .outside }
        var window = event.window
        while let current = window {
            if current == popoverWindow { return .popover }
            window = current.parent
        }
        return .outside
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = isStatusItemHovered ? "  \(model.displayTime)" : ""
        if button.title != title { button.title = title }
        let position: NSControl.ImagePosition = isStatusItemHovered ? .imageLeading : .imageOnly
        if button.imagePosition != position { button.imagePosition = position }
        button.contentTintColor = model.isPaused || !model.remindersEnabled ? .secondaryLabelColor : .labelColor
        button.toolTip = model.isOnBreak ? "GazeBreak — break in progress" : "GazeBreak — click for timer and controls"
    }

    private func installStatusItemHoverTracking() {
        guard let button = statusItem.button else { return }
        let observer = StatusHoverObserver { [weak self] hovered in
            guard let self, self.isStatusItemHovered != hovered else { return }
            self.isStatusItemHovered = hovered
            self.model.setCountdownVisible(hovered || self.popover.isShown)
            self.updateStatusItem()
        }
        statusHoverObserver = observer
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: observer,
            userInfo: nil
        ))
    }

    private func showReminder() {
        guard reminderWindow == nil else { return }
        let controller = NSHostingController(rootView: ReminderView(model: model))
        let window = NSPanel(contentViewController: controller)
        window.styleMask = [.borderless, .nonactivatingPanel]
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 390, height: 310))
        window.center()
        window.makeKeyAndOrderFront(nil)
        reminderWindow = window
    }

    private func dismissReminder() {
        reminderWindow?.orderOut(nil)
        reminderWindow?.contentViewController = nil
        reminderWindow = nil
    }
}

enum BreakSound: String, CaseIterable, Identifiable {
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
                Image(systemName: "eye.circle.fill").font(.system(size: 26)).foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text(!model.remindersEnabled ? "REMINDERS OFF" : (model.isOnBreak ? "BREAK IN PROGRESS" : (model.isPaused ? "PAUSED" : "NEXT BREAK IN")))
                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(model.displayTime)
                    .font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit()
                Text("Look at something roughly 6 m / 20 ft away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePaused() }
                    .buttonStyle(.borderedProminent).tint(.accentColor)
                    .disabled(!model.remindersEnabled || model.isOnBreak)
                Button("Reset") { model.reset() }.buttonStyle(.bordered)
                Spacer()
                Button("Break now") { model.beginBreak() }
                    .buttonStyle(.bordered)
                    .disabled(!model.remindersEnabled || model.isOnBreak || model.isSystemPaused)
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
                    playBreakCompletionSound(named: model.breakSoundName, enabled: model.soundEnabled, volume: model.soundVolume)
                }
                .buttonStyle(.bordered)
                .disabled(!model.soundEnabled)
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
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: $model.soundVolume, in: 0...1, step: 0.05)
                    .accessibilityLabel("Sound volume")
                Text("\(Int(model.soundVolume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.top, 8)
            .disabled(!model.soundEnabled)
            HStack {
                Spacer()
                Button("Quit GazeBreak") { NSApp.terminate(nil) }
                    .buttonStyle(.link).font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 18)
        }
        .padding(20).frame(width: 340)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.accentColor)
    }
}

@MainActor
private final class StatusHoverObserver: NSResponder {
    let onHover: (Bool) -> Void

    init(onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

struct ReminderView: View {
    @ObservedObject var model: GazeBreakModel
    @State private var remaining: Int = 0
    @State private var deadline: TimeInterval = 0
    private let timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.fill").font(.system(size: 30)).foregroundStyle(Color.accentColor)
            Text("Look away for a moment").font(.title2.bold())
            Text("Find something in the distance, let your focus soften, and blink normally.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%02d", remaining))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(Color.accentColor)
                .accessibilityLabel("\(remaining) seconds remaining")
            HStack(spacing: 10) {
                Button("Skip") { model.finishCurrentBreak() }.buttonStyle(.bordered)
                Button("Snooze 5 min") { model.snooze() }.buttonStyle(.bordered)
                Button("I’m back") { model.finishCurrentBreak() }
                    .buttonStyle(.borderedProminent).tint(.accentColor)
            }
        }
        .padding(28).frame(width: 390, height: 310)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
        .tint(.accentColor)
        .onAppear {
            remaining = model.breakSeconds
            deadline = ProcessInfo.processInfo.systemUptime + Double(remaining)
        }
        .onReceive(timer) { _ in
            guard model.isOnBreak else { return }
            // Elapsed time keeps the break accurate even when callbacks are delayed.
            remaining = breakSecondsRemaining(until: deadline, now: ProcessInfo.processInfo.systemUptime)
            if remaining == 0 {
                playBreakCompletionSound(named: model.breakSoundName, enabled: model.soundEnabled, volume: model.soundVolume)
                model.finishCurrentBreak()
            }
        }
    }
}

private func playBreakCompletionSound(named name: String, enabled: Bool, volume: Double) {
    guard enabled else { return }
    let sound = NSSound(named: NSSound.Name(name))
        ?? NSSound(named: NSSound.Name(BreakSound.pop.rawValue))
    if let sound {
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }
}
