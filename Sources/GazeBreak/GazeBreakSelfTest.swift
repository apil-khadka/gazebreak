import Foundation
import AppKit

@MainActor
enum GazeBreakSelfTest {
    static func run() {
        setbuf(stdout, nil)
        // Never change the running app's preferences, even if an assertion fails.
        let suite = "GazeBreak.SelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock: TimeInterval = 100
        let model = GazeBreakModel(defaults: defaults, now: { clock })
        var reminders = 0
        var dismissals = 0
        model.onReminder = { reminders += 1 }
        model.onBreakDismissed = { dismissals += 1 }
        model.updateInterval(1)
        model.start()

        precondition(model.scheduledDelayForTesting == 60,
                     "hidden countdown wakes the app every second")
        clock += 25
        model.setCountdownVisible(true)
        precondition(model.secondsRemaining == 35, "opening the menu did not catch up")
        precondition(model.scheduledDelayForTesting == 1, "visible countdown is not live")
        model.setCountdownVisible(false)
        precondition(model.scheduledDelayForTesting == 35, "closing the menu kept second-by-second updates")
        clock += 34
        model.refreshCountdown()
        precondition(model.secondsRemaining == 1, "countdown drifted")
        clock += 1
        model.refreshCountdown()
        precondition(model.secondsRemaining == 0 && model.isOnBreak && model.isPaused,
                     "reminder did not start at the deadline")
        precondition(reminders == 1 && model.scheduledDelayForTesting == nil,
                     "focus timer kept waking during a break")
        model.refreshCountdown()
        precondition(reminders == 1, "reminder fired twice")
        model.togglePaused()
        precondition(model.isPaused, "pause control resumed an active break")
        model.finishCurrentBreak()
        precondition(model.secondsRemaining == 60 && !model.isPaused && dismissals == 1,
                     "break completion did not close and reset")
        print("PASS: hidden/visible scheduling and reminder boundary")

        clock += 10.25
        model.togglePaused()
        precondition(model.secondsRemaining == 50 && model.scheduledDelayForTesting == nil,
                     "pause kept the timer running")
        clock += 100
        model.togglePaused()
        precondition(abs(model.scheduledDelayForTesting! - 49.75) < 0.001,
                     "resume lost the fractional countdown")
        model.pauseForSystem(.session)
        model.pauseForSystem(.display)
        clock += 100
        model.resumeFromSystem(.display)
        precondition(model.isPaused && model.scheduledDelayForTesting == nil,
                     "display wake resumed a locked session")
        model.resumeFromSystem(.session)
        precondition(!model.isPaused && model.secondsRemaining == 50, "system pause lost the countdown")
        model.togglePaused()
        model.pauseForSystem(.display)
        model.resumeFromSystem(.display)
        precondition(model.isPaused, "wake cleared a manual pause")
        model.reset()
        model.pauseForSystem(.session)
        model.reset()
        precondition(model.isPaused && model.scheduledDelayForTesting == nil,
                     "reset resumed a locked session")
        model.resumeFromSystem(.session)
        print("PASS: manual pause, overlapping sleep/lock, reset while locked")

        clock += 12
        model.remindersEnabled = false
        precondition(model.secondsRemaining == 48 && model.scheduledDelayForTesting == nil,
                     "disabled reminders still wake the app")
        clock += 100
        model.remindersEnabled = true
        precondition(model.scheduledDelayForTesting == 48, "disabled time counted as focus")
        model.beginBreak()
        let previousReminders = reminders
        model.beginBreak()
        precondition(reminders == previousReminders, "Break now duplicated the reminder")
        model.snooze()
        precondition(!model.isOnBreak && model.secondsRemaining == 300,
                     "snooze did not defer by five minutes")
        clock += 300
        model.refreshCountdown()
        precondition(model.isOnBreak, "snoozed reminder did not return")
        model.remindersEnabled = false
        precondition(!model.isOnBreak && model.secondsRemaining == 60 && model.scheduledDelayForTesting == nil,
                     "disabling reminders left a stale break window")
        model.remindersEnabled = true
        model.beginBreak()
        model.pauseForSystem(.display)
        precondition(!model.isOnBreak && model.isPaused, "sleep left a stale reminder")
        model.resumeFromSystem(.display)
        model.beginBreak()
        model.updateInterval(20)
        precondition(!model.isOnBreak && model.secondsRemaining == 1200,
                     "changing interval left a stale reminder")
        print("PASS: disabled reminders, Break now, snooze, reminder cancellation")

        for _ in 0..<10 {
            clock += 20 * 60
            model.refreshCountdown()
            precondition(model.isOnBreak && model.breakSeconds == 30,
                         "a long reset replaced the configured short break")
            model.finishCurrentBreak()
        }
        precondition(breakSecondsRemaining(until: 10, now: 9) == 1, "break ended early")
        precondition(breakSecondsRemaining(until: 10, now: 10) == 0, "break ended late")
        precondition(breakSecondsRemaining(until: 10, now: 12) == 0, "delayed break callback drifted")
        print("PASS: short breaks remain short beyond two hours; exact break completion")

        model.soundVolume = 0.65
        model.breakSoundName = BreakSound.glass.rawValue
        model.soundEnabled = false
        model.breakSeconds = 45
        let reloaded = GazeBreakModel(defaults: defaults)
        precondition(abs(reloaded.soundVolume - 0.65) < 0.001 && reloaded.breakSoundName == "Glass"
                     && !reloaded.soundEnabled && reloaded.breakSeconds == 45 && reloaded.intervalMinutes == 20,
                     "preferences did not persist")
        defaults.set(-100, forKey: "intervalMinutes")
        defaults.set(10000, forKey: "breakSeconds")
        defaults.set("Unknown", forKey: "breakSoundName")
        defaults.set(10.0, forKey: "soundVolume")
        let clamped = GazeBreakModel(defaults: defaults)
        precondition(clamped.intervalMinutes == 1 && clamped.breakSeconds == 300
                     && clamped.breakSoundName == "Pop" && clamped.soundVolume == 1,
                     "invalid preferences were not clamped")
        print("PASS: isolated preferences, persistence and bounds")

        // Exercise the real run-loop timer, not only manual refreshes.
        clock += 1200 - 0.01
        model.refreshCountdown()
        let beforeTimer = reminders
        clock += 0.01
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(model.isOnBreak && reminders == beforeTimer + 1,
                     "scheduled timer did not deliver a reminder on the main actor")
        print("PASS: actual scheduled timer callback")
        testPopoverDismissal()
        print("GazeBreak self-test passed")
    }

