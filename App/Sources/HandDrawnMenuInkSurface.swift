import SwiftUI

/// A bounded, menu-local ink layer used to prototype the diegetic menu
/// interaction. This is intentionally in-memory: future phases decide how
/// menu drawings map to folders, note names, and destructive commands.
struct HandDrawnMenuInkSurface<Content: View>: View {
    let key: String
    @ViewBuilder let content: () -> Content

    @State private var tool: MenuInkTool = .pen
    @State private var strokes: [MenuInkStroke] = []
    @State private var selectedStrokeIDs = Set<UUID>()
    @State private var activePoints: [CGPoint] = []
    @State private var activeTool: MenuInkTool?
    @State private var eraserLocation: CGPoint?
    @State private var contentSize: CGSize = .zero

    private var coordinateSpaceName: String { "menu-ink.\(key)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: MenuInkSizePreferenceKey.self, value: proxy.size)
                    }
                }
                .overlay {
                    MenuInkDrawingLayer(
                        strokes: strokes,
                        selectedStrokeIDs: selectedStrokeIDs,
                        activePoints: activePoints,
                        activeTool: activeTool,
                        eraserLocation: eraserLocation
                    )
                    .allowsHitTesting(false)
                }
                .coordinateSpace(name: coordinateSpaceName)
                .contentShape(Rectangle())
                .simultaneousGesture(inkGesture)
                .onPreferenceChange(MenuInkSizePreferenceKey.self) { contentSize = $0 }

            toolStrip
        }
    }

    private var inkGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentTool = activeTool ?? tool
                activeTool = currentTool

                let point = clamp(value.location, to: contentSize)
                if activePoints.isEmpty {
                    appendActivePoint(clamp(value.startLocation, to: contentSize))
                }
                appendActivePoint(point)

                switch currentTool {
                case .pen:
                    eraserLocation = nil
                case .eraser:
                    eraserLocation = point
                    erase(at: point)
                case .lasso:
                    eraserLocation = nil
                }
            }
            .onEnded { value in
                let point = clamp(value.location, to: contentSize)
                appendActivePoint(point)
                finishActiveGesture()
            }
    }

    private var toolStrip: some View {
        ViewThatFits(in: .horizontal) {
            toolStripContent
            ScrollView(.horizontal, showsIndicators: false) {
                toolStripContent
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var toolStripContent: some View {
        HStack(spacing: 5) {
            ForEach(MenuInkTool.allCases) { candidate in
                AppIconButton(
                    source: candidate.icon,
                    title: candidate.title,
                    isSelected: tool == candidate
                ) {
                    tool = candidate
                    activePoints.removeAll()
                    activeTool = nil
                    eraserLocation = nil
                    if candidate != .lasso {
                        selectedStrokeIDs.removeAll()
                    }
                }
            }

            if !selectedStrokeIDs.isEmpty {
                AppDivider(height: 34, key: "\(key).menu-ink.selection")
                AppIconButton(
                    source: .builtIn(name: "trash", fallbackSymbol: "trash"),
                    title: "Delete",
                    isSelected: false
                ) {
                    deleteSelection()
                }
            }

            if !strokes.isEmpty {
                AppDivider(height: 34, key: "\(key).menu-ink.clear")
                AppButton(label: "Clear") {
                    strokes.removeAll()
                    selectedStrokeIDs.removeAll()
                    activePoints.removeAll()
                }
            }
        }
        .padding(.top, 2)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private func appendActivePoint(_ point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let last = activePoints.last, distance(last, to: point) < 1.5 {
            return
        }
        activePoints.append(point)
    }

    private func finishActiveGesture() {
        defer {
            activePoints.removeAll()
            activeTool = nil
            eraserLocation = nil
        }

        guard let activeTool else { return }
        switch activeTool {
        case .pen:
            guard activePoints.count > 1, pathLength(activePoints) >= 4 else { return }
            selectedStrokeIDs.removeAll()
            strokes.append(MenuInkStroke(points: activePoints))
        case .eraser:
            selectedStrokeIDs = selectedStrokeIDs.filter { id in
                strokes.contains { $0.id == id }
            }
        case .lasso:
            guard activePoints.count > 2, pathLength(activePoints) >= 8 else {
                selectedStrokeIDs.removeAll()
                return
            }
            selectedStrokeIDs = strokeIDsHit(by: activePoints)
        }
    }

    private func erase(at point: CGPoint) {
        let hitIDs = Set(strokes.compactMap { stroke -> UUID? in
            stroke.contains(point, radius: MenuInkTool.eraserRadius) ? stroke.id : nil
        })
        guard !hitIDs.isEmpty else { return }
        strokes.removeAll { hitIDs.contains($0.id) }
        selectedStrokeIDs.subtract(hitIDs)
    }

    private func deleteSelection() {
        guard !selectedStrokeIDs.isEmpty else { return }
        strokes.removeAll { selectedStrokeIDs.contains($0.id) }
        selectedStrokeIDs.removeAll()
    }

    private func strokeIDsHit(by lassoPoints: [CGPoint]) -> Set<UUID> {
        guard lassoPoints.count > 1 else { return [] }

        let tolerance: CGFloat = 9
        let lassoBounds = boundingRect(for: lassoPoints).insetBy(dx: -tolerance, dy: -tolerance)
        let closed = isClosedShape(lassoPoints)

        return Set(strokes.compactMap { stroke in
            guard stroke.bounds.insetBy(dx: -tolerance, dy: -tolerance).intersects(lassoBounds) else {
                return nil
            }
            if lassoTouches(stroke, lassoPoints: lassoPoints, tolerance: tolerance) {
                return stroke.id
            }
            if closed, stroke.points.contains(where: { pointInPolygon($0, polygon: lassoPoints) }) {
                return stroke.id
            }
            return nil
        })
    }

    private func lassoTouches(
        _ stroke: MenuInkStroke,
        lassoPoints: [CGPoint],
        tolerance: CGFloat
    ) -> Bool {
        lassoPoints.contains { stroke.contains($0, radius: tolerance) }
            || stroke.points.contains { lassoContains($0, lassoPoints: lassoPoints, tolerance: tolerance) }
    }

    private func lassoContains(_ point: CGPoint, lassoPoints: [CGPoint], tolerance: CGFloat) -> Bool {
        guard let first = lassoPoints.first else { return false }
        if lassoPoints.count == 1 {
            return distance(point, to: first) <= tolerance
        }
        for index in 1..<lassoPoints.count {
            if distance(point, toSegmentFrom: lassoPoints[index - 1], to: lassoPoints[index]) <= tolerance {
                return true
            }
        }
        return false
    }

    private func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return point }
        return CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }
}

private enum MenuInkTool: String, CaseIterable, Identifiable {
    case pen
    case eraser
    case lasso

    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .eraser: "Erase"
        case .lasso: "Select"
        }
    }

    var icon: IconSource {
        switch self {
        case .pen: .builtIn(name: "pen", fallbackSymbol: "pencil.tip")
        case .eraser: .builtIn(name: "eraser", fallbackSymbol: "eraser")
        case .lasso: .builtIn(name: "lasso", fallbackSymbol: "lasso")
        }
    }

    static let eraserRadius: CGFloat = 15
}

