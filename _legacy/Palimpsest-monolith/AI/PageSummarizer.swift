import Foundation
import FoundationModels

/// Structured output for the on-device summarizer, using `@Generable` for
/// type-safe results instead of parsing free-form text.
@Generable
struct PageSummary {
    @Guide(description: "A concise one- or two-sentence summary of the page's content")
    var summary: String

    @Guide(description: "Three to six short topical tags for this page", .count(3...6))
    var tags: [String]
}

enum SummarizerError: Error {
    case unavailable(String)
}

/// Wraps the Foundation Models framework's on-device ~3B model. It's
/// excellent at shaping text it's given (summarizing, tagging) and weak on
/// world knowledge or long documents — set feature expectations accordingly.
/// Requires an Apple-Intelligence-capable device; every other feature in the
/// app works without it.
@MainActor
final class PageSummarizer: ObservableObject {
    @Published private(set) var isAvailable: Bool
    @Published private(set) var unavailableReason: String?

    init() {
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            unavailableReason = nil
        case .unavailable(let reason):
            isAvailable = false
            unavailableReason = String(describing: reason)
        }
    }

    func summarize(recognizedPageText: String) async throws -> PageSummary {
        guard isAvailable else {
            throw SummarizerError.unavailable(unavailableReason ?? "The on-device model isn't available on this device.")
        }
        guard !recognizedPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PageSummary(summary: "This page doesn't have any recognized handwriting yet.", tags: [])
        }

        let session = LanguageModelSession(instructions: """
            You summarize a student's handwritten notes. Be concise and \
            factual, and never invent details that aren't present in the \
            provided text.
            """)
        let response = try await session.respond(
            to: "Summarize and tag these recognized notes:\n\n\(recognizedPageText)",
            generating: PageSummary.self
        )
        return response.content
    }
}
