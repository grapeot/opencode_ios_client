import Foundation

struct ClientCapabilityCallbackStore {
    enum StoreError: Error {
        case invalidRecord
        case duplicateCapability
    }

    static let pendingLifetime: TimeInterval = 15 * 60
    static let outboxLifetime: TimeInterval = 6 * 60 * 60
    static let maximumRecordCount = 50

    let rootDirectory: URL
    var now: () -> Date = Date.init

    private var pendingDirectory: URL { rootDirectory.appendingPathComponent("Pending", isDirectory: true) }
    private var outboxDirectory: URL { rootDirectory.appendingPathComponent("Outbox", isDirectory: true) }

    static func applicationSupport() -> ClientCapabilityCallbackStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ClientCapabilityCallbackStore(rootDirectory: base.appendingPathComponent("ClientCapabilityCallbacks", isDirectory: true))
    }

    func createPending(
        capability: ClientCapability,
        hostProfileID: UUID,
        hostConfigurationSignature: String = "",
        carContextKey: String,
        sessionID: String,
        assistantMessageID: String,
        actionID: String
    ) throws -> ClientCapabilityCallbackRecord {
        try prepareDirectories()
        try cleanup()
        if try hasActiveRecord(for: capability) {
            throw StoreError.duplicateCapability
        }

        let createdAt = now()
        let callbackID = Self.makeCallbackID()
        let record = ClientCapabilityCallbackRecord(
            version: 1,
            callbackID: callbackID,
            capability: capability,
            hostProfileID: hostProfileID,
            hostConfigurationSignature: hostConfigurationSignature,
            carContextKey: carContextKey,
            sessionID: sessionID,
            assistantMessageID: assistantMessageID,
            actionID: actionID,
            continuationMessageID: "msg_client_\(callbackID)",
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(Self.pendingLifetime),
            result: nil
        )
        try write(record, to: pendingURL(callbackID))
        return record
    }

    func consume(_ callback: ClientActionCallback) throws -> ClientCapabilityCallbackRecord? {
        try prepareDirectories()
        let pending = pendingURL(callback.callbackID)
        let outbox = outboxURL(callback.callbackID)
        if FileManager.default.fileExists(atPath: outbox.path) { return nil }
        guard let record = try readRecord(at: pending),
              record.version == 1,
              record.callbackID == callback.callbackID,
              record.capability == .healthExportAll,
              record.expiresAt > now() else {
            try? FileManager.default.removeItem(at: pending)
            return nil
        }

        var accepted = record
        accepted.result = ClientActionCallbackPayload(callback: callback)
        try write(accepted, to: outbox)
        try? FileManager.default.removeItem(at: pending)
        return accepted
    }

    func outboxRecords() throws -> [ClientCapabilityCallbackRecord] {
        try prepareDirectories()
        return try recordURLs(in: outboxDirectory).compactMap(readRecord).sorted { $0.createdAt < $1.createdAt }
    }

    func removeOutbox(callbackID: String) throws {
        let url = outboxURL(callbackID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func removePending(callbackID: String) throws {
        let url = pendingURL(callbackID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func hasActiveRecord(for capability: ClientCapability) throws -> Bool {
        try prepareDirectories()
        let records = try recordURLs(in: pendingDirectory).compactMap(readRecord)
            + recordURLs(in: outboxDirectory).compactMap(readRecord)
        return records.contains { $0.capability == capability && retentionDeadline(for: $0) > now() }
    }

    func cleanup() throws {
        try prepareDirectories()
        var records: [(URL, ClientCapabilityCallbackRecord)] = []
        for url in try recordURLs(in: pendingDirectory) + recordURLs(in: outboxDirectory) {
            guard Self.isValidCallbackID(url.deletingPathExtension().lastPathComponent) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let record: ClientCapabilityCallbackRecord
            do {
                guard let decoded = try readRecord(at: url) else { continue }
                record = decoded
            } catch {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard record.version == 1,
                  record.callbackID == url.deletingPathExtension().lastPathComponent else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if url.deletingLastPathComponent() == pendingDirectory,
               FileManager.default.fileExists(atPath: outboxURL(record.callbackID).path) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if retentionDeadline(for: record) <= now() {
                try? FileManager.default.removeItem(at: url)
            } else {
                records.append((url, record))
            }
        }
        if records.count > Self.maximumRecordCount {
            for (url, _) in records.sorted(by: { $0.1.createdAt < $1.1.createdAt }).prefix(records.count - Self.maximumRecordCount) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func makeCallbackID() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isValidCallbackID(_ value: String) -> Bool {
        guard (43...128).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122: return true
            default: return false
            }
        }
    }

    private func retentionDeadline(for record: ClientCapabilityCallbackRecord) -> Date {
        record.result == nil ? record.expiresAt : record.createdAt.addingTimeInterval(Self.outboxLifetime)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true)
    }

    private func pendingURL(_ callbackID: String) -> URL { pendingDirectory.appendingPathComponent(callbackID).appendingPathExtension("json") }
    private func outboxURL(_ callbackID: String) -> URL { outboxDirectory.appendingPathComponent(callbackID).appendingPathExtension("json") }

    private func recordURLs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private func readRecord(at url: URL) throws -> ClientCapabilityCallbackRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ClientCapabilityCallbackRecord.self, from: Data(contentsOf: url))
    }

    private func write(_ record: ClientCapabilityCallbackRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}
