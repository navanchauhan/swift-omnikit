import Foundation

// MARK: - generate()

public func generate(
    model: String,
    prompt: String? = nil,
    messages: [Message]? = nil,
    system: String? = nil,
    tools: [Tool]? = nil,
    toolChoice: ToolChoice? = nil,
    maxToolRounds: Int = 1,
    stopWhen: StopCondition? = nil,
    responseFormat: ResponseFormat? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    maxTokens: Int? = nil,
    stopSequences: [String]? = nil,
    reasoningEffort: String? = nil,
    provider: String? = nil,
    providerOptions: [String: [String: AnyCodable]]? = nil,
    maxRetries: Int = 2,
    timeout: TimeoutConfig? = nil,
    client: LLMClient? = nil
) async throws -> GenerateResult {
    // Validate: prompt XOR messages
    if prompt != nil && messages != nil {
        throw ConfigurationError(message: "Cannot provide both 'prompt' and 'messages'. Use one or the other.")
    }
    if prompt == nil && messages == nil {
        throw ConfigurationError(message: "Must provide either 'prompt' or 'messages'.")
    }

    // Check for cancellation early
    try Task.checkCancellation()

    let activeClient = client ?? getDefaultClient()

    // Build initial messages
    var conversation: [Message] = []
    if let system = system {
        conversation.append(.system(system))
    }
    if let prompt = prompt {
        conversation.append(.user(prompt))
    } else if let messages = messages {
        conversation.append(contentsOf: messages)
    }

    // Tool definitions
    let toolDefs = tools?.map { $0.definition }
    let effectiveToolChoice = tools != nil ? (toolChoice ?? .auto) : nil

    let retryPolicy = RetryPolicy(maxRetries: maxRetries)
    var steps: [StepResult] = []
    var totalUsage: Usage = .zero

    let totalDeadline: ContinuousClock.Instant?
    if let totalTimeout = timeout?.total {
        totalDeadline = .now + .seconds(totalTimeout)
    } else {
        totalDeadline = nil
    }

    for round in 0...maxToolRounds {
        // Check cancellation
        try Task.checkCancellation()

        // Check total timeout
        if let deadline = totalDeadline, ContinuousClock.now >= deadline {
            throw RequestTimeoutError(message: "Total timeout of \(timeout!.total!)s exceeded")
        }

        let request = Request(
            model: model,
            messages: conversation,
            provider: provider,
            tools: toolDefs,
            toolChoice: effectiveToolChoice,
            responseFormat: responseFormat,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            stopSequences: stopSequences,
            reasoningEffort: reasoningEffort,
            providerOptions: providerOptions
        )

        let response: Response = try await retry(policy: retryPolicy) {
            try await withStepTimeout(perStep: timeout?.perStep, totalDeadline: totalDeadline) {
                try await activeClient.complete(request: request)
            }
        }

        let responseToolCalls = response.toolCalls
        var toolResults: [ToolResult] = []

        // Execute active tools if model wants to call them
        if !responseToolCalls.isEmpty && response.finishReason.reason == "tool_calls" {
            toolResults = await executeTools(tools: tools ?? [], calls: responseToolCalls)
        }

        let step = StepResult(
            text: response.text,
            reasoning: response.reasoning,
            toolCalls: responseToolCalls,
            toolResults: toolResults,
            finishReason: response.finishReason,
            usage: response.usage,
            response: response,
            warnings: response.warnings
        )
        steps.append(step)
        totalUsage = totalUsage + response.usage

        // Check stop conditions
        if responseToolCalls.isEmpty || response.finishReason.reason != "tool_calls" {
            break  // Natural completion
        }
        if round >= maxToolRounds {
            break  // Budget exhausted
        }
        if let stopWhen = stopWhen, stopWhen.shouldStop(steps: steps) {
            break  // Custom stop
        }

        // Continue conversation with tool results
        conversation.append(response.message)
        for result in toolResults {
            conversation.append(Message.toolResult(
                toolCallId: result.toolCallId,
                content: result.contentString,
                isError: result.isError
            ))
        }
    }

    let lastStep = steps.last!
    return GenerateResult(
        text: lastStep.text,
        reasoning: lastStep.reasoning,
        toolCalls: lastStep.toolCalls,
        toolResults: lastStep.toolResults,
        finishReason: lastStep.finishReason,
        usage: lastStep.usage,
        totalUsage: totalUsage,
        steps: steps,
        response: lastStep.response
    )
}

// MARK: - Timeout Enforcement

/// Runs an operation with per-step and total deadline enforcement.
/// Throws RequestTimeoutError if either timeout is exceeded.
func withStepTimeout<T: Sendable>(
    perStep: TimeInterval?,
    totalDeadline: ContinuousClock.Instant?,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    // Compute the effective timeout: the smaller of perStep and time remaining to totalDeadline
    var effectiveTimeout: TimeInterval?
    if let perStep = perStep {
        effectiveTimeout = perStep
    }
    if let deadline = totalDeadline {
        let remaining = Double((deadline - .now).components.seconds)
            + Double((deadline - .now).components.attoseconds) / 1e18
        if remaining <= 0 {
            throw RequestTimeoutError(message: "Total timeout exceeded")
        }
        if let current = effectiveTimeout {
            effectiveTimeout = min(current, remaining)
        } else {
            effectiveTimeout = remaining
        }
    }

    guard let timeout = effectiveTimeout else {
        return try await operation()
    }

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw RequestTimeoutError(message: "Step timeout of \(timeout)s exceeded")
        }
        guard let result = try await group.next() else {
            throw RequestTimeoutError(message: "Timeout race failed unexpectedly")
        }
        group.cancelAll()
        return result
    }
}

