import Foundation
import Testing
@testable import OmniContainer

@Suite("GzipDecoder")
struct GzipDecoderTests {
    @Test("decompresses gzip payloads without shelling out")
    func decompressesPayload() throws {
        guard let compressed = Data(base64Encoded: "H4sIADzDvWkAA8tIzcnJV0grys9VSK/KLOACAHgtvXgQAAAA") else {
            Issue.record("Expected embedded gzip fixture to decode from base64")
            return
        }

        let decompressed = try GzipDecoder.decompress(compressed)
        #expect(String(decoding: decompressed, as: UTF8.self) == "hello from gzip\n")
    }

    @Test("empty payload returns empty data")
    func emptyPayload() throws {
        #expect(try GzipDecoder.decompress(Data()).isEmpty)
    }
}
