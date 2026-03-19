import Testing
@testable import OmniVFS

@Suite("PipeFS")
struct PipeFSTests {

    @Test("write then readAll returns written data")
    func writeAndReadAll() throws {
        let (reader, writer) = makePipe()
        let data: [UInt8] = [10, 20, 30, 40, 50]
        _ = try writer.write(data)
        let result = try reader.readAll()
        #expect(result == data)
    }

    @Test("incremental read returns correct chunks")
    func incrementalRead() throws {
        let (reader, writer) = makePipe()
        _ = try writer.write([1, 2, 3, 4, 5, 6])

        var buf = [UInt8](repeating: 0, count: 3)
        let n1 = try reader.read(into: &buf, count: 3)
        #expect(n1 == 3)
        #expect(Array(buf[0..<3]) == [1, 2, 3])

        let n2 = try reader.read(into: &buf, count: 3)
        #expect(n2 == 3)
        #expect(Array(buf[0..<3]) == [4, 5, 6])
    }

    @Test("read returns 0 when buffer is empty")
    func readEmpty() throws {
        let (reader, _) = makePipe()
        var buf = [UInt8](repeating: 0, count: 10)
        let n = try reader.read(into: &buf, count: 10)
        #expect(n == 0)
    }

    @Test("writer close propagates — reader sees EOF (empty readAll)")
    func closeWriter() throws {
        let (reader, writer) = makePipe()
        _ = try writer.write([1, 2])
        try writer.close()

        // Can still read buffered data
        let data = try reader.readAll()
        #expect(data == [1, 2])

        // After draining, nothing left
        let data2 = try reader.readAll()
        #expect(data2.isEmpty)
    }

    @Test("write after reader close throws isClosed")
    func writeAfterReaderClose() throws {
        let (reader, writer) = makePipe()
        try reader.close()
        #expect(throws: VFSError.self) {
            _ = try writer.write([1])
        }
    }

    @Test("stat on reader reports available bytes")
    func readerStat() throws {
        let (reader, writer) = makePipe()
        _ = try writer.write([1, 2, 3])
        let info = try reader.stat()
        #expect(info.name == "pipe")
        #expect(info.size == 3)
    }

    @Test("writer stat and read throw notSupported")
    func writerReadThrows() {
        let (_, writer) = makePipe()
        #expect(throws: VFSError.self) {
            _ = try writer.readAll()
        }
    }
}
