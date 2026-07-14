import SwiftUI
import os
import os.lock
import VoiceFlowKit
#if os(iOS) || os(visionOS)
@preconcurrency import AVFoundation
#endif

/// Mic-button voice input for the chat composer. VoiceFlow uses its
/// realtime session while FluidVoice retains the same microphone's PCM
/// chunks for one batch request after stop. UI states (`isRecording`, `isTranscribing`,
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

/// FluidVoice is batch-only, so its PCM chunks are retained until the user
/// stops recording. Storage is capped at exactly 300 seconds of PCM16/24 kHz
/// mono audio even if the stop timer fires between audio callbacks.
final class SpeechPCMBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Data())

    nonisolated func append(_ chunk: Data) {
        storage.withLock { data in
            let remaining = FluidVoiceWAV.maximumPCMByteCount - data.count
            guard remaining > 0 else { return }
            data.append(chunk.prefix(remaining))
        }
    }

    nonisolated func takeData() -> Data {
        storage.withLock { data in
            let captured = data
            data.removeAll(keepingCapacity: false)
            return captured
        }
    }

    nonisolated func clear() {
        storage.withLock { $0.removeAll(keepingCapacity: false) }
    }
}

extension ChatTabView {
    static let speechHeartbeatIntervalSeconds: UInt64 = 12
    static let fluidVoiceRecordingLimitSeconds: UInt64 = 300

