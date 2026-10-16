import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct FleetAccountMenuProjectionTests {
    @Test
    func `remote account appears only without a local equivalent`() {
        let remote = Self.snapshot(accountKey: "remote", fetchedAt: Date(timeIntervalSince1970: 200))

        let visible = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [remote],
            currentDeviceID: "local-device",
            localAccountKeys: [],
            hasLocalUsage: true)
        let hidden = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [remote],
            currentDeviceID: "local-device",
            localAccountKeys: ["remote"],
            hasLocalUsage: true)

        #expect(visible.additionalAccounts.map(\.accountKey) == ["remote"])
        #expect(hidden.additionalAccounts.isEmpty)
    }

    @Test
    func `local usage wins over an equivalent remote snapshot`() {
        let remote = Self.snapshot(accountKey: "shared", fetchedAt: Date(timeIntervalSince1970: 200))
        let projection = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [remote],
            currentDeviceID: "local-device",
            localAccountKeys: ["shared"],
            hasLocalUsage: true)

        #expect(projection.fallback == nil)
        #expect(projection.additionalAccounts.isEmpty)
    }

    @Test
    func `genuinely distinct remote account remains beside local usage`() {
        let settings = testSettingsStore(suiteName: "FleetAccountMenuProjectionTests-distinct-remote")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let localIdentity = "local-account"
        let localKey = AccountSnapshotSyncPayload.accountKey(for: localIdentity)
        let distinctKey = AccountSnapshotSyncPayload.accountKey(for: "remote-account")
        store.snapshots[.codex] = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "local@example.com",
                accountOrganization: nil,
                loginMethod: nil,
                accountID: localIdentity))
        let localCopy = Self.snapshot(accountKey: localKey, fetchedAt: Date(timeIntervalSince1970: 200))
        let distinct = Self.snapshot(accountKey: distinctKey, fetchedAt: Date(timeIntervalSince1970: 300))
        let localAccountKeys = store.cloudSyncLocalAccountKeys(for: .codex)

        let projection = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [distinct, localCopy],
            currentDeviceID: settings.iCloudSyncDeviceID,
            localAccountKeys: localAccountKeys,
            hasLocalUsage: true)

        #expect(store.cloudSyncAccountSnapshots().map(\.accountKey) == [localKey])
        #expect(localAccountKeys == [localKey])
        #expect(projection.fallback == nil)
        #expect(projection.additionalAccounts.map(\.accountKey) == [distinctKey])
    }

    @Test
    func `fallback selects the freshest remote snapshot`() {
        let old = Self.snapshot(
            accountKey: "old",
            fetchedAt: Date(timeIntervalSince1970: 100),
            deviceID: "remote-one")
        let fresh = Self.snapshot(accountKey: "fresh", fetchedAt: Date(timeIntervalSince1970: 300))
        let sameAccountNewer = Self.snapshot(
            accountKey: "old",
            fetchedAt: Date(timeIntervalSince1970: 250),
            deviceID: "remote-two")
        let projection = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [old, fresh, sameAccountNewer],
            currentDeviceID: "local-device",
            localAccountKeys: [],
            hasLocalUsage: false)

        #expect(projection.fallback?.accountKey == "fresh")
        #expect(projection.additionalAccounts.map(\.accountKey) == ["old"])
        #expect(projection.additionalAccounts.first?.fetchedAt == sameAccountNewer.fetchedAt)
        #expect(projection.additionalAccounts.first?.deviceID == "remote-two")
    }

    @Test
    func `equal freshness remote copies choose a deterministic device`() {
        let fetchedAt = Date(timeIntervalSince1970: 200)
        let first = Self.snapshot(accountKey: "shared", fetchedAt: fetchedAt, deviceID: "remote-a")
        let second = Self.snapshot(accountKey: "shared", fetchedAt: fetchedAt, deviceID: "remote-b")

        let forward = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [first, second],
            currentDeviceID: "local-device",
            localAccountKeys: [],
            hasLocalUsage: false)
        let reversed = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [second, first],
            currentDeviceID: "local-device",
            localAccountKeys: [],
            hasLocalUsage: false)

        #expect(forward.fallback?.deviceID == "remote-b")
        #expect(reversed.fallback?.deviceID == forward.fallback?.deviceID)
        #expect(forward.additionalAccounts.isEmpty)
        #expect(reversed.additionalAccounts.isEmpty)
    }

    @Test
    func `identity less local snapshot owns the legacy default account`() {
        let settings = testSettingsStore(suiteName: "FleetAccountMenuProjectionTests-legacy-default")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.snapshots[.openrouter] = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100))
        let remote = Self.snapshot(
            provider: .openrouter,
            accountKey: AccountSnapshotSyncPayload.accountKey(for: nil),
            fetchedAt: Date(timeIntervalSince1970: 200))

        let projection = FleetAccountMenuPlanner.projection(
            provider: .openrouter,
            snapshots: [remote],
            currentDeviceID: settings.iCloudSyncDeviceID,
            localAccountKeys: store.cloudSyncLocalAccountKeys(for: .openrouter),
            hasLocalUsage: true)

        #expect(store.cloudSyncLocalAccountKeys(for: .openrouter) == ["default"])
        #expect(projection.fallback == nil)
        #expect(projection.additionalAccounts.isEmpty)
    }

    @Test
    func `identity less local snapshot also owns the provider email alias`() {
        let settings = testSettingsStore(suiteName: "FleetAccountMenuProjectionTests-default-email-alias")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.snapshots[.codex] = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100))
        let email = "person@example.com"
        let emailKey = AccountSnapshotSyncPayload.accountKey(for: email)
        store.accountInfoCache[.codex] = UsageStore.AccountInfoCacheEntry(
            account: AccountInfo(email: email, plan: nil),
            configRevision: settings.configRevision,
            expiresAt: .distantFuture)
        let remote = Self.snapshot(accountKey: emailKey, fetchedAt: Date(timeIntervalSince1970: 200))
        let localAccountKeys = store.cloudSyncLocalAccountKeys(for: .codex)

        let projection = FleetAccountMenuPlanner.projection(
            provider: .codex,
            snapshots: [remote],
            currentDeviceID: settings.iCloudSyncDeviceID,
            localAccountKeys: localAccountKeys,
            hasLocalUsage: true)

        #expect(localAccountKeys == [AccountSnapshotSyncPayload.accountKey(for: nil), emailKey])
        #expect(projection.fallback == nil)
        #expect(projection.additionalAccounts.isEmpty)
    }

    @Test
    func `fleet badge uses compact staleness`() {
        let now = Date(timeIntervalSince1970: 10000)

        #expect(FleetAccountMenuPlanner.staleness(fetchedAt: now.addingTimeInterval(-60), now: now) == "1m ago")
        #expect(FleetAccountMenuPlanner.staleness(fetchedAt: now.addingTimeInterval(-3600), now: now) == "1h ago")
        #expect(FleetAccountMenuPlanner.badge(
            deviceName: "Studio",
            fetchedAt: now.addingTimeInterval(-3600),
            now: now) == "via Studio · 1h ago")
    }

    @Test
    func `menu bar uses the same remote fallback as the menu without a local login`() {
        let old = Self.snapshot(provider: .claude, accountKey: "old", fetchedAt: Date(timeIntervalSince1970: 100))
        let fresh = Self.snapshot(provider: .claude, accountKey: "fresh", fetchedAt: Date(timeIntervalSince1970: 200))
        let source = Self.menuBarSource(snapshots: [old, fresh])
        let menu = FleetAccountMenuPlanner.projection(
            provider: .claude,
            snapshots: [old, fresh],
            currentDeviceID: "local-device",
            localAccountKeys: [],
            hasLocalUsage: false)

        #expect(source.isFleet)
        #expect(source.fleetSnapshot?.accountKey == menu.fallback?.accountKey)
        #expect(source.snapshot?.primary?.usedPercent == 25)
        #expect(source.snapshot?.updatedAt == fresh.usage.updatedAt)
    }

    @Test
    func `menu bar keeps local usage authoritative even when remote data is newer`() {
        let remote = Self.snapshot(provider: .claude, accountKey: "remote", fetchedAt: Date(timeIntervalSince1970: 200))
        let local = UsageSnapshot(
            primary: RateWindow(usedPercent: 70, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100))
        let source = Self.menuBarSource(local: local, snapshots: [remote])

        #expect(!source.isFleet)
        #expect(source.fleetSnapshot == nil)
        #expect(source.snapshot?.primary?.usedPercent == 70)
        #expect(source.snapshot?.updatedAt == local.updatedAt)
    }

    @Test
    func `menu bar respects every existing fleet display gate`() {
        let toggles: [(SettingsStore) -> Void] = [
            { $0.iCloudSyncEnabled = false },
            { $0.iCloudSyncSnapshotsEnabled = false },
            { $0.iCloudSyncShowFleetAccounts = false },
        ]
        for (index, disable) in toggles.enumerated() {
            let (settings, _, controller) = Self.makeRemoteController(suffix: "gate-\(index)")
            defer { controller.releaseStatusItemsForTesting() }
            #expect(controller.menuBarUsageSource(for: .codex).isFleet)
            disable(settings)
            #expect(!controller.menuBarUsageSource(for: .codex).isFleet)
            #expect(controller.menuBarUsageSource(for: .codex).snapshot == nil)
        }
        #expect(!MenuBarUsageSource.resolve(
            provider: .claude,
            localSnapshot: nil,
            fleetSnapshots: [Self.snapshot(provider: .claude, accountKey: "remote", fetchedAt: .now)],
            currentDeviceID: "local-device",
            fleetEnabled: false).isFleet)
    }

    @Test
    func `menu bar ignores other providers and this devices persisted snapshots`() {
        let otherProvider = Self.snapshot(accountKey: "other", fetchedAt: Date(timeIntervalSince1970: 300))
        let thisDevice = Self.snapshot(
            provider: .claude,
            accountKey: "own-old-account",
            fetchedAt: Date(timeIntervalSince1970: 400),
            deviceID: "local-device")
        let source = Self.menuBarSource(snapshots: [otherProvider, thisDevice])

        #expect(!source.isFleet)
        #expect(source.snapshot == nil)
    }

    @Test
    func `menu bar drops remote usage after device removal`() {
        let remote = Self.snapshot(provider: .claude, accountKey: "remote", fetchedAt: Date(timeIntervalSince1970: 200))
        #expect(Self.menuBarSource(snapshots: [remote]).isFleet)
        #expect(Self.menuBarSource(snapshots: []).snapshot == nil)
    }

    @Test
    func `menu bar follows changed remote percentages without publishing them as local usage`() {
        let settings = testSettingsStore(suiteName: "FleetAccountMenuProjectionTests-menubar-no-echo")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let remote = Self.snapshot(provider: .claude, accountKey: "remote", fetchedAt: Date(timeIntervalSince1970: 200))
        let changed = AccountSnapshotSyncPayload(
            provider: .claude,
            deviceID: remote.deviceID,
            accountKey: remote.accountKey,
            fetchedAt: Date(timeIntervalSince1970: 300),
            displayLabel: remote.displayLabel,
            usage: UsageSnapshot(
                primary: RateWindow(usedPercent: 80, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 300)))
        let original = Self.menuBarSource(local: store.menuBarSnapshot(for: .claude), snapshots: [remote])
        let refreshed = Self.menuBarSource(local: store.menuBarSnapshot(for: .claude), snapshots: [remote, changed])

        #expect(original.snapshot?.primary?.usedPercent == 25)
        #expect(refreshed.snapshot?.primary?.usedPercent == 80)
        #expect(refreshed.fleetSnapshot?.fetchedAt == changed.fetchedAt)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `remote menu bar layout renders quota without local credits or history`() throws {
        let (_, store, controller) = Self.makeRemoteController(suffix: "remote-render")
        defer { controller.releaseStatusItemsForTesting() }
        store.credits = CreditsSnapshot(remaining: 1234, events: [], updatedAt: Date())

        let snapshot = try #require(controller.menuBarUsageSource(for: .codex).snapshot)
        let data = controller.menuBarLayoutRenderData(provider: .codex, snapshot: snapshot, warningFlash: false)
        #expect(data.primary?.usedPercent == 25)
        #expect(data.costToday == nil)
        #expect(data.cost30d == nil)
        #expect(data.sessionPace == nil)
        #expect(data.weeklyPace == nil)
        #expect(data.runsOut == nil)
        #expect(controller.menuBarLayoutCodexCredits(provider: .codex, snapshot: snapshot) == nil)
        #expect(controller.menuBarCreditsRemainingForIcon(provider: .codex, snapshot: snapshot) == nil)
        store._setErrorForTesting("No local login", provider: .codex)
        #expect(!controller.menuBarIsStale(for: .codex))
        #expect(!controller.shouldAnimate(provider: .codex))
        #expect(controller.menuBarDisplayText(for: .codex, snapshot: snapshot)?.contains("75%") == true)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `status item labels remote usage with its source and hides the device when redacting`() throws {
        let (settings, _, controller) = Self.makeRemoteController(suffix: "remote-tooltip")
        defer { controller.releaseStatusItemsForTesting() }
        controller.cloudSyncState.fleetDevices["device-remote-device"] = DeviceSyncPayload(
            deviceID: "remote-device",
            hostName: "Studio",
            model: "Mac15,14",
            appVersion: "0.76.0",
            lastSeen: Date())

        controller.applyIcon(phase: nil)
        let button = try #require(controller.statusItem.button)
        #expect(button.toolTip?.contains("iCloud") == true)
        #expect(button.toolTip?.contains("Studio") == true)

        settings.hidePersonalInfo = true
        controller.applyIcon(phase: nil)
        #expect(button.toolTip?.contains("Studio") == false)
    }

    @Test
    func `remote updates redraw the status item without requiring a local provider refresh`() async throws {
        let (_, store, controller) = Self.makeRemoteController(suffix: "remote-observation")
        defer { controller.releaseStatusItemsForTesting() }
        controller.applyIcon(phase: nil)
        let previous = controller.lastAppliedMergedIconRenderSignature
        let old = try #require(controller.menuBarUsageSource(for: .codex).fleetSnapshot)
        let updated = AccountSnapshotSyncPayload(
            provider: old.provider,
            deviceID: old.deviceID,
            accountKey: old.accountKey,
            fetchedAt: old.fetchedAt.addingTimeInterval(60),
            displayLabel: old.displayLabel,
            usage: UsageSnapshot(
                primary: RateWindow(usedPercent: 80, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: old.fetchedAt.addingTimeInterval(60)))

        controller.cloudSyncState.fleetSnapshots[updated.recordName] = updated
        for _ in 0..<20 {
            if controller.lastAppliedMergedIconRenderSignature != previous { break }
            await Task.yield()
        }
        #expect(controller.lastAppliedMergedIconRenderSignature != previous)
        #expect(controller.menuBarUsageSource(for: .codex).snapshot?.primary?.usedPercent == 80)
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
    }

    @Test
    func `remote quota renders in a separate status item and local data takes back authority`() throws {
        let (settings, store, controller) = Self.makeRemoteController(suffix: "remote-separate")
        defer { controller.releaseStatusItemsForTesting() }
        settings.mergeIcons = false
        controller.applyIcon(for: .codex, phase: nil)
        let remoteSignature = try #require(controller.lastAppliedProviderIconRenderSignatures[.codex])
        #expect(controller.switcherWeeklyRemaining(for: .codex) ==
            StatusItemController.switcherWeeklyMetricPercent(
                for: .codex, snapshot: controller.menuBarUsageSource(for: .codex).snapshot, showUsed: false))
        #expect(remoteSignature.contains("primary=75.000"))
        #expect(remoteSignature.contains("stale=0"))
        #expect(remoteSignature.contains("loading=0"))
        let local = UsageSnapshot(
            primary: RateWindow(usedPercent: 60, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        store._setSnapshotForTesting(local, provider: .codex)
        controller.applyIcon(for: .codex, phase: nil)
        #expect(!controller.menuBarUsageSource(for: .codex).isFleet)
        #expect(controller.lastAppliedProviderIconRenderSignatures[.codex]?.contains("primary=40.000") == true)
        #expect(controller.statusItems[.codex]?.button?.toolTip == nil)
    }

    @Test
    func `remote Claude quota appears in the custom percent layout without local authentication`() throws {
        let (settings, store, controller) = Self.makeRemoteController(suffix: "claude-layout", provider: .claude)
        defer { controller.releaseStatusItemsForTesting() }
        settings.menuBarIconStyle = .iconAndPercent
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.percent(window: .session)]]), for: nil)
        controller.applyIcon(phase: nil)

        let button = try #require(controller.statusItem.button)
        #expect(controller.menuBarUsageSource(for: .claude).isFleet)
        #expect(button.accessibilityTitle()?.contains("75%") == true)
        #expect(button.toolTip?.contains("iCloud") == true)
        #expect(!controller.shouldAnimate(provider: .claude))
        #expect(store.snapshots.isEmpty)
        #expect(store.cloudSyncAccountSnapshots().isEmpty)
        try Self.writeSyntheticFleetProof(button: button)
    }

    /// Opt-in developer proof of the actual rendered status-item content, not a live CloudKit screenshot.
    private static func writeSyntheticFleetProof(button: NSButton) throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_FLEET_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let canvas = NSImage(size: NSSize(width: 620, height: 160))
        canvas.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 620, height: 160).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black,
        ]
        NSAttributedString(string: "iCloud status item — synthetic fixture", attributes: attributes)
            .draw(at: NSPoint(x: 24, y: 118))
        NSAttributedString(string: button.accessibilityTitle() ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: NSColor.black,
        ]).draw(at: NSPoint(x: 24, y: 64))
        NSAttributedString(string: button.toolTip ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray,
        ]).draw(at: NSPoint(x: 24, y: 24))
        canvas.unlockFocus()
        let tiff = try #require(canvas.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("icloud-menubar-synthetic-proof.png"), options: .atomic)
    }

    private static func makeRemoteController(suffix: String, provider: UsageProvider = .codex)
        -> (SettingsStore, UsageStore, StatusItemController)
    {
        let settings = testSettingsStore(
            suiteName: "FleetAccountMenuProjectionTests-\(suffix)",
            userDefaults: InMemoryUserDefaults())
        settings.iCloudSyncEnabled = true
        settings.iCloudSyncSnapshotsEnabled = true
        settings.iCloudSyncShowFleetAccounts = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.usageBarsShowUsed = false
        settings.menuBarDisplayMode = .percent
        settings.menuBarIconStyle = .critters
        settings.mergeIcons = true
        settings.unifiedIconSource = .currentSelection
        settings.selectedMenuProvider = provider.instanceID
        settings.mergedMenuLastSelectedWasOverview = false
        if let metadata = ProviderRegistry.shared.metadata[provider] {
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let state = CloudSyncState()
        let remote = Self.snapshot(provider: provider.instanceID, accountKey: "remote", fetchedAt: Date())
        state.fleetSnapshots[remote.recordName] = remote
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar(),
            cloudSyncState: state)
        return (settings, store, controller)
    }

    private static func menuBarSource(
        local: UsageSnapshot? = nil,
        snapshots: [AccountSnapshotSyncPayload]) -> MenuBarUsageSource
    {
        MenuBarUsageSource.resolve(
            provider: .claude,
            localSnapshot: local,
            fleetSnapshots: snapshots,
            currentDeviceID: "local-device",
            fleetEnabled: true)
    }

    private static func snapshot(
        provider: ProviderInstanceID = .codex,
        accountKey: String,
        fetchedAt: Date,
        deviceID: String = "remote-device") -> AccountSnapshotSyncPayload
    {
        AccountSnapshotSyncPayload(
            provider: provider,
            deviceID: deviceID,
            accountKey: accountKey,
            fetchedAt: fetchedAt,
            displayLabel: "person@example.com",
            usage: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: fetchedAt))
    }
}
