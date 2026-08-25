import Foundation
import Testing
@testable import OpenCodeClient

struct UserDefaultsIsolationTests {
    @MainActor
    @Test func shortlistDoesNotLeakAcrossUserDefaultsSuites() {
        let aDefaults = UserDefaults(suiteName: "opencode.tests.iso.a.\(UUID().uuidString)")!
        let bDefaults = UserDefaults(suiteName: "opencode.tests.iso.b.\(UUID().uuidString)")!
        let a = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: aDefaults)
        let b = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: bDefaults)

        a.addModelsToShortlist([
            ModelPreset(displayName: "GLM-5.3", providerID: "zai-coding-plan", modelID: "glm-5.3")
        ])
        #expect(a.modelShortlist.map(\.id) == ["zai-coding-plan/glm-5.3"])
        #expect(b.modelShortlist.isEmpty)

        let bReloaded = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), sshTunnelManager: SSHTunnelManager(), userDefaults: bDefaults)
        #expect(bReloaded.modelShortlist.isEmpty)
    }
}
