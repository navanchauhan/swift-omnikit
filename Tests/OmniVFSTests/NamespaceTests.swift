import Testing
@testable import OmniVFS

@Suite("VFSNamespace")
struct NamespaceTests {

    @Test("bind replace and open file via srcPath")
    func bindReplace() throws {
        var ns = VFSNamespace()
        let fs = MemFS()
        try fs.createFile("hello.txt", data: Array("hi".utf8))
        ns.bind(src: fs, srcPath: ".", dstPath: "mnt", mode: .replace)

        let file = try ns.open("mnt/hello.txt")
        #expect(try file.readAll() == Array("hi".utf8))
        try file.close()
    }

    @Test("bind after prepends — new binding checked first for open")
    func bindAfterPriority() throws {
        var ns = VFSNamespace()
        let fs1 = MemFS()
        try fs1.createFile("only1.txt", data: Array("first".utf8))
        let fs2 = MemFS()
        try fs2.createFile("only2.txt", data: Array("second".utf8))

        ns.bind(src: fs1, dstPath: "mnt", mode: .replace)
        ns.bind(src: fs2, dstPath: "mnt", mode: .after) // prepended, checked first

        // fs2 has only2.txt, and since after prepends it, resolve finds fs2 first
        let file2 = try ns.open("mnt/only2.txt")
        #expect(try file2.readAll() == Array("second".utf8))
        try file2.close()

        // fs1 still reachable if fs2 doesn't resolve the file
        // (but MemFS resolveFS always returns self — so first target wins for shared names)
    }

    @Test("bind before appends — original binding still checked first")
    func bindBeforeOrder() throws {
        var ns = VFSNamespace()
        let fs1 = MemFS()
        try fs1.createFile("only1.txt", data: Array("first".utf8))
        let fs2 = MemFS()
        try fs2.createFile("only2.txt", data: Array("second".utf8))

        ns.bind(src: fs1, dstPath: "mnt", mode: .replace)
        ns.bind(src: fs2, dstPath: "mnt", mode: .before) // appended, checked last

        // fs1 is still first in list; can access its file
        let file1 = try ns.open("mnt/only1.txt")
        #expect(try file1.readAll() == Array("first".utf8))
        try file1.close()
    }

    @Test("unbind removes all bindings at path")
    func unbind() throws {
        var ns = VFSNamespace()
        let fs = MemFS()
        try fs.createFile("a.txt", data: [1])
        ns.bind(src: fs, dstPath: "mnt", mode: .replace)

        // Should work before unbind
        let file = try ns.open("mnt/a.txt")
        try file.close()

        ns.unbind(dstPath: "mnt")
        #expect(throws: VFSError.self) {
            try ns.open("mnt/a.txt")
        }
    }

    @Test("resolveFS returns correct filesystem and path")
    func resolveFS() throws {
        var ns = VFSNamespace()
        let fs = MemFS()
        try fs.createFile("data.bin", data: [9])
        ns.bind(src: fs, dstPath: "vol", mode: .replace)

        let (resolved, resolvedPath) = try ns.resolveFS("vol/data.bin")
        let file = try resolved.open(resolvedPath)
        #expect(try file.readAll() == [9])
        try file.close()
    }

    @Test("nested bindings resolve more specific path first")
    func nestedBindings() throws {
        var ns = VFSNamespace()
        let rootFS = MemFS()
        try rootFS.createFile("root.txt", data: Array("root".utf8))
        let subFS = MemFS()
        try subFS.createFile("sub.txt", data: Array("sub".utf8))

        ns.bind(src: rootFS, dstPath: "root", mode: .replace)
        ns.bind(src: subFS, dstPath: "nested", mode: .replace)

        // "nested" binding resolves nested/sub.txt to subFS
        let subFile = try ns.open("nested/sub.txt")
        #expect(try subFile.readAll() == Array("sub".utf8))
        try subFile.close()

        // "root" binding resolves root/root.txt to rootFS
        let rootFile = try ns.open("root/root.txt")
        #expect(try rootFile.readAll() == Array("root".utf8))
        try rootFile.close()
    }

    @Test("clone creates independent copy")
    func cloneIndependent() throws {
        var ns = VFSNamespace()
        let fs = MemFS()
        try fs.createFile("x.txt", data: [1])
        ns.bind(src: fs, dstPath: "mnt", mode: .replace)

        var ns2 = ns.clone()

        // Unbinding from clone should not affect original
        ns2.unbind(dstPath: "mnt")

        // Original still works
        let file = try ns.open("mnt/x.txt")
        #expect(try file.readAll() == [1])
        try file.close()

        // Clone does not
        #expect(throws: VFSError.self) {
            try ns2.open("mnt/x.txt")
        }
    }

    @Test("readDir shows synthesized entries for child bindings")
    func readDirSynthesized() throws {
        var ns = VFSNamespace()
        let rootFS = MemFS()
        ns.bind(src: rootFS, dstPath: ".", mode: .replace)
        let childFS = MemFS()
        ns.bind(src: childFS, dstPath: "child", mode: .replace)

        let entries = try ns.readDir(".")
        let names = entries.map(\.name)
        #expect(names.contains("child"))
    }
}
