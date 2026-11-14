#if canImport(AppKit)
import AppKit
import SwiftUI

// The pieces every surface of mac++ is built from (the dropdown, onboarding, Settings, Help and each
// tool's own windows), so a card, a tile or a lesson step looks the same wherever it appears.

/// mac++'s corner and fill for a card, in one place.
public enum CardStyle {
    public static let corner: CGFloat = 12
    public static let fill = Color.primary.opacity(0.035)
    public static let stroke = Color.primary.opacity(0.08)
}

/// An SF Symbol in a tint, on a rounded square of the same tint, faint: the icon every card and row
/// leads with.
public struct IconTile: View {
    let symbol: String
    var tint: Color
    var size: CGFloat

    public init(symbol: String, tint: Color = .accentColor, size: CGFloat = 34) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tint.opacity(0.13)))
            .accessibilityHidden(true)
    }
}

/// The top of a tool's page of the dropdown: its mark, its name (with a ? to its Help, when it has
/// one) and one line under it, then anything at its right (the tool's main switch).
public struct PageHeader<Trailing: View>: View {
    let logo: AnyView
    let title: String
    let line: String?
    let help: (() -> Void)?
    let trailing: Trailing

    public init(logo: AnyView, title: String, line: String?, help: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing) {
        self.logo = logo
        self.title = title
        self.line = line
        self.help = help
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 10) {
            logo.shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let help { HelpButton(subject: title, action: help) }
                }
                if let line {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension PageHeader where Trailing == EmptyView {
    public init(logo: AnyView, title: String, line: String?, help: (() -> Void)? = nil) {
        self.init(logo: logo, title: title, line: line, help: help) { EmptyView() }
    }
}

/// The ? beside a name that opens its Help: quiet until the pointer is on it.
public struct HelpButton: View {
    let subject: String
    let action: () -> Void
    @State private var hovering = false

    public init(subject: String, action: @escaping () -> Void) {
        self.subject = subject
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(hovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(subject) Help")
        .accessibilityLabel("\(subject) Help")
    }
}

extension EnvironmentValues {
    /// Set by the dropdown on a tool's page: opens that tool's Help over it.
    @Entry public var openHelp: (() -> Void)? = nil
}

/// A rounded, faintly filled panel around its content, padded.
public struct ContentCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    public init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(CardStyle.fill))
            .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(CardStyle.stroke))
    }
}

/// A small title over a rounded panel of rows (the rows draw their own padding and hairlines).
public struct TitledCard<Content: View>: View {
    let title: String
    let trailing: AnyView?
    let content: Content

    public init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(CardStyle.fill))
                .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(CardStyle.stroke))
                .clipShape(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous))
        }
    }
}

/// One setting on a card: its icon, its name (after the part it belongs to, if given) and a line on
/// what it does, then its control at the right.
public struct SettingCard<Control: View>: View {
    let symbol: String
    let section: String?
    let title: String
    let detail: String
    let control: Control

    public init(symbol: String, section: String? = nil, title: String, detail: String,
                @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.section = section
        self.title = title
        self.detail = detail
        self.control = control()
    }

    public var body: some View {
        ContentCard(padding: 10) {
            SettingRow(symbol: symbol, title: section.map { "\($0) · \(title)" } ?? title, detail: detail) { control }
        }
    }
}

/// A setting's line inside a card that holds several: icon, name, a line on what it does, control.
public struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String?
    let control: Control

    public init(symbol: String, title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: .secondary, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(minHeight: 30)
    }
}

/// A feature in a few words: its tile, its name and a line or two on it.
public struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    public init(_ symbol: String, _ title: String, _ detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The line above a lesson's picture, with its buttons at its right.
public struct LessonIntro<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    public init(text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            trailing
        }
        .controlSize(.small)
        .frame(height: 24)
    }
}

extension LessonIntro where Trailing == EmptyView {
    public init(text: String) { self.init(text: text) { EmptyView() } }
}

/// One thing to do in a lesson, ticked once it has been done.
public struct LessonStep: View {
    let title: String
    let detail: String
    let done: Bool

    public init(title: String, detail: String, done: Bool) {
        self.title = title
        self.detail = detail
        self.done = done
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }
}

/// The system sidebar material, so a window's side list reads like every other Mac window's.
public struct SidebarMaterial: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// App icons by bundle identifier, looked up once.
public enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    public static func icon(bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        cache[bundleID] = image
        return image
    }
}
#endif
