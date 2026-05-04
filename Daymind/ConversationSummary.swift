//
//  ConversationSummary.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import Foundation
import FoundationModels

struct ConversationSummary: Equatable {
    var summary: String
    var keyInsights: [String]

    static let empty = ConversationSummary(summary: "", keyInsights: [])
}

@Generable
struct GeneratedConversationSummary {
    @Guide(description: "A concise, plain-language summary of the conversation so far.")
    var summary: String

    @Guide(description: "Important decisions, facts, risks, questions, or follow-up items mentioned in the conversation.")
    var keyInsights: [String]

    var conversationSummary: ConversationSummary {
        ConversationSummary(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            keyInsights: keyInsights
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}
