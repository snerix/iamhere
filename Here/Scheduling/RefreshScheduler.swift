import AppKit
import Foundation

/// Drives `IPService.refresh()` on a periodic loop.
///
/// Drives `IPService.refresh()` on a user-configurable periodic loop:
/// one interval while the display is awake, another while the display
/// is asleep. Network / wake events still fire immediate forced refreshes
/// so proxy, VPN, WiFi, and lid-open transitions do not have to wait for
/// the next scheduled tick.
///
/// Auxiliary inputs:
/// - `NetworkMonitor` (NWPathMonitor): when the link drops we stop
///   firing requests and flip IPState to `.offline`; recovery on
///   `becameReachable` triggers a forced fetch.
/// - `SleepWakeObserver`: pauses the loop on lid-close so we don't
///   accumulate work, kicks a forced refresh on lid-open.
/// - `NSWorkspace` screen-sleep/wake: throttles the loop while
///   the display is off (B1: don't poll fast on a sleeping screen).
@MainActor
final class RefreshScheduler {
    private let ipService: IPService
    private let settings: SettingsStore
    private let networkMonitor: NetworkMonitor
    private let sleepWakeObserver: SleepWakeObserver

    private var loopTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?

    /// `true` while the display is awake. Flipped by the NSWorkspace
    /// screen-sleep / -wake notifications. Read by the polling loop
    /// to decide between active and idle cadence.
    private var displayAwake = true

    init(
        ipService: IPService,
        settings: SettingsStore,
        networkMonitor: NetworkMonitor,
        sleepWakeObserver: SleepWakeObserver
    ) {
        self.ipService = ipService
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.sleepWakeObserver = sleepWakeObserver
    }

    func start() {
        observeScreenPower()
        restartLoop()
        observeNetworkEvents()
        observeWakeEvents()
        observeSettingsChanges()
    }

    func stop() {
        loopTask?.cancel(); loopTask = nil
        networkTask?.cancel(); networkTask = nil
        wakeTask?.cancel(); wakeTask = nil
        settingsTask?.cancel(); settingsTask = nil
        if let obs = screenSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            screenSleepObserver = nil
        }
        if let obs = screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            screenWakeObserver = nil
        }
    }

    /// Manual refresh (e.g. the popover's refresh button). Bypasses
    /// IPService's 5-second `minimumGap` so the user always gets a
    /// fresh fetch when they ask for one — they're explicitly
    /// invoking the action, not riding the loop. Loud (not silent):
    /// the popover's spinner / blur overlay is the user-visible
    /// "we heard you" feedback for the click.
    func triggerNow() {
        Task { [ipService] in await ipService.refresh(force: true) }
    }

    // MARK: - Polling loop

    private var currentInterval: TimeInterval {
        displayAwake ? settings.activeRefreshIntervalSeconds : settings.idleRefreshIntervalSeconds
    }

    private func restartLoop() {
        loopTask?.cancel()
        Log.scheduler.info(
            "Loop restarting (interval \(self.currentInterval, privacy: .public)s, displayAwake \(self.displayAwake, privacy: .public))"
        )
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let sleepFor = self.currentInterval
                do {
                    try await Task.sleep(for: .seconds(sleepFor))
                } catch { break }
                await self.tickIfOnline()
            }
        }
    }

    private func tickIfOnline() async {
        if case .offline = networkMonitor.reachability {
            Log.scheduler.debug("Skipping tick; offline")
            return
        }
        // `silent: true` — the popover would otherwise flicker its
        // spinner-and-blur overlay on every scheduled background tick
        // and the menu-bar widget would reroll its placeholder
        // random flag through every cycle's `.loading` emission.
        // For background polling that's both ugly and useless: the
        // user didn't ask for a check, they shouldn't notice one.
        await ipService.refresh(silent: true)
    }

    // MARK: - Auxiliary observers

    private func observeNetworkEvents() {
        networkTask?.cancel()
        networkTask = Task { [weak self] in
            guard let stream = self?.networkMonitor.events() else { return }
            for await event in stream {
                guard let self else { return }
                switch event {
                case .becameReachable:
                    // Network came back — fire one immediate refresh so
                    // the popover reflects the new plane without waiting
                    // up to one tick. Silent because this is a system-
                    // driven refresh, not user-driven.
                    await ipService.refresh(force: true, silent: true)
                case .becameUnreachable:
                    // Airplane mode, link down, fully offline. Drop
                    // straight into `.error(.offline)` instead of
                    // letting the next URLSession call time out —
                    // saves the user a round-trip's wait for an
                    // answer the kernel already knows.
                    await ipService.forceOffline()
                case .interfaceChanged, .pathChanged:
                    // Normal network mutations (WiFi SSID hop, VPN
                    // up/down, proxy toggle). Fire immediately instead
                    // of waiting for the user's configured loop interval.
                    await ipService.refresh(force: true, silent: true)
                }
            }
        }
    }

    private struct SettingsSnapshot: Equatable {
        let activeValue: Int
        let activeUnit: RefreshIntervalUnit
        let idleValue: Int
        let idleUnit: RefreshIntervalUnit
    }

    private func observeSettingsChanges() {
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            guard let self else { return }
            var last = settingsSnapshot()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                let current = settingsSnapshot()
                if current != last {
                    last = current
                    restartLoop()
                }
            }
        }
    }

    private func settingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            activeValue: settings.activeRefreshIntervalValue,
            activeUnit: settings.activeRefreshIntervalUnit,
            idleValue: settings.idleRefreshIntervalValue,
            idleUnit: settings.idleRefreshIntervalUnit
        )
    }

    private func observeWakeEvents() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            guard let stream = self?.sleepWakeObserver.events() else { return }
            for await event in stream {
                guard let self else { return }
                switch event {
                case .didWake:
                    // Brief settle to let the link/DHCP/DNS come back
                    // before we hit the network. Silent — wake is a
                    // system event, not a user request, so the popover
                    // shouldn't pop a loading overlay on every lid-open.
                    try? await Task.sleep(for: .seconds(1.5))
                    self.restartLoop()
                    await ipService.refresh(force: true, silent: true)
                case .willSleep:
                    loopTask?.cancel()
                }
            }
        }
    }

    /// Listen for display-sleep / display-wake. When the user's
    /// screen turns off (idle timeout, manual lock, lid close on
    /// clamshell), the polling loop switches to the configured idle cadence — there's
    /// no one looking, no point hammering the IP provider and the network
    /// stack at full speed.
    ///
    /// Distinct from `SleepWakeObserver`, which handles full system
    /// sleep (hibernate / suspend). Display sleep is the much more
    /// common case for laptops.
    private func observeScreenPower() {
        let center = NSWorkspace.shared.notificationCenter
        screenSleepObserver = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.displayAwake = false
                Log.scheduler.info("Display slept — switching poll to \(self.currentInterval, privacy: .public)s")
                self.restartLoop()
            }
        }
        screenWakeObserver = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.displayAwake = true
                Log.scheduler.info("Display woke — switching poll to \(self.currentInterval, privacy: .public)s")
                self.restartLoop()
                await self.ipService.refresh(force: true, silent: true)
            }
        }
    }
}
