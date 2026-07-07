import SwiftUI

struct CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var editorModel: PageEditorModel
    @ObservedObject var toolbox: ToolboxModel
    var initialFocusCanvasPoint: CGPoint?
    var onHover: (CGPoint?) -> Void

    func makeUIView(context: Context) -> CanvasHostView {
        let view = CanvasHostView()
        view.editorModel = editorModel
        view.toolbox = toolbox
        view.onHover = onHover
        view.initialFocusCanvasPoint = initialFocusCanvasPoint
        return view
    }

    func updateUIView(_ uiView: CanvasHostView, context: Context) {
        if uiView.editorModel !== editorModel {
            uiView.editorModel = editorModel
        }
        if uiView.toolbox !== toolbox {
            uiView.toolbox = toolbox
        }
    }
}

/// A full page-editing surface: the transformable canvas plus the floating
/// toolbar, tool popup, and hover-preview cursor that sit on top of it.
struct PageCanvasView: View {
    @StateObject private var toolbox = ToolboxModel()
    @StateObject private var editorModel: PageEditorModel
    @StateObject private var summarizer = PageSummarizer()
    @State private var hoverLocation: CGPoint?
    @State private var summaryResult: PageSummary?
    @State private var summaryError: String?
    @State private var isSummarizing = false

    private let initialFocusCanvasPoint: CGPoint?
    private let repository: NotebookRepository

    init(page: Page, repository: NotebookRepository, focusOn canvasPoint: CGPoint? = nil) {
        _editorModel = StateObject(wrappedValue: PageEditorModel(page: page, repository: repository))
        initialFocusCanvasPoint = canvasPoint
        self.repository = repository
    }

    var body: some View {
        ZStack(alignment: .top) {
            CanvasRepresentable(editorModel: editorModel, toolbox: toolbox, initialFocusCanvasPoint: initialFocusCanvasPoint) { location in
                hoverLocation = location
            }
            .ignoresSafeArea()

            if let hoverLocation {
                Circle()
                    .strokeBorder(.primary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: toolbox.currentStyle.width + 10, height: toolbox.currentStyle.width + 10)
                    .position(hoverLocation)
                    .allowsHitTesting(false)
            }

            floatingToolbar
                .padding(.top, 12)

            if toolbox.isPopupPresented {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { toolbox.isPopupPresented = false }
                ToolPopupView(toolbox: toolbox)
            }
        }
        .sheet(isPresented: Binding(get: { summaryResult != nil }, set: { if !$0 { summaryResult = nil } })) {
            summarySheet
        }
        .alert("Summarize", isPresented: Binding(get: { summaryError != nil }, set: { if !$0 { summaryError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(summaryError ?? "")
        }
    }

    private var floatingToolbar: some View {
        HStack(spacing: 12) {
            ForEach(InkTool.allCases) { tool in
                Button {
                    toolbox.select(ToolStyle(tool: tool, color: toolbox.currentStyle.color, width: tool.defaultWidth, blendMode: tool.defaultBlendMode))
                } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 36, height: 36)
                        .background(toolbox.currentStyle.tool == tool ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                }
            }
            Divider().frame(height: 20)
            Button {
                toolbox.presentPopup(at: CGPoint(x: 200, y: 80))
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 36, height: 36)
            }
            Button {
                runSummarize()
            } label: {
                if isSummarizing {
                    ProgressView().frame(width: 36, height: 36)
                } else {
                    Image(systemName: "sparkles").frame(width: 36, height: 36)
                }
            }
            .disabled(isSummarizing)
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6)
        .buttonStyle(.plain)
    }

    private var summarySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(summaryResult?.summary ?? "")
                    .font(.body)
                if let tags = summaryResult?.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.tertiary, in: Capsule())
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Page Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func runSummarize() {
        isSummarizing = true
        let pageID = editorModel.page.id
        let repository = repository
        Task {
            defer { isSummarizing = false }
            let lines = (try? repository.recognizedTextLines(forPage: pageID)) ?? []
            let text = lines.map(\.text).joined(separator: "\n")
            do {
                summaryResult = try await summarizer.summarize(recognizedPageText: text)
            } catch let SummarizerError.unavailable(reason) {
                summaryError = reason
            } catch {
                summaryError = error.localizedDescription
            }
        }
    }
}
