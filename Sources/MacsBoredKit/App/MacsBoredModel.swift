#if canImport(AppKit)
import MacsShared
import AppKit
import Combine
import MacsBoredCore

/// The app's state and everything that changes it. Several times a second it reads what is in front
/// (`ContextReader`), works out the passthrough plan, switches macOS's system shortcuts to match and
/// hands the keyboard tap its new setup. The settings live in `config.json`: every change is saved
/// straight away, and an edit made to the file by hand, a script or an agent is picked up as soon as
/// it's saved. A file with a mistake leaves the last good settings running until it's fixed.
@MainActor
final class MacsBoredModel: ObservableObject {
    @Published private(set) var config: MacsBoredConfig
    /// What's wrong with `config.json` as it is on disk (errors and warnings).
    @Published private(set) var fileIssues: [ConfigFile.Issue]
    @Published private(set) var context = AppContext()
    @Published private(set) var plan = PassthroughPlan.inactive
    /// Paused for this app: passthrough resumes once another app comes to the front.
    @Published private(set) var pausedFor: String?
    @Published private(set) var isAuthorized = Accessibility.isTrusted
    @Published private(set) var tapRunning = false
    @Published private(set) var hyperBlocked = false
    /// While keys are being recorded, the tap lets every key through to the recorder.
    var isRecording = false { didSet { pushSetup() } }

    var onEdit: (EntryDraft) -> Void = { _ in }
    var onPlanChange: (PassthroughPlan, Bool) -> Void = { _, _ in }

    private let store: MacsBoredConfigStore
    private let reader = ContextReader()
    private let hotKeys = SystemHotKeySwitch()
    private let tap = KeyboardTap()
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var observers: [NSObjectProtocol] = []
    /// The minute the clock was on at the last look, for actions set for a time.
    private var lastMinute: Int?

    init(store: MacsBoredConfigStore) {
        self.store = store
        self.config = store.config
        self.fileIssues = store.issues
    }

    var configURL: URL { store.url }
    var fileErrors: [ConfigFile.Issue] { fileIssues.filter { !$0.isWarning } }
    var hotKeySwitchAvailable: Bool { SymbolicHotKeys.isAvailable }
    /// How many system shortcuts are switched off right now (ones already off in System Settings aren't counted).
    var systemShortcutsOff: Int { hotKeys.disabledCount }
    var isPaused: Bool { pausedFor != nil }
    var openAtLogin: Bool { LoginItem.isEnabled }

    // MARK: - Running

