#if canImport(AppKit)
import AppKit
import SwiftUI

/// What a Help page says (a tool's, or mac++'s): what it is for, the shape of what you make with it
/// (the parts one is made of, in the order they act, with a few whole examples), how the rest of it
/// works, and its keys.
public struct HelpContent {
    /// The general shape of the thing a tool makes ("an action": a trigger, its steps, and where and
    /// when), so the page explains what people can do before how each control works.
    public struct Shape {
        /// One part, in the order the parts act.
        public struct Part: Identifiable {
            public let symbol: String
            public let title: String
            /// What the part is, in general, with the kinds it can be.
            public let text: String
            public var id: String { title }

            public init(_ symbol: String, _ title: String, _ text: String) {
                self.symbol = symbol
                self.title = title
                self.text = text
            }
        }

        /// The section's heading: "What an action is made of".
        public let title: String
        public let parts: [Part]
        /// Whole examples, each a phrase per part in the parts' order (fewer phrases leave the
        /// later parts out).
        public let examples: [[String]]
        /// A word under the parts, such as what happens when a part is left empty.
        public let footnote: String?

        public init(_ title: String, parts: [Part], examples: [[String]] = [], footnote: String? = nil) {
            self.title = title
            self.parts = parts
            self.examples = examples
            self.footnote = footnote
        }
    }

    public struct Topic: Identifiable {
        public let symbol: String
        public let title: String
        public let text: String
        public var id: String { title }

        public init(_ symbol: String, _ title: String, _ text: String) {
            self.symbol = symbol
            self.title = title
            self.text = text
        }
    }

    public struct Key: Identifiable {
        public let keys: String
        public let what: String
        public var id: String { keys + what }

        public init(_ keys: String, _ what: String) {
            self.keys = keys
            self.what = what
        }
    }

    /// Something Help can do beside explain, such as show a file in Finder. It leaves the dropdown.
    public struct Link: Identifiable {
        public let title: String
        public let action: () -> Void
        public var id: String { title }

        public init(_ title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    public var name: String
    /// One line under the name: what the tool does.
    public var tagline: String
    public var logo: (CGFloat) -> AnyView
    /// What the Help page calls the tool ("Windows"), when not `name`.
    public var title: String?
    /// The one-colour mark at the top of the Help page, drawn at a size, when not `logo`.
    public var mark: ((CGFloat) -> AnyView)?
    /// What you make with the tool and the parts it's made of, drawn above `topics`.
    public var shape: Shape?
    public var topics: [Topic]
    public var keys: [Key]
    /// A last word, such as where the tool keeps its settings.
    public var footnote: String?
    /// Drawn above the lessons, under the last word.
    public var links: [Link]

    public init(name: String, tagline: String, logo: @escaping (CGFloat) -> AnyView, title: String? = nil,
                mark: ((CGFloat) -> AnyView)? = nil, shape: Shape? = nil, topics: [Topic], keys: [Key] = [],
                footnote: String? = nil, links: [Link] = []) {
        self.shape = shape
        self.links = links
        self.name = name
        self.tagline = tagline
        self.logo = logo
        self.title = title
        self.mark = mark
        self.topics = topics
        self.keys = keys
        self.footnote = footnote
    }
}
extension HelpContent {
    /// A `mark` drawn from an SF Symbol, in one colour, about the size asked for.
    public static func symbolMark(_ symbol: String) -> (CGFloat) -> AnyView {
        { size in
            AnyView(Image(systemName: symbol).font(.system(size: size * 0.8, weight: .regular))
                .foregroundStyle(.primary).frame(width: size, height: size).accessibilityHidden(true))
        }
    }
}

/// A Help page of the dropdown, drawn as Settings' panes are: what it is for, the shape of what you
/// make with it, how the rest works, its keys and any last word, then its lessons again (in the
/// onboarding window).
public struct HelpPane: View {
    let content: HelpContent
    let replayTitle: String
    let onReplay: () -> Void

    public init(content: HelpContent, replayTitle: String, onReplay: @escaping () -> Void) {
        self.content = content
        self.replayTitle = replayTitle
        self.onReplay = onReplay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHero(icon: (content.mark ?? content.logo)(40), title: content.title ?? content.name,
                         text: content.tagline)
            if let shape = content.shape { HelpShapeSections(shape: shape) }
            SettingsSection(content.shape == nil ? "How it works" : "Good to know") {
                ForEach(content.topics) { topic in
                    SettingsRow(icon: AnyView(SettingsIcon(topic.symbol, .accentColor)), topic.title, detail: topic.text)
                }
            }
            if !content.keys.isEmpty {
                SettingsSection("Keys") {
                    ForEach(content.keys) { key in
                        SettingsRow(key.what) {
                            Text(key.keys).font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                }
            }
            SettingsSection(footer: content.footnote) {
                ForEach(content.links) { SettingsLink($0.title, kind: .window, action: $0.action) }
                SettingsLink(replayTitle, kind: .window, action: onReplay)
            }
        }
        // The same margin as a tool's page.
        .padding(12)
    }
}

/// A shape's sections: its parts joined by arrows, then each part on a row of its own, then its
/// examples, each one whole, its phrases joined by the same arrows.
private struct HelpShapeSections: View {
    let shape: HelpContent.Shape

    var body: some View {
        SettingsSection(shape.title, footer: shape.footnote) {
            flow
            ForEach(shape.parts) { part in
                SettingsRow(icon: AnyView(SettingsIcon(part.symbol, .accentColor)), part.title, detail: part.text)
            }
        }
        if !shape.examples.isEmpty {
            SettingsSection("For example") {
                ForEach(Array(shape.examples.enumerated()), id: \.offset) { _, phrases in
                    Self.sentence(phrases)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    /// The parts' names in order, an arrow between each: the shape at a glance. Drawn smaller, then
    /// without the parts' symbols, when the menu is too narrow for it (the larger sizes).
    private var flow: some View {
        ViewThatFits(in: .horizontal) {
            strip(font: .callout, spacing: 8, symbols: true)
            strip(font: .caption, spacing: 5, symbols: true)
            strip(font: .caption, spacing: 4, symbols: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private func strip(font: Font, spacing: CGFloat, symbols: Bool) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(shape.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Self.arrow.accessibilityHidden(true) }
                HStack(spacing: 5) {
                    if symbols {
                        Image(systemName: part.symbol).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(part.title).font(font.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, spacing)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .fixedSize()
            }
        }
    }

    private static var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
    }

    /// "⌥Space → Open Terminal → Only in Finder", the arrows faint.
    private static func sentence(_ phrases: [String]) -> Text {
        phrases.filter { !$0.isEmpty }.enumerated().reduce(Text("")) { text, item in
            item.offset == 0 ? text + Text(item.element)
                : text + Text("  →  ").foregroundStyle(.tertiary) + Text(item.element)
        }
    }
}
#endif
