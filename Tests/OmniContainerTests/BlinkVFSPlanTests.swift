import Foundation
import Testing
@testable import OmniContainer
import OmniVFS

@Suite("Blink VFS Plan")
struct BlinkVFSPlanTests {
    @Test("DiskFS workspace bind stays as a host mount and skips workspace snapshotting")
    func workspaceBindUsesHostMount() throws {
        let rootFS = MemFS()
        try rootFS.mkdir("etc")
        try rootFS.createFile("etc/os-release", data: Array("NAME=PlannerTest\n".utf8))

        let hostDir = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: hostDir) }

        let fileURL = hostDir.appending(path: "hello.txt")
        try Data("hello from host\n".utf8).write(to: fileURL)
        try FileManager.default.createSymbolicLink(
            atPath: hostDir.appending(path: "hello-link").path,
            withDestinationPath: "hello.txt"
        )

        let diskFS = DiskFS(root: hostDir.path)
        var namespace = VFSNamespace()
        namespace.bind(src: rootFS, dstPath: ".", mode: .replace)
        namespace.bind(src: diskFS, dstPath: "workspace", mode: .replace)

        let plan = BlinkVFSPlanner.buildLaunchPlan(namespace: namespace)

        #expect(plan.hostMounts.count == 1)
        #expect(plan.hostMounts[0] == BlinkHostMount(
            hostPath: try diskFS.mountSourcePath(),
            guestPath: "/workspace"
        ))
        #expect(plan.flatVFS.entries.contains { $0.path == "etc/os-release" })
        #expect(plan.flatVFS.entries.allSatisfy { !$0.path.localizedStandardContains("workspace/") })
    }
}
