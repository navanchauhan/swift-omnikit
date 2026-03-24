import Foundation
import OmniAgentMesh

public actor MeshInteractionBridgeService: WorkerInteractionBridge {
    private let serverRegistry: WorkspaceSessionRegistry
    private let missionStore: any MissionStore
    private let pollInterval: Duration
    private let defaultTimeoutSeconds: Double

    public init(
        serverRegistry: WorkspaceSessionRegistry,
        missionStore: any MissionStore,
        pollInterval: Duration = .milliseconds(250),
        defaultTimeoutSeconds: Double = 600
    ) {
        self.serverRegistry = serverRegistry
        self.missionStore = missionStore
        self.pollInterval = pollInterval
        self.defaultTimeoutSeconds = max(1, defaultTimeoutSeconds)
    }

    public func requestApproval(_ prompt: WorkerApprovalPrompt) async throws -> WorkerInteractionResolution {
        let server = await serverRegistry.server(sessionID: prompt.rootSessionID)
        let request = try await server.requestApprovalPrompt(
            title: prompt.title,
            prompt: prompt.prompt,
            missionID: prompt.missionID,
            taskID: prompt.taskID,
            requesterActorID: prompt.requesterActorID,
            sensitive: prompt.sensitive,
            metadata: prompt.metadata
        )
        return try await waitForApproval(requestID: request.requestID, timeoutSeconds: prompt.timeoutSeconds)
    }

    public func requestQuestion(_ prompt: WorkerQuestionPrompt) async throws -> WorkerInteractionResolution {
        let server = await serverRegistry.server(sessionID: prompt.rootSessionID)
        let request = try await server.requestQuestionPrompt(
            title: prompt.title,
            prompt: prompt.prompt,
            kind: prompt.kind,
            options: prompt.options,
            missionID: prompt.missionID,
            taskID: prompt.taskID,
            requesterActorID: prompt.requesterActorID,
            metadata: prompt.metadata
        )
        return try await waitForQuestion(requestID: request.requestID, timeoutSeconds: prompt.timeoutSeconds)
    }

    private func waitForApproval(
        requestID: String,
        timeoutSeconds: Double?
    ) async throws -> WorkerInteractionResolution {
        let deadline = Date().addingTimeInterval(timeoutSeconds ?? defaultTimeoutSeconds)
        while true {
            guard var request = try await missionStore.approvalRequest(requestID: requestID) else {
                return WorkerInteractionResolution(requestID: requestID, status: .cancelled)
            }

            switch request.status {
            case .approved:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .approved,
                    responseText: request.responseText,
                    responderActorID: request.responseActorID
                )
            case .rejected:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .rejected,
                    responseText: request.responseText,
                    responderActorID: request.responseActorID
                )
            case .cancelled:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .cancelled,
                    responseText: request.responseText,
                    responderActorID: request.responseActorID
                )
            case .deferred:
                if Date() >= deadline {
                    return WorkerInteractionResolution(
                        requestID: request.requestID,
                        status: .deferred,
                        responseText: request.responseText,
                        responderActorID: request.responseActorID
                    )
                }
            case .pending:
                if Date() >= deadline {
                    request.status = .deferred
                    request.updatedAt = Date()
                    _ = try await missionStore.saveApprovalRequest(request)
                    return WorkerInteractionResolution(
                        requestID: request.requestID,
                        status: .deferred,
                        responseText: request.responseText,
                        responderActorID: request.responseActorID
                    )
                }
            }

            try await Task.sleep(for: pollInterval)
        }
    }

    private func waitForQuestion(
        requestID: String,
        timeoutSeconds: Double?
    ) async throws -> WorkerInteractionResolution {
        let deadline = Date().addingTimeInterval(timeoutSeconds ?? defaultTimeoutSeconds)
        while true {
            guard var request = try await missionStore.questionRequest(requestID: requestID) else {
                return WorkerInteractionResolution(requestID: requestID, status: .cancelled)
            }

            switch request.status {
            case .answered:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .answered,
                    responseText: request.answerText,
                    responderActorID: request.answerActorID
                )
            case .cancelled:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .cancelled,
                    responseText: request.answerText,
                    responderActorID: request.answerActorID
                )
            case .timedOut:
                return WorkerInteractionResolution(
                    requestID: request.requestID,
                    status: .timedOut,
                    responseText: request.answerText,
                    responderActorID: request.answerActorID
                )
            case .deferred:
                if Date() >= deadline {
                    return WorkerInteractionResolution(
                        requestID: request.requestID,
                        status: .deferred,
                        responseText: request.answerText,
                        responderActorID: request.answerActorID
                    )
                }
            case .pending:
                if Date() >= deadline {
                    request.status = .timedOut
                    request.updatedAt = Date()
                    _ = try await missionStore.saveQuestionRequest(request)
                    return WorkerInteractionResolution(
                        requestID: request.requestID,
                        status: .timedOut,
                        responseText: request.answerText,
                        responderActorID: request.answerActorID
                    )
                }
            }

            try await Task.sleep(for: pollInterval)
        }
    }
}
