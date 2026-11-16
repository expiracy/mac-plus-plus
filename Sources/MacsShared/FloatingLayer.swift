import SwiftUI

/// Something a page floats over the whole dropdown, past its scrolling and its footer, so nothing
/// cuts it off: drawn by `content` from where `anchor` is and how big the dropdown is.
public struct FloatingLayer {
    public let anchor: Anchor<CGRect>
    public let content: (_ anchor: CGRect, _ space: CGSize) -> AnyView

    public init(anchor: Anchor<CGRect>, content: @escaping (_ anchor: CGRect, _ space: CGSize) -> AnyView) {
        self.anchor = anchor
        self.content = content
    }
}

/// The page's floating layer, if it has one open; the dropdown draws it over everything.
public struct FloatingLayerKey: PreferenceKey {
    public static var defaultValue: FloatingLayer? { nil }
    public static func reduce(value: inout FloatingLayer?, nextValue: () -> FloatingLayer?) {
        value = value ?? nextValue()
    }
}
