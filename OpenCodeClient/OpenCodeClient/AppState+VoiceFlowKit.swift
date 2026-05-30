import Foundation
import os
import VoiceFlowKit

/// VoiceFlowKit speech recognition integration. Wraps the kit's
/// `VoiceFlowClient` for OpenCode's three speech entry points:
/// one-shot transcription of an audio file, real-time WS sessions for
/// the chat composer's mic button, and the Settings-side connection
/// test against the AI Builder Space token.
///
/// All four methods are facade-only — host (`ChatTabView` /
/// `SettingsView`) never touches kit Internal types.
extension AppState {
    private func makeVoiceFlowClient() throws -> VoiceFlowClient {
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw VoiceFlowError.missingToken }
        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointString = base.isEmpty ? VoiceFlowConfig.defaultEndpoint.absoluteString : base
        let normalized = endpointString.hasPrefix("http://") || endpointString.hasPrefix("https://")
            ? endpointString
            : "https://\(endpointString)"
        guard let endpoint = URL(string: normalized) else {
            throw VoiceFlowError.invalidEndpoint
        }
        let promptText = aiBuilderCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = aiBuilderTerminology
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let config = VoiceFlowConfig(
            endpoint: endpoint,
            tokenProvider: { token },
            prompt: promptText.isEmpty ? nil : promptText,
            terms: terms
        )
        return VoiceFlowClient(config: config)
    }

    func transcribeAudio(audioFileURL: URL, onPartialTranscript: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        let fileName = audioFileURL.lastPathComponent.isEmpty ? "audio.m4a" : audioFileURL.lastPathComponent
        Self.logger.notice("[SpeechProfile] appState.transcribe begin file=\(fileName, privacy: .public)")
        do {
            let client = try makeVoiceFlowClient()
            let result = try await client.transcribe(audioFile: audioFileURL, onPartialTranscript: onPartialTranscript)
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.notice("[SpeechProfile] appState.transcribe done ms=\(elapsedMs, privacy: .public) textChars=\(result.text.count, privacy: .public) requestID=\(result.requestID, privacy: .public)")
            return result.text
        } catch {
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.error("[SpeechProfile] appState.transcribe failed ms=\(elapsedMs, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func startRealtimeSpeechSession() async throws -> VoiceFlowSession {
        let start = ProcessInfo.processInfo.systemUptime
        Self.logger.notice("[SpeechProfile] appState.realtime start begin")
        do {
            let client = try makeVoiceFlowClient()
            let session = try await client.startSession()
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.notice("[SpeechProfile] appState.realtime start done ms=\(elapsedMs, privacy: .public)")
            return session
        } catch {
            let elapsedMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.error("[SpeechProfile] appState.realtime start failed ms=\(elapsedMs, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func transcribePreservedAudio(
        _ preservedAudio: VoiceFlowPreservedAudio,
        onPartialTranscript: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let client = try makeVoiceFlowClient()
        let result = try await client.transcribe(preservedAudio: preservedAudio, onPartialTranscript: onPartialTranscript)
        return result.text
    }

    func discardPreservedAudio(_ preservedAudio: VoiceFlowPreservedAudio) {
        Task {
            do {
                let client = try makeVoiceFlowClient()
                await client.discardPreservedAudio(preservedAudio)
            } catch {
                Self.logger.error("[SpeechProfile] discard preserved audio failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func testAIBuilderConnection() async {
        guard !isTestingAIBuilderConnection else { return }
        isTestingAIBuilderConnection = true
        defer { isTestingAIBuilderConnection = false }

        aiBuilderConnectionError = nil
        aiBuilderConnectionOK = false
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            aiBuilderConnectionError = L10n.t(.errorAiBuilderTokenEmpty)
            aiBuilderLastTestedAt = Date()
            return
        }
        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let client = try makeVoiceFlowClient()
            try await client.testConnection()
            aiBuilderConnectionOK = true
            aiBuilderLastTestedAt = Date()

            let sig = Self.aiBuilderSignature(baseURL: base, token: token)
            UserDefaults.standard.set(sig, forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.set(aiBuilderLastTestedAt?.timeIntervalSince1970, forKey: Self.aiBuilderLastOKTestedAtKey)
        } catch {
            aiBuilderLastTestedAt = Date()
            aiBuilderConnectionOK = false
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
            switch error {
            case VoiceFlowError.missingToken:
                aiBuilderConnectionError = L10n.t(.errorAiBuilderTokenEmpty)
            case VoiceFlowError.invalidEndpoint:
                aiBuilderConnectionError = L10n.t(.errorInvalidBaseURL)
            case VoiceFlowError.httpError(let statusCode):
                aiBuilderConnectionError = L10n.errorMessage(.errorServerError, String(statusCode))
            default:
                aiBuilderConnectionError = error.localizedDescription
            }
        }
    }
}
