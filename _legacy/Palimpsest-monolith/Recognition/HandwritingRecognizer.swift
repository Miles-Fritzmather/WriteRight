import CoreGraphics
import Foundation
import UIKit
import Vision

/// Rasterizes a page's ink and runs on-device Vision OCR over it, mapping
/// each recognized line's bounding box back into canvas space so a search
/// hit can pan the camera straight to where it was written.
enum HandwritingRecognizer {
    static func recognize(strokes: [Stroke], pageID: UUID) async -> [RecognizedTextLine] {
        guard !strokes.isEmpty else { return [] }

        let padding: CGFloat = 40
        let bounds = strokes
            .dropFirst()
            .reduce(strokes[0].boundingBox) { $0.union($1.boundingBox) }
            .insetBy(dx: -padding, dy: -padding)
        guard bounds.width > 1, bounds.height > 1 else { return [] }

        let scale: CGFloat = 2
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard pixelSize.width < 8000, pixelSize.height < 8000 else { return [] }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -bounds.minX, y: -bounds.minY)
            for stroke in strokes {
                StrokeRasterizer.draw(stroke, in: cg)
            }
        }
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision's normalized bounding box has its origin at the
            // bottom-left of the image; flip it back into our top-left,
            // canvas-space convention.
            let normalized = observation.boundingBox
            let canvasRect = CGRect(
                x: bounds.minX + normalized.origin.x * bounds.width,
                y: bounds.minY + (1 - normalized.origin.y - normalized.height) * bounds.height,
                width: normalized.width * bounds.width,
                height: normalized.height * bounds.height
            )
            return RecognizedTextLine(pageID: pageID, text: candidate.string, boundingBox: canvasRect)
        }
    }
}
