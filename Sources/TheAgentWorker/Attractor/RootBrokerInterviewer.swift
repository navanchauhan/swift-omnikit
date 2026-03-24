import Foundation
import OmniAIAttractor
import OmniAgentMesh

public struct RootBrokerInterviewer: Interviewer {
    private let task: TaskRecord
    private let bridge: any WorkerInteractionBridge
    private let defaultTimeoutSeconds: Double

    public init(
        task: TaskRecord,
        bridge: any WorkerInteractionBridge,
        defaultTimeoutSeconds: Double = 600
    ) {
        self.task = task
        self.bridge = bridge
        self.defaultTimeoutSeconds = max(1, defaultTimeoutSeconds)
    }

    public func ask(_ question: InterviewQuestion) async -> InterviewAnswer {
        do {
            if isApprovalQuestion(question) {
                let resolution = try await bridge.requestApproval(
                    WorkerApprovalPrompt(
                        rootSessionID: task.rootSessionID,
                        requesterActorID: task.requesterActorID,
                        workspaceID: task.workspaceID,
                        channelID: task.channelID,
                        missionID: task.missionID,
                        taskID: task.taskID,
                        title: interactionTitle(for: question, defaultPrefix: "Approval Needed"),
                        prompt: question.text,
                        sensitive: question.metadata["interaction_sensitive"] != "false",
                        metadata: interactionMetadata(for: question),
                        timeoutSeconds: resolvedTimeout(for: question)
                    )
                )
                return mapApprovalResolution(resolution, question: question)
            }

            let resolution = try await bridge.requestQuestion(
                WorkerQuestionPrompt(
                    rootSessionID: task.rootSessionID,
                    requesterActorID: task.requesterActorID,
                    workspaceID: task.workspaceID,
                    channelID: task.channelID,
                    missionID: task.missionID,
                    taskID: task.taskID,
                    title: interactionTitle(for: question, defaultPrefix: "Question Pending"),
                    prompt: question.text,
                    kind: questionKind(for: question),
                    options: question.options.map(\.label),
                    metadata: interactionMetadata(for: question),
                    timeoutSeconds: resolvedTimeout(for: question)
                )
            )
            return mapQuestionResolution(resolution, question: question)
        } catch {
            return question.defaultAnswer ?? .skipped()
        }
    }

    public func inform(_ message: String, stage: String) async {}

    private func isApprovalQuestion(_ question: InterviewQuestion) -> Bool {
        if question.metadata["interaction_kind"] == "approval" {
            return true
        }
        let labels = question.options.map { $0.label.lowercased() }
        return labels.contains(where: { $0 == "approve" || $0 == "reject" })
    }

    private func interactionTitle(for question: InterviewQuestion, defaultPrefix: String) -> String {
        if let explicit = question.metadata["interaction_title"], !explicit.isEmpty {
            return explicit
        }
        if !question.stage.isEmpty {
            return "\(defaultPrefix): \(question.stage)"
        }
        return defaultPrefix
    }

    private func interactionMetadata(for question: InterviewQuestion) -> [String: String] {
        question.metadata.merging([
            "stage": question.stage,
            "task_id": task.taskID,
            "mission_id": task.missionID ?? "",
        ]) { current, _ in current }
    }

    private func resolvedTimeout(for question: InterviewQuestion) -> Double {
        max(1, question.timeoutSeconds ?? defaultTimeoutSeconds)
    }

    private func questionKind(for question: InterviewQuestion) -> QuestionRequestRecord.Kind {
        switch question.type {
        case .confirm, .yesNo, .confirmation:
            return .confirmation
        case .singleSelect, .multipleChoice, .multiSelect:
            return .singleSelect
        case .freeText, .freeform:
            return .freeText
        }
    }

    private func mapApprovalResolution(
        _ resolution: WorkerInteractionResolution,
        question: InterviewQuestion
    ) -> InterviewAnswer {
        switch resolution.status {
        case .approved:
            if let selected = preferredOption(
                in: question.options,
                candidates: ["approve", "yes", "continue"]
            ) {
                return .option(selected)
            }
            return .yes()
        case .rejected, .cancelled:
            if let selected = preferredOption(
                in: question.options,
                candidates: ["reject", "no", "abort"]
            ) {
                return .option(selected)
            }
            return .no()
        case .deferred, .timedOut:
            return .timedOut()
        case .answered:
            if let text = resolution.responseText, !text.isEmpty {
                return matchAnswerText(text, question: question)
            }
            return question.defaultAnswer ?? .skipped()
        }
    }

    private func mapQuestionResolution(
        _ resolution: WorkerInteractionResolution,
        question: InterviewQuestion
    ) -> InterviewAnswer {
        switch resolution.status {
        case .answered:
            guard let responseText = resolution.responseText, !responseText.isEmpty else {
                return question.defaultAnswer ?? .skipped()
            }
            return matchAnswerText(responseText, question: question)
        case .approved:
            return .yes()
        case .rejected, .cancelled:
            return .no()
        case .deferred, .timedOut:
            return .timedOut()
        }
    }

    private func matchAnswerText(
        _ answerText: String,
        question: InterviewQuestion
    ) -> InterviewAnswer {
        if let option = preferredOption(in: question.options, matching: answerText) {
            return .option(option)
        }
        return .freeText(answerText)
    }

    private func preferredOption(
        in options: [InterviewOption],
        candidates: [String]
    ) -> InterviewOption? {
        options.first { option in
            let normalizedLabel = option.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedKey = option.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return candidates.contains(normalizedLabel) || candidates.contains(normalizedKey)
        } ?? options.first
    }

    private func preferredOption(
        in options: [InterviewOption],
        matching answerText: String
    ) -> InterviewOption? {
        let normalizedAnswer = answerText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return options.first { option in
            option.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAnswer
                || option.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAnswer
        }
    }
}
