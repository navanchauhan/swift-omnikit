import Foundation

/// Creates a bidirectional pipe pair for stdio.
/// Returns (reader: VFSFile, writer: VFSWritableFile).
public func makePipe(capacity: Int = 65536) -> (reader: any VFSFile, writer: any VFSWritableFile) {
    let buffer = PipeBuffer(capacity: capacity)
    let reader = PipeReader(buffer: buffer)
    let writer = PipeWriter(buffer: buffer)
    return (reader, writer)
}

/// Shared ring buffer backing a pipe.
private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UInt8]
    private var readPos: Int = 0
    private var writePos: Int = 0
    private var count: Int = 0
    private var writerClosed = false
    private var readerClosed = false

    init(capacity: Int) {
        self.storage = [UInt8](repeating: 0, count: capacity)
    }

    func write(_ data: [UInt8]) throws -> Int {
        return try lock.withLock {
            if readerClosed { throw VFSError.isClosed }
            if writerClosed { throw VFSError.isClosed }
            var written = 0
            for byte in data {
                if count >= storage.count {
                    // Grow storage (non-blocking approach).
                    storage.append(contentsOf: [UInt8](repeating: 0, count: storage.count))
                }
                storage[(readPos + count) % storage.count] = byte
                count += 1
                written += 1
            }
            return written
        }
    }

    func read(into buffer: inout [UInt8], count requestedCount: Int) -> Int {
        return lock.withLock {
            let toRead = min(requestedCount, count)
            if toRead == 0 { return 0 }
            for i in 0..<toRead {
                buffer[i] = storage[readPos % storage.count]
                readPos += 1
            }
            // Normalize readPos to prevent overflow.
            if readPos >= storage.count {
                readPos = readPos % storage.count
            }
            count -= toRead
            return toRead
        }
    }

    func readAll() -> [UInt8] {
        return lock.withLock {
            var result = [UInt8](repeating: 0, count: count)
            for i in 0..<count {
                result[i] = storage[(readPos + i) % storage.count]
            }
            readPos = (readPos + count) % storage.count
            count = 0
            return result
        }
    }

    var isEOF: Bool {
        return lock.withLock { writerClosed && count == 0 }
    }

    var availableBytes: Int {
        return lock.withLock { count }
    }

    func closeWriter() {
        lock.withLock { writerClosed = true }
    }

    func closeReader() {
        lock.withLock { readerClosed = true }
    }
}

/// Reader end of a pipe.
private final class PipeReader: @unchecked Sendable, VFSFile {
    private let buffer: PipeBuffer

    init(buffer: PipeBuffer) {
        self.buffer = buffer
    }

    func stat() throws -> VFSFileInfo {
        return VFSFileInfo(name: "pipe", size: Int64(buffer.availableBytes))
    }

    func read(into buf: inout [UInt8], count: Int) throws -> Int {
        return buffer.read(into: &buf, count: count)
    }

    func readAll() throws -> [UInt8] {
        return buffer.readAll()
    }

    func close() throws {
        buffer.closeReader()
    }
}

/// Writer end of a pipe.
private final class PipeWriter: @unchecked Sendable, VFSWritableFile {
    private let buffer: PipeBuffer

    init(buffer: PipeBuffer) {
        self.buffer = buffer
    }

    func stat() throws -> VFSFileInfo {
        return VFSFileInfo(name: "pipe", size: 0)
    }

    func read(into buf: inout [UInt8], count: Int) throws -> Int {
        throw VFSError.notSupported("cannot read from pipe writer")
    }

    func readAll() throws -> [UInt8] {
        throw VFSError.notSupported("cannot read from pipe writer")
    }

    func write(_ data: [UInt8]) throws -> Int {
        return try buffer.write(data)
    }

    func close() throws {
        buffer.closeWriter()
    }
}
