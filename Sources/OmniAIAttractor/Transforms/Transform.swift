import Foundation

// MARK: - Transform Protocol

public protocol GraphTransform: Sendable {
    func apply(_ graph: Graph) -> Graph
}

// MARK: - Variable Expansion Transform

/// Replaces $goal in node prompts with the graph's goal attribute.
public struct VariableExpansionTransform: GraphTransform {
    public init() {}

    public func apply(_ graph: Graph) -> Graph {
        let goal = graph.attributes.goal
        for (_, node) in graph.nodes {
            if node.prompt.contains("$goal") {
                node.prompt = node.prompt.replacingOccurrences(of: "$goal", with: goal)
            }
        }
        return graph
    }
}

// MARK: - Preamble Transform

/// Synthesizes context carryover text for stages that do not use `full` fidelity.
/// This transform is applied at execution time (not at parse time) since it depends on runtime state.
/// When applied, it prepends a preamble to node prompts with relevant context information.
public struct PreambleTransform: GraphTransform {
    public let context: PipelineContext
    public let completedNodes: [String]

    public init(context: PipelineContext, completedNodes: [String]) {
        self.context = context
        self.completedNodes = completedNodes
    }

    public func apply(_ graph: Graph) -> Graph {
        let graphDefault = graph.attributes.defaultFidelity
        let goal = graph.attributes.goal

        for (_, node) in graph.nodes {
            let fidelity = ContextFidelity.resolve(
                edgeFidelity: "",
                nodeFidelity: node.fidelity,
                graphDefault: graphDefault
            )
            guard fidelity != .full else { continue }

            var preamble = ""
            if !goal.isEmpty {
                preamble += "Goal: \(goal)\n"
            }
            if !completedNodes.isEmpty {
                preamble += "Completed stages: \(completedNodes.joined(separator: ", "))\n"
            }
            let contextSnapshot = context.serializableSnapshot()
            if !contextSnapshot.isEmpty {
                let entries = contextSnapshot.sorted(by: { $0.key < $1.key })
                    .map { "  \($0.key) = \($0.value)" }
                    .joined(separator: "\n")
                preamble += "Context:\n\(entries)\n"
            }

            if !preamble.isEmpty && !node.prompt.isEmpty {
                node.prompt = preamble + "\n" + node.prompt
            }
        }

        return graph
    }
}

// MARK: - Transform Pipeline

/// Manages and applies a sequence of transforms to a graph.
/// Built-in transforms run first, followed by custom transforms in registration order.
// Safety: @unchecked Sendable — mutable state (customTransforms) is guarded by
// `lock`. The lock is released before applying transforms.
public final class TransformPipeline: @unchecked Sendable {
    private var customTransforms: [GraphTransform] = []
    private let lock = NSLock()

    public init() {}

    /// Register a custom transform to run after built-in transforms.
    public func register(_ transform: GraphTransform) {
        lock.lock()
        defer { lock.unlock() }
        customTransforms.append(transform)
    }

    /// Apply all built-in transforms followed by custom transforms.
    public func apply(to graph: Graph) -> Graph {
        lock.lock()
        let customs = customTransforms
        lock.unlock()

        var result = graph

        // Built-in transforms in defined order
        result = VariableExpansionTransform().apply(result)
        result = StylesheetTransform().apply(result)

        // Custom transforms in registration order
        for transform in customs {
            result = transform.apply(result)
        }

        return result
    }
}
