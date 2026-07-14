import Foundation

extension AppState {
    @discardableResult
    func normalizeFluidVoiceBaseURL() throws -> String {
        let normalized = try FluidVoiceClient.normalizedBaseURL(fluidVoiceBaseURL).absoluteString
        if normalized != fluidVoiceBaseURL {
            fluidVoiceBaseURL = normalized
        }
        return normalized
    }

    func testFluidVoiceConnection() async {
        guard !isTestingFluidVoiceConnection else { return }
        isTestingFluidVoiceConnection = true
        defer { isTestingFluidVoiceConnection = false }

        fluidVoiceConnectionOK = false
        fluidVoiceConnectionError = nil
        fluidVoiceHealthStatus = nil
        fluidVoiceHealthVersion = nil

        do {
            let normalized = try normalizeFluidVoiceBaseURL()
            let health = try await fluidVoiceClient.health(baseURL: normalized)
            fluidVoiceHealthStatus = health.status
            fluidVoiceHealthVersion = health.version
            fluidVoiceConnectionOK = health.status.lowercased() == "ok"
            if !fluidVoiceConnectionOK {
                fluidVoiceConnectionError = "FluidVoice reported status: \(health.status)"
            }
        } catch {
            fluidVoiceConnectionError = error.localizedDescription
        }
    }

    func transcribeWithFluidVoice(wavFileURL: URL) async throws -> String {
        let normalized = try normalizeFluidVoiceBaseURL()
        return try await fluidVoiceClient.transcribeAudio(
            wavFileURL: wavFileURL,
            baseURL: normalized,
            postprocessWithFluidIntelligence: fluidVoicePostprocess
        )
    }
}