// MARK: - Tool Execution

func executeTools(tools: [Tool], calls: [ToolCall]) async -> [ToolResult] {
    await withTaskGroup(of: (Int, ToolResult).self) { group in
        for (index, call) in calls.enumerated() {
            group.addTask {
                let tool = tools.first { $0.name == call.name }
                guard let tool = tool, let execute = tool.execute else {
                    return (index, ToolResult(
                        toolCallId: call.id,
                        content: "Unknown tool: \(call.name)",
                        isError: true
                    ))
                }

                // Validate arguments against the tool's parameter schema
                if !tool.parameters.isEmpty {
                    let validationErrors = validateJSONSchema(value: call.arguments, schema: tool.parameters, path: "")
                    if !validationErrors.isEmpty {
                        let errorMsg = "Tool argument validation failed for '\(call.name)': " + validationErrors.joined(separator: "; ")
                        return (index, ToolResult(
                            toolCallId: call.id,
                            content: errorMsg,
                            isError: true
                        ))
                    }
                }

                do {
                    let result = try await execute(call.arguments)
                    let content: Any
                    if let s = result as? String {
                        content = s
                    } else if let d = result as? [String: Any] {
                        content = d
                    } else if let a = result as? [Any] {
                        content = a
                    } else {
                        content = "\(result)"
                    }
                    return (index, ToolResult(toolCallId: call.id, content: content))
                } catch {
                    return (index, ToolResult(
                        toolCallId: call.id,
                        content: "Tool execution error: \(error.localizedDescription)",
                        isError: true
                    ))
                }
            }
        }

        var results: [(Int, ToolResult)] = []
        for await result in group {
            results.append(result)
        }
        return results.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
    }
}

// MARK: - JSON Schema Validation

/// Validates a JSON value against a JSON Schema. Returns an array of error messages.
/// Supports type, required, properties, items, enum, minimum, maximum, minLength, maxLength.
func validateJSONSchema(value: Any, schema: [String: Any], path: String) -> [String] {
    var errors: [String] = []
    let pathPrefix = path.isEmpty ? "" : "\(path): "

    // Check type
    if let expectedType = schema["type"] as? String {
        switch expectedType {
        case "object":
            guard let dict = value as? [String: Any] else {
                errors.append("\(pathPrefix)expected object, got \(type(of: value))")
                return errors
            }
            // Check required properties
            if let required = schema["required"] as? [String] {
                for req in required {
                    if dict[req] == nil {
                        errors.append("\(pathPrefix)missing required property '\(req)'")
                    }
                }
            }
            // Validate each property against its sub-schema
            if let properties = schema["properties"] as? [String: Any] {
                for (key, val) in dict {
                    if let propSchema = properties[key] as? [String: Any] {
                        let subPath = path.isEmpty ? key : "\(path).\(key)"
                        errors.append(contentsOf: validateJSONSchema(value: val, schema: propSchema, path: subPath))
                    }
                }
            }

        case "array":
            guard let arr = value as? [Any] else {
                errors.append("\(pathPrefix)expected array, got \(type(of: value))")
                return errors
            }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (i, item) in arr.enumerated() {
                    let subPath = path.isEmpty ? "[\(i)]" : "\(path)[\(i)]"
                    errors.append(contentsOf: validateJSONSchema(value: item, schema: itemSchema, path: subPath))
                }
            }

        case "string":
            guard let str = value as? String else {
                errors.append("\(pathPrefix)expected string, got \(type(of: value))")
                return errors
            }
            if let minLen = schema["minLength"] as? Int, str.count < minLen {
                errors.append("\(pathPrefix)string length \(str.count) is less than minimum \(minLen)")
            }
            if let maxLen = schema["maxLength"] as? Int, str.count > maxLen {
                errors.append("\(pathPrefix)string length \(str.count) exceeds maximum \(maxLen)")
            }

        case "number", "integer":
            guard let num = value as? NSNumber, !(value is Bool) else {
                errors.append("\(pathPrefix)expected \(expectedType), got \(type(of: value))")
                return errors
            }
            if let minimum = schema["minimum"] as? Double, num.doubleValue < minimum {
                errors.append("\(pathPrefix)value \(num) is less than minimum \(minimum)")
            }
            if let maximum = schema["maximum"] as? Double, num.doubleValue > maximum {
                errors.append("\(pathPrefix)value \(num) exceeds maximum \(maximum)")
            }

        case "boolean":
            if !(value is Bool) {
                errors.append("\(pathPrefix)expected boolean, got \(type(of: value))")
            }

        default:
            break
        }
    }

    // Check enum constraint
    if let enumValues = schema["enum"] as? [Any] {
        let valueStr = "\(value)"
        let matched = enumValues.contains { "\($0)" == valueStr }
        if !matched {
            errors.append("\(pathPrefix)value '\(value)' is not in allowed enum values")
        }
    }

    return errors
}
