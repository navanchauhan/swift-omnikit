import Testing
@testable import OmniContainer
@testable import OmniVFS

@Suite("ContainerLifecycle")
struct ContainerLifecycleTests {

    func makeTestContainer() -> ContainerActor {
        let rootFS = MemFS()
        try! rootFS.mkdir("bin")
        try! rootFS.mkdir("tmp")
        try! rootFS.mkdir("etc")
        try! rootFS.createFile("etc/hostname", data: Array("test-container".utf8))
        let spec = ContainerSpec(imageRef: "test:local")
        return ContainerActor(config: spec, rootFS: rootFS)
    }

    @Test("container starts from created state")
    func startFromCreated() async throws {
        let container = makeTestContainer()
        let state = await container.state
        #expect(state == .created)
        try await container.start()
        let newState = await container.state
        #expect(newState == .running)
    }

    @Test("container stop from running")
    func stopFromRunning() async throws {
        let container = makeTestContainer()
        try await container.start()
        await container.stop()
        let state = await container.state
        if case .stopped = state {
            // ok
        } else {
            Issue.record("Expected .stopped, got \(state)")
        }
    }

    @Test("container destroy")
    func destroyContainer() async throws {
        let container = makeTestContainer()
        try await container.start()
        await container.destroy()
        let state = await container.state
        #expect(state == .destroyed)
    }

    @Test("double start throws")
    func doubleStartThrows() async throws {
        let container = makeTestContainer()
        try await container.start()
        await #expect(throws: ContainerError.self) {
            try await container.start()
        }
    }

    @Test("VFS operations work through container")
    func vfsOperations() async throws {
        let container = makeTestContainer()
        try await container.start()

        // Write a file into the overlay via the root CowFS
        try await container.writeFile(path: "bin/test.txt", content: "hello world")

        // Read it back
        let content = try await container.readFile(path: "bin/test.txt")
        #expect(content == "hello world")

        // Check existence
        let exists = await container.fileExists(path: "bin/test.txt")
        #expect(exists)

        // List directory
        let entries = try await container.listDirectory(path: "bin", depth: 1)
        #expect(entries.contains(where: { $0.name == "test.txt" }))
    }

    @Test("CowFS overlay captures writes without mutating base")
    func cowfsOverlay() async throws {
        let baseFS = MemFS()
        try baseFS.mkdir("data")
        try baseFS.createFile("data/original.txt", data: Array("base content".utf8))
        let spec = ContainerSpec(imageRef: "test:local")
        let container = ContainerActor(config: spec, rootFS: baseFS)
        try await container.start()

        // Write new file through container (into data/ dir which exists in base)
        try await container.writeFile(path: "data/new-file.txt", content: "overlay content")

        // Read from container works
        let content = try await container.readFile(path: "data/new-file.txt")
        #expect(content == "overlay content")

        // Original base still has the original file
        let baseFile = try baseFS.open("data/original.txt")
        let baseData = try baseFile.readAll()
        #expect(String(decoding: baseData, as: UTF8.self) == "base content")

        // Base doesn't have the new file
        #expect(throws: VFSError.self) {
            _ = try baseFS.open("data/new-file.txt")
        }
    }
}
