import Foundation
import OmniAICore

open class OmniAICoreModel: Model, @unchecked Sendable {
    public let modelName: String?
    public let providerName: String?
    public let client: Client
    public let providerOptions: [String: JSONValue]

    public init(
        modelName: String? = nil,
        providerName: String? = nil,
        client: Client? = nil,
        providerOptions: [String: JSONValue] = [:]
    ) {
        self.modelName = modelName
        self.providerName = providerName
        self.client = client ?? (try! Client.fromEnvAllowingEmpty())
        self.providerOptions = providerOptions
    }

    public func close() async {}

    public func getResponse(
        systemInstructions: String?,
        input: StringOrInputList,
        modelSettings: ModelSettings,
        tools: [Tool],
        outputSchema: (any AgentOutputSchemaBase)?,
        handoffs: [Any],
        tracing: ModelTracing,
        previousResponseID: String?,
        conversationID: String?,
        prompt: Prompt?
    ) async throws -> ModelResponse {
        let request = try buildRequest(
            systemInstructions: systemInstructions,
            input: input,
            modelSettings: modelSettings,
            tools: tools,
            outputSchema: outputSchema,
            previousResponseID: previousResponseID,
            conversationID: conversationID,
            prompt: prompt
        )
        let response = try await client.complete(request)
        return ModelConversion.responseToModelResponse(response)
    }

    public func streamResponse(
        systemInstructions: String?,
        input: StringOrInputList,
        modelSettings: ModelSettings,
        tools: [Tool],
        outputSchema: (any AgentOutputSchemaBase)?,
        handoffs: [Any],
        tracing: ModelTracing,
        previousResponseID: String?,
        conversationID: String?,
        prompt: Prompt?
    ) async throws -> AsyncThrowingStream<TResponseStreamEvent, Error> {
        let request = try buildRequest(
            systemInstructions: systemInstructions,
            input: input,
            modelSettings: modelSettings,
            tools: tools,
            outputSchema: outputSchema,
            previousResponseID: previousResponseID,
            conversationID: conversationID,
            prompt: prompt
        )
        let upstream = try await client.stream(request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in upstream {
                        continuation.yield(ModelConversion.streamEventToResponseEvent(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    open func buildRequest(
        systemInstructions: String?,
        input: StringOrInputList,
        modelSettings: ModelSettings,
        tools: [Tool],
        outputSchema: (any AgentOutputSchemaBase)?,
        previousResponseID: String?,
        conversationID: String?,
        prompt: Prompt?
    ) throws -> Request {
        let resolvedProviderName = providerName ?? client.defaultProviderName
        let requestTools = try tools.compactMap { try $0.llmDefinition() }

        let responseFormat: ResponseFormat?
        if let outputSchema, !outputSchema.isPlainText, let schema = outputSchema.jsonSchema {
            responseFormat = .jsonSchema(.object(schema), strict: outputSchema.isStrictJSONSchema)
        } else {
            responseFormat = nil
        }

        let toolChoice: OmniAICore.ToolChoice?
        switch modelSettings.toolChoice {
        case nil, .some(.auto):
            toolChoice = requestTools.isEmpty ? nil : .auto
        case .some(.none):
            toolChoice = OmniAICore.ToolChoice.none
        case .some(.required):
            toolChoice = .required
        case .some(.named(let name)):
            toolChoice = .named(name)
        case .some(.mcpToolChoice(let choice)):
            toolChoice = .named(choice.name)
        }

        let scopedProviderOptions = buildScopedProviderOptions(
            resolvedProviderName: resolvedProviderName,
            modelSettings: modelSettings,
            tools: tools,
            conversationID: conversationID
        )

        return Request(
            model: resolveModelName(for: resolvedProviderName),
            messages: ModelConversion.inputItemsToMessages(
                systemInstructions: PromptUtil.render(prompt: prompt, baseInstructions: systemInstructions),
                input: input
            ),
            provider: resolvedProviderName,
            previousResponseId: previousResponseID,
            tools: requestTools.isEmpty ? nil : requestTools,
            toolChoice: toolChoice,
            responseFormat: responseFormat,
            temperature: modelSettings.temperature,
            topP: modelSettings.topP,
            maxTokens: modelSettings.maxTokens,
            reasoningEffort: modelSettings.reasoning?.effort,
            metadata: modelSettings.metadata,
            providerOptions: scopedProviderOptions
        )
    }

    open func resolveModelName(for providerName: String?) -> String {
        if let modelName {
            return modelName
        }
        if let providerName,
           let latest = client.getLatestModel(provider: providerName) {
            return latest.id
        }
        return getDefaultModel()
    }

    open func buildScopedProviderOptions(
        resolvedProviderName: String?,
        modelSettings: ModelSettings,
        tools: [Tool],
        conversationID: String?
    ) -> [String: JSONValue]? {
        guard let resolvedProviderName else {
            return nil
        }

        var scoped = providerOptions

        if resolvedProviderName == "openai" {
            if tools.contains(where: { if case .webSearch = $0 { return true } else { return false } }) {
                scoped[OpenAIProviderOptionKeys.includeNativeWebSearch] = .bool(true)
                if let externalWebAccess = tools.compactMap({ tool -> Bool? in
                    if case .webSearch(let search) = tool { return search.externalWebAccess }
                    return nil
                }).last {
                    scoped[OpenAIProviderOptionKeys.webSearchExternalWebAccess] = .bool(externalWebAccess)
                }
            }
            if let conversationID, !conversationID.isEmpty {
                scoped["conversation"] = .string(conversationID)
            }
        }

        if let extraBody = modelSettings.extraBody {
            for (key, value) in extraBody {
                scoped[key] = value
            }
        }
        if let extraArgs = modelSettings.extraArgs {
            for (key, value) in extraArgs {
                scoped[key] = value
            }
        }

        return scoped.isEmpty ? nil : [resolvedProviderName: .object(scoped)]
    }
}

open class OpenAIResponsesModel: OmniAICoreModel, @unchecked Sendable {
    public init(modelName: String? = nil, client: Client? = nil, providerOptions: [String: JSONValue] = [:]) {
        super.init(modelName: modelName, providerName: "openai", client: client, providerOptions: providerOptions)
    }
}

public final class OpenAIResponsesWSModel: OpenAIResponsesModel, @unchecked Sendable {
    public init(modelName: String? = nil, client: Client? = nil) {
        super.init(
            modelName: modelName,
            client: client,
            providerOptions: [OpenAIProviderOptionKeys.responsesTransport: .string("websocket")]
        )
    }
}