    func start() {
        hotKeys.restoreLeftovers()
        tap.onDecision = { [weak self] decision in self?.handle(decision) }
        applyHyper()
        applyLogin()
        startTapIfAllowed()
        watchFile()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { bundleID.map { self?.appOpened($0) } }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    /// Everything back as macOS had it: system shortcuts and Caps Lock.
    func stop() {
        timer?.invalidate()
        watcher?.cancel()
        hotKeys.restoreAll()
        HyperKeyMapping.set(false)
    }

    private func startTapIfAllowed() {
        isAuthorized = Accessibility.isTrusted
        if isAuthorized, !tap.isRunning { tapRunning = tap.start() }
    }

    private func tick() {
        if !tap.isRunning { startTapIfAllowed() }
        let now = reader.read()
        if let paused = pausedFor, now.bundleID != paused { pausedFor = nil }
        if now != context { context = now }
        recompute()
        reachTime(now.minuteOfDay)
    }

    /// Runs the actions set for a time the clock has just reached (or passed while the Mac slept).
    private func reachTime(_ minute: Int) {
        defer { lastMinute = minute }
        guard let last = lastMinute, last != minute, config.isEnabled, !isRecording else { return }
        for trigger in config.runningTriggers where trigger.fires(from: last, to: minute, context: context) {
            run(trigger)
        }
    }

    /// Runs the actions set for this app opening.
    private func appOpened(_ bundleID: String) {
        guard config.isEnabled, !isRecording else { return }
        for trigger in config.runningTriggers where trigger.fires(onOpening: bundleID, context: context) {
            run(trigger)
        }
    }

    private func recompute() {
        let profiles = config.isEnabled ? config.runningProfiles : []
        let next = PassthroughPlanner.plan(profiles: profiles, context: context, paused: isPaused || isRecording)
        hotKeys.move(to: next.disabledHotKeys)
        if next != plan {
            plan = next
            onPlanChange(next, config.isEnabled)
        }
        pushSetup()
    }

    private func pushSetup() {
        // Switched off, MacsBored lets every key through: no triggers, no pause keys, no Hyper.
        let off = isRecording || !config.isEnabled
        tap.setup = KeyRouter.Setup(plan: isRecording ? .inactive : plan,
                                    triggers: off ? [] : config.runningTriggers,
                                    context: context,
                                    pauseKeys: off ? nil : config.pauseKeys,
                                    hyperKeyEnabled: config.isEnabled && config.hyperKeyEnabled && !hyperBlocked)
    }

    private func handle(_ decision: KeyDecision) {
        switch decision {
        case .togglePause:
            togglePause()
        case let .runTrigger(id):
            guard let trigger = config.triggers.first(where: { $0.id == id }) else { return }
            run(trigger)
        default:
            break
        }
    }

    // MARK: - The file

    /// The folder is watched rather than the file: saving replaces the file, which would end a watch on it.
    private func watchFile() {
        let folder = store.url.deletingLastPathComponent()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reloadFromDisk() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Takes in an edit made outside the app.
    func reloadFromDisk() {
        guard store.reload() else { return }
        fileIssues = store.issues
        guard store.config != config else { return }
        config = store.config
        applyHyper()
        applyLogin()
        recompute()
        onPlanChange(plan, config.isEnabled)
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    func openConfigFile() {
        NSWorkspace.shared.open(store.url)
    }

    // MARK: - Switches

    func togglePause() {
        if pausedFor != nil {
            pausedFor = nil
        } else if plan.isActive {
            pausedFor = context.bundleID
        }
        recompute()
        onPlanChange(plan, config.isEnabled)
    }

    /// MacsBored's main switch: off, it lets every key through and macOS keeps all its shortcuts.
    func setEnabled(_ on: Bool) {
        update { $0.isEnabled = on }
        applyHyper()
        pushSetup()
    }

    func setOpenAtLogin(_ on: Bool) {
        update { $0.openAtLogin = on }
        applyLogin()
    }

    private func applyLogin() {
        if let wanted = config.openAtLogin, wanted != LoginItem.isEnabled { LoginItem.setEnabled(wanted) }
    }

    /// Caps Lock as Hyper (`capsLockAsHyper`), applied at once.
    func setHyperKey(_ on: Bool) {
        update { $0.hyperKeyEnabled = on }
        applyHyper()
    }

    private func applyHyper() {
        let outcome = HyperKeyMapping.set(config.isEnabled && config.hyperKeyEnabled)
        hyperBlocked = outcome == .blockedByOtherMapping
    }

    func requestAccess() {
        Accessibility.request { [weak self] in
            MainActor.assumeIsolated { self?.startTapIfAllowed() }
        }
    }

    func completeSetup() {
        update { $0.setupCompleted = true }
    }

    // MARK: - Entries

    /// The editor on a new action, blank unless a trigger is chosen already.
    func newEntry(_ draft: EntryDraft = EntryDraft()) {
        onEdit(draft)
    }

    /// Runs an action's steps, and shows its notification if it asks for one.
    private func run(_ trigger: Trigger) {
        ActionRunner.run(trigger.steps)
        if trigger.notifies { RunNotices.post(trigger) }
    }

    /// Runs an action's steps now, to try it before saving.
    func tryOut(_ steps: [TriggerAction]) {
        ActionRunner.run(steps)
    }

    /// Setup's shortcut: a passthrough entry with the defaults for each app picked, straight away.
    func addProfiles(for apps: [AppRef]) {
        update { config in
            for app in apps where !config.profiles.contains(where: { $0.covers(bundleID: app.bundleID) }) {
                config.profiles.append(PassthroughProfile(name: app.name, apps: [app]))
            }
        }
    }

    func editProfile(_ id: UUID) {
        guard let profile = config.profiles.first(where: { $0.id == id }) else { return }
        onEdit(EntryDraft(profile: profile))
    }

    func editTrigger(_ id: UUID) {
        guard let trigger = config.triggers.first(where: { $0.id == id }) else { return }
        onEdit(Self.draft(for: trigger))
    }

    /// The editor's draft of a trigger, its apps named as Finder names them (the settings file
    /// keeps only their bundle IDs), so the sentence and the chips read "Notes".
    static func draft(for trigger: Trigger) -> EntryDraft {
        var named = trigger
        named.steps = trigger.steps.map { if case let .openApp(app) = $0 { .openApp(AppIcons.named(app)) } else { $0 } }
        named.starts = trigger.starts.map { if case let .appOpens(app) = $0 { .appOpens(AppIcons.named(app)) } else { $0 } }
        named.apps = trigger.apps.map(AppIcons.named)
        var draft = EntryDraft(trigger: named)
        if draft.customName.isEmpty, trigger.name != draft.suggestedName { draft.customName = trigger.name }
        return draft
    }

    /// The trigger another one would take its keys from, for the editor's warning.
    func trigger(using keys: KeyCombo, apps: [AppRef], except id: UUID?) -> Trigger? {
        config.triggers.first { $0.id != id && $0.keys.contains(keys) && $0.apps == apps }
    }

    /// Saves what the editor made. It replaces the entry it was opened on, in its place when it is
    /// still the same kind, so switching a passthrough app to a trigger moves it between the lists.
    /// Keys another trigger had in the same place are taken from it.
    func save(_ result: EntryDraft.Result, replacing origin: EntryDraft.Origin) {
        update { config in
            var triggerSlot: Int?
            var profileSlot: Int?
            switch origin {
            case .new: break
            case let .trigger(id):
                triggerSlot = config.triggers.firstIndex { $0.id == id }
                config.triggers.removeAll { $0.id == id }
            case let .profile(id):
                profileSlot = config.profiles.firstIndex { $0.id == id }
                config.profiles.removeAll { $0.id == id }
            }
            // A pack named in the editor that isn't one yet is made, at the end of the list.
            let packs: [String] = switch result {
            case let .trigger(trigger): trigger.packs
            case let .profile(profile): profile.packs
            }
            for pack in packs where config.pack(named: pack) == nil { config.packs.append(ActionPack(name: pack)) }
            switch result {
            case let .trigger(trigger):
                for index in config.triggers.indices where config.triggers[index].apps == trigger.apps {
                    config.triggers[index].keys.removeAll { trigger.keys.contains($0) }
                }
                config.triggers.insert(trigger, at: min(triggerSlot ?? config.triggers.count, config.triggers.count))
            case let .profile(profile):
                config.profiles.insert(profile, at: min(profileSlot ?? config.profiles.count, config.profiles.count))
            }
        }
    }

    func delete(_ origin: EntryDraft.Origin) {
        switch origin {
        case .new: break
        case let .trigger(id): deleteTrigger(id)
        case let .profile(id): deleteProfile(id)
        }
    }

    func deleteProfile(_ id: UUID) {
        update { $0.profiles.removeAll { $0.id == id } }
    }

    func toggleProfile(_ id: UUID) {
        update { config in
            guard let index = config.profiles.firstIndex(where: { $0.id == id }) else { return }
            config.profiles[index].isEnabled.toggle()
        }
    }

    func deleteTrigger(_ id: UUID) {
        update { $0.triggers.removeAll { $0.id == id } }
    }

    func toggleTrigger(_ id: UUID) {
        update { config in
            guard let index = config.triggers.firstIndex(where: { $0.id == id }) else { return }
            config.triggers[index].isEnabled.toggle()
        }
    }

    // MARK: - Packs

    func togglePack(_ name: String) {
        update { config in
            guard let index = config.packs.firstIndex(where: { $0.name == name }) else { return }
            config.packs[index].isEnabled.toggle()
        }
    }

    /// A new, empty pack at the top of the list, named "New pack" (or "New pack 2", …); its name.
    @discardableResult
    func newPack() -> String {
        var name = "New pack"
        var number = 2
        while config.packs.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "New pack \(number)"
            number += 1
        }
        let made = name
        update { $0.packs.insert(ActionPack(name: made), at: 0) }
        return made
    }

    /// Renames a pack and moves its actions with it; false when the name is empty or another pack's.
    @discardableResult
    func renamePack(_ name: String, to new: String) -> Bool {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty else { return false }
        guard new == name || !config.packs.contains(where: { $0.name.caseInsensitiveCompare(new) == .orderedSame && $0.name != name })
        else { return false }
        update { config in
            guard let index = config.packs.firstIndex(where: { $0.name == name }) else { return }
            config.packs[index].name = new
            for i in config.triggers.indices { config.triggers[i].packs = config.triggers[i].packs.map { $0 == name ? new : $0 } }
            for i in config.profiles.indices { config.profiles[i].packs = config.profiles[i].packs.map { $0 == name ? new : $0 } }
        }
        return true
    }

    func setPackApps(_ name: String, _ apps: [AppRef]) {
        update { config in
            guard let index = config.packs.firstIndex(where: { $0.name == name }) else { return }
            config.packs[index].apps = apps
        }
    }

    /// What a row of the Actions list carries when dragged: the entry, and the pack it's dragged from
    /// ("trigger-<id>", or "trigger-<id>@<pack>" from a pack's card).
    static func dragID(_ entry: MacsBoredConfig.Entry, from pack: String?) -> String {
        let base = switch entry {
        case let .trigger(id): "trigger-\(id)"
        case let .profile(id): "profile-\(id)"
        }
        return pack.map { base + "@" + $0 } ?? base
    }

    /// A row dragged into a pack, or out of one (nil): it leaves the pack it was dragged from, and
    /// keeps any others.
    func move(dragged id: String, toPack pack: String?) {
        let entry: MacsBoredConfig.Entry
        let rest: Substring
        if id.hasPrefix("trigger-"), let uuid = UUID(uuidString: String(id.dropFirst(8).prefix(36))) {
            entry = .trigger(uuid)
            rest = id.dropFirst(8 + 36)
        } else if id.hasPrefix("profile-"), let uuid = UUID(uuidString: String(id.dropFirst(8).prefix(36))) {
            entry = .profile(uuid)
            rest = id.dropFirst(8 + 36)
        } else {
            return
        }
        let from = rest.hasPrefix("@") ? String(rest.dropFirst()) : nil
        update { $0.move(entry, from: from, to: pack) }
    }

    /// Deletes a pack; its actions stay, on their own.
    func deletePack(_ name: String) {
        update { config in
            config.packs.removeAll { $0.name == name }
            for i in config.triggers.indices { config.triggers[i].packs.removeAll { $0 == name } }
            for i in config.profiles.indices { config.profiles[i].packs.removeAll { $0 == name } }
        }
    }

    /// The pack being named in place, just made from + Add.
    @Published private(set) var renamingPack: String?

    /// A new pack at the top of the list, its name typed in place.
    func startNewPack() {
        renamingPack = newPack()
    }

    /// The name typed for the pack just made; nil (or a name taken) keeps the one it was made with.
    func finishNamingPack(_ name: String, to typed: String?) {
        guard renamingPack == name else { return }
        renamingPack = nil
        if let typed { renamePack(name, to: typed) }
    }

    /// Opens a pack's page: its name, switch and apps.
    var onEditPack: (String) -> Void = { _ in }

    func editPack(_ name: String) { onEditPack(name) }

    // MARK: -

    /// A change from the app, made to the settings as they are on disk now. While the file has a
    /// mistake nothing is written over it; the menu says so instead.
    private func update(_ change: (inout MacsBoredConfig) -> Void) {
        reloadFromDisk()
        var next = config
        change(&next)
        guard next != config else { return }
        do {
            try store.save(next)
        } catch {
            fileIssues = store.issues
            NSSound.beep()
            return
        }
        config = store.config
        fileIssues = store.issues
        recompute()
        onPlanChange(plan, config.isEnabled)
    }
}
#endif
