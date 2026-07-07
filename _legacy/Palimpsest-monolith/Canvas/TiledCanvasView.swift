import UIKit

struct TileKey: Hashable {
    var x: Int
    var y: Int
}

private struct TileCacheKey: Hashable {
    var key: TileKey
    var tier: Int
}

/// Renders *committed* strokes only — live ink while drawing is PencilKit's
/// job (see `CanvasHostView`). The canvas plane is divided into a fixed grid;
/// each visible tile is rasterized once into a `UIImage` and cached, so
/// pan/zoom/rotate is just re-compositing cached images through the camera
/// transform. A tile is only re-rendered when a stroke inside it changes, or
/// when the zoom level crosses a resolution tier boundary.
final class TiledCanvasView: UIView {
    static let tileSize: CGFloat = 512

    var camera: CanvasCamera! {
        didSet { setNeedsDisplay() }
    }

    /// Supplies every stroke whose bounding box intersects the given
    /// canvas-space rect. Backed by the repository's in-memory page cache
    /// (or, for very large pages, the R-tree index).
    var strokeProvider: ((CGRect) -> [Stroke])?

    private var cache: [TileCacheKey: UIImage] = [:]
    private var dirtyTileKeys: Set<TileKey> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Drops every cached tile — used when the host swaps in a different page.
    func resetCache() {
        cache.removeAll()
        dirtyTileKeys.removeAll()
        setNeedsDisplay()
    }

    /// Called by the canvas host after strokes are added, erased, or moved.
    func invalidate(canvasRects: [CGRect]) {
        for rect in canvasRects {
            for key in tileKeys(coveringCanvasRect: rect) {
                dirtyTileKeys.insert(key)
            }
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let camera, let context = UIGraphicsGetCurrentContext() else { return }

        let visibleCanvasRect = camera.canvasBoundingRect(ofScreenRect: bounds)
        let visibleKeys = tileKeys(coveringCanvasRect: visibleCanvasRect)
        let tier = Self.tier(forScale: camera.currentScale)

        for key in visibleKeys {
            let cacheKey = TileCacheKey(key: key, tier: tier)
            if dirtyTileKeys.contains(key) || cache[cacheKey] == nil {
                cache[cacheKey] = renderTile(key, tier: tier)
                dirtyTileKeys.remove(key)
                purgeStaleTiers(for: key, keeping: tier)
            }
        }

        context.saveGState()
        context.concatenate(camera.transform)
        for key in visibleKeys {
            guard let image = cache[TileCacheKey(key: key, tier: tier)] else { continue }
            image.draw(in: canvasRect(for: key))
        }
        context.restoreGState()
    }

    // MARK: - Tile geometry

    private func tileKeys(coveringCanvasRect rect: CGRect) -> [TileKey] {
        let size = Self.tileSize
        let minX = Int(floor(rect.minX / size))
        let maxX = Int(floor(rect.maxX / size))
        let minY = Int(floor(rect.minY / size))
        let maxY = Int(floor(rect.maxY / size))
        guard maxX - minX < 200, maxY - minY < 200 else { return [] } // sanity guard against runaway zoom-out
        var keys: [TileKey] = []
        for x in minX...maxX {
            for y in minY...maxY {
                keys.append(TileKey(x: x, y: y))
            }
        }
        return keys
    }

    private func canvasRect(for key: TileKey) -> CGRect {
        CGRect(x: CGFloat(key.x) * Self.tileSize, y: CGFloat(key.y) * Self.tileSize, width: Self.tileSize, height: Self.tileSize)
    }

    private static func tier(forScale scale: CGFloat) -> Int {
        let raw = Int(log2(max(scale, 0.001)).rounded())
        return min(max(raw, -3), 3)
    }

    private func purgeStaleTiers(for key: TileKey, keeping tier: Int) {
        for t in -3...3 where t != tier {
            cache.removeValue(forKey: TileCacheKey(key: key, tier: t))
        }
    }

    // MARK: - Rasterization

    private func renderTile(_ key: TileKey, tier: Int) -> UIImage {
        let rect = canvasRect(for: key)
        let pixelsPerCanvasUnit = pow(2, CGFloat(tier))
        let pixelSize = CGSize(width: Self.tileSize * pixelsPerCanvasUnit, height: Self.tileSize * pixelsPerCanvasUnit)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        let strokes = strokeProvider?(rect) ?? []
        return renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.scaleBy(x: pixelsPerCanvasUnit, y: pixelsPerCanvasUnit)
            cg.translateBy(x: -rect.minX, y: -rect.minY)
            for stroke in strokes {
                StrokeRasterizer.draw(stroke, in: cg)
            }
        }
    }
}
