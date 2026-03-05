import Foundation

enum TurnPipeline {
    static func prepareModelInput<TContext>(
        items: [TResponseInputItem],
        agent: Agent<TContext>,
        runConfig: RunConfig?,
        runContext: RunContextWrapper<TContext>
    ) async throws -> ModelInputData {
        var modelData = ModelInputData(input: items, instructions: try await agent.getSystemPrompt(runContext: runContext))
        if let filter = runConfig?.callModelInputFilter {
            modelData = try await filter(.init(modelData: modelData, agent: unsafeBitCast(agent, to: Agent<Any>.self), context: runContext.context as Any))
        }
        return modelData
    }
}