private struct MenuInkStroke: Identifiable, Equatable {
    let id: UUID
    var points: [CGPoint]
    var width: CGFloat
    var color: Color

    init(
        id: UUID = UUID(),
        points: [CGPoint],
        width: CGFloat = 2.8,
        color: Color = Color(hex: "#2b2723").opacity(0.9)
    ) {
        self.id = id
        self.points = points
        self.width = width
        self.color = color
    }

    var bounds: CGRect {
        boundingRect(for: points).insetBy(dx: -width, dy: -width)
    }

    func contains(_ point: CGPoint, radius: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        let effectiveRadius = radius + width / 2
        if points.count == 1 {
            return distance(point, to: first) <= effectiveRadius
        }

        for index in 1..<points.count {
            if distance(point, toSegmentFrom: points[index - 1], to: points[index]) <= effectiveRadius {
                return true
            }
        }
        return false
    }
}

private struct MenuInkDrawingLayer: View {
    let strokes: [MenuInkStroke]
    let selectedStrokeIDs: Set<UUID>
    let activePoints: [CGPoint]
    let activeTool: MenuInkTool?
    let eraserLocation: CGPoint?

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                let path = menuInkPath(for: stroke.points)
                if selectedStrokeIDs.contains(stroke.id) {
                    context.stroke(
                        path,
                        with: .color(Color.blue.opacity(0.34)),
                        style: StrokeStyle(lineWidth: stroke.width + 7, lineCap: .round, lineJoin: .round)
                    )
                }
                context.stroke(
                    path,
                    with: .color(stroke.color),
                    style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                )
            }

            if let activeTool, activePoints.count > 1 {
                let activePath = menuInkPath(for: activePoints)
                switch activeTool {
                case .pen:
                    context.stroke(
                        activePath,
                        with: .color(Color(hex: "#2b2723").opacity(0.82)),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                    )
                case .eraser:
                    context.stroke(
                        activePath,
                        with: .color(Color(hex: "#2b2723").opacity(0.18)),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round, dash: [5, 4])
                    )
                case .lasso:
                    context.stroke(
                        activePath,
                        with: .color(Color.blue.opacity(0.74)),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [7, 5])
                    )
                    if isClosedShape(activePoints) {
                        context.fill(activePath, with: .color(Color.blue.opacity(0.055)))
                    }
                }
            }

            if let eraserLocation {
                let radius = MenuInkTool.eraserRadius
                let rect = CGRect(
                    x: eraserLocation.x - radius,
                    y: eraserLocation.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color(hex: "#2b2723").opacity(0.42)),
                    lineWidth: 1.1
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: "#2b2723").opacity(0.045)))
            }
        }
    }
}

