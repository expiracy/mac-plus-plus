#if canImport(AppKit)
import SwiftUI

/// The bubble mac++'s apps draw their menus in: a rounded panel with a small nub on top pointing at what it came from (the
/// menu-bar icon, the System Settings list). The nub sits at `nubX` from the left edge, or in the
/// middle when that is nil, and is kept clear of the rounded corners. With `pointsDown` the nub
/// sits on the bottom edge instead, for a bubble that opens upward.
public struct SpeechBubbleShape: Shape {
    public static let standardNub = CGSize(width: 22, height: 9)

    public var nub = SpeechBubbleShape.standardNub
    public var nubX: CGFloat?
    public var corner: CGFloat = 14
    public var pointsDown = false

    public init(nub: CGSize = SpeechBubbleShape.standardNub, nubX: CGFloat? = nil, corner: CGFloat = 14,
                pointsDown: Bool = false) {
        self.nub = nub
        self.nubX = nubX
        self.corner = corner
        self.pointsDown = pointsDown
    }

    public func path(in rect: CGRect) -> Path {
        let up = upwardPath(in: rect)
        guard pointsDown else { return up }
        return up.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY))
    }

    private func upwardPath(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + nub.height, width: rect.width, height: rect.height - nub.height)
        let panel = Path(roundedRect: body, cornerRadius: corner, style: .continuous)
        let clear = corner + nub.width / 2
        let x = min(max(rect.minX + (nubX ?? rect.width / 2), rect.minX + clear), rect.maxX - clear)
        var tip = Path()
        tip.move(to: CGPoint(x: x - nub.width / 2, y: body.minY + 0.5))
        tip.addQuadCurve(to: CGPoint(x: x, y: rect.minY),
                         control: CGPoint(x: x - nub.width / 6, y: rect.minY + 1))
        tip.addQuadCurve(to: CGPoint(x: x + nub.width / 2, y: body.minY + 0.5),
                         control: CGPoint(x: x + nub.width / 6, y: rect.minY + 1))
        tip.closeSubpath()
        return panel.union(tip)   // one outline, so the border runs round the nub without a seam
    }
}
#endif
