#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's part of mac++'s onboarding: what it does (the notch at work), the drag on sample
/// windows, which layouts the notch offers, and suggested shortcuts tried on sample windows.
/// Accessibility and the menu bar are mac++'s own steps, either side of every tool's lessons.
final class MacsPaneOnboarding: ObservableObject, OnboardingPart {
    enum Step: Int, CaseIterable { case welcome, drag, layouts, shortcuts }

    @Published var step: Step = .welcome
    /// Offscreen-render seed only: the practice notch open with a preset aimed at.
    var previewPicker = false
    let app: MacsPaneModel
    let shortcuts: SetupShortcutsModel

    init(app: MacsPaneModel) {
        self.app = app
        shortcuts = SetupShortcutsModel(app: app)
    }

    let name = "MacsPane"

    var steps: [OnboardingStep] {
        Step.allCases.map { step in
            step.onboardingStep { [unowned self] in AnyView(MacsPaneSetupView(model: self, step: step)) }
        }
    }

    /// The shortcuts lesson listens for its keys only while it shows.
    func didShow(step index: Int?) {
        if let index, let step = Step(rawValue: index) { self.step = step }
        shortcuts.setActive(index == Step.shortcuts.rawValue)
    }

    func finish() { app.completeSetup() }

    /// Closing counts as done: onboarding isn't opened at launch again.
    func close() {
        shortcuts.setActive(false)
        app.completeSetup()
    }
}

/// One of MacsPane's onboarding steps.
struct MacsPaneSetupView: View {
    @ObservedObject var model: MacsPaneOnboarding
    @ObservedObject var app: MacsPaneModel
    let step: MacsPaneOnboarding.Step

    init(model: MacsPaneOnboarding, step: MacsPaneOnboarding.Step) {
        self.model = model
        self.app = model.app
        self.step = step
    }

