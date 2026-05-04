//
//  ContentView.swift
//  Daymind
//
//  Created by Gentian Barileva on 4.5.26.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct ContentView: View {
    @StateObject private var sessionStore = SessionStore()
    @State private var navigationPath = NavigationPath()
    @State private var isPaywallPresented = false
    @State private var purchaseHasActiveEntitlement = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if sessionStore.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Sessions", systemImage: "waveform")
                    } description: {
                        Text("Start a new session to save transcripts, summaries, and key details locally.")
                    } actions: {
                        Button("New Session", systemImage: "plus") {
                            startNewSession()
                        }
                    }
                } else {
                    List {
                        ForEach(sessionStore.sessions) { session in
                            NavigationLink(value: SessionRoute.existing(session.id)) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete(perform: sessionStore.delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PurchaseStatusButton(
                        isPro: purchaseHasActiveEntitlement,
                        isPaywallPresented: $isPaywallPresented
                    )

                    Button {
                        startNewSession()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New session")
                }
            }
            .navigationDestination(for: SessionRoute.self) { route in
                switch route {
                case .new(let session):
                    SessionDetailView(session: session, isReadOnly: false)
                case .existing(let sessionID):
                    if let session = sessionStore.session(withID: sessionID) {
                        SessionDetailView(session: session, isReadOnly: true)
                    } else {
                        ContentUnavailableView("Session Not Found", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .environmentObject(sessionStore)
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView()
                .onPurchaseCompleted { customerInfo in
                    updatePurchaseState(with: customerInfo)
                    isPaywallPresented = false
                }
        }
        .task {
            await refreshPurchaseState()
        }
    }

    private func startNewSession() {
        navigationPath.append(SessionRoute.new(ConversationSession.draft()))
    }

    private func refreshPurchaseState() async {
        guard let customerInfo = try? await Purchases.shared.customerInfo() else { return }
        updatePurchaseState(with: customerInfo)
    }

    private func updatePurchaseState(with customerInfo: CustomerInfo) {
        purchaseHasActiveEntitlement = !customerInfo.entitlements.active.isEmpty
    }
}

private enum SessionRoute: Hashable {
    case new(ConversationSession)
    case existing(UUID)
}

private struct SessionRow: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var previewText: String {
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }

        let transcript = session.transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return transcript.isEmpty ? "No transcript saved." : transcript
    }
}

private struct PurchaseStatusButton: View {
    let isPro: Bool
    @Binding var isPaywallPresented: Bool

    var body: some View {
        if isPro {
            Text("PRO")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green, in: Capsule())
                .accessibilityLabel("Pro active")
        } else {
            Button {
                isPaywallPresented = true
            } label: {
                Image(systemName: "crown")
            }
            .accessibilityLabel("Show paywall")
        }
    }
}

private struct SessionDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = ConversationViewModel()
    @State private var session: ConversationSession

    let isReadOnly: Bool

    init(session: ConversationSession, isReadOnly: Bool) {
        _session = State(initialValue: session)
        self.isReadOnly = isReadOnly
    }

    var body: some View {
        Group {
            if isReadOnly {
                ReadOnlySessionView(session: session)
            } else {
                RecordingSessionView(viewModel: viewModel)
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.transcript) { _, _ in
            persistDraft()
        }
        .onChange(of: viewModel.summary) { _, _ in
            persistDraft()
        }
        .onChange(of: viewModel.keyInsights) { _, _ in
            persistDraft()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !isReadOnly else { return }

            viewModel.updateScenePhase(newPhase)

            if newPhase == .background {
                persistDraft()
                sessionStore.saveImmediately()
            }
        }
        .onDisappear {
            guard !isReadOnly else { return }

            if viewModel.isRecording {
                viewModel.stopRecording()
            }

            persistDraft()
            sessionStore.saveImmediately()
        }
    }

    private func persistDraft() {
        guard !isReadOnly else { return }

        session.update(
            transcript: viewModel.transcript,
            summary: viewModel.summary,
            keyInsights: viewModel.keyInsights
        )

        sessionStore.upsert(session)
    }
}

private struct RecordingSessionView: View {
    @ObservedObject var viewModel: ConversationViewModel

    var body: some View {
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
    }
}

private struct ReadOnlySessionView: View {
    let session: ConversationSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SessionMetadataHeader(session: session)
                SavedSummarySection(summary: session.summary)
                KeyInsightsSection(insights: session.keyInsights)
                SavedTranscriptSection(transcript: session.transcript)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct SessionMetadataHeader: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Saved Session", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            Text("Created \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Updated \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SavedSummarySection: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Summary", systemImage: "text.alignleft")
                .font(.headline)

            Text(summary.isEmpty ? "No summary was saved for this session." : summary)
                .font(.body)
                .foregroundStyle(summary.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SavedTranscriptSection: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transcript", systemImage: "quote.bubble")
                .font(.headline)

            Text(transcript.isEmpty ? "No transcript was saved for this session." : transcript)
                .font(.body)
                .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
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
