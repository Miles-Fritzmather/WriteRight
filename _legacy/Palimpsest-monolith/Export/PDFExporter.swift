import CoreGraphics
import Foundation
import UIKit

/// Renders a page's committed ink to a PDF page, embedding the Vision-
/// recognized text as an invisible, selectable layer (drawn with a clear
/// fill color) so the export is a genuinely searchable PDF.
enum PDFExporter {
    static func exportPage(strokes: [Stroke], recognizedText: [RecognizedTextLine], pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            let cg = context.cgContext

            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: pageSize))

            var contentRect = strokes.reduce(CGRect.null) { $0.union($1.boundingBox) }
            if contentRect.isNull { contentRect = CGRect(origin: .zero, size: pageSize) }
            let scale = min(pageSize.width / max(contentRect.width, 1), pageSize.height / max(contentRect.height, 1))

            cg.saveGState()
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -contentRect.minX, y: -contentRect.minY)
            for stroke in strokes {
                StrokeRasterizer.draw(stroke, in: cg)
            }
            cg.restoreGState()

            for line in recognizedText {
                let rect = CGRect(
                    x: (line.boundingBox.minX - contentRect.minX) * scale,
                    y: (line.boundingBox.minY - contentRect.minY) * scale,
                    width: line.boundingBox.width * scale,
                    height: line.boundingBox.height * scale
                )
                guard rect.height > 0 else { continue }
                let font = UIFont.systemFont(ofSize: max(rect.height * 0.8, 4))
                let attributed = NSAttributedString(string: line.text, attributes: [
                    .font: font,
                    .foregroundColor: UIColor.clear,
                ])
                attributed.draw(in: rect)
            }
        }
    }

    static func exportNotebook(pages: [(strokes: [Stroke], text: [RecognizedTextLine])], pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                drawPage(strokes: page.strokes, recognizedText: page.text, pageSize: pageSize, in: context.cgContext)
            }
        }
    }

    private static func drawPage(strokes: [Stroke], recognizedText: [RecognizedTextLine], pageSize: CGSize, in cg: CGContext) {
        UIColor.white.setFill()
        cg.fill(CGRect(origin: .zero, size: pageSize))

        var contentRect = strokes.reduce(CGRect.null) { $0.union($1.boundingBox) }
        if contentRect.isNull { contentRect = CGRect(origin: .zero, size: pageSize) }
        let scale = min(pageSize.width / max(contentRect.width, 1), pageSize.height / max(contentRect.height, 1))

        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -contentRect.minX, y: -contentRect.minY)
        for stroke in strokes {
            StrokeRasterizer.draw(stroke, in: cg)
        }
        cg.restoreGState()

        for line in recognizedText {
            let rect = CGRect(
                x: (line.boundingBox.minX - contentRect.minX) * scale,
                y: (line.boundingBox.minY - contentRect.minY) * scale,
                width: line.boundingBox.width * scale,
                height: line.boundingBox.height * scale
            )
            guard rect.height > 0 else { continue }
            let font = UIFont.systemFont(ofSize: max(rect.height * 0.8, 4))
            NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: UIColor.clear]).draw(in: rect)
        }
    }
}
