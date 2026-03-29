import Foundation

public actor TelegramPollingRunner {
    private let client: any TelegramBotAPI
    private let webhookHandler: TelegramWebhookHandler
    private let allowedUpdates: [String]
    private let onError: (@Sendable (any Error) -> Void)?
    private var nextOffset: Int?

    public init(
        client: any TelegramBotAPI,
        webhookHandler: TelegramWebhookHandler,
        allowedUpdates: [String]? = nil,
        onError: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.client = client
        self.webhookHandler = webhookHandler
        self.allowedUpdates = allowedUpdates ?? ["message", "callback_query"]
        self.onError = onError
    }

    public func run(
        timeoutSeconds: Int = 10,
        limit: Int = 25,
        pollInterval: Duration = .milliseconds(250),
        failureBackoff: Duration = .seconds(1),
        maxPolls: Int? = nil
    ) async throws {
        var polls = 0
        while !Task.isCancelled {
            do {
                let updates = try await client.getUpdates(
                    offset: nextOffset,
                    timeoutSeconds: timeoutSeconds,
                    allowedUpdates: allowedUpdates,
                    limit: limit
                )
                for update in updates {
                    do {
                        _ = try await webhookHandler.handle(update: update)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        onError?(error)
                    }
                    nextOffset = update.updateID + 1
                }
                polls += 1
                if let maxPolls, polls >= maxPolls {
                    return
                }
                if updates.isEmpty {
                    try await Task.sleep(for: pollInterval)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                onError?(error)
                try await Task.sleep(for: failureBackoff)
            }
        }
    }
}
