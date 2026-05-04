//
//  ContentView.swift
//  Daymind
//
//  Created by Gentian Barileva on 4.5.26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = ConversationViewModel()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            StatusHeader(viewModel: viewModel)
                            RecordingControl(viewModel: viewModel)
                            SummarySection(viewModel: viewModel)
                            KeyInsightsSection(insights: viewModel.keyInsights)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                    }

                    LiveTranscriptView(transcript: viewModel.transcript)
                        .frame(height: max(220, geometry.size.height * 0.33))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Daymind")
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.updateScenePhase(newPhase)
        }
    }
}

private struct StatusHeader: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.secondary)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                Text(viewModel.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(viewModel.modelStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingControl: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        HStack {
            Spacer()
            Button {
                viewModel.toggleRecording()
            } label: {
                Label(
                    viewModel.isRecording ? "Stop" : "Start",
                    systemImage: viewModel.isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.headline)
                .frame(minWidth: 116)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.isRecording ? .red : .blue)
            .accessibilityHint(viewModel.isRecording ? "Stops listening." : "Starts listening and transcription.")
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct SummarySection: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.headline)

                Spacer()

                if viewModel.isSummarizing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating summary")
                }
            }

            Text(viewModel.summary.isEmpty ? "A concise summary will appear as the conversation develops." : viewModel.summary)
                .font(.body)
                .foregroundStyle(viewModel.summary.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct KeyInsightsSection: View {
    let insights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Key Details", systemImage: "sparkles")
                .font(.headline)

            if insights.isEmpty {
                Text("Decisions, follow-ups, risks, and useful details will appear here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(insight)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LiveTranscriptView: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live Transcript", systemImage: "quote.bubble")
                    .font(.headline)
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcript.isEmpty ? "Transcript will appear here while Daymind listens." : transcript)
                        .font(.body)
                        .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("transcript-bottom")
                }
                .onChange(of: transcript) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("transcript-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ContentView()
}
