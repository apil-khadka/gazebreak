import Foundation
import Combine

func breakSecondsRemaining(until deadline: TimeInterval, now: TimeInterval) -> Int {
    max(0, Int(ceil(deadline - now)))
}

/// A deadline clock: one wakeup per focus interval while no countdown is visible.
@MainActor
final class GazeBreakModel: ObservableObject {
    @Published var intervalMinutes: Int {
        didSet { defaults.set(intervalMinutes, forKey: "intervalMinutes") }
    }
    @Published var breakSeconds: Int {
        didSet { defaults.set(breakSeconds, forKey: "breakSeconds") }
    }
    @Published private(set) var secondsRemaining: Int
    @Published private(set) var isPaused = false
    @Published private(set) var isOnBreak = false
    @Published var remindersEnabled: Bool {
        didSet {
            defaults.set(remindersEnabled, forKey: "remindersEnabled")
            guard remindersEnabled != oldValue else { return }
            synchronizeCountdown()
            if !remindersEnabled && isOnBreak { finishCurrentBreak() }
            reschedule()
            onTick?()
        }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var breakSoundName: String {
        didSet { defaults.set(breakSoundName, forKey: "breakSoundName") }
    }
    @Published var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: "soundVolume") }
    }

    enum SystemPauseReason: Hashable { case session, display }

    var onTick: (() -> Void)?
    var onReminder: (() -> Void)?
    var onBreakDismissed: (() -> Void)?
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private var timer: Timer?
    private(set) var scheduledDelayForTesting: TimeInterval?
    private var deadline: TimeInterval?
    private var frozenRemaining: TimeInterval
    private var started = false
    private var countdownVisible = false
    private var manuallyPaused = false
    private var systemPauseReasons: Set<SystemPauseReason> = []

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.now = now
        let interval = min(max(defaults.object(forKey: "intervalMinutes") as? Int ?? 20, 1), 240)
        intervalMinutes = interval
        breakSeconds = min(max(defaults.object(forKey: "breakSeconds") as? Int ?? 30, 5), 300)
        remindersEnabled = defaults.object(forKey: "remindersEnabled") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        let sound = defaults.string(forKey: "breakSoundName") ?? BreakSound.pop.rawValue
        breakSoundName = BreakSound(rawValue: sound)?.rawValue ?? BreakSound.pop.rawValue
        soundVolume = min(max(defaults.object(forKey: "soundVolume") as? Double ?? 0.35, 0), 1)
        secondsRemaining = interval * 60
        frozenRemaining = Double(interval * 60)
    }

    deinit { timer?.invalidate() }

    var formattedTime: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    var displayTime: String { remindersEnabled ? formattedTime : "Off" }
    var isSystemPaused: Bool { !systemPauseReasons.isEmpty }

    func start() {
        started = true
        reschedule()
    }

    func setCountdownVisible(_ visible: Bool) {
        guard visible != countdownVisible else { return }
        countdownVisible = visible
        refreshCountdown()
    }

    func togglePaused() {
        guard !isOnBreak else { return }
        synchronizeCountdown()
        manuallyPaused.toggle()
        reschedule()
        onTick?()
    }

    func reset() { finishCurrentBreak() }

    func finishCurrentBreak(after seconds: Int? = nil) {
        let wasOnBreak = isOnBreak
        isOnBreak = false
        manuallyPaused = false
        deadline = nil
        frozenRemaining = Double(seconds ?? intervalMinutes * 60)
        secondsRemaining = Int(frozenRemaining)
        reschedule()
        if wasOnBreak { onBreakDismissed?() }
        onTick?()
    }

    func snooze() { finishCurrentBreak(after: 5 * 60) }

    func beginBreak() {
        guard remindersEnabled, !isOnBreak, !isSystemPaused else { return }
        deadline = nil
        frozenRemaining = 0
        secondsRemaining = 0
        isOnBreak = true
        reschedule()
        onTick?()
        onReminder?()
    }

    func pauseForSystem(_ reason: SystemPauseReason) {
        synchronizeCountdown()
        systemPauseReasons.insert(reason)
        // A real screen/session break cancels an outstanding reminder.
        if isOnBreak { finishCurrentBreak() }
        reschedule()
        onTick?()
    }

    func resumeFromSystem(_ reason: SystemPauseReason) {
        systemPauseReasons.remove(reason)
        reschedule()
        onTick?()
    }

    func updateInterval(_ value: Int) {
        intervalMinutes = min(max(value, 1), 240)
        reset()
    }

    /// Also used by deterministic tests with an injected monotonic clock.
    func refreshCountdown() {
        synchronizeCountdown()
        if started, remindersEnabled, !isPaused, secondsRemaining == 0 {
            beginBreak()
        } else {
            reschedule()
            onTick?()
        }
    }

    private func synchronizeCountdown() {
        guard let deadline else { return }
        frozenRemaining = max(0, deadline - now())
        let remaining = Int(ceil(frozenRemaining))
        if secondsRemaining != remaining { secondsRemaining = remaining }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        scheduledDelayForTesting = nil
        let paused = manuallyPaused || isSystemPaused || isOnBreak
        if isPaused != paused { isPaused = paused }
        guard started, remindersEnabled, !paused else {
            deadline = nil
            return
        }
        if deadline == nil { deadline = now() + frozenRemaining }
        let remaining = max(0.001, (deadline ?? now()) - now())
        let delay = countdownVisible ? min(1, remaining) : remaining
        let nextTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshCountdown() }
        }
        nextTimer.tolerance = countdownVisible ? 0.1 : 0.05
        timer = nextTimer
        scheduledDelayForTesting = delay
        RunLoop.main.add(nextTimer, forMode: .common)
    }
}
