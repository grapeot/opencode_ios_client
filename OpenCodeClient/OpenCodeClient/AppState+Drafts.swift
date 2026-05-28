import Foundation

/// Per-session draft input persistence + selected-model-per-session map.
/// State fields (`draftInputsBySessionID`, `selectedModelIDBySessionID`)
/// stay on `AppState` so SwiftUI observation works; only behavior moves.
extension AppState {
    func persistSelectedModelMap() {
        if selectedModelIDBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.selectedModelBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(selectedModelIDBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.selectedModelBySessionKey)
        }
    }

    func draftText(for sessionID: String?) -> String {
        guard let sessionID else { return "" }
        return draftInputsBySessionID[sessionID] ?? ""
    }

    func setDraftText(_ text: String, for sessionID: String?) {
        guard let sessionID else { return }
        let cleaned = text
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftInputsBySessionID[sessionID] = nil
        } else {
            draftInputsBySessionID[sessionID] = cleaned
        }

        if draftInputsBySessionID.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftInputsBySessionKey)
            return
        }
        if let data = try? JSONEncoder().encode(draftInputsBySessionID) {
            UserDefaults.standard.set(data, forKey: Self.draftInputsBySessionKey)
        }
    }
}
