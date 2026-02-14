import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - Pipeline Run State

public final class PipelineRunState: @unchecked Sendable {
    private let lock = NSLock()
    public let id: String
    public let dotSource: String
    public private(set) var status: PipelineRunStatus = .pending
    public private(set) var result: PipelineResult?
    public private(set) var error: String?
    public private(set) var pendingQuestions: [PendingQuestion] = []
    private var questionAnswers: [String: InterviewAnswer] = [:]
    private var questionContinuations: [String: CheckedContinuation<InterviewAnswer, Never>] = [:]
    public let eventEmitter: PipelineEventEmitter
    private var task: Task<Void, Never>?

    public init(id: String, dotSource: String) {
        self.id = id
        self.dotSource = dotSource
        self.eventEmitter = PipelineEventEmitter()
    }

    public enum PipelineRunStatus: String, Sendable {
        case pending, running, completed, failed, cancelled
    }

    public struct PendingQuestion: Sendable {
        public let id: String
        public let question: InterviewQuestion
        public let createdAt: Date
    }

    func setStatus(_ s: PipelineRunStatus) {
        lock.lock()
        status = s
        lock.unlock()
    }

    func setResult(_ r: PipelineResult) {
        lock.lock()
        result = r
        status = r.status == .success ? .completed : .failed
        lock.unlock()
    }

    func setError(_ e: String) {
        lock.lock()
        error = e
        status = .failed
        lock.unlock()
    }

    func setTask(_ t: Task<Void, Never>) {
        lock.lock()
        task = t
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        task?.cancel()
        status = .cancelled
        lock.unlock()
    }

    func addPendingQuestion(_ q: PendingQuestion) {
        lock.lock()
        pendingQuestions.append(q)
        lock.unlock()
    }

    func removePendingQuestion(_ qid: String) {
        lock.lock()
        pendingQuestions.removeAll { $0.id == qid }
        lock.unlock()
    }

    func registerQuestionContinuation(_ qid: String, _ cont: CheckedContinuation<InterviewAnswer, Never>) {
        lock.lock()
        if let answer = questionAnswers[qid] {
            questionAnswers.removeValue(forKey: qid)
            lock.unlock()
            cont.resume(returning: answer)
        } else {
            questionContinuations[qid] = cont
            lock.unlock()
        }
    }

    func submitAnswer(_ qid: String, _ answer: InterviewAnswer) {
        lock.lock()
        if let cont = questionContinuations[qid] {
            questionContinuations.removeValue(forKey: qid)
            lock.unlock()
            cont.resume(returning: answer)
        } else {
            questionAnswers[qid] = answer
            lock.unlock()
        }
    }
}

// MARK: - HTTP Server Interviewer

public final class HTTPServerInterviewer: @unchecked Sendable, Interviewer {
    private let runState: PipelineRunState
    private var questionCounter = 0
    private let lock = NSLock()

    public init(runState: PipelineRunState) {
        self.runState = runState
    }

    public func ask(_ question: InterviewQuestion) async -> InterviewAnswer {
        lock.lock()
        questionCounter += 1
        let qid = "q\(questionCounter)"
        lock.unlock()

        let pending = PipelineRunState.PendingQuestion(
            id: qid,
            question: question,
            createdAt: Date()
        )
        runState.addPendingQuestion(pending)

        await runState.eventEmitter.emit(PipelineEvent(
            kind: .interviewStarted,
            data: ["question_id": qid, "question": question.text, "stage": question.stage]
        ))

        let answer: InterviewAnswer = await withCheckedContinuation { continuation in
            runState.registerQuestionContinuation(qid, continuation)
        }

        runState.removePendingQuestion(qid)

        await runState.eventEmitter.emit(PipelineEvent(
            kind: .interviewCompleted,
            data: ["question_id": qid, "answer": answer.value]
        ))

        return answer
    }
}

// MARK: - Attractor HTTP Server