private struct MenuInkSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private func menuInkPath(for points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)

    guard points.count > 2 else {
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    for index in 1..<points.count {
        let previous = points[index - 1]
        let current = points[index]
        let midpoint = CGPoint(
            x: (previous.x + current.x) / 2,
            y: (previous.y + current.y) / 2
        )
        path.addQuadCurve(to: midpoint, control: previous)
    }

    if let last = points.last {
        path.addLine(to: last)
    }
    return path
}

private func boundingRect(for points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .null }
    var minX = first.x
    var minY = first.y
    var maxX = first.x
    var maxY = first.y

    for point in points.dropFirst() {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }

    return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
}

private func pathLength(_ points: [CGPoint]) -> CGFloat {
    guard points.count > 1 else { return 0 }
    var length: CGFloat = 0
    for index in 1..<points.count {
        length += distance(points[index - 1], to: points[index])
    }
    return length
}

private func isClosedShape(_ points: [CGPoint]) -> Bool {
    guard let first = points.first, let last = points.last, points.count > 8 else { return false }
    let box = boundingRect(for: points)
    let threshold = max(14, min(box.width, box.height) * 0.28)
    return distance(first, to: last) <= threshold
}

private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1

    for i in polygon.indices {
        let pi = polygon[i]
        let pj = polygon[j]
        let crosses = (pi.y > point.y) != (pj.y > point.y)
        if crosses {
            let x = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
            if point.x < x {
                inside.toggle()
            }
        }
        j = i
    }

    return inside
}

private func distance(_ a: CGPoint, to b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > .ulpOfOne else {
        return distance(point, to: start)
    }

    let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
    let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
    return distance(point, to: projection)
}
