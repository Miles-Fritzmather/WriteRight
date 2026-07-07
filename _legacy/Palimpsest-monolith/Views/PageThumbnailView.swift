import SwiftUI
import UIKit

/// Lightweight, non-tiled rasterization of a page's full extent — reuses
/// `StrokeRasterizer` so thumbnails match the on-canvas ink exactly.
struct PageThumbnailView: View {
    let page: Page
    let repository: NotebookRepository

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            // `.onAppear` (not `.task(id:)`) deliberately — this must
            // re-render every time the grid reappears (e.g. navigating back
            // from the canvas after drawing), not just once per page identity.
            Task {
                image = await Self.renderThumbnail(pageID: page.id, repository: repository)
            }
        }
    }

    static func renderThumbnail(pageID: UUID, repository: NotebookRepository) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let strokes = try? repository.allStrokes(onPage: pageID), !strokes.isEmpty else { return nil }
            var bounds = strokes[0].boundingBox
            for stroke in strokes.dropFirst() { bounds = bounds.union(stroke.boundingBox) }
            bounds = bounds.insetBy(dx: -20, dy: -20)
            guard bounds.width > 0, bounds.height > 0 else { return nil }

            let width: CGFloat = 300
            let size = CGSize(width: width, height: width * bounds.height / bounds.width)
            let scale = width / bounds.width

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let cg = context.cgContext
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -bounds.minX, y: -bounds.minY)
                for stroke in strokes {
                    StrokeRasterizer.draw(stroke, in: cg)
                }
            }
        }.value
    }
}
