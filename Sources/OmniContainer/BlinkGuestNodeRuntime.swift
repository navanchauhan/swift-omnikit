import Foundation

public enum BlinkGuestNodeRuntime {
    private static let forcedNodeOption = "--jitless"
    private static let allowGuestJitEnv = "OMNIKIT_BLINK_ALLOW_NODE_GUEST_JIT"
    private static let forceGuestJitlessEnv = "OMNIKIT_BLINK_FORCE_NODE_GUEST_JITLESS"

    private static var shouldForceNodeJitless: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment[allowGuestJitEnv] != nil {
            return false
        }
        if environment[forceGuestJitlessEnv] != nil {
            return true
        }
        #if arch(arm64) && canImport(Darwin)
        return true
        #else
        return false
        #endif
    }

    private static func mergedNodeOptionsValue(_ existing: String?) -> String? {
        guard shouldForceNodeJitless else { return existing }
        guard let existing else { return forcedNodeOption }
        guard !existing.split(separator: " ").contains(where: { $0 == Substring(forcedNodeOption) }) else {
            return existing
        }
        guard !existing.isEmpty else { return forcedNodeOption }
        return existing + " " + forcedNodeOption
    }

    public static func mergedEnvironment(_ env: [String: String]) -> [String: String] {
        guard shouldForceNodeJitless else { return env }
        var env = env
        env["NODE_OPTIONS"] = mergedNodeOptionsValue(env["NODE_OPTIONS"])
        return env
    }

    public static func mergedEnvironmentStrings(_ env: [String]) -> [String] {
        guard shouldForceNodeJitless else { return env }

        var merged = env
        for (index, entry) in merged.enumerated() {
            guard entry.hasPrefix("NODE_OPTIONS=") else { continue }
            let value = String(entry.dropFirst("NODE_OPTIONS=".count))
            if let mergedValue = mergedNodeOptionsValue(value) {
                merged[index] = "NODE_OPTIONS=\(mergedValue)"
            }
            return merged
        }

        if let mergedValue = mergedNodeOptionsValue(nil) {
            merged.append("NODE_OPTIONS=\(mergedValue)")
        }
        return merged
    }
}
