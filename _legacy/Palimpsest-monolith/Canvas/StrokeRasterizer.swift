import CoreGraphics
import UIKit

/// Shared canvas-space -> pixels rasterization, used by both the tiled
/// on-screen renderer and the PDF exporter so committed ink looks identical
/// in both places.
enum StrokeRasterizer {
    static func draw(_ stroke: Stroke, in context: CGContext) {
        guard stroke.points.count > 0 else { return }
        let color = stroke.style.color
        context.saveGState()
        context.setBlendMode(stroke.style.blendMode == .multiply ? .multiply : .normal)
        context.setStrokeColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        context.setLineWidth(stroke.style.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if stroke.points.count == 1 {
            let p = stroke.points[0].location
            context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            context.fillEllipse(in: CGRect(x: p.x - stroke.style.width / 2, y: p.y - stroke.style.width / 2, width: stroke.style.width, height: stroke.style.width))
            context.restoreGState()
            return
        }

        let path = CGMutablePath()
        path.move(to: stroke.points[0].location)
        for i in 1..<stroke.points.count {
            let mid = midpoint(stroke.points[i - 1].location, stroke.points[i].location)
            path.addQuadCurve(to: mid, control: stroke.points[i - 1].location)
        }
        path.addLine(to: stroke.points[stroke.points.count - 1].location)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
