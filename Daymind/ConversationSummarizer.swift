//
//  ConversationSummarizer.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import Foundation
import FoundationModels

enum ConversationSummarizerError: LocalizedError {
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            reason
        }
    }
}

final class ConversationSummarizer {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        model.availability == .available
    }

    var availabilityMessage: String {
        switch model.availability {
        case .available:
            "Apple Intelligence is ready."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is off. Turn it on in Settings to generate summaries and key details."
        case .unavailable(.deviceNotEligible):
            "This device does not support Apple Intelligence summaries."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still preparing the on-device model."
        @unknown default:
            "Apple Intelligence is unavailable."
        }
    }

    func summarize(transcriptDelta: String, currentSummary: String) async throws -> ConversationSummary {
        guard isAvailable else {
            throw ConversationSummarizerError.modelUnavailable(availabilityMessage)
        }

        let session = LanguageModelSession(model: model) {
            """
            You summarize live conversations for the person recording them.
            Keep the result useful, factual, and compact.
            Do not invent names, dates, decisions, or action items.
            Prefer concrete key details over generic observations.
            The transcript may contain speaker labels such as [Speaker A] and [Speaker B].
            When speaker labels are present, attribute statements and insights to the correct speaker.
            Use "Speaker A" and "Speaker B" consistently in the summary and key details.
            """
        }

        let prompt = """
        Existing summary:
        \(currentSummary.isEmpty ? "No summary yet." : currentSummary)

        New transcript text:
        \(transcriptDelta)

        Return an updated summary and up to 6 key insights or key details.
        """

        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0.1,
            maximumResponseTokens: 500
        )

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedConversationSummary.self,
            options: options
        )

        return response.content.conversationSummary
    }
}
