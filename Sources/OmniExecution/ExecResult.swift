public struct ExecResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public var timedOut: Bool
    public var durationMs: Int

    public init(stdout: String, stderr: String, exitCode: Int32, timedOut: Bool, durationMs: Int) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.durationMs = durationMs
    }

    public var combinedOutput: String {
        var parts: [String] = []
        if !stdout.isEmpty { parts.append(stdout) }
        if !stderr.isEmpty { parts.append(stderr) }
        return parts.joined(separator: "\n")
    }
}
