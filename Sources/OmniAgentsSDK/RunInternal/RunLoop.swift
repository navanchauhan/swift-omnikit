import Foundation
import OmniAICore

enum AgentRunLoop {
    static func run<TContext>(
        startingAgent: Agent<TContext>,
        input: StringOrInputList,
        contextWrapper: RunContextWrapper<TContext>,
        maxTurns: Int,
        hooks: RunHooks<TContext>?,
        runConfig: RunConfig?,
        errorHandlers: RunErrorHandlers<TContext>?,
        previousResponseID: String?,
        autoPreviousResponseID: Bool,
        conversationID: String?,
        session: Session?,
        eventSink: ((AgentStreamEvent) -> Void)? = nil,
        existingState: RunState<TContext>? = nil
    ) async throws -> RunResult<TContext> {
        var currentAgent = existingState?.currentAgent ?? startingAgent
        var inputGuardrailResults = existingState?.inputGuardrailResults ?? []
        var outputGuardrailResults = existingState?.outputGuardrailResults ?? []
        var toolInputGuardrailResults = existingState?.toolInputGuardrailResults ?? []
        var toolOutputGuardrailResults = existingState?.toolOutputGuardrailResults ?? []
        var rawResponses = existingState?.modelResponses ?? []
        var newItems = existingState?.generatedItems ?? []
        let initialModelInputItems: [TResponseInputItem]
        if let existingModelInputItems = existingState?.modelInputItems {
            initialModelInputItems = existingModelInputItems
        } else {
            initialModelInputItems = try await SessionPersistenceRuntime.prepareInput(session: session, input: input, runConfig: runConfig)
        }
        var modelInputItems = initialModelInputItems
        let tracker = AgentToolUseTracker()
        if let snapshot = existingState?.toolUseTrackerSnapshot {
            for (agentName, toolNames) in snapshot {
                for toolName in toolNames {
                    await tracker.record(agentName: agentName, toolName: toolName)
                }
            }
        }

        var conversationTracker = OpenAIServerConversationTracker(
            conversationID: existingState?.conversationID ?? conversationID,
            previousResponseID: existingState?.previousResponseID ?? previousResponseID,
            autoPreviousResponseID: existingState?.autoPreviousResponseID ?? autoPreviousResponseID
        )

        let trace: Trace?
        if runConfig?.tracingDisabled == true {
            trace = nil
        } else {
            trace = existingState?.trace ?? createTraceForRun(name: runConfig?.workflowName ?? "Agent workflow", groupID: runConfig?.groupID, metadata: runConfig?.traceMetadata)
        }

        if inputGuardrailResults.isEmpty {
            inputGuardrailResults += try await GuardrailRuntime.runInputGuardrails(
                currentAgent.inputGuardrails,
                context: contextWrapper,
                agent: currentAgent,
                input: input
            )
            if let globalGuardrails = runConfig?.inputGuardrails {
                inputGuardrailResults += try await GuardrailRuntime.runInputGuardrails(
                    globalGuardrails.compactMap { guardrail in
                        InputGuardrail<TContext>(name: guardrail.name, runInParallel: guardrail.runInParallel) { context, agent, input in
                            guardrail.guardrailFunction(RunContextWrapper<Any>(context: context.context as Any, usage: context.usage, turnInput: context.turnInput), unsafeBitCast(agent, to: Agent<Any>.self), input)
                        }
                    },
                    context: contextWrapper,
                    agent: currentAgent,
                    input: input
                )
            }
        }

        await hooks?.onAgentStart(agent: currentAgent, context: contextWrapper)
        await currentAgent.hooks?.onStart(agent: currentAgent, context: contextWrapper)

        for turn in (existingState?.currentTurn ?? 0)..<maxTurns {
            let model = AgentRunnerHelpers.resolveModel(agent: currentAgent, runConfig: runConfig)
            let modelSettings = AgentRunnerHelpers.resolveModelSettings(agent: currentAgent, runConfig: runConfig)
            let allTools = try await currentAgent.getAllTools(runContext: contextWrapper)
            let handoffMap = ToolPlanningRuntime.handoffMap(for: currentAgent)
            let handoffTools = currentAgent.handoffs.map { handoff in
                Tool.function(FunctionTool(
                    name: handoff.toolName,
                    description: handoff.toolDescription,
                    paramsJSONSchema: handoff.inputJSONSchema,
                    onInvokeTool: { _, _ in handoff.agentName },
                    strictJSONSchema: handoff.strictJSONSchema,
                    isEnabled: handoff.isEnabled,
                    needsApproval: .always(false),
                    isAgentTool: true,
                    agentInstance: currentAgent
                ))
            }
            let availableTools = allTools + handoffTools

            let modelInputData = try await TurnPipeline.prepareModelInput(
                items: modelInputItems,
                agent: currentAgent,
                runConfig: runConfig,
                runContext: contextWrapper
            )

            await hooks?.onLLMStart(agent: currentAgent, input: modelInputData.input, context: contextWrapper)
            await currentAgent.hooks?.onLLMStart(agent: currentAgent, input: modelInputData.input, context: contextWrapper)
            let response = try await withSpan(name: "llm.call", data: .init(kind: "llm", attributes: ["agent": .string(currentAgent.name)])) {
                try await model.getResponse(
                    systemInstructions: modelInputData.instructions,
                    input: .inputList(modelInputData.input),
                    modelSettings: modelSettings,
                    tools: availableTools,
                    outputSchema: currentAgent.outputType,
                    handoffs: [],
                    tracing: .enabled,
                    previousResponseID: conversationTracker.previousResponseID,
                    conversationID: conversationTracker.conversationID,
                    prompt: try await currentAgent.getPrompt(runContext: contextWrapper)
                )
            }
            rawResponses.append(response)
            conversationTracker.record(response)
            await hooks?.onLLMEnd(agent: currentAgent, response: response, context: contextWrapper)
            await currentAgent.hooks?.onLLMEnd(agent: currentAgent, response: response, context: contextWrapper)

            eventSink?(.rawResponse(.init(data: ["type": .string("raw_response"), "response_id": response.responseID.map(JSONValue.string) ?? .null])))

            let responseItems = RunItemFactory.items(from: response, agent: currentAgent, handoffNames: Set(handoffMap.keys))
            newItems.append(contentsOf: responseItems)
            for item in responseItems {
                switch item {
                case let message as MessageOutputItem:
                    eventSink?(.runItem(.init(name: .messageOutputCreated, item: message)))
                case let reasoning as ReasoningItem:
                    eventSink?(.runItem(.init(name: .reasoningItemCreated, item: reasoning)))
                case let handoffCall as HandoffCallItem:
                    eventSink?(.runItem(.init(name: .handoffRequested, item: handoffCall)))
                case let toolCall as ToolCallItem:
                    eventSink?(.runItem(.init(name: .toolCalled, item: toolCall)))
                default:
                    break
                }
            }

            let toolCallItems = ToolPlanningRuntime.extractToolCalls(from: response)
            if toolCallItems.isEmpty {
                let finalOutput = try AgentRunnerHelpers.renderFinalOutput(response: response, agent: currentAgent)
                outputGuardrailResults += try await GuardrailRuntime.runOutputGuardrails(currentAgent.outputGuardrails, context: contextWrapper, agent: currentAgent, output: finalOutput)
                if let globalOutputGuardrails = runConfig?.outputGuardrails {
                    outputGuardrailResults += try await GuardrailRuntime.runOutputGuardrails(
                        globalOutputGuardrails.compactMap { guardrail in
                            OutputGuardrail<TContext>(name: guardrail.name) { context, agent, output in
                                guardrail.guardrailFunction(RunContextWrapper<Any>(context: context.context as Any, usage: context.usage, turnInput: context.turnInput), unsafeBitCast(agent, to: Agent<Any>.self), output)
                            }
                        },
                        context: contextWrapper,
                        agent: currentAgent,
                        output: finalOutput
                    )
                }
                try await SessionPersistenceRuntime.persist(session: session, items: response.toInputItems())
                await hooks?.onAgentEnd(agent: currentAgent, result: finalOutput, context: contextWrapper)
                await currentAgent.hooks?.onEnd(agent: currentAgent, output: finalOutput, context: contextWrapper)
                return RunResult(
                    input: input,
                    newItems: newItems,
                    rawResponses: rawResponses,
                    finalOutput: finalOutput,
                    inputGuardrailResults: inputGuardrailResults,
                    outputGuardrailResults: outputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults,
                    contextWrapper: contextWrapper,
                    lastAgent: currentAgent,
                    lastProcessedResponse: .init(items: responseItems, nextStep: .finalOutput(finalOutput), response: response),
                    toolUseTrackerSnapshot: await tracker.snapshot(),
                    currentTurn: turn,
                    modelInputItems: modelInputItems,
                    originalInput: input,
                    conversationID: conversationTracker.conversationID,
                    previousResponseID: conversationTracker.previousResponseID,
                    autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                    reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                    maxTurns: maxTurns,
                    trace: trace
                )
            }

            var toolOutputsForNextTurn: [TResponseInputItem] = response.toInputItems()
            var interruptions: [ToolApprovalItem] = []
            var functionToolResults: [FunctionToolResult] = []
            let toolMap = ToolPlanningRuntime.toolMap(for: availableTools)

            for call in toolCallItems {
                let toolName = call["name"]?.stringValue ?? "tool"
                let callID = call["call_id"]?.stringValue ?? call["id"]?.stringValue ?? UUID().uuidString

                if let handoff = handoffMap[toolName] {
                    let handoffAgent = try await handoff.onInvokeHandoff(contextWrapper, call["arguments"]?.stringValue ?? "{}")
                    let transferItem: TResponseInputItem = [
                        "type": .string("message"),
                        "role": .string("assistant"),
                        "content": .array([.object(["type": .string("output_text"), "text": .string(handoff.getTransferMessage())])]),
                    ]
                    let handoffOutputItem = HandoffOutputItem(agent: handoffAgent, rawItem: transferItem, sourceAgent: currentAgent, targetAgent: handoffAgent)
                    newItems.append(handoffOutputItem)
                    eventSink?(.agentUpdated(.init(newAgent: handoffAgent)))
                    let handoffInputData = HandoffInputData(
                        inputHistory: .inputList(modelInputItems),
                        preHandoffItems: newItems,
                        newItems: responseItems,
                        runContext: RunContextWrapper<Any>(context: contextWrapper.context as Any, usage: contextWrapper.usage, turnInput: contextWrapper.turnInput),
                        inputItems: newItems
                    )
                    if handoff.nestHandoffHistory == true || (handoff.nestHandoffHistory == nil && runConfig?.nestHandoffHistory == true) {
                        if let inputFilter = handoff.inputFilter {
                            let filtered = try await inputFilter(handoffInputData)
                            modelInputItems = filtered.inputHistory.inputItems
                        } else {
                            modelInputItems = try await nestHandoffHistory(handoffInputData)
                        }
                    } else if let inputFilter = handoff.inputFilter {
                        let filtered = try await inputFilter(handoffInputData)
                        modelInputItems = filtered.inputHistory.inputItems
                    } else if let globalFilter = runConfig?.handoffInputFilter {
                        let filtered = try await globalFilter(handoffInputData)
                        modelInputItems = filtered.inputHistory.inputItems
                    } else {
                        modelInputItems = modelInputItems + [transferItem]
                    }
                    await hooks?.onHandoff(from: currentAgent, to: handoffAgent, context: contextWrapper)
                    await currentAgent.hooks?.onHandoff(from: currentAgent, to: handoffAgent, context: contextWrapper)
                    currentAgent = handoffAgent
                    continue
                }

                guard let tool = toolMap[toolName] else {
                    throw UserError(message: "Unknown tool called by model: \(toolName)")
                }

                let rawArguments = call["arguments"]?.objectValue ?? [:]
                let needsApproval = try await ApprovalRuntime.evaluateNeedsApprovalSetting(tool: tool, runContext: contextWrapper, arguments: rawArguments, callID: callID)
                if needsApproval {
                    let approvalStatus = contextWrapper.getApprovalStatus(toolName: toolName, callID: callID)
                    if approvalStatus == nil {
                        let approvalItem = ApprovalRuntime.makeApprovalItem(agent: currentAgent, toolName: toolName, callID: callID, rawItem: call)
                        interruptions.append(approvalItem)
                        newItems.append(approvalItem)
                        eventSink?(.runItem(.init(name: .mcpApprovalRequested, item: approvalItem)))
                        continue
                    }
                    if approvalStatus == false {
                        let message: String
                        if let formatter = runConfig?.toolErrorFormatter {
                            message = try await formatter(.init(kind: "approval_rejected", toolType: tool.type, toolName: toolName, callID: callID, defaultMessage: ApprovalRuntime.defaultApprovalRejectedMessage(toolName: toolName), runContext: RunContextWrapper<Any>(context: contextWrapper.context as Any, usage: contextWrapper.usage, turnInput: contextWrapper.turnInput))) ?? ApprovalRuntime.defaultApprovalRejectedMessage(toolName: toolName)
                        } else {
                            message = ApprovalRuntime.defaultApprovalRejectedMessage(toolName: toolName)
                        }
                        let outputItem = ToolCallOutputItem(agent: currentAgent, rawItem: ItemHelpers.toolCallOutputItem(toolCall: call, output: message), output: message)
                        newItems.append(outputItem)
                        toolOutputsForNextTurn.append(try outputItem.toInputItem())
                        eventSink?(.runItem(.init(name: .toolOutput, item: outputItem)))
                        continue
                    }
                }

                await hooks?.onToolStart(tool: tool, context: contextWrapper, arguments: call["arguments"]?.stringValue ?? ItemHelpers.stringifyJSON(.object(rawArguments)), callID: callID)
                await currentAgent.hooks?.onToolStart(agent: currentAgent, tool: tool, context: contextWrapper, arguments: call["arguments"]?.stringValue ?? ItemHelpers.stringifyJSON(.object(rawArguments)), callID: callID)
                let toolResult = try await ToolRuntime.execute(tool: tool, call: call, runContext: contextWrapper, agent: currentAgent, runConfig: runConfig)
                functionToolResults.append(toolResult)
                await tracker.record(agentName: currentAgent.name, toolName: toolName)
                await hooks?.onToolEnd(tool: tool, context: contextWrapper, result: toolResult.output, callID: callID)
                await currentAgent.hooks?.onToolEnd(agent: currentAgent, tool: tool, context: contextWrapper, result: toolResult.output, callID: callID)

                let outputItem = ToolCallOutputItem(agent: currentAgent, rawItem: ItemHelpers.toolCallOutputItem(toolCall: call, output: toolResult.output), output: toolResult.output)
                newItems.append(outputItem)
                toolOutputsForNextTurn.append(try outputItem.toInputItem())
                eventSink?(.runItem(.init(name: .toolOutput, item: outputItem)))
            }

            if !interruptions.isEmpty {
                return RunResult(
                    input: input,
                    newItems: newItems,
                    rawResponses: rawResponses,
                    finalOutput: ItemHelpers.textMessageOutputs(items: responseItems),
                    inputGuardrailResults: inputGuardrailResults,
                    outputGuardrailResults: outputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults,
                    contextWrapper: contextWrapper,
                    lastAgent: currentAgent,
                    lastProcessedResponse: .init(items: responseItems, nextStep: .interruption(interruptions), response: response, toolResults: functionToolResults),
                    toolUseTrackerSnapshot: await tracker.snapshot(),
                    currentTurn: turn,
                    modelInputItems: toolOutputsForNextTurn,
                    originalInput: input,
                    conversationID: conversationTracker.conversationID,
                    previousResponseID: conversationTracker.previousResponseID,
                    autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                    reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                    maxTurns: maxTurns,
                    interruptions: interruptions,
                    trace: trace
                )
            }

            switch currentAgent.toolUseBehavior {
            case .stopOnFirstTool where !functionToolResults.isEmpty:
                let output = functionToolResults.count == 1 ? functionToolResults[0].output : functionToolResults.map(\.output)
                return RunResult(
                    input: input,
                    newItems: newItems,
                    rawResponses: rawResponses,
                    finalOutput: output,
                    inputGuardrailResults: inputGuardrailResults,
                    outputGuardrailResults: outputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults,
                    contextWrapper: contextWrapper,
                    lastAgent: currentAgent,
                    lastProcessedResponse: .init(items: responseItems, nextStep: .finalOutput(output), response: response, toolResults: functionToolResults),
                    toolUseTrackerSnapshot: await tracker.snapshot(),
                    currentTurn: turn,
                    modelInputItems: toolOutputsForNextTurn,
                    originalInput: input,
                    conversationID: conversationTracker.conversationID,
                    previousResponseID: conversationTracker.previousResponseID,
                    autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                    reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                    maxTurns: maxTurns,
                    trace: trace
                )
            case .stopAtTools(let stopAt) where !functionToolResults.filter({ stopAt.stopAtToolNames.contains($0.tool.name) }).isEmpty:
                let output = functionToolResults.map(\.output)
                return RunResult(
                    input: input,
                    newItems: newItems,
                    rawResponses: rawResponses,
                    finalOutput: output,
                    inputGuardrailResults: inputGuardrailResults,
                    outputGuardrailResults: outputGuardrailResults,
                    toolInputGuardrailResults: toolInputGuardrailResults,
                    toolOutputGuardrailResults: toolOutputGuardrailResults,
                    contextWrapper: contextWrapper,
                    lastAgent: currentAgent,
                    lastProcessedResponse: .init(items: responseItems, nextStep: .finalOutput(output), response: response, toolResults: functionToolResults),
                    toolUseTrackerSnapshot: await tracker.snapshot(),
                    currentTurn: turn,
                    modelInputItems: toolOutputsForNextTurn,
                    originalInput: input,
                    conversationID: conversationTracker.conversationID,
                    previousResponseID: conversationTracker.previousResponseID,
                    autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                    reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                    maxTurns: maxTurns,
                    trace: trace
                )
            case .custom(let function):
                let result = try await function(contextWrapper, functionToolResults)
                if result.isFinalOutput {
                    return RunResult(
                        input: input,
                        newItems: newItems,
                        rawResponses: rawResponses,
                        finalOutput: result.finalOutput as Any,
                        inputGuardrailResults: inputGuardrailResults,
                        outputGuardrailResults: outputGuardrailResults,
                        toolInputGuardrailResults: toolInputGuardrailResults,
                        toolOutputGuardrailResults: toolOutputGuardrailResults,
                        contextWrapper: contextWrapper,
                        lastAgent: currentAgent,
                        lastProcessedResponse: .init(items: responseItems, nextStep: .finalOutput(result.finalOutput as Any), response: response, toolResults: functionToolResults),
                        toolUseTrackerSnapshot: await tracker.snapshot(),
                        currentTurn: turn,
                        modelInputItems: toolOutputsForNextTurn,
                        originalInput: input,
                        conversationID: conversationTracker.conversationID,
                        previousResponseID: conversationTracker.previousResponseID,
                        autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                        reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                        maxTurns: maxTurns,
                        trace: trace
                    )
                }
            default:
                break
            }

            modelInputItems = toolOutputsForNextTurn
            try await SessionPersistenceRuntime.persist(session: session, items: toolOutputsForNextTurn)
        }

        let error = MaxTurnsExceeded(message: "Max turns exceeded")
        if let handled = try await ErrorHandlerRuntime.handleMaxTurns(
            error: error,
            input: input,
            newItems: newItems,
            rawResponses: rawResponses,
            history: modelInputItems,
            lastAgent: currentAgent,
            context: contextWrapper,
            handlers: errorHandlers
        ) {
            return RunResult(
                input: input,
                newItems: newItems,
                rawResponses: rawResponses,
                finalOutput: handled.finalOutput,
                inputGuardrailResults: inputGuardrailResults,
                outputGuardrailResults: outputGuardrailResults,
                toolInputGuardrailResults: toolInputGuardrailResults,
                toolOutputGuardrailResults: toolOutputGuardrailResults,
                contextWrapper: contextWrapper,
                lastAgent: currentAgent,
                toolUseTrackerSnapshot: await tracker.snapshot(),
                currentTurn: maxTurns,
                modelInputItems: modelInputItems,
                originalInput: input,
                conversationID: conversationTracker.conversationID,
                previousResponseID: conversationTracker.previousResponseID,
                autoPreviousResponseID: conversationTracker.autoPreviousResponseID,
                reasoningItemIDPolicy: runConfig?.reasoningItemIDPolicy,
                maxTurns: maxTurns,
                trace: trace
            )
        }

        throw error
    }
}
