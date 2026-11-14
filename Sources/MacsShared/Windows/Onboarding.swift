#if canImport(AppKit)
import AppKit
import SwiftUI

/// One step of the onboarding window, as the sidebar and heading show it, and what it draws.
public struct OnboardingStep {
    public let title: String
    public let subtitle: String
    public let symbol: String
    /// The sidebar's label when the title is too long for it.
    public var shortTitle: String?
    public let content: () -> AnyView

    public init(title: String, subtitle: String, symbol: String, shortTitle: String? = nil,
                content: @escaping () -> AnyView) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.shortTitle = shortTitle
        self.content = content
    }
}

/// A run of onboarding steps that belong together: mac++'s own (welcome, Accessibility, the menu bar)
/// or one tool's lessons. The sidebar lists them under `name`.
public protocol OnboardingPart: AnyObject {
    var name: String { get }
    var steps: [OnboardingStep] { get }
    /// Which of this part's steps is showing now, or nil when none is (a lesson can stop listening).
    func didShow(step: Int?)
    /// The last step's button was clicked: keep what was chosen and remember onboarding is done.
    func finish()
    /// The window is going, finished or not: stop listening, and don't open onboarding at launch again.
    func close()
}

/// The onboarding window's state: every part's steps, one after another, and which is showing.
public final class OnboardingModel: ObservableObject {
    public let parts: [OnboardingPart]
    @Published public var current = 0 {
        didSet { if current != oldValue { announce() } }
    }
    /// Closes the window (the last step's button).
    var onDone: () -> Void = {}

    public init(parts: [OnboardingPart], startAt part: Int = 0) {
        self.parts = parts
        current = parts.prefix(part).reduce(0) { $0 + $1.steps.count }
        announce()
    }

    /// Every step, with the part it belongs to and its place in that part.
    var flat: [(part: Int, index: Int, step: OnboardingStep)] {
        parts.enumerated().flatMap { p, part in part.steps.enumerated().map { (p, $0.offset, $0.element) } }
    }

    var isLast: Bool { current == flat.count - 1 }

    public func finish() {
        parts.forEach { $0.finish() }
        onDone()
    }

    func close() {
        parts.forEach { $0.didShow(step: nil) }
        parts.forEach { $0.close() }
    }

    private func announce() {
        let steps = flat
        guard steps.indices.contains(current) else { return }
        let showing = steps[current]
        for (p, part) in parts.enumerated() {
            part.didShow(step: p == showing.part ? showing.index : nil)
        }
    }
}

/// The onboarding window: mac++'s mark over a sidebar of numbered steps grouped by part (ticked once
/// passed), the step's title and one line under it, the step itself, and a footer of Back · progress
/// dots · Continue (the last step's button finishes). The title bar is see-through, so the sidebar runs
/// to the top edge under the traffic lights.
public struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let finishTitle: String

    /// Room for a lesson's stage beside the sidebar without crowding a 14" display.
    public static let size = CGSize(width: 1000, height: 660)
    static let sidebarWidth: CGFloat = 224
    static let gutter: CGFloat = 36
    static let footerHeight: CGFloat = 64

    public init(model: OnboardingModel, finishTitle: String = "Start using mac++") {
        self.model = model
        self.finishTitle = finishTitle
    }

    public var body: some View {
        let steps = model.flat
        let step = steps[min(model.current, steps.count - 1)].step
        HStack(spacing: 0) {
            sidebar(steps)
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarMaterial())
            Divider().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(.system(size: 26, weight: .bold))
                    Text(step.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .padding(.top, 36)
                .padding(.bottom, 18)
                .fixedSize(horizontal: false, vertical: true)
                step.content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(model.current)
                    .transition(.opacity)
                footer(count: steps.count)
            }
            .padding(.horizontal, Self.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        // At least the designed size, and filling a window any taller, so the sidebar and the bottom bar
        // always reach the window's bottom edge.
        .frame(minWidth: Self.size.width, maxWidth: .infinity, minHeight: Self.size.height, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.18), value: model.current)
    }

    // MARK: - Sidebar

    private func sidebar(_ steps: [(part: Int, index: Int, step: OnboardingStep)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MacPlusPlusLogo(size: 40)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("mac++").font(.system(size: 15, weight: .semibold))
                    Text("Onboarding").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { flatIndex, item in
                    if item.index == 0 && model.parts.count > 1 {
                        Text(model.parts[item.part].name)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, flatIndex == 0 ? 0 : 10)
                            .padding(.bottom, 3)
                            .accessibilityAddTraits(.isHeader)
                    }
                    stepRow(flatIndex, item.step)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 8)
            Label {
                Text("You can change all of this later in Settings, and play the lessons again from Help.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "menubar.arrow.up.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    private func stepRow(_ index: Int, _ step: OnboardingStep) -> some View {
        let selected = model.current == index
        let passed = index < model.current
        return Button { model.current = index } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected || passed ? Color.accentColor : Color.primary.opacity(0.07))
                    if passed {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    } else {
                        Text("\(index + 1)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(selected || passed ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                Text(step.shortTitle ?? step.title)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1), \(step.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Footer

    private func footer(count: Int) -> some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index == model.current ? Color.accentColor
                              : Color.primary.opacity(index < model.current ? 0.35 : 0.15))
                        .frame(width: index == model.current ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(model.current + 1) of \(count)")
            HStack(spacing: 12) {
                if model.current > 0 {
                    Button("Back") { model.current -= 1 }
                }
                Spacer()
                if model.isLast {
                    Button(finishTitle) { model.finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { model.current += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.large)
        // One fixed strip under a hairline, the same on every step: a tall step can't push it down.
        .frame(height: Self.footerHeight)
        .overlay(alignment: .top) { Divider().padding(.horizontal, -Self.gutter) }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Opens the onboarding window, one at a time. Closing it, finished or not, counts as done, so it
/// doesn't open at launch again; Settings and each tool's Help bring it back.
public final class OnboardingController {
    private let window = AppWindowController()
    private var model: OnboardingModel?
    /// The window closed, finished or not.
    public var onClose: () -> Void = {}

    public init() {
        window.onClose = { [weak self] in
            self?.model?.close()
            self?.model = nil
            self?.onClose()
        }
    }

    public var isShown: Bool { window.isShown }

    /// Show the onboarding made of `parts`, at the first step of the part at `part`.
    public func show(parts: [OnboardingPart], startAt part: Int = 0) {
        if let model, window.isShown {
            model.current = model.parts.prefix(part).reduce(0) { $0 + $1.steps.count }
            window.front()
            return
        }
        let model = OnboardingModel(parts: parts, startAt: part)
        model.onDone = { [weak self] in self?.window.close() }
        self.model = model
        window.show(title: "mac++ onboarding", size: OnboardingView.size, showsInDock: true) {
            OnboardingView(model: model)
        }
    }

    public func close() { window.close() }
}
#endif
