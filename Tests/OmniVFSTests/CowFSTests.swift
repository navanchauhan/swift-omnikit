import Testing
@testable import OmniVFS

@Suite("CowFS")
struct CowFSTests {

    /// Helper: create a base MemFS with some files.
    private func makeBase() throws -> MemFS {
        let base = MemFS()
        try base.mkdir("docs")
        try base.createFile("docs/readme.md", data: Array("base readme".utf8))
        try base.createFile("root.txt", data: Array("base root".utf8))
        try base.mkdir("bin")
        try base.createFile("bin/busybox", data: Array("base busybox".utf8))
        try base.symlink(target: "busybox", link: "bin/sh")
        return base
    }

    @Test("read-through to base for unmodified files")
    func readThrough() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)
        let file = try cow.open("root.txt")
        let contents = try file.readAll()
        #expect(contents == Array("base root".utf8))
        try file.close()
    }

    @Test("write captures in overlay, base unchanged")
    func writeOverlay() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)
        try cow.writeFile("root.txt", data: Array("overlay root".utf8))

        // CowFS returns overlay version
        let cowFile = try cow.open("root.txt")
        #expect(try cowFile.readAll() == Array("overlay root".utf8))
        try cowFile.close()

        // Base still has original
        let baseFile = try base.open("root.txt")
        #expect(try baseFile.readAll() == Array("base root".utf8))
        try baseFile.close()
    }

    @Test("remove creates whiteout, hiding base entry")
    func whiteout() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)
        try cow.remove("root.txt")

        #expect(throws: VFSError.self) {
            try cow.open("root.txt")
        }

        // Base still has it
        let baseFile = try base.open("root.txt")
        #expect(try baseFile.readAll() == Array("base root".utf8))
        try baseFile.close()
    }

    @Test("readDir merges base and overlay, minus whiteouts")
    func readDirMerge() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)

        // Add a new file in overlay dir
        try cow.createFile("docs/new.txt", data: [1, 2, 3])

        // Remove a base file
        try cow.remove("docs/readme.md")

        let entries = try cow.readDir("docs")
        let names = entries.map(\.name)
        #expect(names.contains("new.txt"))
        #expect(!names.contains("readme.md"))
    }

    @Test("stat returns overlay info when present")
    func statOverlay() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)
        try cow.writeFile("root.txt", data: Array("bigger overlay data".utf8))
        let info = try cow.stat("root.txt")
        #expect(info.size == Int64("bigger overlay data".utf8.count))
    }

    @Test("createFile after whiteout re-creates entry")
    func recreateAfterWhiteout() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)
        try cow.remove("root.txt")
        try cow.createFile("root.txt", data: Array("reborn".utf8))
        let file = try cow.open("root.txt")
        #expect(try file.readAll() == Array("reborn".utf8))
        try file.close()
    }

    @Test("base symlinks resolve through the merged overlay view")
    func baseSymlinkRespectsOverlayWrites() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)

        try cow.writeFile("bin/busybox", data: Array("overlay busybox".utf8))

        let file = try cow.open("bin/sh")
        #expect(try file.readAll() == Array("overlay busybox".utf8))
        try file.close()

        let info = try cow.stat("bin/sh")
        #expect(info.isSymlink)
        #expect(info.symlinkTarget == "busybox")
    }

    @Test("rename preserves symlink nodes instead of dereferencing them")
    func renameSymlink() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)

        try cow.rename(from: "bin/sh", to: "bin/ash")

        let info = try cow.stat("bin/ash")
        #expect(info.isSymlink)
        #expect(info.symlinkTarget == "busybox")

        let file = try cow.open("bin/ash")
        #expect(try file.readAll() == Array("base busybox".utf8))
        try file.close()

        #expect(throws: VFSError.self) {
            try cow.stat("bin/sh")
        }
    }

    @Test("whiteouting a directory hides its base descendants")
    func removeDirectoryHidesDescendants() throws {
        let base = try makeBase()
        let cow = CowFS(base: base)

        try cow.remove("docs")

        #expect(throws: VFSError.self) {
            try cow.open("docs/readme.md")
        }
    }
}
