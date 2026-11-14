#if canImport(AppKit)
import AppKit
import SwiftUI

/// mac++'s marks, drawn in code so the icon file, the menu bar, the dropdown, onboarding, Settings and
/// Help share one source: an apple (a plain fruit: round, with a stem and a leaf, and no bite out of
/// it) with "++" inside.
///
/// - `MacPlusPlusLogo` is the app icon: a tile with a blue apple, a green leaf and a white "++". It has
///   a light face and a dark (slate) face, and follows the colour scheme unless told which to wear.
/// - `MacPlusPlusGlyph` is the one-colour mark for the menu bar: an outlined apple with a solid "++",
///   or, while MacsBored is handing macOS's shortcuts to an app, a solid apple with the "++" cut out.
///
/// Geometry is on a 100-unit square.
public enum MacPlusPlusMark {
    /// The apple's body: two shoulders either side of a dimple at the top, full sides, and a small
    /// dimple at the foot.
    public static func body(in rect: CGRect) -> Path {
        let p = grid(rect)
        var path = Path()
        path.move(to: p(50, 32))
        path.addCurve(to: p(83, 31), control1: p(58, 24), control2: p(73, 22))
        path.addCurve(to: p(87, 74), control1: p(95, 41), control2: p(95, 61))
        path.addCurve(to: p(63, 94), control1: p(81, 86), control2: p(72, 94))
        path.addCurve(to: p(50, 91), control1: p(57, 94), control2: p(55, 91))
        path.addCurve(to: p(37, 94), control1: p(45, 91), control2: p(43, 94))
        path.addCurve(to: p(13, 74), control1: p(28, 94), control2: p(19, 86))
        path.addCurve(to: p(17, 31), control1: p(5, 61), control2: p(5, 41))
        path.addCurve(to: p(50, 32), control1: p(27, 22), control2: p(42, 24))
        path.closeSubpath()
        return path
    }

    /// The stem, as a line to stroke with round ends.
    public static func stem(in rect: CGRect) -> Path {
        let p = grid(rect)
        var path = Path()
        path.move(to: p(50, 30))
        path.addCurve(to: p(55, 12), control1: p(50, 22), control2: p(51, 16))
        return path
    }

    public static func stemWidth(in rect: CGRect) -> CGFloat { 6 * unit(rect) }

    /// The leaf, off the stem to the right.
    public static func leaf(in rect: CGRect) -> Path {
        let p = grid(rect)
        var path = Path()
        path.move(to: p(57, 22))
        path.addCurve(to: p(77, 7), control1: p(59, 12), control2: p(68, 6))
        path.addCurve(to: p(57, 22), control1: p(75, 17), control2: p(66, 23))
        path.closeSubpath()
        return path
    }

    /// The two plus signs, side by side in the apple's middle. Each is one outline (not two crossed
    /// bars), so it can be cut out of the solid apple cleanly.
    public static func plusses(in rect: CGRect, scale: CGFloat = 1) -> Path {
        let u = unit(rect)
        let p = grid(rect)
        let a = 10 * scale * u
        let b = 3.6 * scale * u
        var path = Path()
        for c in [p(36, 62), p(64, 62)] {
            path.addLines([
                CGPoint(x: c.x - b, y: c.y - a), CGPoint(x: c.x + b, y: c.y - a), CGPoint(x: c.x + b, y: c.y - b),
                CGPoint(x: c.x + a, y: c.y - b), CGPoint(x: c.x + a, y: c.y + b), CGPoint(x: c.x + b, y: c.y + b),
                CGPoint(x: c.x + b, y: c.y + a), CGPoint(x: c.x - b, y: c.y + a), CGPoint(x: c.x - b, y: c.y + b),
                CGPoint(x: c.x - a, y: c.y + b), CGPoint(x: c.x - a, y: c.y - b), CGPoint(x: c.x - b, y: c.y - b),
            ])
            path.closeSubpath()
        }
        return path
    }

    private static func unit(_ rect: CGRect) -> CGFloat { min(rect.width, rect.height) / 100 }

    private static func grid(_ rect: CGRect) -> (CGFloat, CGFloat) -> CGPoint {
        let u = unit(rect)
        let origin = CGPoint(x: rect.midX - 50 * u, y: rect.midY - 50 * u)
        return { x, y in CGPoint(x: origin.x + x * u, y: origin.y + y * u) }
    }
}