    private static func testPopoverDismissal() {
        var globalHandler: ((NSEvent) -> Void)?
        var localHandler: ((NSEvent) -> NSEvent?)?
        var removed: [Int] = []
        var closeCalls = 0
        var registrations = 0
        let client = EventMonitorClient(
            addGlobal: { mask, handler in
                precondition(!mask.contains(.mouseMoved) && mask.contains(.rightMouseDown), "global monitor tracks movement or misses clicks")
                registrations += 1
                globalHandler = handler
                return 1
            },
            addLocal: { mask, handler in
                precondition(mask.contains(.keyDown), "Escape is not monitored")
                registrations += 1
                localHandler = handler
                return 2
            },
            remove: { removed.append($0 as! Int) }
        )
        weak var activeMonitor: PopoverDismissalMonitor?
        let monitor = PopoverDismissalMonitor(client: client, target: { event in
            switch event.windowNumber {
            case 42: return .popover
            case 43: return .statusItem
            case 44: return .nativeMenu
            default: return .outside
            }
        }, close: { closeCalls += 1; activeMonitor?.stop() })
        activeMonitor = monitor
        precondition(registrations == 0, "closed menu registers event monitors")
        monitor.start()
        func click(window: Int) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                              windowNumber: window, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        for window in [42, 43, 44] {
            precondition(localHandler?(click(window: window)) != nil, "inside click was swallowed")
        }
        precondition(closeCalls == 0, "menu closed for its own controls, icon or Picker")
        precondition(localHandler?(click(window: 45)) != nil, "outside click was swallowed")
        precondition(closeCalls == 1 && !monitor.isMonitoring && removed.count == 2, "outside click failed to close or remove monitors")
        globalHandler?(click(window: 45))
        precondition(closeCalls == 1, "closed menu handles global events")
        monitor.start()
        globalHandler?(click(window: 45))
        precondition(closeCalls == 2 && !monitor.isMonitoring, "click in another application failed to close")
        monitor.start()
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 42, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        precondition(localHandler?(escape) == nil && closeCalls == 3 && removed.count == 6,
                     "Escape failed to close or remove monitors")
        print("PASS: outside/local/global click dismissal, Escape, control clicks and monitor cleanup")
    }
}
