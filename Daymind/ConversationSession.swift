//
//  ConversationSession.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import Foundation

struct ConversationSession: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var transcript: String
    var summary: String
    var keyInsights: [String]

    var hasContent: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !keyInsights.isEmpty
    }

    static func draft(createdAt: Date = Date()) -> ConversationSession {
        ConversationSession(
            id: UUID(),
            title: fallbackTitle(for: createdAt),
            createdAt: createdAt,
            updatedAt: createdAt,
            transcript: "",
            summary: "",
            keyInsights: []
        )
    }

    mutating func update(transcript: String, summary: String, keyInsights: [String], at date: Date = Date()) {
        self.transcript = transcript
        self.summary = summary
        self.keyInsights = keyInsights
        updatedAt = date
        title = Self.title(for: transcript, createdAt: createdAt)
    }

    static func title(for transcript: String, createdAt: Date) -> String {
        let normalizedTranscript = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalizedTranscript.isEmpty else {
            return fallbackTitle(for: createdAt)
        }

        if normalizedTranscript.count <= 48 {
            return normalizedTranscript
        }

        let prefix = String(normalizedTranscript.prefix(45))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    static func fallbackTitle(for date: Date) -> String {
        "Session \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
