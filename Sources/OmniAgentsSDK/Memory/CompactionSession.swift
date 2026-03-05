import Foundation

public final actor OpenAIResponsesCompactionSession: OpenAIResponsesCompactionAwareSession {
    public let sessionID: String
    public let sessionSettings: SessionSettings?
    private var items: [TResponseInputItem]
    private var lastResponseID: String?

    public init(sessionID: String, sessionSettings: SessionSettings? = nil) {
        self.sessionID = sessionID
        self.sessionSettings = sessionSettings
        self.items = []
    }

    public func getItems(limit: Int? = nil) async throws -> [TResponseInputItem] {
        let resolvedLimit = resolveSessionLimit(limit, settings: sessionSettings)
        guard let resolvedLimit else { return items }
        return Array(items.suffix(resolvedLimit))
    }

    public func addItems(_ items: [TResponseInputItem]) async throws {
        self.items.append(contentsOf: items)
    }

    public func popItem() async throws -> TResponseInputItem? {
        items.popLast()
    }

    public func clearSession() async throws {
        items.removeAll()
    }

    public func runCompaction(args: OpenAIResponsesCompactionArgs? = nil) async throws {
        let mode = args?.compactionMode ?? "auto"
        switch mode {
        case "input":
            if items.count > 1 {
                items = [items.last!]
            }
        case "previous_response_id", "auto":
            if let responseID = args?.responseID {
                lastResponseID = responseID
            }
            if items.count > 1, args?.force == true {
                items = [items.last!]
            }
        default:
            break
        }
    }
}