    static func mergedSpeechInput(prefix: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return cleanedTranscript }
        return prefix + " " + cleanedTranscript
    }

    static func speechFailureInput(prefix: String, lastPartialTranscript: String) -> String {
        mergedSpeechInput(prefix: prefix, transcript: lastPartialTranscript)
    }

    static func requestMicrophonePermissionForRecording() async -> Bool {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
        #else
        return true
        #endif
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

    func startSpeechAudioLevelConsumer() {
        speechAudioLevelTask?.cancel()
        speechAudioLevel = 0
        let levels = microphone.audioLevel
        speechAudioLevelTask = Task {
            for await level in levels {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    speechAudioLevel = level
                }
            }
        }
    }

    func stopSpeechAudioLevelConsumer() {
        speechAudioLevelTask?.cancel()
        speechAudioLevelTask = nil
        speechAudioLevel = 0
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

    func terminateSpeechSession(_ session: VoiceFlowSession) async {
        do {
            if let preserved = try await session.abortPreservingAudio() {
                state.discardPreservedAudio(preserved)
            }
        } catch {
            Self.logger.error("[SpeechProfile] realtime session termination failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func removeTemporarySpeechFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func stopSpeechRecordingLimit() {
        speechRecordingLimitTask?.cancel()
        speechRecordingLimitTask = nil
    }

    func scheduleFluidVoiceRecordingLimit() {
        stopSpeechRecordingLimit()
        speechRecordingLimitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(Self.fluidVoiceRecordingLimitSeconds))
            } catch {
                return
            }
            guard isRecording, recordingVoiceProvider == .fluidVoice else { return }
            speechRecordingLimitTask = nil
            await toggleRecording()
        }
    }

    func beginFluidVoiceTranscription(pcmData: Data, prefix: String) throws {
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        do {
            try FluidVoiceWAV.write(pcmData: pcmData, to: wavURL)
        } catch {
            removeTemporarySpeechFile(wavURL)
            throw error
        }

        let operationID = UUID()
        speechTranscriptionID = operationID
        isTranscribing = true
        speechTranscriptionTask = Task { @MainActor in
            defer {
                removeTemporarySpeechFile(wavURL)
                if speechTranscriptionID == operationID {
                    speechTranscriptionID = nil
                    speechTranscriptionTask = nil
                    isTranscribing = false
                    recordingVoiceProvider = nil
                }
            }

            do {
                let transcript = try await state.transcribeWithFluidVoice(wavFileURL: wavURL)
                try Task.checkCancellation()
                guard speechTranscriptionID == operationID else { return }
                let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.notice("[SpeechProfile] FluidVoice batch transcribe done chars=\(cleaned.count, privacy: .public)")
                inputText = Self.mergedSpeechInput(prefix: prefix, transcript: cleaned)
            } catch is CancellationError {
                return
            } catch FluidVoiceClientError.cancelled {
                return
            } catch {
                guard speechTranscriptionID == operationID else { return }
                Self.logger.error("[SpeechProfile] FluidVoice batch transcribe failed")
                inputText = prefix
                speechError = error.localizedDescription
            }
        }
    }

    func stopSpeechForBackground() async {
        stopSpeechRecordingLimit()
        speechTranscriptionID = nil
        speechTranscriptionTask?.cancel()
        speechTranscriptionTask = nil
        stopSpeechHeartbeat()
        stopSpeechEventConsumer()
        stopSpeechAudioLevelConsumer()
        let microphoneFile = try? await microphone.stop()
        removeTemporarySpeechFile(microphoneFile)
        fluidVoicePCMBuffer.clear()

        let session = speechSession
        speechSession = nil
        recordingVoiceProvider = nil
        isRecording = false
        isTranscribing = false
        isStartingRecording = false

        if let session {
            await terminateSpeechSession(session)
        }
    }

    func toggleRecording() async {
        if isRecording {
            stopSpeechRecordingLimit()
            stopSpeechHeartbeat()
            stopSpeechEventConsumer()
            stopSpeechAudioLevelConsumer()
            let stopStart = ProcessInfo.processInfo.systemUptime
            let microphoneFile = try? await microphone.stop()
            removeTemporarySpeechFile(microphoneFile)
            isRecording = false
            Self.logger.notice("[SpeechProfile] speech capture stopped ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - stopStart) * 1000)), privacy: .public)")

            let prefix = recordingInputPrefix
            if recordingVoiceProvider == .fluidVoice {
                let pcmData = fluidVoicePCMBuffer.takeData()
                do {
                    try beginFluidVoiceTranscription(pcmData: pcmData, prefix: prefix)
                } catch {
                    recordingVoiceProvider = nil
                    isTranscribing = false
                    inputText = prefix
                    speechError = error.localizedDescription
                }
                return
            }

            guard let session = speechSession else {
                Self.logger.error("[SpeechProfile] realtime stop failed: missing session")
                recordingVoiceProvider = nil
                return
            }

            isTranscribing = true
            defer {
                if speechSession === session {
                    speechSession = nil
                    isTranscribing = false
                    recordingVoiceProvider = nil
                }
            }
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
                await terminateSpeechSession(session)
            } catch {
                await terminateSpeechSession(session)
                guard speechSession === session else { return }
                Self.logger.error("[SpeechProfile] chat realtime transcribe failed ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - transcribeStart) * 1000)), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                inputText = Self.speechFailureInput(prefix: prefix, lastPartialTranscript: partialTranscriptBuffer.current())
                speechError = error.localizedDescription
            }
        } else {
            guard !isStartingRecording else { return }
            // VoiceFlowMicrophone.audioLevel is tied to the microphone instance's
            // AsyncStream continuation. Recreate it per capture so repeated
            // start/stop cycles keep publishing real levels for the waveform.
            microphone = VoiceFlowMicrophone()
            fluidVoicePCMBuffer = SpeechPCMBuffer()
            let provider = state.voiceTranscriptionProvider

            switch provider {
            case .voiceFlow:
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
            case .fluidVoice:
                do {
                    try state.normalizeFluidVoiceBaseURL()
                } catch {
                    speechError = error.localizedDescription
                    return
                }
            }

            let permissionStart = ProcessInfo.processInfo.systemUptime
            let allowed = await Self.requestMicrophonePermissionForRecording()
            Self.logger.notice("[SpeechProfile] microphone permission allowed=\(allowed, privacy: .public) ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - permissionStart) * 1000)), privacy: .public)")
            guard allowed else {
                speechError = L10n.t(.chatMicrophoneDenied)
                return
            }
            isStartingRecording = true
            let startRecordingStart = ProcessInfo.processInfo.systemUptime
            do {
                clearPreservedSpeechAudio()
                recordingInputPrefix = inputText
                recordingVoiceProvider = provider
                startSpeechAudioLevelConsumer()

                switch provider {
                case .voiceFlow:
                    let session = try await state.startRealtimeSpeechSession()
                    speechSession = session
                    startSpeechEventConsumer(for: session)
                    try await microphone.start { chunk in
                        Task {
                            await session.sendAudioChunk(chunk)
                        }
                    }
                    startSpeechHeartbeat(for: session)
                case .fluidVoice:
                    let buffer = fluidVoicePCMBuffer
                    try await microphone.start { chunk in
                        buffer.append(chunk)
                    }
                }
                isRecording = true
                isStartingRecording = false
                if provider == .fluidVoice {
                    scheduleFluidVoiceRecordingLimit()
                }
                Self.logger.notice("[SpeechProfile] speech capture started provider=\(provider.rawValue, privacy: .public) ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - startRecordingStart) * 1000)), privacy: .public)")
            } catch {
                let microphoneFile = try? await microphone.stop()
                removeTemporarySpeechFile(microphoneFile)
                stopSpeechHeartbeat()
                stopSpeechEventConsumer()
                stopSpeechAudioLevelConsumer()
                stopSpeechRecordingLimit()
                fluidVoicePCMBuffer.clear()
                isStartingRecording = false
                if let speechSession {
                    await terminateSpeechSession(speechSession)
                }
                speechSession = nil
                recordingVoiceProvider = nil
                Self.logger.error("[SpeechProfile] speech capture start failed error=\(error.localizedDescription, privacy: .public)")
                speechError = error.localizedDescription
            }
        }
    }

    func abortSpeechRecognition() async {
        stopSpeechRecordingLimit()
        stopSpeechHeartbeat()
        stopSpeechEventConsumer()
        stopSpeechAudioLevelConsumer()
        let microphoneFile = try? await microphone.stop()
        removeTemporarySpeechFile(microphoneFile)

        if recordingVoiceProvider == .fluidVoice || speechTranscriptionTask != nil {
            speechTranscriptionID = nil
            speechTranscriptionTask?.cancel()
            speechTranscriptionTask = nil
            fluidVoicePCMBuffer.clear()
            recordingVoiceProvider = nil
            isRecording = false
            isTranscribing = false
            isStartingRecording = false
            return
        }

        let session = speechSession
        let prefix = recordingInputPrefix
        speechSession = nil
        recordingVoiceProvider = nil
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
