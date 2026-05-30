import SwiftUI
import os
import os.lock
import VoiceFlowKit

/// Mic-button voice input for the chat composer. Holds the speech
/// session, microphone, heartbeat task, and event consumer task; calls
/// into `AppState.startRealtimeSpeechSession()` to obtain a session
/// from `VoiceFlowKit`. UI states (`isRecording`, `isTranscribing`,
/// `isStartingRecording`, `speechError`, `speechRecoveryActive`) and
/// the session-bearing `@State` fields live on `ChatTabView` itself —
/// SwiftUI requires `@State` on the containing struct — and this
/// extension hosts the lifecycle methods.
///
/// The chat composer intentionally suppresses mid-recording
/// `.partialTranscript` events: OpenCode's UX shows transcript text
/// only after stop. VoiceFlow's recorder shows live partials; see
/// `AppState+LiveSession.swift` in the VoiceFlowKit repo for that flow.

/// Thread-safe buffer for the latest partial transcript. Used to recover
/// a salvageable string when `commitAndStop` fails after partials
/// already streamed in.
final class SpeechPartialTranscriptBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: "")

    nonisolated func update(_ newValue: String) {
        storage.withLock { $0 = newValue }
    }

    nonisolated func current() -> String {
        storage.withLock { $0 }
    }
}

extension ChatTabView {
    static let speechHeartbeatIntervalSeconds: UInt64 = 12

