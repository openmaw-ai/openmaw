import Foundation

struct SyncItem: Codable {
    let itemType: String
    let itemId: String
    let data: SyncItemData
    var deleted: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case data, deleted
        case updatedAt = "updated_at"
    }
}

/// Wraps arbitrary JSON data for sync items.
struct SyncItemData: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: SyncAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([SyncAnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { SyncAnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { SyncAnyCodable($0) })
        } else if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

struct SyncPullResponse: Codable {
    let items: [SyncItem]
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case items
        case serverTime = "server_time"
    }
}

struct SyncPushResponse: Codable {
    let accepted: [String]
    let conflicts: [SyncConflict]
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case accepted, conflicts
        case serverTime = "server_time"
    }
}

struct SyncConflict: Codable {
    let itemType: String
    let itemId: String
    let serverData: SyncItemData
    let serverUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case itemType = "item_type"
        case itemId = "item_id"
        case serverData = "server_data"
        case serverUpdatedAt = "server_updated_at"
    }
}

// MARK: - SyncAnyCodable helper

struct SyncAnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: SyncAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([SyncAnyCodable].self) {
            value = array.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { SyncAnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { SyncAnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
