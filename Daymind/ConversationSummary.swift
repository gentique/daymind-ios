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
    @Guide(description: "A concise plain-language paragraph (2-4 sentences) summarizing the conversation so far. Cover only what was actually said.")
    var summary: String

    @Guide(
        description: "Concrete decisions, action items, risks, questions, dates, numbers, or named entities mentioned in the conversation. One short sentence each. Skip generic observations. Return an empty list if nothing concrete has been said yet.",
        .maximumCount(6)
    )
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
