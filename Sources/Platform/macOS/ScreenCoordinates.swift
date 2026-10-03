import CoreGraphics
import Foundation

func flippedScreenPoint(_ point: CGPoint, primaryScreenTop: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: primaryScreenTop - point.y)
}
