#if canImport(AppKit)
import AppKit
import SwiftUI

// mac++'s Settings and Help, drawn the way System Settings draws its panes: a centred icon, title and line at
// the top, then rows grouped on rounded cards, each card with a heading over it and a note under it.

/// A pane's mark, as System Settings draws one: a white glyph on a rounded square of colour.
public struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat

    public init(_ symbol: String, _ color: Color, size: CGFloat = 22) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// The top of a pane: its icon, its title (with a ? to its Help, when it has one), and what it is
/// for, centred.
public struct SettingsHero: View {
    let icon: AnyView
    let title: String
    let text: String?
    let help: (() -> Void)?

    public init(icon: AnyView, title: String, text: String?, help: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.text = text
        self.help = help
    }

    public var body: some View {
        VStack(spacing: 6) {
            icon
            HStack(spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let help { HelpButton(subject: title, action: help) }
            }
            if let text {
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

/// Rows on one rounded card, a hairline between each, with an optional heading over the card and
/// note under it.
public struct SettingsSection<Content: View>: View {
    let header: String?
    let footer: String?
    let content: Content

    public init(_ header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            _VariadicView.Tree(DividedRows()) { content }
                .background(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).fill(CardStyle.fill))
                .overlay(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous).strokeBorder(CardStyle.stroke))
                .clipShape(RoundedRectangle(cornerRadius: CardStyle.corner, style: .continuous))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A hairline between each row of a section, starting where the rows' titles do.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child.overlay(alignment: .top) {
                    if child.id != children.first?.id { Divider().padding(.leading, 10) }
                }
            }
        }
    }
}

/// One row: an icon, a title with any note under it, and what sits at its end.
public struct SettingsRow<Trailing: View>: View {
    let icon: AnyView?
    let title: String
    let detail: String?
    var tint: Color?
    let trailing: Trailing

    public init(icon: AnyView? = nil, _ title: String, detail: String? = nil, tint: Color? = nil,
                @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tint = tint
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: 10) {
            if let icon { icon.frame(width: 22, height: 22) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, detail == nil ? 0 : 2)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

extension SettingsRow where Trailing == EmptyView {
    public init(icon: AnyView? = nil, _ title: String, detail: String? = nil, tint: Color? = nil) {
        self.init(icon: icon, title, detail: detail, tint: tint) { EmptyView() }
    }
}

/// A row that goes somewhere: to another page (a chevron at its end), or out to a window (an arrow
/// out of a box). Lit while the pointer is on it.
public struct SettingsLink: View {
    public enum Kind { case pane, window }

    let icon: AnyView?
    let title: String
    let detail: String?
    let value: String?
    let kind: Kind
    let action: () -> Void
    @State private var hovering = false

    public init(icon: AnyView? = nil, _ title: String, detail: String? = nil, value: String? = nil,
                kind: Kind = .pane, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.value = value
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            SettingsRow(icon: icon, title, detail: detail, tint: kind == .window ? .accentColor : nil) {
                HStack(spacing: 6) {
                    if let value { Text(value).foregroundStyle(.secondary) }
                    Image(systemName: kind == .pane ? "chevron.right" : "arrow.up.forward.square")
                        .font(.system(size: kind == .pane ? 11 : 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .background(Color.primary.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A row with a switch at its end.
public struct SettingsToggle: View {
    let icon: AnyView?
    let title: String
    let detail: String?
    let isOn: Bool
    let set: (Bool) -> Void

    public init(icon: AnyView? = nil, _ title: String, detail: String? = nil, isOn: Bool,
                set: @escaping (Bool) -> Void) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.set = set
    }

    public var body: some View {
        SettingsRow(icon: icon, title, detail: detail) {
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}
#endif
