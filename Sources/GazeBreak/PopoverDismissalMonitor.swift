import AppKit

struct EventMonitorClient {
    var addGlobal: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    var addLocal: (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
    var remove: (Any) -> Void

    static let live = EventMonitorClient(
        addGlobal: { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
        addLocal: { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
        remove: { NSEvent.removeMonitor($0) }
    )
}

/// Monitors clicks only while the menu is open; never monitors mouse movement.
@MainActor
final class PopoverDismissalMonitor {
    enum Target { case popover, statusItem, nativeMenu, outside }

    private let client: EventMonitorClient
    private let target: (NSEvent) -> Target
    private let close: () -> Void
    private var monitors: [Any] = []
    private(set) var isMonitoring = false

    init(client: EventMonitorClient = .live,
         target: @escaping (NSEvent) -> Target,
         close: @escaping () -> Void) {
        self.client = client
        self.target = target
        self.close = close
    }

    func start() {
        stop()
        isMonitoring = true
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = client.addGlobal(clicks, { [weak self] _ in
            guard let self, self.isMonitoring else { return }
            self.close()
        }) { monitors.append(global) }
        if let local = client.addLocal(clicks.union(.keyDown), { [weak self] event in
            guard let self, self.isMonitoring else { return event }
            let target = self.target(event)
            // Let a Picker's native menu handle its own Escape and selection.
            if target == .nativeMenu { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.close()
                return nil
            }
            if target == .outside { self.close() }
            // Always forward the click; status-item clicks use the normal toggle.
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        isMonitoring = false
        monitors.forEach(client.remove)
        monitors.removeAll()
    }

    deinit { monitors.forEach(client.remove) }
}
