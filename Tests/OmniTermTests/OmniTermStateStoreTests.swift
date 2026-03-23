import Foundation
import Testing
@testable import OmniTermSupport

struct OmniTermStateStoreTests {
    @Test("Initialization is gated by metadata and root presence")
    func initializationState() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appending(
            path: "omniterm-state-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let statePaths = try OmniTermStateStore.preparePaths(
            for: "alpine:minirootfs",
            baseDirectoryOverride: tempDirectory.path,
            reset: false,
            fileManager: fileManager
        )

        #expect(
            !OmniTermStateStore.isInitialized(
                at: statePaths,
                imageRef: "alpine:minirootfs",
                fileManager: fileManager
            )
        )

        try fileManager.createDirectory(at: statePaths.rootDirectory, withIntermediateDirectories: true)
        try OmniTermStateStore.markInitialized(
            at: statePaths,
            imageRef: "alpine:minirootfs",
            fileManager: fileManager
        )

        #expect(
            OmniTermStateStore.isInitialized(
                at: statePaths,
                imageRef: "alpine:minirootfs",
                fileManager: fileManager
            )
        )
        #expect(
            !OmniTermStateStore.isInitialized(
                at: statePaths,
                imageRef: "ubuntu:latest",
                fileManager: fileManager
            )
        )
    }

    @Test("Reset removes stale persisted guest state")
    func resetState() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appending(
            path: "omniterm-state-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let statePaths = try OmniTermStateStore.preparePaths(
            for: "alpine:minirootfs",
            baseDirectoryOverride: tempDirectory.path,
            reset: false,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: statePaths.rootDirectory, withIntermediateDirectories: true)
        let sentinel = statePaths.rootDirectory.appending(path: "usr/local/bin/codex")
        try fileManager.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("installed".utf8).write(to: sentinel)
        try OmniTermStateStore.markInitialized(
            at: statePaths,
            imageRef: "alpine:minirootfs",
            fileManager: fileManager
        )

        _ = try OmniTermStateStore.preparePaths(
            for: "alpine:minirootfs",
            baseDirectoryOverride: tempDirectory.path,
            reset: true,
            fileManager: fileManager
        )

        #expect(!fileManager.fileExists(atPath: sentinel.path))
    }

    @Test("Warm launch cleanup only clears ephemeral directories")
    func clearsEphemeralDirectories() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appending(
            path: "omniterm-state-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let statePaths = try OmniTermStateStore.preparePaths(
            for: "alpine:minirootfs",
            baseDirectoryOverride: tempDirectory.path,
            reset: false,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: statePaths.rootDirectory, withIntermediateDirectories: true)

        let tmpFile = statePaths.rootDirectory.appending(path: "tmp/cache.txt")
        let durableFile = statePaths.rootDirectory.appending(path: "usr/local/bin/codex")
        try fileManager.createDirectory(at: tmpFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: durableFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("temp".utf8).write(to: tmpFile)
        try Data("codex".utf8).write(to: durableFile)

        try OmniTermStateStore.clearEphemeralDirectories(in: statePaths, fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: tmpFile.path))
        #expect(fileManager.fileExists(atPath: durableFile.path))
        #expect(fileManager.fileExists(atPath: statePaths.rootDirectory.appending(path: "tmp").path))
        #expect(fileManager.fileExists(atPath: statePaths.rootDirectory.appending(path: "var/tmp").path))
    }
}