public final class AttractorHTTPServer: @unchecked Sendable {
    private let backend: CodergenBackend
    private let port: UInt16
    private let lock = NSLock()
    private var runs: [String: PipelineRunState] = [:]
    private var listener: Any? = nil

    public init(backend: CodergenBackend, port: UInt16 = 8080) {
        self.backend = backend
        self.port = port
    }

    // MARK: - Pipeline Management

    public func createRun(dotSource: String) -> PipelineRunState {
        let id = UUID().uuidString.lowercased().prefix(8).description
        let state = PipelineRunState(id: id, dotSource: dotSource)
        lock.lock()
        runs[id] = state
        lock.unlock()
        return state
    }

    public func getRun(_ id: String) -> PipelineRunState? {
        lock.lock()
        defer { lock.unlock() }
        return runs[id]
    }

    public func startRun(_ state: PipelineRunState) {
        state.setStatus(.running)
        let backend = self.backend

        let task = Task {
            let logsRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("attractor-server/\(state.id)")
            let interviewer = HTTPServerInterviewer(runState: state)

            let config = PipelineConfig(
                logsRoot: logsRoot,
                backend: backend,
                interviewer: interviewer,
                eventEmitter: state.eventEmitter
            )

            let engine = PipelineEngine(config: config)
            do {
                let result = try await engine.run(dot: state.dotSource)
                state.setResult(result)
            } catch {
                state.setError(error.localizedDescription)
            }
        }
        state.setTask(task)
    }

    public func cancelRun(_ id: String) -> Bool {
        guard let state = getRun(id) else { return false }
        state.cancel()
        return true
    }

    public func submitAnswer(runId: String, questionId: String, answer: InterviewAnswer) -> Bool {
        guard let state = getRun(runId) else { return false }
        state.submitAnswer(questionId, answer)
        return true
    }

    // MARK: - HTTP Request Handling

