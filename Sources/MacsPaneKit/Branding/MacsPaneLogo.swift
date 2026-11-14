#if canImport(AppKit)
import MacsShared
import AppKit
import SwiftUI

/// MacsPane's mark, drawn in code so its page of the dropdown, its Help and onboarding share one
/// source (mac++'s own icon is `MacPlusPlusLogo`).
///
/// - `MacsPaneLogo` is the tool's tile: a slate tile with the notch hanging from its top edge, a window
///   snapped into the left half in blue and its neighbour outlined. It has a dark (slate) face and a
///   light face, and follows the colour scheme unless told which to wear.
///
/// Geometry is in units of the tile (1 = its side).
struct MacsPaneLogo: View {
    var size: CGFloat = 40
    /// The icon file's own canvas: the tile inset in transparent margin with its drop shadow.
    var iconCanvas = false
    /// Which face to draw; nil follows the surrounding colour scheme.
    var face: ColorScheme?
    /// Only the marks (notch and panes) on a clear square, the layer the system's icon format stacks on its fill.
    var marksOnly = false
    @Environment(\.colorScheme) private var scheme

    /// The pane you aim at in the picker: the system blue the snap highlight uses.
    static let paneBlue = Color(red: 0.04, green: 0.52, blue: 1)

    private var dark: Bool { (face ?? scheme) == .dark }
    private var tileColours: [Color] { dark ? [Color(white: 0.25), Color(white: 0.09)] : [.white, Color(white: 0.89)] }
    private var outlineColour: Color { dark ? Color(white: 0.91) : Color(white: 0.23) }

    var body: some View {
        let tile = iconCanvas ? size * 824 / 1024 : size
        let shape = RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
        if marksOnly {
            marks(tile: tile).frame(width: tile, height: tile)
        } else {
            ZStack {
                LinearGradient(colors: tileColours, startPoint: .top, endPoint: .bottom)
                marks(tile: tile)
            }
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: dark ? [.white.opacity(0.35), .white.opacity(0.02)]
                                                                     : [.black.opacity(0.05), .black.opacity(0.16)],
                                                        startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(0.5, tile * 0.0036)))
            .shadow(color: .black.opacity(iconCanvas ? 0.28 : 0), radius: tile * 0.024, y: tile * 0.0146)
            .frame(width: size, height: size)
            .accessibilityLabel("MacsPane")
        }
    }

    /// The notch hanging from the top edge, then the two panes: the left one snapped (filled blue), the
    /// right one waiting (outlined).
    private func marks(tile: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            NotchMarkShape(width: 0.37, height: 0.12, flare: 0.033, radius: 0.044).fill(.black)
            RoundedRectangle(cornerRadius: tile * 0.065, style: .continuous)
                .fill(Self.paneBlue)
                .frame(width: tile * 0.315, height: tile * 0.587)
                .offset(x: tile * 0.163, y: tile * 0.272)
            RoundedRectangle(cornerRadius: tile * 0.054, style: .continuous)
                .strokeBorder(outlineColour, lineWidth: tile * 0.0435)
                .frame(width: tile * 0.293, height: tile * 0.565)
                .offset(x: tile * 0.543, y: tile * 0.283)
        }
        .frame(width: tile, height: tile, alignment: .topLeading)
    }
}

#endif