    var body: some View {
        switch step {
        case .welcome: welcome
        case .drag: drag
        case .layouts: layouts
        case .shortcuts: SetupShortcutsStep(model: model.shortcuts)
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupWelcomeDemo(config: app.config)
            HStack(alignment: .top, spacing: 12) {
                feature("rectangle.split.2x1", "Drag to the notch",
                        "Hold a window on the notch and your layouts open. Let go on a box and the window fills it.")
                feature("square.stack.3d.up", "Presets",
                        "Arrange your windows once, save them as a preset, and put them all back with one click.")
                feature("keyboard", "Shortcuts",
                        "Give a box keys, like \(rightHalfKeys), and send the window you're in there from any app.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The right half's keys as you have them, or as setup suggests them.
    private var rightHalfKeys: String {
        let config = app.config
        return config.shortcutSuggestions.first { $0.name == "Right half" }.map { config.keys(for: $0).displayName } ?? "⌃⌥→"
    }

    private var drag: some View {
        FirstRunSnapDemo(config: app.config, previewPicker: model.previewPicker,
                         dwellIndex: Binding(get: { app.config.dwellChoiceIndex },
                                             set: { app.setDwell(MacsPaneConfig.dwellChoices[$0]) }))
    }

    private var layouts: some View {
        let offered = app.config.windows.dragBarLayoutIDs
        let catalog = app.config.windows.layoutCatalog
        return VStack(alignment: .leading, spacing: 12) {
            LessonIntro(text: "Click a layout to add it to the notch or take it out.") {
                Text(offered.count == 1 ? "1 in the notch" : "\(offered.count) in the notch")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .contentTransition(.numericText())
            }
            SetupLayoutsPreview(config: app.config)
            // A long catalogue scrolls sideways rather than pushing the line under it off.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog) { layoutCard($0, on: offered.contains($0.id)) }
                }
                .padding(1)
            }
            Text(layoutsStatus(catalog.filter { offered.contains($0.id) }.map(\.name)))
                .font(.caption).foregroundStyle(.secondary)
            // Only once there is something to bring back: on a first run every built-in is here.
            if app.config.canRestoreBuiltInLayouts {
                SettingCard(symbol: "arrow.counterclockwise", section: "Layout", title: "Built-in layouts",
                                 detail: "Bring back any you deleted or changed. Your changes stay, as your own.") {
                    Button("Restore") { withAnimation(NotchMotion.panel) { app.restoreBuiltInLayouts() } }
                }
                .transition(.opacity)
            }
        }
    }

    private func layoutsStatus(_ names: [String]) -> String {
        names.isEmpty ? "Nothing is in the notch yet: pick at least one layout."
                      : "The notch offers \(ListFormatter.localizedString(byJoining: names)), in the menu's order."
    }

    /// A layout as a small card you tick: its shape, its name, and whether the notch offers it.
    private func layoutCard(_ layout: WindowLayout, on: Bool) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { app.toggleBar(layout.id) } } label: {
            VStack(spacing: 6) {
                MacsPaneLayoutGlyph(boxes: layout.boxes, size: CGSize(width: 56, height: 35))
                    .opacity(on ? 1 : 0.55)
                Text(layout.name)
                    .font(.caption.weight(on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 8)
            .frame(width: 88)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "In the notch · click to take it out" : "Not in the notch · click to add it")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(symbol: symbol)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The welcome step's picture: the app's own notch at work, on a loop. A cursor drags Safari to the
/// notch, the strip appears, the layouts open, and it lets go on the left box of a layout; then it
/// rests on Notes and the right half's keys send Notes to the right half. Then the windows scatter and
/// it plays again. Runs only while it is on screen.
private struct SetupWelcomeDemo: View {
    @StateObject private var driver: SetupNotchDriver
    @State private var cursor: CGPoint?
    /// The keys being pressed, drawn over the desk.
    @State private var keys: KeyShortcut?
    private let rightHalf: KeyShortcut
    /// The demo's own hold time, so it doesn't drag on a long one.
    private static let dwellMs = 450

    init(config: MacsPaneConfig) {
        _driver = StateObject(wrappedValue: SetupNotchDriver(config: config, dwellMs: Self.dwellMs))
        rightHalf = config.shortcutSuggestions.first { $0.name == "Right half" }.map(config.keys(for:))
            ?? KeyShortcut(keyCode: 124, modifiers: [.control, .option])
    }

    var body: some View {
        SetupWelcomeDesktop(host: driver.host) {
            GeometryReader { geo in
                SetupNotchStage(driver: driver, size: geo.size, interactive: false, cursor: cursor)
                    .task(id: geo.size) { await play(in: geo.size) }
            }
        }
        .overlay(alignment: .bottom) {
            if let keys {
                SetupKeyCaps(shortcut: keys)
                    .padding(.bottom, 18)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A window dragged to the notch opens your layouts, and letting go on a box snaps it there. "
                            + "A shortcut sends another window to a box.")
    }

    @MainActor private func play(in size: CGSize) async {
        let screen = SetupNotchDriver.screen(in: size)
        let lesson = driver.lesson
        cursor = CGPoint(x: size.width * 0.5, y: size.height * 0.8)
        while !Task.isCancelled {
            lesson.scatter()
            await pause(0.8)
            // Safari by the drag, into the left box of a layout.
            if let window = lesson.windows.first(where: { $0.app == WindowsLessonModel.apps[0] }) {
                let rect = driver.frame(of: window, in: screen)
                let titleBar = CGPoint(x: rect.midX, y: rect.minY + 8)
                await glide(to: titleBar, over: 0.6)
                await pause(0.2)
                driver.begin(window, at: titleBar, in: screen)
                await glide(to: CGPoint(x: size.width / 2, y: SetupStage.menuBarHeight / 2), over: 0.8, dragging: true)
                // The strip, then the layouts once the hold is up.
                await pause(Double(Self.dwellMs) / 1000 + 0.7)
                if let target = boxPoint(0) {
                    await glide(to: target, over: 0.6, dragging: true)
                    await pause(0.7)
                }
                driver.end(in: screen)
                await pause(0.9)
            }
            // Notes by its keys, into the right half.
            if let window = lesson.windows.first(where: { $0.app == WindowsLessonModel.apps[2] }) {
                let rect = driver.frame(of: window, in: screen)
                await glide(to: CGPoint(x: rect.midX, y: rect.midY + 20), over: 0.6)
                await pause(0.4)
                withAnimation(.bouncy(duration: 0.25)) { keys = rightHalf }
                await pause(0.35)
                withAnimation(NotchMotion.land) {
                    lesson.place(window.app, at: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
                }
                await pause(1.1)
                withAnimation(.easeOut(duration: 0.2)) { keys = nil }
            }
            await pause(1.8)
        }
    }

    /// The middle of box `index` of the first offered layout with two boxes, as the open notch draws it.
    @MainActor private func boxPoint(_ index: Int) -> CGPoint? {
        let snap = driver.host.windowSnap
        guard let layout = snap.pickerLayouts.first(where: { $0.boxes.count >= 2 }) ?? snap.pickerLayouts.first,
              let inner = snap.layoutFrames[layout.id]?.inner else { return nil }
        let unit = WindowsLessonModel.topLeft(layout.boxes[min(index, layout.boxes.count - 1)])
        return SetupNotchDriver.stage(CGPoint(x: inner.minX + unit.midX * inner.width, y: inner.minY + unit.midY * inner.height))
    }

    /// Move the cursor to `point`, easing in and out, carrying the window when `dragging`.
    @MainActor private func glide(to point: CGPoint, over duration: Double, dragging: Bool = false) async {
        let start = cursor ?? point
        let frames = max(1, Int(duration * 60))
        for frame in 1...frames {
            guard !Task.isCancelled else { return }
            let t = Double(frame) / Double(frames)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let next = CGPoint(x: start.x + (point.x - start.x) * eased, y: start.y + (point.y - start.y) * eased)
            cursor = next
            if dragging { driver.move(to: next) }
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// The desk the welcome demo plays on, its menu bar words hidden while the notch is out over them.
private struct SetupWelcomeDesktop<Content: View>: View {
    @ObservedObject var host: MacsPaneSnapHost
    @ViewBuilder var content: () -> Content

    var body: some View {
        SetupDesktop(height: SetupStage.height, showsMenuItems: host.stage == .rest, notch: content)
    }
}

extension MacsPaneOnboarding.Step {
    func onboardingStep(_ content: @escaping () -> AnyView) -> OnboardingStep {
        switch self {
        case .welcome:
            OnboardingStep(title: "Meet MacsPane", subtitle: "Snap any window into place by dragging it to the notch.",
                           symbol: "rectangle.split.2x1", shortTitle: "What it does", content: content)
        case .drag:
            OnboardingStep(title: "Try the drag", subtitle: "The gesture you'll use on every window, practised on samples.",
                           symbol: "hand.draw", content: content)
        case .layouts:
            OnboardingStep(title: "Choose your layouts",
                           subtitle: "The notch offers these when you hold a window on it.",
                           symbol: "square.grid.2x2", shortTitle: "Layouts", content: content)
        case .shortcuts:
            OnboardingStep(title: "Keys for your windows",
                           subtitle: "Send the window you're in to a box without reaching for the mouse.",
                           symbol: "keyboard", shortTitle: "Window keys", content: content)
        }
    }
}
#endif
