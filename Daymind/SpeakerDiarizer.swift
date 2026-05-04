//
//  SpeakerDiarizer.swift
//  Daymind
//
//  Attempts to separate two speakers using acoustic features extracted from
//  SFSpeechRecognitionMetadata: mean log-pitch, mean jitter, and speaking rate.
//  A simple k-means (k=2) clusters the chunks after each new one arrives.
//
//  Limitations:
//  - Granularity is one chunk per ~55-second recognition window, so this
//    identifies *blocks* of speech by speaker, not individual turns.
//  - Works best when speakers differ meaningfully in pitch or speaking pace.
//  - With very few chunks the clustering is unreliable; labels stabilize as
//    more data accumulates.
//

import Speech
import Foundation

// MARK: - Data model

struct SpeechChunk: Identifiable {
    let id = UUID()
    let text: String
    /// Mean log-pitch across all voiced frames in this chunk (ln of normalized freq).
    let meanPitch: Double
    /// Mean jitter across frames (% of fundamental frequency).
    let meanJitter: Double
    /// Words per minute for this chunk.
    let speakingRate: Double
    /// 0 = Speaker A, 1 = Speaker B, -1 = not yet clustered.
    var speakerIndex: Int = -1

    var speakerLabel: String {
        switch speakerIndex {
        case 0:  return "Speaker A"
        case 1:  return "Speaker B"
        default: return "Unknown"
        }
    }
}

// MARK: - Diarizer

final class SpeakerDiarizer {

    // Emitted after every new chunk is added and clustering runs.
    var onChunksUpdated: (([SpeechChunk]) -> Void)?

    private(set) var chunks: [SpeechChunk] = []

    // MARK: Public interface

    /// Call this whenever `SFSpeechRecognitionResult.isFinal == true`.
    func process(result: SFSpeechRecognitionResult) {
        guard result.isFinal else { return }

        guard
            let metadata = result.speechRecognitionMetadata,
            let voiceAnalytics = metadata.voiceAnalytics
        else { return }

        let pitchFrames  = voiceAnalytics.pitch.acousticFeatureValuePerFrame
        let jitterFrames = voiceAnalytics.jitter.acousticFeatureValuePerFrame

        guard !pitchFrames.isEmpty else { return }

        let meanPitch   = pitchFrames.mean
        let meanJitter  = jitterFrames.isEmpty ? 0 : jitterFrames.mean
        let speakRate   = metadata.speakingRate
        let text        = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return }

        let chunk = SpeechChunk(
            text: text,
            meanPitch: meanPitch,
            meanJitter: meanJitter,
            speakingRate: speakRate
        )
        chunks.append(chunk)
        recluster()
        onChunksUpdated?(chunks)
    }

    /// Formatted transcript with speaker labels prepended to each chunk.
    var labeledTranscript: String {
        chunks.map { "[\($0.speakerLabel)]: \($0.text)" }.joined(separator: "\n")
    }

    /// Drop all accumulated data (e.g. when a new recording starts).
    func reset() {
        chunks.removeAll()
    }

    // MARK: K-means clustering (k=2)

    private func recluster() {
        guard chunks.count >= 2 else {
            // Single chunk — assign to Speaker A by default.
            chunks[0].speakerIndex = 0
            return
        }

        // Build feature matrix [meanPitch, meanJitter, speakingRate].
        let raw: [[Double]] = chunks.map { [$0.meanPitch, $0.meanJitter, $0.speakingRate] }

        // Z-score normalise each dimension independently so no single
        // feature dominates due to scale differences.
        let normalised = normaliseColumns(raw)

        // Seed centroids: first chunk and last chunk.  Using the extremes
        // gives better separation than two random picks when data is sparse.
        var centroids: [[Double]] = [normalised.first!, normalised.last!]
        var assignments = Array(repeating: 0, count: normalised.count)

        for _ in 0..<100 {
            var changed = false
            // Assignment step
            for i in normalised.indices {
                let d0 = squaredDistance(normalised[i], centroids[0])
                let d1 = squaredDistance(normalised[i], centroids[1])
                let best = d0 <= d1 ? 0 : 1
                if best != assignments[i] { changed = true }
                assignments[i] = best
            }
            guard changed else { break }

            // Update step
            let dims = normalised[0].count
            for k in 0..<2 {
                let members = normalised.indices.filter { assignments[$0] == k }.map { normalised[$0] }
                guard !members.isEmpty else { continue }
                centroids[k] = (0..<dims).map { d in members.map { $0[d] }.mean }
            }
        }

        for i in chunks.indices {
            chunks[i].speakerIndex = assignments[i]
        }
    }

    // MARK: Math helpers

    private func normaliseColumns(_ matrix: [[Double]]) -> [[Double]] {
        guard let first = matrix.first else { return matrix }
        let dims = first.count
        var result = matrix

        for d in 0..<dims {
            let col = matrix.map { $0[d] }
            let mu  = col.mean
            let std = col.standardDeviation
            guard std > 1e-9 else { continue }
            for i in matrix.indices {
                result[i][d] = (matrix[i][d] - mu) / std
            }
        }
        return result
    }

    private func squaredDistance(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
    }
}

// MARK: - Array<Double> convenience

private extension Array where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let mu = mean
        let variance = map { ($0 - mu) * ($0 - mu) }.reduce(0, +) / Double(count)
        return sqrt(variance)
    }
}
