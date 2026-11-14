#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsBoredCore

/// MacsBored's part of mac++'s onboarding: what it does, then two hands-on lessons (a sample remote
/// session to try passthrough on, and sample triggers), then which installed remote-desktop apps get
/// macOS's shortcuts. Accessibility and the menu bar are mac++'s own steps, either side of every
/// tool's lessons.
final class MacsBoredOnboarding: ObservableObject, OnboardingPart {
    enum Step: Int, CaseIterable {
        case welcome, passthrough, trigger, apps

        var sidebar: String {
            switch self {
            case .welcome: "What it does"
            case .passthrough: "Try passthrough"
            case .trigger: "Try a trigger"
            case .apps: "Choose your apps"
            }
        }

        var title: String {
            switch self {
            case .welcome: "Meet MacsBored"
            case .passthrough: "Try passthrough"
            case .trigger: "Try a trigger"
            case .apps: "Choose your apps"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: "Your Mac's shortcuts, sent to the computer you're remoting into."
            case .passthrough: "What happens to ⌘⇥ and friends in a remote session, practised on a sample one."
            case .trigger: "A key of your own that does one job, wherever you are."
            case .apps: "The apps that get macOS's shortcuts. Change them any time from the menu bar."
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "command"
            case .passthrough: "arrow.right.to.line"
            case .trigger: "keyboard"
            case .apps: "square.grid.2x2"
            }
        }
    }

    let model: MacsBoredModel
    /// The remote-desktop apps ticked on the last step; every installed one to start with.
    @Published var picked: Set<String>

    init(model: MacsBoredModel) {
        self.model = model
        picked = Set(Self.installed.map(\.bundleID))
    }

    static var installed: [AppRef] {
        KnownPassthroughApps.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    let name = "MacsBored"

    var steps: [OnboardingStep] {
        Step.allCases.map { step in
            OnboardingStep(title: step.title, subtitle: step.subtitle, symbol: step.symbol, shortTitle: step.sidebar) {
                [unowned self] in AnyView(MacsBoredSetupView(part: self, model: self.model, step: step))
            }
        }
    }

    func didShow(step: Int?) {}

    /// The ticked apps become passthrough apps.
    func finish() {
        MainActor.assumeIsolated {
            model.addProfiles(for: Self.installed.filter { picked.contains($0.bundleID) })
            model.completeSetup()
        }
    }

    /// Closing counts as done: onboarding isn't opened at launch again.
    func close() {
        MainActor.assumeIsolated { model.completeSetup() }
    }
}

/// One of MacsBored's onboarding steps.
struct MacsBoredSetupView: View {
    @ObservedObject var part: MacsBoredOnboarding
    @ObservedObject var model: MacsBoredModel
    let step: MacsBoredOnboarding.Step

    private var installed: [AppRef] { MacsBoredOnboarding.installed }

