import Foundation
import OmniAgentMesh

public struct AttractorWorkflowTemplate: Sendable {
    public var provider: String
    public var model: String
    public var reasoningEffort: String

    public init(
        provider: String = "openai",
        model: String = "gpt-5.2-codex",
        reasoningEffort: String = "high"
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    public func dot(for task: TaskRecord) -> String {
        let taskBrief = escape(task.historyProjection.taskBrief)
        let constraints = escape(joinedList(task.historyProjection.constraints))
        let expectedOutputs = escape(joinedList(task.historyProjection.expectedOutputs))
        let includeApprovalGate = task.historyProjection.constraints.contains {
            $0.localizedStandardContains("human_gate=true") || $0.localizedStandardContains("requires_approval=true")
        }
        let includeQuestionGate = task.historyProjection.constraints.contains {
            $0.localizedStandardContains("question_gate=true")
        } || constraintValue(prefix: "question_prompt=", in: task.historyProjection.constraints) != nil
        let questionPrompt = escape(
            constraintValue(prefix: "question_prompt=", in: task.historyProjection.constraints)
                ?? "Do we have enough information to continue with this task?"
        )

        let rejectNode = """
            reject       [shape=box, prompt="The workflow was halted after a human gate. Summarize the stop condition and exit.", auto_status=true]
        """

        let approvalNode = includeApprovalGate ? """
            approval     [shape=hexagon, prompt="Approve execution for task: \(taskBrief)?", human.default_choice="Approve", interaction_kind="approval", interaction_title="Approval Needed"]
        """ : ""

        let questionNode = includeQuestionGate ? """
            clarify      [shape=hexagon, prompt="\(questionPrompt)", human.default_choice="Continue", interaction_kind="question", interaction_title="Clarification Needed", question_kind="confirmation"]
        """ : ""

        let humanNodes = [questionNode, approvalNode, (includeApprovalGate || includeQuestionGate) ? rejectNode : ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let planEdge: String = {
            if includeQuestionGate {
                return "plan -> clarify"
            }
            if includeApprovalGate {
                return "plan -> approval"
            }
            return "plan -> implement"
        }()

        let questionEdges = includeQuestionGate ? """
            clarify -> \(includeApprovalGate ? "approval" : "implement") [label="Continue"]
            clarify -> reject [label="Abort"]
        """ : ""

        let approvalEdges = includeApprovalGate ? """
            approval -> implement [label="Approve"]
            approval -> reject [label="Reject"]
        """ : ""

        let humanEdges = [planEdge, questionEdges, approvalEdges, (includeApprovalGate || includeQuestionGate) ? "reject -> done" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return """
        digraph attractor_task_\(escapeIdentifier(task.taskID)) {
            graph [
                goal="\(taskBrief)",
                default_max_retry=0,
                model_stylesheet="* { llm_model: \(model); llm_provider: \(provider); reasoning_effort: \(reasoningEffort); }"
            ]

            start        [shape=Mdiamond]
            plan         [shape=box, prompt="Create a concise execution contract for this task. Task: \(taskBrief). Constraints: \(constraints). Expected outputs: \(expectedOutputs)."]
            \(humanNodes)
            implement    [shape=box, prompt="Implement or execute the task. Task: \(taskBrief). Constraints: \(constraints). Expected outputs: \(expectedOutputs).", auto_status=true]
            review       [shape=box, prompt="Review the implementation outcome for blockers. Task: \(taskBrief). Expected outputs: \(expectedOutputs). If blockers exist, return outcome fail.", goal_gate=true]
            scenario     [shape=box, prompt="Validate the result against the expected outputs. Outputs: \(expectedOutputs). If validation fails, return outcome fail.", goal_gate=true]
            judge        [shape=box, prompt="Judge whether the workflow is complete and safe to report. Return success if complete, fail if blockers remain.", goal_gate=true]
            done         [shape=Msquare]

            start -> plan
            \(humanEdges)
            implement -> review
            review -> scenario
            scenario -> judge
            judge -> done
        }
        """
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func escapeIdentifier(_ rawValue: String) -> String {
        rawValue.map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce(into: "") { partialResult, character in
            partialResult.append(character)
        }
    }

    private func joinedList(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    private func constraintValue(prefix: String, in constraints: [String]) -> String? {
        constraints.first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
