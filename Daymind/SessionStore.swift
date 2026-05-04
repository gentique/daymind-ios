//
//  SessionStore.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [ConversationSession] = []

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    deinit {
        saveTask?.cancel()
    }

    func session(withID id: UUID) -> ConversationSession? {
        sessions.first { $0.id == id }
    }

    func upsert(_ session: ConversationSession) {
        guard session.hasContent else { return }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }

        sortSessions()
        scheduleSave()
    }

    func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { index in
            sessions.indices.contains(index) ? sessions[index].id : nil
        }

        sessions.removeAll { idsToDelete.contains($0.id) }
        scheduleSave()
    }

    func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try JSONDecoder().decode([ConversationSession].self, from: data)
            sortSessions()
        } catch {
            sessions = []
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            self?.saveImmediately()
        }
    }

    private func save() {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // For this POC, keep the UI responsive even if local persistence fails.
        }
    }

    private func sortSessions() {
        sessions.sort { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    private static var defaultFileURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appendingPathComponent("Daymind", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }
}
