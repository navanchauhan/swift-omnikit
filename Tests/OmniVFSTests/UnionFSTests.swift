import Testing
@testable import OmniVFS

@Suite("UnionFS")
struct UnionFSTests {

    @Test("open returns file from first FS that has it")
    func priorityOrdering() throws {
        let fs1 = MemFS()
        try fs1.createFile("shared.txt", data: Array("from fs1".utf8))
        let fs2 = MemFS()
        try fs2.createFile("shared.txt", data: Array("from fs2".utf8))

        let union = UnionFS([fs1, fs2])
        let file = try union.open("shared.txt")
        #expect(try file.readAll() == Array("from fs1".utf8))
        try file.close()
    }

    @Test("open falls through to second FS when first lacks file")
    func fallThrough() throws {
        let fs1 = MemFS()
        let fs2 = MemFS()
        try fs2.createFile("only2.txt", data: [42])

        let union = UnionFS([fs1, fs2])
        let file = try union.open("only2.txt")
        #expect(try file.readAll() == [42])
        try file.close()
    }

    @Test("open throws notFound when no FS has the file")
    func notFound() {
        let union = UnionFS([MemFS(), MemFS()])
        #expect(throws: VFSError.self) {
            try union.open("missing.txt")
        }
    }

    @Test("readDir merges and deduplicates")
    func readDirMerge() throws {
        let fs1 = MemFS()
        try fs1.mkdir("dir")
        try fs1.createFile("dir/a.txt", data: [1])
        try fs1.createFile("dir/shared.txt", data: [10])

        let fs2 = MemFS()
        try fs2.mkdir("dir")
        try fs2.createFile("dir/b.txt", data: [2])
        try fs2.createFile("dir/shared.txt", data: [20])

        let union = UnionFS([fs1, fs2])
        let entries = try union.readDir("dir")
        let names = entries.map(\.name)
        #expect(names.contains("a.txt"))
        #expect(names.contains("b.txt"))
        #expect(names.contains("shared.txt"))
        // shared.txt appears exactly once (dedup)
        #expect(names.filter { $0 == "shared.txt" }.count == 1)
    }

    @Test("stat uses first FS priority")
    func statPriority() throws {
        let fs1 = MemFS()
        try fs1.createFile("f.txt", data: [1, 2, 3])
        let fs2 = MemFS()
        try fs2.createFile("f.txt", data: [1, 2, 3, 4, 5])

        let union = UnionFS([fs1, fs2])
        let info = try union.stat("f.txt")
        #expect(info.size == 3) // from fs1
    }
}