/// The app icon: the apple on a tile.
public struct MacPlusPlusLogo: View {
    var size: CGFloat
    /// The icon file's own canvas: the tile inset in transparent margin with its drop shadow.
    var iconCanvas: Bool
    /// Which face to draw; nil follows the surrounding colour scheme.
    var face: ColorScheme?
    /// Only the apple on a clear square, the layer the system's icon format stacks on its fill.
    var marksOnly: Bool
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat = 40, iconCanvas: Bool = false, face: ColorScheme? = nil, marksOnly: Bool = false) {
        self.size = size
        self.iconCanvas = iconCanvas
        self.face = face
        self.marksOnly = marksOnly
    }

    /// The apple's blue: the system blue the rest of mac++ is drawn in, deepening towards the foot.
    static let appleTop = Color(red: 0.16, green: 0.6, blue: 1)
    static let appleFoot = Color(red: 0.0, green: 0.4, blue: 0.92)
    static let leafColour = Color(red: 0.2, green: 0.78, blue: 0.37)

    private var dark: Bool { (face ?? scheme) == .dark }
    private var tileColours: [Color] { dark ? [Color(white: 0.25), Color(white: 0.09)] : [.white, Color(white: 0.89)] }
    private var stemColour: Color { dark ? Color(white: 0.85) : Color(white: 0.3) }

    public var body: some View {
        let tile = iconCanvas ? size * 824 / 1024 : size
        let shape = RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
        if marksOnly {
            apple.frame(width: tile, height: tile)
        } else {
            ZStack {
                LinearGradient(colors: tileColours, startPoint: .top, endPoint: .bottom)
                apple.padding(tile * 0.14)
            }
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: dark ? [.white.opacity(0.35), .white.opacity(0.02)]
                                                                     : [.black.opacity(0.05), .black.opacity(0.16)],
                                                        startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(0.5, tile * 0.0036)))
            .shadow(color: .black.opacity(iconCanvas ? 0.28 : 0), radius: tile * 0.024, y: tile * 0.0146)
            .frame(width: size, height: size)
            .accessibilityLabel("mac++")
        }
    }

    private var apple: some View {
        Canvas { context, canvas in
            let rect = CGRect(origin: .zero, size: canvas)
            context.stroke(MacPlusPlusMark.stem(in: rect), with: .color(stemColour),
                           style: StrokeStyle(lineWidth: MacPlusPlusMark.stemWidth(in: rect), lineCap: .round))
            context.fill(MacPlusPlusMark.leaf(in: rect), with: .color(Self.leafColour))
            let body = MacPlusPlusMark.body(in: rect)
            context.fill(body, with: .linearGradient(Gradient(colors: [Self.appleTop, Self.appleFoot]),
                                                      startPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25),
                                                      endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            context.fill(MacPlusPlusMark.plusses(in: rect), with: .color(.white))
        }
    }
}

/// The one-colour mark, drawn in the current foreground style so it tints like an SF Symbol.
public struct MacPlusPlusGlyph: View {
    /// Solid apple with the "++" cut out (MacsBored passing shortcuts on), rather than an outline.
    var filled: Bool

    public init(filled: Bool = false) {
        self.filled = filled
    }

    public var body: some View {
        Canvas { context, size in
            Self.draw(in: CGRect(origin: .zero, size: size), filled: filled) { path, how in
                switch how {
                case .fill: context.fill(path, with: .foreground)
                case .evenOdd: context.fill(path, with: .foreground, style: FillStyle(eoFill: true))
                case let .stroke(width): context.stroke(path, with: .foreground,
                                                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityLabel("mac++")
    }

    enum Paint { case fill, evenOdd, stroke(CGFloat) }

    /// The glyph's paths and how each is painted, shared by the view and the template image.
    static func draw(in rect: CGRect, filled: Bool, paint: (Path, Paint) -> Void) {
        // The menu bar's square is a touch roomier than the fruit needs; pull it in so it sits with
        // the other icons' weight.
        let inner = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03)
        let u = min(inner.width, inner.height) / 100
        paint(MacPlusPlusMark.stem(in: inner), .stroke(MacPlusPlusMark.stemWidth(in: inner) * 1.2))
        paint(MacPlusPlusMark.leaf(in: inner), .fill)
        if filled {
            var cut = MacPlusPlusMark.body(in: inner)
            cut.addPath(MacPlusPlusMark.plusses(in: inner, scale: 1.12))
            paint(cut, .evenOdd)
        } else {
            let line = 8 * u
            // Stroked inside the outline, so the outline keeps the fruit's size.
            let body = MacPlusPlusMark.body(in: inner.insetBy(dx: line / 2, dy: line / 2))
            paint(body, .stroke(line))
            paint(MacPlusPlusMark.plusses(in: inner, scale: 0.95), .fill)
        }
    }

    /// The menu bar's template image.
    public static func templateImage(filled: Bool = false, pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            draw(in: rect, filled: filled) { path, how in
                context.addPath(path.cgPath)
                switch how {
                case .fill: context.fillPath()
                case .evenOdd: context.fillPath(using: .evenOdd)
                case let .stroke(width):
                    context.setLineWidth(width)
                    context.strokePath()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = filled ? "mac++, shortcuts going to the app in front" : "mac++"
        return image
    }
}
#endif
