import Foundation

// MARK: - Transform Protocol

public protocol GraphTransform: Sendable {
    func apply(_ graph: Graph) -> Graph
}

// MARK: - Variable Expansion Transform

/// Replaces `$key` placeholders in node prompts, tool_command raw attributes,
/// and the graph label with values from graph-level raw attributes.
/// `$goal` is always available from `graph.attributes.goal`.
/// Custom variables are read from `graph.rawAttributes` (e.g. `source_ref="..."` in the DOT
/// graph block becomes `$source_ref` in prompts and tool commands).
public struct VariableExpansionTransform: GraphTransform {
    public init() {}

    public func apply(_ graph: Graph) -> Graph {
        // Build variable map: longest keys first to avoid partial replacement
        // (e.g. $target_name before $target).
        var vars: [String: String] = [:]
        if !graph.attributes.goal.isEmpty {
            vars["$goal"] = graph.attributes.goal
        }
        for (key, value) in graph.rawAttributes {
            vars["$\(key)"] = value.stringValue
        }
        guard !vars.isEmpty else { return graph }

        let sortedVars = vars.sorted { $0.key.count > $1.key.count }

        func expand(_ text: String) -> String {
            var result = text
            for (varName, varValue) in sortedVars {
                if result.contains(varName) {
                    result = result.replacingOccurrences(of: varName, with: varValue)
                }
            }
            return result
        }

        // Expand in node prompts and tool_command raw attributes
        for (_, node) in graph.nodes {
            node.prompt = expand(node.prompt)
            if let cmd = node.rawAttributes["tool_command"] {
                node.rawAttributes["tool_command"] = .string(expand(cmd.stringValue))
            }
        }

        // Expand in graph label
        graph.attributes.label = expand(graph.attributes.label)

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
