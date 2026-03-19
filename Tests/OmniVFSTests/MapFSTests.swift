import Testing
@testable import OmniVFS

@Suite("MapFS")
struct MapFSTests {

    @Test("open delegates to mapped VFS")
    func openMapped() throws {
        let inner = MemFS()
        try inner.createFile("data.bin", data: [1, 2, 3])
        let mapfs = MapFS(["stuff": inner])

        let file = try mapfs.open("stuff/data.bin")
        #expect(try file.readAll() == [1, 2, 3])
        try file.close()
    }

    @Test("open mapped root returns root of inner VFS")
    func openMappedRoot() throws {
        let inner = MemFS()
        try inner.mkdir("sub")
        let mapfs = MapFS(["mydir": inner])

        // Opening "mydir" opens the root of inner, which is a directory
        let file = try mapfs.open("mydir")
        let info = try file.stat()
        #expect(info.isDir == true)
        try file.close()
    }

    @Test("readDir at root shows mapping keys")
    func readDirRoot() throws {
        let inner1 = MemFS()
        let inner2 = MemFS()
        let mapfs = MapFS(["alpha": inner1, "beta": inner2])

        let entries = try mapfs.readDir(".")
        let names = entries.map(\.name)
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
    }

    @Test("synthesized parent directories for nested mappings")
    func synthesizedParents() throws {
        let inner = MemFS()
        try inner.createFile("x.txt", data: [99])
        let mapfs = MapFS(["a/b/c": inner])

        // "a" and "a/b" should be synthesized directories
        let rootEntries = try mapfs.readDir(".")
        #expect(rootEntries.contains { $0.name == "a" && $0.isDir })

        let aEntries = try mapfs.readDir("a")
        #expect(aEntries.contains { $0.name == "b" && $0.isDir })

        // stat on synthesized dir
        let info = try mapfs.stat("a")
        #expect(info.isDir == true)
    }

    @Test("open on non-existent path throws notFound")
    func notFound() {
        let mapfs = MapFS(["x": MemFS()])
        #expect(throws: VFSError.self) {
            try mapfs.open("missing")
        }
    }

    @Test("stat delegates through to inner VFS for sub-paths")
    func statSubPath() throws {
        let inner = MemFS()
        try inner.createFile("hello.txt", data: Array("hello".utf8))
        let mapfs = MapFS(["mount": inner])

        let info = try mapfs.stat("mount/hello.txt")
        #expect(info.size == 5)
        #expect(info.isDir == false)
    }
}
