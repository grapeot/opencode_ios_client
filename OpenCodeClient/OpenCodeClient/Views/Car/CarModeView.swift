import SwiftUI
import os
import VoiceFlowKit

struct CarModeView: View {
    @Bindable var state: AppState
    @State private var microphone = VoiceFlowMicrophone()
    @State private var speechSession: VoiceFlowSession?
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var audioLevelTask: Task<Void, Never>?
    @State private var audioLevel: Float = 0
    @State private var isStartingRecording = false
    @State private var speechFinalizationID: UUID?
    @State private var showNewSessionConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    private var displayPhase: CarModePhase {
        if ProcessInfo.processInfo.arguments.contains("UITEST_CAR_MODE_FIXTURE") {
            return .idle
        }
        return state.carPhase
    }

    private var statusText: String {
        switch displayPhase {
        case .idle: return L10n.t(.carReady)
        case .recording: return L10n.t(.carListening)
        case .finalizing: return L10n.t(.carFinalizing)
        case .waitingReply: return L10n.t(.carWorking)
        case .speaking: return L10n.t(.carSpeaking)
        case .awaitingConfirmation: return L10n.t(.carNeedsConfirmation)
        case .failed: return L10n.t(.carFailed)
        }
    }

    private var primaryLabel: String {
        switch displayPhase {
        case .recording: return L10n.t(.carStopAndSend)
        case .finalizing: return L10n.t(.commonCancel)
        case .waitingReply: return L10n.t(.carStopResponse)
        case .speaking: return L10n.t(.carStopSpeaking)
        case .awaitingConfirmation: return L10n.t(.carSpeakConfirmation)
        case .failed: return L10n.t(.commonRetry)
        case .idle: return L10n.t(.carStartSpeaking)
        }
    }