    static func mergedSpeechInput(prefix: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return cleanedTranscript }
        return prefix + " " + cleanedTranscript
    }

    static func speechFailureInput(prefix: String, lastPartialTranscript: String) -> String {
        mergedSpeechInput(prefix: prefix, transcript: lastPartialTranscript)
    }

    func startSpeechHeartbeat(for session: VoiceFlowSession) {
        speechHeartbeatTask?.cancel()
        speechHeartbeatTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.speechHeartbeatIntervalSeconds))
                } catch {
                    return
                }
                await session.ping()
            }
        }
    }

    func stopSpeechHeartbeat() {
        speechHeartbeatTask?.cancel()
        speechHeartbeatTask = nil
    }

    /// Drain `session.events` so the UI sees phase transitions and recovery
    /// state mid-recording. Otherwise a stream blip is invisible until the
    /// user hits stop and `commitAndStop` either succeeds late or fails.
    func startSpeechEventConsumer(for session: VoiceFlowSession) {
        speechEventTask?.cancel()
        speechEventTask = Task {
            let events = await session.events
            for await event in events {
                guard !Task.isCancelled else { return }
                switch event {
                case .recoveryStarted:
                    await MainActor.run { speechRecoveryActive = true }
                case .recoveryFailed(let message):
                    Self.logger.error("[SpeechProfile] realtime recovery failed message=\(message, privacy: .public)")
                    await MainActor.run {
                        speechRecoveryActive = false
                        speechError = L10n.t(.chatSpeechStreamDisconnected)
                    }
                case .phaseChanged(let phase):
                    if phase == .connected, speechRecoveryActive {
                        await MainActor.run { speechRecoveryActive = false }
                    }
                case .partialTranscript:
                    // Mid-recording partial transcripts are intentionally
                    // suppressed in OpenCode's chat composer — the user only
                    // sees text after stop. (See VoiceFlow's recording flow
                    // for the opposite UX.)
                    continue
                }
            }
        }
    }

    func stopSpeechEventConsumer() {
        speechEventTask?.cancel()
        speechEventTask = nil
        speechRecoveryActive = false
    }

    func toggleRecording() async {
        if isRecording {
            stopSpeechHeartbeat()
            stopSpeechEventConsumer()
            let stopStart = ProcessInfo.processInfo.systemUptime
            _ = try? await microphone.stop()
            isRecording = false
            Self.logger.notice("[SpeechProfile] realtime capture stopped ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - stopStart) * 1000)), privacy: .public)")

            guard let session = speechSession else {
                Self.logger.error("[SpeechProfile] realtime stop failed: missing session")
                return
            }

            isTranscribing = true
            defer {
                if speechSession === session {
                    speechSession = nil
                    isTranscribing = false
                }
            }
            let prefix = recordingInputPrefix
            let partialTranscriptBuffer = SpeechPartialTranscriptBuffer()
            let transcribeStart = ProcessInfo.processInfo.systemUptime
            do {
                let transcript = try await session.commitAndStop { partial in
                    partialTranscriptBuffer.update(partial)
                    Task { @MainActor in
                        inputText = Self.mergedSpeechInput(prefix: prefix, transcript: partial)
                    }
                }
                let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard speechSession === session else { return }
                Self.logger.notice("[SpeechProfile] chat realtime transcribe done ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - transcribeStart) * 1000)), privacy: .public) chars=\(cleaned.count, privacy: .public)")
                inputText = Self.mergedSpeechInput(prefix: prefix, transcript: cleaned)
                clearPreservedSpeechAudio()
            } catch {
                await session.cancel()
                guard speechSession === session else { return }
                Self.logger.error("[SpeechProfile] chat realtime transcribe failed ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - transcribeStart) * 1000)), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                inputText = Self.speechFailureInput(prefix: prefix, lastPartialTranscript: partialTranscriptBuffer.current())
                speechError = error.localizedDescription
            }
        } else {
            guard !isStartingRecording else { return }
            let token = state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty {
                speechError = L10n.t(.chatSpeechTokenMissing)
                return
            }
            if state.isTestingAIBuilderConnection {
                speechError = L10n.t(.chatSpeechTesting)
                return
            }
            guard state.aiBuilderConnectionOK else {
                speechError = L10n.t(.chatSpeechNotPassed)
                return
            }

            let permissionStart = ProcessInfo.processInfo.systemUptime
            let allowed = await microphone.requestPermission()
            Self.logger.notice("[SpeechProfile] microphone permission allowed=\(allowed, privacy: .public) ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - permissionStart) * 1000)), privacy: .public)")
            guard allowed else {
                speechError = L10n.t(.chatMicrophoneDenied)
                return
            }
            isStartingRecording = true
            let startRecordingStart = ProcessInfo.processInfo.systemUptime
            do {
                clearPreservedSpeechAudio()
                let session = try await state.startRealtimeSpeechSession()
                recordingInputPrefix = inputText
                speechSession = session
                startSpeechEventConsumer(for: session)

                try await microphone.start { chunk in
                    Task {
                        await session.sendAudioChunk(chunk)
                    }
                }
                isRecording = true
                isStartingRecording = false
                startSpeechHeartbeat(for: session)
                Self.logger.notice("[SpeechProfile] realtime capture started ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - startRecordingStart) * 1000)), privacy: .public)")
            } catch {
                _ = try? await microphone.stop()
                stopSpeechHeartbeat()
                stopSpeechEventConsumer()
                isStartingRecording = false
                if let speechSession {
                    await speechSession.cancel()
                }
                speechSession = nil
                Self.logger.error("[SpeechProfile] realtime capture start failed error=\(error.localizedDescription, privacy: .public)")
                speechError = error.localizedDescription
            }
        }
    }

    func abortSpeechRecognition() async {
        stopSpeechHeartbeat()
        stopSpeechEventConsumer()
        _ = try? await microphone.stop()

        let session = speechSession
        let prefix = recordingInputPrefix
        speechSession = nil
        isRecording = false
        isTranscribing = false
        isStartingRecording = false

        guard let session else { return }
        do {
            if let preserved = try await session.abortPreservingAudio() {
                clearPreservedSpeechAudio()
                preservedSpeechInputPrefix = prefix
                preservedSpeechAudio = preserved
                Self.logger.notice("[SpeechProfile] realtime speech aborted with preserved bytes=\(preserved.byteCount, privacy: .public)")
            }
        } catch {
            Self.logger.error("[SpeechProfile] realtime speech abort failed error=\(error.localizedDescription, privacy: .public)")
            speechError = error.localizedDescription
        }
    }

    func retryPreservedSpeechAudio() async {
        guard let preserved = preservedSpeechAudio else { return }
        isRetryingSpeech = true
        defer { isRetryingSpeech = false }

        let prefix = preservedSpeechInputPrefix
        do {
            let transcript = try await state.transcribePreservedAudio(preserved) { partial in
                Task { @MainActor in
                    inputText = Self.mergedSpeechInput(prefix: prefix, transcript: partial)
                }
            }
            inputText = Self.mergedSpeechInput(prefix: prefix, transcript: transcript)
            clearPreservedSpeechAudio()
        } catch {
            Self.logger.error("[SpeechProfile] preserved speech retry failed error=\(error.localizedDescription, privacy: .public)")
            speechError = error.localizedDescription
        }
    }

    func clearPreservedSpeechAudio() {
        if let preservedSpeechAudio {
            state.discardPreservedAudio(preservedSpeechAudio)
        }
        preservedSpeechAudio = nil
        preservedSpeechInputPrefix = ""
    }
}
