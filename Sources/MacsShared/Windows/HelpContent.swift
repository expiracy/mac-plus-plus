#if canImport(AppKit)
import AppKit
import SwiftUI

/// What a Help page says (a tool's, or mac++'s): what it is for, how each part of it works, and its
/// keys.
public struct HelpContent {
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
    public var topics: [Topic]
    public var keys: [Key]
    /// A last word, such as where the tool keeps its settings.
    public var footnote: String?
    /// Drawn above the lessons, under the last word.
    public var links: [Link]

    public init(name: String, tagline: String, logo: @escaping (CGFloat) -> AnyView, title: String? = nil,
                mark: ((CGFloat) -> AnyView)? = nil, topics: [Topic], keys: [Key] = [], footnote: String? = nil,
                links: [Link] = []) {
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

/// A Help page of the dropdown, drawn as Settings' panes are: what it is for, how each part works,
/// its keys and any last word, then its lessons again (in the onboarding window).
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
            SettingsSection("How it works") {
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
#endif
