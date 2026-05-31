import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var store: UsageStore!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = UsageStore()
        store.onUpdate = { [weak self] in self?.rebuildMenu() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: "gauge.medium",
                                   accessibilityDescription: "AI usage")?
                .withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        statusItem.menu = menu
        rebuildMenu()
        Task { await refreshFromTimer() }
    }

    private func scheduleNextTimer() {
        timer?.invalidate()
        let next = Timer(timeInterval: store.secondsUntilNextRefresh, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshFromTimer() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func refreshFromTimer() async {
        await store.tick(force: false)
        scheduleNextTimer()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        for p in store.providers {
            let item = NSMenuItem()
            item.view = ProviderRowView(usage: p)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if let updated = store.lastUpdated {
            let stamp = NSMenuItem(title: "Updated \(timeFormatter.string(from: updated))", action: nil, keyEquivalent: "")
            stamp.isEnabled = false
            menu.addItem(stamp)
        }

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let setToken = NSMenuItem(title: "Set Cursor Token…", action: #selector(setCursorToken), keyEquivalent: "")
        setToken.target = self
        menu.addItem(setToken)

        let launch = NSMenuItem(title: "Launch at Login: \(LaunchAtLogin.isEnabled ? "On" : "Off")",
                                action: #selector(toggleLaunchAtLogin),
                                keyEquivalent: "")
        launch.target = self
        menu.addItem(launch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func refreshNow() {
        Task {
            await store.tick(force: true)
            scheduleNextTimer()
        }
    }

    @objc private func setCursorToken() {
        let initial = Keychain.cachedGenericPassword(service: Keychain.cursorService, account: Keychain.cursorAccount) ?? ""

        guard let value = CursorTokenPrompt.present(initial: initial) else { return }

        if value.isEmpty {
            Keychain.deleteGenericPassword(service: Keychain.cursorService, account: Keychain.cursorAccount)
        } else {
            Keychain.setGenericPassword(value, service: Keychain.cursorService, account: Keychain.cursorAccount)
        }
        Task {
            await store.tick(force: true)
            scheduleNextTimer()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        _ = LaunchAtLogin.toggle()
        rebuildMenu()
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()