    var body: some View {
        switch step {
        case .welcome: welcome
        case .passthrough: PassthroughLesson()
        case .trigger: TriggerLesson()
        case .apps: apps
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentCard {
                VStack(alignment: .leading, spacing: 16) {
                    explainer("arrow.right.to.line", "Pass shortcuts to a remote session",
                              "In Windows App, Citrix or a virtual machine, ⌘⇥, Spotlight and the rest go to the other computer, not your Mac.")
                    explainer("keyboard", "Give a key a job with a trigger",
                              "Remap keys, open an app, a link or a file, run a Shortcut, or pass just some keys to the app in front.")
                    explainer("menubar.rectangle", "Everything else is in the menu bar",
                              "Pausing, your passthrough apps and triggers are on MacsBored's page under the mac++ icon.")
                    explainer("doc.text", "Or set it all up from a file",
                              "Every setting is in one JSON file that MacsBored reloads the moment it changes, so you, a script or an AI agent can edit it.")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(part.picked.count == 1 ? "1 app gets the shortcuts" : "\(part.picked.count) apps get the shortcuts")
                .font(.callout).foregroundStyle(.secondary)
            if installed.isEmpty {
                Text("No remote-desktop app is installed yet. Add one later with the + beside Passthrough in the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(installed) { app in appCard(app, on: part.picked.contains(app.bundleID)) }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }

    private func appCard(_ app: AppRef, on: Bool) -> some View {
        Button {
            if on { part.picked.remove(app.bundleID) } else { part.picked.insert(app.bundleID) }
        } label: {
            VStack(spacing: 10) {
                if let icon = AppIcons.icon(bundleID: app.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                }
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                    Text(app.name).lineLimit(1)
                }
                .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func explainer(_ symbol: String, _ title: String, _ detail: String) -> some View {
        FeatureRow(symbol, title, detail)
    }
}

// MARK: - The lessons' shared pieces

/// The top of a Mac screen: wallpaper and a menu bar naming the app in front.
private struct LessonDesktop<Content: View>: View {
    let frontApp: String
    var iconDimmed = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.19, green: 0.21, blue: 0.26), Color(red: 0.11, green: 0.12, blue: 0.15)]
                : [Color(red: 0.80, green: 0.85, blue: 0.91), Color(red: 0.70, green: 0.76, blue: 0.84)],
                startPoint: .top, endPoint: .bottom)
            content
            HStack(spacing: 12) {
                Text(frontApp).fontWeight(.semibold)
                Spacer()
                Image(systemName: "command").opacity(iconDimmed ? 0.35 : 1)
                Image(systemName: "wifi")
                Text("9:41")
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Color.white.opacity(scheme == .dark ? 0.06 : 0.28))
            .allowsHitTesting(false)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// A sample window: a title bar with traffic lights, lit while it's in front, over its content.
private struct SampleWindow<Content: View>: View {
    let title: String
    let front: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { color in
                    Circle().fill(front ? color : Color.gray.opacity(0.35)).frame(width: 9, height: 9)
                }
                Spacer()
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 39, height: 1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor))
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(front ? 0.25 : 0.12), radius: front ? 12 : 5, y: 4)
    }
}

/// Catches the lesson's keys while the setup window is in front. Keys macOS keeps for itself
/// (⌘⇥, ⌘Space) never arrive here, so each lesson also has buttons for them.
private struct KeyCatcher: ViewModifier {
    let handle: (KeyCombo) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let keys = KeyCombo(keyCode: event.keyCode, modifiers: FlagBits.modifiers(UInt64(event.modifierFlags.rawValue)))
                    return handle(keys) ? nil : event
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

// MARK: - Try passthrough

/// A sample remote session: in it, ⌘⇥ and ⌘Space reach Windows; ⌃⌥⌘P pauses so macOS has them back;
/// clicking the desktop beside it puts Finder in front, where every shortcut is the Mac's.
private struct PassthroughLesson: View {
    enum Shown { case winSwitcher, winSearch, macSwitcher, spotlight }
    enum Event { case paused, resumed, pauseOnMac, left }

    @State private var remoteInFront = true
    @State private var paused = false
    @State private var shown: Shown?
    @State private var event: Event?
    @State private var sent = false
    @State private var triedPaused = false
    @State private var left = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LessonIntro(text: "Press a key in the sample session. Nothing on your Mac happens.") {
                Button("⌘⇥") { press(.tab) }
                Button("⌘Space") { press(.space) }
                Button("⌃⌥⌘P") { press(.pause) }
                Button("Start over") { reset() }.padding(.leading, 6)
            }
            LessonDesktop(frontApp: remoteInFront ? "Windows App" : "Finder", iconDimmed: paused && remoteInFront) {
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { remoteInFront = false; paused = false; shown = nil; event = .left; left = true }
                    SampleWindow(title: "Work PC · Windows App", front: remoteInFront) {
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [Color(red: 0.16, green: 0.44, blue: 0.79), Color(red: 0.04, green: 0.24, blue: 0.48)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            HStack(spacing: 6) {
                                ForEach(0..<4) { index in
                                    RoundedRectangle(cornerRadius: 2).fill([Color.cyan, .green, .yellow, .blue][index].opacity(0.85))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: 22).background(Color.black.opacity(0.7))
                            if shown == .winSwitcher { windowsSwitcher.frame(maxHeight: .infinity) }
                            if shown == .winSearch { windowsSearch.padding(.bottom, 28) }
                        }
                    }
                    .frame(width: 460, height: 220)
                    .offset(y: 16)
                    .onTapGesture { remoteInFront = true; shown = nil; if event == .left { event = nil } }
                    if shown == .macSwitcher { macSwitcher }
                    if shown == .spotlight { spotlight.frame(maxHeight: .infinity, alignment: .top).padding(.top, 70) }
                    if paused && remoteInFront {
                        Label("Passthrough paused", systemImage: "pause.fill")
                            .font(.caption)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 30).padding(.trailing, 10)
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                LessonStep(title: "Press ⌘⇥ in the session", detail: "It reaches Windows as Alt+Tab, not your Mac's app switcher.", done: sent)
                LessonStep(title: "Pause with ⌃⌥⌘P, then press ⌘⇥", detail: "macOS gets its shortcuts back until you switch apps.", done: triedPaused)
                LessonStep(title: "Click the desktop beside it", detail: "Back on your Mac, every shortcut works as usual.", done: left)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.2), value: shown)
        .animation(.snappy(duration: 0.2), value: remoteInFront)
        .modifier(KeyCatcher { keys in
            if keys == MacsBoredConfig.defaultPauseKeys { press(.pause); return true }
            return false
        })
    }

    private enum Key { case tab, space, pause }

    private func press(_ key: Key) {
        if key == .pause {
            guard remoteInFront else { shown = nil; event = .pauseOnMac; return }
            paused.toggle()
            shown = nil
            event = paused ? .paused : .resumed
            return
        }
        let toSession = remoteInFront && !paused
        shown = toSession ? (key == .tab ? .winSwitcher : .winSearch) : (key == .tab ? .macSwitcher : .spotlight)
        event = nil
        if toSession { sent = true }
        if remoteInFront && paused { triedPaused = true }
    }

    private func reset() {
        remoteInFront = true; paused = false; shown = nil; event = nil; sent = false; triedPaused = false; left = false
    }

    private var status: String {
        switch (shown, event) {
        case (.winSwitcher?, _): return "Windows got ⌘⇥ as Alt+Tab. Your Mac's app switcher stayed shut."
        case (.winSearch?, _): return "⌘Space opened Windows search, not Spotlight."
        case (.macSwitcher?, _): return remoteInFront ? "Paused, so ⌘⇥ opened your Mac's app switcher. Press ⌃⌥⌘P again to resume."
                                                     : "On your Mac, ⌘⇥ opens the Mac's app switcher as usual."
        case (.spotlight?, _): return remoteInFront ? "Paused, so ⌘Space opened Spotlight on your Mac." : "On your Mac, ⌘Space opens Spotlight as usual."
        case (nil, .paused?): return "Paused. macOS has its shortcuts back until you switch apps. Press ⌘⇥ to see."
        case (nil, .resumed?): return "Resumed. Shortcuts go to the session again."
        case (nil, .pauseOnMac?): return "⌃⌥⌘P only does something while a passthrough app is in front."
        case (nil, .left?): return "Finder is in front, so every shortcut is your Mac's again. Click the session to go back."
        case (nil, nil): return remoteInFront ? "The sample session is in front, so its shortcuts go to Windows. Press ⌘⇥ to try."
                                              : "Finder is in front. Click the session to go back."
        }
    }

    private var windowsSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(["Excel", "Edge", "File Explorer"], id: \.self) { name in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(name == "Excel" ? 0.95 : 0.8))
                        .frame(width: 64, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white, lineWidth: name == "Excel" ? 2 : 0).padding(-3))
                    Text(name).font(.system(size: 10)).foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
    }

