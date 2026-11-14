#if canImport(AppKit)
import AppKit
import ApplicationServices
import SwiftUI
import MacsShared

/// Whether mac++ has Accessibility (one grant covers both tools), read again once a second while
/// something shows it.
final class AccessWatch: ObservableObject {
    @Published private(set) var granted = AXIsProcessTrusted()
    /// Grant Access was clicked, so System Settings is open at the list.
    @Published var asked = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        granted = AXIsProcessTrusted()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AXIsProcessTrusted()
            if now != self.granted { self.granted = now }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// mac++'s own onboarding steps before the tools' lessons: what mac++ is, and the one permission
/// both tools need.
final class WelcomeOnboarding: OnboardingPart {
    let name = "mac++"
    private let access = AccessWatch()
    private let tools: [MenuTab]
    private let requestAccess: () -> Void

    init(tools: [MenuTab], requestAccess: @escaping () -> Void) {
        self.tools = tools
        self.requestAccess = requestAccess
    }

    var steps: [OnboardingStep] {
        [
            OnboardingStep(title: "Welcome to mac++", subtitle: "Two tools for your Mac, behind one icon in the menu bar.",
                           symbol: "hand.wave", shortTitle: "Welcome") { [tools] in
                AnyView(WelcomeStep(tools: tools.map(\.help)))
            },
            OnboardingStep(title: "Allow Accessibility",
                           subtitle: "The one permission mac++ needs, for both tools.",
                           symbol: "lock.shield", shortTitle: "Accessibility") { [access, requestAccess] in
                AnyView(AccessStep(access: access, request: requestAccess))
            },
        ]
    }

    /// The grant is read once a second only while its step shows.
    func didShow(step: Int?) {
        if step == 1 { access.start() } else { access.stop() }
    }

    func finish() {}
    func close() { access.stop() }
}

/// The last step, after every tool's lessons: where mac++ lives, and Open at login.
final class MenuBarOnboarding: OnboardingPart {
    let name = "Ready"
    private let tabs: [MenuTab]
    private let showMenu: () -> Void
    private let setOpenAtLogin: (Bool) -> Void

    init(tabs: [MenuTab], showMenu: @escaping () -> Void, setOpenAtLogin: @escaping (Bool) -> Void) {
        self.tabs = tabs
        self.showMenu = showMenu
        self.setOpenAtLogin = setOpenAtLogin
    }

    var steps: [OnboardingStep] {
        [
            OnboardingStep(title: "Find it in the menu bar",
                           subtitle: "mac++ has no window of its own: click its apple for everything both tools do.",
                           symbol: "menubar.arrow.up.rectangle", shortTitle: "Menu bar") { [tabs, showMenu, setOpenAtLogin] in
                AnyView(MenuBarStep(tabs: tabs, showMenu: showMenu, setOpenAtLogin: setOpenAtLogin))
            },
        ]
    }

