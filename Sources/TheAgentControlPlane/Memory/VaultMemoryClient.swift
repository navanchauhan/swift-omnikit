import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct VaultMemoryClient {
    struct MemoryRecord: Decodable, Sendable {
        var id: Int64?
        var kind: String
        var text: String
        var entities: [String]
        var sourceItemIDs: [Int64]?
        var confidence: Double?
        var salience: Double?
        var staleness: Double?
        var expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case kind
            case text
            case entities
            case sourceItemIDs = "source_item_ids"
            case confidence
            case salience
            case staleness
            case expiresAt = "expires_at"
        }

        func json(score: Double) -> [String: Any] {
            [
                "id": id ?? NSNull(),
                "kind": kind,
                "text": text,
                "entities": entities,
                "source_item_ids": sourceItemIDs ?? [],
                "confidence": confidence ?? NSNull(),
                "salience": salience ?? NSNull(),
                "staleness": staleness ?? NSNull(),
                "expires_at": expiresAt?.ISO8601Format() ?? NSNull(),
                "score": score,
            ]
        }
    }

    struct MemoryHit: Decodable, Sendable {
        var memory: MemoryRecord
        var score: Double
    }

    struct SearchResponse: Decodable, Sendable {
        var hits: [MemoryHit]
        var count: Int
    }

    static func search(query: String, kinds: [String], entities: [String], limit: Int) async throws -> [String: Any] {
        let hits = try await searchRaw(query: query, kinds: kinds, entities: entities, limit: limit)
        return [
            "query": query,
            "count": hits.count,
            "hits": hits.map { $0.memory.json(score: $0.score) },
        ]
    }

    static func automaticContext(for query: String, limit: Int = 6) async -> String? {
        guard autoInjectEnabled(),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        do {
            let hits = try await searchRaw(query: query, kinds: [], entities: [], limit: limit)
            let lines = hits.prefix(limit).map { hit in
                let entities = hit.memory.entities.isEmpty ? "" : " entities=\(hit.memory.entities.joined(separator: ","))"
                return "- [\(hit.memory.kind) score=\(String(format: "%.2f", hit.score))\(entities)] \(hit.memory.text)"
            }
            guard !lines.isEmpty else { return nil }
            return lines.joined(separator: "\n")
        } catch {
            return nil
        }
    }

    private static func searchRaw(query: String, kinds: [String], entities: [String], limit: Int) async throws -> [MemoryHit] {
        let config = try Config.load()
        var components = URLComponents(url: config.baseURL.appendingPathComponent("memory/search"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 30)))),
        ]
        if !kinds.isEmpty {
            queryItems.append(URLQueryItem(name: "kind", value: kinds.joined(separator: ",")))
        }
        if !entities.isEmpty {
            queryItems.append(URLQueryItem(name: "entity", value: entities.joined(separator: ",")))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw VaultMemoryError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: config.timeoutSeconds)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VaultMemoryError.httpStatus(status, String(body.prefix(300)))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SearchResponse.self, from: data).hits
    }

    private static func autoInjectEnabled() -> Bool {
        let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }
        let value = env["THE_VAULT_MEMORY_AUTO_INJECT"] ?? env["VAULT_MEMORY_AUTO_INJECT"] ?? "0"
        return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private struct Config: Sendable {
        var baseURL: URL
        var apiKey: String
        var timeoutSeconds: TimeInterval

        static func load() throws -> Config {
            let env = ProcessInfo.processInfo.environment.merging(loadDotEnv()) { current, _ in current }
            let rawBase = env["THE_VAULT_API_BASE_URL"] ?? env["VAULT_API_BASE_URL"] ?? "http://127.0.0.1:8942/api/v1"
            guard let baseURL = URL(string: rawBase.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw VaultMemoryError.invalidURL
            }
            guard let apiKey = (env["THE_VAULT_API_KEY"] ?? env["VAULT_API_KEY"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty
            else {
                throw VaultMemoryError.missingAPIKey
            }
            let timeout = TimeInterval(env["THE_VAULT_API_TIMEOUT_SECONDS"] ?? "") ?? 4
            return Config(baseURL: baseURL, apiKey: apiKey, timeoutSeconds: max(1, min(timeout, 15)))
        }
    }

    private static func loadDotEnv() -> [String: String] {
        guard let data = try? String(contentsOfFile: ".env", encoding: .utf8) else {
            return [:]
        }
        var values: [String: String] = [:]
        for rawLine in data.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }
}

enum VaultMemoryError: Error, CustomStringConvertible {
    case invalidURL
    case missingAPIKey
    case httpStatus(Int, String)

    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid Vault memory API URL."
        case .missingAPIKey:
            return "Missing THE_VAULT_API_KEY or VAULT_API_KEY."
        case .httpStatus(let status, let body):
            return "Vault memory API returned HTTP \(status): \(body)"
        }
    }
}