    private var primaryIcon: String {
        switch displayPhase {
        case .recording: return "stop.fill"
        case .finalizing, .waitingReply, .speaking: return "xmark"
        case .awaitingConfirmation: return "mic.fill"
        case .failed: return "arrow.clockwise"
        case .idle: return "mic.fill"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), DesignColors.Brand.primary.opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    statusRail
                    Spacer(minLength: DesignSpacing.xl)
                    responseArea
                    Spacer(minLength: DesignSpacing.xl)
                    primaryControl
                    confirmationControls
                }
                .padding(.horizontal, DesignSpacing.xxl)
                .padding(.bottom, DesignSpacing.xxl)
            }
            .navigationTitle(L10n.t(.carTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewSessionConfirmation = true
                    } label: {
                        Image(systemName: "plus.message")
                    }
                    .accessibilityLabel(L10n.t(.carNewSession))
                    .accessibilityIdentifier("car-new-session")
                }
            }
            .confirmationDialog(L10n.t(.carNewSessionPrompt), isPresented: $showNewSessionConfirmation) {
                Button(L10n.t(.carNewSession), role: .destructive) {
                    Task { await state.startNewCarSession() }
                }
                Button(L10n.t(.commonCancel), role: .cancel) {}
            }
        }
        .accessibilityIdentifier("car-mode-root")
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await stopForBackground() }
        }
        .onDisappear {
            Task { await stopForBackground() }
        }
    }

    private var statusRail: some View {
        HStack(spacing: DesignSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText.uppercased())
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let sessionID = state.currentCarSessionID {
                Text(String(sessionID.suffix(6)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, DesignSpacing.sm)
        .accessibilityIdentifier("car-status")
    }

    private var responseArea: some View {
        VStack(spacing: DesignSpacing.md) {
            if let response = state.carLastResponse {
                Text(response.speech)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("car-last-response")
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(DesignColors.Brand.primary)
                Text(L10n.t(.carEmptyPrompt))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }

            if !state.carLastTranscript.isEmpty {
                Text("“\(state.carLastTranscript)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("car-last-transcript")
            }

            if let error = state.carError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(DesignColors.Semantic.error)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("car-error")
            }
        }
        .frame(maxWidth: 620)
    }

    private var primaryControl: some View {
        Button {
            Task { await handlePrimaryAction() }
        } label: {
            ZStack {
                Circle()
                    .fill(primaryColor.gradient)
                    .shadow(color: primaryColor.opacity(0.28), radius: 24, y: 10)
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
                    .padding(7)
                VStack(spacing: DesignSpacing.sm) {
                    Image(systemName: primaryIcon)
                        .font(.system(size: 42, weight: .semibold))
                    Text(primaryLabel)
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
            .frame(width: 190, height: 190)
            .scaleEffect(displayPhase == .recording ? 1 + CGFloat(min(audioLevel, 0.18)) : 1)
            .animation(.easeOut(duration: 0.12), value: audioLevel)
        }
        .buttonStyle(.plain)
        .disabled(isStartingRecording)
        .accessibilityIdentifier("car-primary-action")
        .accessibilityLabel(primaryLabel)
    }

    @ViewBuilder
    private var confirmationControls: some View {
        if displayPhase == .awaitingConfirmation {
            HStack(spacing: DesignSpacing.md) {
                Button(L10n.t(.commonOk)) {
                    Task { await state.submitCarTurn(L10n.t(.carConfirmUtterance)) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("car-confirm")

                Button(L10n.t(.commonCancel)) {
                    Task { await state.submitCarTurn(L10n.t(.carCancelUtterance)) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("car-decline")
            }
            .padding(.top, DesignSpacing.lg)
        } else {
            Color.clear.frame(height: 52)
        }
    }

    private var statusColor: Color {
        switch displayPhase {
        case .recording: return DesignColors.Semantic.error
        case .finalizing, .waitingReply, .speaking: return DesignColors.Brand.gold
        case .failed: return DesignColors.Semantic.error
        case .awaitingConfirmation: return DesignColors.Semantic.warning
        case .idle: return DesignColors.Semantic.success
        }
    }

    private var primaryColor: Color {
        switch displayPhase {
        case .recording, .finalizing, .waitingReply, .speaking: return DesignColors.Semantic.error
        case .failed: return DesignColors.Semantic.warning
        default: return DesignColors.Brand.primary
        }
    }

    private func handlePrimaryAction() async {
        switch displayPhase {
        case .recording:
            await stopRecordingAndSubmit()
        case .finalizing, .waitingReply, .speaking:
            speechFinalizationID = nil
            await state.cancelCarInteraction()
        case .failed:
            await state.submitCarTurn(state.carLastTranscript)
        case .idle, .awaitingConfirmation:
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !isStartingRecording else { return }
        let token = state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            state.carError = L10n.t(.chatSpeechTokenMissing)
            state.carPhase = .failed
            return
        }
        guard state.aiBuilderConnectionOK else {
            state.carError = L10n.t(.chatSpeechNotPassed)
            state.carPhase = .failed
            return
        }
        guard await ChatTabView.requestMicrophonePermissionForRecording() else {
            state.carError = L10n.t(.chatMicrophoneDenied)
            state.carPhase = .failed
            return
        }

        isStartingRecording = true
        speechFinalizationID = nil
        state.carSpeechOutput.stop()
        microphone = VoiceFlowMicrophone()
        do {
            let session = try await state.startRealtimeSpeechSession()
            speechSession = session
            try await microphone.start { chunk in
                Task { await session.sendAudioChunk(chunk) }
            }
            state.carError = nil
            state.carPhase = .recording
            startHeartbeat(for: session)
            startAudioLevelConsumer()
        } catch {
            speechSession = nil
            state.carError = error.localizedDescription
            state.carPhase = .failed
        }
        isStartingRecording = false
    }

    private func stopRecordingAndSubmit() async {
        stopHeartbeat()
        stopAudioLevelConsumer()
        _ = try? await microphone.stop()
        state.carPhase = .finalizing
        let finalizationID = UUID()
        speechFinalizationID = finalizationID
        guard let session = speechSession else {
            speechFinalizationID = nil
            state.carError = L10n.t(.carTranscriptionFailed)
            state.carPhase = .failed
            return
        }
        speechSession = nil

        do {
            let transcript = try await session.commitAndStop()
            await terminate(session)
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { throw CarModeError.invalidResponse }
            guard speechFinalizationID == finalizationID else { return }
            speechFinalizationID = nil
            await state.submitCarTurn(cleaned)
        } catch {
            await terminate(session)
            guard speechFinalizationID == finalizationID else { return }
            speechFinalizationID = nil
            state.carError = error.localizedDescription
            state.carPhase = .failed
        }
    }

    private func stopForBackground() async {
        speechFinalizationID = nil
        stopHeartbeat()
        stopAudioLevelConsumer()
        _ = try? await microphone.stop()
        if let session = speechSession {
            speechSession = nil
            await terminate(session)
        }
        await state.cancelCarInteraction()
    }

    private func terminate(_ session: VoiceFlowSession) async {
        do {
            if let preserved = try await session.abortPreservingAudio() {
                state.discardPreservedAudio(preserved)
            }
        } catch {
            AppState.logger.error("Car speech session termination failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startHeartbeat(for session: VoiceFlowSession) {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ChatTabView.speechHeartbeatIntervalSeconds))
                guard !Task.isCancelled else { return }
                await session.ping()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func startAudioLevelConsumer() {
        audioLevelTask?.cancel()
        let levels = microphone.audioLevel
        audioLevelTask = Task {
            for await level in levels {
                guard !Task.isCancelled else { return }
                audioLevel = level
            }
        }
    }

    private func stopAudioLevelConsumer() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        audioLevel = 0
    }
}
