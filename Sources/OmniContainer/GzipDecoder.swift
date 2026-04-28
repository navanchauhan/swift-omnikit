import Foundation
import OmniVFS
import OmniCZlib

enum GzipDecoder {
    private static let chunkSize = 64 * 1024

    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard data.count <= Int(uInt.max) else {
            throw VFSError.notSupported("gzip payload exceeds zlib input limits")
        }

        return try data.withUnsafeBytes { rawInput in
            guard let inputBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                throw VFSError.notSupported("gzip payload is missing input bytes")
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(
                &stream,
                Int32(MAX_WBITS + 16),
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw VFSError.notSupported("gzip inflate init failed: \(initStatus)")
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK

            repeat {
                var chunk = Data(count: chunkSize)
                let produced = try chunk.withUnsafeMutableBytes { rawOutput in
                    guard let outputBase = rawOutput.bindMemory(to: Bytef.self).baseAddress else {
                        throw VFSError.notSupported("gzip inflate output buffer allocation failed")
                    }

                    stream.next_out = outputBase
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)

                    guard status == Z_OK || status == Z_STREAM_END else {
                        let message = stream.msg.map { String(cString: $0) } ?? "zlib status \(status)"
                        throw VFSError.notSupported("gzip inflate failed: \(message)")
                    }

                    return chunkSize - Int(stream.avail_out)
                }

                output.append(chunk.prefix(produced))
            } while status != Z_STREAM_END

            return output
        }
    }
}