    private var windowsSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type here to search").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            Text("Windows search").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(8)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
    }

    private var macSwitcher: some View {
        HStack(spacing: 12) {
            ForEach(["com.apple.finder", "com.microsoft.rdc.macos", "com.apple.Notes"], id: \.self) { id in
                Group {
                    if let icon = AppIcons.icon(bundleID: id) { Image(nsImage: icon).resizable() } else { RoundedRectangle(cornerRadius: 10).fill(.gray) }
                }
                .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var spotlight: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Spotlight Search")
            Spacer()
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(width: 340, height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

// MARK: - Try a trigger

/// Three sample triggers: one opens Notes, one runs a Shortcut, one presses other keys.
private struct TriggerLesson: View {
    enum Sample: CaseIterable { case notes, focus, emoji }
    @State private var shown: Sample?
    @State private var done: Set<Sample> = []

    private static let keys: [Sample: KeyCombo] = [
        .notes: KeyCombo(text: "ctrl+opt+N")!, .focus: KeyCombo(text: "ctrl+opt+F")!, .emoji: KeyCombo(text: "ctrl+opt+E")!,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LessonIntro(text: "Press a sample trigger, here or on your keyboard.") {
                Button("⌃⌥N") { fire(.notes) }
                Button("⌃⌥F") { fire(.focus) }
                Button("⌃⌥E") { fire(.emoji) }
                Button("Start over") { shown = nil; done = [] }.padding(.leading, 6)
            }
            LessonDesktop(frontApp: shown == .notes ? "Notes" : "Finder") {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    SampleWindow(title: "Documents", front: shown != .notes) {
                        HStack(spacing: 0) {
                            Color.primary.opacity(0.05).frame(width: 80)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 10), count: 4), spacing: 10) {
                                ForEach(0..<4) { index in
                                    RoundedRectangle(cornerRadius: 4).fill(index < 2 ? Color.blue.opacity(0.35) : Color.gray.opacity(0.2))
                                        .frame(height: 30)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                    .frame(width: 300, height: 190)
                    .offset(x: 40, y: 48)
                    if shown == .notes {
                        SampleWindow(title: "Notes", front: true) {
                            HStack(spacing: 0) {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.yellow.opacity(0.6)).frame(height: 22)
                                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)).frame(height: 22)
                                    Spacer()
                                }
                                .padding(8).frame(width: 110)
                                Text("Standup").font(.caption).padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .background(Color(nsColor: .textBackgroundColor))
                            }
                        }
                        .frame(width: 320, height: 190)
                        .offset(x: 300, y: 64)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if shown == .focus {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [.pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Focus timer").font(.caption.weight(.semibold))
                                Text("Started · 25 minutes, Do Not Disturb on").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(width: 260, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 32).padding(.trailing, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if shown == .emoji {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Search").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
                                ForEach(Array("😀😂😊😍👍🙏🎉🔥✅👀💡☕️🚀🙌😅❤️").map(String.init), id: \.self) { Text($0).font(.system(size: 16)) }
                            }
                        }
                        .padding(8)
                        .frame(width: 220)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .offset(x: 150, y: 120)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                LessonStep(title: "⌃⌥N opens an app", detail: "Notes opens, or comes to the front if it's already open.", done: done.contains(.notes))
                LessonStep(title: "⌃⌥F runs a Shortcut", detail: "Anything Apple's Shortcuts app can do, from one key.", done: done.contains(.focus))
                LessonStep(title: "⌃⌥E remaps keys", detail: "It presses ⌃⌘Space for you, which opens the emoji picker.", done: done.contains(.emoji))
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: shown)
        .modifier(KeyCatcher { keys in
            guard let sample = Self.keys.first(where: { $0.value == keys })?.key else { return false }
            fire(sample)
            return true
        })
    }

    private func fire(_ sample: Sample) {
        shown = sample
        done.insert(sample)
    }

    private var status: String {
        if done.count == Sample.allCases.count { return "That's triggers. Make your own with New in the menu bar." }
        switch shown {
        case .notes?: return "Notes opened. If it was already open, the trigger brings it to the front."
        case .focus?: return "Your “Focus timer” Shortcut ran, from one key."
        case .emoji?: return "The trigger pressed ⌃⌘Space for you, so the emoji picker opened."
        case nil: return "Finder is in front. A trigger works in any app except a passthrough one."
        }
    }
}
#endif
