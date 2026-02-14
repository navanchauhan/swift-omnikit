import Foundation

// MARK: - Wait Human Handler

public final class WaitHumanHandler: NodeHandler, @unchecked Sendable {
    public let handlerType: HandlerType = .waitHuman
    private let interviewer: Interviewer

    public init(interviewer: Interviewer) {
        self.interviewer = interviewer
    }

    public func execute(
        node: Node,
        context: PipelineContext,
        graph: Graph,
        logsRoot: URL
    ) async throws -> Outcome {
        let outgoing = graph.outgoingEdges(from: node.id)

        // Build options from outgoing edge labels
        let options = outgoing.map { edge -> InterviewOption in
            let label = edge.label.isEmpty ? edge.to : edge.label
            let key = parseAcceleratorKey(from: label)
            return InterviewOption(key: key, label: label)
        }

        let questionText = node.prompt.isEmpty ? node.label : node.prompt

        // Determine timeout
        var timeoutSeconds: Double? = nil
        if let duration = node.timeout {
            let ns = duration.components.seconds * 1_000_000_000 + Int64(duration.components.attoseconds / 1_000_000_000)
            timeoutSeconds = Double(ns) / 1_000_000_000.0
        }

        // Find default answer
        var defaultAnswer: InterviewAnswer? = nil
        if let defaultEdge = outgoing.first(where: { $0.label.lowercased().contains("default") }) {
            let label = defaultEdge.label.isEmpty ? defaultEdge.to : defaultEdge.label
            let key = parseAcceleratorKey(from: label)
            defaultAnswer = .option(InterviewOption(key: key, label: label))
        }

        let questionType: QuestionType = options.count > 0 ? .singleSelect : .freeText

        let question = InterviewQuestion(
            text: questionText,
            type: questionType,
            options: options,
            defaultAnswer: defaultAnswer,
            timeoutSeconds: timeoutSeconds,
            stage: node.id
        )

        let answer = await interviewer.ask(question)

        // Handle timeout
        if answer.answerValue == .timeout || answer.answerValue == .skipped {
            if defaultAnswer != nil, let defaultEdge = outgoing.first(where: { $0.label.lowercased().contains("default") }) {
                let label = defaultEdge.label.isEmpty ? defaultEdge.to : defaultEdge.label
                return Outcome(
                    status: .success,
                    preferredLabel: label,
                    notes: "Used default due to timeout/skip"
                )
            }
            return Outcome(status: .skipped, notes: "Human input skipped or timed out")
        }

        // Match selected option to an edge label
        let selectedLabel: String
        if let selected = answer.selectedOption {
            selectedLabel = selected.label
        } else {
            // Try to match free text to an edge label
            let matchedEdge = outgoing.first { edge in
                let label = edge.label.isEmpty ? edge.to : edge.label
                return label.lowercased() == answer.value.lowercased()
            }
            selectedLabel = matchedEdge.map { $0.label.isEmpty ? $0.to : $0.label } ?? answer.value
        }

        return Outcome(
            status: .success,
            preferredLabel: selectedLabel,
            contextUpdates: ["human_input": answer.value],
            notes: "Human selected: \(selectedLabel)"
        )
    }

    /// Parse accelerator key from edge labels.
    /// Supports formats: `[K] Label`, `K) Label`, `K - Label`, or uses first character.
    private func parseAcceleratorKey(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)

        // [K] Label
        if trimmed.hasPrefix("["), let closeBracket = trimmed.firstIndex(of: "]") {
            let start = trimmed.index(after: trimmed.startIndex)
            let key = String(trimmed[start..<closeBracket])
            if !key.isEmpty { return key }
        }

        // K) Label
        if trimmed.count >= 2 {
            let secondChar = trimmed[trimmed.index(after: trimmed.startIndex)]
            if secondChar == ")" {
                return String(trimmed.first!)
            }
        }

        // K - Label
        if trimmed.count >= 3 {
            let idx1 = trimmed.index(trimmed.startIndex, offsetBy: 1)
            let idx2 = trimmed.index(trimmed.startIndex, offsetBy: 2)
            if trimmed[idx1] == " " && trimmed[idx2] == "-" {
                return String(trimmed.first!)
            }
        }

        // Default: first character
        if let first = trimmed.first {
            return String(first)
        }
        return ""
    }
}

