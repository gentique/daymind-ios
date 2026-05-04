//
//  ConversationViewModel.swift
//  Daymind
//
//  Created by Codex on 4.5.26.
//

import Combine
import SwiftUI

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isBackgrounded = false
    @Published var transcript = ""
    @Published var summary = ""
    @Published var keyInsights: [String] = []
    @Published var statusText = "Ready to listen."
    @Published var modelStatusText = ""
    @Published var isSummarizing = false

    private let transcriber = SpeechTranscriber()
    private let summarizer = ConversationSummarizer()
    private var pauseSummaryTask: Task<Void, Never>?
    private var periodicSummaryTask: Task<Void, Never>?
    private var activeSummaryTask: Task<Void, Never>?
    private var lastSummarizedTranscript = ""
    private var hasQueuedSummaryUpdate = false

    init() {
        modelStatusText = summarizer.availabilityMessage

        transcriber.onTranscriptChange = { [weak self] transcript in
            Task { @MainActor in
                self?.receiveTranscript(transcript)
            }
        }

        transcriber.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.statusText = status
            }
        }

        transcriber.onFailure = { [weak self] error in
            Task { @MainActor in
                self?.handleTranscriptionFailure(error)
            }
        }

        transcriber.onRecordingEnded = { [weak self] in
            Task { @MainActor in
                self?.handleRecordingEnded()
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording()
            }
        }
    }

    func startRecording() async {
        guard !isRecording else { return }

        modelStatusText = summarizer.availabilityMessage
        statusText = "Preparing microphone and speech recognition..."

        do {
            try await transcriber.start()
            isRecording = true
            statusText = "Listening on device."
            startPeriodicSummaryUpdates()
        } catch {
            isRecording = false
            statusText = error.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        pauseSummaryTask?.cancel()
        periodicSummaryTask?.cancel()
        periodicSummaryTask = nil
        transcriber.stop()
        requestSummaryUpdate(force: true)
    }

    func updateScenePhase(_ scenePhase: ScenePhase) {
        isBackgrounded = scenePhase == .background

        if isRecording {
            statusText = isBackgrounded ? "Listening in the background." : "Listening on device."
        }
    }

    private func receiveTranscript(_ newTranscript: String) {
        guard newTranscript != transcript else { return }
        transcript = newTranscript
        schedulePauseSummaryUpdate()
    }

    private func handleRecordingEnded() {
        isRecording = false
        pauseSummaryTask?.cancel()
        periodicSummaryTask?.cancel()
        periodicSummaryTask = nil
    }

    private func handleTranscriptionFailure(_ error: Error) {
        handleRecordingEnded()
        statusText = error.localizedDescription
        requestSummaryUpdate(force: true)
    }

    private func schedulePauseSummaryUpdate() {
        pauseSummaryTask?.cancel()
        pauseSummaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.requestSummaryUpdate(force: false)
        }
    }

    private func startPeriodicSummaryUpdates() {
        periodicSummaryTask?.cancel()
        periodicSummaryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.requestSummaryUpdate(force: false)
            }
        }
    }

    private func requestSummaryUpdate(force: Bool) {
        guard summarizer.isAvailable else {
            modelStatusText = summarizer.availabilityMessage
            return
        }

        let currentTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTranscript.isEmpty else { return }

        if !force, currentTranscript == lastSummarizedTranscript {
            return
        }

        guard activeSummaryTask == nil else {
            hasQueuedSummaryUpdate = true
            return
        }

        let transcriptDelta = delta(from: currentTranscript)
        guard !transcriptDelta.isEmpty else { return }

        let currentSummary = summary
        isSummarizing = true
        modelStatusText = "Updating key details on device..."

        activeSummaryTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.summarizer.summarize(
                    transcriptDelta: transcriptDelta,
                    currentSummary: currentSummary
                )
                self.applySummaryResult(result, summarizedTranscript: currentTranscript)
            } catch {
                self.finishSummaryUpdate(errorMessage: error.localizedDescription)
            }
        }
    }

    private func delta(from currentTranscript: String) -> String {
        if currentTranscript.hasPrefix(lastSummarizedTranscript) {
            return String(currentTranscript.dropFirst(lastSummarizedTranscript.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return currentTranscript
    }

    private func applySummaryResult(_ result: ConversationSummary, summarizedTranscript: String) {
        summary = result.summary
        keyInsights = Array(result.keyInsights.prefix(6))
        lastSummarizedTranscript = summarizedTranscript
        finishSummaryUpdate(errorMessage: nil)
    }

    private func finishSummaryUpdate(errorMessage: String?) {
        isSummarizing = false
        activeSummaryTask = nil
        modelStatusText = errorMessage ?? summarizer.availabilityMessage

        if hasQueuedSummaryUpdate {
            hasQueuedSummaryUpdate = false
            requestSummaryUpdate(force: false)
        }
    }
}
