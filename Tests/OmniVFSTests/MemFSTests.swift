import Testing
@testable import OmniVFS

@Suite("MemFS")
struct MemFSTests {

    @Test("createFile and readAll round-trip")
    func createAndRead() throws {
        let fs = MemFS()
        let data: [UInt8] = [72, 101, 108, 108, 111] // "Hello"
        try fs.createFile("hello.txt", data: data)
        let file = try fs.open("hello.txt")
        let contents = try file.readAll()
        #expect(contents == data)
        try file.close()
    }

    @Test("writeFile overwrites existing file")
    func writeFileOverwrite() throws {
        let fs = MemFS()
        try fs.createFile("f.txt", data: [1, 2, 3])
        try fs.writeFile("f.txt", data: [4, 5])
        let file = try fs.open("f.txt")
        #expect(try file.readAll() == [4, 5])
        try file.close()
    }

    @Test("mkdir and readDir")
    func mkdirAndReadDir() throws {
        let fs = MemFS()
        try fs.mkdir("sub")
        try fs.createFile("sub/a.txt", data: [1])
        try fs.createFile("sub/b.txt", data: [2])
        let entries = try fs.readDir("sub")
        let names = entries.map(\.name)
        #expect(names == ["a.txt", "b.txt"])
    }

    @Test("stat returns correct info")
    func statFile() throws {
        let fs = MemFS()
        try fs.createFile("data.bin", data: [0, 1, 2, 3])
        let info = try fs.stat("data.bin")
        #expect(info.name == "data.bin")
        #expect(info.size == 4)
        #expect(info.isDir == false)
    }

    @Test("remove deletes file")
    func removeFile() throws {
        let fs = MemFS()
        try fs.createFile("gone.txt", data: [1])
        try fs.remove("gone.txt")
        #expect(throws: VFSError.self) {
            try fs.open("gone.txt")
        }
    }

    @Test("createFile rejects duplicate")
    func createDuplicate() throws {
        let fs = MemFS()
        try fs.createFile("dup.txt", data: [1])
        #expect(throws: VFSError.self) {
            try fs.createFile("dup.txt", data: [2])
        }
    }

    @Test("memory cap enforcement")
    func memoryCap() throws {
        let fs = MemFS(maxBytes: 10)
        try fs.createFile("a.txt", data: [UInt8](repeating: 0, count: 5))
        #expect(throws: VFSError.self) {
            try fs.createFile("b.txt", data: [UInt8](repeating: 0, count: 6))
        }
        // Exactly at cap should succeed
        try fs.createFile("c.txt", data: [UInt8](repeating: 0, count: 5))
    }

    @Test("concurrent access does not crash")
    func concurrentAccess() async throws {
        let fs = MemFS()
        try fs.mkdir("dir")
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    try? fs.createFile("dir/file\(i).txt", data: [UInt8(i & 0xFF)])
                }
            }
        }
        let entries = try fs.readDir("dir")
        #expect(entries.count == 50)
    }
}
