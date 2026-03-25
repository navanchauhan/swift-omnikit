import Foundation

public enum OmniSkillPolicy {
    private static let privilegedCapabilities: Set<String> = [
        "filesystem",
        "network",
        "secrets",
        "mcp",
        "shell",
        "worker_tools",
    ]

    public static func requiresApproval(_ manifest: OmniSkillManifest) -> Bool {
        !Set(manifest.requiredCapabilities).isDisjoint(with: privilegedCapabilities)
    }
}
