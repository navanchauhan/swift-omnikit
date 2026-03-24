import Foundation

public actor TelegramPollingRunner {
    private let client: any TelegramBotAPI
    private let webhookHandler: TelegramWebhookHandler
    private let allowedUpdates: [String]
    private var nextOffset: Int?

    public init(
        client: any TelegramBotAPI,
        webhookHandler: TelegramWebhookHandler,
        allowedUpdates: [String]? = nil
    ) {
        self.client = client
        self.webhookHandler = webhookHandler
        self.allowedUpdates = allowedUpdates ?? ["message", "callback_query"]
    }

    public func run(
        timeoutSeconds: Int = 10,
        limit: Int = 25,
        pollInterval: Duration = .milliseconds(250),
        maxPolls: Int? = nil
    ) async throws {
        var polls = 0
        while !Task.isCancelled {
            let updates = try await client.getUpdates(
                offset: nextOffset,
                timeoutSeconds: timeoutSeconds,
                allowedUpdates: allowedUpdates,
                limit: limit
            )
            for update in updates {
                nextOffset = update.updateID + 1
                _ = try await webhookHandler.handle(update: update)
            }
            polls += 1
            if let maxPolls, polls >= maxPolls {
                return
            }
            if updates.isEmpty {
                try await Task.sleep(for: pollInterval)
            }
        }
    }
}
