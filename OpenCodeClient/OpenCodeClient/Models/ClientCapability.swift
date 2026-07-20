import Foundation

nonisolated enum ClientCapability: String, Codable, Sendable {
    case healthExportAll = "health_quantification.export_all"
}

nonisolated enum ClientCapabilityPermission: String, Codable, Sendable {
    case ask
    case allowAlways = "allow_always"
}

nonisolated enum HealthExportStatus: String, Codable, Sendable {
    case success
    case partial
    case failed
    case busy
}

nonisolated enum HealthExportCategory: String, Codable, CaseIterable, Sendable {
    case sleep
    case vitals
    case body
    case lifestyle
    case activity
    case workouts
}

nonisolated enum HealthExportErrorCode: String, Codable, CaseIterable, Sendable {
    case categoryFailure = "category_failure"
    case exportInProgress = "export_in_progress"
    case invalidServerURL = "invalid_server_url"
}

nonisolated struct ClientActionCallback: Equatable, Sendable {
    let callbackID: String
    let status: HealthExportStatus
    let sent: Int
    let upserted: Int
    let failedCategories: [HealthExportCategory]
    let errorCode: HealthExportErrorCode?
}

nonisolated struct ClientCapabilityCallbackRecord: Codable, Equatable, Sendable {
    let version: Int
    let callbackID: String
    let capability: ClientCapability
    let hostProfileID: UUID
    let hostConfigurationSignature: String
    let carContextKey: String
    let sessionID: String
    let assistantMessageID: String
    let actionID: String
    let continuationMessageID: String
    let createdAt: Date
    let expiresAt: Date
    var result: ClientActionCallbackPayload?

    enum CodingKeys: String, CodingKey {
        case version
        case callbackID = "callback_id"
        case capability
        case hostProfileID = "host_profile_id"
        case hostConfigurationSignature = "host_configuration_signature"
        case carContextKey = "car_context_key"
        case sessionID = "session_id"
        case assistantMessageID = "assistant_message_id"
        case actionID = "action_id"
        case continuationMessageID = "continuation_message_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case result
    }
}

nonisolated struct ClientActionCallbackPayload: Codable, Equatable, Sendable {
    let status: HealthExportStatus
    let sent: Int
    let upserted: Int
    let failedCategories: [HealthExportCategory]
    let errorCode: HealthExportErrorCode?

    enum CodingKeys: String, CodingKey {
        case status
        case sent
        case upserted
        case failedCategories = "failed_categories"
        case errorCode = "error_code"
    }

    init(callback: ClientActionCallback) {
        status = callback.status
        sent = callback.sent
        upserted = callback.upserted
        failedCategories = callback.failedCategories
        errorCode = callback.errorCode
    }
}

struct PendingClientCapabilityRequest: Identifiable, Equatable {
    let action: CarClientAction
    let hostProfileID: UUID
    let sessionID: String
    let carContextKey: String
    let assistantMessageID: String

    var id: String { action.id }
}
