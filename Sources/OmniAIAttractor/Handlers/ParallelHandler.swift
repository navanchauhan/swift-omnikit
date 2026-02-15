import Foundation

// MARK: - Parallel Handler

public final class ParallelHandler: NodeHandler, @unchecked Sendable {
    public let handlerType: HandlerType = .parallel
    private let registry: HandlerRegistry

    public init(registry: HandlerRegistry) {
        self.registry = registry
    }

    public func execute(
        node: Node,
        context: PipelineContext,
        graph: Graph,
        logsRoot: URL
    ) async throws -> Outcome {
        let outgoing = graph.outgoingEdges(from: node.id)

        if outgoing.isEmpty {
            return .success(notes: "Parallel node with no branches")
        }

        // Run all branches concurrently
        let results: [(String, Outcome)] = try await withThrowingTaskGroup(
            of: (String, Outcome).self
        ) { group in
            for edge in outgoing {
                let targetId = edge.to
                guard let targetNode = graph.node(targetId) else { continue }
                guard let handler = registry.resolve(targetNode.handlerType) else {
                    throw AttractorError.handlerNotFound(targetNode.handlerType.rawValue)
                }

                // Clone context for each branch
                let branchContext = context.clone()

                group.addTask {
                    let outcome = try await handler.execute(
                        node: targetNode,
                        context: branchContext,
                        graph: graph,
                        logsRoot: logsRoot
                    )
                    return (targetId, outcome)
                }
            }

            var collected: [(String, Outcome)] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // Store results in context
        var branchResults: [String: String] = [:]
        for (nodeId, outcome) in results {
            branchResults[nodeId] = outcome.status.rawValue
        }
        context.set("parallel.results", branchResults)

        // Merge context updates from all branches
        var mergedUpdates: [String: String] = [:]
        for (_, outcome) in results {
            for (key, value) in outcome.contextUpdates {
                mergedUpdates[key] = value
            }
        }

        let allSucceeded = results.allSatisfy { $0.1.status == .success || $0.1.status == .partialSuccess }
        let status: OutcomeStatus = allSucceeded ? .success : .partialSuccess

        return Outcome(
            status: status,
            contextUpdates: mergedUpdates,
            notes: "Parallel: \(results.count) branches completed"
        )
    }
}
