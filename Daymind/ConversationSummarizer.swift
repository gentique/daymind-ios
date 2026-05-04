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
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason
        case .generationFailed(let reason): reason
        }
    }
}

final class ConversationSummarizer {
    private let model = SystemLanguageModel.default

    private static let instructions = """
    You maintain a running summary of a live conversation for the person recording it.
    Always produce a complete, fresh summary and a fresh list of key details that reflect the entire conversation so far.
    Be factual. Never invent names, dates, decisions, or follow-ups that were not said.
    Key details must be concrete: decisions, action items, risks, questions, numbers, dates, or named entities. Skip generic observations.
    If nothing concrete has been said yet, return an empty list of key details.
    """

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

    func summarize(
        transcriptTail: String,
        previousSummary: String,
        previousKeyInsights: [String]
    ) async throws -> ConversationSummary {
        guard isAvailable else {
            throw ConversationSummarizerError.modelUnavailable(availabilityMessage)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)

        // Greedy sampling = deterministic structured extraction. Temperature is
        // meaningless with greedy, so we omit it. The token ceiling needs to be
        // generous enough to fit the JSON envelope plus a multi-sentence summary
        // and up to 6 insights — 500 truncated the array.
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: 1024
        )

        let priorInsightsBlock = previousKeyInsights.isEmpty
            ? "(none yet)"
            : previousKeyInsights.map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        Summary so far:
        \(previousSummary.isEmpty ? "(none yet)" : previousSummary)

        Key details so far:
        \(priorInsightsBlock)

        Most recent transcript excerpt (verbatim):
        \(transcriptTail)

        Produce a refreshed summary covering the full conversation, plus a refreshed list of up to 6 key details. Carry forward earlier details that still matter, drop any that no longer apply, and add new ones from the recent transcript.
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedConversationSummary.self,
                options: options
            )
            return response.content.conversationSummary
        } catch let error as LanguageModelSession.GenerationError {
            throw ConversationSummarizerError.generationFailed(Self.message(for: error))
        }
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "The conversation got too long for on-device summarization."
        case .guardrailViolation:
            "Apple Intelligence declined to summarize this content."
        case .unsupportedLanguageOrLocale:
            "This conversation language is not yet supported on device."
        case .decodingFailure:
            "Apple Intelligence returned an incomplete response. Trying again may help."
        case .rateLimited:
            "Too many summary requests in a row. Slowing down."
        case .assetsUnavailable:
            "Apple Intelligence assets are still loading."
        default:
            error.errorDescription ?? "Summarization failed."
        }
    }
}