    public func handleRequest(method: String, path: String, body: Data?) async -> HTTPResponse {
        let components = path.split(separator: "/").map(String.init)

        // POST /pipelines - Create and start a pipeline
        if method == "POST" && components == ["pipelines"] {
            guard let body = body,
                  let dotSource = String(data: body, encoding: .utf8),
                  !dotSource.isEmpty else {
                return HTTPResponse(status: 400, body: "{\"error\":\"Missing DOT source in request body\"}")
            }
            let state = createRun(dotSource: dotSource)
            startRun(state)
            return HTTPResponse(
                status: 201,
                body: "{\"id\":\"\(state.id)\",\"status\":\"\(state.status.rawValue)\"}"
            )
        }

        // GET /pipelines/{id} - Get pipeline status
        if method == "GET" && components.count == 2 && components[0] == "pipelines" {
            let id = components[1]
            guard let state = getRun(id) else {
                return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
            }
            var json: [String: Any] = [
                "id": state.id,
                "status": state.status.rawValue,
            ]
            if let result = state.result {
                json["completed_nodes"] = result.completedNodes
                json["node_outcomes"] = result.nodeOutcomes.mapValues { $0.rawValue }
            }
            if let error = state.error {
                json["error"] = error
            }
            let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            return HTTPResponse(status: 200, body: String(data: data ?? Data(), encoding: .utf8) ?? "{}")
        }

        // GET /pipelines/{id}/events - SSE event stream
        if method == "GET" && components.count == 3 && components[0] == "pipelines" && components[2] == "events" {
            let id = components[1]
            guard let state = getRun(id) else {
                return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
            }
            let events = await state.eventEmitter.history()
            var lines: [String] = []
            for event in events {
                var eventData: [String: Any] = [
                    "kind": event.kind.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                ]
                if let nodeId = event.nodeId { eventData["node_id"] = nodeId }
                for (k, v) in event.data { eventData[k] = v }
                if let data = try? JSONSerialization.data(withJSONObject: eventData, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    lines.append("data: \(str)\n")
                }
            }
            return HTTPResponse(
                status: 200,
                body: lines.joined(separator: "\n"),
                contentType: "text/event-stream"
            )
        }

        // POST /pipelines/{id}/cancel - Cancel pipeline
        if method == "POST" && components.count == 3 && components[0] == "pipelines" && components[2] == "cancel" {
            let id = components[1]
            if cancelRun(id) {
                return HTTPResponse(status: 200, body: "{\"status\":\"cancelled\"}")
            }
            return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
        }

        // GET /pipelines/{id}/questions - Get pending questions
        if method == "GET" && components.count == 3 && components[0] == "pipelines" && components[2] == "questions" {
            let id = components[1]
            guard let state = getRun(id) else {
                return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
            }
            var questions: [[String: Any]] = []
            for q in state.pendingQuestions {
                var qDict: [String: Any] = [
                    "id": q.id,
                    "text": q.question.text,
                    "type": q.question.type.rawValue,
                    "stage": q.question.stage,
                ]
                if !q.question.options.isEmpty {
                    qDict["options"] = q.question.options.map { ["key": $0.key, "label": $0.label] }
                }
                questions.append(qDict)
            }
            let data = try? JSONSerialization.data(withJSONObject: ["questions": questions], options: [.sortedKeys])
            return HTTPResponse(status: 200, body: String(data: data ?? Data(), encoding: .utf8) ?? "{}")
        }

        // POST /pipelines/{id}/questions/{qid}/answer - Submit answer
        if method == "POST" && components.count == 5
            && components[0] == "pipelines" && components[2] == "questions" && components[4] == "answer" {
            let runId = components[1]
            let qid = components[3]
            guard let body = body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let value = json["value"] as? String else {
                return HTTPResponse(status: 400, body: "{\"error\":\"Missing 'value' in request body\"}")
            }

            var answer: InterviewAnswer
            if let optionKey = json["option_key"] as? String,
               let optionLabel = json["option_label"] as? String {
                answer = .option(InterviewOption(key: optionKey, label: optionLabel))
            } else {
                answer = .freeText(value)
            }

            if submitAnswer(runId: runId, questionId: qid, answer: answer) {
                return HTTPResponse(status: 200, body: "{\"status\":\"answered\"}")
            }
            return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline or question not found\"}")
        }

        // GET /pipelines/{id}/checkpoint - Get checkpoint
        if method == "GET" && components.count == 3 && components[0] == "pipelines" && components[2] == "checkpoint" {
            let id = components[1]
            guard let state = getRun(id) else {
                return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
            }
            if let result = state.result {
                let json: [String: Any] = [
                    "completed_nodes": result.completedNodes,
                    "node_outcomes": result.nodeOutcomes.mapValues { $0.rawValue },
                    "context": result.context,
                ]
                let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                return HTTPResponse(status: 200, body: String(data: data ?? Data(), encoding: .utf8) ?? "{}")
            }
            return HTTPResponse(status: 200, body: "{\"status\":\"in_progress\"}")
        }

        // GET /pipelines/{id}/context - Get context
        if method == "GET" && components.count == 3 && components[0] == "pipelines" && components[2] == "context" {
            let id = components[1]
            guard let state = getRun(id) else {
                return HTTPResponse(status: 404, body: "{\"error\":\"Pipeline not found\"}")
            }
            if let result = state.result {
                let data = try? JSONSerialization.data(withJSONObject: result.context, options: [.sortedKeys])
                return HTTPResponse(status: 200, body: String(data: data ?? Data(), encoding: .utf8) ?? "{}")
            }
            return HTTPResponse(status: 200, body: "{}")
        }

        return HTTPResponse(status: 404, body: "{\"error\":\"Not found\"}")
    }
}

// MARK: - HTTP Response

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: String
    public let contentType: String

    public init(status: Int, body: String, contentType: String = "application/json") {
        self.status = status
        self.body = body
        self.contentType = contentType
    }
}