    func didShow(step: Int?) {}
    func finish() {}
    func close() {}
}

// MARK: - Steps

/// What mac++ is: a card for each tool (its mark, name and line, from its help), then how the menu works.
private struct WelcomeStep: View {
    let tools: [HelpContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(tools, id: \.name) { tool(logo: $0.logo(40), name: $0.name, line: $0.tagline) }
            }
            .fixedSize(horizontal: false, vertical: true)
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow("menubar.rectangle", "One icon, one menu",
                               "Click mac++'s apple in the menu bar. Each tool has a page of the menu: switch between them at its top, or with ⌘1 and ⌘2.")
                    FeatureRow("gearshape", "Settings and Quit belong to mac++",
                               "At the foot of the menu: Settings, for the whole app, and Quit, which stops both tools.")
                    FeatureRow("graduationcap", "A lesson for each tool",
                               "Next, try each tool on samples. Nothing changes on your Mac until you choose it.")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tool(logo: AnyView, name: String, line: String) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                logo.frame(width: 40, height: 40)
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(line).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct AccessStep: View {
    @ObservedObject var access: AccessWatch
    let request: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentCard {
                HStack(spacing: 13) {
                    MacPlusPlusLogo(size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility").font(.callout.weight(.semibold))
                        Text("MacsPane moves other apps' windows through it, and MacsBored sees keys before macOS acts on them. mac++ reads nothing else.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 14)
                    if access.granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            access.asked = true
                            request()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                LessonStep(title: "Click Grant Access", detail: "System Settings opens at the Accessibility list.",
                           done: access.asked || access.granted)
                LessonStep(title: "Switch mac++ on",
                           detail: "If it isn't in the list, drag it in from the box under the window.",
                           done: access.granted)
                LessonStep(title: "Come back here",
                           detail: "This step notices as soon as it's on.", done: access.granted)
            }
            Label(access.granted
                    ? "All set: MacsPane can move your windows and MacsBored can see your keys."
                    : "Until it's on, dragging a window to the notch does nothing and macOS keeps every shortcut. You can grant it later from the menu.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct MenuBarStep: View {
    let tabs: [MenuTab]
    let showMenu: () -> Void
    let setOpenAtLogin: (Bool) -> Void
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LessonIntro(text: "Everything mac++ does starts from its apple, up by the clock.") {
                Button("Show me", action: showMenu)
                    .buttonStyle(.borderedProminent)
                    .help("Open the menu under the apple")
            }
            HStack(alignment: .top, spacing: 22) {
                MenuPicture(tabs: tabs)
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow("rectangle.split.2x1", "A page for each tool",
                               "Its main switch, what it is doing now, its settings and lists. Switch at the top, or press ⌘1 and ⌘2.")
                    FeatureRow("gearshape", "Settings", "Accessibility and Open at login, for both tools. The ? beside a name opens its Help.")
                    FeatureRow("power", "Quit mac++", "Stops both tools. MacsBored gives macOS every shortcut back first.")
                }
            }
            Spacer(minLength: 0)
            SettingCard(symbol: "power", title: "Open at login",
                        detail: "So both tools are ready whenever you are.") {
                Toggle("Open mac++ at login", isOn: Binding(get: { openAtLogin }, set: { on in
                    setOpenAtLogin(on)
                    openAtLogin = LoginItem.isEnabled
                }))
                .labelsHidden()
            }
        }
        .padding(.bottom, 16)
    }
}

/// The dropdown hanging from mac++'s apple, its top part, on a strip of menu bar.
private struct MenuPicture: View {
    let tabs: [MenuTab]
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false
    private static let size = CGSize(width: 300, height: 330)
    private static let scale: CGFloat = 0.6
    /// Where the apple sits along the strip, and where the dropdown's nub sits along its top.
    private static let iconX: CGFloat = 226
    private static let nubX: CGFloat = 300
    private static let barHeight: CGFloat = 22

    var body: some View {
        LinearGradient(colors: scheme == .dark
            ? [Color(red: 0.19, green: 0.21, blue: 0.26), Color(red: 0.11, green: 0.12, blue: 0.15)]
            : [Color(red: 0.80, green: 0.85, blue: 0.91), Color(red: 0.70, green: 0.76, blue: 0.84)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: Self.size.width, height: Self.size.height)
            // Overlays take no part in the layout, so the menu keeps its own size and hangs from the top.
            .overlay(alignment: .topLeading) {
                TabbedMenuPicture(tabs: tabs, nubX: Self.nubX)
                    .fixedSize()
                    .scaleEffect(Self.scale, anchor: .topLeading)
                    .offset(x: Self.iconX - Self.nubX * Self.scale, y: Self.barHeight)
            }
            .overlay(alignment: .top) { bar }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("mac++'s apple in the menu bar, with its menu open below it.")
    }

    private var bar: some View {
        ZStack {
            HStack(spacing: 10) {
                Spacer()
                Image(systemName: "wifi")
                Text("9:41")
            }
            .padding(.horizontal, 12)
            MacPlusPlusGlyph().frame(width: 13, height: 13)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.28)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 26, height: 26).scaleEffect(pulse ? 1.5 : 1).opacity(pulse ? 0 : 0.9))
                .position(x: Self.iconX, y: Self.barHeight / 2)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.primary.opacity(0.72))
        .frame(height: Self.barHeight)
        .background(Color.white.opacity(scheme == .dark ? 0.06 : 0.28))
    }
}
#endif
